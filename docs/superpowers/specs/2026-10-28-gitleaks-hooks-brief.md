# Brief: block secrets at commit and push with gitleaks

Date: 2026-10-28. Task brief, no phase plan. The implementer takes it directly;
one review follows. Evidence file: `docs/superpowers/evidence/2026-10-28-gitleaks-hooks.md`.

## Goal

A commit or a push in this repository that adds a password, API key or token
is refused locally by gitleaks, on the host and inside the ai-sandbox, with the
offending file and line named and the secret itself redacted.

## User decisions

- Tool: gitleaks, pinned to v8.30.1 (MIT, static binary, no account, no
  network). Chosen over TruffleHog (verification needs network, AGPL,
  `curl | sh` installer) and detect-secrets (stale, noisier).
- Both hooks: `pre-commit` scans the staged changes
  (`gitleaks git --pre-commit --staged --redact`); `pre-push` scans every
  commit in every pushed range read from stdin, including the whole history of
  a new branch (`<local sha> --not --remotes`); a ref deletion is skipped.
  History already on the remote is out of scope: the push hook scans only what
  is being pushed, and nothing rewrites history.
- The hooks are versioned in the repository under `.githooks/` and activated
  per clone with `git config core.hooksPath .githooks`. The `.git` directory is
  the same on the host and in the sandbox, so one activation covers both.
  The logic lives once: one script, the two hook names dispatch to it.
- Fail closed: when `gitleaks` is not on `PATH` the hook refuses with a message
  that names where to get it (host: the releases page, same version; sandbox:
  rebuild the image with `create-ai-sandbox.sh`). No silent pass-through.
- The sandbox image installs the pinned binary from the GitHub releases
  tarball the way it installs comby: a `GITLEAKS_VERSION` constant beside
  `COMBY_VERSION`, download in the Dockerfile, `gitleaks version` as the
  build-time smoke test, a `sandbox-doctor` status line, a line in the tool
  notes block. Never an install script piped to a shell.
- False positives in the tracked tree are suppressed inline with
  `gitleaks:allow`, only on lines that are known fakes (the test fixture in
  `tests/ai-sync/test-sync.sh` is one candidate; add the comment only where a
  scan of the tree actually reports a finding). No `.gitleaks.toml` unless a
  finding cannot be handled inline; say so in the evidence file if one is added.
- Documentation: a short "Git hooks" section in `README.md` (activation, host
  install, what the hooks do) and entries for `.githooks/` and the new test
  directory in `PROJECT_MAP.md`.

## Obligations (tests and acceptance)

- H1 `tests/git-hooks/test-hooks.sh`, self-contained like
  `tests/ai-sync/test-sync.sh`, against a temporary repository with the hooks
  activated and a temporary bare remote: a staged file containing a secret
  gitleaks detects is refused at commit; a clean file commits; a commit made
  with `--no-verify` that contains a secret is refused at push; a clean push
  succeeds; a new branch with a secret in an earlier commit is refused at push;
  with `gitleaks` removed from `PATH` the commit is refused and the message
  names the install source. Expected: every case passes. The fixture secret is
  composed at runtime (or carries `gitleaks:allow`) so the test file itself
  does not trip the hook when committed.
- H2 `bash tests/ai-sandbox/test-tools.sh`: new assertions that the generated
  Dockerfile downloads the pinned gitleaks release and smoke-tests
  `gitleaks version`. Expected: the suite passes.
- H3 `gitleaks dir . --redact` at the repository root after the change:
  no findings except lines marked `gitleaks:allow`. Record the command output.
- H4 `git config core.hooksPath` set in this clone and one real commit of this
  task going through the pre-commit hook: record the hook's output.
- H5 `bash tests/ai-sandbox/run-tests.sh` and `bash tests/ai-sync/test-sync.sh`
  stay green. The SDKMAN case known to fail only inside a sandbox (test-tools,
  "a candidate without a default is skipped") is pre-existing; note it, do not
  fix it.

Acceptance: H1 through H5 evidenced in the evidence file with the actual
command output and the commits.

## If the environment cannot run it

The sandbox image does not yet contain gitleaks. Install the pinned release
tarball into a directory on `PATH` for the tests (the sandbox allows it); if
that download is refused by the harness, write the tests anyway, record the
refusal in the evidence file under H1, and stop so the lead can batch the host
run for the user. Do not weaken or skip the tests.
