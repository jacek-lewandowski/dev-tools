# Brief: fix round after the reverse review of 2026-11-03

Class: brief (rule text, several files). Fix round 1 of at most 2.

## Input

- The review: `docs/superpowers/evidence/2026-11-03-rules-reverse-review.md`
  in the dev-tools repository (findings I1-I5, M1-M6).
- The object: `~/knowledge` on `main` (`rules/global.md`, `roles/*.md`,
  `decisions.md`). The intent of each rule is in `decisions.md`.

## Task

Edit the rule text in `~/knowledge` so that every finding I1-I5 and M1-M6 is
resolved. Take the resolution the review proposes unless you find a simpler one
that resolves the same failure scenario; then say why in your report. M7 is
outside the repository and not yours.

Constraints the user set earlier, which every fix must keep:

- The end user's expectation stays a step of the question filter, and the lead
  still filters a subagent's question before relaying it; only the cases the
  review names (business rules, incompatible behaviour changes, contract
  changes, 🔴 confirmations, design questions that belong to the spec's author)
  are carved out.
- A user's request to discuss or assess still changes nothing in the object
  under discussion.
- The implementer still reviews its own note.
- The lead stays Skippy Wspaniały, with the persona in the conversation only;
  the name in commit trailers and file names is intended (M6: state it as
  allowed).

Style: operative sentences only, rationale goes to `decisions.md`; prose, no
tool-specific syntax, no project names in rule text; match the surrounding
voice and wrap lines at the width of the file. Prefer moving or deleting a
duplicate over adding text.

Add one `decisions.md` entry at the top of the entries, dated 2026-11-03,
slug `rules-reverse-review-fixes`, naming the files changed and, in a few
sentences, what each finding changed.

## Acceptance

Each finding I1-I5, M1-M6 is resolved in the text, or your report says why a
finding needs no change. `git -C ~/knowledge diff --stat` touches only
`rules/`, `roles/` and `decisions.md`. Do not commit; the lead commits after
the re-review.

## Report

Open with your name. Per finding: one line, what you changed and where.
Then the output of `git -C ~/knowledge diff --stat`.
