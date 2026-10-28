# Evidence: gitleaks hooks (brief 2026-10-28-gitleaks-hooks-brief.md)

Commits: bb6b78c (hooks, test, README, PROJECT_MAP), c5ed2ab (sandbox image + test-tools assertions).

Environment: the v8.30.1 tarball was downloaded from the GitHub release into
/tmp/claude-1000/gl (outside the tree); its sha256
551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb matches the
release's gitleaks_8.30.1_checksums.txt. The harness did not refuse the download.
Binary put on PATH for every command below: `gitleaks version` -> 8.30.1.
No `.gitleaks.toml` was added and no `gitleaks:allow` marker was needed: the
tree scan (H3) found nothing, not even the fake token in tests/ai-sync/test-sync.sh.

Design notes: one script `.githooks/gitleaks-hook`; `pre-commit` and `pre-push`
are two-line wrappers calling it. `--verbose` is needed for gitleaks to print
the finding (file, line) at all; `--redact` hides the secret. pre-push uses
`<remote sha>..<local sha>` for an existing branch and `<local sha> --not --remotes`
for a new one.

## H1
After the review fixes (commit aeaa1d9): `bash tests/git-hooks/test-hooks.sh` -> `15 run, 0 failed` (15 cases). The refused-commit case now also asserts the line (`Line: 2`, the fixture secret sits on line 2). Earlier run and cases as before: clean commit, secret refused at commit with file named and secret redacted, clean push, `--no-verify` leak refused at push, new branch with an earlier leak refused, ref deletion not blocked, missing gitleaks refused with the install source named. Original commit bb6b78c.

Review finding 4 fix: observed `gitleaks git --bogus` -> exit 126 and `gitleaks git /nonexistent` -> exit 1, so gitleaks' own errors can use 1 and the default findings code (1) cannot be told apart. The hook now passes `--exit-code 2` for findings: 2 -> "secret found", anything else -> "gitleaks itself failed (exit N)" with its output shown; both refuse. Added a case with a stub gitleaks exiting 126. `bash tests/git-hooks/test-hooks.sh` -> `19 run, 0 failed`.

## H2
After the review fixes (commit aeaa1d9): `bash tests/ai-sandbox/test-tools.sh` -> `not ok 39 - a candidate without a default is skipped
76 run, 1 failed`; the only failure is the known SDKMAN case. New assertions: tarball verified with `sha256sum -c -` against the pinned `GITLEAKS_LINUX_X64_SHA256` (value from the release checksums file, matches the downloaded tarball), `--no-same-owner` extraction, and a check that every version copy in `.githooks/*` and `README.md` equals `GITLEAKS_VERSION` (negative check: changing one README copy to v8.30.2 made it `not ok`, reverted).

## H3
`gitleaks dir . --redact --no-banner` at the repository root after the fixes, whole tree:
```
7:16AM INF scanned ~1063633 bytes (1.06 MB) in 248ms
7:16AM INF no leaks found
```
Also `gitleaks git --redact --no-banner` earlier: `221 commits scanned ... no leaks found`. (The earlier entry's ~1091 bytes figure was the staged diff of c5ed2ab scanned by the pre-commit hook, not the tree scan.)

## H4
`git config core.hooksPath` -> `.githooks`. Both commits of this task went
through pre-commit; output at commit bb6b78c and c5ed2ab:
`INF 0 commits scanned. / INF scanned ~6485 bytes (6.49 KB) in 153ms / INF no leaks found`
(bb6b78c) and `... scanned ~1091 bytes (1.09 KB) ... no leaks found` (c5ed2ab).

## H5
`bash tests/ai-sync/test-sync.sh` -> `37 run, 0 failed`.
`bash tests/ai-sandbox/run-tests.sh` -> `SOME SUITES FAILED`, exactly three
failures, all pre-existing: test-tools 35 (SDKMAN, known), and test-delegate
43 "writer prompt has no-tools line" and 48 "second-reviewer prompt has no-commands
line". The two test-delegate failures reproduce identically on a clean worktree
of f5f6cfb (before this task), so they are not caused by it; not fixed (out of
scope; likely the a6fd318 agy grant changed the prompt wording the test asserts).
Every other suite: 0 failed.
