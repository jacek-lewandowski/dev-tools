---
name: propose-rule
description: Proposes a generic lesson learned as a change to the shared knowledge repository, by committing one proposal file on this sandbox's proposals branch. Use when the user asks to remember a rule for every project, or a mistake reveals a missing global or role rule.
---

# Propose a rule for the shared knowledge

This sandbox reads its rules read-only and proposes changes through its own clone
of the knowledge repository at `~/knowledge`, on a branch `proposals/<project-id>`.
You can commit there. You cannot fetch or push; the host does that when the
sandbox next starts.

## When

- The user says a lesson should apply everywhere, not just to this project.
- A mistake happened that a global or role rule would have prevented.

Project-specific lessons go to project memory or the project's own rule files, not
here.

## Procedure

1. Confirm the clone and branch:
   ```bash
   git -C ~/knowledge branch --show-current     # proposals/<project-id>
   git -C ~/knowledge status --porcelain        # must be empty before you start
   ```
   If `~/knowledge` is missing, the knowledge repository is not configured on this
   host; tell the user and stop.
2. Check for duplicates and prior rejections. Grep `~/knowledge/rules/`,
   `~/knowledge/roles/` and `~/knowledge/decisions.md` for the key words of the
   lesson. If it exists or was rejected, tell the user and stop.
3. Decide the scope: `global` for every agent, `role/<name>` for one kind of agent
   (planner, implementer, reviewer), `skill/<name>` for a procedure.
4. Write the file `~/knowledge/proposals/<project-id>/<YYYY-MM-DD>-<slug>.md`:
   ```markdown
   ---
   scope: global
   project: <basename of the project directory>
   target: rules/global.md
   evidence: <what happened, one paragraph, factual>
   ---

   # <Short imperative title>

   <The rule text exactly as it should appear in the target file.>
   ```
   Prose only. No tool-specific syntax, no line numbers, no project names inside
   the rule text itself.
5. Commit only that file:
   ```bash
   git -C ~/knowledge add proposals/<project-id>/<file>
   git -C ~/knowledge commit -m "proposal: <slug>"
   ```
6. Tell the user the proposal is committed and will reach the remote on the next
   sandbox start, and that the integrator decides whether it enters `main`.

## Never

- Edit anything outside `proposals/<project-id>/` on this branch. The host refuses
  to push such a branch and the proposal is stuck until the change is reverted.
- Run `git push`, `git fetch`, `git rebase` or change the branch.
- Put project-specific content in a proposal.
