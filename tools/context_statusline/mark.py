"""Write or clear the "handover ready" mark the status line shows.

The mark is dirname(transcript)/<session_id>/handover-ready holding the
handover's path, so it is session-scoped and outside the project tree. The
session is CLAUDE_CODE_SESSION_ID when set, else the newest transcript in the
project's Claude directory (CLAUDE_CONFIG_DIR or ~/.claude, projects/<cwd with
every non-alphanumeric character as "-">). Exit: 0 done, 2 no session found.
"""

import argparse
import os
import re
import sys

from .statusline import HANDOVER_MARKER


def default_projects():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return os.path.join(base, "projects")


def find_session(projects, cwd):
    """(transcript directory, session id) or None."""
    directory = os.path.join(projects, re.sub(r"[^A-Za-z0-9]", "-", cwd))
    session = os.environ.get("CLAUDE_CODE_SESSION_ID")
    if session:
        return directory, session
    try:
        transcripts = [
            os.path.join(directory, n)
            for n in os.listdir(directory)
            if n.endswith(".jsonl")
        ]
        newest = max(transcripts, key=os.path.getmtime)
    except (OSError, ValueError):
        return None
    return directory, os.path.basename(newest)[: -len(".jsonl")]


def main(argv=None, projects=None, cwd=None, stdout=None):
    parser = argparse.ArgumentParser(
        prog="handover-ready",
        description="Mark this session's handover ready for the status line.",
    )
    parser.add_argument("handover", nargs="?", help="path of the handover file")
    parser.add_argument("--clear", action="store_true", help="remove the mark")
    args = parser.parse_args(argv)
    if not args.clear and not args.handover:
        parser.error("a handover path or --clear is required")
    stdout = stdout or sys.stdout
    found = find_session(projects or default_projects(), cwd or os.getcwd())
    if found is None:
        print("handover-ready: no session found", file=sys.stderr)
        return 2
    directory, session = found
    marker = os.path.join(directory, session, HANDOVER_MARKER)
    if args.clear:
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
        print(f"cleared {marker}", file=stdout)
        return 0
    os.makedirs(os.path.dirname(marker), exist_ok=True)
    with open(marker, "w", encoding="utf-8") as f:
        f.write(args.handover + "\n")
    print(f"marked {marker}", file=stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
