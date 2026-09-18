# Shared knowledge v2, phase 1: prerequisite check and disposable migration

Spec: `docs/superpowers/specs/2026-09-18-shared-knowledge-v2-design.md`, phase 1.
Spec change: none. Unverified assumptions: none (see the end).
Invariants: the spec's "Invariants" section; this phase adds the start-path rule
"checks prerequisites and stops; never repairs".

Tests run with `bash tests/ai-sandbox/test-knowledge.sh` unless a task says
otherwise; the full suite, `bash tests/ai-sandbox/run-tests.sh`, runs once at the
end. Every existing behaviour without `~/.ai-sandbox/knowledge/config` is unchanged.

## Contracts

Managed `.env` keys, written by `create-ai-sandbox.sh` beside `SANDBOX_WITH_DOCKER`:

```
SANDBOX_KNOWLEDGE=0|1          1 when the compose file carries the knowledge mounts
SANDBOX_PROJECT_DIR=<abs path> the project the sandbox was created for
```

Library functions in `bin/ai/ai-sandbox-lib.sh`:

```
ai_sandbox_list                      # "<sandbox dir>\t<project dir>" per *-agent dir with a
                                     # docker-compose.yml; project dir empty when unstamped
ai_sandbox_knowledge_stamp <sbdir>   # prints 0, 1 or nothing (unstamped)
ai_sandbox_knowledge_state <sbdir>   # prints current | stale | unstamped, comparing the
                                     # stamp with ai_knowledge_configured
ai_sandbox_require_current <sbdir>   # returns 1 and prints the migration command unless current
```

Container environment: `SANDBOX_KNOWLEDGE` is passed like `SANDBOX_WITH_DOCKER`; unset
inside a container means the compose file predates this phase.

## Tasks

### Task 1: commit the approved spec

Goal: the spec and this plan are in history before code changes.
Files: the two documents. Command: `git add docs/superpowers && git commit`
(`docs(ai-knowledge): spec revision 2 and phase 1 plan`).
Acceptance: `git status` clean, commit present.

### Task 2: stamps and state in the library

Goal: the four functions above exist and classify a sandbox from its `.env`.
Files: `bin/ai/ai-sandbox-lib.sh`, near `ai_sandbox_dir_for`; tests appended to
`tests/ai-sandbox/test-knowledge.sh` in a new section that fabricates three sandbox
directories under the fake root with `SANDBOX_KNOWLEDGE=1`, `=0` and no key, plus a
directory without `docker-compose.yml` that must not be listed.
Behaviour: `ai_sandbox_require_current` prints one message naming
`bin/ai/ai-sandbox-migrate-knowledge` and the sandbox, then returns 1.
Acceptance: the section's assertions pass; `test-identity.sh` still passes.

### Task 3: create writes the stamps and exports the flag

Goal: every run of `create-ai-sandbox.sh` records both keys and passes
`SANDBOX_KNOWLEDGE` into the container.
Files: `create-ai-sandbox.sh`, the managed-keys map in the `.env` writer and the
`COMPOSE_ENV` block. `KNOWLEDGE` is already decided before the `.env` is written.
Tests: in `test-knowledge.sh` after the existing create case, assert the `.env`
holds `SANDBOX_KNOWLEDGE=1` and `SANDBOX_PROJECT_DIR=<proj>` and the compose file
holds the environment line; in `test-options.sh`, a create without knowledge
config yields `SANDBOX_KNOWLEDGE=0`. Command: both files.
Acceptance: assertions pass; the compose still contains every mount the existing
create case checks.

### Task 4: start scripts hard-stop on a stale sandbox

Goal: `ai-sandbox` and `ai-sandbox-restart` refuse before any compose or sync call
when the sandbox is not current.
Files: `bin/ai/ai-sandbox` after `ai_sandbox_require_ctx` and before
`--print-context` handling is unaffected; `bin/ai/ai-sandbox-restart` before
`ai_sandbox_check_capacity`, so a refused restart leaves the container running.
Tests: new section in `test-knowledge.sh` running both scripts against a fabricated
stale sandbox with the stub docker and `DOCKER_STUB_LOG`: exit status 1, the log
holds no `compose` line, stderr names the migration script; against a current one
`ai-sandbox --print-context` still succeeds.
Acceptance: assertions pass; `test-capacity.sh` and `test-shared.sh` unchanged.

