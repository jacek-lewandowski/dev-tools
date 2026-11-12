Task: 2026-11-11-sandbox-hardening
Class: phase

# ai-sandbox hardening: scoped credentials, reversible remotes, no host execution of agent content

Date: 2026-11-11
Status: approved by the user on 2026-11-11 ("U17:b / Akceptuję, planowanie już modelem
opus"): revision 3 with the fixes of its review, review closed, U17 answered. Changes
S-1 ("Inputs"), S-2 (C-MODULES) and S-3 (C-GIT), raised while planning phase 1,
approved by the user on 2026-11-12 with the phase 1 plan ("Ja zajmę się uruchomieniem
na hoście, natomiast ty zajmij się implementacją i planowaniem kolejnych faz.", read
back to the user as approval of the plan and of the three changes); deferred entry E2
added with them. Change S-4 (I3e narrowed to the host sockets a sandbox is given, two
residual risks, the phase 2 sentence on a remembered `--audio`), raised while planning
phase 2, approved by the user on 2026-11-12 with the phase 2 plan, option (a) ("a")
Author: Hania (planner 1), the spec's author for this task
Tree: `96540a5` (`main`)
Scope: `bin/ai/` (the toolchain), `tools/` as far as the host and the sandboxes load it,
`tests/ai-sandbox/`, `PROJECT_MAP.md`. Not in scope: `bin/cassandra/`, `bin/video/`,
`ai-sync` except where a phase names it as a dependant.

Inputs. The security review of 2026-11-11 (findings C1 to L5), the options report, its
addendum, the user's decisions, the accepted task list and two scout reports are kept
untracked under `.tmp/security/` on purpose: the repository is public. This spec names
findings by key and states the property each phase establishes; it holds no reproduction
steps, and nothing committed for this work may hold them either, except the fixture code
of a test as stated here. A plan, an evidence file, a batch for the user, a commit
message, a review and a test's name, header, assertion message or comment state the
property and the finding key, and name an input only by its class, as this spec does (a
clone's configuration, its refs, a link placed where a sandbox can write). A closing
check that needs a fixture gets one in committed test code: the smallest that shows the
property, whose only effect is a marker inside the test's own temporary directory; the
specific settings, paths and commands it uses appear in nothing committed but that code.
A host step outside the suite that needs such a fixture, before that code exists or
after, takes it from an untracked file under `.tmp/security/`, which the plan names by
path.

How facts are cited. `[Gn]`, `[Bn]`, `[Ln]`, `[Sn]`, `[Rn]` are primary sources fetched
for this spec on 2026-11-11 and listed at the end with URL and quote; every fact about an
external tool or service that a contract rests on carries one. Finding keys (C1 to L5)
and question keys (Q1 to Q12, Q-A to Q-E) name items of the untracked reports for the
user, who has them; no statement here rests on them. "Tree" means read in the
repository at the commit above. **Nothing in this spec has been run on a host.** What
rests on that is in the assumption table, with the experiment that settles it.

Files of this work. Phase n has the key `2026-11-11-sandbox-hardening-p<n>`, its plan at
`docs/superpowers/plans/2026-11-11-sandbox-hardening-p<n>-plan.md` and its evidence
directory at `docs/superpowers/evidence/2026-11-11-sandbox-hardening-p<n>/`. Logs of
host runs describe the user's machine and stay untracked under `.tmp/security/`; the
assumption table here records only their verdict.

## Who uses it and what they are trying to do

- **The user**, on the host: creates and enters sandboxes (`create-ai-sandbox.sh`,
  `ai-sandbox`), keeps a clone of each project in the home directory, synchronises it
  with the hosting service and sometimes with a second host, runs project containers
  with Docker Compose for testing, and reads what agents produced through pull requests
  and issues.
- **Agents**, inside a sandbox: edit, build and test; commit, push, pull and open pull
  requests and issues on GitHub with `gh` (the user's later decision); fetch and push
  the one Bitbucket repository with git; file proposals to the shared knowledge
  repository.
- **The user, away from the host, on a phone** (requirement of 2026-11-11): talks to
  agent sessions that run inside sandboxes entered on the host beforehand, and reads,
  reviews and merges pull requests in the hosting service's own interface. No terminal
  on the host is at hand.

The user's priorities, in order, are the three goals below. Smooth everyday work is a
hard requirement on all three, and so is work from a phone (I8).

## Goals

- **G1 No secret leaves.** A sandbox holds no secret of the user beyond what the work
  inside needs, and each one it holds is issued for that sandbox, limited in scope and
  revocable without touching anything else.
- **G2 Remote git operations are reversible.** With what a sandbox holds, no ref of a
  remote repository can be deleted or rewritten, and nothing the host pushes on a
  sandbox's behalf can be either.
- **G3 Agent-written content does not execute with the user's host privileges.**
- **G4 The toolchain can be read.** `create-ai-sandbox.sh` (2898 lines, tree) is split
  into modules with one concern each, so the user's independent review and every later
  change work on small files.

## Phases at a glance

| Phase | What | Findings | Starts with | Waits for |
|---|---|---|---|---|
| 1 | Host git leaves the sandbox-writable trees (knowledge sync, project identity) | C1, H7, H8, H4 (clone part) | X1 | - |
| 2 | Host audio off by default | C2 | - | - |
| 3 | Split of `create-ai-sandbox.sh` (refactor flag) | - | pins on the tree it starts from | - |
| 4 | The host runs an installed revision | H3 | - | - |
| 5 | Repository list, git tokens, hosting-rule check, pipeline secrets | H6 (server-side part) | X2, X3 | - |
| 6 | Separate clones | H5, H6 | - | - |
| 7 | AI credentials and stores per sandbox | H1, M1 | login check | - |
| 8 | Project containers inside the sandbox, on the engine X4 selects | M3 (part), host Docker use, root on bind mounts | X4 | - |
| 9 | Knowledge sync, remaining findings | H2, H4 (rest), M6 | - | - |
| 10 | Remaining Medium and Low, independent review | M2, M3 (rest), M4, M5, L1-L5 | - | - |

The order is the accepted task list's (critical findings, clean-up with the installed
revision right after it, clones and tokens, containers, the rest) with one change: H7,
H8 and part of H4 move into phase 1 (D2, confirmed by the user as U14). Inside the third
step, which the list does not order, tokens come before clones (D6). What each
phase establishes is in its block.

## Invariants

- **I1 Credentials are per sandbox.** No host credential store (login, cookie store,
  browser profile, licence key, key ring) is copied or mounted into a sandbox. A
  credential present in a sandbox was issued for it, is limited to that sandbox's
  repositories or account grant, and can be revoked alone. A git token reaches a
  sandbox on standard input only; it never appears in a compose file, a sandbox's
  `.env`, the environment a container is started with or a command line (how it is
  held inside is D13). A sandbox the user created with the host's AI logins copied
  (`--host-logins`, U2) is outside this invariant for those logins, and the toolchain
  says so when the option is given. Established by phases 5 and 7.
- **I2 A sandbox cannot make an irreversible change to a remote.** For every repository
  a sandbox holds a credential of this toolchain for, the hosting service refuses ref
  deletion and non-fast-forward updates from that credential, and the host issues the
  credential only once that is established: checked through the API on GitHub,
  confirmed by the user on Bitbucket (contract C-RULES). The host pushes on a sandbox's
  behalf only from a repository it owns, only to the remote recorded in its own
  configuration, and never as a forced update of a ref (the leased deletions of the
  knowledge design stay as they are until phase 9 looks at them under M6). Stated
  exceptions: tags on Bitbucket Cloud, which its restrictions do not cover ([B1]: they
  match branches); a personal token the user brings into a sandbox, which acts as
  the user and is bound by no check made for the toolchain's credential (phase 5
  reports those it finds); and a credential within a pipeline run's reach that may
  bypass the rules (C-PIPE, condition 6). Established by phases 1, 5 and 9.
- **I3 The host does not execute, source or trust what a sandbox can write.**
  - **I3a** The host starts no git process whose repository or working tree a sandbox
    can write, except through the confined primitive of contract C-GIT. Phase 1 for
    the toolchain, phase 6 for the user's own git.
  - **I3b** Everything the host executes or sources from this toolchain, and the
    `tools/` code mounted into sandboxes, comes from the install root, which only a
    deliberate install of a revision the user named changes. Phase 4.
  - **I3c** A host write into a directory a sandbox can write never follows a link,
    and status the host reports to a sandbox lives outside what the sandbox can write.
    Phase 1 for the knowledge clone, phase 9 for the rest.
  - **I3d** Nothing that decides a sandbox's identity, role, mounts or token scope is
    read from a place a sandbox can write. Phases 1 and 5.
  - **I3e** By default the toolchain gives a sandbox no host daemon's socket but its
    display's, so the host's sound server, a daemon that acts on a client's request,
    is out of its reach. The display server of the chosen mode (the host's compositor
    under `wayland`, a server the host starts for the sandbox under `xpra` and
    `nested`) is outside this invariant: what it shares with the host is M2, phase 10,
    and `--display=host`, which shares the host's own X server, is a mode the
    toolchain names unsafe. A sandbox the user opted into host audio is outside this
    invariant, and the toolchain says so when the option is given. Phase 2.
- **I4 Smooth everyday work.** After every phase: entering a sandbox is still one
  command; an agent pushes and opens a pull request without the user doing anything
  per push; nothing the user does daily gains a step. A step the user must take once
  (re-create a sandbox, install a revision, store a token) is asked for in one batch
  per phase, with the exact commands.
- **I5 Nothing is deleted silently.** No command of this work removes a clone, a
  branch or unpushed work without listing it and asking.
- **I6 An existing sandbox keeps working until the user re-creates it**, or is refused
  at start with the one command that repairs it (the existing convention of the
  knowledge stamp, tree: `ai_sandbox_require_current`). No phase rewrites a sandbox on
  its own.
- **I7 Earlier invariants stay**, with one replaced. The shared-knowledge specs'
  invariants hold unchanged (rules never writable from a sandbox, proposals change only
  `proposals/`, the host never force-pushes, `main` changes only with the user's
  approval). "No sandbox holds git credentials; the host is the only party that fetches
  or pushes" (2026-09-14 design) stays true for the knowledge repository and is
  **replaced for project repositories by I1 and I2 from phase 5 on**, as the user
  decided on 2026-11-11. The build-caches and memory-budget invariants are untouched.
- **I8 Work from a phone.** Once a sandbox is entered on the host, and for as long as
  that entry stays open, nothing in everyday work needs a command typed on the host: an
  agent edits, builds, tests, runs the project's containers, pushes, fetches and opens
  pull requests and issues, and the user merges in the hosting service's interface. A
  host command of this work is either a set-up step, done before the user leaves, or a
  repair that also happens without being typed. "Host commands and phone work"
  classifies each one and names what waits for the user's return; every phase plan
  checks the host commands it adds against it. Established by phases 5, 7 and 8.
- **I9 An agent writes only its own branches.** With a sandbox's credential no branch
  outside the repository's agent prefix is created or updated, the default branch
  included; that one moves by the user's merge (U4, U6). Against a pipeline run an
  agent defines it holds only while that run reaches no credential that may bypass
  the rules (C-PIPE, condition 6). Outside this invariant, and named as such where it
  is set: the default branch of a repository the user switched to `default=ff`, and
  on Bitbucket every branch but the default one (C-RULES). Established by phase 5.

## Non-goals

- A host git gateway for project repositories, and pull requests or issues through a
  gateway (shelved by the user's later decision; D4).
- A virtual machine, Kata or Podman as the engine; shared read-only image layers
  between sandboxes (declined with the chosen direction: an inner Docker's store
  serves one container at a time, [S1]).
- A host timer, and any host process of this work that outlives the command that
  started it (U15).
- A way to run host commands from a phone (a remote shell, a chat bridge). Set-up
  steps wait for the user's return; I8 names them.
- Egress filtering (U8: left open for now; the user's idea for it is on the deferred
  list). Taking it up is a new phase and a spec change.
- Preventing publication: a fast-forward push of content that should not be public
  cannot be undone by any mechanism here.
- Moving pipeline secrets into protected environments and making the workflows on
  protected branches safe against content an agent supplies: the user's work in the
  hosting service. The toolchain restricts which refs an agent writes and records the
  user's confirmation (C-RULES, C-PIPE).
- The user's own Bitbucket MCP gateway for pull requests; the sandbox supervisor (its
  spec is shelved).
- Hardening a project that has no repository on a hosting service: it keeps the shared
  tree, labelled as such (D8).
- The user's step 0 on the host and in the hosting services (checking existing clones,
  the audio daemon, the gitleaks hits, setting rulesets, branch restrictions and
  environments). The phases check its results where a contract says so; they do not
  perform it.
- Changing the text of the shared knowledge rules from here. Phase 5 files a proposal
  to the knowledge repository for the sentence that says a sandbox has no git
  credentials; the user approves it there.

## The user's decisions (2026-11-11)

The user answered every open decision of revision 2 on 2026-11-11, and U17 of
revision 3 with the approval of this spec. The quoted words
are the user's; the reading beside them is the lead's, stated back to the user for
the first batch of answers and confirmed by the user only where a line quotes the
confirmation. "Differs" marks an answer other than revision 2's recommendation.

