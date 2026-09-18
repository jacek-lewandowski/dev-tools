# Shared knowledge v2, phase 2: `sync --all`, parallelism, ssh-agent

Spec: `docs/superpowers/specs/2026-09-18-shared-knowledge-v2-design.md`, phase 2.
Spec change: none. Unverified assumptions: two inferred ones, listed at the end;
neither decides feasibility and the code degrades safely where they fail.
Reviewed once (plan review of 2026-09-18); its blocking findings are folded in.
Invariants: the spec's "Invariants"; this phase relies on "the render is rebuilt by
at most one process at a time" and "an agent ai-knowledge started is killed by its
exit trap; one it did not start is never killed".

Tests: `bash tests/ai-sandbox/test-knowledge.sh` unless stated; full suites at the
end. Phase 1's stamps are in place: `ai_sandbox_list` yields the project of every
stamped sandbox.

## Contracts

```
ai-knowledge sync                 main + render only (unchanged)
ai-knowledge sync PROJECT_DIR     as today: main, render, that clone, render again if main moved
ai-knowledge sync --all           main, render, every stamped sandbox's clone in parallel
                                  (AI_KNOWLEDGE_JOBS, default 4), then fetch main once more
                                  and render if it advanced; one summary table at the end
ensure_ssh_access REMOTE_URL      probes once, handles the agent as below, re-probes once
                                  after a successful ssh-add; the caller ignores its return
                                  and today's git_net path runs either way; non-ssh URLs
                                  return at once
```

Summary table row: `<sandbox name>  <state>  <.sync-status line or "never">`, one per
`ai_sandbox_list` entry. An `unstamped` sandbox is not synced and its row says so; a
child that exits non-zero (project directory gone, unexpected error) gets the row
`missing project` or `error` and the run continues. Each child's output is
captured in `<sandbox dir>/.sync-output`, never inside the clone, and printed as a
block under its name before the table, in list order, never interleaved.

Agent handling, in order, when a probe against an ssh remote fails with a
public-key refusal:

1. `SSH_AUTH_SOCK` set and the agent answers: `ssh-add -t 3600` on the keys
   `ssh -G <host>` names that exist (bare `ssh-add -t 3600` when none), then say the
   key was added to the user's agent for one hour.
2. No agent and a terminal on stdin: start `ssh-agent`, remember its pid, `ssh-add`
   as above, say the agent lives only for this run; the exit trap kills it.
3. No agent and no terminal: today's offline path, unchanged.

A probe that fails for another reason (timeout, unknown host, no network) takes the
offline path without touching any agent, and so does a second refusal after a
successful `ssh-add` (the key is not authorised; no passphrase is involved). The
"started by this process" fact is a non-exported shell variable set only inside
`ensure_ssh_access`; the exit trap kills through `ssh-add`'s companion `ssh-agent -k`
only when that variable is set, so `_sync-clone` children, which inherit the
exported `SSH_AUTH_SOCK` and `SSH_AGENT_PID`, never kill the parent's agent.

## Tasks

### Task 1: single-clone sync as a subprocess unit

