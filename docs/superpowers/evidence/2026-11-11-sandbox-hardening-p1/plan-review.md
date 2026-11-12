Task: 2026-11-11-sandbox-hardening

# Phase 1 plan review, round 1

Fiona (reviewer 1), 2026-11-11. Object: the phase 1 plan, its evidence file and
`author-questions.md`, against the spec at `4d6f677` (phase 1 block and what it names) and the
tree at `4d6f677`. **Verdict: not accepted.** 1 Critical, 5 Important, 9 lesser; nothing fixed
by me. Re-run: S1-S3, S5-S15, S17-S22 unchanged (counts equal the recorded ones); the patterns
of R3 and R5-R9 on the base; the structural search (119, as recorded) and a cross-check of it
(F2); two scratch probes with git 2.34.1 (F1). Not run: the base suite (read), anything on a host.

## Critical

- **F1 A fetch through C-GIT is not confined to `refs/sandbox/<id>/`** (C-KNOW data block, T09,
  O7, O10, B1's fetch lines, choice 3). Probe: with the plan's refspec form, in both
  transports, the fetching repository also gained a ref outside that namespace, supplied by the
  served repository; a short ref name of the kind `ai-knowledge` uses for the host's own
  remote-tracking `main` (tree: lines 233, 269, 292, 314, 420) then named a commit the served
  repository chose, and the host's fast-forward of its own checkout followed it. With choice 3
  that checkout is the render's source, so the goal's second bullet and I7 (rules never writable
  from a sandbox) would not hold, and O7's fixture has no such case. Resolves: the data block
  and T09 state that a fetch through C-GIT creates and updates refs only below
  `refs/sandbox/<id>/`, and that the host addresses its own refs there by full name; an
  obligation that fails otherwise (after a sync of a clone carrying refs of every kind, the
  host-owned repository's refs outside the namespace equal what its own fetch from the remote
  left, its `main` equals the remote's, and each origin holds exactly the listed refs and no
  other); a residue search for short names of host refs in `ai-knowledge`'s git calls; B1 in the
  same fetch form; and a second look at choice 3 (a bare repository of its own for sandbox refs
  keeps them out of the checkout the render reads).

## Important

- **F2 The structural rule misses git starts** (O3, R1, evidence "Structural search", impact-set
  row 1). Cross-check `command grep -rnaE '(^|[^A-Za-z0-9_./-])git([[:space:]]|$)' bin/ai`
  against the rule's output: three starts are absent from the 119, `ai-knowledge:61` (the body
  of `git_net`), `ai-knowledge:1158`, `ai-sandbox-migrate-knowledge:18`. The rule sees `git`
  only as command name or first argument; a wrapper with arguments of its own, and an
  environment-prefixed start in a brace group of a condition, pass, so R1 can be 0 with starts
  left and O3's known case does not pin it. The globs also skip a new extensionless script
  silently (`sandbox-knowledge-sync` already). Resolves: the rule matches the word `git`, bare
  or with a path, as name or any argument (such a rule gives 123 on the base: the 119, the
  three, and `command -v git` at 199); O3's cases add the missed forms; the non-starts
  (`require git`, `command -v git`, `hint git`: the 15 "wrapped" findings are hints) are
  exempted by name or removed, the plan says which; the test fails for a bash file under
  `bin/ai` that is neither parsed nor a named exception; a text-search residue covers what no
  structural rule sees; the evidence count and listing are corrected.
- **F3 X1's marker line cannot fail** (B1, pass line A1). The host-side fetch is given a path
  that exists only inside the container, so no host process can reach the fixture, and the
  mount is not C-GIT's form. Resolves: B1 mounts the root read-only at its own path and gives
  the fetch the fixture's real path, as O1 states, so X1 and PA6 test what T09 runs.
- **F4 A closed report is pushed again** (states, `pushed-report=`, O11, T10, O13). The base
  removes a writer's report ref on the host right after its push (`ai-knowledge:889`); the plan
  leaves that to the in-sandbox command. A clone whose container has not run it since the push
  (stopped during `sync --all`; running with stamp `1`) keeps the report, the remote no longer
  holds it once the integrator closed it, the host has no record of its push, and the next sync
  publishes it as open again. No case covers it (the stub runs the command after every sync).
  Related: the data block does not say that `refs/sandbox/<id>/` mirrors the clone at each
  fetch, nor what `ai-sandbox-rm` and `-gc` do with it. Resolves: a host-side record of pushed
  report commits that the push and `pushed-report=` consult; a case with a stopped writer
  across a close; the mirror and the removal stated.
