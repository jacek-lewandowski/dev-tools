Task: 2026-11-11-sandbox-hardening

# Phase 1 plan: answers of the spec's author

Hania (planner 1, the spec's author slot), 2026-11-11. Answers `author-questions.md` in
this directory. Read against the spec at `4d6f677`, the plan
`docs/superpowers/plans/2026-11-11-sandbox-hardening-p1-plan.md` and its evidence file,
and the tree at `4d6f677`. Findings are named by key only.

Summary: Q1, Q2 and the two extra choices stand as plan detail. Q3 needs a change of
the plan now (fold) and a change of the spec's C-MODULES for phases 3 and 4 (S-2,
for the user's approval). Q4: the planner's reading is right; the spec's sentence is
widened so every phase applies it the same way (S-1, for the user's approval). Q5
goes to the deferred list for phase 4 (E2); the contract's name stays.

## Q1 `project-id=` and `closed-proposal=` in `status/knowledge`

**The spec settles it as plan detail.** C-STATUS fixes the location, the read-only
mount, line 1 and the shape of further lines ("`key=value`, per topic"), and names two
keys of `knowledge` (`role=`, `pushed-report=`). The contracts section says "Names
given here are fixed; everything else is the phase plan's". Two more keys of the same
shape keep every fixed name and every reader: `sandbox-doctor` prints line 1 only, and
phase 9 plans against C-KNOW and C-STATUS as the plan's data block records them. No
spec change.

Both keys agree with the invariants:
- `closed-proposal=<branch> <commit>` keeps the classification of a closed proposal on
  the host (O17, a rule lives once). The condition "only while its tip is the listed
  commit" has a real trigger: agents commit in the clone between two syncs.
- `project-id=` lets the in-sandbox command write `.git/ai-knowledge-role` in its old
  shape for the reader outside this repository (the knowledge repository's
  `propose-rule` skill and proposals README; evidence S12). C-STATUS says the status
  file "replaces `.sync-status` and `.git/ai-knowledge-role` inside the clone"; that
  binds the host, which writes neither any more (phase 1 goal: the host writes nothing
  below `<sandbox dir>/knowledge`) and reads neither (residue R3). A program inside the
  sandbox keeping the old shape for an outside reader is the project's rule for
  formats read outside the repository, not a contradiction. The role file decides
  nothing on the host (I3d holds because the host never reads it). Retiring it is a
  change in the knowledge repository through a proposal, not work of this spec, and
  needs no entry now.

## Q2 C-STAMP when no stamped ancestor exists

**The spec is silent on the not-found result; returning the given directory may stand
as plan detail.** C-STAMP defines the found case and says that a command below a
sandboxed parent addresses the parent's sandbox. Returning the directory itself keeps
every caller's behaviour: `ai_sandbox_require_ctx` then finds no compose file and says
"No sandbox configured" as today; `sync <dir>` and `status <dir>` report no sandbox.
It reads nothing a sandbox can write (I3d). Later phases that resolve "the sandbox of
the current directory" (C-REPOS) get the same "no sandbox" outcome. The plan's contract
block is where later phases find it; the spec needs no sentence.

`ai-knowledge init --integrator DIR` is the one caller that stores the result and
compares it later as a string (`INTEGRATOR = project`, tree: `ai-knowledge`), and it
also writes it into `README.md` on the knowledge `main`, where a wrong first record
persists. Today init and create resolve through the same function and agree by
construction; after the plan they do not (init: the lookup; create:
`ai_sandbox_create_root`). Consequences, all fail-safe (no sandbox gains the role it
was not named for, except as below), but visible only later:
- DIR is a repository root with no sandbox yet (the documented use,
  `docs/shared-knowledge.md` step 3, which comes before any sandbox exists): the
  record must equal what the lookup returns after `create-ai-sandbox.sh DIR`. That
  holds only if the not-found result and the stamp written by create have the same
  path form; the plan's O4 shows that today's stamps hold the resolved path for a
  repository, so a project reached through a linked parent would differ and the
  integrator would silently sync as `proposals`.
- DIR is a subdirectory of a repository with no sandbox yet: today the repository
  root is recorded, after the plan the subdirectory, which no sandbox will be created
  for.
- DIR is a repository below a sandboxed parent and has no sandbox of its own: C-STAMP
  settles this, the parent's sandbox is addressed and takes the role. That is the
  spec's rule (the sandbox that works on DIR), and it stays.

What the plan adds, as plan detail (no spec change):
1. A case under O4 or O6: `init --integrator DIR` run before DIR's sandbox exists
   records the value that the lookup returns for DIR once `create-ai-sandbox.sh DIR`
   has created it, for DIR a repository root, also when DIR is reached through a
   linked parent. Which path form the plan uses is its choice as long as this holds.
2. `init` prints, before it records the integrator in `README.md`, the directory it
   recorded and the sandbox that directory names, or that none exists yet and that
   the sandbox created for exactly that directory takes the role. A line of output,
   not a guard; the repair is a re-run of `init`, as today.

## Q3 `ai-delegate` on the host, and the exception in the structural rule

**What the spec settles.** I3a: the host starts no git process whose repository or
working tree a sandbox can write, except through C-GIT, "Phase 1 for the toolchain".
C-GIT: the structural rule fails the suite "when a host script starts git other than
through these two functions". The spec's scope is `bin/ai/`, so `ai-delegate` is part
of the toolchain.

**The exception does not agree with I3a as long as the toolchain installs
`ai-delegate` on the host.** It is copied into the image (tree: the Dockerfile's
`COPY ai-delegate`) and is also on `ai_sandbox_helpers`, which `create-ai-sandbox.sh`
installs into `~/.ai-sandbox/bin` on the host's `PATH` and `ai-sandbox-migrate`
refreshes (tree, since `4036f32`). It starts git in its working directory, so run on
the host inside a sandboxed project it is a host git process in a sandbox-writable
tree. Its host install serves no documented use: `PROJECT_MAP.md` says "Installed in
the sandbox image", the generated environment block addresses it to the sandbox, and
the host opt-in that the agent-roles design required for host use (its D3, a
root-owned allow file) does not exist in the tree. PA9 is therefore right about the
intent and wrong about the effect.

**Phase 1 (fold into this plan; same file, inside the goal I3a for the toolchain).**
- Remove `ai-delegate` from `ai_sandbox_helpers`, and have the helper install in
  `create-ai-sandbox.sh` remove a copy of it that an earlier run put into
  `~/.ai-sandbox/bin` (trigger: every host where a create ran since `4036f32`; the
  install loop and `ai-sandbox-migrate` add helpers but remove none), with one line of
  output that says so.
- O3's exception then rests on a true premise: both `ai-delegate` and
  `sandbox-knowledge-sync` are in-image programs that the toolchain does not install
  on the host. One obligation case: `ai_sandbox_helpers` lists neither, and a create
  run over a home holding the old copy leaves none.
- What remains until phase 4: a host whose `PATH` names the checkout's `bin/ai`
  (`PROJECT_MAP.md`: each `bin/` subdirectory is meant for `PATH`; the host status line
  uses it) still reaches both programs there. That is the accepted residual of H3
  ("H3 stays open until phase 4"); phase 1 adds no guard for it.

**Phases 3 and 4 need a spec change (S-2 below).** C-INSTALL makes
`~/.ai-sandbox/bin` a link to `installed/current/bin/ai`, which would put every
top-level program of `bin/ai`, `ai-delegate` included, on the host's `PATH` again.
C-MODULES already places `sandbox-knowledge-sync` under `image/`, which `PATH` does not
reach, but its list does not name `ai-delegate`. The clean form is that `image/` holds
exactly the in-image programs; the structural rule then leaves out a directory instead
of naming files, and phase 4's manifest check can show that the host neither executes
nor sources anything there.

## Q4 No reproduction steps in the public repository, and the fixtures tests need

**The planner's reading is right.** The spec requires committed tests with such
fixtures: phase 1's closing check ("a test syncs a clone prepared as in X1") and phase
6's ("a test converts a tree prepared as in X1"). So test code that builds the fixture
is committed; what the spec forbids is narrative. The rule, for every phase:

- **Test code** (committed). A closing check that needs a fixture gets the smallest
  fixture that shows the property. Its only effect is a marker inside the test's own
  temporary directory: no network, nothing outside that directory, nothing that
  outlives the test. The specific settings, paths and commands that make it work
  appear in that code and nowhere else.
- **Test names, headers, assertion messages, comments** (committed, and printed in
  suite output that evidence quotes). They state the property under test and the
  finding key, for example "the host runs no git in the clone (C1)". They do not say
  which setting or path has which effect on the host, why the fixture triggers it, or
  what someone would gain.
- **Plans, evidence files, batches for the user, commit messages, review reports**
  (committed). They name findings by key and inputs only by their class, at the level
  the spec uses: "a clone prepared as in X1", "a clone's configuration and refs", "a
  link at each path the base design wrote below the clone". An obligation names the
  cases its claim depends on by class and points at the test file and case names; the
  enumeration lives in the test. Evidence records commands, counts and results, not
  fixture code or why it works.
- **Host steps before the test exists** take the fixture from an untracked file under
  `.tmp/security/`, named in the plan by path (phase 1's B1 and B2 do this), and host
  logs stay there; evidence records only the verdict (spec, "Files of this work").
- **Public documentation the spec cites** ([L3], [L4]) may be cited as it stands; it
  is not a reproduction step.

Applied to this plan: B1 and B2 hold no setting that produces a marker; O7 names its
inputs at the spec's own level (where the host pushes, what it compares against). O8
lists four specific paths at which links are placed, each a place where the base
design wrote below the clone; together with "links" and H4 that is a recipe for the
base tree. O8 should say "a link at each path the base design wrote below the clone
(the list is in the test)" and leave the four names to the test code. The same applies
to the impact-set row for `.git/ai-knowledge-role` only where it would say what a link
there does; naming the file as a dependant is fine.

The spec's sentence names only "phase plan, evidence file or test description", which
leaves commit messages, batches, test comments and fixture code to each planner's
reading. S-1 below states the rule once in the spec, the only document every phase's
planner reads.

## Q5 `.gitignore` ignores `MANIFEST` (phase 4)

**Verified in the tree.** `git check-ignore -v --no-index bin/ai/MANIFEST` answers
`.gitignore:27:MANIFEST`, a line of the Python packaging section of the initial
commit; the same check on the other paths C-MODULES and C-INSTALL name (`create.d/`,
`image/` files) answers not ignored, so `MANIFEST` is the only one.

The failure is reachable: `git add bin/ai` skips an ignored file without an error, the
suite's manifest check passes in the working tree, and a revision exported from a
commit (C-INSTALL, `rev/<commit>/`) lacks the manifest. The contract's name stays;
the fix is one negation line, `!bin/ai/MANIFEST`, in `.gitignore`. That is no change of
a goal, contract or invariant, so no spec change; the carrier to phase 4 is the
deferred list (E2 below), which the lead adds with this plan's commit. The phase 4
planner treats the line as part of the phase although `.gitignore` is not in the scope
line at the top of the spec; the entry says so.

## Extra choice: the host-owned repository is `~/.ai-sandbox/knowledge/main`

**Agrees with the spec; plan detail.** C-KNOW: "one host-owned repository under
`~/.ai-sandbox/knowledge/`". C-GIT: host-owned means outside every sandbox mount, with
configuration only the host writes. Tree: sandboxes mount the render under
`~/.ai-sandbox/shared/knowledge` (read-only) and their own `<sandbox dir>/knowledge`,
never `knowledge/main`; its configuration and hooks are the host's. It is already the
source of the render and of `propose --push`, so one repository serves all host
checks. Property the plan relies on and should state with T09 (no new obligation if
O7 covers it): the work tree of `knowledge/main`, and so the render, moves only to
the `main` the host fetched from the remote; `refs/sandbox/*` are compared and pushed
from, never checked out or merged on the host.

## Extra choice: `ai_sandbox_writable_path` and `ai_sandbox_image_name`

**Both agree with the spec; plan detail.** C-GIT fixes the two functions that start
git; helpers that start none are the plan's.
- `ai_sandbox_image_name` gives the image tag one definition (the tag is computed in
  `create-ai-sandbox.sh` today); C-GIT needs "the sandbox image" and phase 8 already
  plans against C-GIT's container.
- `ai_sandbox_writable_path` judges what a sandbox can write now, from host-written
  compose files and stamps. That matches C-INSTALL's refusal ("a directory that a
  sandbox mounts read-write (by the stamps under `~/.ai-sandbox`)"), so phase 4 may
  reuse it. It is not C-WORKSPACE's "sandbox-written", which also counts trees that
  removed sandboxes wrote (`~/.ai-sandbox/written-trees`). Phase 6 adds that test
  beside it, under its own name, and does not widen this function's meaning in place.

## Spec changes proposed (for the user's approval, through the lead)

**S-1 (Q4), section "Inputs" at the top.** Replace the sentence

> This spec names findings by key and states the property each phase establishes; it
> holds no reproduction steps, and no phase plan, evidence file or test description
> committed for this work may hold them either.

with

> This spec names findings by key and states the property each phase establishes; it
> holds no reproduction steps, and nothing committed for this work may hold them
> either. A plan, an evidence file, a batch for the user, a commit message, a review
> and a test's name, header, assertion message or comment state the property and the
> finding key, and name an input only by its class, as this spec does (a clone's
> configuration, its refs, a link placed where a sandbox can write). A closing check
> that needs a fixture gets one in committed test code: the smallest that shows the
> property, whose only effect is a marker inside the test's own temporary directory;
> the specific settings, paths and commands it uses appear only in that code. A host
> step that needs such a fixture before that code exists takes it from an untracked
> file under `.tmp/security/`, which the plan names by path.

Why: the current sentence leaves commit messages, batches, comments and fixture code
to each phase's reading, and phases 1 and 6 both need fixtures.

**S-2 (Q3), contract C-MODULES.** In the table row for `image/`, replace

> `sandbox-knowledge-sync`, `sandbox-desktop`,

with

> `sandbox-knowledge-sync`, `ai-delegate`, `sandbox-desktop`,

and add after the paragraph "Later phases cite these files: ..." the paragraph

> `image/` holds exactly the programs that run only inside the container. Nothing
> there is installed on the host or reached by C-INSTALL's `PATH` entry, so C-GIT's
> structural rule leaves out `image/` by directory and names no file. A program that
> also runs on the host (`context-statusline`, the host's status line) stays in
> `bin/ai`.

Why: C-INSTALL puts the top level of `bin/ai` on the host's `PATH`; without this,
phase 4 would make the in-image `ai-delegate`, which starts git in its working
directory, a host command again, against I3a.

## Deferred list (no goal, contract or invariant changes; added with the plan's commit)

- **E2 `bin/ai/MANIFEST` would be ignored by git** (noticed while planning phase 1,
  2026-11-11). Failure: `.gitignore` ignores every path named `MANIFEST` (its Python
  packaging section), so C-INSTALL's manifest is skipped by `git add` of its directory
  and missing from a revision exported from a commit. Kept for phase 4: its plan
  adds `!bin/ai/MANIFEST` to `.gitignore`, a one-line change outside the scope line at
  the top of the spec, needed by the contract's fixed name.

## Changes to the phase 1 plan that follow (the planner's, with the plan's approval)

- Q2: the `init --integrator` case under O4 or O6, and the printed line.
- Q3: remove `ai-delegate` from `ai_sandbox_helpers` and the stale host copy, with
  the obligation case; PA9 restated as verified intent; the plan's deferred list adds
  E2.
- Q4: O8 names its link cases by class and leaves the paths to the test.
