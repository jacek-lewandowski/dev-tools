# Evidence: Claude Code plugins at sandbox start (brief 2026-10-28-claude-plugins-brief.md)

Commit 6862cd8 (entrypoint section, constant, list file, doctor line, notes line, test, PROJECT_MAP).

Design: the five ids live in the `CLAUDE_PLUGINS` constant in create-ai-sandbox.sh and are
rendered once into `claude-plugins.list` (copied to /usr/local/share/ in the image); the
entrypoint and sandbox-doctor read that file, so no id is repeated. The section runs in a
background subshell: marketplace ensured (list, add if absent), then
`plugin list --json`; if that fails nothing is installed; the marketplace is updated and
`plugin install <id> -y` run only for absent ids. Log: /tmp/claude-plugins.log.

## P1
After the review fixes (commit 0a31fa8): `bash tests/ai-sandbox/test-plugins.sh` -> `33 run, 0 failed`. Same cases as before, now isolated: the entrypoint honours `SANDBOX_RUNTIME_DIR` (tests only), the suite puts a stub `dbus-launch` on PATH and unsets the optional-service variables. New cases: the live `/run/user/1000/sandbox-env.sh` (mtime and size) is unchanged, the `dbus-daemon` count is unchanged (31 before and after), the stub was the one called, the snapshot landed in the overridden dir. Network steps now run under `timeout` and the marketplace check no longer feeds stderr to the JSON parser (stub cases unchanged and green).

## P2
After the fixes: the five ids still appear exactly once in the build context (cases 1-5 ok). The TOOL_NOTES plugins line is now rendered from `CLAUDE_PLUGINS` (`CLAUDE_PLUGIN_NAMES`), and a new case compares the names on the generated notes line with those in `claude-plugins.list`; it passes. (With a sixth plugin added to the constant temporarily, the count cases failed as expected and the notes case stayed green because the line follows the constant; reverted.)

## P3
Plugin section extracted from a freshly generated entrypoint and run against the real ~/.claude
(only superpowers was installed before). Log:
```
--- 2026-10-28T07:12:42Z
Updating marketplace: claude-plugins-official...✔ Successfully updated marketplace: claude-plugins-official
Installing plugin "frontend-design@claude-plugins-official"...✔ Successfully installed plugin: ... (scope: user)
Installing plugin "code-simplifier@claude-plugins-official"...✔ ... (scope: user)
Installing plugin "playwright@claude-plugins-official"...✔ ... (scope: user)
Installing plugin "claude-md-management@claude-plugins-official"...✔ ... (scope: user)
done
```
`claude plugin list --json` (id, scope, enabled):
```
claude-md-management@claude-plugins-official user True
code-simplifier@claude-plugins-official user True
frontend-design@claude-plugins-official user True
playwright@claude-plugins-official user True
superpowers@claude-plugins-official user True
```
A second run installed nothing (log: only `done`); it took 1.5 s, in the background section.

## P4
`bash tests/ai-sandbox/run-tests.sh` after the fixes -> three failures, all pre-existing: test-tools 39 (the known SDKMAN case, renumbered), test-delegate 43 and 48. test-plugins.sh passes (33 cases). `/run/user/1000/sandbox-env.sh` was not modified by the run (mtime 07:17, left as the lead asked).
