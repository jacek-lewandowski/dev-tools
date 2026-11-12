Task: 2026-11-11-sandbox-hardening
Class: phase

# Phase 1 plan: host git leaves the sandbox-writable trees

Phase key: `2026-11-11-sandbox-hardening-p1`. Spec:
`docs/superpowers/specs/2026-11-11-sandbox-hardening-design.md` (approved, `4d6f677`),
block "Phase 1", with I2, I3a, I3c, I3d, I4, I5, I6, I7, I8 and the contracts C-GIT,
C-STATUS, C-KNOW, C-STAMP. Evidence directory:
`docs/superpowers/evidence/2026-11-11-sandbox-hardening-p1/`; the searches and probes
behind this plan are in `2026-11-11-sandbox-hardening-p1-plan.md` there. Written by
Bartek (planner 2) on 2026-11-11 against `4d6f677`; revised the same day after the plan
review (round 1), each finding's answer in `plan-fixes-r1.md` there, and on 2026-11-12
after round 2, in `plan-fixes-r2.md` there. Findings are named
by key only and inputs only by their class (the author's answer to Q4, and S-1); no step
here reproduces one.

## Amendments after implementation (2026-11-12)

Applied by Bartek (planner 2) after T12 and before the phase review, from the lead's
queue (numbered as there), so that the review reads what was agreed. Evidence files are
those of the branch, in the evidence directory. No goal, invariant or contract of the
spec changes, and no obligation is added; obligations change only where an item says.

| Item | What changed in this plan | Rests on |
|---|---|---|
| 1 | Contract line of `ai_sandbox_create_root`: its fallback is the directory with links resolved, as `ai_sandbox_project_root`'s. O5: the ids equal today's except for an unstamped plain directory first reached through a link, which is stamped by its resolved path. | `T02-stamp-lookup.md`, "Deviation from the plan" |
| 2, 9 | Decided: O13 stands as written and T08's entry is amended. T08 kept the old-style-branch skip with a new message; T09 removed it and its half of the line-272 case (the host reads refs only; a branch outside `proposal/*` is no proposal to it). | `T08-remove-migration.md`, "Deviations from the plan"; `T09-gateway-proposals.md`, "Deviations from the plan" 1 |
| 3 | T06's entry: the hook is copied into `sandbox-knowledge-sync`; T09's entry: T09 deletes `install_hook` and the role-file write in `ai-knowledge` (R3, R8). | `T06-in-sandbox-sync.md`, "Deviations from the plan" |
| 4 | Impact-set row "Image tag": the corrected search S22, three lines, `bin/ai/ai-sandbox-extensions` added; the search is kept as a build check in `test-identity.sh`. | `T01-host-git.md`, "S22" |
| 5 | "First gate" and T12's entry: T12 runs after T09 and T10. | `T12-documents.md` (base `b8671e5`, T10's tip) |
| 6 | O3 and the entries of T09, T10, T11: until T10 the tree case holds an exact allowance for `ai-knowledge`'s clone starts (`PENDING_AI_KNOWLEDGE`: 42 at T11, 10 after T09); T10 removes it and completes O3. | `T11-host-git-rule.md`, "Deviations from the plan"; `T09-gateway-proposals.md`, "Residue"; `T10-gateway-reports.md`, "O3" |
| 7 | New section "If phase 1 lands on `main` second" (phase 2's procedure, steps 1 to 5, and the re-run of phase 2's evidence section); RP1 takes its range from `merge-base main <tip>` and shows a merge commit's resolution (`--cc`). | phase 2 plan, "Base and branches"; probe "RP1 range after a merge" in this plan's evidence file |
| 8 | "First gate", T09 and T10: written before X1's answer, in B1a's form (the user's decision); "What the plan becomes" applies once X1 is in; RP1 also waits for X1's verdict in `x1.md`. | `T09-gateway-proposals.md` and `T10-gateway-reports.md`, "X1's verdict is pending" |
| 9 | T09's and T10's entries: they land only together (T09 alone leaves the report part pushing to the read-only origin). | `T09-gateway-proposals.md`, "Deviations from the plan" 2 |
| 10 | O7 names the case of an integrator's clone whose `main` is strictly behind the host's `refs/remotes/origin/main` (not pushed); a `fix:` commit of T09's code with its regression case closes it. | `T12-documents.md`, "Deviations and findings" 1; `F01-integrator-main-behind.md` |

## Read this first (for the reviewer)

- **Spec change: none needed by this plan.** It follows S-1 (the author's proposed
  wording of what committed text may hold), which the user is asked about with this
  plan. One question for the spec's author concerns later phases only (S-3, last
  section); phase 1 does not wait for it. The choices the spec leaves to the plan,
  with the author's answers (`author-answers.md`), which bind:
  1. C-STATUS: the `knowledge` file carries `project-id=` and `closed-proposal=` beside
     `role=` and `pushed-report=`; the in-sandbox command keeps the old-shape role file
     for its reader outside the repository. Author: plan detail. The review's L6 reads
     the role file as against C-STATUS's last sentence; the plan follows the author
     (the host neither writes nor reads it).
  2. C-STAMP: with no stamped ancestor, `ai_sandbox_project_root` returns the given
     directory itself, links resolved. Author: plan detail, with the `init` case O21
     and a printed line. The review classified it as not plan detail; the plan follows
     the author.
  3. The host-owned repository of C-KNOW is `~/.ai-sandbox/knowledge/main`. Author: plan
     detail. The review asked for a second look under F1: kept, because F1 is closed in
     that repository by O19 (a fetch from a sandbox changes no ref outside its
     namespace) and R10 (the host names its refs in full), and T09 states the author's
     property that its work tree, and so the render, moves only to the remote's `main`.
  4. `ai_sandbox_writable_path` and `ai_sandbox_image_name` in the lib. Author: plan
     detail.
  5. New in this round: `AI_SANDBOX_GIT_TIMEOUT` in the C-GIT block (today's network
     time limit wraps `git` with `timeout`, which cannot run a shell function), and the
     host's record of pushed reports `refs/pushed-reports/<id>/` (F4).
  6. New in round 3: the key `closed-report=<name>` in `status/knowledge` (N1), of
     the same kind as item 1's keys; and the confined fetch as a lib function,
     `ai_sandbox_confined_fetch` (contract block), as the spec's author suggested, so
     that phases 4 and 6 call it instead of extracting it from `ai-knowledge`.
