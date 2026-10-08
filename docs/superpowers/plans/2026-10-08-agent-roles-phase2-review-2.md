# Phase 2 review (code T1 + drafts T2-T4), round 1

Date: 2026-10-08. Verdict: **blocked** (3 important, all in the role drafts). T1, readme.patch and
the global.md patches have no blocking findings. test-knowledge.sh 387/0; the T1 test fails against
HEAD's ai-knowledge (cases 18, 19), so it is a real regression test. All patches pass
`apply --check` and apply in either order. I2 grep empty; tools: lines match the plan.

## Important

1. **Native reports lose C4 envelope fields** (runner.md, writer.md "How to hand the report over" /
   "What to return"; also scout.md). They list only ran_on, status, summary, open_questions,
   requests, body and say "overwrite that report with your final one"; the native report then lacks
   schema, route, session, usage (no post-processing on the native path) and breaks C4/I8.
   Resolution: keep schema, route, session, usage from the pending report unchanged (session and
   usage stay null) and replace only the listed fields; for the scout the lead merges them.
2. **The writer cannot follow its own check rules on its main route** (writer.md "Check", "Limits"
   extract: bullet, status). It says "run it yourself", "never skip the check", and done requires
   "the check passed"; but the writer routes external by default, where it cannot run commands, C4
   keeps check.exit_code null and D14 has the lead run check: and extract:. Resolution: running
   check:/extract: is conditional on being able to run commands; otherwise exit_code and output stay
   null and done means "every output written, check left to the lead"; extract: output then already
   arrives among the inputs.
3. **Scout hand-over contradicts D5/C5 and its own tools** (scout.md "How to hand the report over",
   ran_on). (a) "If you can write a file ... overwrite the report" contradicts "You change no files"
   and D5/C5 step 2 (the lead writes the scout's report). (b) A native scout with WebSearch, WebFetch
   cannot read the pending report or the brief C5 step 1 hands it as a path; the T8 smoke run would
   produce a wrong ran_on (I8). Resolution: the scout always returns the JSON as its final message
   and leaves ran_on to the lead, who copies it from the pending report when writing the file; the
   question goes inline in the prompt. Spec C5 step 1 and plan T8 step 3 need matching changes.

## Lesser

- scout.md: also forbid putting file content into a search query (D24 names search as the
  remaining outward channel).
- scout.md, writer.md, second-reviewer.md: do not ask for a project fact under open_questions (D25);
  use requests or state the assumption.
- writer.md: the Polish rules can contradict a brief's gender-neutral/addressee keys; state that the
  style block wins where it sets a key; say "the reader", not "the user".
- ran_on: writer.md says copy from the pending report even on external runs (none named);
  scout.md/second-reviewer.md ask the model to state its own tool and model (unreliable); let the
  wrapper or the lead set it.
- writer.md does not say it may read the project files it is given (D20); the others do.
- README intro still says every agent has rules/global.md "on top"; false for external runs (I7).
- second-reviewer.md: "a mechanical change that arrives in its own commit with its script" assumes
  history the external reviewer cannot see (HEAD plus uncommitted, log without patches).
- T1 test: `$(...)` comparisons strip trailing newlines; compare with `cmp` against a filtered file.
- global-d9-milestone-suites.patch leaves a ragged short line; reflow it.
