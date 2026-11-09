# Review: 2026-11-09-static-trace-tool (Fiona, reviewer 1)

Object: small diff, `~/knowledge` a093800 (rules/global.md §4, decisions.md).
Evidence: `docs/superpowers/evidence/2026-11-09-static-trace-tool.md`.

Verdict: **blocked**, one Important finding (needs a decision). All five points of
the lead's instruction are carried; no contradiction with §1, §2 "Ask vs. assume",
§3 "Dependency hygiene", §4 known-case or smoke-test rules, or the scout,
reviewer and runner roles.

## Important

I1. `rules/global.md`, bullet "A code-tracing task runs a static tool for the
stack": CodeQL is the first named tool for security traces, and the rule has the
agent install and run it without confirmation in the sandbox (🟢+). The CodeQL
CLI terms (https://github.com/github/codeql-cli-binaries/blob/main/LICENSE.md,
fetched 2026-11-09) bar its use "in connection with any codebase that is not an
Open Source Codebase" unless under a paid GitHub Advanced Security licence or for
academic research. Scenario: an agent on a closed-source project (the work that
prompted this rule is a Jira-tracked product, OMDEV-n) installs CodeQL as the
rule names and runs it, breaching the tool's terms with no human in the loop.
Resolve (user's decision): either drop CodeQL from the list, or add that the
tool's licence must permit use on this codebase (Dependency hygiene has no
licence check today).

## Minor (not blocking)

M1. Same bullet: FindSecBugs is listed as a "taint or dataflow analyser", but it
reports the sink line of a bug pattern, not a source-to-sink path, so the
"answer cites the tool's paths" sentence cannot be satisfied from it. Not
applied: it belongs with I1's edit of the same tool list. Resolve: drop it, or
list it as a sink finder.

M2. No role carries a code trace. The scout role runs no commands and has no
Bash, so it cannot install or run a tool; the reviewer role's table has no trace
object. The lead may again spawn reviewer agents for a trace, as in the
omega-psir escape trace. This is a decision (which role, or "an implementer
slot"), so not applied; the user's request was the tool rule only, so it may
equally stay as is.

M3. `decisions.md`, static-trace-tool entry: "ran as reviewer agents reading
files" was not in the report, and the figures come from its "Waste" section, not
"Fit of kinds and roles". **Applied** as 79c21d9 (`fix(rules)`, unpushed).

## Checks run

- `git -C ~/knowledge show a093800`: read in full; only the two files changed.
- Decision figures (200 rows, 113228, 23m22s, Marta; ContestSearchFilters as
  Explore) found in `.tmp/process-report-omega-psir-6.0.x-2026-11-03_2026-11-09.md`
  lines 67, 92, 106, 113; that file is byte-identical to the one on
  `refs/reports/2026-11-09-omega-psir-6-0-x-d6d3`.
- Decision entry format matches the file's header and the ui-prototype-track
  entry (same "no proposal file" form); it is consistent with that entry's
  "Left out: a read-only repository scout".
