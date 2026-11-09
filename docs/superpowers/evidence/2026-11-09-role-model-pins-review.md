# Review: role-model-pins (2026-11-09), Fiona, reviewer 1

Class: small, one diff review for both commits.
Under review: dev-tools `4e0ab85`, ~/knowledge `294c0d0`, evidence
`docs/superpowers/evidence/2026-11-09-role-model-pins.md`.

## Verdict

Accepted. No Critical or Important finding; the round is closed.

What was checked, without re-running anything (the recorded results settle the claims):
- Scope: `294c0d0` touches decisions.md, roles/README.md and the four single-tier roles
  (runner `haiku`; implementer, scout, writer `sonnet`); planner, reviewer and second-reviewer carry
  no `model:`; rules/global.md is untouched. `4e0ab85` touches only the renderer and its test.
- Render: `drop_claude_keys` filters only the front matter group of `^(---\n)(.*?)(\n---\n?.*)$`, with
  `re.match` anchored at line start, so body lines and indented lines stay and `models:`-like keys are not
  matched. Antigravity and Codex copies are built from `description` and the body only.
- Test: the recorded red run (`not ok 24`, `not ok 25`, 473 run, 2 failed) fails for the reason the change
  guards; green 473 run, 0 failed. The byte comparison against the Claude copy minus the exact
  `model: haiku` line pins both the drop and the body-line survival.
- README against global.md §2 "Decomposition": runner cheapest = `haiku`, implementer, scout, writer
  cheaper = `sonnet`; planner and reviewer span two tiers and stay unpinned. The Agent tool's per-spawn
  `model` takes precedence over the definition's front matter, so "the lead passes the model per spawn"
  is operative.
- decisions.md entry: newest first, `<date> <name> integrated`, target line, two sentences; naming a
  non-proposal decision follows the 2026-10-08 `agent-roles-readme` precedent it reverses. The cited
  ukf-consulting-site report was not checked (unverifiable from this tree; the user's stated motive).

## Lesser findings (not blocking, not applied)

1. `~/knowledge/roles/README.md`, front matter example: it shows `name: planner` with `model: sonnet`,
   while the bullet below says planner has none. Failure: a reader copying the example pins a two-tier
   role. Resolve: drop the `model:` line from the example, or make the example a single-tier role; this is
   a choice, so it returns to the author.
2. `~/knowledge/roles/README.md`, `model:` bullet: second-reviewer is unpinned but is neither a one-tier
   nor a two-tier role in the bullet's terms (it runs only on another vendor's model), and the bullet does
   not say that a per-spawn model overrides a pin (needed when global.md's routing table or the user's
   word for a stronger model applies). Resolve: one clause for each.

Not applied: this agent's own definition opens with "You review; you do not fix", which conflicts with the
current `roles/reviewer.md` on ~/knowledge main and with the lead's instruction; the render this session
runs on predates that change. Both findings are wording in ~/knowledge and need no re-review.
