"""Claude Code status line: the main session's context and every live subagent's.

Prints one line: model, main context as percentage and tokens, then one token
per live subagent (label, estimated context, "~" when compacted since its last
reply), sorted by size, then "handover ready" when the session's mark exists,
cut to COLUMNS, each coloured by the thresholds below.
Never fails the line: a missing directory, a malformed file or unparsable stdin
still prints the main part. Stdlib only.

# reads-outside: Claude Code 2.1.312 status line JSON on stdin
#   (code.claude.com/docs/en/statusline.md): session_id, transcript_path,
#   model.display_name, context_window.{used_percentage, current_usage.
#   {input_tokens, cache_creation_input_tokens, cache_read_input_tokens}};
#   both null before the first reply and right after /compact.
# reads-outside: Claude Code 2.1.312 subagent transcripts under
#   dirname(transcript_path)/<session_id>/subagents/: agent-<id>.meta.json
#   {description, finished} and agent-<id>.jsonl lines {type, message.usage.
#   {input_tokens, cache_creation_input_tokens, cache_read_input_tokens}},
#   an API error or interruption as {type: "assistant", isApiErrorMessage:
#   true, message.model: "<synthetic>"} with all-zero usage,
#   and {type: "system", subtype: "compact_boundary"}.
# reads-outside: the handover mark, dirname(transcript_path)/<session_id>/
#   handover-ready, written by bin/ai/handover-ready (tools/context_statusline/
#   mark.py) for the lead's session; its presence adds the "handover ready"
#   segment. Session-scoped: /clear starts another session id, so the mark
#   stops showing by itself; a user message after the mark (transcript entries
#   {type: "user", timestamp, message.content, isMeta, isSidechain}) withdraws it.
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime

# Consumer comment: these two equal the knowledge rule's thresholds
# (~/knowledge rules/global.md, context lifecycle bullet, approved 2026-11-01):
# prepare the handover from PREPARE_TOKENS, the ceiling is CEILING_TOKENS.
PREPARE_TOKENS = 250_000
CEILING_TOKENS = 350_000

# An unfinished meta whose transcript is older than this belongs to a session
# that died mid-run; it would otherwise show as live for good.
STALE_AFTER_S = 600

LABEL_CHARS = 12
SEPARATOR = " | "
# Transcripts reach megabytes; only the tail holds the last reply. The tail
# grows when it holds no reply, which a long tool call can push out of it.
TAIL_BYTES = 64 * 1024

GREEN = "\x1b[32m"
YELLOW = "\x1b[33m"
RED = "\x1b[31m"
CYAN = "\x1b[36m"
RESET = "\x1b[0m"

# The mark's file name (also written by mark.py) and the segment it shows.
HANDOVER_MARKER = "handover-ready"
HANDOVER_SEGMENT = "handover ready"

SYNTHETIC_MODEL = "<synthetic>"
USAGE_FIELDS = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)


def colour_of(tokens):
    if tokens >= CEILING_TOKENS:
        return RED
    if tokens >= PREPARE_TOKENS:
        return YELLOW
    return GREEN


def fmt_tokens(tokens):
    return f"{tokens / 1000:.0f}k" if tokens >= 1000 else str(tokens)


def usage_tokens(usage):
    """Context estimate from a usage object, or None when a field is missing."""
    if not isinstance(usage, dict):
        return None
    try:
        return sum(int(usage[f]) for f in USAGE_FIELDS)
    except (KeyError, TypeError, ValueError):
        return None


def _tail_lines(path, size):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        end = f.tell()
        f.seek(max(0, end - size))
        data = f.read()
    return data.splitlines(), end


def last_reply(path):
    """(tokens, compacted) from the transcript's last assistant entry, or None."""
    size = TAIL_BYTES
    while True:
        lines, total = _tail_lines(path, size)
        compacted = False
        for raw in reversed(lines):
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(entry, dict):
                continue
            if (
                entry.get("type") == "system"
                and entry.get("subtype") == "compact_boundary"
            ):
                compacted = True
            elif entry.get("type") == "assistant":
                message = entry.get("message") or {}
                # An API error or an interruption is written as an assistant
                # entry with all-zero usage; the real context is the reply before.
                if (
                    entry.get("isApiErrorMessage")
                    or message.get("model") == SYNTHETIC_MODEL
                ):
                    continue
                tokens = usage_tokens(message.get("usage"))
                if tokens is not None:
                    return tokens, compacted
        if size >= total:
            return None
        size *= 16


def live_agents(subagents_dir, now):
    """[(tokens, label, compacted)] for every live subagent, largest first."""
    try:
        names = os.listdir(subagents_dir)
    except OSError:
        return []
    agents = []
    for name in names:
        if not name.endswith(".meta.json"):
            continue
        stem = name[: -len(".meta.json")]
        transcript = os.path.join(subagents_dir, stem + ".jsonl")
        try:
            with open(os.path.join(subagents_dir, name), encoding="utf-8") as f:
                meta = json.load(f)
            if not isinstance(meta, dict) or meta.get("finished") is True:
                continue
            if now - os.stat(transcript).st_mtime > STALE_AFTER_S:
                continue
            reply = last_reply(transcript)
        except (OSError, ValueError):
            continue
        if reply is None:
            continue
        label = str(meta.get("description") or stem)[:LABEL_CHARS]
        agents.append((reply[0], label, reply[1]))
    agents.sort(key=lambda a: a[0], reverse=True)
    return agents


