# Evidence: no process narration (2026-11-09)

global.md word count: before 5612, after 5717 (delta +105).

Roles check: grep -rniE 'relay|tell the user|report to the user|goes to the user' roles/ returned only planner.md:86 (a spec change goes to the user first), no contradiction. Reviewer and second-reviewer roles only say findings stay in the report.

## git -C ~/knowledge diff
```diff
diff --git a/decisions.md b/decisions.md
index a5d8df1..f262c9a 100644
--- a/decisions.md
+++ b/decisions.md
@@ -14,6 +14,16 @@ Format:
 
 ## Entries
 
+- 2026-11-09 no-process-narration integrated
+  rules/global.md: the user said, "Do not tell me what the reviewer found or
+  who is fixing what now; that is your internal process, I have no influence on
+  it and it is noise. I only want the end state: a short summary, what I should
+  pay attention to, and suggestions of what I could ask about." The reviewed
+  versions bullet now covers all work, not only plans. The end-of-block
+  notification sits in the context lifecycle bullet because its answer is what
+  decides the handover there; the lead cannot otherwise know whether a break
+  will outlast the cache lifetime.
+
 - 2026-11-03 rules-reverse-review-fixes integrated
   rules/global.md, roles/implementer.md, roles/planner.md, roles/reviewer.md:
   fixes of the reverse review of 2026-11-03. The question filter no longer
diff --git a/rules/global.md b/rules/global.md
index 4ed5e87..13ef6e0 100644
--- a/rules/global.md
+++ b/rules/global.md
@@ -97,12 +97,16 @@ Host rules apply everywhere, including inside an ai-sandbox container
   names who runs the gate and reads the verdict, and writes the report. It
   reads reports, not code. The topology is flat: the lead spawns every agent
   and continues it by name; agents do not spawn agents.
-- **The user sees only reviewed versions.** A plan, brief or spec change
-  reaches the user after its review and fix rounds are finished; until then the
-  user hears at most that planning is in progress. They get one final version
-  carrying only the decisions still theirs to make, including any review finding
-  they must decide; findings already fixed are not relayed, and every later
-  reference points to that version.
+- **The user sees only reviewed versions, and never the process.** Between the
+  request and the result the lead tells the user nothing about the internal
+  process (review findings, rounds, which agent fixes what), at most one line
+  that work is in progress. The final report gives the end state in a few
+  sentences, what the user should check or watch, and questions the user could
+  ask. A plan, brief or spec change reaches the user after its review and fix
+  rounds are finished, as one final version carrying only the decisions still
+  theirs to make; a review finding appears only when the user must decide it,
+  findings already fixed are not relayed, and every later reference points to
+  that version.
 - **A second reviewer is optional.** An environment may offer a reviewer from
   another vendor. Use it only on the spec or the plan of design work or of a
   contract change, in parallel with the reviewer; a diff goes to it only on
@@ -201,6 +205,11 @@ Host rules apply everywhere, including inside an ai-sandbox container
     long wait acts now, on the warm cache, not after the return: the lead
     writes its handover, a subagent is retired. A continued subagent whose
     next use is a long wait away is retired at the end of its task, not kept.
+  - Where the environment can push a notification to the user, the lead ends
+    a work block with one carrying what finished and a closed question: will
+    the break last longer than the cache lifetime? The lead cannot know, and
+    the answer decides the handover: yes, it writes the handover now; no, it
+    waits.
   - The lead's `/clear` makes every subagent unreachable, so before it the
     lead asks each live implementer with an open task for its note and lists
     the live agents, their open units and their note paths in the handover.
```
