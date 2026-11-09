# Review: 2026-11-09-task-key (Fiona, reviewer 1, round 1)

Task: 2026-11-09-task-key
Object: brief diff, `~/knowledge` ed5e562 and ae5436e, against the brief and the evidence file.
Verdict: **blocked** (two Important findings).

## Important

1. **`transcript_stats.py` `git_commits_of`: a commit with two Co-Authored-By trailers loses its `Task` and `Class` trailers.**
   The Co-Authored-By field is still joined with `\x1e`, and the new Task and Class fields come after it on the same line. `out.splitlines()` breaks the line at `\x1e`, so the fields go to a second line that does not start with `\x01`. That line is then read as a numstat line: its Task trailer is dropped, and its Class value becomes a fake file of 0/0 lines.
   Reproduced on a temp repo in the scratchpad (`twoco`). A commit with `Task: A`, `Class: brief` and one co-author gives `tasks ['A']`, class `brief`, which is correct. The same trailers with two co-authors give `tasks []`, class `None` and files `[('brief', 0, 0), ('f', 1, 1)]`.
   The case is reachable. 4 of 313 dev-tools commits carry two Co-Authored-By trailers, for example 2052b5f: the agent's named trailer and the tool's default trailer. Search: `git log --branches --no-merges --format='%H%x09%(trailers:key=Co-Authored-By,valueonly,separator=%x1f)' | awk -F'\x1f' 'NF>1'`. Checked on the temp repo, which has one known two-co-author commit and returned 1.
   Deviation 2 is therefore not out of scope. Before this change, the bug lost only the second co-author. This change puts the new fields behind the bug.
   Fix:
   - Join and split Co-Authored-By with `\x1f`.
   - Add a regression test, red first: one commit with two Co-Authored-By trailers and a `Task` trailer. It is keyed by the trailer, both co-authors are kept, and no file is invented.
   - Correct the comment above the `git log` call.

2. **`SKILL.md` step 4: the trim removed "(cheaper tier)".**
   Commit c32d8c7 ("restores the reviewer tier note") put this note back on purpose. The `reviewer` agent definition sets no model, so without the note the report review runs on the lead's model. This silently reverses a reviewed fix.
   Fix: restore "(cheaper tier)" and cut two words elsewhere that carry no instruction, keeping the body under 500 words (it is now 499).

## Deviations

- 1 (`\x1f` for Task and Class): accepted. `'a\x1fb'.splitlines()` keeps one line, while `\x1e` splits it.
- 2 (Co-Authored-By left on `\x1e`): rejected, see Important 1.
- 3 (SKILL.md trimmed): accepted except for the tier note, see Important 2. The other cuts only remove information ("default today", "(for a worktree)", the timestamp sentence, "An old host leaves it local, silently.").

## Lesser (fixed in 1e07811, not pushed)

- `test_task_file_spawn_gate_commit_and_tracker_class` (T5): the gate commit also carried `Class: phase`, so the row's class came from the trailer.
  Disabling the file `Task:` rule in a scratch copy kept the test green on ae5436e. After the fix, the same mutant fails that test.
  Fix: removed the trailer from the gate commit.
- `test_old_shapes_still_key_without_a_task_line` (T6): it covered only `#n`; the brief asks for a path key as well. Added a path-key spawn and commit.
- Checks after 1e07811:
  - `python3 -m unittest`: `Ran 56 tests`, `OK`.
  - ruff 0.17.3 check: `All checks passed!`.
  - ruff 0.17.3 format check: `4 files already formatted`.

## Lesser (not fixed, no blocking)

- SKILL.md step 2: "against the class given and the rules' class definitions" became "against the rules' classes". This drops what `fit?` compares.
- Evidence O4 records its result ("identical, 11 rows") but not the command run.
- decisions.md entry has four sentences, while the file's format asks for one or two. Neighbouring entries do the same.

## Confirmed

- The rule block landed verbatim. A whitespace-normalised comparison of the brief's block with `ed5e562:rules/global.md` returns True; the same block with one changed phrase returns False.
- `ed5e562` touches only `decisions.md` and `rules/global.md`.
- `spawn_key` and `commit_key` read the explicit key first, and the path and issue heuristics follow unchanged. `class_index_of` gives the explicit key precedence over the legacy key (`{**legacy, **explicit}`).
- T1–T7 and T2b are present. No existing test was modified.

## Round 2 (delta a111fad, ed816ba)

Verdict: **accepted**.

- Important 1 is resolved.
  - a111fad joins and splits Co-Authored-By with `\x1f`.
  - The `twoco` repro now gives `tasks ['A']`, class `brief`, both co-authors and files `[('f', 1, 1)]`.
  - `grep -n x1e transcript_stats.py` returns only the comment.
  - The new test `test_two_co_authors_keep_the_task_and_class_trailers` has a recorded red run before the fix (`errors=1`).
- Important 2 is resolved: ed816ba restores "(cheaper tier)".
- Lesser findings resolved:
  - The step 2 wording is restored.
  - O4 now records its command.
  - The decisions.md entry is two sentences.
- Re-run on HEAD ed816ba:
  - `python3 -m unittest`: `Ran 57 tests`, `OK`.
  - ruff 0.17.3: `All checks passed!` and `4 files already formatted`.
  - SKILL.md body: 498 words.
- Lesser, not fixed: the step 6 cut drops "(no stats JSON)", the reason the filed figures cannot be re-checked. No reader loses an instruction, so no change.