def subagents_dir(data):
    transcript = data.get("transcript_path")
    session = data.get("session_id")
    if not isinstance(transcript, str) or not isinstance(session, str):
        return None
    return os.path.join(os.path.dirname(transcript), session, "subagents")


def _is_user_message(entry):
    """A message the user typed: not a tool result, an agent message or a subagent's."""
    if entry.get("type") != "user":
        return False
    if entry.get("isMeta") or entry.get("isSidechain"):
        return False
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, list):
        return any(
            isinstance(b, dict) and b.get("type") != "tool_result" for b in content
        )
    return isinstance(content, str)


def last_user_time(path):
    """Epoch seconds of the transcript's last user message, or None."""
    size = TAIL_BYTES
    while True:
        lines, total = _tail_lines(path, size)
        for raw in reversed(lines):
            try:
                entry = json.loads(raw)
                if isinstance(entry, dict) and _is_user_message(entry):
                    stamp = str(entry["timestamp"]).replace("Z", "+00:00")
                    return datetime.fromisoformat(stamp).timestamp()
            except (ValueError, KeyError):
                continue
        if size >= total:
            return None
        size *= 16


def handover_ready(data):
    """True when the session's mark exists and no user message came after it."""
    transcript = data.get("transcript_path")
    session = data.get("session_id")
    if not isinstance(transcript, str) or not isinstance(session, str):
        return False
    marker = os.path.join(os.path.dirname(transcript), session, HANDOVER_MARKER)
    try:
        if not os.path.isfile(marker):
            return False
        marked = os.stat(marker).st_mtime
        last_user = last_user_time(transcript)
    except OSError:
        # No readable transcript: nothing says the user came back.
        return os.path.isfile(marker)
    return last_user is None or last_user <= marked


def _paint(text, tokens, colour):
    return f"{colour_of(tokens)}{text}{RESET}" if colour else text


def _cut(pieces, columns):
    """Join (visible text, painted text) pieces within COLUMNS visible characters."""
    out, width = [], 0
    for plain, painted in pieces:
        if width + len(plain) <= columns:
            out.append(painted)
            width += len(plain)
            continue
        room = columns - width
        if room > 0:
            cut = plain[:room]
            # Keep the escapes of a painted piece around its cut text.
            out.append(painted.replace(plain, cut, 1) if painted != plain else cut)
        break
    return "".join(out)


def render(data, *, columns, colour, now):
    model = data.get("model") if isinstance(data.get("model"), dict) else {}
    name = str(model.get("display_name") or model.get("id") or "?")
    window = (
        data.get("context_window")
        if isinstance(data.get("context_window"), dict)
        else {}
    )
    tokens = usage_tokens(window.get("current_usage"))
    percentage = window.get("used_percentage")
    if tokens is None or not isinstance(percentage, (int, float)):
        main_text, main_painted = "--", "--"
    else:
        main_text = f"{percentage:.0f}% {fmt_tokens(tokens)}"
        main_painted = _paint(main_text, tokens, colour)
    pieces = [(name + " ", name + " "), (main_text, main_painted)]

    directory = subagents_dir(data)
    agents = live_agents(directory, now) if directory else []
    for i, (agent_tokens, label, compacted) in enumerate(agents):
        pieces.append((SEPARATOR, SEPARATOR) if i == 0 else (" ", " "))
        text = f"{label}:{'~' if compacted else ''}{fmt_tokens(agent_tokens)}"
        pieces.append((text, _paint(text, agent_tokens, colour)))
    if handover_ready(data):
        painted = f"{CYAN}{HANDOVER_SEGMENT}{RESET}" if colour else HANDOVER_SEGMENT
        pieces.append((SEPARATOR, SEPARATOR))
        pieces.append((HANDOVER_SEGMENT, painted))
    return _cut(pieces, columns)


def main(argv=None, stdin=None, stdout=None):
    parser = argparse.ArgumentParser(
        prog="context-statusline",
        description="Claude Code status line: main context and live subagents.",
    )
    parser.add_argument(
        "--plain", action="store_true", help="no ANSI colours (also: NO_COLOR set)"
    )
    args = parser.parse_args(argv)
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    try:
        data = json.load(stdin)
    except ValueError:
        data = {}
    if not isinstance(data, dict):
        data = {}
    try:
        columns = int(os.environ.get("COLUMNS", ""))
    except ValueError:
        columns = 200
    colour = not args.plain and not os.environ.get("NO_COLOR")
    print(render(data, columns=columns, colour=colour, now=time.time()), file=stdout)
    return 0
