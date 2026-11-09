# 2026-11-09-ai-delegate-read-denied (Zuzia) - diagnosis only, fix not landed

## Reproduction (agy 1.4.0, model gemini-3.8-flash-high)
- Settings agy reads headless: /home/jlewandowski/.gemini/antigravity-cli/settings.json (log line:
  "CLI settings initialized: permissions=&{Allow:[read_url(*) command(ls) ... command(jq)] Deny:[] Ask:[]}, toolPermission=request-review").
  Contains read_url(*) + 26 command(<tool>) grants from a6fd318 (merged by create-ai-sandbox.sh, "agy grants" block, line ~1490). No read_file grant.
- `cd repo; agy -p "Read the file docs/superpowers/specs/2026-11-09-ui-prototype-track-design.md ..." --model gemini-3.8-flash-high`
  -> answers (first line). Same from a cwd of `.ai-delegate/t/work` with --add-dir <repo> and an absolute path -> answers.
- Same call reading `/home/jlewandowski/knowledge/rules/global.md` (outside workspace) ->
  `jetski: no output produced — a tool required the "read_file" permission ... (e.g. read_file(<target>))`.
- Real `bin/ai/ai-delegate second-reviewer <task>` -> same error; agy log: `Print mode: soft-denying tool confirmation "ReadFile" at step 4`.
  The spec the task names mentions ~/knowledge/{rules,roles,skills,.git/...}; the model reads files there (outside the workspace = cwd + --add-dir).

## Cause
Grants cover only command(<program>) and read_url; the file-reading tool is a separate permission, read_file(<target>),
and agy auto-denies it for paths outside the workspace (cwd $run/work + --add-dir repo). In-repo reads are auto-allowed;
~/knowledge (and any other path outside the repo) is not. The "command" denial of run 1 is the same class (cat on an outside path).
Cause is in this repository's grants (create-ai-sandbox.sh block), settings file is writable here.

## Not done
Verifying the allow-rule syntax needs a live edit of settings.json (e.g. `read_file(/home/jlewandowski/knowledge/**)`);
the permission system denied that edit (self-modification), so the glob form is unverified. No test written, no commit.

## Live check after the user added read_file(/home/jlewandowski/knowledge/**)
- agy log confirms the entry is loaded (Allow list ends with read_file(/home/jlewandowski/knowledge/**)).
- Minimal repro reading /home/jlewandowski/knowledge/rules/global.md (file exists, realpath identical): STILL denied,
  `Print mode: soft-denying tool confirmation "ReadFile" at step 2`. So the `**` glob form is not accepted.
- The agy binary's embedded automation prompt documents the grant form: `read_file(<absolute_path>)`, e.g.
  `read_file(/Users/alice/notes)` (a directory path without a glob; "never read_file(*) or read_file(/)"). Untested here.
- Real ai-delegate run not repeated (same denial). No commit; test and block unchanged.

## Fix (user set read_file(/home/jlewandowski/knowledge) in settings.json)
- Minimal repro reading ~/knowledge/rules/global.md: passes ("# Global Software Engineering Rules ...").
- Real `bin/ai/ai-delegate second-reviewer ...second-review-task.md`: rc=0, JSON report saved to
  docs/superpowers/evidence/2026-11-09-ui-prototype-track-second-review.md (verdict block, 4 important, 2 minor).
- Red: with bin/ai/create-ai-sandbox.sh at HEAD, `bash tests/ai-sandbox/test-tools.sh` -> `not ok 71`, `not ok 72`, `81 run, 2 failed`.
- Green after fix: `81 run, 0 failed`.
- Change: GRANTS.append("read_file(~/knowledge)") in the agy grants block; entry is the plain dir (glob `**` not accepted).
