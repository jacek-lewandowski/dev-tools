# Arek, reviewer 2 — small-class diff review of 980754f8 "feat(ai-delegate): probe agy before a run"
(saved by the lead from the hand-back, 2026-10-31)

Verdict: not blocked. No Critical or Important findings. The diff does what the instruction asked and nothing else; the evidence settles every claim (red run: five new assertions fail on the old script; green run: pass; real agy answered OK in 13 s; stub-hang run exited 3 after 16 s with no orphaned sleep).

Checks: `timeout 16s` wraps the probe and signals the process group, so a stub child dies too; `--print-timeout 15s` and the outer `timeout` do not conflict; OK plus other text or OK on stderr both pass (2>&1 + grep -qw). `grep -qw OK` is reached only after exit 0. The probe uses "$model" after the default assignment. Nothing to leave behind on failure (runs before .ai-delegate/, mktemp and the trap). The stub returns before argv/prompt/cwd capture, so later assertions read the real run. Timing `< 20` against a 16 s timer leaves ~3 s margin; timers are not CPU-bound. The two pre-existing test failures (writer / second-reviewer prompt wording) date from a6fd318 (2026-10-25), unrelated.

Lesser (non-blocking):
1. Misleading message on non-timeout failures: a bad --model, a quota error or any agy error exit also prints "did not answer the preflight within 15 seconds" and discards agy's own text. Resolve: distinguish rc 124 from other failures, or append the last line of the output when non-empty; still one stderr line.
2. `timeout` without `-k`: the bound holds only if agy exits on SIGTERM. `timeout -k 5s 16s` closes that; the test's `< 20` becomes `< 25`.
3. Note: the preflight prompt literal is duplicated between script and stub; harmless, a mismatch fails every test loudly.