Goal: `ai-knowledge _sync-clone PROJECT_DIR` (undocumented, used by `--all`) does
`prepare_targets`, `link_skills_into`, `sync_clone` and `print_hints` for one
sandbox and never renders; `cmd_sync` with a project keeps its behaviour by calling
the same code path plus the render steps. Design work: the implementer chooses
whether `sync_clone` is reused directly or wrapped.
Files: `bin/ai/ai-knowledge`.
Tests: existing single-project cases still pass; a new case calls `_sync-clone` on
the project sandbox and asserts `.sync-status` is `ok` and the captured output has
no `rendered` line (the line `cmd_render` logs; mtimes prove nothing under rsync
`-a` or the suite's stub rsync). `_sync-clone` takes the sandbox dir as a second
argument so phase 3 need not re-derive it.
Acceptance: assertions pass.

### Task 2: `sync --all`

Goal: the `--all` flow from the contract, run with `xargs -P` (newline-delimited
input, one argument per child, since paths may hold spaces) or background jobs,
implementer's choice; the job-wait or `xargs` exit status is captured and never
fatal. Blocks printed in order, then the table. Sandboxes listed with an empty
project are reported as `unstamped` and skipped without a child. The second
`sync_main` runs once after every child finished and only if the first fetch
succeeded (offline, a second fetch would only add a timeout and a duplicate
hint); it renders only if `main`'s HEAD changed, compared before and after.
Files: `bin/ai/ai-knowledge`, `cmd_sync`, usage header.
Tests: with the project sandbox, the integrator sandbox and a third project's
sandbox all on the local bare remote: `sync --all` leaves three `ok` statuses, the
table has three rows, a fabricated unstamped sandbox shows `unstamped`, a stamped
sandbox whose project directory does not exist shows `missing project` while the
others still end `ok`, and, after the integrator committed on `main` inside its
clone, the render carries the new text after one `sync --all`. Count renders by
the `rendered` log lines in the captured output: one when main did not move, two
when it did.
Acceptance: assertions pass; `AI_KNOWLEDGE_JOBS=1` produces the same result.

### Task 3: `ensure_ssh_access`

Goal: the function from the contract, called once at the top of `cmd_init` and
`cmd_sync` after `load_config`, before any `git_net`, and therefore before the
parallel phase so children inherit the agent variables. The probe is
`git_net ls-remote -q REMOTE HEAD`; a public-key refusal is recognised by
`Permission denied` or `publickey` in its output. Host and user come from the
URL (`git@host:path` and `ssh://[user@]host[:port]/path`). Keys: `ssh -G
[user@]host` (with `-p port` when given) `identityfile` lines with `~` expanded,
filtered to existing files; none found means bare `ssh-add`; several keys may
prompt more than once. Every message goes to stderr, prefixed like `warn`. The
EXIT trap that kills a started agent runs on success, `die` and unexpected errors
alike, and only in the process that started it (see the contract).
Files: `bin/ai/ai-knowledge`.
Tests: stubs `ssh`, `ssh-agent`, `ssh-add` in `tests/ai-sandbox/stub/`. The stub
`ssh` serves as `GIT_SSH_COMMAND` for an `ssh://stub/<bare path>` remote: it prints
`Permission denied (publickey).` and exits 255 unless a marker file says a key is
loaded, otherwise it runs the command git passed locally; `-G` prints an
`identityfile` line for a file the test creates. Stub `ssh-add` creates the marker
and records its arguments (`-t 3600` expected); stub `ssh-agent -s` prints the two
export lines and touches a running marker, `-k` removes it. Git invokes the stub as
`ssh -o BatchMode=yes stub "git-upload-pack '/path'"`, so it strips the option pair
and runs the last argument with `sh -c`. Cases: existing agent (`SSH_AUTH_SOCK` set
to a path the stub accepts) is used and not killed; no agent plus a terminal
(`script -qec ... /dev/null`) starts one, syncs `ok`, and the running marker is
gone afterwards, also when the run ends in `die`; a `sync --all` under the started
agent leaves the marker present until the parent exits (children do not kill);
no agent and no terminal ends `offline` with no agent started; a `file://` remote
never calls the stubs. Under `script` the output has CRLF endings: assert on
`.sync-status` and marker files, not on the pty output.
Acceptance: assertions pass; the existing offline cases still pass.

### Task 4: wording

Goal: every "next sandbox start" phrase in dev-tools that describes when a
proposal or a new `main` travels says "next sync: a sandbox start or
`ai-knowledge sync --all` on the host" and, where it describes rules taking
effect, adds "and a new agent session". Files: `bin/ai/ai-knowledge` (`cmd_init`
log line), `bin/ai/knowledge-seed/README.md`, `bin/ai/knowledge-seed/proposals/README.md`,
`bin/ai/knowledge-seed/skills/propose-rule/SKILL.md`,
`.agents/skills/knowledge-integrate/SKILL.md`, `docs/shared-knowledge.md`. The
copies of the seed files on the knowledge repository's `main` are updated in
phase 3 together with the skill rewrite.
Tests: `grep -rn "next sandbox start" bin/ai docs .agents` finds nothing;
`grep -c "ai-knowledge sync --all" docs/shared-knowledge.md` is at least 1.
Acceptance: both greps as stated.

### Task 5: documentation

Goal: `docs/shared-knowledge.md` gets a "Sync on demand" subsection under "How it
works" describing `sync --all`, the parallel shape, the single render, and the
agent handling with its three cases; the commands table gains the `--all` row;
"Known limits" notes that `ssh -G` key discovery falls back to a bare `ssh-add` and
that several configured keys may prompt more than once.
`PROJECT_MAP.md`'s `ai-knowledge` row mentions `sync --all` and the agent handling.
Acceptance: `grep -n -- '--all' docs/shared-knowledge.md PROJECT_MAP.md` finds both.

### Task 6: full suites and commits

Goal: `bash tests/ai-sandbox/run-tests.sh` and `bash tests/ai-sync/test-sync.sh`
with output at hand (test-tools case 20 is the known sandbox-only failure). One
Conventional Commit per task 1 to 5.

## Assumptions

- The stub docker is irrelevant here; the local bare remote and `file://` transport
  are already used by the suite (verified).
- `script` from util-linux is available for a pseudo-terminal in tests (verified:
  `/usr/bin/script`, 2.37.2). If the host lacks it the case is skipped, not failed.
- `ssh -G <host>` prints `identityfile` lines honouring `~/.ssh/config` (inferred
  from the OpenSSH manual; no ssh client in this sandbox). The code does not depend
  on it: with no usable line it runs bare `ssh-add`, which loads the default keys.
- `git ls-remote` against an ssh remote with a refused key prints `Permission
  denied (publickey)` on stderr and exits non-zero (inferred from OpenSSH/git
  behaviour; the stub reproduces it, and any other failure text takes the offline
  path, so a different message costs only the agent convenience).

## Deferred list

Empty.
