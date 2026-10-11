# Review of spec revision 7 (phase 3 results, D21/D24 rewrite), round 1

Date: 2026-10-11. Verdict: **blocked** (3 important). The user's four decisions are reflected
correctly; nothing beyond them is decided silently; no global rule changes.

## Important

1. **read_url(*) applies to every run, but its local reach was never measured** (I6, A23 row,
   D21). The spikes tested read_url(*) only against https://example.com. Untested: `file://`
   paths (`file:///home/...`, `file://<top>/...`) and local services (`localhost`,
   `host.docker.internal`). I6 says "Content reads outside the worktree are denied" and A23 is
   "verified for content" from grep_search, view_file and list_dir only. Scenario: an injected page
   has a writer run fetch `file:///home/.../.env` and post it out; D20 accepts sending project files
   to a URL, not reading local files outside the worktree. Resolution: restate A23 as verified for
   view_file, list_dir and grep_search only; add a guessed assumption "read_url_content reaches no
   file:// path or local host" with a check before phase 4 is planned, or the user accepts it.
2. **The rest of ~/.gemini/antigravity-cli is unmeasured** (D24, I6 residuals). S4 put a canary
   only in scratch/; never probed the root, conversations/, log/ or settings.json (the token was
   deliberately never opened). scratch/ was readable without --add-dir, so agy may grant its whole
   app-data directory. Scenario: with fetch on every run, a run reads agy's OAuth token or other
   runs' conversation records and sends them to a URL. Resolution: a guessed assumption with a
   canary check that never opens the token (canaries in the root of antigravity-cli/ and in
   conversations/), or the user's acceptance.
3. **The host route is undecided** (D3, C6, phase 4 docs). C6 makes every route not-confined when
   read_url(*) is missing; the entrypoint merge exists only in the sandbox; D3's host opt-in lists
   the allow file, Bash(ai-delegate *) and the auto-mode sentence but not this rule. Resolution:
   state the host behaviour in D3 (the host user adds read_url(*) to the host's agy settings, or
   external routes always fall back on the host).

## Minor

- A21 row: restore "no effect under this layout" / "not refuted: only the HOME layout mirrors the
  real path" for XDG_CONFIG_HOME and ANTIGRAVITY_EXECUTABLE_DATA_DIR.
- Stale statements: I6 "Denied: ... reads outside the worktree and /tmp"; I6 "Content reads outside
  the worktree are denied" (scratch/ and the per-run TMPDIR are readable); A6 row "/tmp stay
  reachable"; C3's /tmp refusal cites S3 alone. Qualify each with the residuals and TMPDIR.
- Per-run TMPDIR: say whether the CANCELED retry gets a fresh TMPDIR; "also on failure" should say
  "every exit, including timeout and signals"; S4 never tested, with TMPDIR set, whether a run can
  reach the parent .ai-delegate/ or a sibling tmp-<id>/wt-<id> (record as an assumption); C3 has no
  refusal for brief/input/report/answers paths under .ai-delegate/tmp-*; the phase 4 test bullet
  omits "answers".
- Entrypoint merge target: state it is only the sandbox's own seeded copy
  (`${SANDBOX_DIR}/.gemini`, bind-mounted at create-ai-sandbox.sh:2110; entrypoint runs as the
  container user, line 1941), never the host's ~/.gemini; keep mode 600 and the owner.
- Fetch now reaches the writer and second reviewer, but I10 mentions fetch only for the scout;
  D16's reasoning (no inline inputs because of fetch) now applies to the writer, which gets inputs
  inline (possibly untracked files); only roles/scout.md has "do not send their content to any
  URL" (writer.md and second-reviewer.md do not). Say whether those role bodies change (an I11
  approval) or deliberately stay.
