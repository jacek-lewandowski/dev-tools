# Review: task-key brief, round 1 (Marta, reviewer 3)

Verdict: one Important finding (blocking), lesser findings applied or listed.

## Important
1. Key shape vs rule. The rule text defines a key as a tracker id or a `YYYY-MM-DD-slug` stem, but T5 and "Key shape" use `p1-T5`, and the rule does not say what key a phase and its tasks carry, nor what a phase-level spawn (reviewer, runner, planner) or the gate commit is keyed by. In the phase class the unit of plan, review and gate is the phase (global.md §2, §5), while evidence files are per task. Without a sentence, nodespool-style `evidence/phase-N/` stays unassigned or splits per task. Resolve: state in the rule block that a phase has one key (its plan stem or tracker id), its tasks and spawns carry it, and change T5's key to such a stem; or state per-task keys and how phase-level spawns are keyed.

## Lesser (applied in the brief)
- O2 said 47 existing tests; `python3 -m unittest test_transcript_stats` runs 48 (OK).
- O4 claimed no commit carries `Task:`, but the brief's own two commits do and fall in the 2026-11-09 window; O4 now runs before commit (1).

## Lesser (listed)
- T2 covers spawn precedence only; add a commit case: `Task:` trailer wins over a differing path/subject hint.
- "a slug passes through `strip_suffix`": say whether it applies to every explicit key or only to date-slugs, and apply the same to the class index key so a brief and its evidence collapse (class lookup uses the stripped key).
- Class from the earliest-commit trailer needs commits inside `class_index` (today `class_index(repos)` takes none); the signature change is implied, name it.
- Rule block placement: it fits the "Every task has a class" bullet and does not contradict "Agents carry names" (name line stays first), "Tracker issues are task briefs" (issue id = key) or §3 Commits (no trailer rule there; the Task/Class trailers live only in §2). Consider no change; the trailer lives in one place.

## Checked and fine
- Transcript claims: Agent `tool_use`, `input.prompt` beginning "You are Fiona, reviewer 1." found in 4256d730-...jsonl. Script claims (`PATH_KEY`, `ISSUE`, `known_issues` gating, `class_index_of` brief/plan rule, trailer format string, `strip_suffix`) match `transcript_stats.py`. Not checked: the `isMeta` later-prompt shape in the subagent file.
- Tests T1-T7 and O2-O7 prove the behaviour including the fallback; size fits a brief.
- SKILL.md body is 497 words, as stated.
