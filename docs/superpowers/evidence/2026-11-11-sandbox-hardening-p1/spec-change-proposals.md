Task: 2026-11-11-sandbox-hardening

# Proposed changes of the approved spec, raised while planning phase 1

The spec (`docs/superpowers/specs/2026-11-11-sandbox-hardening-design.md`) changes only
with the user's approval. None of these is applied yet. Collected by the lead.

## S-1 and S-2: proposed by the spec's author
Exact text and reasons are in `author-answers.md` in this directory, section "Spec
changes for the user's approval".
- S-1, section "Inputs": states for every phase what committed text may hold (the
  property, the finding key, an input named by its class) and where a closing check's
  fixture lives (committed test code whose only effect is a marker in the test's own
  temporary directory; before that code exists, an untracked file the plan names).
- S-2, contract C-MODULES: `ai-delegate` belongs to the programs that run only inside
  the container and is not installed on the host or reached by the host's `PATH` entry.

## S-3: proposed by the phase 1 planner, for the author to judge
In C-GIT, at the end of the bullet that begins "Two uses. As the remote program of a
fetch made by a host-owned repository…", add:

> A fetch through it creates or updates refs of the fetching repository only under the
> destinations its refspecs name, and the host names its own refs in that repository by
> their full names; nothing the served repository holds outside those refspecs becomes a
> ref on the host.

The planner's reason: the contract's "the case git documents as safe" covers code
execution, not the refs a fetch creates; phases 4 and 6 also use C-GIT. Phase 1 does
not wait for it: the plan carries the property as its own obligation (O19).

## Conditional, not proposed now
Only if the user does not accept the timing that experiment X1 measures: the spec's
fallback for assumption A2 (`docker exec` into a running sandbox) would add a second
way to run git against a clone, against C-GIT's "one function". The plan does not
choose it.

## The author's judgement

