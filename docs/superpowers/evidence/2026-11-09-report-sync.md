# Evidence: report sync through refs/reports

## R9 host smoke on the real GitHub remote (run by the user, 2026-11-09)

Run on the host in `~/.ai-sandbox/knowledge/main`, the brief's R9 block wrapped in
`bash <<'EOF'` (only so that `set -e` does not close the user's shell). Output as
pasted by the user, abridged to the lines that settle each step:

- push: `* [new reference] 83609236d2834f31002aeaa57b7058c6aa3dda0f -> refs/reports/9999-12-31-smoke-test-0000`
- `ls-remote origin 'refs/reports/*'`: `83609236... refs/reports/9999-12-31-smoke-test-0000`
- `fetch --prune origin` in the host checkout: no report ref taken (it pruned 30 stale
  `origin/proposal/*` tracking refs of already-deleted remote branches); the following
  `for-each-ref refs/reports` printed nothing.
- scratch repo `fetch origin 'refs/reports/*:refs/reports/*'`: `* [new ref] refs/reports/9999-12-31-smoke-test-0000`;
  `for-each-ref`: `83609236... commit refs/reports/9999-12-31-smoke-test-0000`
- leased delete: `- [deleted] refs/reports/9999-12-31-smoke-test-0000`
- final `ls-remote origin 'refs/reports/*'`: printed nothing.

Result: GitHub accepts push, fetch by explicit refspec and leased delete of a custom
`refs/reports/*` namespace; default fetch does not take it. The brief's feasibility
assumption holds. Recorded by Skippy Wspaniały (lead).
