"""Write or clear the "handover ready" mark the status line shows.

The mark is dirname(transcript)/<session_id>/handover-ready holding the
handover's path, so it is session-scoped and outside the project tree. The
session is CLAUDE_CODE_SESSION_ID (required); its project directory is found as
<projects>/*/<session_id>.jsonl, where projects is CLAUDE_CONFIG_DIR or
~/.claude plus /projects, never from the caller's directory. A warning goes to
stderr when a newer transcript sits beside it (the variable may be stale after
/clear). Exit: 0 done, 2 no session id or transcript found.
"""

import argparse
import glob
import os
import sys

from .statusline import HANDOVER_MARKER

SESSION_ENV = "CLAUDE_CODE_SESSION_ID"


def default_projects():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return os.path.join(base, "projects")


def find_transcript(projects, session):
    """Path of the session's transcript, or None."""
    pattern = os.path.join(glob.escape(projects), "*", glob.escape(session) + ".jsonl")
    found = glob.glob(pattern)
    return found[0] if found else None


def newer_transcripts(transcript):
    directory = os.path.dirname(transcript)
    mine = os.path.getmtime(transcript)
    return [
        n
        for n in os.listdir(directory)
        if n.endswith(".jsonl") and os.path.getmtime(os.path.join(directory, n)) > mine
    ]


def main(argv=None, projects=None, stdout=None):
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
    session = os.environ.get(SESSION_ENV)
    if not session:
        print(f"handover-ready: {SESSION_ENV} is not set", file=sys.stderr)
        return 2
    transcript = find_transcript(projects or default_projects(), session)
    if transcript is None:
        print(f"handover-ready: no transcript for session {session}", file=sys.stderr)
        return 2
    try:
        if newer_transcripts(transcript):
            print(
                f"handover-ready: warning: a newer transcript exists beside "
                f"{session}; {SESSION_ENV} may be stale after /clear",
                file=sys.stderr,
            )
    except OSError:
        pass
    marker = os.path.join(os.path.dirname(transcript), session, HANDOVER_MARKER)
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
