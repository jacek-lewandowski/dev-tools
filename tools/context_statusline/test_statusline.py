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

from tools.context_statusline.statusline import (
    CEILING_TOKENS,
    GREEN,
    PREPARE_TOKENS,
    RED,
    RESET,
    STALE_AFTER_S,
    YELLOW,
    main,
    render,
)

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
STALE_AGENT = "agent-d4stale000000000"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
MAIN_PART = "Fable 5.1 42% 84k"
FULL_LINE = MAIN_PART + " | Write superv:~375k Land the con:138k"


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


if __name__ == "__main__":
    unittest.main()
