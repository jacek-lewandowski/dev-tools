# Review: no process narration (2026-11-09)

Reviewer: Fiona, reviewer 1. Object: small diff, `git -C ~/knowledge show 8713b48`
(rules/global.md, decisions.md). Evidence:
docs/superpowers/evidence/2026-11-09-no-process-narration.md.

Verdict: blocking, one Important finding. The narration bullet does what the
user's quoted request asks; the new notification sub-bullet contradicts the
sub-bullet before it and the lead row of the table.

## Important

1. rules/global.md, context lifecycle, the new "Where the environment can push
   a notification" sub-bullet, against the "A long wait is ..." sub-bullet
   (lines 202-207) and the Lead row of the table (line 244).
   - The existing sub-bullet defines "the end of a work block" and "a question
     to the user" as long waits by definition, and says a lead past the prepare
     threshold acts before one, on the warm cache, without asking. The new
     sub-bullet makes the same moment conditional on the user's answer to a
     question, which is itself a long wait under the first sub-bullet.
   - Failure scenario: a lead at 300k ends a work block where push exists. The
     first sub-bullet says write the handover now; the second says send the
     question and write it only on "yes". If the user answers "yes" after 70
     minutes, the handover is written on a cold cache, the case the first
     sub-bullet exists to prevent. A lead reading both cannot tell which wins.
   - The new sub-bullet has no threshold: read literally, a lead at 80k that
     gets "yes" writes a handover, which the table (handover from 250k) does not
     ask for. It also says nothing about subagents, which the first sub-bullet
     retires before a long wait. Does "no" keep them?
   - Resolve: state the precedence in one place. For example, scope the new
     sub-bullet to a lead past the prepare threshold. Make it the exception to
     the first sub-bullet ("where the environment can push a notification, the
     end of a work block is a long wait only when the user answers yes to ...").
     Exempt this one question from "a question to the user" in the definition.
     Say whether "no" also keeps the continued subagents. If the user wants the
     handover to stay unconditional past 250k and the question only to decide
     for leads below it, say that instead. Either way the two sub-bullets and
     the table must give one action.

## Minor (not blocking)

2. rules/global.md, "never the process" bullet. "Tells the user nothing about
   the internal process ..., at most one line that work is in progress" is
   scoped only by "about the internal process". The lead must still interrupt
   mid-work with 🔴 confirmations (persona bullet line 185), relayed agent
   questions (lines 273-275), a class change needing approval, and the
   per-milestone request to run what the sandbox cannot (line 458). A strict
   reader may hold these until the final report. Resolve: add "questions and
   confirmations the rules route to the user excepted".
3. Same bullet against line 481 ("lesser findings are fixed, or reported to the
   user") and line 233 (still-blocking handover findings are named to the user).
   "A review finding appears only when the user must decide it" leaves unclear
   where an unfixed lesser finding goes. Resolve: say unfixed findings go under
   "what the user should check or watch".
4. Two lists of the final report's content now coexist. The persona bullet
   (lines 187-189) has "what changed, what was verified and what is open". The
   new bullet has "end state, what to check or watch, questions the user could
   ask". The new list drops "what was verified / not verified", which line 184
   and §4 ("Done" only with output at hand) still require. Resolve: name one
   list, or have the new one include what was and was not verified.
5. The new sub-bullet's "The lead cannot know" is rationale in global.md; it
   already sits in decisions.md. Delete it. The closed question should also
   name the duration ("more than an hour?"): the user does not know the cache
   lifetime, and the bullet above says to assume an hour.
6. Traceability: the evidence file and the decisions.md entry quote only the
   narration request. The user's request for the end-of-block notification is
   not quoted anywhere in the files, so its wording cannot be checked against
   the source. Resolve: quote it in the evidence file.

## Checks run

- `git -C ~/knowledge show 8713b48`; read rules/global.md lines 60-250 and
  476-484.
- `grep -niE 'to the user|the user|relay|notif|long wait|work block|report'
  roles/*.md`: no role narrates process to the user. Roles route questions to
  the user (implementer.md:28, :55; planner.md:185, :223), which is finding 2,
  not a contradiction in the roles. The evidence's narrower grep reaches the
  same conclusion.
- Tool neutrality: no tool or harness name was added ("push a notification" is
  generic; `/clear` was there before).

## Round 2

Delta: `git -C ~/knowledge show 6538cce`, and the "Fix round" section of the
evidence file.

Verdict: closed. No Critical or Important finding.

- Important 1 is resolved. Past the prepare threshold the new sub-bullet keeps
  the first sub-bullet and the table's Lead row as they were: handover before
  the wait, and the notification only reports that it is ready. Below the
  threshold, the first sub-bullet obliges no handover, so a handover on "yes"
  conflicts with neither it nor the table. The table only states what is due
  past 250k. The question is now exempted from "a question to the user" in
  so many words.
  - On "no", the subagents stay. This is consistent: a long wait is defined as
    a pause expected to outlast the cache lifetime, and "no" makes the pause
    short.
  - On "yes", the subagents are retired as for a long wait.
  - Where no push exists, the end of a block stays a long wait by definition,
    as before.
- The minor fixes add no new conflict.
  - The exception for routed questions and confirmations covers lines 185,
    273-275 and 458.
  - "Unfixed findings" in the final report agrees with line 481 ("reported to
    the user") and with the handover findings named at line 233.
  - The final report has one content list, which includes "what was verified
    and what was not" (line 184, §4). The persona bullet now points to that
    list instead of keeping a second one.
  - The rationale sentence is gone.
- The user's notification request is now quoted in the evidence. The rule's
  wording (closed question, handover advisable) matches it.
