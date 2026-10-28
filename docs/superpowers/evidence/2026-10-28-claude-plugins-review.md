# Review: Claude Code plugins at sandbox start (33ea393..d35da26)

Arek, reviewer 2. Brief `docs/superpowers/specs/2026-10-28-claude-plugins-brief.md`,
evidence `docs/superpowers/evidence/2026-10-28-claude-plugins.md`. Verdict: **blocked**, two Important findings.

## Findings

1. **Important. `tests/ai-sandbox/test-plugins.sh`, `run_ep` and the timing case, run the whole
   generated `entrypoint.sh` in the live sandbox.** The entrypoint's earlier sections are not
   isolated: `RUNTIME_DIR="/run/user/$(id -u)"` and `: > "$ENV_SNAPSHOT"` truncate and rewrite the
   real `/run/user/1000/sandbox-env.sh`, and `eval "$(dbus-launch --sh-syntax)"` starts a session
   bus that is never stopped. Reproduced at d35da26: one run of the suite took the
   `dbus-daemon` count from 26 to 31 and rewrote `sandbox-env.sh` (mtime 07:17:44), which now points
   at a stray bus instead of the one the container started (PID 17). In a sandbox started with
   `--with-docker` or in wayland mode the `DOCKER_HOST` / `DISPLAY=:99` lines are lost the same way,
   so every later shell gets a wrong environment; `run-tests.sh` (the milestone suite, run inside
   sandboxes) does this every time. Resolve: keep the test on the rendered entrypoint but neutralise
   the other sections, e.g. a runtime-dir override the entrypoint honours plus a `dbus-launch` stub
   in `$stub`, or run only the rendered plugin section cut out between its markers. Operator note:
   the stray `dbus-daemon`s started 07:12-07:17 today (all but PID 17) and the current
   `sandbox-env.sh` are leftovers of the implementer's and this review's runs.
2. **Important. `bin/ai/create-ai-sandbox.sh`, `TOOL_NOTES` line for the plugins, repeats the
   plugin list.** It names the five plugins literally, so a sixth added to `CLAUDE_PLUGINS` leaves
   the agents' notes listing five; this breaks the user decision "a later plugin is added there and
   nowhere else". P2's search (`grep -rhoF "<id>@claude-plugins-official"` over the build dir)
   cannot see it: the notes carry bare names and are not rendered into the build dir. Resolve:
   render the names from the constant (for example `${CLAUDE_PLUGINS[*]%@*}` inside the
   double-quoted `TOOL_NOTES`) or drop the names from the line, and assert in the test that the
   notes line follows the constant.
3. Minor. `sandbox-doctor` plugins line: any Python failure, including a missing
   `/usr/local/share/claude-plugins.list`, is reported as "claude CLI unavailable". The paths
   `/usr/local/share/claude-plugins.list` and `/tmp/claude-plugins.log` are each written in three
   places (Dockerfile COPY / entrypoint default / doctor; entrypoint / doctor / notes); one search
   for either name finds all of them.
4. Minor. Entrypoint plugin section: `claude plugin marketplace list --json 2>&1 | python3` feeds
   stderr into the JSON parser, so any CLI warning on stderr triggers a needless (idempotent)
   `marketplace add` each start; the early `exit 0` when `claude` or the list is missing writes
   nothing to the log; network steps have no `timeout`, so a hung clone leaves a background process
   until the container stops (the start itself is not delayed).

## Obligations re-run

- P1: `bash tests/ai-sandbox/test-plugins.sh` at d35da26 (detached worktree) -> `28 run, 0 failed`.
  Read: the stub answers only the two list calls from fixtures and records argv; cases cover the
  empty list (add + update + five `install <id> -y`), one enabled and one disabled present (three
  installs, none for the two, no add), all present (no install, no update), every command failing
  (exit 0, no install). It runs the rendered `$build/entrypoint.sh`, not a copy (see finding 1).
- P2: same run, cases 1-7 pass; I confirmed by reading that the ids exist once in
  `CLAUDE_PLUGINS` and once in `claude-plugins.list`, apart from the notes copy in finding 2.
- P3: `claude plugin list --json` here now lists all five at `scope: user`, `enabled: true`.
- P4: `bash tests/ai-sandbox/test-tools.sh` at d35da26 -> `72 run, 1 failed` (35, the known SDKMAN
  case). A first run against the live tree, while commits aeaa1d9/d143001 landed, failed 52 cases
  with build files missing mid-run; two reruns were clean apart from the SDKMAN case, so I put that
  down to the concurrent work, not to this diff.

Read in full and found sound: backgrounding with all output in the log, the start not depending on
the network, the parsing of the real `claude plugin list --json` / `marketplace list --json`
(arrays with `id` / `name`, checked against CLI 2.1.302), install only for absent ids, update only
when something is missing, no direct writes to `~/.claude/settings.json`, `@MARKETPLACE@`
substitution, the Dockerfile COPY, the build hash covering the new file (it hashes the whole build
dir), and the PROJECT_MAP entries.

## Round 2 (delta d35da26..8bda9c3: 0a31fa8, 8bda9c3; gitleaks commits excluded)

Verdict: **accepted**. Findings 1 and 2 are resolved. 3 and the rest of 4 were left on
purpose and stay non-blocking.

- Finding 1 resolved. `entrypoint.sh` reads `RUNTIME_DIR="${SANDBOX_RUNTIME_DIR:-/run/user/$(id -u)}"`.
  The test exports it to `$tmp/run`, stubs `dbus-launch` and unsets the optional services.
  `bash tests/ai-sandbox/test-plugins.sh` at 8bda9c3 (detached worktree): `33 run, 0 failed`.
  Measured around the run myself: `/run/user/1000/sandbox-env.sh` stat `07:22:33.795 69` before
  and after; `dbus-daemon` count 1 before, 1 after. The new cases 29-32 assert the same.
- The override cannot be abused. `grep -rn SANDBOX_RUNTIME_DIR bin tests` finds only the
  entrypoint line and the test. Nothing sets it: the compose `environment:` block (`create-ai-sandbox.sh`,
  COMPOSE_ENV), the Dockerfile `ENV` lines and `/etc/ai-sandbox-env.sh` (BASH_ENV) all leave it
  out. The only other way to set it is the host-side `.env` that compose reads, which only the
  host operator writes and which can already change everything else. If it were set, the
  only effect is that the shells' hard-coded snapshot read (`sandbox-bashrc`, line 1731) finds
  nothing. That is a lost convenience, and no file outside the runtime directory is written.
- Finding 2 resolved. `CLAUDE_PLUGIN_NAMES` is built from `"${CLAUDE_PLUGINS[@]}"` with
  `${_p%@*}`, and the notes line expands it; no plugin name is written by hand any more. Case 33
  compares the rendered `GEMINI.md` line with `claude-plugins.list` and passes.
- Finding 4, partially fixed: `2>&1` is gone from the marketplace parse; `timeout` 60/120/120/180 s
  wraps list, add, update and install. Without `pipefail`, the `if` tests the parser's exit
  status, as before.
- `bash tests/ai-sandbox/test-tools.sh` at 8bda9c3: `76 run, 1 failed`. The failure is case 39,
  the known SDKMAN case.
- Non-blocking: case 30 counts every `dbus-daemon` on the machine, so another process starting or
  killing one during the run, as the coordinator's clean-up could, would make it flaky.
