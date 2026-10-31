# Evidence: ai-delegate preflight probe of agy

Task: instruction in the lead's message, no brief. Implementer: Wojtek.
Commit: 980754f8db5f444e44a6c0c955b9d23344c33152 `feat(ai-delegate): probe agy before a run`.

Change: `bin/ai/ai-delegate` runs, right after the `agy models` sign-in check,
`timeout 16s agy -p "Reply with exactly the word OK and nothing else." --model "$model" --print-timeout 15s --disable-slash-commands`
with stdout and stderr captured; a non-zero exit, a timeout or output without the word `OK`
prints `agy did not answer the preflight within 15 seconds; use the Claude subagent` to stderr
and exits 3. The exit-code comment on line 8 now reads
`3 agy not signed in or silent on the preflight (use the Claude subagent instead).`
`tests/ai-sandbox/test-delegate.sh`: the stub `agy` answers the preflight prompt itself
(`OK`, or hangs / answers `Hello` under `STUB_PREFLIGHT=hang|wrong`) and gains five assertions
beside the existing "not signed in exits 3" case.

## Syntax check

Command: `bash -n bin/ai/ai-delegate && echo "bash -n: ok"`

Result:
```
bash -n: ok
```

## Red run (test written before the change)

Command: `bash tests/ai-sandbox/test-delegate.sh 2>&1 | grep -n 'preflight\|run,'`

Result:
```
34:not ok 34 - hung preflight exits 3
36:not ok 35 - hung preflight message
37:        expected to contain 'agy did not answer the preflight within 15 seconds; use the Claude subagent', got ''
38:ok 36 - hung preflight cut within 20 s
39:not ok 37 - preflight without OK exits 3
41:not ok 38 - preflight without OK message
42:        expected to contain 'agy did not answer the preflight within 15 seconds; use the Claude subagent', got ''
85:63 run, 6 failed
```
(Case 36 passes before the change because the unchanged script, with no probe, does not wait at all;
it guards the bound after the change.)

Baseline before any edit: `58 run, 2 failed`; the two failures are `writer prompt has no-tools line`
and `second-reviewer prompt has no-commands line`, wording mismatches between the test and the
script that predate this task and are outside its scope.

## Green run

Command: `bash tests/ai-sandbox/test-delegate.sh 2>&1 | grep -n 'preflight\|exits 3\|^not ok\|run,'`

Result:
```
32:ok 32 - not signed in exits 3
34:ok 34 - hung preflight exits 3
35:ok 35 - hung preflight message
36:ok 36 - hung preflight cut within 20 s
37:ok 37 - preflight without OK exits 3
38:ok 38 - preflight without OK message
48:not ok 48 - writer prompt has no-tools line
61:not ok 53 - second-reviewer prompt has no-commands line
81:63 run, 2 failed
```
The two remaining failures are the pre-existing ones named above.

## Manual probe of the real agy (shape and timing of the answer)

Command (sandbox, 2026-10-31):
```
start=$(date +%s); out=$(timeout 20 agy -p "Reply with exactly the word OK and nothing else." --model gemini-3.8-flash-high --print-timeout 15s --disable-slash-commands 2>&1); rc=$?; end=$(date +%s); echo "rc=$rc elapsed=$((end-start))s"; printf '%s\n' "$out"
```

Result:
```
rc=0 elapsed=13s
--- output:
OK
```

## Probe path for real, through the script

Task file `trivial-task.md`: `Reply with exactly the word DONE and nothing else. Do not use any tools.`

Command:
```
PS4='+$(date +%s) ' BASH_XTRACEFD=9 bash -x bin/ai/ai-delegate scout <scratch>/trivial-task.md 9><scratch>/trace.log
```

Result:
```
rc=0 total_elapsed=30s
--- stdout:
DONE

--- stderr:
ai-delegate: conversation_id=0973356c-4aca-4203-a594-af39b3f84be2
--- preflight timing from trace:
87:++1793434083 timeout 16s agy -p 'Reply with exactly the word OK and nothing else.' --model gemini-3.8-flash-high --print-timeout 15s --disable-slash-commands
88:+1793434096 preflight_out=OK
90:+1793434096 grep -qw OK
97:+1793434096 mkdir -p /home/jlewandowski/dev/public/dev-tools/.ai-delegate
```
Preflight answered `OK` in 13 s (1793434083 to 1793434096), the script went on to the real run,
which returned `DONE`; 30 s in total. Two probes today took 13 s each against the 15 s limit the
instruction fixes; the lead's manual probe of the same day took 9 s.

## Failure path with a stub agy that lists models but hangs on `-p`

Stub `agy` on PATH:
```
#!/usr/bin/env bash
if [ "${1:-}" = "models" ]; then echo "gemini-3.8-flash-high	Gemini 3.8 Flash (High)"; exit 0; fi
sleep 60
```

Command:
```
start=$(date +%s); PATH="<scratch>/stubbin:$PATH" bin/ai/ai-delegate scout <scratch>/trivial-task.md >stub-out.txt 2>stub-err.txt; rc=$?; end=$(date +%s); echo "rc=$rc elapsed=$((end-start))s"; cat stub-out.txt; cat stub-err.txt; pgrep -af 'sleep 60'
```