### Task 5: `ai-knowledge status` lists every sandbox

Goal: `status` with no argument prints one row per `ai_sandbox_list` entry: sandbox
name, project (or `unknown`), state, last sync line or `never`; `status <dir>`
keeps today's output. The header lines (remote, integrator, main, render) stay.
Files: `bin/ai/ai-knowledge`, `cmd_status`.
Tests: `test-knowledge.sh`, with the fabricated sandboxes from task 2: rows contain
`current`, `stale`, `unstamped`; the unstamped row shows `unknown`.
Acceptance: assertions pass; the existing `status` assertions, if any, pass.

### Task 6: doctor distinguishes not configured from not migrated

Goal: inside a container the knowledge line reads the sync status when
`SANDBOX_KNOWLEDGE=1`, says the host is not configured when it is `0`, and says the
sandbox predates the knowledge mounts, naming the migration script, when unset.
Files: `create-ai-sandbox.sh`, the `status "knowledge"` line in the `sandbox-doctor`
heredoc.
Tests: `test-knowledge.sh` asserts the generated `image/build/sandbox-doctor`
contains `SANDBOX_KNOWLEDGE` and the migration script name.
Acceptance: assertion passes; the existing doctor assertion passes.

### Task 7: the disposable migration script

Goal: `bin/ai/ai-sandbox-migrate-knowledge`, executable, not in `ai_sandbox_helpers`,
run from the checkout. It prints the state table, then for each `stale` or
`unstamped` sandbox recovers the project path from the stamp or, failing that, from
the compose line that mounts a path onto itself, refuses the whole run naming any
sandbox whose project directory is missing, otherwise stops the container with the
sandbox's compose file, re-runs `create-ai-sandbox.sh <project>` forwarding its own
extra arguments (for `--display=none`, `--no-start` in tests), and ends with a
summary of migrated and untouched sandboxes. Nothing to migrate exits 0 with one
line. Design work: the compose-path recovery is the implementer's choice.
Files: the new script; a note in `create-ai-sandbox.sh` usage under the host
commands is not added, since the script is temporary.
Tests: new section in `test-knowledge.sh`: a fabricated unstamped sandbox whose
compose mounts `$proj` onto itself becomes current after the script runs with
`--display=none --no-start`; the stub log shows `compose ... down` before the
create; a sandbox pointing at a deleted directory makes the script exit 1 and
migrate nothing; a run with everything current exits 0.
Acceptance: assertions pass.

### Task 8: documentation

Goal: `docs/shared-knowledge.md` deployment step 4 describes the stamp, the hard
stop and the migration script, and says the script is deleted once every sandbox
is current; the sync section says a sandbox start syncs its own clone; the
`status` row in the commands table mentions the all-sandboxes listing.
`PROJECT_MAP.md` gains one sentence for the migration script and notes it is
temporary. Files: those two.
Acceptance: `grep -n migrate-knowledge docs/shared-knowledge.md PROJECT_MAP.md`
finds both.

### Task 9: full suite and commits

Goal: `bash tests/ai-sandbox/run-tests.sh` and `bash tests/ai-sync/test-sync.sh`
pass with output at hand. Commits, Conventional Commits, one per task 2 to 8 or per
coherent pair, ending with the Co-Authored-By line.
Acceptance: `ALL SUITES PASSED` printed; `git log` shows the commits.

## Assumptions checked against the tree

- The stub docker exits 0 for every `compose` invocation and logs arguments to
  `DOCKER_STUB_LOG` (verified in `tests/ai-sandbox/stub/docker`).
- The managed `.env` block is rewritten on every create and `KNOWLEDGE` is decided
  earlier in the script (verified).
- `SANDBOX_WITH_DOCKER` already reaches the container through `COMPOSE_ENV`
  (verified), so a second key follows the same path.
- The compose file mounts the project at its own path (verified), which is what the
  unstamped-recovery in task 7 reads.
- The generated doctor is readable at `image/build/sandbox-doctor` after a
  `--no-start` create (verified in `test-resources.sh`).
- Whether `compose up -d` recreates a container whose mounts changed is not relied
  upon: task 7 runs `compose down` first.

## Deferred list

Empty.
