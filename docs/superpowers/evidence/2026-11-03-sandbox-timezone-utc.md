# Sandbox timezone: UTC by name showed the host zone (small fix)

## Bug
`create-ai-sandbox.sh` bind-mounted the host's zoneinfo file at `/etc/localtime:ro`.
The image's `/etc/localtime` is a symlink to `/usr/share/zoneinfo/Etc/UTC`; Docker followed it
and mounted Europe/Warsaw over `Etc/UTC`. `TZ=UTC date` and `TZ=Etc/UTC date` printed CET;
`/etc/timezone` said Etc/UTC while TZ was Europe/Warsaw.

## Red test
`bash tests/ai-sandbox/test-resources.sh` on the old script (new tests, old code):
```
not ok 33 - no volume targets /etc/localtime or zoneinfo
not ok 36 - the log names the zone and the file
not ok 43 - entrypoint links /etc/localtime to the zone
not ok 44 - entrypoint writes the zone to /etc/timezone
not ok 46 - an unknown zone keeps the previous link
not ok 47 - and the entrypoint warns about it
63 run, 6 failed
```

## Fix
- `bin/ai/create-ai-sandbox.sh`: the `/etc/localtime` volume is gone; log line, `TZ_SUMMARY` and comment updated.
  `TZ=<host zone>` and its detection order are unchanged.
- Entrypoint: new Timezone section. It runs as the unprivileged user, so it tries the plain write,
  then `sudo -n` (passwordless in the image). It links `/etc/localtime` to `/usr/share/zoneinfo/$TZ`
  and writes `$TZ` to `/etc/timezone`. If the zone file is missing it warns and leaves the image default.
  `SANDBOX_ETC_DIR` / `SANDBOX_ZONEINFO_DIR` override the paths (tests only).
- `tests/ai-sandbox/test-plugins.sh` points those overrides at a temp dir so its entrypoint runs never touch the real `/etc`.

## Green
- `bash tests/ai-sandbox/test-resources.sh`: `63 run, 0 failed`
- `bash tests/ai-sandbox/test-plugins.sh`: `33 run, 0 failed`
- `bash -n bin/ai/create-ai-sandbox.sh`: clean (shellcheck is not installed here).
- `bash tests/ai-sandbox/run-tests.sh`: every suite 0 failed except test-sdkman, `79 run, 1 failed`:
  `not ok 42 - a candidate without a default is skipped`, the known failure that occurs only inside a sandbox (unrelated).

## Not verified
Docker cannot be run here; the real container behaviour (sudo in the entrypoint, the symlink in the running container) is untested.

## Host verification
Re-run `bin/ai/create-ai-sandbox.sh` for one project (the entrypoint is part of the image build context, so it rebuilds), then inside the sandbox:
```
TZ=UTC date        # UTC time, "UTC" suffix
date               # host local time, host zone abbreviation
readlink /etc/localtime    # /usr/share/zoneinfo/<host zone, e.g. Europe/Warsaw>
cat /etc/timezone          # <host zone>
grep zoneinfo /proc/self/mountinfo   # no output
md5sum /usr/share/zoneinfo/Etc/UTC /usr/share/zoneinfo/Europe/Warsaw   # different hashes
```

## Follow-up (review minors)
- TZ_SUMMARY reworded to what is requested: the entrypoint links /etc/localtime and writes /etc/timezone at start, warning in docker logs if it cannot.
- New case 6 in `tests/ai-sandbox/test-resources.sh`: read-only fake /etc plus a stub `sudo` (requires `-n`, opens the dir for the command it runs); asserts the symlink target and /etc/timezone content.
- Mutation checks, `bash tests/ai-sandbox/test-resources.sh`:
  - `sudo -n ln` changed to `sudo ln`: `not ok 48`, `not ok 49`, `65 run, 2 failed`.
  - `sudo -n tee` replaced by `cat >/dev/null`: `not ok 49`, `65 run, 1 failed`.
  - Both restored.
- Final, after the last edit: `test-resources.sh` `65 run, 0 failed`; `test-plugins.sh` `33 run, 0 failed`.

## Host verification result (2026-11-03, sandbox rebuilt by the user at be70fa4)
Run inside the rebuilt dev-tools sandbox by the lead:
```
$ echo $TZ                      -> Europe/Warsaw
$ TZ=UTC date                   -> Tue Nov  3 21:12:35 UTC 2026
$ TZ=Etc/UTC date               -> Tue Nov  3 21:12:35 UTC 2026
$ date                          -> Tue Nov  3 22:12:35 CET 2026
$ date -u                       -> Tue Nov  3 21:12:35 UTC 2026
$ readlink /etc/localtime       -> /usr/share/zoneinfo/Europe/Warsaw
$ cat /etc/timezone             -> Europe/Warsaw
$ grep -E "zoneinfo|localtime" /proc/self/mountinfo   -> (no output)
$ md5sum /usr/share/zoneinfo/Etc/UTC /usr/share/zoneinfo/Europe/Warsaw
38bb24ba4d742dd6f50c1cba29cd966a  /usr/share/zoneinfo/Etc/UTC
499916a22979b1cffade2ca408c318c7  /usr/share/zoneinfo/Europe/Warsaw
```
Before the fix the same sandbox showed Etc/UTC == Europe/Warsaw (499916a2...) and `TZ=UTC date` printing CET. All six expected results hold; the sudo fallback ran in a real container.
