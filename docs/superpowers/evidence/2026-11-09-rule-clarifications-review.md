# Review: rule clarifications of 2026-11-09 (review-round-limit, spec-author-slot)

Fiona, reviewer 1. Class: small. Round 1.
Object: `~/knowledge` main, 116227e and c1b8b86; evidence: section "Follow-up (2026-11-09)"
of `docs/superpowers/evidence/2026-11-09-role-model-pins.md`.

Verdict: **block** on one Important finding (I1). c1b8b86 (spec-author-slot) passes as is.

## Important

**I1. `rules/global.md` §5 "Maximum 2 review→fix rounds" contradicts the handover's own end of rounds.**
- Where: the new sentence "When a finding still blocks after the second round, the lead brings it to
  the user with three choices…" (116227e), against `rules/global.md` §2 context lifecycle, bullet
  "The lead's handover is reviewed…" ("The lead appends findings still blocking after the second
  round to the handover under a heading of its own, commits it, and names them when it declares the
  handover ready. Only then comes `/clear`.") and the Handover row of `roles/reviewer.md`, which says
  the same.
- Scenario: the 30-minute timer fires with no user action; the lead writes the handover and has it
  reviewed; a finding still blocks after round 2. §5 says to put three choices to the user, who is
  away. The context lifecycle says to append the finding, declare the handover ready and clear. A lead
  following §5 holds the handover undeclared and never marks the session ready; one following the
  lifecycle skips the choice the user decided on. Nothing in the rules says which one wins.
- Resolution needs a decision on scope, so it is not fixed here. Recommendation: keep the handover
  exception, because the user is not there to choose, and add a clause to the §5 sentence, e.g.
  "…or allow one more round; a handover review ends as the context lifecycle states." The other
  option is to apply the three choices to handovers too, and rewrite the lifecycle bullet and the
  Handover row to match.

## Lesser

- **M1 (fixed, 650212f).** `roles/reviewer.md` Round column. The Brief diff cell (new in 116227e)
  said "the second and last round", which rules out the third round the user may allow. The Small
  diff cell said "One; a blocking finding gets a delta re-review", which under decision (a) is
  two rounds. Both now say "a delta re-review, which is the second round". The Phase row
  ("As the brief; at most two rounds") matches §5's "Maximum 2" and is unchanged.
- **M2 (not fixed, needs a decision).** `skills/process-report/SKILL.md` step 4 has its own limit,
  "At most two rounds; you fix.", and `transcript_stats.py` `--check` accepts only `rounds=([0-2])`.
  If the user allows a third round under §5 for a report review, the Method line cannot record it
  and `--check` fails. This is the same question of scope as I1. Recommendation: settle it together
  with I1, either by naming the skill's own limit as an exception or by widening the regex and its
  test to 3.

## Checked, no finding

- Each diff says what was decided and nothing more. The rationale is in `decisions.md` only, and
  the `global.md` sentences are operative.
- spec-author-slot agrees with "Ask vs. assume", whose lead answers only what the spec settles and
  so is not a gap. It also agrees with "The lead only stitches", with the lifecycle table row
  "Spec author… a fresh agent in the same slot carries on from the files", with `/clear` and with
  `roles/planner.md` line 9.
- §2 "The user sees only reviewed versions" already lets questions that the rules route to the
  user through, so the three-choice question fits it.
- `roles/implementer.md` and `roles/second-reviewer.md` do not contradict the round count
  ("Round 2 is a continuation" still holds).
- The two `decisions.md` entries follow the format, newest first, two sentences each. They follow
  the role-model-pins precedent for entries whose source is a process report, not a proposal.
- The evidence quotes match the committed text. The `~/knowledge` repo has no check set to run.

## Round 2 (delta 6fe5c0f)

Verdict: **pass**. No Critical or Important finding.

- I1: resolved. The §5 sentence now says a handover review ends as the context lifecycle states,
  which agrees with that bullet and with the Handover row of `roles/reviewer.md`.
- M2: resolved. §5 points a process-report review to its skill. In step 5 of the skill, a
  finding still blocking after round two is recorded as a gap, and `rounds=<0-2>` and the `--check`
  regex stay valid.

Lesser findings, fixed by me in `~/knowledge` main (not pushed):
- d59505c: removed the rationale clause "because no user decides there" from the `global.md` §5
  sentence, because global.md carries operative sentences only.
- 66c7f7f, 8a9b911: the review-round-limit entry in `decisions.md` now lists
  `skills/process-report/SKILL.md` among its targets and gives the reason for the exceptions in a
  sentence of its own. It is not attributed to the user's decision, because the lead made it.

Lesser, not fixed (needs a choice): step 5 of `skills/process-report/SKILL.md` does not say which
`verdict` goes with a finding that still blocks. `accepted with notes` is the likely reading.
