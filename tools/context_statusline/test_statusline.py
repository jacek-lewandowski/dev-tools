"""Unit tests on the fixture stdin JSON and the fixture subagents directory.

Run from the repository root: python3 -m unittest tools.context_statusline.test_statusline -v
"""

import io
import json
import os
import re
import shutil
import tempfile
import time
import unittest
from unittest import mock

from tools.context_statusline import mark
from tools.context_statusline.statusline import (
    CEILING_TOKENS,
    GREEN,
    HANDOVER_MARKER,
    HANDOVER_SEGMENT,
    PREPARE_TOKENS,
    RED,
    RESET,
    STALE_AFTER_S,
    TAIL_BYTES,
    YELLOW,
    main,
    render,
)

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
STALE_AGENT = "agent-d4stale000000000"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
MAIN_PART = "Fable 5.1 42% 84k"
FULL_LINE = MAIN_PART + " | Write superv:~375k Land the con:138k"
SEGMENT_TAIL = " | handover ready"


def visible(line):
    return ANSI.sub("", line)


class StatuslineTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.now = time.time()

    def stdin(self, name="stdin.json"):
        with open(os.path.join(FIXTURES, name), encoding="utf-8") as f:
            data = json.load(f)
        data["transcript_path"] = os.path.join(self.tmp, data["session_id"] + ".jsonl")
        return data

    def session_dir(self, data):
        """Copy the fixture subagents beside the transcript; git keeps no mtimes,
        so the fresh ones are touched now and the stale one aged past the bound."""
        dest = os.path.join(self.tmp, data["session_id"], "subagents")
        shutil.copytree(os.path.join(FIXTURES, "subagents"), dest)
        for name in os.listdir(dest):
            age = STALE_AFTER_S + 1 if name.startswith(STALE_AGENT) else 0
            os.utime(os.path.join(dest, name), (self.now - age, self.now - age))
        return dest

    def with_usage(self, tokens):
        data = self.stdin()
        data["context_window"]["current_usage"] = {
            "input_tokens": tokens,
            "output_tokens": 1,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
        }
        data["context_window"]["used_percentage"] = 100.0 * tokens / 200000
        return data

    def run_main(self, data, argv=(), env=None):
        out = io.StringIO()
        with mock.patch.dict(os.environ, env or {}, clear=False):
            for key in ("NO_COLOR", "COLUMNS"):
                if key not in (env or {}):
                    os.environ.pop(key, None)
            rc = main(list(argv), stdin=io.StringIO(json.dumps(data)), stdout=out)
        self.assertEqual(rc, 0)
        return out.getvalue().rstrip("\n")

    # --- main part -------------------------------------------------------

    def test_main_part_prints_model_percentage_and_tokens(self):
        line = render(self.stdin(), columns=200, colour=False, now=self.now)
        self.assertEqual(line, MAIN_PART)

    def test_null_usage_prints_dashes(self):
        line = render(
            self.stdin("stdin-null.json"), columns=200, colour=False, now=self.now
        )
        self.assertEqual(line, "Fable 5.1 --")

    # --- subagents -------------------------------------------------------

    def test_live_agents_sorted_by_size_finished_and_stale_absent(self):
        data = self.stdin()
        self.session_dir(data)
        line = render(data, columns=200, colour=False, now=self.now)
        self.assertEqual(line, FULL_LINE)

    def test_missing_subagents_dir_prints_main_part(self):
        line = render(self.stdin(), columns=200, colour=False, now=self.now)
        self.assertEqual(line, MAIN_PART)

    def test_malformed_transcript_prints_main_part(self):
        data = self.stdin()
        dest = os.path.join(self.tmp, data["session_id"], "subagents")
        os.makedirs(dest)
        with open(
            os.path.join(dest, "agent-bad.meta.json"), "w", encoding="utf-8"
        ) as f:
            f.write('{"description": "Broken')
        with open(os.path.join(dest, "agent-bad.jsonl"), "w", encoding="utf-8") as f:
            f.write('{"type":"assistant","message":{"usage":{"input_tokens":1,')
        with open(
            os.path.join(dest, "agent-empty.meta.json"), "w", encoding="utf-8"
        ) as f:
            f.write('{"description": "No transcript yet"}')
        line = render(data, columns=200, colour=False, now=self.now)
        self.assertEqual(line, MAIN_PART)

    def write_agent(self, data, stem, lines):
        dest = os.path.join(self.tmp, data["session_id"], "subagents")
        os.makedirs(dest, exist_ok=True)
        with open(os.path.join(dest, stem + ".meta.json"), "w", encoding="utf-8") as f:
            f.write('{"description": "Single agent"}')
        with open(os.path.join(dest, stem + ".jsonl"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines))

    def test_synthetic_last_entry_keeps_the_real_estimate(self):
        data = self.stdin()
        reply = {
            "type": "assistant",
            "message": {
                "model": "claude-fable-5-1",
                "usage": {
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 200,
                    "cache_read_input_tokens": 300000,
                    "output_tokens": 5,
                },
            },
        }
        synthetic = {
            "type": "assistant",
            "isApiErrorMessage": True,
            "message": {
                "model": "<synthetic>",
                "usage": {
                    "input_tokens": 0,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                    "output_tokens": 0,
                },
            },
        }
        self.write_agent(
            data, "agent-synthetic", [json.dumps(reply), json.dumps(synthetic)]
        )
        line = render(data, columns=200, colour=False, now=self.now)
        self.assertEqual(line, MAIN_PART + " | Single agent:300k")

    def test_reply_beyond_the_tail_and_a_torn_last_line(self):
        data = self.stdin()
        reply = {
            "type": "assistant",
            "message": {
                "model": "claude-fable-5-1",
                "usage": {
                    "input_tokens": 3,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 260000,
                    "output_tokens": 5,
                },
            },
        }
        result = {"type": "user", "message": {"role": "user", "content": "x" * 1000}}
        lines = [json.dumps(reply)] + [json.dumps(result)] * (2 * TAIL_BYTES // 1000)
        lines.append('{"type":"user","message":{"role":"user","con')
        self.write_agent(data, "agent-long", lines)
        self.assertGreater(
            os.path.getsize(
                os.path.join(
                    self.tmp, data["session_id"], "subagents", "agent-long.jsonl"
                )
            ),
            TAIL_BYTES,
        )
        line = render(data, columns=200, colour=False, now=self.now)
        self.assertEqual(line, MAIN_PART + " | Single agent:260k")

    # --- colours ---------------------------------------------------------

    def test_thresholds_colour_the_main_part(self):
        cases = [
            (PREPARE_TOKENS - 1, GREEN, "125% 250k"),
            (PREPARE_TOKENS, YELLOW, "125% 250k"),
            (CEILING_TOKENS, RED, "175% 350k"),
        ]
        for tokens, escape, text in cases:
            line = render(
                self.with_usage(tokens), columns=200, colour=True, now=self.now
            )
            self.assertEqual(line, f"Fable 5.1 {escape}{text}{RESET}", tokens)

    def test_agent_tokens_are_coloured_by_the_same_thresholds(self):
        data = self.stdin()
        self.session_dir(data)
        line = render(data, columns=200, colour=True, now=self.now)
        self.assertIn(f"{RED}Write superv:~375k{RESET}", line)
        self.assertIn(f"{GREEN}Land the con:138k{RESET}", line)
        self.assertEqual(visible(line), FULL_LINE)

    def test_plain_flag_and_no_color_drop_escapes(self):
        data = self.stdin()
        self.session_dir(data)
        self.assertIn("\x1b[", self.run_main(data))
        self.assertEqual(self.run_main(data, argv=["--plain"]), FULL_LINE)
        self.assertEqual(self.run_main(data, env={"NO_COLOR": "1"}), FULL_LINE)
        self.assertIn("\x1b[", self.run_main(data, env={"NO_COLOR": ""}))

    # --- width -----------------------------------------------------------

    def test_columns_cuts_visible_characters(self):
        data = self.stdin()
        self.session_dir(data)
        plain = self.run_main(data, argv=["--plain"], env={"COLUMNS": "40"})
        self.assertEqual(plain, FULL_LINE[:40])
        coloured = self.run_main(data, env={"COLUMNS": "40"})
        self.assertEqual(visible(coloured), FULL_LINE[:40])
        self.assertTrue(coloured.endswith(RESET))

    def test_unparsable_stdin_prints_a_line(self):
        out = io.StringIO()
        rc = main(["--plain"], stdin=io.StringIO("not json"), stdout=out)
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), "? --\n")

    # --- handover-ready mark ---------------------------------------------

    def write_marker(self, data, text="/tmp/handover.md"):
        directory = os.path.join(self.tmp, data["session_id"])
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, HANDOVER_MARKER), "w") as f:
            f.write(text)

    def test_marker_adds_a_distinct_segment_last(self):
        data = self.stdin()
        self.session_dir(data)
        self.write_marker(data)
        line = render(data, columns=200, colour=True, now=self.now)
        self.assertEqual(visible(line), FULL_LINE + SEGMENT_TAIL)
        self.assertIn(HANDOVER_SEGMENT, line)
        self.assertNotIn(f"{GREEN}{HANDOVER_SEGMENT}", line)

    def test_marker_without_agents_and_without_marker(self):
        data = self.stdin()
        self.assertEqual(
            render(data, columns=200, colour=False, now=self.now), MAIN_PART
        )
        self.write_marker(data)
        self.assertEqual(
            render(data, columns=200, colour=False, now=self.now),
            MAIN_PART + SEGMENT_TAIL,
        )

    def test_marker_of_another_session_is_not_shown(self):
        data = self.stdin()
        self.write_marker({"session_id": "other-session"})
        self.assertEqual(
            render(data, columns=200, colour=False, now=self.now), MAIN_PART
        )

    def test_marker_never_fails_the_line(self):
        data = self.stdin()
        data["transcript_path"] = None
        self.assertEqual(
            render(data, columns=200, colour=False, now=self.now), MAIN_PART
        )
        data = self.stdin()
        # a directory in place of the file is not a mark
        os.makedirs(os.path.join(self.tmp, data["session_id"], HANDOVER_MARKER))
        self.assertEqual(
            render(data, columns=200, colour=False, now=self.now), MAIN_PART
        )


