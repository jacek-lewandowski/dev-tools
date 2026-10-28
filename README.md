# dev-tools
My development utils

## Git hooks

`.githooks/` refuses a commit or push that adds a password, API key or token,
using [gitleaks](https://github.com/gitleaks/gitleaks) v8.30.1. Activate it once
per clone (the host and the ai-sandbox share the same `.git`, so one activation
covers both):

    git config core.hooksPath .githooks

- `pre-commit` scans the staged changes; `pre-push` scans every commit being
  pushed, including the whole history of a new branch. Findings name the file
  and line with the secret redacted.
- Fail closed: without `gitleaks` on `PATH` the hooks refuse. On the host,
  install the v8.30.1 release binary from
  <https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1>; the sandbox
  image has it after `create-ai-sandbox.sh` is re-run.
- A known fake is suppressed with a `gitleaks:allow` comment on its line.
- Tests: `bash tests/git-hooks/test-hooks.sh` (needs `gitleaks` on `PATH`).
