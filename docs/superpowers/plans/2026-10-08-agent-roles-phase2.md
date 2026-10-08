# Phase 2 plan: roles and rules in the knowledge repository

Date: 2026-10-08. Phase planner, from the spec and the phase 2 brief.
Spec: [2026-10-08-agent-roles-design.md](../specs/2026-10-08-agent-roles-design.md) (revision 6).
Brief: [2026-10-08-agent-roles-phase2-brief.md](2026-10-08-agent-roles-phase2-brief.md).
This plan details the approach only; **no spec change**. Invariants I2, I7, I10, I11 and decisions D4, D8-D11, D13, D18, D19, D25 apply and are not restated.

## Baseline (run here, 2026-10-08)

`bash tests/ai-sandbox/run-tests.sh`: all suites green except `test-display.sh` case 1 (display number 118 vs 119) and `test-tools.sh` case 30 (`~/.sdkman` on `PATH`). Both are environmental and predate this phase; they may stay. `test-knowledge.sh`: 381 run, 0 failed. The I2 grep on `~/knowledge/roles/*.md` is empty today.

## Verification of the brief against the tree

- `cmd_render` (embedded Python in `bin/ai/ai-knowledge`) writes the same `text` to `claude/agents` and `gemini/agents`; `frontmatter()` parses only flat `key: value` lines. Verified.
- `roles/README.md` is skipped by the render; its example still has `model: inherit`. `bin/ai/knowledge-seed/roles/README.md` is an identical copy and will drift (out of scope, brief: leave unchanged).
- `~/knowledge` is on `main`; `.git/hooks/pre-commit` allows integrator commits on `main`. Existing roles carry no `tools:` key, so the test needs a fixture role.
- Discrepancy recorded: the spec's phase 2 name search covers `~/knowledge/roles/`; `README.md` documents per-tool rendering and must name the tools, so the I2 check excludes it (brief).

## Order and ownership

Drafts live outside `~/knowledge`, in `docs/superpowers/plans/2026-10-08-agent-roles-phase2-drafts/` (untracked, never committed): new role files as plain files, `README` and `global.md` edits as one patch file per change against the current tree. Nothing touches `~/knowledge` until T6.

T1 (dev-tools) commits first. T2-T4 draft only. T5 is the A12 check, T6 the approval gate and sequential commits. One implementer for T1, one for T2-T4 and for any redraft; the lead runs T5-T8. Nothing is pushed.

## T1. Render: drop `tools:` from the Gemini copy (D10)

- Files: `bin/ai/ai-knowledge` (`cmd_render`), `tests/ai-sandbox/test-knowledge.sh`.
- Behaviour: for `gemini/agents/<name>.md`, remove the `tools:` line from the front matter only (a body line that starts with `tools:` stays). The Claude copy, Antigravity and Codex outputs stay byte-identical.
- Test first: extend `test-knowledge.sh` after the render assertions. Put a fixture role with `tools: Read, Grep` into the test's fixture checkout (the temporary `$AI_KNOWLEDGE_ROOT/main`, not the real `~/knowledge`), run `knowledge render`, assert the key is in `claude/agents`, absent from `gemini/agents`, that the rest of the Gemini file equals the Claude file minus that line, and that `planner.md` (no key) is unchanged in both.
- Run: `bash tests/ai-sandbox/test-knowledge.sh`.
- Acceptance: green, all 381 earlier cases unchanged. Commit `feat(ai-knowledge): ...` in dev-tools, before any host sync.

## T2. Delegable role files (design work)

