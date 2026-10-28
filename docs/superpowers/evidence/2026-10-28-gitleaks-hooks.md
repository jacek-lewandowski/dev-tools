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
`bash tests/git-hooks/test-hooks.sh` -> 14 cases, `14 run, 0 failed`: clean commit ok;
staged secret refused at commit, file named, secret redacted; clean push ok;
`--no-verify` secret commit refused at push, remote untouched; new branch with
secret in an earlier commit refused, branch not created; ref deletion not blocked;
with gitleaks off PATH the commit is refused and the message names the releases
page and create-ai-sandbox.sh. (First run, before `--verbose` was added, failed
"the file is named": the hook printed no location; fixed.) Fixture token is composed
at runtime. Commit bb6b78c.

## H2
`bash tests/ai-sandbox/test-tools.sh` -> `72 run, 1 failed`; the only failure is
`not ok 35 - a candidate without a default is skipped` (the known sandbox-only
SDKMAN case). New assertions (gitleaks download URL at the pinned release,
`ARG GITLEAKS_VERSION=8.30.1`, `gitleaks version;` smoke test, notes mention)
all `ok`. Commit c5ed2ab.

## H3
`gitleaks dir . --redact --no-banner` -> `INF scanned ~1091 bytes ... no leaks found`
(and over the whole tree after the commits: `scanned ~1038761 bytes (1.04 MB) ... no leaks found`).
Also `gitleaks git --redact --no-banner` -> `221 commits scanned ... no leaks found`.

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