Result:
```
rc=3 elapsed=16s
--- stdout:
--- stderr:
agy did not answer the preflight within 15 seconds; use the Claude subagent
--- leftover sleep processes:
<only the invoking shell's own command line matched; no orphaned sleep>
```

## Full suite of the changed package

Command: `bash tests/ai-sandbox/run-tests.sh`

Per-file totals:
```
test-account.sh          32 run, 0 failed
test-build-caches.sh    151 run, 0 failed
test-capacity.sh         16 run, 0 failed
test-create-identity.sh  13 run, 0 failed
test-delegate.sh         63 run, 2 failed   (not ok 48 writer prompt has no-tools line;
                                             not ok 53 second-reviewer prompt has no-commands line; pre-existing)
test-devices.sh          16 run, 0 failed
test-display.sh           5 run, 0 failed
test-gc.sh               23 run, 0 failed
test-helpers.sh          12 run, 0 failed
test-idea.sh             19 run, 0 failed
test-identity.sh         17 run, 0 failed
test-image.sh            14 run, 0 failed
test-knowledge.sh       387 run, 0 failed
test-migrate.sh          32 run, 0 failed
test-options.sh          15 run, 0 failed
test-plugins.sh          33 run, 0 failed
test-resources.sh        34 run, 0 failed
test-sdkman.sh           27 run, 0 failed
test-shared.sh           39 run, 0 failed
test-tools.sh            76 run, 1 failed   (not ok 39 a candidate without a default is skipped;
                                             known to fail only inside a sandbox, pre-existing)
```
Total: 1024 run, 3 failed, all three pre-existing and unrelated to this change.

## Fix round

Review: /home/jlewandowski/dev/public/dev-tools/docs/superpowers/evidence/2026-10-31-ai-delegate-preflight-review.md
(Arek, not blocked; lesser findings 1 and 2 fixed here, finding 3 noted as harmless).
Commit: b623f32accc3f831f05cea212e50281744889da9
`fix(ai-delegate): tell a preflight timeout from an agy error, kill a stuck probe`.

Change: the probe runs under `timeout -k 5s 16s` with `|| preflight_rc=$?` (the shape line 80 uses).
Exit 124 or 137 (timeout's own codes, the second when `-k` had to KILL) keeps the message
`agy did not answer the preflight within 15 seconds; use the Claude subagent`. Any other
non-zero exit, or exit 0 without the word `OK`, prints
`agy failed the preflight (exit <rc>): <last non-empty output line>; use the Claude subagent`
(the `: <line>` part is omitted when the output is empty); exit 3 in every case, one stderr line.
Test: stub gains `STUB_PREFLIGHT=stuck` (`trap '' TERM; while :; do sleep 1; done`) and
`STUB_PREFLIGHT=error` (`Error: model not found: custom-model` on stderr, exit 1); the timing
bound moves from `< 20` to `< 25`; six assertions added, the `wrong` message assertion updated.

### Syntax check

Command: `bash -n bin/ai/ai-delegate && echo "bash -n: ok"`
```
bash -n: ok
```

### Preflight cases of tests/ai-sandbox/test-delegate.sh

Command: `bash tests/ai-sandbox/test-delegate.sh 2>&1 | grep -n 'preflight\|exits 3\|^not ok\|run,'`
```
32:ok 32 - not signed in exits 3
34:ok 34 - hung preflight exits 3
35:ok 35 - hung preflight message
36:ok 36 - hung preflight cut within 25 s
37:ok 37 - preflight ignoring SIGTERM exits 3
38:ok 38 - preflight ignoring SIGTERM message
39:ok 39 - preflight ignoring SIGTERM killed within 25 s
40:ok 40 - preflight without OK exits 3
41:ok 41 - preflight without OK message
42:ok 42 - failed preflight exits 3
43:ok 43 - failed preflight quotes agy
44:ok 44 - failed preflight is not called a timeout
54:not ok 54 - writer prompt has no-tools line
67:not ok 59 - second-reviewer prompt has no-commands line
87:69 run, 2 failed
```
The two failures are the pre-existing wording mismatches named above. No red run for the new
assertions is claimed separately: they were written together with the fix.

### Stub paths through the script

Hang stub (lists models, `sleep 60` on `-p`), same stub as the first round:
```
rc=3 elapsed=16s
agy did not answer the preflight within 15 seconds; use the Claude subagent
```
Stuck stub (lists models, `trap '' TERM; while :; do sleep 1; done` on `-p`):
```
rc=3 elapsed=21s
agy did not answer the preflight within 15 seconds; use the Claude subagent
leftover stub processes: 0
```
(16 s to SIGTERM, which the stub ignores, then 5 s to SIGKILL from `-k 5s`.)

### Full suite of the changed package

Command: `bash tests/ai-sandbox/run-tests.sh`
```
test-delegate.sh   69 run, 2 failed   (not ok 54 writer prompt has no-tools line;
                                       not ok 59 second-reviewer prompt has no-commands line; pre-existing)
test-tools.sh      76 run, 1 failed   (not ok 39 a candidate without a default is skipped; sandbox-only, pre-existing)
all other 18 files 0 failed
TOTAL: 1030 run, 3 failed
```
All three failures pre-existing and unrelated to this change.
