# Review of spec revision 3 (phase 1 update)

Date: 2026-10-08. Verdict: **blocked** (1 critical, 6 important). Fix round 1 of 2.

## Critical

1. **C5 "Requests" / D19: the fixed list lets agy read any file and can lead to command
   execution without the user.** It bans only `-c`, `--output`, `-O`, `--ext-diff` (a deny list
   over an open option set) and the lead runs matching requests in the main tree, returning the
   output to agy. Reads: `diff /dev/null ~/.config/gcloud/<file>`, `git diff --no-index /dev/null
   ~/.netrc`, `git blame --contents ~/.ssh/id_ed25519 -- README.md`, `git grep --no-index` /
   `--untracked` (returns `.env`). Breaks I5, D20, the brief's "paths outside the project stay
   unreadable", global §1 (secret reads are 🔴). Execution: global options before the subcommand are
   not excluded; agy can write /tmp, so it writes `/tmp/x/.git/config` with
   `core.fsmonitor=<program>` and requests `git -C /tmp/x status`, or uses `--git-dir`/`--work-tree`;
   `git -p` and an env prefix (`GIT_PAGER=...`) are not addressed.
   Resolution: an allowlist of forms — subcommand right after `git`, no global option, no env
   assignment; no `--no-index`, `--contents`, `--untracked`, `--others`, `--ignored`, `-f/--file`;
   every path argument resolves inside the top level and is tracked; coreutils `diff` only between
   such paths; anything else goes to the user. Alternatively run requests in a fresh worktree.

## Important

2. **I6 vs C6 vs D21: fetch for writer and second reviewer.** C6's settings check accepts
   `read_url(*)` on every route; S3b measured the rule as global to every agy run, so a writer or
   second-reviewer run with fetch and project read is reported as confined — the exfiltration path
   the user accepted only for the scout (e.g. injected text in the diff under review). D21 lists it
   as open but C6 settles it the less safe way. Resolution: route-dependent check; align I6.
3. **/tmp residual vs the user's decision.** S3 measured /tmp readable and writable by every agy
   run; the lead's scratchpad and persisted tool outputs live there (`/tmp/claude-1000/...`). C3
   protects only the wrapper's files. Resolution: a short spike (does agy's temp grant follow
   TMPDIR? a private /tmp through a mount namespace, the sandbox has sudo), or an explicit D-item.
4. **C6 settings check cannot pass on a real install.** The sandbox's agy settings.json has no
   `toolPermission`/`allowNonWorkspaceAccess` keys; defaults come from the binary. Resolution:
   check effective values from `agy -p "/config"` (as S3 said), or state that a missing key means
   the default verified for agy 1.1.22.
5. **C6 worktree contents, hooks, cleanup.** "Uncommitted changes to tracked files" is undefined:
   staged new files (a mistakenly added `.env`) count as tracked; `cp` follows symlinks out of the
   project; C3 secret patterns are not applied to the worktree; the phase 1 outcome "the worktree
   keeps secrets out" overstates S3b (tracked files with secrets stay visible). `git worktree add`
   runs `post-checkout` hooks and smudge filters (LFS), contradicting I5. `git worktree remove`
   refuses modified worktrees without `--force`. Resolution: apply changes with
   `git diff --binary HEAD | git apply`; delete files matching C3 secret patterns and symlinks
   resolving outside the worktree before agy starts; create with hooks off
   (`core.hooksPath=/dev/null`); unique worktree per run; remove with `--force`.
6. **C6 command line** lacks `--add-dir <worktree>` and `--print-timeout` (agy's 5 min default
   turns a 10 min brief timeout into ERROR -> tool-error -> fallback/skipped). Resolution: add both,
   `--print-timeout` from the brief's `timeout`.
7. **Phases 2/3 cannot be planned without guessing; undeclared global rule change.** Phase 2 says
   it does not change role text, yet I10 for the scout changed from "no file access" to "reads the
   project", so `roles/scout.md` and a native scout's `tools:` are a guess. Nothing puts the lead's
   `requests` procedure where the lead reads it (phase 2 global.md items, phase 3 tool notes). The
   lead running `git show/diff` and reading the output contradicts global §2 ("reads reports, not
   code"), undeclared. Resolution: name where the procedure lives; declare the §2 change, hand
   requests to the runner, or have the lead redirect output into `.ai-delegate/` and pass it as an
   input without reading it.

## Lesser

- D20 calls the untracked/ignored exclusion "the lead's assumption"; the brief records it as
  confirmed by the user.
- The brief still carries the superseded bullet "agy may run read-only git".
- Phase 3 provisioning of `read_url(*)`: `.gemini` is seeded once and re-pulled by
  `ai-sandbox-account refresh`, which drops the rule; say where the rule is written.
- `-p "<prompt>"` as one argument fails above 128 KiB (E2BIG) for large writer inputs.
- `~/.gemini/antigravity-cli/scratch/` was not tested for reads in default mode.
- With project read on, models try `run_command` and get CANCELED; consider one retry.

## User choices that remain

1. D21: fetch for all agy runs, scout-only (route-dependent), or none (scout `not-confined`).
2. /tmp: mitigation spike or accepted residual.
3. Tracked secrets: strip C3-pattern files from the worktree or accept as residual.
4. Who runs `requests`: lead (§2 change), lead redirecting without reading, or runner.
5. D23: MCP exposure.
