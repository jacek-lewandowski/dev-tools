# Shared knowledge v2, phase 4: init, owner path, naming

Spec: `docs/superpowers/specs/2026-09-18-shared-knowledge-v2-design.md`, phase 4.
Spec change: none. Unverified assumptions: none that decide feasibility (listed at
the end). Invariants: the spec's; the commits this phase makes on `main` from the
host (integrator record, nothing else) are built with the same plumbing as
`propose`, pushed fast-forward only, and never rewrite anything.

Tests: `bash tests/ai-sandbox/test-knowledge.sh`, `bash tests/ai-sync/test-sync.sh`;
full suites at the end. Phases 1 to 3 are in place: stamps, `sync --all`,
`propose`, per-proposal branches.

## Contracts

```
~/.ai-sandbox/bin/knowledge-seed/       the seed, installed by create-ai-sandbox.sh beside the
                                        helpers and refreshed by ai-sandbox-migrate; ai-knowledge
                                        looks there first, then at DEV_TOOLS_DIR (as today)
README.md on main                       carries one line "<!-- ai-knowledge integrator: <hostname>:<abs path> -->"
                                        written once by 'init --integrator'; a different value already
                                        present is a warning, never overwritten
ai-knowledge init <url> [--integrator DIR]
                                        on a host whose ~/.gemini/GEMINI.md is a regular file that
                                        differs from rules/global.md (sandbox block stripped): shows
                                        the unified diff and, with a terminal, asks whether to file it
                                        as a proposal (slug gemini-md-<hostname>, machine <hostname>,
                                        project_id host, body = the diff in a fenced block); the backup
                                        of the file is kept as today either way
ai-knowledge status                     header gains "clone (integrator): <path>" when INTEGRATOR is set
```

## Tasks

### Task 1: the seed travels with the helper

Goal: `create-ai-sandbox.sh` installs `knowledge-seed/` into
`$AI_SANDBOX_ROOT/bin/knowledge-seed` (mirror, deletions included) when it installs
the helpers; `ai-sandbox-migrate`'s helper refresh does the same from
`DEV_TOOLS_DIR`; `seed_dir` in `ai-knowledge` prefers `$HERE/knowledge-seed`, which
is that installed copy for the installed helper and the checkout for the checkout's
copy, and falls back to `DEV_TOOLS_DIR` as today. The doc's deployment step 1
becomes "install the helpers once", no longer tied to a project.
Files: `create-ai-sandbox.sh` (helper install), `ai-sandbox-migrate` (refresh),
`ai-knowledge` (`seed_dir`), `docs/shared-knowledge.md`.
Tests: after the existing create case, `$AI_SANDBOX_ROOT/bin/knowledge-seed/skills/propose-rule/SKILL.md`
exists; in `test-migrate.sh`, a modified installed seed file is restored by a
migrate run; an `init` of the installed helper against a second bare remote, with a
second `HOME`/`AI_SANDBOX_ROOT` that has no `config`, seeds the remote (the seed
came from beside the helper).
Acceptance: assertions pass.

### Task 2: init shows and offers to file GEMINI.md drift

Goal: in `wire_host`'s backup path, when the remote already had a `main` (not the
seeding case), `init` prints `diff -u <render/rules from main> <local GEMINI.md
without the sandbox block>`; with a terminal it asks `File this difference as a
proposal? [y/N]`, and on yes calls `cmd_propose` per the contract with `--push`,
reporting the branch; without a terminal it prints the diff and the command to
run later (`ai-knowledge propose <backup file> ...`). An identical file prints
nothing extra. The backup file is kept in every case.
Files: `ai-knowledge` (`wire_host`, `cmd_init`).
Tests: a second `HOME` with a differing `GEMINI.md`, `init` with `printf 'y\n' |`
against the first remote: a `proposal/*-gemini-md-*` branch exists on the remote
whose file holds a fenced diff and `machine:`; the same with `</dev/null` files
nothing and prints the `propose` command; an identical file prints no diff.
Acceptance: assertions pass.

### Task 3: the integrator is recorded in the repository

Goal: `init --integrator DIR` reads `README.md` from `origin/main`; if it carries
no integrator line, a plumbing commit on top of `origin/main` appends the line and
is pushed as `main` fast-forward, then the canonical checkout fast-forwards; if it
carries this host's line, nothing happens; if it carries another host's, `init`
warns that two integrators can make `main` diverge and leaves the record alone.
`init` without `--integrator` on a host whose README names another host says so in
one line. Design work: the helper that builds a one-file commit on `origin/main`
is shared with `cmd_propose` (extract, do not duplicate).
Files: `ai-knowledge`.
Tests: first `init --integrator` writes the line (visible in `git show origin/main:README.md`
of the canonical checkout); a second host's `init --integrator` warns and leaves
the line; a plain `init` on that host mentions the recorded integrator.
Acceptance: assertions pass.

### Task 4: status, docs, naming

Goal: `cmd_status` header prints `clone (integrator): <sandbox dir>/knowledge` when
`INTEGRATOR` is set. `docs/shared-knowledge.md`: deployment steps rewritten for
tasks 1 to 3 (install once, init, migrate, second computer), a short "Editing the
rules yourself" subsection (edit `main` in the integrator clone, `decisions.md`
entry, next sync pushes and renders). `ai-sync` help renames item 4 to
"Antigravity knowledge items" and its two `log_step` lines to match. The spec's
`Status:` line becomes `approved 2026-09-18, implemented in four phases`.
`PROJECT_MAP.md` rows for `ai-knowledge` and `knowledge-seed` updated.
Files: `ai-knowledge`, `ai-sync`, the two docs, the spec.
Tests: `test-sync.sh` asserts the help contains "Antigravity knowledge items" and
not "Knowledge Items"; `test-knowledge.sh` asserts the status header line.
Acceptance: assertions pass.

### Task 5: suites and commits

Goal: both full suites with output at hand (test-tools case 20 known). One
Conventional Commit per task 1 to 4.

## Assumptions

- `create-ai-sandbox.sh` installs helpers with `install -m 0755` from the
  `ai_sandbox_helpers` list and records `DEV_TOOLS_DIR` in `$AI_SANDBOX_ROOT/config`
  (verified); a directory needs `rsync -a --delete`, which the script already
  requires.
- `ai-sandbox-migrate` refreshes helpers from `DEV_TOOLS_DIR` when the config
  exists (verified); the seed refresh sits in the same block.
- `wire_host` backs the regular `GEMINI.md` up as `GEMINI.md.pre-ai-knowledge.<ts>`
  before linking (verified); the diff is taken before that move.
- The plumbing in `cmd_propose` builds a commit on `origin/main` without a working
  tree (verified by phase 3 tests); the integrator record reuses it with `main` as
  the target ref and a fast-forward push.
- The test suite's `ai-sync` stub and help assertions exist in `tests/ai-sync/test-sync.sh`
  (verified: 35 cases).

## Deferred list

Empty.
