# Brief: reverse review of the whole rule set after 2026-11-03

Class: review of rule text (no code). Reviewer on the stronger tier, as the
whole-rule-set review of 2026-10-31.

## Object

The shared knowledge repository at `~/knowledge`, branch `main`:

- `rules/global.md`
- `roles/*.md` (implementer, planner, reviewer, runner, scout, second-reviewer,
  writer, README)
- `decisions.md`, the record of why each rule exists; the entries dated
  2026-11-02 and 2026-11-03 state the intent of the latest changes.

Latest changes: `git -C ~/knowledge log --oneline dd91d76..main` (the lead's
handover review, the implementer's self-review of its note, the end user's
expectation, the lead's persona). Read them in context, not as a diff only.

## Goal

A reverse review: not "is the text consistent with itself" alone, but "does
the rule set, as it now stands, do what its rules are for, and does it make
sense as a whole to an agent that reads it fresh". In particular:

1. Each change of 2026-11-02/03 against its stated purpose in `decisions.md`:
   does the rule text achieve it, can an agent actually follow it, does it
   cost more than it buys?
2. Contradictions or tension between any two rules, old or new, that an agent
   would hit in practice (say which rule wins today, if any).
3. Rules an agent cannot follow: an actor that does not exist in that
   situation, a step with no input to act on, a check nobody runs.
4. Duplicates: the same rule stated twice in different words, where the two
   copies can drift.
5. The lead's persona: can it leak into files, agent messages, code or
   verification claims under the text as written?

## Out of scope

Wording polish, line wrapping, word count for its own sake, and proposals for
new rules unrelated to a finding.

## Output

Write the report to
`docs/superpowers/evidence/2026-11-03-rules-reverse-review.md` in the dev-tools
repository (the working directory). Per finding: severity (Critical,
Important, Minor, as the reviewer role defines), file and the rule's bold
heading or table row, the failure scenario (which agent, in which situation,
does what wrong), and what would resolve it. End with a short verdict on
question 1 for each of the four changes.

Do not edit anything in `~/knowledge` and do not commit.