- **U1 Audio.** "domyślnie wyłączone". Off by default, on per sandbox. Phase 2.
- **U2 AI logins.** "parametr create-ai-sandbox". Differs. An option of sandbox
  creation decides whether the host's logins are copied; the default, confirmed
  ("Pozostałe rzeczy dobrze zrozumiałeś"), is to log in inside. Phase 7.
- **U4 Default branch.** First "tak"; then, shown what that does together with U16,
  "rekomendowane". An agent does not update the default branch: it moves by the
  user's merge, which the user makes from a phone; switchable per repository. I9.
- **U5 Tags.** "tylko tworzenie, ewentualnie aktualizacja opisu jeżeli można to
  wydzielić jako osobne uprawnienie"; the description meant: "wydania". Differs. An
  agent creates tags and never moves or deletes them. The user's condition, a
  separate permission for the description, cannot be met: the permission every push
  needs also edits and deletes releases, and nothing withholds that part (C-RULES;
  residual risk).
- **U6 Pipelines.** "dobre pytanie - dzięki temu agent może uruchamiać workflow poza
  hostem...". A push to a branch an agent writes starts pipelines, and that is wanted.
  Each repository gets a branch prefix that C-RULES verifies; C-PIPE says what keeps
  secrets out of those runs.
- **U8 Egress.** "czy można jakoś sprawdzić adres w Google czy nie jest podejrzany?
  Możemy to zostawić na później, póki co otwarte". Left open; deferred list, E1.
- **U9 AI tools on the host in sandboxed projects.** "sporadycznie, ale przyjmijmy
  że nie - mógłbym się tylko do nich zalogować, aktualizować". Not used for work
  there: the project's Claude history and memory stay shared with the host. Phase 7.
- **U11 Root on bind mounts.** "zgoda", to this: before phase 8 the same sandbox and
  the same Compose project run on rootless Docker and on Sysbox, the latter with the
  clones directory on a `nosuid` mount, against one pass line; rootless Docker is
  taken if it passes, otherwise Sysbox with `nosuid`. Differs. X4, phase 8.
- **U12 Integrator's `main`.** "tak". The host shows the change and asks before it is
  pushed. Phase 9.
- **U14 Scope of phase 1.** "razem". C1 together with H7, H8 and the clone part of H4.
- **U15 Token refresh.** "b". A refresher bound to the open `ai-sandbox` session.
  C-TOKEN.
- **U16 Workflow files.** "b muszę mieć możliwość pracy przez telefon". Differs. The
  app holds the Workflows permission permanently; sensitive pipeline secrets live in
  hosting-side environments limited to protected branches. D12, C-PIPE.
- **Work from a phone**, a new hard requirement, in the same sentence. I8.
- **U17 Reading pipeline runs.** "U17:b". Differs from the recommended (a). Results
  and logs: the app also holds Actions, Checks and Commit statuses read (D12), so an
  agent reads a failed run's log itself, and with it the checks, logs and
  downloadable artifacts of every run in the repository, those on the default branch
  that held environment secrets included ([G2]). The user's confirmation includes
  C-PIPE's condition 7. Phase 5.

## Decisions taken in this spec

Each is the author's, with its reason; a reviewer or the user may overturn it.

- **D1 The knowledge clones get the gateway transport (C1).** The host stays the only
  party that pushes to the knowledge remote, because it is the enforcement point for
  two existing invariants (a proposal changes only `proposals/`; only the integrator
  advances `main`), and those cannot be delegated to a token inside every sandbox.
  So the fix is a gateway transport for this one repository: the host fetches a
  sandbox's branches as data into a repository it owns and validates and pushes
  from there. C1 does not wait for the token work.
- **D2 Phase 1 also closes H7, H8 and the knowledge-clone part of H4.** A sync that
  works from a host-owned repository can no longer follow the clone's remote
  configuration or compare against the clone's refs (H7), and it has no reason left to
  write into the clone (H4). The project-root lookup (H8) is the toolchain's other git
  call inside a sandbox-writable tree (tree: `ai_sandbox_project_root`), so the same
  residue search covers it.
- **D3 The installed revision (H3) is its own phase, right after the split.** The split
  carries the refactor flag: behaviour unchanged, proven by pins. H3 changes what the
  host sources and what sandboxes mount, so inside the split it would break that
  proof. The accepted task list has it "with it or right after"; right after is what
  remains, and the manifest of C-INSTALL is then written once, against the split
  files.
- **D4 Pull requests and issues stay on a token inside the sandbox.** The user asked
  whether they could go through a gateway. They could, but a GitHub App installation
  token is already limited per request to the listed repositories and to chosen
  permissions and expires after one hour ([G1]); with C-RULES in force it can do
  nothing irreversible to refs. A gateway would add trusted host code to protect that
  credential. Non-goal; revisit only if egress filtering becomes a phase.
- **D5 Toolchains shared into project containers: offered, not imposed.** The sandbox
  gets uv-managed Python, the JDK and Node read-only at one fixed path (C-DOCKER); a
  project's compose file may bind that path into its own containers. What it saves is
  measured in X4 before anything is built for it.
- **D6 Tokens before clones**, inside the task list's third step, whose items carry no
  order. A clone the host does not share is useful only if the sandbox can exchange
  commits with the remote. For GitHub the user logs `gh` in by
  hand today; for the Bitbucket repository nothing inside can fetch or push (the
  user's statement). So phase 5 delivers credentials first and phase 6 removes the
  shared tree.
- **D7 The sandbox's clones live outside the sandbox directory and survive
  `ai-sandbox-rm`.** The task list says "under the sandbox's directory", the user's
  decision says the clone must survive the sandbox's removal, and `ai-sandbox-rm`
  deletes the sandbox directory whole (tree). A separate workspace root (C-WORKSPACE)
  satisfies both: credentials and state go, work stays until the user deletes it
  after seeing what is unpushed.
- **D8 A project without a hosting remote keeps the shared tree.** The clone model
  needs a remote to exchange commits through, and such projects exist: the user
  starts sandboxes in plain parent directories, and the suite creates them for
  directories that are no repository. Such a sandbox is stamped
  `SANDBOX_TREE=shared`, the create output and `ai-sandbox --print-context` say that
  I3a does not hold for it, and nothing else changes for it.
- **D9 The rule check asks the hosting service what the token itself may bypass**, not
  whether the bypass list is empty (C-RULES). The user's question was whether a
  ruleset that keeps a bypass for the administrator still binds the app. The API
  reports, per ruleset, the bypass level of the caller ([G1]); checking that with the
  token about to be handed over answers the question for exactly that token, and lets
  the user keep the bypass their own merge needs (U4). It rests on A9 and A10, and
  it says nothing about who else is on the list (C-PIPE, condition 6).
  On Bitbucket the check is the user's confirmation, given once per repository and
  recorded with its date: reading the restrictions needs the admin scope ([B1], [B2]),
  and the user's rule gives the host a Write token only. Only an administrator can
  change the restrictions afterwards, so the confirmation does not go stale by
  anything a sandbox does.
- **D10 A Bitbucket token is stored per sandbox and repository.** The user asked for
  one keyring entry per project and hosting service; since one sandbox can cover
  several repositories the entry also names the repository. Two sandboxes that need
  the same repository get two tokens, so each is revoked alone (I1).
- **D11 The lead's two suggestions are adopted**: the declared list of a sandbox's
  repositories that also decides token coverage (C-REPOS), and the check of
  hosting-side rules at token issue with an explicit, recorded override (C-RULES),
  the latter with the criterion of D9.
- **D12 The GitHub App's permissions are what the user said agents do from inside**:
  contents, pull requests and issues read-write, workflows write (U16; editing files
  under `.github/workflows` needs it, [G4]), actions, checks and commit statuses read
  (U17), metadata read. No administration, environments or secrets permission, so no
  token changes a ruleset or an environment or reads a secret's name ([G2]); and no
  Actions write (re-run, cancel, start a workflow by hand on any ref): nothing the
  user described needs it. Adding any other permission is a change of this spec.
- **D13 Inside a sandbox the token set is a file, and `gh` reads its token from its
  own process environment.** The user's rule (standard input, never an environment
  variable or an argument) governs how a token reaches the sandbox, and I1 keeps it.
  Inside, the user accepted a plain-text store; the environment of the `gh` process
  is the form documented for an installation token, while `--with-token` is
  documented for a classic personal token and a login is one account per host
  ([G9]).
- **D14 Conversion to a separate clone replaces the tree at the user's path.** A tree a
  sandbox could write stays unsafe for the user's git and tools after the mount is
  gone, and no listing of differences can be shown complete. So the old tree becomes
  the sandbox's clone and the user's path gets a new clone from the hosting service
  (C-WORKSPACE). The user who does not want that for a project keeps it `shared`.
  C-WORKSPACE applies the same rule wherever a clone is made or seeded, and says
  how a tree a sandbox could write is known.
- **D15 Settled by the files, not asked.** Images pulled inside a sandbox are kept
  across re-creation and pruned on request (the accepted task list, step 4). The two
  cases of `test-delegate.sh` that fail on the base (A4) test the prompts of
  `ai-delegate`, a surface the split does not touch (tree: cases 54 and 59); the
  split's pin is that the suite's result is the same before and after, and the two
  cases are looked at with M5 in phase 10.
- **D16 One ruleset carries U4 and U6**: the one "outside the agent prefix" of
  C-RULES, under which the default branch needs no rule of its own. The prefix
  defaults to `agent/` (inferred: a conventional name, changed per repository with
  `prefix=`). A ruleset binds everyone who is not on its bypass list, and the host
  cannot read that list ([G1]). What may sit there is the user's own role and an
  actor no pipeline run can act as (C-PIPE, condition 6); another app that pushes
  branches of its own gets a place only on those terms.
- **D17 Environments are limited by name pattern, not by "protected branches only".**
  The user's words were "limited to protected branches". GitHub's option of that name
  admits every branch when the repository has no branch protection rule ([G11]).
  Whether a ruleset counts as such a rule the source does not say; this design
  protects branches with rulesets, and on either reading the option does not serve.
  C-PIPE therefore asks for "Selected branches and tags" with patterns that no ref an
  agent can write matches, which is what the user's answer is for.
- **D18 One engine per host.** If rootless Docker passes X4, every sandbox runs on it,
  not only those with Docker enabled: the capacity check, the cache lock and every
  `docker` call of the toolchain address one daemon (tree: `ai_sandbox_check_capacity`),
  and root on bind mounts then closes for all sandboxes, which is what the user asked
  about beyond U11.

## Contracts

Data shapes, locations and command interfaces that phases plan against. Names given
here are fixed; everything else is the phase plan's.

### C-GIT, the confined git primitive (phase 1; used by 4 and 6)

- One function in `ai-sandbox-lib.sh`, `ai_sandbox_confined_git <root> <subdirectory>
  <git subcommand> [arguments]`, is the only way the host runs git against a
  repository a sandbox can write. It runs the command in a throwaway container of the
  sandbox image: no network, the root as the only mount and read-only, the host
  user's uid (under a rootless engine the container id that maps to it, C-DOCKER),
  none of the sandbox's volumes or environment; standard input and output pass
  through; the exit status is git's.
- The root is a directory whose own path no sandbox can change (a sandbox directory, a
  workspace, a project root); the subdirectory is entered inside the container, so a
  link planted below the root resolves there and never on the host.
- Two uses. As the remote program of a fetch made by a host-owned repository
  (`remote.<name>.uploadpack`, [L2]), so the host is an ordinary git client of an
  untrusted server, the case git documents as safe ([L3], [L4]). And for read-only
  queries whose output the host compares as text and never evaluates, and prints only
  with control characters removed.
- A fetch through it changes refs of the fetching repository only below the
  destinations its refspecs name, whatever else the served repository holds. Those
  destinations lie below a prefix kept for that served repository alone, outside
  `refs/heads/` and `refs/tags/` (for the knowledge sync `refs/sandbox/<sandbox id>/`,
  C-KNOW). In such a repository every git call of the toolchain gives a revision as a
  full ref name or an object id, never as a short name or `FETCH_HEAD`, so no name
  the served repository chose can stand for one of the host's refs. In a repository
  the user works in (phase 6) this binds the toolchain's calls, not what the user
  types: a short name the user gives for one of their own refs never resolves below
  the prefix.
- A host-owned repository is one outside every sandbox mount whose configuration only
  the host writes. All validation, comparison and pushing happens there, through a
  second function, `ai_sandbox_host_git`.
- The repository keeps a structural search rule that fails the suite when a host
  script starts git other than through these two functions.

### C-STATUS, the status channel from host to sandbox (phase 1; extended by 5 and 6)

- `<sandbox dir>/status/`, written only by the host, mounted read-only at
  `/run/ai-sandbox/status`. One file per topic: `knowledge` (phase 1), `credentials`
  (phase 5), `repos` (phase 6).
- Line 1: `<local ISO-8601 time> <state> <message>`, state one of `ok`, `warn`,
  `refused`, `offline`. Further lines are `key=value`, per topic. `sandbox-doctor`
  prints line 1 of every file with its age.
- `knowledge` carries `role=proposals|integrator` and one `pushed-report=<name>` per
  report the remote accepted. It replaces `.sync-status` and `.git/ai-knowledge-role`
  inside the clone.

### C-KNOW, the knowledge sync (phase 1; used by 9)

