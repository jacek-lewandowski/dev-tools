# Review: gitleaks hooks (f5f6cfb..7dccf1c)

Fiona, reviewer 1. Against `docs/superpowers/specs/2026-10-28-gitleaks-hooks-brief.md`
and `docs/superpowers/evidence/2026-10-28-gitleaks-hooks.md`.

Verdict: **accept, no blocking findings.**

## Obligations re-run (gitleaks 8.30.1 from /tmp/claude-1000/gl/bin on PATH)

The tarball's sha256 (551f6fc8...) matches the release's checksums file.

- H1 `bash tests/git-hooks/test-hooks.sh` gives `14 run, 0 failed`. I also probed extra
  pre-push cases in a scratch repository: two refs in one push with the leak in either
  order were refused and the leaking branch was not created; two existing branches
  (clean, leak) were refused; a delete plus a leak in one push was refused; a tag, and
  an annotated tag, on an already-pushed commit pushed fine (empty range, exit 0).
  The pre-commit output names `File: f` and `Line: 3`, with `Secret: REDACTED`.
- H2 `bash tests/ai-sandbox/test-tools.sh` gives `72 run, 1 failed`. The only failure is
  35, the known SDKMAN case. The new assertions 5, 6, 7 and 50 pass.
- H3 `gitleaks dir . --redact` gives `scanned ~1047186 bytes ... no leaks found`, and
  `gitleaks git .` gives `223 commits scanned ... no leaks found`. The test fixture does
  not trip either scan.
- H4 `git config core.hooksPath` gives `.githooks`. `.githooks/pre-commit` run from the
  repository root exits 0. I cannot re-run the historical commit output; the claim is
  accepted on the config and the hook running.
- H5, on a clean `git archive 7dccf1c` export (the working tree holds another task's
  uncommitted changes): `run-tests.sh` fails only on test-delegate 43 and 48 and
  test-tools 35, all known. `test-sync.sh` gives `37 run, 0 failed`.

## Findings (none blocking)

1. Minor: commit hygiene, 7dccf1c. The evidence commit also adds the unrelated
   81-line `docs/superpowers/specs/2026-10-28-claude-plugins-brief.md`, which breaks
   "one logical change each" (§3 Commits). The code is not affected. Fixing it means
   rewriting two unpushed commits underneath work that is in progress, so the lead
   should decide; at the least, say so in the report.
2. Minor: shared version literal, `.githooks/gitleaks-hook` (the missing-binary
   message) and `README.md`. Both hard-code `v8.30.1`, apart from `GITLEAKS_VERSION`
   in `bin/ai/create-ai-sandbox.sh`. If someone bumps the constant, the hook keeps
   sending host users to the old release, so the host and the sandbox drift apart.
   A search for `8.30.1` does find every copy. To resolve: add a test-tools assertion
   that the hook message carries `$GITLEAKS_VERSION`, or add a coupling-register line.
3. Minor: Dockerfile gitleaks `RUN` in `bin/ai/create-ai-sandbox.sh`. The download is
   pinned by tag and not checksummed. That matches comby and earthly (neither has a
   sha256), so it meets the brief, but the implementer already had the release
   sha256 and a `sha256sum -c` line would make it better than the convention. Also,
   `tar` runs as root, so it keeps the archive's owner: `gitleaks` lands as uid 501,
   gid 20. To resolve: add `--no-same-owner`, or `chown root:root` after extraction.
4. Minor: misleading message, `.githooks/gitleaks-hook` `scan()`. Every non-zero
   gitleaks exit is reported as "secret found". gitleaks also exits 1 on its own
   errors (for example a bad `--log-opts` range), and the operator is then told
   there is a secret. The hook still fails closed, so this is cosmetic.
5. Minor: test gap, `tests/git-hooks/test-hooks.sh`. The brief's goal says "file and
   line named", but only the file is asserted. The hook does print `Line:` (checked
   by hand above). To resolve: add one `assert_contains ... "Line:"`.
6. Minor: evidence accuracy, H3. The first recorded result, `scanned ~1091 bytes`,
   cannot be a whole-tree `dir .` scan; it is the size of c5ed2ab's staged diff. The
   whole-tree figure in the parenthesis is the correct one. My re-run is above.

## Points checked with nothing to report

- The pre-push stdin handling covers a new branch, a deleted ref, several refs, an
  all-zeros remote sha and a remote tip that is not known locally, which falls back
  to `--not --remotes`.
- The hook fails closed, and its message names the releases page and
  `create-ai-sandbox.sh`.
- The logic lives once: the two wrappers `exec` the single script.
- The test isolates git config (`GIT_CONFIG_GLOBAL=/dev/null`).
- The fixture token is composed at runtime, so it is not a matchable literal.

## Round 2 (delta 7dccf1c..602ccdf: 5befc8c, 602ccdf)

Verdict: **accept, no blocking findings.** Findings 2, 3, 5 and 6 are resolved.
Findings 1 and 4 stay with the user, as decided.

- Finding 3, checksum: I fetched `gitleaks_8.30.1_checksums.txt` and the
  `linux_x64` tarball from the GitHub release myself, into a fresh directory. The
  tarball's sha256 is `551f6fc8...f2470eb`, which equals the release entry and
  `GITLEAKS_LINUX_X64_SHA256`. I simulated the generated `RUN` steps on that tarball:
  `sha256sum -c -` prints OK, and a corrupted hash makes it exit 1.
  `tar ... --no-same-owner` now extracts with the caller's uid, not 501.
- Finding 2, version copies: `git grep 8.30.1` at 602ccdf (docs excluded) finds the
  hook (line 13), `README.md` (lines 7, 17, 18), the generator constant and
  test-tools assertion 6. The new assertion 10 covers the hook and README copies.
  The test-tools literal enumerates itself, because it fails on a bump. Negative
  checks on a `git archive` export: changing the hook copy to 8.30.2 fails 10
  (`got '8.30.1 8.30.2 '`); bumping `GITLEAKS_VERSION` alone fails 6 and 10.
- Finding 5: `test-hooks.sh` gives `15 run, 0 failed`. `ok 4 - the line is named`
  matches `^Line: +2$`.
- Finding 6: the H3 entry is corrected and its figure matches my whole-tree scan.
- `test-tools.sh` gives `76 run, 1 failed`. The only failure is 39, the known SDKMAN
  case (renumbered from 35).

Lesser, not blocking:
- `tests/ai-sandbox/test-tools.sh`, assertion 10: it collects every `x.y.z` string
  in the whole `README.md`. If another tool's version is later added to the README,
  the test fails under a gitleaks label. To resolve: restrict the grep to lines that
  mention gitleaks, for example `grep -h gitleaks ... | grep -oE ...`.
- Bumping `GITLEAKS_VERSION` without `GITLEAKS_LINUX_X64_SHA256` passes the suite.
  The stale hash then fails only at image build, in `sha256sum -c`. That is fail
  loud, and the comment beside the constant says so; no action needed.