- Files (new, in the drafts directory): `roles/{scout,runner,writer,second-reviewer}.md`, to be copied into `~/knowledge/roles/` at T7.
- Front matter flat: `name` equals the file name and the C1 role; `description` one line; `tools:` per the table; no `model:`.
- The implementer states, before drafting, how it keeps each body usable both as a native subagent prompt and as the start of a non-Claude prompt (I7). Each body:
  - states its I10 limits and the C4 envelope fields it sets (`ran_on`, `status`, `summary`, `open_questions`, `requests`, `body`) plus its body fields, spelled as in C4;
  - says the agent may read the project files it is given; that typed `requests` are used only when the prompt offers them; that unanswered questions go under `open_questions` with the blocking mark (D18); that for a native run it copies `ran_on` from the pending report and overwrites that report (C5). It never says "no writes, no commands" (the wrapper's lines carry that);
  - restates what it needs from `global.md` (I7) and names no tool, CLI, vendor or model.
- Role specifics are those of the brief's "What each role file carries". Additionally the runner says it is continued per milestone (D13), and the writer says it never reviews its own translation and names no checker.
- `tools:` (brief table, adjusted): scout `WebSearch, WebFetch`; runner `Bash, Read, Grep, Glob, Write` (Write only for the report and logs under the delegation directory; "never edits tracked files" is prose, since `tools:` cannot scope it); writer `Read, Grep, Glob, Write, Edit, Bash` (Bash for `check:` and `extract:`); second-reviewer no key. No adjustment from the brief.
- Test: the I2 check, run on the drafts (`grep -n -i -E '^model:|\b(claude|agy|gemini|codex|opus|sonnet|haiku)\b' <drafts>/roles/*.md`), empty; and `grep -n '^tools:' <drafts>/roles/*.md` matches the table, with none in `second-reviewer.md`.
- Acceptance: both greps as stated; every C4 field name in a role text appears in C4 (checked by a second grep of the spec's field list).

## T3. `roles/README.md`

- Draft as a patch file against the current README: remove `model: inherit` from the example; add that `model:` is never used and the model comes from the environment's routing table; add that `tools:` reaches only Claude Code and the Gemini copy drops it; fix the Gemini row of the table ("verbatim" becomes "without `tools:`").
- Test: grep for `model:` shows only the "never used" sentence. Acceptance: diff reads correctly.

## T4. `rules/global.md` (four patch files, tool-neutral, no file or command names)

Each edit is its own patch against the current `global.md`, touching its own sentences, so they apply in any order.

1. D4, §2 Decomposition: tier sentence stays as the default; add that an environment's routing table overrides it. Add the runner on the cheapest tier and the scout and writer on the cheaper tier, so that the table's Claude rows equal the defaults (D4); flag this clause in the diff, it is the one addition beyond the brief.
2. D9, §2 "The lead only stitches": the lead runs the commits, hands milestone suites to the runner and reads its verdict.
3. D13, §2 "Agent lifetimes": four entries as in D13, plus that a writer's translation is reviewed by a different agent.
4. D8, §2 and §5: the second reviewer is optional, used for design-work tasks and contract changes only; its findings belong to the reviewer's round, so the two-round limit is counted once.
- Test: each patch passes `git apply --check` on the current tree and touches only its place. Acceptance: shown at T6.

## T5. A12 check, before anything is committed (lead runs it)

Goal: prove a `tools:` list limits a native subagent before the roles are published.
- Define a throwaway inline subagent on the cheapest model, for example `claude -p --model haiku --agents '{"probe":{"description":"probe","prompt":"Try to read /etc/hostname with Read, then run `echo hi` with Bash, and report what each call returned.","tools":["WebSearch","WebFetch"]}}' "Use the probe agent."`. If the flag form differs in the installed version, use the equivalent inline or file definition and record it.
- Record the exact command and the output lines in the phase report. Pass: both Read and Bash are refused or absent. Fail or inconclusive: repeat once with a changed prompt, then treat as fail.
- Fallback on fail: stop. The scout and runner limits would be prose only, so the plan returns a spec change to the user (I10 wording and the A12 row) and the phase does not close. T6-T8 do not run.

## T6. Approval gate and sequential commits to `~/knowledge` `main`

Per I11 and the integrator rules, one change at a time, in this order: (a) the four role files, (b) README, (c) D4, (d) D9, (e) D13, (f) D8. The planner's grouping; the user may split (a) at the gate.
For each change:
1. The lead shows the user its draft as a diff (`git diff --no-index` or the patch file); for (c) it calls out the tier clause, which adds a third tier name ("cheapest") beyond the brief.
2. On approval, the implementer applies it to `~/knowledge` (`git apply` or copying the files), writes the `decisions.md` entry for this change only, newest first, in the file's format (`- 2026-10-DD <slug> integrated`, then `<target>: <why>`, "agreed with the user in the agent-roles spec", citing the D-item), and the lead commits it (`feat(roles): ...` or `feat(rules): ...`). The hook stays on; no push. Slugs: `agent-roles-roles`, `agent-roles-readme`, `agent-roles-tiers`, `agent-roles-milestone-suites`, `agent-roles-lifetimes`, `agent-roles-second-reviewer`.
3. An edited draft: the user's wording replaces the draft, the patch is regenerated, and it is shown again before the commit. A rejected draft: nothing is applied, the remaining changes continue, and the phase report lists it as dropped with the user's reason; a later patch still applies because patches touch disjoint places. If one is rejected that a later phase needs, the lead returns it to the user as a spec question. Maximum two redraft rounds per change (global §5).
Acceptance: `git -C ~/knowledge status` clean after each commit, `git log` shows one commit per approved change, branch ahead of origin.

## T7. Phase test run (lead)

The I2 grep (README excluded) on `~/knowledge/roles`, `bash tests/ai-sandbox/test-knowledge.sh`, then `bash tests/ai-sandbox/run-tests.sh`; failures equal the baseline. A marker search finds none of the phase.

## T8. Host step (lead; one batched request, ends the phase)

1. `ai-knowledge sync --all` on the host, after T1 is committed.
2. In this sandbox: `ls ~/.claude/agents` lists scout, runner, writer, second-reviewer; `grep -c '^tools:' ~/.gemini/agents/scout.md` prints `0`.
3. Native smoke runs in a fresh session. No wrapper exists yet, so the lead gives each agent an ad-hoc report path, `.ai-delegate/smoke-<role>.report.json`, with a hand-written `pending` report there naming a Claude model. Scout: a factual question, and a prompt that also asks it to read a local file and run a command, both expected refused (A12 evidence again). Runner: run `bash tests/ai-sandbox/test-helpers.sh`. Writer: translate a two-line note listed in `outputs`, with a `check:` of `diff`. The user pastes the three report paths' status fields.

## Assumptions

| # | Assumption | Status |
|---|---|---|
| A12 | `tools:` limits a Claude Code subagent's tools | inferred; checked at T5 before any commit; fail means stop and a spec change |
| A15 | the render copies roles verbatim for Claude and Gemini | verified (`cmd_render`; T1 test covers the change) |
| P1 | A subagent without a `tools:` key (second-reviewer) inherits every tool if spawned natively | inferred; **accepted residual** (D8): the only guard is its description plus the lead's C1 rule that it is never spawned natively |
| P2 | `~/knowledge` is the integrator checkout (main, role `integrator`, hook allows main) | verified by the plan review |

Unverified: A12 (until T5), P1 (accepted). Deferred list: entries 1 and 2 are kept for a later spec change and touch nothing here; none folded or dropped.