- The host fetches a sandbox's `proposal/*` branches, the integrator's `main`,
  `refs/reports/*` and `refs/reports-closed/*` through C-GIT into one host-owned
  repository under `~/.ai-sandbox/knowledge/`, below `refs/sandbox/<sandbox id>/`.
  Name, scope and ancestry checks run there against the `main` the host fetched
  itself; pushes go from there to the remote in the host's knowledge configuration.
- The sandbox's `origin` is a bare repository the host writes and mounts read-only at
  `/run/ai-sandbox/knowledge-origin.git`. Ref names inside the clone do not change
  (`origin/main`, `origin/proposal/*`); only the integrator's holds `refs/reports/*`.
- One command baked into the image, `sandbox-knowledge-sync`, does inside the
  container what the host did in the clone: creates the clone when absent, fetches
  from that origin, fast-forwards `main`, removes closed branches and the reports
  listed as pushed. The entrypoint runs it at start; the host runs it through
  `docker exec` after each sync of a running sandbox.
- The knowledge stamp in `.env` becomes `SANDBOX_KNOWLEDGE=2`; a sandbox stamped `1`
  is refused at start with the re-create command, as a stale one is today.
- The role comes from the host's knowledge configuration and the project stamp
  (C-STAMP), never from the clone.

### C-STAMP, the project's identity (phase 1)

- `ai_sandbox_project_root` keeps its name and starts no git process. It returns the
  nearest ancestor `A` of the given directory for which
  `~/.ai-sandbox/<id of A>-agent/project-path` exists and names `A`. So a command
  given inside a sandboxed parent directory addresses that parent's sandbox, also from
  a repository below it that has none of its own.
- `create-ai-sandbox.sh` alone also accepts a directory without a stamp: it takes the
  nearer of the stamped ancestor and the ancestor that holds a `.git` entry (tested
  for existence only), else the directory itself. A repository below a sandboxed
  parent therefore still gets its own sandbox, as today.
- The host's git identity for the sandbox's `.env` is read from the user's global git
  configuration, not from inside the project.

### C-MODULES, the module boundaries after the split (phase 3)

Each module is sourced once, by the entry script, in this order; no module sources
another; each generated file has one owner.

| File under `bin/ai/` | Owns |
|---|---|
| `create-ai-sandbox.sh` | option defaults and the order of the stages; generates nothing |
| `create.d/options.sh` | `usage`, option parsing, options remembered in `.env` |
| `create.d/project.sh` | prerequisites, project resolution, paths, the sandbox directory, the sync of shared stores |
| `create.d/display.sh` | display mode, X authority, `start-display.sh`, `stop-display.sh`, `xpra.conf` |
| `create.d/resources.sh` | memory, CPU set, timezone |
| `create.d/devices.sh` | audio, serial devices, device cgroup rules, `security_opt` |
| `create.d/rules.sh` | shared-brain wiring, the generated "AI sandbox environment" block, the knowledge render call |
| `create.d/seed.sh` | tool-state seed, IntelliJ, the SDKMAN farm |
| `create.d/image.sh` | build context, Dockerfile, image build and stamp |
| `create.d/compose.sh` | the managed keys of `.env`, `docker-compose.yml` |
| `create.d/install.sh` | helper installation, the `~/.bashrc` block (phase 4 replaces both with C-INSTALL) |
| `create.d/start.sh` | capacity check, start under the cache lock, the closing summary |
| `image/` | what is baked into the image, as files instead of heredocs: `entrypoint.sh`, `sandbox-doctor`, `sandbox-knowledge-sync`, `ai-delegate`, `sandbox-desktop`, `sandbox-idea`, `xdg-open`, `sandbox-bashrc.sh`, `sandbox-env.sh`, `sandbox-sdk`, `claude-managed-settings.json`, the Dockerfile parts |

Later phases cite these files: compose mounts and the runtime line in `compose.sh`,
credential and knowledge commands in `image/`, the seed in `seed.sh`, audio in
`devices.sh`.

