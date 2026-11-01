# Task statement: two rules for the knowledge repository

Stated by Stefan (lead), 2026-11-01. Class: **brief** (text changes in
`~/knowledge/rules/global.md`, `~/knowledge/roles/*.md` and
`~/knowledge/decisions.md`; this sandbox is the integrator and commits on
`main`; the host pushes on sync). The planner writes the brief with the exact
paragraphs as its contract; a reviewer checks it; the user approves the
wording; one implementer lands it.

## Rule 1: the lead checks its own question first

The user: "add a rule so that Stefan tries to answer the question himself,
especially when the answer is rather obvious." Context: many questions the
leads asked the user were not decisions: a premise that cannot hold under the
project's data, rules or contracts, or an answer the spec or the rules already
settle. The rule, for the lead (and any agent that would ask the user):
before asking, state the question with its candidate answers; check whether
the premise can occur at all; check whether the spec, the plan, the rules or
the data already settle it; if one candidate is clearly right, take it, record
the assumption in the report, and do not ask. Ask only a genuine decision, with
the candidates and a recommendation. Where it goes: `rules/global.md` "Ask vs.
assume" bullet (extend it, do not add a second bullet), plus a `decisions.md`
entry with the rationale.

## Rule 2: context lifecycle per role, with the cache in mind

The user wants the existing "Cache pays off within a loop" and "300k
context" rules completed into one table: per role, what happens when context
grows, who triggers it, and when. Inputs for the planner:

- Facts (code.claude.com, 2026-11-01): subagents auto-compact on their own
  window (`autoCompactWindow` per role file, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`);
  the parent sees only a token count at each stop; a subagent is resumable by
  name in its session and after `--resume` of that session, not after
  `/clear` (new session); compaction keeps requests and key snippets, may lose
  early instructions, re-reads up to five recent files, leaves background
  subagents running; idle compaction exists (default on, after about an hour
  idle, from 200k tokens, `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS`); the subagent
  prompt cache lives one hour here (CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=1h).
- Analysis the lead gave the user (to turn into the table): spec author,
  phase planner, reviewer, runner, scout, writer: state lives in files, so
  replace with a fresh agent in the same slot, no handover, no compaction
  needed; implementer: compaction mid-task (keeps the handle and recent
  files), replacement at a task boundary when over the threshold, with a
  short note into the evidence directory first; lead: handover file and
  /clear at phase boundaries, and before /clear the lead asks live
  implementers for their notes, since they are unreachable afterwards; the
  lead's handover lists the live agents.
- The user's addition: the trigger is not only the fill level but the
  expected idle time. If an agent (the lead included) is about to be idle for
  longer than the cache lifetime (a question to the user, the end of a work
  block, the end of a task), the handover or compaction happens now, on the
  warm cache, not after the return, when the whole context would be re-read
  at full price only to be summarised. So: at the end of a turn that expects
  a long wait, an agent above the threshold writes its handover (lead) or is
  compacted/retired (subagent) before the wait; a continued subagent whose
  next use is more than the cache lifetime away is retired at the end of its
  task, not kept.
- Thresholds: 300k ceiling exists; the planner proposes the lower "prepare"
  threshold (the user's default 70 % of the window from the supervisor
  discussion) and states it once.

Where it goes: one table in `rules/global.md` replacing or extending the
"Cache pays off" and "Agent lifetimes" bullets' threshold sentences (no
duplicate sentence may remain: the planner lists the sentences it replaces),
matching lines in `roles/planner.md`, `roles/implementer.md`,
`roles/runner.md` where they state lifetimes, and a `decisions.md` entry. The
user's style: operative sentences in global.md, rationale in decisions.md,
bullets over dense paragraphs (memory: rule-writing-style).

## Deliverable

`docs/superpowers/specs/2026-11-01-context-lifecycle-rules-brief.md` in the
house brief shape: goal, the exact new text as the contract (every
paragraph/table as it will land), the sentences removed, obligations (the
diff shows only those changes; `grep` residues for the removed sentences; the
rendered CLAUDE.md note that the host must sync), evidence file path
`docs/superpowers/evidence/2026-11-01-context-lifecycle-rules.md`, under 200
lines.
