Task: 2026-11-11-sandbox-hardening

# Phase 1 plan: questions for the spec's author

Put by the phase planner (Bartek, planner 2) while writing
`docs/superpowers/plans/2026-11-11-sandbox-hardening-p1-plan.md`; relayed by the lead.
The plan's section listing its own choices and its evidence file
(`2026-11-11-sandbox-hardening-p1-plan.md` in this directory) hold the detail.

1. C-STATUS: the plan adds two keys to the `knowledge` status file, `project-id=` and
   `closed-proposal=<branch> <commit>`. Are they plan detail, or a change of the
   contract that the spec must state?
2. C-STAMP defines the lookup's result only when a stamp is found. The plan returns the
   given directory itself when none is found, which affects `ai-knowledge init
   --integrator` for a project that has no sandbox yet. Is that the intended result?
3. `ai-delegate` is installed on the host through `ai_sandbox_helpers` and starts git in
   its working directory. The plan keeps it as a named exception of the structural rule
   ("no host git in a sandbox-writable tree"). Should a later phase drop it from the host
   install, and does the exception agree with the invariant phase 1 establishes?
4. The closing check needs a committed test whose fixture plants marker settings, while
   the spec keeps reproduction steps out of the public repository. The planner reads
   this as: the fixture code is committed, its comments state only the property, and no
   plan, evidence or comment narrates it. Is that reading right?
5. For phase 4, not this one: `.gitignore` ignores `MANIFEST`, so the `bin/ai/MANIFEST`
   that C-INSTALL names would be ignored by git.

The plan also makes two more choices the spec leaves open, listed in it for the
reviewer: the host-owned repository is the existing `~/.ai-sandbox/knowledge/main`, and
the lib gains `ai_sandbox_writable_path` and `ai_sandbox_image_name`.
