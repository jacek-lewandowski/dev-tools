# Arek, reviewer 2 — small-class diff review of b949751 "feat(ai-sandbox): host audio on by default"
(saved by the lead from the hand-back, 2026-10-31)

Verdict: not blocking. No Critical or Important findings.

Checked: conflict/"seen" logic untouched (lines 254–282); no stored value + no socket → rc 0, one warning, no mounts, .env records SANDBOX_WITH_AUDIO=1 (run through the harness); the .env writer (line 2113) derives from WITH_AUDIO, so a later --no-audio logs and stores 0 and the next flagless run logs "keeping host audio off"; mounts identical apart from strings (PULSE_SERVER, socket volume, /dev/snd and `c 116:*`); the test's fake socket is scoped to the suite's mktemp dir; the two pre-existing failures re-run identically and the commit touches neither; repo-wide grep finds no other statement of the default; red run 17/4 for the right reasons, green 17/0; full suite 1031/3 read as recorded.

Lesser:
1. Existing projects stay off: the old script wrote SANDBOX_WITH_AUDIO=0 on every run, so every sandbox created before this commit keeps audio off; "on by default" reaches new projects, or existing ones after one explicit --audio. The user should know.
2. Log wording at line 739 attributes "not shared" to --no-audio even when the cause is a stored 0; the stored-0 line above makes it recoverable. Cosmetic.
3. A host with no PulseAudio socket warns on every start until --no-audio is passed; by design.
