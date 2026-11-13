Task: 2026-11-13-gemini-effort-key
Class: small

# Gemini copies drop the effort: key

Red run (test added, fix not applied), `bash tests/ai-sandbox/test-knowledge.sh`:
```
ok 29 - effort key kept in the claude copy
not ok 30 - effort key absent from the front matter of the gemini copy
not ok 31 - gemini copy is the claude copy minus the effort line
ok 32 - a body line starting with effort: stays in the gemini copy
477 run, 2 failed
```

Green run after the fix (same command, run under the suite lock): `477 run, 0 failed`.

Diff stat (code, test and README; this file excluded):
```
 bin/ai/ai-knowledge                   | 6 +++---
 bin/ai/knowledge-seed/roles/README.md | 7 ++++---
 tests/ai-sandbox/test-knowledge.sh    | 8 ++++++++
 3 files changed, 15 insertions(+), 6 deletions(-)
```
Changed: regex in `drop_claude_keys`, its call-site comment, the seed roles README (key list and the Gemini row, which still said "verbatim"). The project has no further checks beyond the ai-sandbox test scripts; only the touched one (test-knowledge.sh) was run.