- **Folded** (the phase grew by this): the host install of `ai-delegate` is removed
  (the author's answer to Q3, review F5), in T01 with O22.
- **Unverified assumptions** the plan rests on: A1, A2 and PA6 (settled by X1), A3 (the
  user's check and the migration in B1; expected not to hold before the migration on
  this host), PA13. Everything else in the assumption table was verified in the tree or
  by a probe recorded in the evidence file.
- **Declared dependency** (🟡): the suite gains a dependency on `ast-grep` (in the
  image already, unpinned; the rule's known cases in O3 fail on a version that parses
  differently).

## Who uses it and the states the phase touches

The user on the host starts and enters sandboxes and runs `ai-knowledge sync --all`;
agents inside commit proposals and reports to `~/knowledge`, and the integrator's agent
commits on `main`; the user on the phone is unaffected (nothing here adds a host
command to everyday work).

- Normal: an entry or a start syncs; proposals, reports and the integrator's `main`
  reach the remote; the clone inside is updated from a read-only origin; the result is
  in `sandbox-doctor`.
- Empty: knowledge not configured (no `knowledge` status file, nothing fetched;
  `status/` exists but is empty); a new sandbox with no clone yet (nothing to fetch;
  the in-sandbox command creates the clone at start); a clone with nothing new (the
  sync pushes nothing and says so).
- Invalid input: a branch outside `proposals/` or with a malformed name, a report
  outside `reports/`: refused, named in the status (as today); a directory with no
  stamped ancestor: "no sandbox configured" (as today).
- Failure: remote unreachable: status `offline`, start proceeds, the origin keeps the
  last fetch (as today); the confined container cannot run (no sandbox image yet,
  trigger: `create-ai-sandbox.sh` syncs before it builds the image, tree): status
  `warn` naming the cause, the next sync fetches; `docker exec` into the container
  fails or the confined run or the exec exceeds the time limit (trigger: a container
  that hangs, the same reason today's network time limit exists): `warn`, the start
  proceeds, the next sync retries. The integrator's sandbox started while its
  tombstones are pending and no sync has reached the remote since (trigger: the
  create's sync offline or finding the lock busy, so the origin holds none of the
  remote's reports, O10; B2 re-creates every sandbox): the clone keeps each report and
  its tombstone until a status file lists the report `closed-report=`, which only a
  sync that reached the remote and found the report gone writes (N1).
- Interruption: a sandbox running across the landing (old image, stamp `1`): it is
  entered as today, its host side is synced, nothing is executed in it, and the host
  prints that it must be re-created; a stopped one is refused with the one re-create
  command (I6). A sync killed mid-way: the next one recomputes everything from refs.
  A writer whose container does not run the in-sandbox command after its report was
  pushed (stopped during `sync --all`, or stamp `1`) while the integrator closes that
  report: the host's record of the push keeps it from being published again, and the
  clone drops the ref when its container next runs the command (F4).
- Retry: every sync is idempotent; `closed-proposal=`, `pushed-report=` and
  `closed-report=` are derived again from refs and the host's records at every sync
  (`closed-report=` only by a sync that reached the remote), so a container that missed
  one status file acts on the next.
- Behaviour change, inferred compatible: a clone with uncommitted changes is no longer
  skipped whole. The host sees refs only, so committed proposal branches are pushed;
  the fast-forward of `main` inside is skipped and reported there (knowledge v2 design:
  "a dirty tree is still skipped, never merged" keeps holding for the merge).

## Deferred list

- E1 (egress): **keep**, phase 10 (open).
- E2, added with this plan's commit, as the spec's author worded it:
  **E2 `bin/ai/MANIFEST` would be ignored by git** (noticed while planning phase 1,
  2026-11-11). Failure: `.gitignore` ignores every path named `MANIFEST` (its Python
  packaging section), so C-INSTALL's manifest is skipped by `git add` of its directory
  and missing from a revision exported from a commit. Kept for phase 4: its plan
  adds `!bin/ai/MANIFEST` to `.gitignore`, a one-line change outside the scope line at
  the top of the spec, needed by the contract's fixed name.
  **Keep**, phase 4 (open).

Nothing else is open.

## Where the work happens, and when the host runs it

- Area: the ai-sandbox toolchain (`bin/ai/`, `tests/ai-sandbox/`, the documents of
  T12). One implementer, slot 1 (Zuzia), all twelve tasks in the order "First gate"
  states (T01 to T08, T11, T09, T10, T12; item 5), in one worktree
  `.worktrees/2026-11-11-sandbox-hardening-p1` on branch
  `2026-11-11-sandbox-hardening-p1`, created from the commit that carries this plan.
  The lead adds `.worktrees/` to `.git/info/exclude`. One tree, one suite run at a time
  (1 CPU, 2 GB).
- Why a worktree: until phase 4 every host `ai-sandbox` start refreshes the installed
  helpers from the main checkout's working tree and sources its lib (tree:
  `ai-sandbox-migrate`, finding H3). Edits in the worktree are never read by the host;
  the base keeps running there for the whole phase.
- **Read point RP0**: the user reads this plan, batch B1 and the fixture file it
  names before running B1. B1 runs a copy of the fixture only if its SHA-256 equals
  the one written in B1, so what runs is what was read.
- **Read point RP1**: after the phase review accepts the tree, the gate passes, X1's
  verdict is in `x1.md` with the plan corrected as "What the plan becomes" says
  (item 8), and A3's
  recheck has passed on every host (B1b; the lead's verdict in `a3.md`), and before
  the lead merges the branch into the main checkout. The lead gives the user `<tip>`
  (the commit the gate ran on). The user reads, at the host,
  first every changed path, then the host-executed files task commit by task commit,
  with the resolution of any merge commit (item 7):
  `B=$(git -C ~/dev/public/dev-tools merge-base main <tip>); git -C ~/dev/public/dev-tools --no-pager diff --no-ext-diff --no-textconv --stat $B <tip>`
  and
  `git -C ~/dev/public/dev-tools --no-pager log --reverse -p --cc --no-ext-diff --no-textconv $B..<tip> -- bin/ai`.
  The merge base is the commit on `main` the branch started from (the commit carrying
  this plan) or last merged, so the range holds phase 1's change only, in either order
  of landing. RP1 is taken again on every tip the gate runs on.
  Until phase 4 nothing binds the working tree the host runs to what was read: the main
  checkout is writable from the dev-tools sandbox (H3, open until phase 4). From the
  merge on, the next `ai-sandbox` start, `create-ai-sandbox.sh` run or
  `ai-sandbox-migrate` run refreshes the installed helpers from the merged working
  tree; until then the installed `ai-knowledge` is the old copy (B2 step 1 refreshes
  first). No host step of this phase runs before RP1 except B1; batch B2 follows RP1.
- Each task below names the files the host executes once it has landed.

## If phase 1 lands on `main` second (item 7)

Phase 2 runs in parallel on its own branch from `dd0146a` (the user's request,
2026-11-12; phase 2's plan, "Base and branches"). If phase 1 lands first, nothing here
applies to phase 1. If phase 2 has landed first, phase 1's branch follows phase 2's
second-landing procedure, as that plan numbers it:

1. take `main` in with a merge commit (no rebase: the evidence cites commit ids) and
   resolve any conflict;
2. run `bash tests/ai-sandbox/run-tests.sh`;
3. re-run phase 2's evidence section "Re-run when the other branch lands on `main`"
   (`docs/superpowers/evidence/2026-11-11-sandbox-hardening-p2/2026-11-11-sandbox-hardening-p2-plan.md`),
   its items read in this direction (`<p1 tip>` is phase 1's commit before the merge);
4. if the merge comes before phase 1's review, the review and the gate cover the merged
   tree; if after, the merge commit's delta gets a review of its own and the gate runs
   again on the new tip;
5. RP1 is taken again on every tip the gate runs on, with its `merge-base` range.

## First gate: batch B1 for the user (X1, then A3 and the migration)

T01 to T08 and T11 do not depend on X1 and start at once. T09 and T10 were written
before X1's answer (the user's decision, 2026-11-12, item 8), on the assumption that
B1a passes in full: the transport is the body of `ai_sandbox_confined_fetch` alone, and
"What the plan becomes" below still applies once X1 is in; RP1 waits for that verdict.
T12 runs after T09 and T10, whose behaviour it documents (item 5). T08 lands on the
branch at once, but RP1 waits until A3's recheck has passed on every host. X2, X3 and X4 are not in this batch: the spec lists their
attempts and pass lines but gives no commands (they need a GitHub App, a Bitbucket
repository and the engines set up), so they wait for the plans of phases 5 and 8.

The fixture is in an untracked file, because this repository is public:
`.tmp/security/2026-11-11-sandbox-hardening-p1-x1-fixture.sh` (the lead writes it from
the planner's report). It prepares a repository as in X1, adds refs of the kinds a
clone can hold, runs the control, and undoes itself; it changes only the repository it
is given. Read it before running B1 (RP0).

### B1a, X1: on one host that has the sandbox image

Paste the whole block into bash on the host and paste back everything it prints. The
host-side step is the fetch in the form T09 will use: the clone's real path as the URL,
the root mounted read-only at its own path in a throwaway container of the sandbox
image, the refs delivered below one namespace. Apart from that fetch, the batch runs no
toolchain code.

```bash
bash <<'B1'
set -u
FIXSRC=~/dev/public/dev-tools/.tmp/security/2026-11-11-sandbox-hardening-p1-x1-fixture.sh
X1=$(mktemp -d /tmp/x1.XXXXXX) && cd "$X1" || exit 1
cp "$FIXSRC" fixture.sh && echo "4a4a652eb4dadb4e2a6022d8742349ae1b452f7ee0520baa854edd93efc25d8a  fixture.sh" | sha256sum -c --quiet - || { echo "FIXTURE DIFFERS FROM THE ONE READ: stop"; exit 1; }
echo "== versions"; git --version; docker version --format 'docker {{.Server.Version}}'
IMG=$(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -m1 -E "^ai-sandbox:(base|docker)-u$(id -u)\$")
echo "image: ${IMG:-NONE}"; [ -n "$IMG" ] || exit 0
ROOT=$X1/root; mkdir -p "$ROOT" markers
git init -q --initial-branch=main "$ROOT/knowledge"
git -C "$ROOT/knowledge" -c user.name=x1 -c user.email=x1@localhost commit -q --allow-empty -m one
git -C "$ROOT/knowledge" branch proposal/x1
bash fixture.sh refs "$ROOT/knowledge"
git -C "$ROOT/knowledge" for-each-ref --format='%(objectname) %(refname)' refs/heads | sed 's|refs/heads/|refs/sandbox/x1/heads/|' > want
bash fixture.sh plant "$ROOT/knowledge" "$X1/markers"
git init -q --bare host.git
RUN="docker run --rm -i --pull never --network none --user $(id -u):$(id -g) -v $ROOT:$ROOT:ro --entrypoint git $IMG"
fetch() { git -C host.git fetch -q --no-tags --prune --upload-pack="$RUN upload-pack" "$ROOT/knowledge" '+refs/heads/*:refs/sandbox/x1/heads/*'; }
echo "== A1, A2: the confined fetch, cold then warm (expected: exit 0 twice)"
time fetch; echo "exit $?"
time fetch; echo "exit $?"
echo "== A1: refs delivered (expected: same)"
git -C host.git for-each-ref --format='%(objectname) %(refname)' refs/sandbox/x1 | diff want - && echo same
echo "== refs outside the namespace (expected: none)"
git -C host.git for-each-ref --format='%(refname)' | grep -v '^refs/sandbox/x1/' || echo none
echo "== markers after the fetch (expected: none)"; ls markers | grep . || echo none
echo "== A1 fallback: a bundle written in the container, fetched by the host (expected: exit 0, same, none, none)"
$RUN -C "$ROOT/knowledge" bundle create - --all > sb.bundle; echo "exit $?"
git -C host.git fetch -q --no-tags "$X1/sb.bundle" '+refs/heads/*:refs/sandbox/x1b/heads/*'
git -C host.git for-each-ref --format='%(objectname) %(refname)' refs/sandbox/x1b | sed 's|/x1b/|/x1/|' | diff want - && echo same
git -C host.git for-each-ref --format='%(refname)' | grep -vE '^refs/sandbox/x1b?/' || echo none
ls markers | grep . || echo none
echo "== control (expected: live)"; bash fixture.sh control "$ROOT/knowledge" "$X1/markers"
echo "== A2: docker exec into a running sandbox, if one runs"
S=$(docker ps --format '{{.Names}}' | grep -m1 -- '-agent$'); if [ -n "$S" ]; then time docker exec "$S" true; else echo "no sandbox running"; fi
cd / && rm -rf -- "$X1"
echo "== end of X1"
B1
```

What each line shows, and what a failing result looks like:

| Line | Pass | Failing result and what follows |
|---|---|---|
| fixture check | nothing printed | `FIXTURE DIFFERS FROM THE ONE READ: stop`: the file changed after RP0; nothing ran; tell the lead. |
| `image:` | a tag | `NONE`: X1 did not run; build the image with any `create-ai-sandbox.sh` run and repeat B1a. |
| the two fetches | `exit 0` twice | another exit status: the confined form does not deliver on this host (for example the container cannot read the mount as the host user, PA6, or the engine does not know an option); the bundle lines decide the transport. |
| refs delivered | `same` | a diff: A1 fails in this form; the bundle lines decide the transport. |
| refs outside the namespace | `none` | any ref listed: this host's git lets the served repository create refs the fetch did not ask for (F1); T09 and T10 stop and the transport goes to the planner and the spec's author. |
| markers after the fetch | `none` | any `MARKER-*`: a host process ran something planted in the fixture; I3a fails for this form; T09 and T10 stop; to the spec's author. |
| bundle lines | `exit 0`, `same`, `none`, `none` | used only when the fetch lines fail; their failure leaves no transport: to the spec's author. |
| control | `live` | `INERT`: the fixture did not take, so the `none` lines above prove nothing; X1 is repeated, not passed. |
| A2 | the user's judgement | the warm fetch's `real` time is not acceptable as an addition to every `ai-sandbox` entry: the spec's fallback (A2) would add a second way to run git against a sandbox's clone, which changes C-GIT's "one function": to the spec's author before T09 (review L7). |

### B1b, A3: on every host that has sandboxes

```bash
bash <<'A3'
echo "== A3 on $(hostname)"
[ -f ~/.ai-sandbox/knowledge/config ] && echo "knowledge configured" || echo "knowledge not configured"
for d in ~/.ai-sandbox/*-agent; do [ -f "$d/docker-compose.yml" ] || continue
  printf '%s stamp=%s\n' "${d##*/}" "$(sed -n 's/^SANDBOX_KNOWLEDGE=//p' "$d/.env" 2>/dev/null | tail -1)"; done
echo "-- old-style branches in the clones (expected: none)"
{ find ~/.ai-sandbox/*-agent/knowledge/.git/refs/heads/proposals -type f 2>/dev/null
  grep -l ' refs/heads/proposals/' ~/.ai-sandbox/*-agent/knowledge/.git/packed-refs 2>/dev/null
  grep -l 'refs/heads/proposals/' ~/.ai-sandbox/*-agent/knowledge/.git/HEAD 2>/dev/null; } | grep . || echo none
echo "-- old-style branches on the remote (expected: none)"
[ -d ~/.ai-sandbox/knowledge/main/.git ] && { git -C ~/.ai-sandbox/knowledge/main ls-remote origin 'refs/heads/proposals/*' | grep . || echo none; }
echo "-- integrator named in this host's knowledge configuration"
v=$(sed -n 's/^INTEGRATOR=//p' ~/.ai-sandbox/knowledge/config 2>/dev/null | head -1); echo "${v:-none}"
echo "== end of A3"
A3
```

The A3 part reads the clones' files and asks the remote; it starts no git in a clone.
Pass: every sandbox `stamp=1` and both "old-style" headings followed by `none` (or
knowledge not configured and every stamp `0`).

**The expected path on this host: the migration, once, before RP1.** Seen from the
dev-tools sandbox's clone, A3 does not hold here, so the A3 part will list old-style
branches. Then, on every host whose A3 part listed any, last the host whose B1b output
names an integrator under "integrator named in this host's knowledge configuration"
(the migration reads that line and closes the old remote branches only there):

1. If the knowledge remote is reached over ssh, load the key once:
   `ssh-add -l >/dev/null || { eval "$(ssh-agent -s)"; ssh-add; }`
2. Run the migration from the dev-tools checkout as it is now (before this phase's
   merge): `~/dev/public/dev-tools/bin/ai/ai-sandbox-migrate-knowledge`.
   - Asked once, for all running sandboxes that are stale together, whether to stop
     and re-create them: answer `y` only if none of them is in use; otherwise answer
     `n`, stop those not in use with `ai-sandbox-stop` in their project directory, and
     run again. Any left running is skipped and the run is not finished.
   - On the integrator's host, asked to delete the old branches on the remote after
     merging them into `main` with `-s ours`: answer `y`.
3. It has finished when its output ends with `failed:` and `skipped (running, not
   stopped):` followed by nothing, no line starts with `!!`, and no line starts with
   `Clones left as they were`. Otherwise follow what it prints and run it again.
4. Run B1b again on every host. A3 holds when every host passes.

The migration is the base design's code: it runs host git in the clones, as every
`ai-sandbox` start does today, so it adds no exposure the base does not already have.
Paste back B1b's output before and after, and the last ten lines of each migration
run.

What the plan becomes.
- B1a all pass: `ai_sandbox_confined_fetch` (T09) fetches in exactly B1a's form,
  through C-GIT's function.
- The fetch lines fail and the bundle lines pass: `ai_sandbox_confined_fetch` (T09)
  fetches from a bundle the confined git writes to standard output into a host-owned file,
  with the same namespace and the same check of refs outside it (the spec's fallback);
  nothing else changes.
- Refs outside the namespace, a marker after a fetch, or both transports failing: T09
  and T10 stop; to the spec's author.
- A2 not accepted: to the spec's author before T09 (above).
- A3 holds on every host after the migration: T08's removal stands and RP1 may follow
  the gate. If the migration cannot finish on some host, RP1 waits and the lead brings
  its output to the user, with two choices: finish by hand as its messages say, or keep
  the script, which runs host git in the clones and so needs a spec change (I3a).
- The lead records the verdicts (not the logs, which stay under `.tmp/security/`) in
  `x1.md` and `a3.md` in the evidence directory and asks the spec's author to update
  the status of A1 to A3 in the spec.

## Contracts

Exported by `bin/ai/ai-sandbox-lib.sh`; later phases and other tasks plan against these
lines.

```bash
# C-GIT. <root>: a directory whose own path no sandbox can change; mounted read-only at
# the same path, as the container's only mount; <subdirectory> is entered inside.
ai_sandbox_confined_git <root> <subdirectory> <git subcommand> [arguments...]
#   exit: git's; 125 when no sandbox image exists or the container cannot start
#   as a fetch's remote program: the fetch's URL is <root>/<subdirectory>, and the
#   program git runs for it ends in this function with upload-pack
ai_sandbox_host_git <repository> <git subcommand> [arguments...]
ai_sandbox_host_git - <git subcommand> [arguments...]   # no repository is discovered
#   exit: git's; 3, without starting git, when ai_sandbox_writable_path <repository>
#   variables set for the call reach git; none reaches the confined container
# Both: AI_SANDBOX_GIT_TIMEOUT=<seconds> in the caller's environment bounds the run;
#   exit 124 when it expires
ai_sandbox_confined_fetch <repository> <prefix> <root> <subdirectory> <ref pattern>...
#   every fetch from a tree a sandbox can write: each <ref pattern> refs/<name>/* of
#   <root>/<subdirectory>, served through ai_sandbox_confined_git, lands in the
#   host-owned <repository> as <prefix>/<name>/*, pruned below <prefix>; no ref of
#   <repository> outside <prefix> changes
#   <prefix>: a full ref name below refs/, outside refs/heads/ and refs/tags/, that
#   holds only refs this function fetched from that one tree (knowledge: refs/sandbox/<id>)
#   exit: as ai_sandbox_host_git (3 for a sandbox-writable <repository>); 125, 124 as above
ai_sandbox_writable_path <path>
#   0 when <path>, links resolved, lies inside a bind source that a sandbox's compose
#   file mounts without :ro, or inside a project directory a stamp names; 1 otherwise
ai_sandbox_image_name <base|docker>                     # ai-sandbox:<variant>-u<uid>
# C-STAMP
ai_sandbox_project_root [dir]   # nearest stamped ancestor, else dir itself with
                                # links resolved; 1: no dir
ai_sandbox_create_root [dir]    # create-ai-sandbox.sh only: the nearer of the stamped
                                # ancestor and the ancestor holding .git, else dir
                                # itself with links resolved (item 1)
```

C-KNOW and C-STATUS data, as phase 9 will find them (the sandbox id is the project id,
the sandbox directory's name without `-agent`):

```
~/.ai-sandbox/knowledge/main                       the host-owned repository; its work tree
                                                   moves only to refs/remotes/origin/main
  refs/remotes/origin/*                            the remote's heads, fetched by the host
  refs/origin-reports/*                            the remote's refs/reports/*, fetched by the host
  refs/sandbox/<id>/heads/*                        a sandbox's branches, fetched through C-GIT
  refs/sandbox/<id>/reports/*                      its refs/reports/*
  refs/sandbox/<id>/reports-closed/*               its refs/reports-closed/*
                                                   (the three: the clone's refs at the last
                                                   successful fetch, pruned)
  refs/pushed-reports/<id>/<name>                  the commit the host pushed for that report;
                                                   dropped once refs/sandbox/<id>/reports/<name> is gone
<sandbox dir>/knowledge-origin.git                 bare, host-written; ro at /run/ai-sandbox/knowledge-origin.git
  refs/heads/*      = refs/remotes/origin/* of the host-owned repository
  refs/reports/*    = refs/origin-reports/*, in the integrator's only
  (no other ref)
<sandbox dir>/status/knowledge                     host-written; ro at /run/ai-sandbox/status/knowledge
  <YYYY-MM-DDTHH:MM:SS> <ok|warn|refused|offline> <message>
  role=<proposals|integrator>
  project-id=<id>
  closed-proposal=<branch> <commit>                one per local branch closed at that commit
  pushed-report=<name>                             one per report whose record equals the commit
                                                   the sandbox holds
  closed-report=<name>                             integrator only: one per tombstone in its
                                                   namespace whose report this sync's completed
                                                   fetch of the remote's reports no longer finds
/usr/local/bin/sandbox-knowledge-sync              in the image; no arguments; exit 0; outcome on stdout
<sandbox .env> SANDBOX_KNOWLEDGE=2                 knowledge configured; 0 when not
```

A fetch through C-GIT (`ai_sandbox_confined_fetch`) creates or updates refs of the
host-owned repository only below `refs/sandbox/<id>/` (F1). The host names every ref
of that repository by its full name; a branch name appears only where git takes one (`checkout`, `symbolic-ref`). A removed
sandbox's namespace and records stay until a sandbox of the same id fetches again
(Left out). A report ref is never moved once made (PA12), so a record is per name and
commit and `pushed-report=` keeps C-STATUS's shape; `closed-report=` names the report
alone for the same reason. Every removal inside the clone follows a key the host wrote
(`closed-proposal=`, `pushed-report=`, `closed-report=`), never the origin's content
alone (N1).

## Obligations

Executable checks name the command and the result; Read checks name the place. Each
task cites the keys it discharges; "completes" marks the task whose evidence closes a
key cited by several. Evidence: one file per task, `t<NN>-<slug>.md`, one entry per key.

- **O1 C-GIT, confined.** `ai_sandbox_confined_git` starts exactly one `docker run`
  with `--rm`, `-i`, network none, no image pull, the host's uid and gid, the image's
  entrypoint not run, the image of `ai_sandbox_image_name` (base when present, else
  docker), the root as the only mount, read-only and at its own path, no `--env-file`
  and no variable of the sandbox's `.env` or of the caller, git working in
  `<root>/<subdirectory>` inside; standard input reaches git, git's standard output
  comes back, and its exit status is git's (cases: 0, a git failure, no image: 125,
  `AI_SANDBOX_GIT_TIMEOUT` expiring: 124). Check: `bash tests/ai-sandbox/test-confined-git.sh`
  ends `0 failed`; its cases assert each property from the stub's recorded arguments.
  Read: T09's remote-program form has the options of B1a's `RUN` and `fetch` lines.
- **O2 C-GIT, host.** `ai_sandbox_host_git` refuses, with status 3 and without
  starting git, a repository in a read-write bind source of a sandbox (cases:
  `<sandbox>/knowledge`, a link pointing into it, a subdirectory of a stamped project)
  and runs a host-owned one (cases: `~/.ai-sandbox/knowledge/main`,
  `<sandbox>/knowledge-origin.git`); with no `~/.ai-sandbox`, as inside a sandbox,
  `ai-knowledge proposals --repo ~/knowledge` lists as before (the knowledge-integrate
  skill's use); its `-` form discovers no repository: with the working directory inside
  a project whose own configuration a sandbox wrote (the case of PA1; the inputs are in
  the test), `ai-knowledge init` and `ai-knowledge sync` reach the configured remote;
  `AI_SANDBOX_GIT_TIMEOUT` expiring gives 124 and today's network-failure report.
  Check: `bash tests/ai-sandbox/test-confined-git.sh` `0 failed` with these cases.
- **O3 The structural rule** (C-GIT; F2). A rule kept in the repository reports every
  command in a bash file under `bin/ai` whose name or any argument is the word `git`,
  bare or with a path, quoted or not, except three forms that start no git
  (`require git`, `hint git`, `command -v git`), and the suite fails for a report
  outside the bodies of the two C-GIT functions. Named exceptions, by path: the
  in-image programs `bin/ai/ai-delegate` and `bin/ai/sandbox-knowledge-sync`, neither
  a host helper (O22). Check: `bash tests/ai-sandbox/test-host-git.sh` `0 failed`,
  whose cases are: a known-case file with one start of each form (direct;
  path-qualified; `command git`; a wrapper with options of its own; an
  environment-prefixed start in a brace group of a condition; a start through two
  wrappers; a quoted command name in double quotes, in single quotes, and quoted with
  a path; a quoted argument of a wrapper) gives exactly 10 reports, and its three
  exempt forms and a heredoc body give 0; an extensionless file is scanned; every
  file under `bin/ai` whose name ends `.sh` or whose first line names bash or sh is parsed by the rule or is a named exception
  (a new file that is neither fails the case); each named exception is absent from
  `ai_sandbox_helpers`; `bin/ai` gives no report outside the two bodies (item 6: until
  T10 this case holds an exact allowance for `ai-knowledge`'s clone starts,
  `PENDING_AI_KNOWLEDGE` in `test-host-git.sh`, 42 at T11 and 10 after T09; T10 removes
  the allowance, so at the phase's end the case is as written); a missing
  `ast-grep` fails the file instead of skipping it. On the base the rule gives 123
  reports, 106 of them starts (evidence, "Structural search").
- **O4 C-STAMP lookup.** `ai_sandbox_project_root` starts no git process (a recording
  `git` first on `PATH` sees no call) and returns: the project for the project
  directory and for any subdirectory; the sandboxed parent for a repository below it
  that has no sandbox of its own; the directory itself, links resolved, when no
  ancestor is stamped;
  not a stamp whose `project-path` names another directory; status 1 for a missing
  directory; a stamp written by today's function is still found when the project is
  reached through a linked parent (today it stored the resolved path for a repository
  and the unresolved one otherwise, tree). Check: `bash tests/ai-sandbox/test-identity.sh`
  `0 failed`.
- **O5 Create's resolution and identity.** `create-ai-sandbox.sh` resolves through
  `ai_sandbox_create_root`: from a subdirectory of a repository without a sandbox, the
  repository; for a repository below a sandboxed parent, the repository; from a
  subdirectory of a sandboxed plain directory, that directory; a plain directory,
  itself; the ids of the repository and plain-directory cases equal today's, except
  that an unstamped plain directory reached through a link resolves to its resolved
  path, as `ai_sandbox_project_root`'s fallback does (item 1; a stamp of either form
  written today is still found through the link, O4). `.env`'s
  `HOST_GIT_NAME` and `HOST_GIT_EMAIL` come from the global git configuration also
  when the project's own sets other values; no git process runs in the project.
  Check: `bash tests/ai-sandbox/test-create-identity.sh` `0 failed`.
- **O6 Identity and role do not come from the tree** (closing check 3; H8, I3d). With
  the inputs a sandbox can write in the project and in its clone set to name another
  project and another role (the list is in the test): `ai-sandbox --print-context`,
  `ai-knowledge sync <project>`, `sync --all` and a create run address the stamped
  sandbox; it syncs as `proposals` and its `main` does not reach the remote;
  `_sync-clone` takes its project and sandbox from the parent and resolves nothing.
  Check: `bash tests/ai-sandbox/test-knowledge.sh` `0 failed`, these cases.
- **O7 The gateway** (closing check 2; C1, H7, I2, I3a). Against a clone prepared as in
  X1 that also carries changes a sandbox can make to its configuration and its refs
  (the list is in the test), `sync <project>` and `sync --all`: leave no marker; put
  in-scope proposals and reports on the configured remote and nothing anywhere else;
  refuse a proposal that is in scope only against a `main` the clone supplies; push the
  integrator's `main` only as a descendant of the host's own
  `refs/remotes/origin/main` (cases include a clone whose `main` is strictly behind
  the host's, after the remote's `main` moved: it is not pushed, item 10); push nothing as a forced update (the stub remote records
  every update of the run, and none is forced); delete remote refs only as today
  (leased). A recording `git` first on `PATH` shows no host git process whose
  repository, `-C` or working directory lies in `<sandbox>/knowledge` or the project
  (the stub's own git, standing in for the container, carries a mark and is left out).
  Check: `bash tests/ai-sandbox/test-knowledge.sh` `0 failed`, these cases.
- **O8 No host write below `<sandbox>/knowledge`** (H4, clone part; I3c). Across
  `sync <project>`, `sync --all`, `init`, `status` and a create run, with the container
  reported not running so that no in-sandbox command runs, a listing of
  `<sandbox>/knowledge` (path, type, size, mode, mtime, content hash; links not
  followed) is the same before and after, and links placed at each path where the base
  design wrote below the clone (the list is in the test) leave their targets
  unchanged. Check: `test-knowledge.sh` `0 failed`, these cases.
- **O9 C-STATUS.** Every create makes `<sandbox>/status/` and its compose file binds it
  read-only at `/run/ai-sandbox/status`, knowledge configured or not; line 1 of
  `status/knowledge` matches
  `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} (ok|warn|refused|offline) .+$`
  in an `ok`, a `refused`, an `offline` and a `warn` case, followed by the keys of the
  contract; `ai-knowledge status` and the `sync --all` table show that line, with
  control characters removed; the generated `sandbox-doctor`, run against a fixture
  status directory, prints line 1 of every file there with its age. Check:
  `test-knowledge.sh` `0 failed`, these cases.
- **O10 The origin.** With knowledge configured, a create makes `<sandbox>/knowledge/`
  and an empty bare `<sandbox>/knowledge-origin.git` before any start, also when its
  sync step fails or finds the lock busy, and the compose file binds the origin
  read-only at `/run/ai-sandbox/knowledge-origin.git` beside the clone's read-write
  mount; after a sync the origin's `refs/heads/*` equal the host's
  `refs/remotes/origin/*`, only the integrator's origin has `refs/reports/*`, equal to
  the remote's, and no origin holds any other ref. Check: `test-knowledge.sh`
  `0 failed`, these cases.
- **O11 The in-sandbox command.** `sandbox-knowledge-sync`, run in a fixture home:
  creates the clone on `main` when absent; adopts a clone of the base design (origin
  URL replaced by the origin's path, local branches and unpushed commits kept, the old
  `.sync-status` removed); fetches; fast-forwards `main` unless the tree is dirty or
  the integrator's `main` is ahead, and reports which; deletes a branch listed
  `closed-proposal=` only while its tip is the listed commit; for a writer deletes a
  report listed `pushed-report=`; for the integrator fetches proposal branches and
  reports, and deletes a report and its tombstone only while the status file lists it
  `closed-report=` (an origin without the report is no such signal: it may not have
  received the remote's reports yet, O10); writes `.git/ai-knowledge-role` as
  `<role> <project-id>` and the advisory pre-commit hook; leaves a non-empty `~/knowledge` that is no clone untouched and
  says so; exits 0 in every case. Check: `test-knowledge.sh` `0 failed`, these cases.
- **O12 Who runs it.** The generated entrypoint runs `sandbox-knowledge-sync` when
  `SANDBOX_KNOWLEDGE=2`, not otherwise, and the start does not fail when it does; after
  a sync the host runs it with `docker exec` only in a running container whose stamp is
  current, as the sandbox's own user, without a terminal and with standard input
  closed, under `AI_SANDBOX_GIT_TIMEOUT`, and prints its standard output and standard
  error with control characters removed. Check: `test-knowledge.sh` and
  `test-plugins.sh` `0 failed`, these cases.
- **O13 The workflow is kept.** Every behaviour of the base `test-knowledge.sh` still
  holds, except the migration script's. Check (Read): `diff <(git show 4d6f677:tests/ai-sandbox/test-knowledge.sh | command grep '^# ---') <(command grep '^# ---' tests/ai-sandbox/test-knowledge.sh)`;
  the evidence explains every changed header; the removed ones are exactly the four
  migration headers of the base (lines 455, 498, 546, 591) and the old-style-branch
  half of line 272; reworded ones include "dirty is skipped" (line 118) and "moved
  aside, never removed" (line 900); `test-knowledge.sh` `0 failed`.
- **O14 Stamp 2.** Create writes `SANDBOX_KNOWLEDGE=2` with knowledge configured and
  `0` without; a stopped sandbox stamped `1` or unstamped is refused by `ai-sandbox`
  and `ai-sandbox-restart` with `create-ai-sandbox.sh <project>` as the only repair
  named; a running one stamped `1` is entered, its host side synced, nothing executed
  in it, and the host says to re-create it; `sync --all` lists it as stale with the
  re-create command; the generated doctor handles `2`. The stamp-`1` cases start from
  a sandbox directory as the base left it (no `status/`, no `knowledge-origin.git`),
  the state of every existing sandbox at its first entry after the merge. Check:
  `test-knowledge.sh` `0 failed`, these cases.
- **O15 The migration script is gone** (A3; the hosts' recheck is RP1's condition,
  not this obligation's). Check: `git ls-files bin/ai/ai-sandbox-migrate-knowledge`
  prints nothing; `bash tests/ai-sandbox/run-tests.sh` has no case naming it.
- **O16 Documents and the register.** Read: `PROJECT_MAP.md` (rows for `ai-knowledge`,
  the lib with C-GIT and C-STAMP, `sandbox-knowledge-sync`, the new test files; the
  `ai-delegate` row says it is installed in the image only; no row for the migration
  script; a coupling-register row for `.git/ai-knowledge-role`, written by
  `sandbox-knowledge-sync`, read by the `propose-rule` skill of the knowledge
  repository, with a `# reads-outside:` marker at the writer; the register's stated
  search for `reads-outside:` is one that also reads extensionless files,
  `git grep -n 'reads-outside:'`, and it finds that marker; the `refs/reports` row still
  names where `REPORT_RE` is); `docs/shared-knowledge.md` (the sync, the status file, stamp
  `2`, re-creation as the one repair); `.agents/skills/knowledge-integrate/SKILL.md`
  (reads the status from `/run/ai-sandbox/status/knowledge`); the usage text of
  `create-ai-sandbox.sh`, its compose comments and the header of `ai-knowledge` (no
  host clone of, or write into, `~/knowledge`).
- **O17 One rule.** The closed and empty classification and the two name patterns
  exist once, on the host; the in-sandbox command takes closed branches, pushed
  reports and closed reports from the status file. Check:
  `command grep -rnaE 'PROPOSAL_RE=|REPORT_RE=|first-parent' bin/ai` lists lines of
  `bin/ai/ai-knowledge` only.
- **O18 Failure and interruption states.** Each state of "Who uses it" has a case:
  offline (start proceeds, origin keeps the last fetch, status `offline`); no sandbox
  image (status `warn` naming it, nothing fetched); lock busy (`warn`); `docker exec`
  failing (`warn`); the confined run or the `docker exec` reaching
  `AI_SANDBOX_GIT_TIMEOUT` (`warn`, the start proceeds); a dirty clone (committed
  proposals pushed, `main` not fast-forwarded inside, reported by the command and the
  doctor); a pending close of a report (N1): the integrator's clone holds a report
  and its tombstone, the remote holds the report, the first sync fails (offline, and
  in a second case the lock busy), the container is started and its command run: both
  refs are still in the clone and the report still on the remote; the next sync that
  reaches the remote deletes the report there, lists it `closed-report=`, and the
  command then removes both refs. Check: `test-knowledge.sh` `0 failed`, these cases.
- **O19 A fetch from a sandbox stays in its namespace** (F1; C-KNOW, goal bullet 2,
  I7). After `sync <project>` and `sync --all` of a clone prepared as in X1 that also
  holds refs of every kind a clone can hold (the list is in the test): every ref of
  `~/.ai-sandbox/knowledge/main` outside `refs/sandbox/` and `refs/pushed-reports/` is
  one the host wrote from the remote (`refs/heads/main`, `refs/remotes/origin/*`,
  `refs/origin-reports/*`), each equal to the stub remote's after the sync; its `main`
  and its work tree equal the remote's `main`, and so does the render; each origin
  holds exactly the refs of O10; the namespace of a second sandbox,
  `refs/sandbox/<other id>/`, is the same after `sync <project>` of the first as
  before (N8). Called directly, `ai_sandbox_confined_fetch` with a served tree holding
  refs of every kind, into a repository whose second prefix already holds refs,
  delivers each pattern's refs as `<prefix>/<name>/*`, drops below `<prefix>` at the
  next call a ref the served tree no longer holds, changes no ref outside its
  `<prefix>` and leaves the second prefix as it was; its exit status is 3, with no git
  started, for a sandbox-writable `<repository>`, 125 with no image and 124 when
  `AI_SANDBOX_GIT_TIMEOUT` expires (the contract's lines). A
  negative case in each file runs the same fetch without T09's confinement and sees a
  ref outside the namespace, so the check is shown able to fail. Check:
  `test-knowledge.sh` and `test-confined-git.sh` `0 failed`, these cases.
- **O20 A report is published once** (F4; "what they do today" for reports). After a
  writer's report was pushed, with its container not running the in-sandbox command
  (stopped, and in a second case stamp `1`), the integrator closes the report and the
  remote drops it; the following `sync --all` and `sync <project>` do not push it
  again and still list it as `pushed-report=`; once the clone no longer holds it, its
  record is gone after the next sync. Check: `test-knowledge.sh` `0 failed`, these
  cases.
- **O21 The integrator record** (the author's answer to Q2).
  `ai-knowledge init --integrator DIR`, run before DIR's sandbox exists, records the
  value the lookup returns for DIR once `create-ai-sandbox.sh DIR` has created it, for
  DIR a repository root, also when DIR is reached through a linked parent; before it
  records, `init` prints the directory and the sandbox it names, or that none exists
  yet and that the sandbox created for exactly that directory takes the role. Check:
  `test-knowledge.sh` `0 failed`, these cases.
- **O22 In-image programs are not installed on the host** (folded: the author's answer
  to Q3, review F5). `ai_sandbox_helpers` lists neither `ai-delegate` nor
  `sandbox-knowledge-sync`; a create run over a home whose `~/.ai-sandbox/bin` holds a
  copy of `ai-delegate` from an earlier run leaves none there and prints one line
  saying so. Check: `bash tests/ai-sandbox/test-helpers.sh` `0 failed`, these cases;
  the exceptions case of O3.

Phase-level, cited by no task:

- **G The gate**, once on the tree the phase review accepts, by the implementer the
  lead names or a runner: `bash tests/ai-sandbox/run-tests.sh` (every file `0 failed`
  except `test-delegate.sh`, whose only failures are cases 54 and 59, D15),
  `bash tests/ai-sync/test-sync.sh`, `bash tests/git-hooks/test-hooks.sh` (needs
  gitleaks), `python3 -m unittest tools.context_statusline.test_statusline`.
- **R1 to R11, residue**, run by the phase review (commands from the repository root of
  the result):
  - R1 git starts: the rule of O3 over `bin/ai`: no report outside the bodies of the
    two C-GIT functions and the named exceptions.
  - R1b what no structural rule sees (F2; N4: it also matches a quoted or
    path-qualified command name):
    `command grep -rnaE '(^|[^A-Za-z0-9_.-])git(["'"'"']?([[:space:]]|$))' bin/ai`, less the lines
    the rule of O3 reports (exempt forms included): each remaining line is a comment,
    the text of a message, usage or hint, a Markdown file under `bin/ai/knowledge-seed/`,
    or inside a heredoc whose body runs in the container (the doctor, the bashrc, the
    Dockerfile). The review reads each. Base: 177 lines, 57 not reported, all of those
    four kinds (evidence, "R1b on the base"; the same 177 lines as round 2's pattern).
  - R2 `command grep -rnaF '.sync-status' bin tests tools .agents PROJECT_MAP.md README.md docs/shared-knowledge.md verify-ai-sandbox-on-host.sh`:
    only `bin/ai/sandbox-knowledge-sync` (removing the base design's file) and the
    `test-knowledge.sh` cases on that removal.
  - R3 `command grep -naF 'ai-knowledge-role' bin/ai/ai-knowledge bin/ai/ai-sandbox-lib.sh`: empty.
  - R4 `command grep -rnaF 'migrate-knowledge' bin tests tools .agents PROJECT_MAP.md README.md docs/shared-knowledge.md verify-ai-sandbox-on-host.sh`:
    empty (`docs/superpowers/` keeps its history on purpose).
  - R5 `command grep -rnaE '"SANDBOX_KNOWLEDGE": *"1"|SANDBOX_KNOWLEDGE=0\|1' bin docs/shared-knowledge.md`: empty.
  - R6 `command grep -rnaF 'rev-parse --show-toplevel' bin tools`: only `bin/ai/ai-delegate`.
  - R7 `command grep -naE '\$(CLONE|iclone)\b|\$sb/knowledge([^-]|$)' bin/ai/ai-knowledge`:
    only the root argument of the confined fetch and the existence test before it,
    named by line in the review.
  - R8 `command grep -naE 'info/exclude|hooks/pre-commit|> *"\$CLONE' bin/ai/ai-knowledge`: empty.
  - R9 `command grep -naF 'ai_sandbox_project_root' bin/ai/ai-knowledge`: only the
    user-facing entries (`init --integrator`, `sync <dir>`, `status <dir>`), none in
    `cmd_sync_clone`.
  - R10 host refs by short name, and the last-fetch record (F1):
    `command grep -naE '\b(git|git_net|ai_sandbox_host_git)\b[^#]*[[:space:]"'"'"'](origin/[A-Za-z$"]|main([[:space:]"'"'"':.]|$))' bin/ai/ai-knowledge bin/ai/ai-sandbox-lib.sh`:
    only the text of messages and hints and a branch name given to `checkout`, named by
    line in the review. Base: 28, all in `ai-knowledge`; none in the lib, which gains
    the confined fetch (evidence S24). And
    `command grep -rnaF 'FETCH_HEAD' bin/ai`: empty. Base: empty (evidence S26).
  - R11 forced pushes (I2, review L9):
    `command grep -naE '\b(git|git_net|ai_sandbox_host_git)\b[^#]*[[:space:]]push([[:space:]]|$)' bin/ai/ai-knowledge bin/ai/ai-sandbox-lib.sh | command grep -E -- '--force([^-]|$)|--mirror|[[:space:]]-f([[:space:]]|$)|[[:space:]]"?\+(refs|[$A-Za-z])'`:
    empty (`--force-with-lease` deletions stay, as today). Base: empty (evidence S25).
- **H Host acceptance** (closing check 4), after RP1, from batch B2: no marker on the
  host after a sync of a re-created sandbox carrying the fixture, with the fixture's
  control `live` inside; no ref of `~/.ai-sandbox/knowledge/main` outside the host's
  own namespaces added, removed or moved by that sync; its
  `status/knowledge` says `ok`; `sandbox-doctor` inside shows it with its age. The
  lead records the verdict in `host.md` in the evidence directory.

## Impact set

Searches are in the evidence file under the names given here, with their exact
commands and output. Bash has no compiler, so the structural search is the static
enumeration; it was checked on a known case and its silent failure mode is recorded.

| Changed | Category | Search | Result | Dependants and their fate |
|---|---|---|---|---|
| Host git starts | static | ast-grep rule of O3, evidence "Structural search" | 123 reports, 106 starts | `ai-knowledge` 75 (T01, T09, T10), `ai-sandbox-migrate-knowledge` 26 (T08), `create-ai-sandbox.sh` 2 (T01), `ai-sandbox-lib.sh` 1 (T02), `ai-delegate` 2 (kept: in-image; its host install removed, T01). The 17 other reports are the exempt forms (`hint git` 15, `require git`, `command -v git`). Residue R1, R1b |
| Host helper list (`ai-delegate` leaves it) | static, outside | S23 | 5 | lib:203 definition (T01); create:2712 install loop, which also removes an earlier installed copy (T01); `ai-sandbox-migrate`:36 refresh, unchanged (it adds, never removes; every sandbox is re-created in B2, so create runs on every host); test-knowledge.sh:16, 457 unchanged. Outside: every host's `~/.ai-sandbox/bin/ai-delegate` copy (removed by the next create, O22) |
| Host refs named by short name, `FETCH_HEAD` | static, one file; strings | S24, S26 | 28, 0 | ai-knowledge's git calls in the host checkout and the clone (T01, T09, T10); in the host-owned repository every revision becomes a full ref name; `FETCH_HEAD` is used nowhere in `bin/ai` today and stays so. Residue R10 |
| Forced pushes | static | S25 | 0 | none today; O7 and R11 keep it so |
| `ai_sandbox_project_root` | static | S1 | 14 | create:369 (T02, via `ai_sandbox_create_root`), ai-knowledge:191, 192, 968, 987, 1088 (T02; 968 stops resolving), lib:126 `ai_sandbox_require_ctx`, test-identity.sh 3 cases (T02). Residue R9 |
| `ai_sandbox_require_ctx` (inherits the lookup) | static | S2 | 7 | `ai-sandbox`, `-stop`, `-restart`, `-attach`, `-rm` (asks before removing, naming the sandbox), `-account`: no edit; O4 covers the lookup |
| Knowledge stamp functions | static | S3 | 29 | lib 5, ai-knowledge 3, `ai-sandbox` 1, `ai-sandbox-restart` 1 (T07); migrate-knowledge 1 (T08); test-knowledge.sh 18 (T07, T08) |
| `sync_clone` and its helpers (`tip_state`, `ff_main`, `install_hook`, `set_status`, `move_aside` of the clone, `record_integrator`'s clone check, `sync_project_clone`, `cmd_sync_clone`) | static, one file | S19 | 32 | all in `ai-knowledge` (T04, T09, T10); `move_aside` of the host checkout in `init` stays. Residue R7, R8 |
| `git_net` | static | S13 | 20 | ai-knowledge only: becomes a call of `ai_sandbox_host_git` under `AI_SANDBOX_GIT_TIMEOUT` (T01); its clone uses go (T09, T10) |
| Image tag | duplicated | S22, corrected (item 4; the exact command and its known case are in the T01 evidence, "S22") | 3 | create:529, 530 and `ai-sandbox-extensions`:37 (the plan's first S22 named create's variables and missed the third): one definition `ai_sandbox_image_name` (T01, T03). The corrected search, with its known case, is a build check in `test-identity.sh` (T01 evidence, "S22"); expected on the result: no line |
| `.sync-status` | strings | S5 | 27 | create 1602-1604 doctor (T04); ai-knowledge 15, 30, 618, 696, 730-731, 1067, 1091, 1098 (T04, T09); test-knowledge.sh (T04, T09); knowledge-integrate skill:26 (T12); shared-knowledge.md:248 (T12). Residue R2 |
| `.git/ai-knowledge-role` | strings, outside | S6, S12 | 9; 2 | written by ai-knowledge:732 and read by its hook:649 (move into `sandbox-knowledge-sync`, T06, T09); read by the doctor create:1614 (T04); read outside by the knowledge repository's `skills/propose-rule/SKILL.md:38` and `proposals/README.md:13`, and their seed copies: old shape kept (T06), register row (T12). Residue R3 |
| `SANDBOX_KNOWLEDGE` values | strings, stored data | S7 | 23 | create:2218 writer, doctor:1598-1623, compose:2306, lib:85 (T07); tests (T07, T08); shared-knowledge.md:105 (T12); every existing sandbox's `.env` (`1`): refused until re-created, B2. Residue R5 |
| `ai-sandbox-migrate-knowledge` | strings | S8 | 16 | lib:119, ai-knowledge:742, 1059, 1061, doctor:1623 (T08); tests (T08); PROJECT_MAP.md:24, shared-knowledge.md:44, 121 (T12). Residue R4 |
| `_sync-clone` | strings | S9 | 6 | ai-knowledge:1024, 1232 (T02); test-knowledge.sh 372-375 (T02) |
| Knowledge strings in create | strings | S17 | 42 | usage 175-211, step 955-963, environment block 1050-1056, entrypoint grant 1497-1503 (unchanged: `~/knowledge` keeps its path), doctor 1598-1623, `.env` 2215-2218, compose 2306, 2361-2372, summary 2848: T04, T05, T06, T07, T12 |
| Mount targets in a sandbox directory | static | S18 | 9 | `prepare_targets`, `link_skills_into` keep writing outside the clone (phase 9's); `ai_sandbox_state_dirs` gains `status` and is used by create and `ai-sandbox-account reset` (T04) |
| New names | strings | S20, S20b, S20c | 0, 0, 0 | `/run/ai-sandbox`, `knowledge-origin`, `refs/sandbox/`, `refs/origin-reports`, `refs/pushed-reports`, `sandbox-knowledge-sync`, `AI_SANDBOX_GIT_TIMEOUT`, `closed-report` and the new lib functions (`ai_sandbox_confined_fetch` among them) collide with nothing: additions, no residue |
| Project root through git | duplicated | S10 | 2 | lib:55 (T02); `ai-delegate`:28 (in-image, kept). Residue R6 |
| Closed classification, name patterns | duplicated | S11 | 4 | ai-knowledge only; the in-sandbox command would be a second user, so it reads `closed-proposal=` instead (O17) |
| `reads-outside:` markers | outside | S21 | 4 | ai-knowledge:634 on `REPORT_RE` stays where `REPORT_RE` stays; a new one at the role-file writer (T06); `PROJECT_MAP.md`:46 states a search that reads only `*.py` and `*.sh` and so misses both: replaced (T12, O16) |
| Outside the repository: knowledge remote | outside | coupling register, `refs/reports` row | - | ref names `main`, `proposal/*`, `refs/reports/*`, `refs/reports-closed/*` unchanged; pushes still non-forced, deletions still leased |
| Outside: the host's own state | outside | tree, `~/.ai-sandbox` layout | - | `~/.ai-sandbox/knowledge/main` gains `refs/sandbox/*`, `refs/pushed-reports/*` and `refs/origin-reports/*` (extension; nothing reads it but `ai-knowledge`); every sandbox directory gains `status/` and `knowledge-origin.git`; clones of the base design are adopted inside (O11); `ai-sandbox-migrate` reads none of it and `ai-sync` reads only `knowledge/config` (tree: `knowledge_owns_brain`) |
| Outside: Python in `tools/` | static | S15 | 0 | no process start, so no git |
| Reliance on an invariant | - | none possible | - | "the host clones and writes the clone" is relied on in wording only (doctor's "clone not synced yet", the skills' "the host does that on the next sync", still true for pushes); the spec's I3a and the module tests are the net |

## Tasks

Each task ends with its targeted tests and `bash tests/ai-sandbox/run-tests.sh`
(about 2.5 minutes here), and commits on the branch with its evidence file. "Host
runs" lists what the host executes from this task once RP1 has landed it.

- **T01 host-git.** Add `ai_sandbox_host_git` (with the contract's time limit),
  `ai_sandbox_writable_path` and `ai_sandbox_image_name` to the lib; route every git
  start in `ai-knowledge` that concerns the host checkout, a `--repo` directory or a
  URL alone through it (`git_net` included); create reads the host identity from the
  global configuration through the no-repository form and takes its image tag from the
  lib. Clone-side starts are left for T09 and T10. **Folded** (the author's answer to
  Q3): `ai-delegate` leaves `ai_sandbox_helpers`, and create's helper install removes a
  copy an earlier run put into `~/.ai-sandbox/bin`, with one line of output. Discharges
  O2, O22; O5 (with T02). Host runs: the lib (sourced by every helper), `ai-knowledge`,
  `create-ai-sandbox.sh`.
- **T02 stamp-lookup.** Design work (how the lookup walks a linked parent so that
  stamps of both path forms written today are found, and the not-found form that O21
  needs). C-STAMP: `ai_sandbox_project_root` by stamps alone, `ai_sandbox_create_root`
  for create, `_sync-clone` taking project and sandbox from its parent, the role from
  the host configuration and the stamp; `init --integrator` prints what it records and
  the sandbox it names. Discharges O4, O21 and O6 (with T09); completes O5. Host runs:
  the lib (every lookup of `ai-sandbox`, `-stop`, `-restart`, `-attach`, `-rm`,
  `-account`), `create-ai-sandbox.sh`, `ai-knowledge`.
- **T03 confined-git.** `ai_sandbox_confined_git` in the lib, with no image pull and
  the contract's time limit; the test stub answers `docker run` by running the git
  command with the same paths and recording the arguments. Nothing calls the function
  yet. Discharges O1. Host runs: the lib.
- **T04 status-channel.** C-STATUS: `status` in the state directories, the read-only
  bind, `status/knowledge` written by `ai-knowledge` instead of `.sync-status`
  (line 1, `role=`, `project-id=`), read by `status` and the `sync --all` table, and
  the doctor's generic status lines and knowledge section. Discharges O9 (with T09,
  T10). Host runs: `ai-knowledge`, the lib, `create-ai-sandbox.sh` (the doctor runs in
  the container).
- **T05 origin.** Create makes `knowledge/` and the bare origin and binds the origin
  read-only; after its fetch of `main` the host also fetches the remote's reports into
  `refs/origin-reports/*` and refreshes each origin from the host checkout, so that it
  holds exactly the contract's refs. Discharges O10; O19 (with T09, T10). Host runs:
  `ai-knowledge`, `create-ai-sandbox.sh`.
- **T06 in-sandbox-sync.** `bin/ai/sandbox-knowledge-sync` (not a host helper), copied
  into the image like `ai-delegate`, with the role file, the hook copied from
  `ai-knowledge` (item 3: the host's sync still wrote both into the clone until T09,
  which deletes them there), the `reads-outside` marker, and test-only overrides for its three
  paths; the entrypoint runs it. It removes refs inside only as the status file lists
  them (`closed-proposal=`, `pushed-report=`, `closed-report=`). Discharges O11; O12
  and O17 (with T09); O18 (with T09, T10); O16 (with T12). Host
  runs: nothing; it runs in containers.
- **T07 stamp-2.** `SANDBOX_KNOWLEDGE=2`, the state rule, the refusal text naming only
  the re-create command, the doctor's case, the `sync --all` row; the host's prompt to
  re-create a running stale sandbox. Discharges O14 (with T09). Host runs: the lib, `ai-knowledge`,
  `create-ai-sandbox.sh`, `ai-sandbox`, `ai-sandbox-restart`.
- **T08 remove-migration.** Delete `ai-sandbox-migrate-knowledge`, its cases and every
  reference in code and tests (documents in T12). It lands on the branch at once; RP1
  waits until A3's recheck has passed on every host (B1b, `a3.md`). Discharges O15, O13
  (with T09, T10). Host runs: the lib, `ai-knowledge` (messages only: its
  old-style-branch skip and that half of the line-272 case stay, with the script's name
  gone from the message, until T09 removes them, items 2 and 9); the host can no
  longer run the script.
- **T09 gateway-proposals.** Depends on X1; written before X1's answer in B1a's form
  (item 8). Lands on `main` only together with T10 (item 9). Adds `ai_sandbox_confined_fetch` to the
  lib (the contract; there rather than in `ai-knowledge` so that phases 4 and 6 call
  it, the spec's author's suggestion), which makes every fetch from a sandbox: through
  C-GIT in exactly B1a's form (or the bundle form X1 chose); `ai-knowledge` calls it to
  mirror the clone's branches, reports and tombstones into `refs/sandbox/<id>/`, and it
  changes no ref of the host-owned repository outside that namespace (F1; the
  mechanism the review found is in the untracked `.tmp/security/2026-11-11-sandbox-hardening-p1-plan-review-private.md`, and the test's
  fixture holds it). Every revision the host gives git in the host-owned repository is
  a full ref name; its work tree, and so the render, moves only to
  `refs/remotes/origin/main`, and `refs/sandbox/*` are compared and pushed from, never
  checked out or merged on the host (the author's property). The sync checks proposals
  and the integrator's `main` against the host's own `refs/remotes/origin/main`, pushes
  to the configured remote without forcing, deletes closed remote branches as today,
  writes `closed-proposal=`, runs the in-sandbox command in a running current container
  as O12 says, and no longer clones, writes a role file, a hook or an exclude line, or
  moves anything in the clone (`install_hook` and the role-file write are deleted,
  item 3), nor skips a clone on an old-style branch (items 2, 9); `record_integrator` fetches before it compares. The stub
  answers `docker exec` with the in-sandbox command; `PENDING_AI_KNOWLEDGE` follows the
  starts left for T10 (item 6). A later `fix:` commit keeps the integrator's `main` from
  being pushed when it is behind the host's (item 10). Discharges O3, O7, O8, O9, O13, O18
  and O19 (with T10); completes O6, O12, O14, O17. Host runs: `ai-knowledge`, the lib.
- **T10 gateway-reports.** Depends on X1 and T09; written before X1's answer, as T09
  (item 8), and lands only together with it (item 9). Reports from `refs/sandbox/<id>/`:
  a writer's pushed once per commit, with the host's record in
  `refs/pushed-reports/<id>/` (F4), listed as `pushed-report=` while the sandbox holds
  that commit, the record dropped once the mirror no longer holds the report; the
  integrator's tombstones deleted on the remote with today's lease, and
  `closed-report=` written for each tombstone in the mirror whose report this sync's
  completed fetch of the remote's reports, made after those deletions, no longer
  finds (N1; O18 lists the report in the sync that deletes it); the integrator's
  origin carrying the remote's reports. Removes `PENDING_AI_KNOWLEDGE` from
  `test-host-git.sh` (item 6). Discharges O20 and O7; completes O3, O8, O9, O13,
  O18, O19. O7 is completed by `F01-integrator-main-behind.md`, the evidence of the `fix:` commit of item 10.
  Host runs: `ai-knowledge`.
- **T11 host-git-rule.** The ast-grep configuration and rule of O3 under
  `tests/ai-sandbox/sg/`, and `tests/ai-sandbox/test-host-git.sh`; `ast-grep` becomes
  a declared dependency of the suite. Discharges O3 (with T09, T10: its tree case holds
  the exact allowance `PENDING_AI_KNOWLEDGE=42`, item 6); completes O22. Host runs: nothing.
- **T12 documents.** Runs after T09 and T10 (item 5). `PROJECT_MAP.md` with the register row, its `reads-outside:`
  search and the `ai-delegate` row, `docs/shared-knowledge.md`, the knowledge-integrate
  skill, the usage text and comments of `create-ai-sandbox.sh`, the header of
  `ai-knowledge`. Completes O16. Host runs: text only in `create-ai-sandbox.sh` and
  `ai-knowledge`.

## Batch B2, after RP1 (set-up, at the host)

1. On every host with sandboxes, bring the checkout to the merged `main` (on this host
   the lead's merge does it), then refresh the installed helpers from it and look at
   the states: `~/.ai-sandbox/bin/ai-sandbox-migrate && ~/.ai-sandbox/bin/ai-knowledge status`.
   Expected: every sandbox shows `stale`. (Without the refresh the installed
   `ai-knowledge` is the old copy and shows `current`.)
2. Print the re-create commands, then run each at a time that suits (it ends the
   sessions inside that sandbox; options are remembered in `.env`; the first one
   rebuilds the image; each also removes the host copy of `ai-delegate`, O22):
   `for d in ~/.ai-sandbox/*-agent; do [ -f "$d/docker-compose.yml" ] && printf 'cd %q && ai-sandbox-stop && create-ai-sandbox.sh\n' "$(head -1 "$d/project-path")"; done`
   A re-creation whose sync reports `offline` or a busy lock loses nothing: a report
   the integrator closed stays in its clone, with its tombstone, until a sync that
   reaches the remote closes it (O18); run `ai-knowledge sync --all` once the remote
   is reachable.
3. Host acceptance (H), on the dev-tools sandbox once re-created. The fixture is run
   inside the sandbox, so nothing of it runs on the host. Inside it:
   `rm -f /tmp/MARKER-*; F=~/dev/public/dev-tools/.tmp/security/2026-11-11-sandbox-hardening-p1-x1-fixture.sh; bash $F refs ~/knowledge && bash $F plant ~/knowledge /tmp && echo planted`
   (expected: `planted`; a `refusing` line instead: `bash $F undo ~/knowledge` and
   start step 3 again).
   On the host, first the refs outside the host's own namespaces before the sync:
   `R='^refs/(heads/main |remotes/origin/|origin-reports/|sandbox/|pushed-reports/)'; git -C ~/.ai-sandbox/knowledge/main for-each-ref --format='%(refname) %(objectname)' | grep -vE "$R" > ~/h-before; cat ~/h-before`
   (on a host where the migration ran, `refs/heads/proposal/*` left by its conversions
   through `ai-knowledge propose`; they are the host's own and stay). Then
   `ai-knowledge sync --all`, then `cd ~/dev/public/dev-tools && ai-sandbox true`,
   then `ls /tmp | grep MARKER || echo none` (expected: `none`),
   `head -1 ~/.ai-sandbox/dev-tools-*-agent/status/knowledge` (expected: `ok`) and
   `R='^refs/(heads/main |remotes/origin/|origin-reports/|sandbox/|pushed-reports/)'; git -C ~/.ai-sandbox/knowledge/main for-each-ref --format='%(refname) %(objectname)' | grep -vE "$R" | diff ~/h-before - && echo same`
   (expected: `same`; any diff line is a ref the sync added, removed or moved outside
   the host's namespaces: H is not passed, and the lead brings the output to the phase
   planner and the spec's author before the phase is closed).
   Inside, before the undo: `ls /tmp | grep MARKER || echo none` (markers here come
   from git run inside the sandbox, the in-sandbox command's included; for the
   record), `bash $F control ~/knowledge /tmp` (expected: `control: live`; `INERT`:
   the fixture did not take, the host's `none` proves nothing, step 3 is repeated, not
   passed), `sandbox-doctor | grep -A2 knowledge` (expected: that line with its age),
   then `bash $F undo ~/knowledge`. On the host: `rm -f ~/h-before`.
   Paste back the output of each.

Host commands of this phase against "Host commands and phone work": `ai-sandbox` and
`ai-sandbox-restart` (everyday, unchanged typing; each entry now starts one throwaway
container, A2); `ai-knowledge sync` and `--all` (periodic, unchanged); re-creation in
B2, X1 and the migration in B1 and reading the diff at RP1 (set-up, at the host,
once); the removed `ai-sandbox-migrate-knowledge` (set-up, gone; the repair is a plain
create run);
`sandbox-knowledge-sync` (automatic, inside the container, not a host command).
Nothing added to everyday work, and nothing a phone could need.

## Assumptions

| # | Assumption | Status | Settled by |
|---|---|---|---|
| A1, A2 | spec's: confined fetch delivers, no host execution; fast enough | inferred, guessed | X1 |
| A3 | spec's: the migration has finished on every host | guessed; does not hold as seen from the dev-tools sandbox's clone (review), so the migration in B1b is the expected path | B1b before and after the migration |
| PA1 | A git process started with its working directory in a repository reads that repository's configuration also for a URL-only command | verified (probe P-A) | - |
| PA2 | The upload-pack program of a fetch gets the URL path appended, and the URL need not exist on the host | verified (probe P-B, git 2.34.1) | the host's git version is in B1 |
| PA3 | `git bundle create -` writes to standard output | verified (P-C) | - |
| PA4 | ast-grep 0.51.0 scans extensionless bash files only through `languageGlobs`, and does not parse heredoc bodies | verified (evidence, method checks) | - |
| PA5 | The base suite: 1217 cases, 2 failing (test-delegate 54, 59) | verified (run) | - |
| PA6 | The image runs `git` as the host user with `--entrypoint git --user <uid>:<gid>` and reads the read-only mount | inferred (tree: `USER_ID=$HOST_UID` build argument) | X1 |
| PA7 | The only reader outside the repository of `.git/ai-knowledge-role` is the knowledge repository's `propose-rule` skill and its proposals README | verified (S12, on this sandbox's clone, current with the remote) | - |
| PA8 | Docker creates a missing bind source owned by root, so the host must create `status/`, `knowledge/` and the origin before any start | verified in the tree (comments at `ai_sandbox_state_dirs`, `prepare_targets`) | - |
| PA9 | `ai-delegate` is an in-sandbox program whose host install serves no documented use | verified intent (the author's answer to Q3: PROJECT_MAP, the environment block, no host opt-in in the tree); its host install is removed here (T01, O22) | - |
| PA10 | With no stamped ancestor the lookup returns the directory itself | settled by the author (Q2), with O21 | - |
| PA11 | A fetch in T09's form changes no ref outside its refspec destinations, also under the user's own fetch settings | verified on git 2.34.1 (probe P-E: four user-level fetch settings tried); the host's git version answers in B1a's "refs outside the namespace" line | X1 |
| PA12 | A report ref is never moved once made: its name carries its commit's prefix | verified (this sandbox's knowledge clone: the process-report skill, step 6, writes `refs/reports/<date>-<project>-<4 hex of HEAD>`; the host drops it after the push today) | - |
| PA13 | The host's Docker accepts `--pull never` on `docker run` | inferred (the option exists in current Docker; the host's version is printed by B1a) | X1: a failing fetch line names it |

## Left out (no trigger found, or a failure no user reaches)

Dropping capabilities, `no-new-privileges`, memory or process limits and a read-only
root file system on the throwaway container (git there serves a read-only mount with no
network; no step was found that needs them); a separate lock for the origin (the
per-sandbox lock covers it); refusing a sandbox whose stamp is stale in `sync <dir>`
(its host side is safe to sync; only the `docker exec` is withheld). Removing the
namespace and records of a sandbox that `ai-sandbox-rm` or `-gc` removed (the cost is
disk only; a re-created sandbox of the same id replaces its mirror at its first fetch,
and its records drop at that sync). A commit field in `pushed-report=` (PA12: a report
ref is never moved, so the name identifies the commit). Pinning `ast-grep` in the image
(its npm line pins none of its tools; pinning what the image downloads is M4, phase 10;
the known cases of O3 fail on a version that parses differently). A separate host-owned
repository for sandbox refs (the review's second look at choice 3; O19 and R10 close
F1 in `knowledge/main`, and the author's answer keeps that repository).

## Questions for the spec's author

Q1 to Q5 of the first round are answered in `author-answers.md` (binding for this
plan; Q5 became E2). Open:

- S-3 (later phases; phase 1 does not wait for it). C-GIT's second use bullet calls the
  host "an ordinary git client of an untrusted server, the case git documents as safe";
  that covers code execution, not the refs a fetch creates, and phases 4 and 6 use C-GIT
  too. Proposed sentence for the spec's author, at the end of that bullet: "A fetch
  through it creates or updates refs of the fetching repository only under the
  destinations its refspecs name, and the host names its own refs in that repository by
  their full names; nothing the served repository holds outside those refspecs becomes
  a ref on the host."
- Conditional, only if B1a's A2 line is not accepted: the spec's A2 fallback adds a
  second way to run git against a sandbox's clone (`docker exec` into a running
  sandbox), against C-GIT's "one function" (review L7). The plan does not choose it.
