# Evidence: role-model-pins (2026-11-09), Zuzia

Class: small, two commits in two repositories.

## Commits
- dev-tools `4e0ab85` feat(ai-knowledge): render drops model: from the Gemini copy of a role
  (files: bin/ai/ai-knowledge, tests/ai-sandbox/test-knowledge.sh; 15 insertions, 5 deletions)
- ~/knowledge `294c0d0` feat(roles): single-tier roles pin their model (role-model-pins)
  (files: decisions.md, roles/README.md, roles/{runner,implementer,scout,writer}.md; 17 insertions, 3 deletions)

## Regression test (tests/ai-sandbox/test-knowledge.sh, after the D10 tools: cases)
Command: `bash tests/ai-sandbox/test-knowledge.sh` (the file is not executable; run through bash)
- Red, before the change to bin/ai/ai-knowledge:
  - `not ok 24 - model key absent from the front matter of the gemini copy` (expected '0', got '1')
  - `not ok 25 - gemini copy is the claude copy minus the model line` (differ byte for byte)
  - `473 run, 2 failed`
- Green, after: `473 run, 0 failed`. `bash -n bin/ai/ai-knowledge`: syntax ok.
- Cases added: model key kept in the claude copy; absent from the gemini front matter; gemini copy equals
  claude copy minus the model line (byte for byte); a body line starting with `model:` stays in the gemini
  copy; the key is not in the antigravity or codex copies.

## Change
`drop_tools_key` became `drop_claude_keys` (regex `(tools|model)\s*:`, same front-matter-only scope); one
call site and the comment updated. Antigravity and Codex copies are built from description and body only,
so they carry no `model:`; the new test asserts it. One stale name remains in
docs/superpowers/specs/2026-11-01-context-lifecycle-rules-brief.md line 16 (a spec, left untouched).

## Checks
- shellcheck is not installed here and run-tests.sh does not call it; not run.
- Only the touched script's suite (test-knowledge.sh) was run, per the class table (the touched package's suite).

## Real-role render (scratch, not the live store)
Scratch HOME with a clone of ~/knowledge at 294c0d0; rsync is not installed in this sandbox, so the
suite's stub was put on PATH:
`PATH=$PWD/tests/ai-sandbox/stub:$PATH HOME=<scratchpad>/render/home bash bin/ai/ai-knowledge render`
(scratch dir: /tmp/claude-1000/-home-jlewandowski-dev-public-dev-tools/e8b82592-5d25-4fac-a7e9-49ce69ce2b5d/scratchpad/render)
Result:
- claude/agents/runner.md front matter: name, description, `model: haiku`, `tools: ...`
- gemini/agents/runner.md front matter: name, description only
- `grep -c '^model:'`: claude copy 1 for implementer, runner, scout, writer, 0 for planner, reviewer,
  second-reviewer; gemini copy 0 for every role
- `grep -rl '^model:'` over antigravity/ and codex/: no files

## Follow-up (2026-11-09)

Commits in ~/knowledge, main, not pushed:
- 8fbae74 fix(roles): README model example and exceptions (role-model-pins)
- 116227e feat(rules): review rounds stop at two and go to the user (review-round-limit)
- c1b8b86 feat(rules): a spec question goes to the author's slot, never to the lead (spec-author-slot)

Final texts:

roles/README.md, example front matter: `name: implementer`, its real description, `model: sonnet`. `model:` bullet adds: "second-reviewer has none either, because it never runs on Claude. A model passed per spawn overrides the pin; use it when the user's word for a stronger model applies."

rules/global.md section 5:
"Maximum 2 review→fix rounds. Every review of the same object is a round, a delta re-review included, whatever its findings. A third finding with the same root cause means redesign, not another hotfix. When a finding still blocks after the second round, the lead brings it to the user with three choices: accept it as known, redesign, or allow one more round. ..."
roles/reviewer.md, Brief diff row: "A blocking finding gets a delta re-review, which is the second and last round; lesser findings close the round." (implementer.md counts no rounds differently; no edit.)

rules/global.md, spec's author: "When no live agent holds the slot (retired, or lost at the lead's `/clear`), a fresh agent in that slot answers from the spec and the files; the lead never settles a spec gap itself." Line 283 and roles/planner.md line 9 do not contradict; unchanged.