Hania (planner 1, the spec's author slot), 2026-11-11. Read: C-GIT, C-KNOW, C-MODULES,
C-INSTALL, C-WORKSPACE, I2, I3, I7, D15, the blocks of phases 1, 4 and 6, review finding
F1, the plan's data block, T09 and O19, and `author-answers.md`.

### S-3 belongs in the contract

Not plan detail of phase 1. C-GIT is the only way the host fetches from a tree a
sandbox can write, and two later phases fetch through it into repositories the host
then trusts:
- Phase 4 (C-INSTALL): `ai-sandbox-install --from` fetches into `src.git`, the
  repository whose revisions the host exports and runs. I3b holds only if a revision
  the user names resolves to the commit the user meant; a name the served tree supplied
  that stood for one of `src.git`'s own refs would break that, also for a later install
  from the hosting remote.
- Phase 6 (C-WORKSPACE): the user's unpushed branches are fetched "as data" into the
  new clone at the user's path, the tree the phase's goal says no sandbox ever wrote.
  The confinement is what keeps that sentence true after the fetch.
C-GIT's "the case git documents as safe" covers what the host executes, not which refs
a fetch leaves behind, so without the sentence neither phase is asked for the property.
The phase 1 plan already carries it (O19, T09's full-name rule, R10) and does not wait.

Two improvements over the planner's wording: deletion is included ("changes"), since a
ref the host compares against must not vanish either; and the destinations are required
to lie under a prefix of their own, because confinement to the destinations protects
nothing if a later plan picks destinations that hold the host's or the user's own refs
(phase 6 is free to do that today). The phase 1 data block already meets both
(`refs/sandbox/<id>/` holds only fetched refs; the host's records are elsewhere).

**Final text.** In C-GIT, a new bullet directly after the bullet that begins "Two uses.":

> - A fetch through it changes refs of the fetching repository only below the
>   destinations its refspecs name, whatever else the served repository holds, and
>   those destinations lie below a prefix that holds only refs fetched this way, apart
>   from every ref the host or the user moves (for the knowledge sync
>   `refs/sandbox/<sandbox id>/`, C-KNOW). In such a repository the host names its own
>   refs by their full names wherever git resolves a revision, so no name the served
>   repository chose can stand for one of them.

A separate bullet rather than the end of the "Two uses." bullet, whose last sentence is
about the read-only queries, not the fetch.

**C-KNOW and the invariants.** No matching sentence. C-KNOW already names the prefix and
runs its checks against the `main` the host fetched itself; the new bullet cites it.
The property serves I3 (the host does not trust what a sandbox can write), I3b and
I7 without changing what any of them says.

**Not a spec matter, for the phase 1 plan.** T09 places the fetch in a function of
`ai-knowledge`. Placing it in `ai-sandbox-lib.sh` beside the C-GIT functions would let
phases 4 and 6 call it instead of extracting it later; the planner's choice.

### S-1, S-2 and S-3 together

Consistent with each other and with the spec.
- S-3's text states a property and names inputs by class only, as S-1 requires.
- S-2 relies on C-GIT's structural rule, which S-3 does not touch. D15 calls
  `ai-delegate`'s prompts "a surface the split does not touch"; under S-2 phase 3 moves
  the file into `image/` but leaves the prompts alone, so D15 still holds, and the
  phase's pin (the same suite result before and after) covers the moved path.
- S-1 permits the committed fixture code that phases 1 and 6 need for their closing
  checks ("prepared as in X1").

None changes a goal, the meaning of an invariant or the order of the phases. All three
are spec changes that need the user's approval: S-1 widens the spec's rule on committed
text to commit messages, batches for the user, test names and comments; S-2 changes
contract C-MODULES (phase 3) and through it what phase 4's `PATH` entry reaches; S-3
adds a property to C-GIT that phases 4 and 6 must meet and evidence in their own plans.
The conditional A2 fallback above stays a separate spec question, raised only if the
user does not accept X1's timing.

## Final texts for the user's approval

Hania (planner 1), 2026-11-11, after the round 2 review of the plan ("Proposed spec
texts" in `plan-review.md`). These texts replace the earlier wordings in
`author-answers.md` and in "The author's judgement" above. All three reviewer points
are taken.

### S-1, section "Inputs" (the paragraph after the header block)

Replace the sentence that begins "This spec names findings by key" and ends "may hold
them either." with:

> This spec names findings by key and states the property each phase establishes; it
> holds no reproduction steps, and nothing committed for this work may hold them
> either, except the fixture code of a test as stated here. A plan, an evidence file,
> a batch for the user, a commit message, a review and a test's name, header,
> assertion message or comment state the property and the finding key, and name an
> input only by its class, as this spec does (a clone's configuration, its refs, a
> link placed where a sandbox can write). A closing check that needs a fixture gets
> one in committed test code: the smallest that shows the property, whose only effect
> is a marker inside the test's own temporary directory; the specific settings, paths
> and commands it uses appear in nothing committed but that code. A host step outside
> the suite that needs such a fixture, before that code exists or after, takes it from
> an untracked file under `.tmp/security/`, which the plan names by path.

Changed from the first wording: the exception for fixture code is named in the
sentence that forbids reproduction steps; "nothing committed but that code" replaces
"only in that code"; the untracked fixture serves host steps also after the test code
exists (phase 1's batch after landing uses it).

### S-2, contract C-MODULES

In the table row for `image/`, replace

> `sandbox-knowledge-sync`, `sandbox-desktop`,

with

> `sandbox-knowledge-sync`, `ai-delegate`, `sandbox-desktop`,

and add after the paragraph that begins "Later phases cite these files:" the paragraph

> Every program that runs only inside the container lives in `image/`. The host
> executes or sources nothing there itself (the host's `docker exec` of
> `sandbox-knowledge-sync` runs it inside the container), nothing there is installed
> on the host, and C-INSTALL's `PATH` entry does not reach it; so C-GIT's structural
> rule leaves out `image/` by directory and names no file. A program that also runs
> on the host (`context-statusline`, the host's status line) stays in `bin/ai`.

Changed from the first wording: "holds exactly the programs" became "every program that
runs only inside the container lives there", which agrees with the row's settings file
and Dockerfile parts; the host's `docker exec` is named so that "executes nothing
there" is not read against C-KNOW.

### S-3, contract C-GIT

A new bullet directly after the bullet that begins "Two uses.":

> - A fetch through it changes refs of the fetching repository only below the
>   destinations its refspecs name, whatever else the served repository holds. Those
>   destinations lie below a prefix kept for that served repository alone, outside
>   `refs/heads/` and `refs/tags/` (for the knowledge sync `refs/sandbox/<sandbox id>/`,
>   C-KNOW). In such a repository every git call of the toolchain gives a revision as a
>   full ref name or an object id, never as a short name or `FETCH_HEAD`, so no name
>   the served repository chose can stand for one of the host's refs. In a repository
>   the user works in (phase 6) this binds the toolchain's calls, not what the user
>   types: a short name the user gives for one of their own refs never resolves below
>   the prefix.

Changed from the first wording:
- `FETCH_HEAD`, which every fetch writes from the served repository's answer, is
  excluded by name. That names a value the host must not use, the defence, not a
  reproduction step; the spec already names git settings at that level
  (`remote.<name>.uploadpack`).
- Phase 6 answered: the full-name rule binds the toolchain's git calls in any repository
  such a fetch writes into, the user's clone included. It cannot bind what the user
  types, so the user's short names are protected by where the refs land instead: the
  prefix lies outside `refs/heads/` and `refs/tags/` and holds only fetched refs, so a
  short name that git resolves to one of the user's own branches, tags or
  remote-tracking refs cannot be matched first by a fetched ref. That replaces "apart
  from every ref the host or the user moves", which left open whether branches under
  `refs/heads/` that the user has not yet moved count.
- "Kept for that served repository alone": a fetch from one sandbox cannot write into
  another sandbox's prefix (round 2, N8, asks the plan to pin this for phase 1).
- Object ids are allowed beside full ref names: the host compares and pushes recorded
  commits by id, and an id is no name the served repository can choose.
The phase 1 plan already meets this text: `refs/sandbox/<id>/` per sandbox, full ref
names in T09, R10 for the residue. R10's pattern does not match `FETCH_HEAD`; the base
does not use it either (`grep -n FETCH_HEAD bin/ai/ai-knowledge` returns nothing), so
the planner adds that name to R10 with an expected result of none.

### Checked against each other once more

- S-3 now names `FETCH_HEAD` and two ref prefixes. Under S-1 these are what the host
  must not use and where fetched refs must not land, the property's own terms; no
  setting that produces an effect, no input of a fixture.
- S-2's paragraph cites C-GIT's structural rule and C-INSTALL's `PATH` entry, neither of
  which S-3 changes; its `docker exec` clause agrees with C-KNOW's third bullet.
- S-1's fixture rule is what phases 1 and 6 need for "a clone prepared as in X1", and
  S-3's phase 6 clause is evidenced the same way (a test, inputs named by class).
- None of the three changes a goal, the meaning of an invariant or the phase order.

### For the user, one sentence each

- **S-1:** The rule "no attack recipes in the public repository" will cover everything
  committed (commit messages, test names, the steps you run on the host), with one named
  exception: a test may build its trap fixture in code that only leaves a harmless
  marker in its own temporary folder, and steps you run on the host take the fixture
  from an uncommitted file.
- **S-2:** `ai-delegate` runs git in whatever folder it starts in, so it joins the
  programs that run only inside the sandbox, a folder the host never runs anything
  from, and the phase 4 installer cannot put it back on the host's `PATH`.
- **S-3:** When the host fetches from a sandbox, the sandbox can fill only its own
  reserved corner of the receiving repository and the toolchain always names branches
  in full, so a sandbox cannot slip in a name that makes the host, or later you in your
  own clone, follow the sandbox's commit; it goes into the shared contract so the
  installer (phase 4) and the separate clones (phase 6) must keep it too.