Every program that runs only inside the container lives in `image/`. The host
executes or sources nothing there itself (the host's `docker exec` of
`sandbox-knowledge-sync` runs it inside the container), nothing there is installed
on the host, and C-INSTALL's `PATH` entry does not reach it; so C-GIT's structural
rule leaves out `image/` by directory and names no file. A program that also runs
on the host (`context-statusline`, the host's status line) stays in `bin/ai`.

### C-INSTALL, the installed revision (phase 4)

```
~/.ai-sandbox/installed/
  src.git/           host-only bare repository of dev-tools; no sandbox mounts it
  rev/<commit>/      one exported commit, read-only: bin/ai/**, tools/**,
                     tests/ai-sandbox/**, verify-ai-sandbox-on-host.sh
  current            symlink -> rev/<commit>, the revision the host runs
~/.ai-sandbox/bin    symlink -> installed/current/bin/ai   (the PATH entry of today)
```

- `ai-sandbox-install [<revision>] [--from <directory>]`: fetches into `src.git` from
  its hosting remote, or with `--from` from a local tree through C-GIT; shows the
  commits and the changed paths between `current` and the revision; asks; exports;
  switches `current`. It is never run by another command. Older `rev/` directories
  that no container mounts are listed and removed by `ai-sandbox-gc`.
- `bin/ai/MANIFEST` lists every path the host executes or sources, copies into the
  image or mounts into a sandbox. A check in the suite fails when a `source`, an
  `install`, an image copy or a mount source in the toolchain names a path outside
  the manifest.
- Every host entry point refuses to run when its own resolved path lies inside a
  directory that a sandbox mounts read-write (by the stamps under `~/.ai-sandbox`),
  and prints the install command. Trigger: the checkout's `bin/ai` on the host's
  `PATH` or called by path, which is how the toolchain is used today
  (`PROJECT_MAP.md`: each `bin/` subdirectory is meant for `PATH`; tree:
  `create-ai-sandbox.sh` resolves the checkout from its own location). The refusal
  guards against that accident only: it lives in a file a sandbox can edit, so what
  holds against an agent is that the host's `PATH` names the install root alone.
- A host run of the suite or of the acceptance script uses the exported copy. Inside
  a sandbox the suite runs from the repository as before; its temporary `HOME` holds
  no stamp, so the refusal does not fire there.
- Sandboxes mount `~/.ai-sandbox/installed/current/tools` read-only as `~/tools`. The
  automatic refresh from `DEV_TOOLS_DIR` and the three-place search for `tools/`
  (tree: `create-ai-sandbox.sh`, `context-statusline`) are removed; the
  `DEV_TOOLS_DIR` line in `~/.ai-sandbox/config` is no longer read.

### C-REPOS, the host-owned list of a sandbox's repositories (phase 5; used by 6)

- File `<sandbox dir>/repos`, mode 0600. The sandbox directory itself is not mounted
  into the container (only its subdirectories are; tree: the generated compose file),
  so no sandbox can read or write the list.
- One repository per line, fields separated by `|`:
  `<role>|<service>|<slug>|<dir>|<options>`.
  - `role`: `project` (exactly one line) or `extra`.
  - `service`: `github`, `bitbucket` or `none`.
  - `slug`: `<owner>/<repo>` or `<workspace>/<repo_slug>`; empty for `none`.
  - `dir`: for an extra, its directory name under the extras mount, one path
    component matching `[A-Za-z0-9][A-Za-z0-9._-]*` (so never `.`, `..`, a leading
    dot or dash, or a separator); the fixed value `.` for the project.
  - `options`: comma-separated `key=value`:
    `prefix=<branch prefix>` (GitHub; default `agent/`, D16);
    `default=merge|ff` (I9; default `merge`);
    `rules=checked|confirmed:<date>|waived:<date>` (C-RULES);
    `pipelines=confirmed:<date>` (C-PIPE).
- Only `ai-sandbox-repos` writes it. A slug is typed or confirmed by the user on the
  host; it is never taken unconfirmed from a file a sandbox can write. `add` refuses
  the repository the host's knowledge configuration names as its remote: a token for
  it inside a sandbox would pass by the two checks the host makes there (D1).
- `ai-sandbox-repos list | add <service>:<slug> [--as <dir>] | remove <dir> | check |
  refresh`, for the sandbox of the current directory (C-STAMP) or `--sandbox <name>`.
  `add` and `remove` take effect in a running sandbox without re-creating it. `remove`
  ends the token's coverage at the next refresh and keeps the clone, naming its path.
  Exit status: 0 done, 3 keyring unavailable, 4 a rule check failed, 1 anything else.
  `add` and `remove` are set-up steps typed on the host (I8); nothing a sandbox writes
  can ask for one.

### C-TOKEN, how a git token reaches a sandbox and is refreshed (phase 5)

- Host secrets live in the session keyring (libsecret, `secret-tool` [L1]):
  `service=ai-sandbox kind=github-app-key app=<client id>` holds the app's private
  key; `service=ai-sandbox kind=git-token sandbox=<sandbox id> host=bitbucket.org
  repo=<workspace>/<slug>` holds one repository access token with the Write
  permission ([B2]), which the user created for that sandbox (D10). The app's client
  id is in `~/.ai-sandbox/git-hosting`; no file holds a secret. The private key never
  leaves the host: it is the app's most valuable secret ([G7]).
- GitHub: the host authenticates as the app with an assertion signed with that key
  and valid for at most ten minutes ([G6]). Per owner on the list it finds the app's
  installation (none means the app is not installed there) and creates one
  installation token with `repositories` set to exactly that owner's listed
  repositories and `permissions` set to D12. The token lives one hour and is an
  opaque string of no fixed length ([G1]).
- Delivery: the host pipes git-credential records (`protocol=https`, `host`,
  `path=<slug>.git`, `username`, `password`, blank line; `x-access-token` for GitHub
  [G5], `x-token-auth` for Bitbucket [B3]) into
  `docker exec -i <container> sandbox-git-credentials`. One stream replaces the whole
  set, so a repository removed from the list loses its entry.
- Inside the sandbox the set is one file, mode 0600, read by git through a credential
  helper. One host can carry several tokens (one per GitHub owner, one per Bitbucket
  repository), so git inside is set to ask per repository path
  (`credential.useHttpPath`; without it git reuses one credential for the whole
  host, [L5]). `gh` obtains the token of the repository it acts on per invocation,
  in the environment of the `gh` process only (D13, [G9]). Remotes written in ssh
  form resolve over HTTPS.
- Refresh (U15): at every start, at every `ai-sandbox` entry, and from then on by a
  refresher. Every entry starts one as its own child, which ends with that entry; a
  lock per sandbox (the mechanism of the cache lock, tree: `flock`) lets one of them
  work at a time, and when its entry closes a waiting one takes over. So a sandbox
  is refreshed for as long as any entry to it is open, and no host process of this
  work outlives its entry. The working one replaces each GitHub token before it
  expires and runs C-RULES again each time; it reads the key from the keyring for
  each refresh and holds nothing in between (A13 has the fallback). A failed refresh
  keeps the old set, is tried again, and is written to `status/credentials`, which
  carries each token's expiry and each repository's branch prefix.
  `ai-sandbox-repos refresh` does the same on request and is never the only repair
  (I8). When the last entry closes while agent sessions inside go on, their GitHub
  access ends within the hour and returns with the next entry.
- A hosting credential inside a sandbox that is not in the delivered set (trigger: the
  user's `gh` logins made by hand inside sandboxes, the user's statement) is outside
  I2. At every start the host looks, as text, in the credential stores it knows and
  reports what it finds on the terminal and in `status/credentials` until it is gone.
- Refusals. Bringing a container up is refused, exit status 3, when the list names a
  repository that needs a token and the keyring cannot be read (the user's rule).
  Entering a running sandbox in that state only warns. A hosting service that cannot
  be reached does not block a start: the sandbox starts without a fresh token and the
  status says `offline` (inferred from the tree: the knowledge sync handles an
  unreachable remote the same way and never blocks a start).

### C-RULES, the check of hosting-side rules at token issue (phase 5)

- GitHub, with each token just created and before it is delivered, so at every
  refresh too; metadata read suffices for the three read endpoints ([G2]). Each
  property below must be met by a ruleset with `enforcement` `active` and
  `current_user_can_bypass` `never` ([G1]):
  - all branches: target `branch`, `conditions.ref_name.include` contains `~ALL`,
    `exclude` is empty, rules `deletion` and `non_fast_forward`;
  - all tags (U5): the same for target `tag`, with `update` added. `creation` is not
    asked for, since an agent creates tags; a repository in which the user restricts
    it as well passes.
  - outside the agent prefix (U4, U6, D16): target `branch`, `include` contains
    `~ALL`, `exclude` holds the prefix's pattern and nothing else, rules `creation`
    and `update` ([G17]). This is a ruleset of its own: the two rules in the
    all-branches ruleset would refuse every push an agent makes. Under `default=ff`
    the default branch may be excluded too, and `add` says what that gives up: I9 for
    that branch, and with it whatever a run on the default branch can read (C-PIPE).
- Releases are not refs. With Contents write a token creates, edits and deletes
  releases ([G2] lists no permission of their own), and no ruleset governs them. So
  the release description of U5 needs nothing added and cannot be granted alone.
  Editing a release moves no existing tag ([G1]). A repository with immutable
  releases enabled locks the assets and the tag of a published release and leaves
  title and notes editable; the price is that a release an agent publishes takes
  its tag name for good, also after the release is deleted ([G12]). That setting is
  the user's.
- Bitbucket: restrictions of kind `force` and `delete` with pattern `*`, which admit
  no exempt users, and, unless `default=ff`, a `push` restriction on the default
  branch that exempts the user alone ([B1]). No restriction there expresses "every
  branch but a prefix", and none covers tags. The check is the user's confirmation
  (D9): `add` asks for it and records `rules=confirmed:<date>`.
- A repository that fails gets no token; the others on the list get theirs.
  `status/credentials` and `ai-sandbox-repos check` name the repository and the
  missing rule. A rule the user repairs in the hosting service's interface is seen
  at the next refresh, with no host command (I8).
- Override: `ai-sandbox-repos add ... --waive-rules`, a set-up step, recorded in the
  list with its date and shown at every start. Its trigger is a repository on which
  the user cannot set the rules: the Bitbucket workspace if X3 shows its plan lacks
  the restrictions (A14), a GitHub repository whose plan has no rulesets ([G10]) or
  that the user does not administer. If X2 and X3 pass and the user administers every
  repository agents work in, phase 5's plan leaves the override out and says so.

### C-PIPE, what keeps pipeline secrets out of an agent's reach (phase 5)

With the Workflows permission (U16) an agent decides what a pipeline run does on
every ref it can write: a branch under its prefix, a tag it creates, a pull request
from such a branch. Whatever such a run can read is within the agent's reach, so
secrets are kept from it by where they are stored, not by what a workflow file says.
What GitHub documents:

- Repository and organization secrets reach any run in the repository: they "are
  read when a workflow run is queued", and only a run triggered from a fork goes
  without ([G13]). They are within an agent's reach, and a credential stored as one
  is the run's to use (condition 6).
- An environment's secrets "are only available to workflow jobs that reference the
  environment", and its deployment branches and tags decide which refs may ([G11]).
  With GitHub Pro both exist in private repositories; required reviewers do not
  ([G11]).
- The option "Protected branches only" does not serve (D17). "Selected branches and
  tags" does: a pattern is "matched against the `GITHUB_REF` of the workflow run", a
  run for a pull request carries `refs/pull/<n>/merge`, and a wildcard does not match
  `/` ([G11], [G14]).
- No token of a sandbox changes an environment, a ruleset or a secret: each needs the
  Administration, Environments or Secrets permission ([G2]), and D12 grants none.
- No token of a sandbox moves a branch an environment admits (I9). That includes the
  merge of its own pull request, which Contents write permits as a permission ([G2])
  and the `update` rule refuses, and the token of a workflow run, a different actor
  under the same rulesets (both inferred: A9, X2). That holds while no bypass list
  names an actor a run can act as (condition 6).
- That run token is otherwise the agent's to shape: a workflow file sets its
  permissions, publishing packages and starting other workflows among them ([G19]).
  It reads no environment the policy refuses and moves no ref the rulesets hold.

So a secret is out of an agent's reach when, in its repository:

1. it is stored in an environment, not at repository or organization level;
2. that environment's policy is "Selected branches and tags" and none of its patterns
   matches a branch under the agent prefix, a pull request ref or a tag. An agent
   creates tags (U5), so an environment that admits a tag pattern is within its
   reach: a release pipeline that needs such a secret runs from the default branch,
   or the user also restricts tag creation in that repository;
3. no workflow on a branch that environment admits acts on content an agent
   supplies. Events that start the default branch's workflow carry such content;
   examples, not a complete list: the head of a pull request under
   `pull_request_target`, the text of an issue, a comment, a label or a release, the
   artifacts of an agent's own run under `workflow_run`, the inputs of a dispatch,
   which an agent can send with Contents write or from a run of its own ([G2],
   [G14], [G19]). GitHub documents the risk ([G14], [G15]) and no setting removes it;
4. a cloud role that trusts the repository's identity tokens is limited to an
   environment that exists and meets condition 2, or to the default branch: the
   token's subject names the environment or the ref ([G16]), and a role that checks
   the repository alone trusts every run;
5. the repository has no self-hosted runner: one "can be persistently compromised
   by untrusted code in a workflow" ([G15]), and where the runner is a machine of
   the user's, G3 fails with it;
6. no credential that may bypass the rules is within a run's reach. The bypass lists
   of the three rulesets (C-RULES) name no actor a run on an agent's ref can act as:
   no deploy key, no app or user whose credential a run can read, and not the
   integration behind the run's own token (the actor types: [G1]). And nothing
   stored at repository or organization level, or in an environment that admits a
   ref an agent writes, is a credential of the user or of an actor on those lists: a
   personal token, a deploy key, an app's key. With one of these a run moves the
   default branch while C-RULES passes, and conditions 1 to 5 fall with I9;
7. no run on a branch an environment admits writes a secret, or a value derived
   from one, where an agent then reads it (U17): a check's summary and annotations,
   a log or an artifact. The read covers every run in the repository ([G2]).
   Redaction is documented for logs only, "is not guaranteed" there and misses
   derived values ([G15]).

The toolchain enforces I9 through C-RULES and takes these conditions on the user's
confirmation: no token of this design reads a bypass list ([G1]) or a secret's name
([G2]), and no permission shows 3, 4 or 7. With Actions read, which the app holds
(U17), the host could read each environment's policy, but not which environment
holds a secret (Environments read, [G2]); and an agent's workflow creates an empty
environment by naming it ([G20]), so a check on policies alone would refuse over
those. A token the host keeps to itself with Environments read as well could check
condition 2 at every refresh; that is one more permission on the app and is not
built unless the user asks.
Nothing a sandbox does makes the confirmation stale: the settings need permissions
D12 withholds, and a workflow on an admitted branch changes only by the user's
merge. The user's own later change does, such a merge included (residual risk). So
`ai-sandbox-repos add` states the conditions, asks the user to confirm them for the
repository and records `pipelines=confirmed:<date>`; a repository without it gets no
token. The settings themselves are the user's work in the hosting service
(non-goals). On Bitbucket no source fetched for this spec separates a pipeline's
variables from a branch an agent can push; the confirmation there is that Pipelines
is off for the repository or holds no secret.

### C-WORKSPACE, the layout of a sandbox's clones on the host (phase 6)

```
~/.ai-sandbox/workspaces/<sandbox id>/
  project/        the sandbox's clone of the project  -> mounted at the project's path,
                  the path the user's clone has on the host
  extra/<dir>/    one clone per extra repository      -> extra/ is mounted once, at ~/repos
```

- `.env` carries `SANDBOX_TREE=clone|shared`. In `clone` mode no directory of the
  user's clone is mounted.
- The workspace is not under the sandbox directory. `ai-sandbox-rm` keeps it and says
  so; with `--with-clones` it first lists, per clone, uncommitted and unpushed work
  (queried through C-GIT, as text) and asks again.
- A new sandbox whose list names a hosting service for the project is in `clone`
  mode from creation. Its clone is seeded from the user's tree (tracked and
  untracked files, `.git`), or with `--fresh` by cloning from the remote inside the
  sandbox. An extra is cloned inside the sandbox, or with `add --from <directory>`
  seeded from an existing checkout (trigger: the user's practice of a parent
  directory that already holds the checkouts). Seeding refuses a tree whose git
  configuration holds a remote URL with a password part, naming the line and not
  the value (trigger: the URL form Bitbucket documents, [B3]).
- A tree is sandbox-written when the stamp of an existing sandbox names it, or an
  ancestor of it, as a project mounted read-write, or when
  `~/.ai-sandbox/written-trees` does; `ai-sandbox-rm` adds a `shared` sandbox's
  project path to that file before the stamp goes. A command that seeds also lets the
  user declare the tree sandbox-written (trigger: sandboxes removed before this
  phase left no record).
- One rule for every seed, at creation, at `add --from` and at conversion (D14). A
  tree that is not sandbox-written is copied and stays where it is. A sandbox-written
  tree is moved into the workspace as the sandbox's clone, and its path gets a new
  clone the host makes from the remote the list names, never from the old tree's
  configuration. While another existing sandbox still mounts that path through an
  ancestor, the command refuses and names that sandbox: the new clone would be
  writable again at once.
- Before a tree is moved the command lists (I5), through C-GIT and as text, what it
  holds that the remote does not: unpushed branches and commits, stashes, uncommitted
  changes, untracked and ignored files by directory, local git settings and hooks;
  then it asks. Nothing is carried over on its own; the user's unpushed branches are
  fetched into the new clone as data, through C-GIT, on request. Declining leaves the
  sandbox `shared`, or the extra not added.

### C-DOCKER, project containers inside the sandbox (phase 8)

- The engine is one per host (D18), `SANDBOX_ENGINE=rootless|sysbox` in
  `~/.ai-sandbox/config`, set from X4's result (U11):
  - `rootless`: every sandbox runs on the user's rootless Docker daemon after its
    next re-creation (I6). Container root is the user's own uid on the host ([R1]),
    so nothing a sandbox writes on a bind mount belongs to root.
  - `sysbox`: a sandbox with Docker enabled runs under `runtime: sysbox-runc` on the
    existing daemon, and the workspace root (C-WORKSPACE) is a mount point with
    `nosuid` and `nodev`, so that a file container root wrote there ([S5]) gains
    nothing when the host executes it ([L7]). Creating a `clone` sandbox is refused
    while the workspace root is no such mount, with the one-time set-up command.
- Either way a sandbox with Docker enabled has an ordinary Docker inside, and its
  compose file carries what X4 showed the engine to need and nothing else. Under
  `sysbox` that is no `security_opt` relaxation and no fuse or tun device (today's
  `--with-docker` block, tree).
- The inner image store is `<sandbox dir>/docker/`, mounted as the inner daemon's
  data root and used by one container at a time ([S1]). It is kept across re-creation
  (D15); `ai-sandbox-gc` reports its size and prunes on request; `ai-sandbox-rm`
  removes it.
- Shared toolchains appear read-only under `/opt/ai-toolchains/<kind>/<version>/`
  (`python` from uv, `java`, `node`), from a host-owned root; the same path is what a
  project's compose file binds into its containers. `java` there is the host's SDKMAN
  candidates the sandbox already mounts (tree), not a second store of JDKs.

## Host commands and phone work

I8 against every command of the contracts that is typed, or runs, on the host.
"Set-up" is done at the host before the user leaves and waits for the user's return
when the need arises later; "everyday" must need no typing on the host.

| Host command or step | Kind | While the user is away, and if an assumption fails |
|---|---|---|
| `ai-sandbox`, the entry | everyday, typed once before leaving | Phone work runs in agent sessions started from an entry that stays open (A23); it is the condition of every row below. Starting or re-entering a sandbox from the phone is not built (non-goals). |
| Token refresh (C-TOKEN) | everyday, automatic | Needs no command while an entry is open; an unreachable hosting service is retried, an unreadable keyring falls to A13. If every entry ends while sessions inside go on (a closed terminal, a lost connection to the host), nothing on the phone repairs it (C-TOKEN); only a refresher that outlives the entry would, which the user did not choose (U15). |
| `ai-sandbox-repos refresh` | repair | Never needed: the refresher does the same. |
| The rule check (C-RULES) | automatic, at every refresh | A rule that stops holding costs that repository its token; the user repairs the rule in the hosting interface and the next refresh restores it. A check replaced by a confirmation (A10) no longer sees such a change. |
| The user's merge into the default branch (U4) | everyday, in the hosting interface | From the phone, with the user's bypass (A22). |
| `ai-sandbox-repos add`, `remove`, `--waive-rules`, the two confirmations; storing the app's key or a Bitbucket token | set-up | A repository that is not on the list cannot be added from the phone; the agent works without it until the user's return. A Bitbucket token that stops being accepted ends Bitbucket git inside until the user stores a new one. |
| `create-ai-sandbox.sh`, re-creation, conversion to `clone`, `ai-sandbox-rm`, `-gc`, `-stop`, `-restart` | set-up | Wait. A stale sandbox is refused at start (I6), which is at the host. |
| `ai-sandbox-install` | set-up | A change an agent makes to the toolchain takes effect when the user installs it (I3b, by design). |
| `ai-knowledge sync`, and the confirmation before the integrator's `main` is pushed (U12) | periodic, at an entry or by hand | Proposals and an integration made while away reach the remote at the user's next sync on the host, as today. |
| AI logins (phase 7) | set-up; renewal inside | A login made inside renews itself there (A19). A login copied with `--host-logins` is renewed by `ai-sandbox-account` on the host, so that option is not for a sandbox worked from the phone. |
| Project containers (phase 8) | everyday, inside the sandbox | No host Docker command; the engine's set-up is one batch. |
| The host itself: restart, suspend, network | - | Sessions end, as today; containers do not restart on their own (tree: `restart: "no"`). |

## Assumptions

Status: **verified** (read in the tree or in cited documentation), **inferred** (follows
from documentation, not observed), **guessed**. No row has been checked on a host.

| # | Assumption | Status | Settled by | If it fails |
|---|---|---|---|---|
| A1 | A host-owned repository fetches through a remote program that starts a container; objects arrive and nothing from the served repository runs on the host | inferred ([L2], [L4]) | X1 | the container writes the sandbox's refs into a bundle file and the host-owned repository fetches from that file ([L6]); no git serves the clone on the host, so I3a stays whole |
| A2 | One throwaway container per sync is quick enough for every `ai-sandbox` entry | guessed | X1 (timed) | a running sandbox is synced through `docker exec` into itself; only stopped ones use the throwaway container |
| A3 | `ai-sandbox-migrate-knowledge` has finished on every host, so phase 1 deletes it | guessed (the project notes list it as pending) | the user's check in phase 1's host batch | the user runs it once before phase 1 is installed |
| A4 | The suite at the base: 20 files, 1217 cases, 2 failing, both in `test-delegate.sh` (cases 54 and 59) | verified (run in a sandbox at `96540a5`, the suite's own summary lines) | - | - |
| A5 | The files `create-ai-sandbox.sh` generates are a deterministic function of options and environment, so byte identity can pin the split | inferred (tree: no timestamp in a generated file except `.seeded`) | phase 3's first task, two runs on the tree it starts from | the pin excludes the named non-deterministic lines, listed in the plan |
| A6 | Docker resolves a symlinked bind source at each container start, so a restart picks up `installed/current` | inferred | phase 4's host acceptance | the compose file names the resolved revision and an install tells which sandboxes to re-create |
| A7 | An installation token of an app owned by and installed on a personal account can be limited per request to named repositories and permissions and lives one hour | verified ([G1], [G8]) | - | - |
| A8 | git over HTTPS and `gh` work inside a sandbox with a delivered installation token, and a replaced token is picked up without restarting anything | first half verified ([G5], [G9]); the refresh inferred | X2 | the refresh also restarts what holds the old token; if `gh` cannot work this way, the user's manual `gh` login stays for GitHub, phase 5 covers git only, and while that personal token is inside the user's role stays off the bypass lists; I9 cannot be enforced against that token, so U4 returns to the user |
| A9 | Rulesets bind the app's token and the token of a workflow run, a merge through the API included: with an empty bypass list, and also when the administrator role is on the bypass list | first half inferred ([G3], [G4], [G17]); second half guessed, no sentence found | X2 | C-RULES takes the user's recorded confirmation that the bypass list is empty (the token cannot read the list: [G1] returns `bypass_actors` only with write access to the ruleset). The prefix ruleset then excludes the default branch, which gets "require a pull request" with one approval that must cover the last push ([G1]): the user approves on the phone instead of bypassing, and the setting that lets workflow runs approve pull requests stays off ([G18]) |
| A10 | `current_user_can_bypass` is returned to an installation token and describes that token | guessed ([G1] says "the user making the API request") | X2 | the GitHub check becomes a recorded confirmation by the user, as on Bitbucket |
| A11 | `~ALL` in a tag ruleset's condition covers all tags | inferred ([G1] words it for branches) | X2 | the check accepts the pattern X2 shows for "all tags" |
| A12 | `secret-tool` stores a multi-line secret from standard input | verified ([L1]) | - | - |
| A13 | A keyring lookup keeps working from the `ai-sandbox` command for as long as its session is open, for hours and with the screen locked, and without a desktop or with a locked keyring it fails promptly instead of waiting for a prompt | guessed ([L1]: "If necessary an item will be unlocked") | X2 | lookups run under a time limit and a timeout is the refusal; if the keyring cannot be read later in a session, the refresher reads the app's key once, when the entry starts it, and keeps it in its own memory until that entry closes, never on disk |
| A14 | Bitbucket Cloud offers `force`, `delete` and `push` restrictions on the workspace's plan, they bind a repository access token (a `push` restriction that exempts the user alone refuses the token), a token with Write alone can also fetch, and tags stay unprotected | inferred ([B1], [B4]; [B2] does not say that Write includes Read) | X3 | the Bitbucket repository gets a token only under a recorded waiver the user gives, or stays as today; the token gets Read as well |
| A15 | Under rootless Docker this image starts with the project mount, the overlay cache volumes and a display; the limits of the compose file are in force; files written from either side of a bind mount are usable on the other | guessed; the documentation names the conditions: cgroup v2 with systemd and delegated controllers, a kernel from 5.11 for `overlay2`, container uid 0 as the user ([R1], [R2], [R3]) | X4 | rootless Docker is not taken and Sysbox with `nosuid` is tried (A16), except in the two outcomes X4 returns to the user |
| A16 | This image starts under Sysbox with the same mounts, display and limits; the host's release and kernel are supported by its package | guessed; the package part inferred ([S2], [S3]; the sandbox shows kernel 6.8) | X4 | if neither engine passes, phase 8 keeps today's `--with-docker` for the projects that need Docker and delivers only the persistent store and the toolchains; the wall goes back to the user |
| A20 | An ordinary Docker inside a sandbox runs the multi-server Compose project and the Raspberry Pi Zero emulation, and inner images persist in a per-sandbox directory: under Sysbox, and inside a container of a rootless daemon | guessed. For rootless the documentation shows only the reverse nesting, a rootless daemon inside a rootful one, and that with `--privileged` ([R3]) | X4 | as A15 for rootless, as A16 for Sysbox |
| A21 | A directory can be made a `nosuid`, `nodev` mount point that survives a restart of the host, Docker binds from it, and work inside the sandbox is unaffected | inferred ([L7]) | X4 | root on bind mounts under Sysbox returns to the user as U11's question |
| A22 | The user can merge a pull request into a branch whose updates are restricted, from a phone, with the bypass kept for their role | guessed, no sentence found | X2, the user's step on the phone | the default branch takes A9's fallback rule: the user approves on the phone, no bypass is needed |
| A23 | Phone work runs in agent sessions that are children of an `ai-sandbox` entry left open on the host | inferred (probe in the dev-tools sandbox on 2026-11-11: the agent session's parent is the shell the entry started; tree: `ai-sandbox` is the toolchain's only way in) | the user, with phase 5's host batch | only a refresher that outlives the entry serves such sessions: U15 returns to the user |
| A17 | The images sandboxes would duplicate are small against the free disk | guessed | X4 (measurement first) | pruning by default; deduplication below the engine returns to the user as a spec change |
| A18 | Toolchains built for glibc run when bound into the projects' Debian-based containers | guessed | X4 | toolchains are shared with the sandbox only |
| A19 | Each AI tool, and the IDE whose licence is copied from the host today (tree), can be logged in or activated inside a sandbox, through the sandbox's display where a login needs a browser; the login survives re-creation and renews itself inside without the user | inferred (tree: the seed runs once and keeps later logins; `ai-sandbox-account`) | phase 7's first task, on the host | that tool keeps a host-copied login as a named exception the user approves; a tool whose login lapses and cannot be renewed from the phone is named in the phase's report (I8) |

## Experiments

Run by the user on the host; none has been run. The phase that needs one starts with
it: its plan's first task writes the exact commands as one batch and what to paste
back, and the rest of the plan is written on the answer. X2 to X4 do not depend on
earlier phases and may be run together with X1 to save a round.

| | Tries | Pass | Decides |
|---|---|---|---|
| X1 | From a new host-owned repository, a fetch through C-GIT's container from a clone prepared to leave a marker if the host ran git in it; the same fetch timed | objects arrive, no marker on the host, the start path stays within a delay the user accepts | A1, A2; phase 1's transport |
| X2 | A GitHub App on the user's account with D12's permissions, installed on a throwaway repository, and a token limited to it: the attempts listed below | the pass line listed below | A8-A11, A13, A22; phase 5 |
| X3 | A throwaway repository in the Bitbucket workspace with `force` and `delete` on `*`, a `push` restriction on the default branch that exempts the user alone, and a Write token: a fetch, a push to another branch, a push to the default branch, rewrite and deletion of a branch, the same on a tag | fetch and push work, the push to the default branch and the branch attempts refused; the tag result recorded | A14; phase 5 |
| X4 | The image sizes first; then one existing sandbox and the multi-server Compose project on each engine in turn, as listed below | one pass line for both engines, listed below | U11; A15-A18, A20, A21; phase 8 |

**X2, attempts.**
- The three rulesets of C-RULES with an empty bypass list, then with the
  administrator role on it; the rulesets read back with the token.
- What must be refused: rewrite and deletion of a branch and of a tag; creating and
  updating a branch outside the prefix; a push to the default branch; a merge of the
  token's own pull request through the API, which Contents write permits ([G2]);
  moving a tag. The same from a workflow run on an agent branch with the run's own
  token.
- What must work: a push under the prefix, a tag created, a release's notes edited;
  a run's checks, log and artifacts read with the token (U17).
- An environment limited to the default branch, referenced by a job on an agent
  branch, on a pull request and on a tag the token created.
- The user merges the pull request from the phone.
- The token delivered into a running sandbox, a push and a pull request; then a
  second token delivered and the first revoked.
- The app's key stored in the keyring and read from a terminal, from a process left
  running in that terminal for several hours, without a desktop, with the screen
  locked.
- Recorded, not part of the pass line: whether the token writes the repository's
  wiki, which no ruleset names.

**X2, pass.** The refusals hold in both bypass configurations, for the token and for
the workflow run; what must work does; none of the three jobs gets the
environment's secret; `current_user_can_bypass` reads
`never`; the user's merge from the phone succeeds; push and pull request work before
and after the replacement; the keyring cases answer A13.

**X4, attempts.**
- The sizes of the images the projects use against the free disk.
- One existing sandbox and the multi-server Compose project, with the Raspberry Pi
  Zero emulation, on each engine in turn: the user's rootless Docker daemon, set up
  as its documentation says for limits ([R3]); and Sysbox on the existing daemon
  with the clones directory on a `nosuid`, `nodev` mount.
- On each: the inner store in a per-sandbox directory across a re-creation, a
  toolchain bound into a project container, a serial device passed through.
- One adaptation is allowed: the user id the image runs as. Today it is the host
  uid (tree: `USER_ID=$HOST_UID`), and under rootless Docker only container uid 0
  maps to the user ([R1]); the sandbox may run as the id the engine maps to the
  user, if the AI tools and the display still start under it. Whatever else an
  engine needs is recorded, not made.

**X4, pass line, the same for both engines.**
1. The sandbox starts with the project tree and the cache overlay volumes usable,
   files written from either side usable on the other, and a display.
2. The memory, CPU-set and process limits of the compose file are in force inside.
3. An ordinary Docker inside runs both workloads, neither it nor the engine is on a
   copying fallback driver, and a service of the Compose project is reached from the
   host the way the user reaches it today.
4. Inner images are still there after a re-creation.
5. A file that root inside makes set-user-ID in the clones directory runs without
   root's rights on the host.
6. The sandbox container is not privileged and has nothing relaxed or added beyond
   today's `--with-docker` block (tree: seccomp and AppArmor unconfined, the fuse and
   tun devices).

**X4, what it decides.** Rootless Docker if it passes, otherwise Sysbox with `nosuid`
if that passes, otherwise A16's fallback (U11). Two outcomes are not decided by rule
and return to the user with the record: an engine that meets points 1 to 5 only
above the ceiling of point 6 (the one nesting [R3] documents for rootless Docker
uses `--privileged`); and a serial device that cannot be reached at all on the
engine that would be taken, since D18 moves every sandbox to it. A serial device
that needs a host rule is still a pass. Recorded for phase 8's plan and shown to
the user with it: what the sandbox container needs on each engine for the inner
Docker, the file system of the store, the owner on the host of a file root wrote
inside.

## Phase 1: host git leaves the sandbox-writable trees

**Establishes.** I3a for everything the toolchain runs; I3c for the knowledge clone;
I3d for role and project identity; I2 for the knowledge remote. Findings C1, H7, H8 and
the knowledge-clone part of H4.

**Starts with** X1. Its scope is the user's (U14).

**Goal, observable when done.**
- `ai-knowledge sync` and `sync --all` do what they do today (proposals pushed, `main`
  rendered, the integrator's `main` and reports pushed, closed branches removed) while
  no host git process has a sandbox-writable directory as its repository or working
  tree.
- Whatever a sandbox writes into its clone's configuration or refs changes neither
  where the host pushes nor what it compares against.
- The host writes nothing below `<sandbox dir>/knowledge`. Sync state reaches the
  sandbox through C-STATUS and `sandbox-doctor` shows it.
- `ai-sandbox`, `create-ai-sandbox.sh` and `ai-knowledge` resolve the project without
  running git in it, also from a subdirectory.
- `ai-sandbox-migrate-knowledge` is gone (A3).

**Contract needed.** None.

**Delivers.** C-GIT, C-STATUS, C-KNOW, C-STAMP.

**Closing check.** The structural search of C-GIT finds no git call outside its two
functions; a test syncs a clone prepared as in X1 and finds no marker and the push at
the configured remote; a test moves the project stamp's inputs inside the tree and
finds identity and role unchanged; one sandbox re-created and synced on the host.

**Touches the long file.** The task list assumed C1 lies outside
`create-ai-sandbox.sh`. Its sandbox side does not: the knowledge mounts in the compose
file, the knowledge rows of `sandbox-doctor` and the entrypoint are generated there
(tree). Phase 1 therefore closes before phase 3 takes its pins.

**For the user.** Every sandbox is re-created once (I6); the knowledge skills inside
keep working unchanged, since they neither fetch nor push (tree: the `propose-rule`
skill forbids both).

**Assumptions.** A1, A2, A3.

## Phase 2: host audio off by default

**Establishes.** I3e. Finding C2. The default is the user's (U1).

**Goal.** A sandbox created or re-created gets no host sound socket and no sound
device unless the user asked for audio for that sandbox. A setting remembered from the
time when on was the default (tree: `SANDBOX_WITH_AUDIO=1` is written for both cases)
does not count as a request: a re-creation without an explicit `--audio` turns such a
setting off and says so. A request made with `--audio` from this phase on is
remembered like the other options of creation, until `--no-audio`. `--audio` states what it shares, microphone included, and that I3e
does not hold for that sandbox.

**Contract needed.** None. **Delivers.** Nothing a later phase plans against.

**Closing check.** A test generates the compose file for a fresh sandbox, for one with
the old remembered value and for one with `--audio`, and finds the socket, the device
and the cgroup rule only in the last.

**Timing.** It edits the audio section of the long file, so it lands before phase 3's
pins are taken or after phase 3 closes, never in between. An opted-in sandbox still
exposes the host daemon; a playback-only path is phase 10's.

## Phase 3: split of `create-ai-sandbox.sh`

**Class.** Refactor flag: behaviour unchanged.

**Establishes.** G4.

**Goal.** The files of C-MODULES exist with the content the script has when the phase
starts, the entry script holds only option defaults and the stage order, and every
file the toolchain generates is byte-identical to what the starting tree generates
for the same options and environment.

**Pins, run once before the first change, on the tree the phase starts from** (the
close of phases 1 and 2, not the commit this spec was written at). The existing
suite, whose result must be the same before and after (D15 for the two cases that
fail today, A4), and a new pin that generates every artefact (compose file, `.env`,
Dockerfile and the baked files, display launchers, `xpra.conf`, the environment
block) for a matrix of options the plan lists (display modes, Docker, audio,
knowledge configured or not, IntelliJ and SDKMAN present or absent) and stores the
results. The repository configures no shell linter, so there is no further guard to
run with the pins; adding one is not part of a refactor.

**Commits.** The move is one mechanical commit produced by a script kept in the
repository and re-runnable; sourcing lines and the entry script are hand edits in
their own commits. One gate for the phase.

**Contract needed.** None. **Delivers.** C-MODULES.

**Closing check.** Both pins unchanged on the result; the mechanical commit
reproduced by re-running its script on its parent.

**After it closes** the user's independent review by other agents and models has
small files to read. Its findings come back through the spec's author, who assigns
them to phase 9 or 10 or brings them to the user as a spec change.

**Assumptions.** A4, A5.

## Phase 4: the host runs an installed revision

**Establishes.** I3b. Finding H3. Design work.

**Goal.**
- Every host entry point of the toolchain, the host's status line included, runs from
  `~/.ai-sandbox/installed/current`, and refuses to run from a directory a sandbox
  mounts read-write.
- Nothing on the host sources, executes or mounts as code a file from a working tree.
  Editing a helper or a file under `tools/` in the dev-tools sandbox changes nothing
  on the host and in no other sandbox until the user installs a revision.
- Installing is one command that names a revision, shows what changed since the
  installed one and asks.
- Inside a sandbox the suite still runs from the repository; on the host it runs from
  the installed revision.

**Contract needed.** C-GIT from phase 1, for `--from`; `install.sh`, `compose.sh` and
`image/` from phase 3.

**Delivers.** C-INSTALL.

**Closing check.** The manifest check passes; a search finds no read of
`DEV_TOOLS_DIR` and no mount source outside the install root for `tools/`; a test runs
an entry point from a directory stamped as a sandbox's project and gets the refusal;
on the host, a change in the working tree is shown to have no effect before
`ai-sandbox-install` and to take effect after it.

**For the user.** One first install by hand, from the phase's batch; the working
tree's `bin/ai` leaves the host's `PATH`. What remains is that the user reads what
they install, and until phase 6 whatever the user runs on the host from the checkout
by path (C-INSTALL; residual risk).

**Assumptions.** A6.

## Phase 5: repository list, git tokens, hosting-rule check

**Establishes.** I1 for git credentials, I2, I9, I3d for token scope, and I8 for git
and the hosting service. Design work.

**Starts with** X2 and X3.

**Goal.**
- Each sandbox has a host-owned list of its repositories; the user adds and removes
  extras with one command and without re-creating the sandbox.
- `git push`, `git fetch` and `gh` work inside without a login by the user: on
  GitHub with a token for exactly the listed repositories and D12's permissions,
  kept fresh while an `ai-sandbox` entry is open, with nothing typed on the host
  (U15, I8); on the Bitbucket repository with its own token, for git.
- An agent's pushes land under the repository's prefix and as new tags, nowhere
  else; the user merges into the default branch from a phone (I9, U5). The pushes
  start pipelines and may change workflow files, and the agent reads the runs'
  results and logs (U6, U16, U17).
- No token is issued for a repository whose rules fail C-RULES, unless the user
  waived the check, or whose pipeline conditions the user has not confirmed
  (C-PIPE); the reason is visible on the host and inside.
- No personal token of the user stays in a sandbox unnoticed (C-TOKEN): the phase's
  batch has the user revoke every one ever used inside a sandbox and log `gh` out
  there.
- The states of the user's flow: no hosting repository on the list (nothing is
  issued, nothing is refused); a slug that does not exist or that the app is not
  installed on (`add` refuses and prints where to install it); keyring unreadable
  (start refused, exit status 3); hosting unreachable (start proceeds, status
  `offline`); a Bitbucket repository whose token is not in the keyring (`add` prints
  how to create and store it and issues nothing); a GitHub token that expired
  (C-TOKEN; the message inside names the expiry and that an open entry renews it);
  a push outside the prefix (the hosting service refuses it; the generated
  environment block and `status/credentials` name the prefix).

**Contract needed.** C-STAMP and C-STATUS from phase 1; `image/` and `compose.sh`
from phase 3.

**Delivers.** C-REPOS, C-TOKEN, C-RULES, C-PIPE; a proposal to the knowledge
repository for the rule sentence about git credentials; the generated environment
block updated, the branch prefix included.

**Closing check.** Tests against stubbed `secret-tool` and hosting endpoints: the
token request names exactly the listed repositories and D12's permissions; the token
string occurs in no generated file, no `docker` argument and no environment; a failing
rule yields no delivery for that repository and status 4 from `check`, and so does a
prefix ruleset that is missing or excludes more than the prefix; a repository without
the pipeline confirmation gets no token; with two owners on the list git inside
presents each repository's own token; `add` refuses a `dir` of `..` and the knowledge
remote; a start reports a `gh` login left inside; the refresher replaces a token
before its expiry; with two entries open, closing either leaves the tokens
refreshed, and after the last one no process is left. On the
host: the attempts of X2 and X3 repeated from inside a real sandbox are refused; a
push made more than an hour after entry succeeds with nothing typed on the host in
between; the user merges that branch's pull request from the phone.

**Assumptions.** A7 to A14, A22, A23.

## Phase 6: separate clones

**Establishes.** I3a for the user's own git: the user's clone is no longer something
an agent can write. Findings H5 and H6.

**Goal.**
- A sandbox in `clone` mode mounts no directory of the user's clone. It works in its
  own clone at the same path inside the container; extra repositories appear under
  one mount.
- An existing sandbox is converted by an explicit command, never by a plain
  re-creation. After it, the tree at the user's path is one no sandbox ever wrote,
  and what the sandbox wrote before is in the sandbox's clone; the same holds for
  every tree a clone is seeded from, at creation and at `add --from` (C-WORKSPACE,
  D14; trigger: such a tree was writable from a sandbox until now, H5).
- `ai-sandbox-rm` and `ai-sandbox-repos remove` never delete a clone without listing
  its uncommitted and unpushed work and asking again (I5).
- States: no extras (only the project mount); a `dir` already taken (`add` refuses);
  a clone that cannot be made because the token or the network is missing (the entry
  stays, `status/repos` says pending, the next refresh retries); an interrupted
  conversion (a rerun completes it, and the user's path is never left without a
  tree); a sandbox on a parent directory or on a project without a hosting remote
  (it stays `shared`, its list still decides its tokens, and the way to separate
  clones is to remove the parent's sandbox and create one on one of the repositories
  with the others added as extras; the parent's checkouts are sandbox-written and
  are replaced by new clones on the way).

**Contract needed.** C-REPOS and C-TOKEN from phase 5; C-GIT from phase 1.

**Delivers.** C-WORKSPACE; `SANDBOX_TREE`.

**Closing check.** A test generates the compose file of a `clone` sandbox and finds
no bind whose source is the project directory or lies inside it; a test removes a
sandbox with an unpushed commit and finds the workspace in place and the commit
listed; a test converts a tree prepared as in X1, runs the user's ordinary git
commands at the user's path and finds no marker and nothing there the remote does
not hold; a test creates a sandbox over, and adds an extra from, a tree that a
removed `shared` sandbox had mounted and finds the tree moved and a new clone at its
path; a test finds the refusal while a sandbox on an ancestor directory exists. On
the host: one project converted, an agent's push arriving in the user's clone by an
ordinary fetch from the hosting service.

**For the user.** Two trees per converted project: the user's and the sandbox's.
Local state at the user's path is listed and brought over by the user, not carried
along (C-WORKSPACE). Uncommitted work of an agent is visible only inside the sandbox
or under the workspace path, which stays a sandbox-written tree: no git and no build
there on the host. A tree that a sandbox removed before this phase had mounted is
known only to the user, who declares it when a command asks for a seed.

**Assumptions.** None beyond phase 5's.

## Phase 7: AI credentials and stores per sandbox

**Establishes.** I1. Findings H1 and M1.

**Goal.**
- By default, creating a sandbox copies nothing from the host that authenticates: no
  token file, cookie store, browser or desktop-app profile, licence key, history or
  list of other projects. What is copied is an allow list of settings files, named in
  the plan and approved with it (who may see what is the user's rule to set).
- The login mode is an option of creation (U2): with `--host-logins`, remembered per
  sandbox, the host's stores that authenticate are copied as today; which they are
  is a second list in the plan, approved with it, and history and lists of other
  projects are in neither. The option says that I1 does not hold for those logins
  and that only the host renews them (I8, the table of host commands).
- Without the option each AI tool is logged in inside the sandbox, once; that login
  survives re-creation and renews itself inside (A19). `ai-sandbox-account` re-pulls
  the host's logins only for a sandbox created with the option.
- A sandbox created before this phase holds copied logins and no recorded mode. It
  counts as created with `--host-logins`, so `ai-sandbox-account` keeps renewing its
  logins and none lapses mid-session (I6; inferred: the answer that changes nothing
  for a sandbox in use). Every start reports that I1 does not hold for it, with the
  one command that replaces the copied logins with logins made inside; that command
  lists which host logins were ever copied, so the user can renew them. Re-creating
  such a sandbox without the option does not record the default mode, so it is not
  left unrenewed while it still holds copied logins.
- The Antigravity brain and conversations are per sandbox. The project's Claude
  history and memory stay shared with the host as today (U9).

**Starts with** the login check of A19 on the host.

**Contract needed.** `seed.sh`, `options.sh` and `compose.sh` from phase 3.

**Delivers.** The allow list as one table in the library, replacing the deny list
(tree: `ai_sandbox_seed_excludes`, `ai_sandbox_seed_paths`).

**Closing check.** A test seeds from a fake home that holds every authenticating
store today's seed reaches (tree: `ai_sandbox_seed_paths`) and finds none of them in
the sandbox directory, and with `--host-logins` exactly the plan's second list; a
sandbox without a recorded mode is reported at start and still renewed;
the compose file of a new sandbox has no read-write bind of a host directory shared
with another sandbox. On the host: a new sandbox logged in inside, re-created, still
logged in.

**Dependants outside the phase.** `ai-sync` reads the Claude memory and the brain
directories on the host (tree); the plan's impact set decides what it reads after
the move.

**Assumptions.** A19.

## Phase 8: project containers inside the sandbox

**Establishes.** G3 for the user's Docker workloads: compose files, test containers
and Docker-using scripts an agent wrote run inside the sandbox, not on the host's
daemon; and nothing a sandbox writes on a bind mount of its clones acts as root on
the host (U11). Part of M3. I8 for the project's containers, which the agent runs
itself.

**Starts with** X4, measurement first. Design work: the plan is written on X4's
record.

**Goal.** Sandboxes run on the engine X4 selected (C-DOCKER). A sandbox with Docker
enabled has an ordinary Docker inside, with no more relaxation than X4 showed that
engine to need; the multi-server project and the Raspberry Pi Zero emulation run
there; images pulled inside survive a re-creation; `ai-sandbox-gc` shows and prunes
each sandbox's store; uv-managed Python, the JDK and Node are available read-only at
one path, to the sandbox and to project containers that bind it.

**Contract needed.** `compose.sh`, `devices.sh`, `resources.sh`, `start.sh` and
`image/` from phase 3; C-WORKSPACE from phase 6 for the clones directory. Under
`rootless` every `docker` call of the toolchain changes daemon and ownership, so the
phase also plans against C-GIT's throwaway container (the id it runs as), the
`docker exec` of C-KNOW and of C-TOKEN's delivery, and the capacity check, which
counts both daemons while sandboxes not yet re-created run on the old one (I6).

**Delivers.** C-DOCKER.

**Closing check.** A test generates the compose file for each engine value and finds
what X4's record prescribes: under `sysbox` the runtime line, no relaxation and the
store mount, and the refusal while the workspace root is no `nosuid` mount; under
`rootless` no limit or device the engine would ignore silently, and the capacity
check counting a sandbox left on the other daemon. On the host, X4's pass line
repeated with the real toolchain, and under `rootless` a knowledge sync and a token
delivery.

**For the user.** One set-up batch on the host, with root where the engine needs it
once: for rootless Docker its installation, the delegation of the cgroup controllers
and the start at boot ([R2], [R3]), and every sandbox re-created once; for Sysbox the
package and the `nosuid` mount.

**What the engines do not give.** An AppArmor profile is applied to a container
under neither ([R2], [S4]). Under rootless Docker container root is the user ([R1]):
a break-out ends with the user's rights, not root's. Its documented limits are what
X4's pass line tests: the storage driver, limits only with cgroup v2 and delegated
controllers, container addresses the host does not reach, ports below 1024 ([R2],
[R3]). Under Sysbox container root still writes bind mounts as the host's root
([S5]); `nosuid` covers the clones directory, not the sandbox directory's mounts.

**Assumptions.** A15 to A18, A20, A21. If neither engine passes X4, the phase shrinks
as A16 says and the question of the wall returns to the user as a spec change.

## Phase 9: knowledge sync, remaining findings

**Establishes.** I2 and I3c in full for the knowledge path. Findings H2, the rest of
H4, M6.

**Goal.** The integrator's `main` reaches the remote and the render only after the
host showed the user what would be pushed and the user confirmed (U12). The
confirmation is typed on the host, so an integration made while the user is away
waits for the next sync there; that is periodic work, as today (I8). The render accepts
only regular files and only role names from a fixed alphabet. No remaining host
write into a directory a sandbox can write follows a link. A closed report stays
reachable after it is closed.

**Contract needed.** C-KNOW and C-STATUS from phase 1.

**Closing check.** Tests for each of the four properties on the stubbed remote; the
existing invariant "main changes only with the user's approval" now has a host-side
test.

**Assumptions.** None beyond phase 1's.

## Phase 10: remaining Medium and Low findings, and the independent review

**Goal.** M2 (clipboard and window marking in the forwarded-display modes), the rest
of M3, M4 (pinning and verification of what the image and the start download), M5 (the
headless agent's command grants, with the two cases of `test-delegate.sh` that fail
today, D15), L1 to L5, a playback-only audio path for sandboxes opted into audio, and
the findings of the user's independent review that fall inside
G1 to G3.

**Establishes.** What is left of G1 and G3 outside the paths the earlier phases
closed; no new invariant.

**Contract needed.** The modules of phase 3.

**Closing check.** One test, or one host check where no stub can show it, per
finding, named in the plan; a finding the phase leaves open is reported to the user
with its reason, not dropped.

**Sizing.** Planned against the tree when phase 9 closes.

**Assumptions.** None of its own; each finding is re-verified against the tree at
planning, since phases 1 to 9 move the code the review cites.

## Decisions for the user

No open entry. The decisions of revision 2, and U17 of revision 3, are answered and
recorded under "The user's decisions".

Settled from the files and recorded instead of asked (the keys U3, U7, U10 and U13
are not reused): the place of the installed revision (D3), the Bitbucket rule check
(D9), kept inner images and the two failing cases of the base (D15).

Settled by the author, each open to the user's veto: the branch prefix's default,
the single ruleset for U4 and U6 and what may sit on its bypass list (D16);
environments by name pattern (D17); one engine per host (D18); that C-PIPE's
conditions stay a confirmation and the host reads no environment (C-PIPE, last
paragraph); what X4 may adapt and which of its outcomes return to the user; an
existing sandbox counted as `--host-logins` (phase 7); what U5 and U16 leave to the
user's settings when taken together, a tag an agent creates against an environment
that admits tags (C-PIPE, condition 2).

Questions of the reports that the chosen direction or the user's facts made moot
are not asked: Q1 to Q3, Q8, Q9 and the addendum's Q-A, Q-B and Q-E.

## Deferred list

Two open entries. Cap: ten open entries; an entry needs a failure a user or an
operator can reach, or a broken invariant.

- **E1 Egress is unchecked** (U8, 2026-11-11). Failure: whatever a sandbox holds can
  be sent to any destination. The user's idea is a reputation check of each
  destination; the earlier candidate was an allow-list proxy. Kept for the planning
  of phase 10, where the user decides whether it becomes a phase of its own, which
  is a spec change.
- **E2 `bin/ai/MANIFEST` would be ignored by git** (noticed while planning phase 1,
  2026-11-11). Failure: `.gitignore` ignores every path named `MANIFEST` (its Python
  packaging section), so C-INSTALL's manifest is skipped by `git add` of its directory
  and missing from a revision exported from a commit. Kept for phase 4: its plan
  adds `!bin/ai/MANIFEST` to `.gitignore`, a one-line change outside the scope line at
  the top of the spec, needed by the contract's fixed name.

## Residual risk the user accepts with this spec

- Whatever a sandbox holds can be sent out while egress is open (U8, E1): the AI
  account login made inside it and its git tokens. I1 limits what that is worth; it
  does not prevent the sending.
- A fast-forward push can publish what should stay private, and a pipeline runs on
  it. What a run on an agent's ref can read is the agent's: every repository-level
  secret, and every secret for which a condition of C-PIPE does not hold although
  the user confirmed it. The host reads none of those settings, and the dated
  confirmation is not asked again when the user later changes an environment, a
  secret, a bypass list or a workflow. A run an agent defines can also publish
  packages, report checks as passed and start the default branch's hand-started
  workflows ([G19]); a green check on a pull request that changes a workflow proves
  nothing.
- What the user merges runs on the default branch with the environments' secrets.
  C-PIPE covers unmerged content only; the user's review of the pull request, on
  the phone, is the only gate.
- An agent reads the checks, logs and downloadable artifacts of every run in the
  repository, those on the default branch that held environment secrets included
  (U17, [G2]). Redaction is documented for logs only, "is not guaranteed" there and
  misses derived values ([G15]); the user's confirmation of C-PIPE's condition 7 is
  the only gate.
- A tag an agent creates starts whatever the repository starts on a tag: a release
  pipeline publishes, and nothing undoes a publication.
- A credential that may bypass the rules and that a pipeline run can read or act as
  (a personal token, a deploy key or an app's key stored as a secret; an actor on a
  bypass list) moves the default branch, and what C-PIPE protects goes with it. The
  host reads neither bypass lists nor secrets: the user's confirmation of
  condition 6 is the only gate.
- A repository switched to `default=ff`: its default branch, and what runs there,
  are within an agent's reach.
- Tags and every branch but the default one on Bitbucket; releases and comments on
  GitHub, which rulesets do not cover: the permission that edits a release's notes
  also deletes the release and, without immutable releases, changes its assets;
  with them, a release an agent publishes takes its tag name for good ([G2],
  [G12]). Not checked: whether a sandbox's token writes a repository's wiki, whose
  history no ruleset names (X2 records it).
- A sandbox the user opted into host audio (phase 2) or into copied host logins
  (phase 7), and a project kept on the shared tree (D8).
- The display server a sandbox talks to by default: until phase 10 what M2 names,
  and after it whatever that server does on a client's request, which is the
  server's own code and not this toolchain's.
- A network service the host offers on the address by which every sandbox reaches
  the host (`host.docker.internal`, given on purpose so that a sandbox can use the
  host's services): no phase takes that address away, and what such a service does
  on a client's request is its own code and not this toolchain's.
- A host AI session opened in a sandboxed project loads what the sandbox wrote into
  the project's Claude state (U9).
- A shared kernel. Under rootless Docker a break-out ends as the user, whose files
  and keyring are then the stake; under Sysbox there are its two root daemons, and
  root-owned files on the bind mounts outside the clones directory (U11).
- The user's reading of a revision before installing it (phase 4), and until phase 6
  whatever the user runs on the host by path from a checkout its sandbox can write.
- Trees that sandboxes removed before phase 6 had mounted: no record names them; the
  user declares them or they are copied as clean.
- The accepted order: H3 stays open until phase 4 and H2 until phase 9, where an
  unreviewed `main` of the knowledge repository still reaches the host's render.
- A bypass the user keeps for their own role is safe only while no token of the user
  is inside a sandbox; the start reports the stores it knows, not every place a token
  can be put. The Bitbucket rules are confirmed by the user, not read by the host.
- If the keyring cannot be read later in a session (A13's fallback), the app's
  private key stays in the memory of a host process for as long as an entry is
  open, instead of being read for each refresh.
- Phone work stands on an open `ai-sandbox` entry: when the last one ends while
  agent sessions go on, pushes and `gh` stop within the hour and nothing on the
  phone repairs it (U15). Set-up steps wait for the user's return (I8, the table of
  host commands).

## Sources fetched for this spec (2026-11-11)

- [G1] GitHub REST API description, version 1.1.4.
  https://raw.githubusercontent.com/github/rest-api-description/main/descriptions/api.github.com/api.github.com.json
  "Create an installation access token for an app": "Installation tokens expire one
  hour from the time you create them."; "you can use the `repositories` or
  `repository_ids` body parameters to specify individual repositories that the
  installation access token can access"; "The installation access token cannot be
  granted permissions that the app was not granted."; "a stateless format
  (`ghs_APPID_JWT`) [...] If your application expects or relies on installation
  tokens being exactly 40 characters long, it may not handle this new token format
  correctly." "Get a repository installation for the authenticated app": "Enables an
  authenticated GitHub App to find the repository's installation information."
  Schema `repository-ruleset`,
  `current_user_can_bypass`: "The bypass type of the user making the API request for
  this ruleset. This field is only returned when querying the repository-level
  endpoint.", values `always`, `pull_requests_only`, `never`, `exempt`. "Get a
  repository ruleset": "the `bypass_actors` property is only returned if the user
  making the API request has write access to the ruleset." Ref-name condition:
  "Also accepts `~DEFAULT_BRANCH` to include the default branch or `~ALL` to include
  all branches." Rule `deletion`: "Only allow users with bypass permissions to delete
  matching refs."; `non_fast_forward`: "Prevent users with push access from force
  pushing to refs."; `update`: "Only allow users with bypass permission to update
  matching refs."; `creation`: "Only allow users with bypass permission to create
  matching refs." "Update a release", `target_commitish`: "Specifies the commitish
  value that determines where the Git tag is created from. [...] Unused if the Git
  tag already exists." Rule `pull_request`, `require_last_push_approval`: "Whether
  the most recent reviewable push must be approved by someone other than the person
  who pushed it." Schema `deployment-branch-policy-settings`, `protected_branches`:
  "Whether only branches with branch protection rules can deploy to this
  environment." Schema `repository-ruleset-bypass-actor`, `actor_type`: `Integration`,
  `OrganizationAdmin`, `RepositoryRole`, `Team`, `DeployKey`, `User`. "Download
  workflow run logs": "Anyone with read access to the repository can use this
  endpoint." Schema `check-run`: `name`, `conclusion`, and `output` with `title`,
  `summary`, `text` and `annotations_url`.
- [G2] GitHub documentation data, permissions of app installation tokens per endpoint.
  https://raw.githubusercontent.com/github/docs/main/src/github-apps/data/fpt-2022-11-28/server-to-server-permissions.json
  `GET /repos/{owner}/{repo}/rulesets`, `GET .../rulesets/{ruleset_id}` and
  `GET .../rules/branches/{branch}` are listed under "Metadata", access `read`;
  `DELETE .../releases/{release_id}` and `PUT .../pulls/{pull_number}/merge` under
  "Contents", `write`;
  `DELETE .../issues/comments/{comment_id}` under "Issues", `write`.
  `POST .../releases` and `PATCH .../releases/{release_id}` under "Contents",
  `write` (and under "Workflows"); the data has no permission named for releases.
  `PUT .../environments/{environment_name}` and `POST
  .../environments/{environment_name}/deployment-branch-policies` under
  "Administration", `write`; `GET .../environments` and `GET .../actions/runs`,
  `GET .../actions/jobs/{job_id}/logs` under "Actions", `read`; `POST
  .../actions/workflows/{workflow_id}/dispatches` under "Actions", `write`;
  `GET .../actions/secrets` under "Secrets", `read`; `GET
  .../environments/{environment_name}/secrets` under "Environments", `read`;
  `GET .../commits/{ref}/check-runs` and `GET
  .../check-runs/{check_run_id}/annotations` under "Checks" and `GET
  .../commits/{ref}/status` under "Commit statuses", `read`.
  `GET .../actions/runs/{run_id}/logs`, `GET
  .../actions/artifacts/{artifact_id}/{archive_format}` and `GET
  .../environments/{environment_name}/deployment-branch-policies` under "Actions",
  `read`; `POST /repos/{owner}/{repo}/dispatches` under "Contents", `write`;
  `PUT .../rulesets/{ruleset_id}` under "Administration", `write`.
- [G3] GitHub documentation, bypass list of a ruleset.
  https://github.com/github/docs/blob/main/data/reusables/repositories/rulesets-bypass-step.md
  "The following are eligible for bypass access: Repository admins, organization
  owners, and enterprise owners", and as a separate entry the GitHub Apps.
- [G4] GitHub documentation, Choosing permissions for a GitHub App.
  https://github.com/github/docs/blob/main/content/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app.md
  "The success of an API request with an installation access token only depends on
  the app's permissions."; "If your app specifically needs to access or edit Actions
  files in the `.github/workflows` directory, request the "Workflows" repository
  permission."
- [G5] GitHub documentation, Authenticating as a GitHub App installation.
  https://github.com/github/docs/blob/main/content/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation.md
  "You can then use the installation access token as the HTTP password."; "API
  requests made by an app installation are attributed to the app."
- [G6] GitHub documentation, Generating a JSON Web Token for a GitHub App.
  https://github.com/github/docs/blob/main/content/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app.md
  "Your JWT must be signed using the `RS256` algorithm"; expiry "must be no more than
  10 minutes into the future."
- [G7] GitHub documentation, Managing private keys for GitHub Apps.
  https://github.com/github/docs/blob/main/content/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps.md
  "The private key is the single most valuable secret for a GitHub App."
- [G8] GitHub documentation, Installing your own GitHub App.
  https://github.com/github/docs/blob/main/content/apps/using-github-apps/installing-your-own-github-app.md
  "select **All repositories** or **Only select repositories**."
- [G9] GitHub CLI manual, `gh auth login`. https://cli.github.com/manual/gh_auth_login
  "use `--with-token` to pass in a personal access token (classic) on standard
  input"; "gh will use the authentication token found in environment variables. This
  method is most suitable for "headless" use of gh such as in automation."; "To use
  gh in GitHub Actions, add `GH_TOKEN: ${{ github.token }}` to `env`."; "login is
  for a single account on a host".
- [G10] GitHub documentation, availability of rulesets.
  https://github.com/github/docs/blob/main/data/reusables/gated-features/repo-rules.md
  "Rulesets are available in public repositories with" the free plans, "and in
  public and private repositories with" Pro, Team and Enterprise Cloud (the plan
  names are template variables in the source).
- [G11] GitHub documentation, Deployments and environments.
  https://github.com/github/docs/blob/main/content/actions/reference/workflows-and-actions/deployments-and-environments.md
  "**Protected branches only:** Only branches with branch protection rules enabled
  can deploy to the environment. If no branch protection rules are defined for any
  branch in the repository, then all branches can deploy."; "**Selected branches and
  tags:** Only branches and tags that match your specified name patterns can deploy
  to the environment."; "The deployment branch or tag rule is matched against the
  `GITHUB_REF` of the workflow run."; "Wildcard characters will not match `/`";
  "Secrets stored in an environment are only available to workflow jobs that
  reference the environment."; "For access to environment secrets in private or
  internal repositories, you must use" Pro, Team or Enterprise; deployment branches
  and tags "are also available for private repositories" on the Pro and Team plans,
  while on those plans "required reviewers are only available for public
  repositories" (plan names are template variables in the source).
- [G12] GitHub documentation, Immutable releases.
  https://github.com/github/docs/blob/main/content/code-security/concepts/supply-chain-security/immutable-releases.md
  "Only the assets and tag are locked. You can still edit the title and release notes
  of a published immutable release"; "If you delete the immutable release, you can
  delete the tag, but you cannot reuse the same tag name."
- [G13] GitHub documentation, Secrets reference, and its note on forks.
  https://github.com/github/docs/blob/main/content/actions/reference/security/secrets.md
  "Organization and repository secrets are read when a workflow run is queued, and
  environment secrets are read when a job referencing the environment starts."
  https://github.com/github/docs/blob/main/data/reusables/actions/forked-secrets.md
  "With the exception of `GITHUB_TOKEN`, secrets are not passed to the runner when a
  workflow is triggered from a forked repository."
- [G14] GitHub documentation, Events that trigger workflows.
  https://github.com/github/docs/blob/main/content/actions/reference/workflows-and-actions/events-that-trigger-workflows.md
  `pull_request`, `GITHUB_REF`: "PR merge branch `refs/pull/PULL_REQUEST_NUMBER/merge`";
  `release`: "Tag ref of release `refs/tags/<tag_name>`"; `workflow_dispatch`: "Branch
  or tag that received dispatch"; `pull_request_target`: "Avoid using this event if
  you need to build or run code from the pull request." Its warning,
  https://github.com/github/docs/blob/main/data/reusables/actions/pull-request-target-permissions-warning.md
  "Running untrusted code on the `pull_request_target` trigger may lead to security
  vulnerabilities. These vulnerabilities include cache poisoning and granting
  unintended access to write privileges or secrets." `issue_comment`, `label` and
  `workflow_run`, `GITHUB_REF`: "Default branch"; `workflow_run`: "The workflow
  started by the `workflow_run` event is able to access secrets and write tokens,
  even if the previous workflow was not."
- [G15] GitHub documentation, Secure use reference, self-hosted runners.
  https://github.com/github/docs/blob/main/content/actions/reference/security/secure-use.md
  Self-hosted runners "do not have guarantees around running in ephemeral clean
  virtual machines, and can be persistently compromised by untrusted code in a
  workflow." "Because there are multiple ways a secret value can be transformed,
  automatic redaction is not guaranteed."; a value generated from a secret "should
  be formally" registered as a secret, "so that it will be redacted if it ever
  appears in the logs." The page describes redaction for logs and for nothing else. "Workflows triggered on `workflow_run` should treat artifacts uploaded from
  other workflows with caution."
- [G16] GitHub documentation, OpenID Connect reference.
  https://github.com/github/docs/blob/main/content/actions/reference/security/oidc.md
  "The subject claim includes the environment name when the job references an
  environment."; "The subject claim includes the branch name of the workflow, but
  only if the job doesn't reference an environment, and if the workflow is not
  triggered by a pull request event."
- [G17] GitHub documentation, Available rules for rulesets.
  https://github.com/github/docs/blob/main/content/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets.md
  Restrict creations: "only users with bypass permissions can create branches or
  tags whose name matches the pattern you specify."; restrict updates: "only users
  with bypass permissions can push to branches or tags whose name matches the pattern
  you specify."
- [G18] GitHub documentation, Managing GitHub Actions settings for a repository.
  https://github.com/github/docs/blob/main/content/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository.md
  "By default, when you create a new repository in your personal account, workflows
  are not allowed to create or approve pull requests."
- [G19] GitHub documentation, the token of a workflow run.
  https://github.com/github/docs/blob/main/data/reusables/actions/jobs/section-assigning-permissions-to-jobs.md
  "You can use `permissions` to modify the default permissions granted to the
  `GITHUB_TOKEN`, adding or removing access as required".
  https://github.com/github/docs/blob/main/data/reusables/actions/github-token-scope-descriptions.md
  "`packages: write` permits an action to upload and publish packages on GitHub
  Packages."
  https://github.com/github/docs/blob/main/data/reusables/actions/actions-do-not-trigger-workflows.md
  "`workflow_dispatch` and `repository_dispatch` events always create workflow runs."
- [G20] GitHub documentation, Managing environments for deployment.
  https://github.com/github/docs/blob/main/content/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments.md
  "Running a workflow that references an environment that does not exist will create
  an environment with the referenced name."; "the newly created environment will not
  have any protection rules or secrets configured. Anyone that can edit workflows in
  the repository can create environments via a workflow file, but only repository
  admins can configure the environment."
- [B1] Bitbucket Cloud REST API description. https://api.bitbucket.org/swagger.json
  `GET /repositories/{workspace}/{repo_slug}/branch-restrictions`: security
  `repository:admin`. `POST` on the same path: "`kind` describes what will be
  restricted. Allowed values include: `push`, `force`, `delete`"; "The restriction
  applies to all branches that match."; "`'*'` will match all branches."; "`users`
  and `groups` are lists of users and groups that are except from the restriction.
  They can only be configured in `push` and `restrict_merges` restrictions."
- [B2] Atlassian, Repository-level access token permissions.
  https://support.atlassian.com/bitbucket-cloud/docs/repository-access-token-permissions/
  Write: "Provides access to modify repositories, including the source code. This
  does not include pull requests." Admin: "View and edit branch permissions.";
  "Ability to delete the repositories."
- [B3] Atlassian, Using access tokens.
  https://support.atlassian.com/bitbucket-cloud/docs/using-access-tokens/
  "git clone https://x-token-auth@bitbucket.org/{workspace}/{repository}.git";
  "git clone https://x-token-auth:{repository_access_token}@bitbucket.org/{workspace}/{repository}.git"
- [B4] Atlassian, Use branch permissions.
  https://support.atlassian.com/bitbucket-cloud/docs/use-branch-permissions/
  "Branch permissions help enforce specific workflows and prevent errors like a new
  workspace member deleting the main branch."; "Merge checks are a Premium feature
  for Bitbucket Cloud." No sentence there ties `force` or `delete` restrictions to a
  plan.
- [L1] libsecret, `secret-tool` manual source.
  https://gitlab.gnome.org/GNOME/libsecret/-/raw/main/docs/man/secret-tool.xml
  "A password to store can also be piped in via stdin. The password will be the
  contents of stdin until EOF."; "If necessary an item will be unlocked."
- [L2] git, configuration of remotes, v2.52.0.
  https://github.com/git/git/blob/v2.52.0/Documentation/config/remote.adoc
  `remote.<name>.uploadpack`: "The default program to execute on the remote side when
  fetching."
- [L3] git(1), SECURITY, v2.52.0.
  https://github.com/git/git/blob/v2.52.0/Documentation/git.adoc
  "it is generally safe to clone remote repositories with untrusted content"; "it is
  not safe to run Git commands in a `.git` directory (or the working tree that
  surrounds it) when that `.git` directory itself comes from an untrusted source."
- [L4] git-upload-pack(1), SECURITY, v2.52.0.
  https://github.com/git/git/blob/v2.52.0/Documentation/git-upload-pack.adoc
  "`upload-pack` tries to avoid any dangerous configuration options or hooks from the
  repository it's serving, making it safe to clone an untrusted directory and run
  commands on the resulting clone."
- [L5] gitcredentials(7), v2.52.0.
  https://github.com/git/git/blob/v2.52.0/Documentation/gitcredentials.adoc
  `useHttpPath`: "By default, Git does not consider the "path" component of an http
  URL to be worth matching via external helpers. This means that a credential stored
  for `https://example.com/foo.git` will also be used for
  `https://example.com/bar.git`. If you do want to distinguish these cases, set this
  option to `true`."
- [L6] git-bundle(1), v2.52.0.
  https://github.com/git/git/blob/v2.52.0/Documentation/git-bundle.adoc
  "Bundles are used for the "offline" transfer of Git objects without an active
  "server" sitting on the other side of the network connection."
- [L7] mount(8), util-linux. https://man7.org/linux/man-pages/man8/mount.8.html
  `nosuid`: "Do not honor set-user-ID and set-group-ID bits or file capabilities when
  executing programs from this filesystem."
- [R1] Docker documentation, Rootless mode, and its UID/GID mapping.
  https://github.com/docker/docs/blob/main/content/manuals/engine/security/rootless/_index.md
  "Rootless mode executes the Docker daemon and containers inside a user namespace."
  https://github.com/docker/docs/blob/main/content/manuals/engine/security/rootless/uid-gid-mapping.md
  "In rootless mode, container UID `0` is mapped to the host UID of the user running
  rootless Docker (the result of `id -u`)"; "files owned by your host user appear as
  owned by `root` inside the container."
- [R2] Docker documentation, Rootless mode, troubleshooting: known limitations.
  https://github.com/docker/docs/blob/main/content/manuals/engine/security/rootless/troubleshoot.md
  "Only the following storage drivers are supported:", with the entries "`overlay2`
  (only if running with kernel 5.11 or later)", `fuse-overlayfs`, `btrfs` and `vfs`;
  "cgroup is supported only when running with cgroup v2 and systemd."; "Following
  features are not supported:", with the entries "AppArmor", "Checkpoint", "Overlay
  network" and "Exposing SCTP ports"; "`IPAddress` shown in
  `docker inspect` is namespaced inside RootlessKit's network namespace. This means
  the IP address is not reachable from the host without `nsenter`-ing into the
  network namespace."; "To expose privileged TCP/UDP ports (< 1024), see" the tips;
  "Capabilities added with `--cap-add` apply only to resources governed by the
  container's user namespace."; "Ubuntu 24.04 and later enables restricted
  unprivileged user namespaces by default".
- [R3] Docker documentation, Rootless mode, tips.
  https://github.com/docker/docs/blob/main/content/manuals/engine/security/rootless/tips.md
  "To run Rootless Docker inside "rootful" Docker, use the
  `docker:<version>-dind-rootless` image"; "`--privileged` is required for disabling
  seccomp, AppArmor, and mount masks."; "typically, only `memory` and `pids`
  controllers are delegated to non-root users by default."; "When these conditions
  are not satisfied, rootless mode ignores the cgroup-related `docker run` flags.";
  "To launch the daemon on system startup, enable the systemd service and lingering".
  None of the pages under [R1] to [R3] describes a Docker daemon nested inside a container of a
  rootless daemon.
- [S1] Sysbox user guide, Docker-in-Docker.
  https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md
  "A given host directory mounted into a system container's `/var/lib/docker` must
  only be mounted on a single system container at any given time."
- [S2] Sysbox, distribution compatibility.
  https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md
  Rows "Noble Numbat (24.04)", minimum kernel "6.8+", and "Ubuntu Jammy (22.04)",
  minimum kernel "5.15+"; package install supported for both.
- [S3] Sysbox user guide, installation.
  https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md
  "Installing shiftfs on hosts with Linux kernel >= 6.3+ is not necessary, as the
  Linux kernel's ID-mapped mounts feature replaces it."
- [S4] Sysbox user guide, security.
  https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md
  "If the container manager (e.g., Docker) instructs Sysbox to apply an AppArmor
  profile on a container, Sysbox currently ignores this."
- [S5] Sysbox user guide, storage.
  https://github.com/nestybox/sysbox/blob/master/docs/user-guide/storage.md
  "when the container's root user writes to these mounted files or directories, it
  will do so as if it were the root user on the host."