- **F5 `ai-delegate` is a host-installed exception of the rule** (O3, PA9, Q3). It is in
  `ai_sandbox_helpers` (lib:216), refreshed on the host at every start, and starts git in its
  working directory; I3a "for everything the toolchain runs" and the closing check's first
  clause are then unmet on an inferred assumption. Resolves: a task drops it from the host list
  and removes the installed copy (the image copy, create:1899, is separate), with a check that
  no file excepted from the rule is a host helper; or the spec records the exception first.
- **F6 Committed text lists fixture ingredients** (O6, O7, O8's list, B1's control step and its
  label, evidence P-D), which equal the scenarios of H8, H7, H4 and C1; the spec forbids that
  in a plan or evidence file. Resolves: the obligations name the property and an untracked
  fixture; the lists and the control step move into the fixture file.

## Lesser

- L1 RP0, RP1: B1 runs a copy of the fixture checked against a hash in the batch; RP1 names a
  commit id, lists every changed path first and disables pager, external diff and textconv; the
  plan says that until phase 4 nothing binds the working tree to what was read.
- L2 B2 step 1: only `ai-sandbox` and create refresh the installed helpers, so `ai-knowledge
  status` after the merge is the old copy and shows `current`; start with the installed
  `ai-sandbox-migrate`. RP1's "the next `ai-knowledge sync` runs it" has the same gap.
- L3 A3: seen from this sandbox's clone it does not hold here, so the fail path is the expected
  one; repeat the A3 part after the migration and include the host checkout's old-style
  remote-tracking branches.
- L4 O12, O18, O1: `docker exec` and the confined run under a time limit; exec without a
  terminal or standard input; their standard error printed only with control characters
  removed; no image pull.
- L5 O8 names the state (container not running): the stub's in-sandbox command writes there.
- L6 The role file kept inside the clone contradicts the letter of C-STATUS's last sentence;
  add it to Q1.
- L7 The A2-fail branch changes C-GIT's "one function" and O3's "two functions": back to the
  spec's author before T09.
- L8 ast-grep becomes a suite dependency (unpinned in the image, PA4 depends on its version):
  declare it. `PROJECT_MAP.md`'s stated search for `reads-outside:` skips extensionless files.
- L9 O7 says "never forced" for `main` only; say it for every push, with a residue search.

## Choices and questions

1 (status keys): plan detail, with L6. 2 (no stamped ancestor): completes C-STAMP's signature
and changes what `init --integrator` records from a subdirectory; the spec states it. 3 (host
repository): plan detail, subject to F1. 4 (lib functions): plan detail. Q3: not plan detail
(F5). Q4: a reading of a spec rule, the author's (F6). Q5: phase 4, no effect here.

## Coverage

Tasks cite every obligation, carry no code, and the gate runs once; the text searches of the
impact set reproduce; nothing is added to phone work. Not yet proven: the goal's second bullet
(F1), the closing check's first clause (F2, F5), "what they do today" for reports (F4).

# Round 2

Fiona (reviewer 1, a fresh agent in the slot), 2026-11-11. Object: the revised plan and
evidence file against round 1, `plan-fixes-r1.md`, `author-answers.md`,
`spec-change-proposals.md`, the fixture file (its SHA-256 equals the one B1a checks) and the
tree at `4d6f677`. **Verdict: not accepted.** 0 Critical, 1 Important (new, N1), 8 lesser;
nothing fixed by me. F1 to F6 are resolved.

Run: the rule of O3 on the base (106 starts, 123 reports, as recorded) and on known cases of
my own; R1b (177 lines, 57 not reported, each of the four kinds); R10 (28), R11 (0), S20b (0),
S23 (5), all as recorded; a scratch probe of F1 in both transports (git 2.34.1); B1a as a
script against a local stand-in for the engine, as written and with the confinement removed;
B1b's clone part on this sandbox's clone (it lists the six old-style branches). Not run: the
suite, anything on a host.

## Round 1 findings

- **F1 resolved.** The property is in the data block and T09, by construction of the one fetch
  function; O19 has a negative case, R10 the residue, B1a and H a host line. Probe: the first
  plan's form left refs outside the namespace, T09's form none, in both transports and with
  six user-level fetch settings set. What B1a publishes is the defence (the fetch form the
  phase ships), not a reproduction step: the flaw existed only in the plan's first draft.
