# Evidence: Claude Code plugins at sandbox start (brief 2026-10-28-claude-plugins-brief.md)

Commit de75852 (entrypoint section, constant, list file, doctor line, notes line, test, PROJECT_MAP).

Design: the five ids live in the `CLAUDE_PLUGINS` constant in create-ai-sandbox.sh and are
rendered once into `claude-plugins.list` (copied to /usr/local/share/ in the image); the
entrypoint and sandbox-doctor read that file, so no id is repeated. The section runs in a
background subshell: marketplace ensured (list, add if absent), then
`plugin list --json`; if that fails nothing is installed; the marketplace is updated and
`plugin install <id> -y` run only for absent ids. Log: /tmp/claude-plugins.log.

## P1
`bash tests/ai-sandbox/test-plugins.sh` -> `28 run, 0 failed`. Covers: empty list adds + updates
the marketplace and installs all five with -y; list with one enabled and one disabled plugin
installs exactly the three missing and never installs the two present (no marketplace add when
known); all present -> no install, no update; a stub failing every command -> exit 0 and no
install; entrypoint hands off in under a second.

## P2
Same suite: each of the five ids appears exactly once in the generated build directory
(`grep -rhoF "<id>@claude-plugins-official" $build | wc -l` = 1, five cases ok), Dockerfile has
`COPY claude-plugins.list /usr/local/share/claude-plugins.list`, sandbox-doctor has
`status "claude plugins"`. All ok.

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
`bash tests/ai-sandbox/run-tests.sh` -> three failures, all pre-existing and unrelated:
test-tools 35 (SDKMAN, known) and test-delegate 43 and 48 (also fail at f5f6cfb, see the
gitleaks evidence). test-plugins.sh is picked up by the runner and passes.

Host step (not performed): re-run create-ai-sandbox.sh to rebuild the image with the new entrypoint.