class MarkTest(unittest.TestCase):
    """The helper writes the mark the status line reads, for the right session."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.projects = os.path.join(self.tmp, "projects")
        self.cwd = "/work/my.project"
        self.slug = os.path.join(self.projects, "-work-my-project")
        os.makedirs(self.slug)

    def transcript(self, session, age):
        path = os.path.join(self.slug, session + ".jsonl")
        open(path, "w").close()
        t = time.time() - age
        os.utime(path, (t, t))
        return path

    def run_mark(self, argv=(), env=None):
        out = io.StringIO()
        with mock.patch.dict(os.environ, env or {}, clear=False):
            os.environ.pop("CLAUDE_CODE_SESSION_ID", None)
            os.environ.update(env or {})
            rc = mark.main(list(argv), projects=self.projects, cwd=self.cwd, stdout=out)
        return rc, out.getvalue()

    def marker(self, session):
        return os.path.join(self.slug, session, HANDOVER_MARKER)

    def test_session_from_environment_wins(self):
        self.transcript("older", 100)
        self.transcript("newer", 1)
        rc, _ = self.run_mark(["/h.md"], env={"CLAUDE_CODE_SESSION_ID": "older"})
        self.assertEqual(rc, 0)
        with open(self.marker("older")) as f:
            self.assertEqual(f.read(), "/h.md\n")
        self.assertFalse(os.path.exists(self.marker("newer")))

    def test_without_environment_the_newest_transcript_is_used(self):
        self.transcript("older", 100)
        self.transcript("newer", 1)
        rc, _ = self.run_mark(["/h.md"])
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.isfile(self.marker("newer")))
        self.assertFalse(os.path.exists(self.marker("older")))

    def test_clear_removes_the_mark_and_tolerates_none(self):
        self.transcript("s1", 1)
        self.run_mark(["/h.md"])
        rc, _ = self.run_mark(["--clear"])
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(self.marker("s1")))
        self.assertEqual(self.run_mark(["--clear"])[0], 0)

    def test_no_session_found_exits_nonzero(self):
        shutil.rmtree(self.slug)
        rc, _ = self.run_mark(["/h.md"])
        self.assertEqual(rc, 2)

    def test_written_mark_is_what_the_status_line_reads(self):
        path = self.transcript("s1", 1)
        self.run_mark(["/h.md"])
        data = {"session_id": "s1", "transcript_path": path}
        line = render(data, columns=200, colour=False, now=time.time())
        self.assertTrue(line.endswith(SEGMENT_TAIL), line)


if __name__ == "__main__":
    unittest.main()