- **F2 resolved** for every start on the base; one claim of O3 is not pinned (N4).
- **F3 resolved.** Read line by line with the fixture: the fetch is given the clone's real
  path, so a host process can reach the fixture; the run fails on the two bad inputs the
  evidence names. Two ways to a false `none`, both guarded: a listing that fails prints
  nothing (the `same` line before it fails then), and an inert fixture (the control says so;
  it shows the configuration-borne marker only, the one a host git run in the clone leaves).
- **F4, F5, F6 resolved**: O20 with the host's record, O22 with the exceptions case of O3;
  plan, evidence and batches name inputs by class. PA12 holds in the knowledge clone's skill.
- **L6 and the two points taken from the author** (role file kept inside by the in-sandbox
  command; the lookup's result with no stamped ancestor; the host-owned repository kept): the
  answers are applied as given (O11, O16, R3; O4, O21; T09, O19) and leave no property of the
  phase unproven.

## Important

- **N1 A pending close of a report can be dropped unpublished** (O11 "drops a closed report
  and its tombstone once the origin no longer has the report"; O10; T06, T10). The other two
  removals inside are driven by the status file; this one is decided from the origin's
  content. An origin that never received the remote's reports (O10 names the state: the
  create's sync failed or found the lock busy; at the landing no host has fetched them yet)
  holds none, so the integrator's command at the first start removes every tombstone the host
  has not acted on, with its report, while the remote still holds the report: the close is
  lost without a word (I5; goal bullet 1, "what they do today": the base removes them only
  after the remote answered). Reached in B2 when the re-creation's sync is offline. Resolves:
  the removal is driven by the host like the other two (a key written once the remote no
  longer holds the report), or waits for a report fetch the status records as completed; a
  case in O11 or O18: a pending tombstone, a first sync that fails, the container started,
  both refs still there, and the next online sync closes the report.

## Lesser

- N2 B2 step 3, H: the ref line expects `none`, but `ai-knowledge propose --repo <host
  checkout> --push` leaves `refs/heads/proposal/*` there (tree: `ai-knowledge:1215`) and the
  migration of B1b calls it per converted file (`ai-sandbox-migrate-knowledge:262`). Compare
  the list before and after the sync, or name that namespace; say what follows a listed ref.
- N3 B2 step 3 has no control: a refused `refs` or `plant` gives `none` too. The in-sandbox
  command leaves markers in the sandbox's own `/tmp`; read them there before `undo`.
- N4 O3 claims "quoted or not", none of its six forms is quoted, and the evidence's rule
  reports a quoted argument but not a quoted command name (probe; R1b does not see it
  either). Add both quoted forms to the known case, or narrow the claim.
- N5 O14: the stamp-`1` case uses a sandbox directory as the base left it (no `status/`, no
  `knowledge-origin.git`); that is every existing sandbox at its first entry after the merge.
- N6 B1b step 2: the stop question is asked once for all running stale sandboxes, not per
  sandbox; and the order rule has no key here (the README on `main`, seen from the
  integrator's clone, records no integrator): print whether the host's configuration names one.
- N7 O15: the `a3.md` clause is a host condition no task can evidence; move it to RP1 or H.
- N8 O19 checks refs outside `refs/sandbox/`; a second sandbox's namespace unchanged by the
  first one's fetch would pin the data block's "only below `refs/sandbox/<id>/`".

## Proposed spec texts

- S-1: sound, no goal or order changes; the plan complies with the current sentence too.
  Two gaps: "nothing committed may hold them" against the fixture code it then requires (name
  the exception), and "before that code exists" leaves out B2's use after it exists.
- S-2: sound; phase 1 does not depend on it. "`image/` holds exactly the programs" disagrees
  with the row's own content (a settings file, Dockerfile parts): say that every in-container
  program lives there and the host executes or sources nothing there.
- S-3: agrees with C-KNOW and I7; phase 1 carries it as O19 and R10. It says "refs": such a
  fetch also writes the repository's last-fetch record, which the host must not resolve; and
  the author should say whether "the host names its refs in full" also binds a repository the
  user works in (phase 6).

## Coverage

With N1 resolved the obligations cover the goal of phase 1: bullet 1 (O7, O13, O20, O3, R1,
R1b), bullet 2 (O7, O19, R10, R11), bullet 3 (O8, O9, R2, R7, R8), bullet 4 (O4, O5, O6, R6,
R9), bullet 5 (O15, R4), the closing check's four parts (O3, O7, O6, H). No everyday host
step is added; the migration's commands and its signs of completion agree with the script
(N6 apart), and it is the base design's code.

# Round 3

Fiona (reviewer 1, a fresh agent in the slot), 2026-11-12. A delta re-review: the diff of the
plan and its evidence file against the round 2 copies (`.pre-r3.md`, byte-equal to `.r2.md`),
read with `plan-fixes-r2.md`, the round 2 findings, the spec at `4d6f677`, the author's
answers and the tree at `4d6f677` (`bin/`, `tests/` unchanged). The unchanged plan was not
reviewed again. **Verdict: accepted.** 0 Critical, 0 Important, 5 lesser (M1 to M5), all five
fixed by me in the plan and its evidence file; nothing is left for a decision.

Run: the revised rule of O3 on the base (106 starts, 123 reports, as recorded; round 2's rule
gives the same) and on the known case (10, round 2's rule 7, without the exemptions 13, as
recorded); R1b with the revised and with round 2's pattern (177 lines each, the outputs equal;
57 not reported) and on the known case (as recorded); S20c (0), S26 (0), R10's first search
(28) and, after M3, over the lib (0); `bash -n` on B1a and B1b; B1b's integrator line on a
scratch home (unset, empty, set); B2's before and after comparison on a scratch repository;
the fixture's SHA-256 against the one B1a checks (equal). Read in the tree: the base's report
and tombstone handling, the migration's stop question and its integrator condition. Not run:
the suite, anything on a host.

## The round 2 findings and the two extra items

- **N1 resolved**, by the first variant round 2 names. Every removal inside the clone follows
  a key the host wrote; `closed-report=` is written only from a completed fetch of the
  remote's reports, so an origin without the report decides nothing (data block, O11, T06,
  T10). The case round 2 asks for is in O18, with both triggers, and fails on the earlier
  behaviour. "Who uses it", the retry line, B2 step 2, the task citations of O18 and the
  new-names row agree with it; O10 needs no change. The key is plan detail by the author's
  answer to Q1.
- **N2 to N8 resolved**: N2 and N3 in B2 step 3 and H (before and after comparison; the plant
  line and the control; the base sync changes no ref of the host checkout outside the named
  namespaces, tree); N4 in O3, the rule and R1b; N5 in O14; N6 in B1b (the key and the single
  question agree with the script); N7 in O15 and RP1; N8 in O19.
- **`FETCH_HEAD` in R10**: added with its source (S26, empty on the base, known case).
- **The confined fetch in the lib**, judged as new text: the author suggested the place and
  calls helpers that start no git the plan's; the contract agrees with the data block, B1a's
  form and the final text of S-3, and holds without it; T09 adds it, O19 has a direct case
  with its own negative case, the row of new names lists it (S20c), R1 and R7 still read
  correctly. Two gaps, M2 and M3.
- The diff holds nothing beyond the findings, the two items and their consequences. Every
  statement of `plan-fixes-r2.md` agrees with the diff and the tree.

## Lesser, fixed by me

- M1 B2 step 3: the after-line relied on the variable `R` set by the before-line. In a new
  shell it is empty, the filter then passes nothing, and with an empty before-list the line
  printed `same` whatever the sync did (tried). Fixed: the after-line sets `R` itself.
- M2 O19, direct case of `ai_sandbox_confined_fetch`: it pinned only that nothing outside the
  prefix changes; the contract's exit line had no check anywhere (status 3 is never reached
  through the sync), and delivery and pruning were pinned only through the sync. Fixed: the
  direct case also asserts delivery as `<prefix>/<name>/*`, the drop of a ref the served tree
  no longer holds, and the three exit statuses.
- M3 R10: its short-name search read `ai-knowledge` only, while the fetch into the host-owned
  repository now lives in the lib. Fixed: the search names both files; evidence S24 records
  the lib's base result (none).
- M4 O17 said the in-sandbox command takes closed branches and pushed reports from the status
  file; closed reports are taken from it too. Fixed: named.
- M5 T10 did not say which fetch decides `closed-report=`; O18 lists the report in the sync
  that deletes it and O10 wants the origin equal to the remote after a sync, so it is the
  fetch made after the deletions. Fixed: T10 says so.

## Public level

The changed text states properties, keys and searches. What it names is what the host must
not use or what the rule must report (`FETCH_HEAD`, the quoted forms of a command name), the
defence and a lint's known case; no input of a fixture and no step that reproduces a finding.

## Coverage

N1 was the one gap round 2 left; with it closed the obligations cover the goal of phase 1 as
round 2 lists them, bullet 1 now also through O18's pending-close case.
