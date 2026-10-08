# Review of spec revision 5 (typed-requests redesign), round 1

Date: 2026-10-08. Verdict: **blocked** (3 important, none critical). The typed-request menu held:
no path, type or revision value read content outside HEAD's tree, read a secret-pattern file or
injected an option (checked with git 2.34 in a throwaway repo, removed).

## Important (blocking)

1. **C5 "Open questions" contradicts D19/I5 and changes global §2 undeclared.** C5: "The lead
   answers a report's `open_questions` and its `other` requests." D19/I5: `other` goes to the user,
   the lead runs and reads nothing. Failure: a report asks under `other` or `open_questions` "what
   does `git log -p -- old/creds.yaml` show?"; C5 tells the lead to answer it, i.e. run a command or
   read code for the agent (root cause of review 3 #1 / review 4 A, now held only by prose; breaks
   §2). Resolution: `other` goes to the user verbatim and the lead writes the user's reply into
   `--answers`; the lead answers `open_questions` only from the brief, the spec/plan and the user's
   decisions, never by running a command or reading project files; a question needing a project
   fact is answered "use a menu request" or goes to the user.
2. **I5 now forbids what D14 and C3 require.** Revision 5: "no one runs a command string supplied
   by a brief or an agent"; D14/C3 still have the lead or the native writer run the brief's
   `check:` and `extract:`. Resolution: "the wrapper never runs a command named in a brief; no one
   runs a command string supplied by an agent."
3. **I6 and A20 claim more than measured.** S3b checked reads outside the worktree only with
   `view_file` and `list_dir`; its table marks `grep_search` and `find_by_name` outside the granted
   directory "not tried", and `find_by_name` worked from the project root while `view_file` was
   denied there. Failure: `grep_search` over `<top>` returns an untracked `.env`. Resolution: restate
   A20/I6 as "verified for view_file and list_dir"; add an S4 check (`grep_search` for a main-tree
   canary, `find_by_name` over `<top>` and `$HOME`, from the worktree setup); if either reaches
   outside, external routes resolve to `not-confined`; add the case to phase 3's assumptions.

## Lesser

- C5 git commands: `log` runs `gpg.program` when `log.showSignature=true` and a signed commit
  touches the path (tested; `--no-show-signature` stops it). Partial clones could lazily fetch
  (untested; `GIT_NO_LAZY_FETCH=1`).
- Path check vs pathspec: `log` honours `:`-magic and globs after `--`; if the tracked check uses
  `git ls-files -- <path>`, `:(top).env` passes the basename check and `log` lists commits touching
  `.env` (subjects only). Fix: `--literal-pathspecs` / `GIT_LITERAL_PATHSPECS=1` on the check and
  every command; reject absolute paths, `..` and a leading `:`; pass git exactly the checked path;
  `file` requires `HEAD:<path>` to be a blob (a tree would list stripped secret names).
- C6 steps 1-2: `git diff --binary --no-ext-diff --no-textconv HEAD` still runs `core.fsmonitor`
  and clean filters (tested); with `diff.noprefix=true` `git apply` patches the wrong path (tested).
  Fix: `-c core.fsmonitor=false`, clean filters off, `git diff-index --binary -p
  --src-prefix=a/ --dst-prefix=b/`; `fsmonitor=false` also on `git worktree add`.
- Phase 1 outcomes: "All three external roles qualify (C6)" contradicts D21.
- C6 order step 2: `/config` waiting on OAuth when signed out is inferred, not measured.
- Phase 2 contract: the "lists typed requests when it cannot run commands" line makes the native
  scout (no shell) emit requests, against C4 (native always `[]`); scope it to worktree runs.
- No caps: number of requests per report, size of a `file` result (large/binary blobs), retries of
  a refused blocking request through `--continue`.
- C6 step list does not place writing request results, the `--answers` copy and the inputs spill
  relative to step 3.
- Phase 3 tests miss `:`-magic and `..` paths, a directory given to `file`, and fsmonitor/gpg/clean
  filter stubs.

## Remaining user choices

1. Whether agy may emit `open_questions` asking for project facts, or every such question must go
   through the menu or to the user.
2. D23, MCP exposure.
3. Tracked secrets under names matching no pattern (D20 alternative).
4. Harden against the user's own git config (gpg, lazy fetch, filters) now, or accept.
