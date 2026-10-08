# Agent roles: phase 1 spike results

Spec: `docs/superpowers/specs/2026-10-08-agent-roles-design.md`. Run in the ai-sandbox on 2026-10-08.
Only S2 and S2b have been run; S1 and S3 are not in this file yet.

## S2 (open point 3: A4, A7, A8)

### What `agy` exposes (A4)

`agy --help` lists `--output-format text|json|stream-json`, `--conversation <id>`, `--continue`
(most recent conversation), `--log-file`. With `--output-format json` one line is printed:

```
{"conversation_id":"<uuid>","status":"SUCCESS|CANCELED","response":"<text>","duration_seconds":<float>,"num_turns":<int>,
 "usage":{"input_tokens":N,"output_tokens":N,"thinking_tokens":N,"cache_read_tokens":N,"total_tokens":N}}
```

A4 is verified: final text (`response`), conversation id (`conversation_id`) and usage including cached
tokens (`cache_read_tokens`) are all present. `--log-file` and `stream-json` were not needed and not inspected.

Observations about the fields:
- `input_tokens` of a fresh call is about 25.8k although the prompt is about 150 words: agy's own system prompt
  and tool definitions are the prefix. The ">4,000 token prefix" condition is therefore met by every call. I did
  not add a larger document, because pasting one through a bare command needs quoting that the call rules forbid.
- `input_tokens` on a resumed conversation is cumulative (the whole history is resent), `num_turns` counts the turns of the conversation.
- `input_tokens` appears to include the cached part (`cache_read_tokens` <= `input_tokens` in every normal call).
- A call whose model tried to read a file (headless, permission auto-denied) returned `status: CANCELED`,
  empty `response`, and `cache_read_tokens` 73403 > `input_tokens` 36882, so the counters of a cancelled
  multi-step call are not comparable; that call is excluded from the comparison. Prompts therefore start with
  "Do not use any tools".

### Method

Model `gemini-3.8-flash-high`, `--output-format json`, one bare `agy -p "<prompt>" ...` per Bash call.
Prompt body (identical in all runs, about 150 words of context about roles, then one question):
"Do not use any tools; answer only from the text below. Context: a team routes review work to several agents. ... Question 1: ..."
Follow-ups: `agy -p "Do not use any tools; answer only from the earlier text. Question N: ..." --conversation <id> --model gemini-3.8-flash-high --output-format json`.
Calls were sequential within a conversation. Fresh-call 3 and conversation-call 3 ran in parallel.

### Raw numbers

| Run | Call | Kind | input | cache_read | output | thinking | wall s | cached/input |
|---|---|---|---|---|---|---|---|---|
| (probe) | "ok" | fresh | 25723 | 0 | 145 | 144 | 3.3 | 0 % |
| (excluded) | Q1 | fresh, CANCELED | 36882 | 73403 | 1028 | 794 | 16.7 | n/a |
| A (conv 2942c6fa) | 1 | first | 25856 | 0 | 618 | 581 | 6.7 | 0 % |
| A | 2 | conversation | 52652 | 0 | 906 | 854 | 16.3 | 0 % |
| A | 3 | conversation | 55416 | 24591 | 1199 | 1133 | 30.0 | 44.4 % |
| A | 4 | conversation | 58710 | 49211 | 1477 | 1399 | 55.5 | 83.8 % |
| fresh 1 (db096067) | 1 | fresh | 25847 | 0 | 804 | 767 | 7.5 | 0 % |
| B (conv e1b8e308) | 1 | first | 25846 | 0 | 242 | 236 | 3.8 | 0 % |
| B | 2 | conversation | 31777 | 20428 | 364 | 350 | 15.8 | 64.3 % |

Fresh calls without `--conversation` (4 of 4 in total, including the probe and run A/B first calls) reported 0 cached tokens, also for an
identical prompt repeated (run A call 1 vs fresh 1: 25856 vs 25847 input, both 0 cached). Only two genuinely
separate fresh repeats of the same prompt exist (A1/fresh 1); I did not run more.

### Decision (the rule of the spec, unchanged)

Rule: reuse is shown when the second call on the conversation reports at least 50 % of its input as cached.
- Run A, second call: 0 %. Rule not met.
- Run B, second call: 64.3 %. Rule met.
- Later calls of run A: 44 % then 84 %.

The measurement is not reproducible on the second call (1 of 2). `agy` does reuse a provider-side cache on
`--conversation` (cached tokens appear only there, never on fresh calls, and grow to 84 % by the fourth call),
but it did not do so reliably at the point the rule looks at. Two runs are too few to call the 0 % a fluke
or the 64 % luck. Strict reading of the rule: **A7 is not shown** (one failing replicate). Phase 3 must not rely on it.

Decision: **no guaranteed reuse for `agy`.** Open for the user: if he accepts "two runs, one pass" plus the rising
numbers as sufficient, A7 can be marked "partly shown, unreliable"; the design below holds either way because it
only needs the safe fallback.

### S2 re-reading of the counters (added after S2b)

Settled with a fresh `agy -p ... --output-format json` conversation (call 1 then two `--conversation` calls, same model):

| call | num_turns | input | cache_read | output | total_tokens |
|---|---|---|---|---|---|
| 1 | 1 | 25730 | 0 | 358 | 26088 |
| 2 | 2 | 31657 | 20421 | 1307 | 32964 |
| 3 | 3 | 34694 | 45060 | 2008 | 36702 |

- `total_tokens` = `input_tokens` + `output_tokens` in every row (26088, 32964, 36702), and the cached tokens are
  not in it. So `input_tokens` is the **uncached** part only; cached tokens are reported beside it, not inside it.
  S2's remark that `input_tokens` appears to include the cached part is wrong.
- All counters are **cumulative over the conversation** (`num_turns` 1, 2, 3; each row exceeds the previous one in
  every column; the stream results of S2b behave the same). Per-call values are differences of consecutive rows.
- Corrected per-call cached share = delta cache / (delta input + delta cache). From the S2 table:
  run A call 2: delta input 26796, cache 0, **0 %**; call 3: 2764 and 24591, **89.9 %**; call 4: 3294 and 24620, **88.2 %**.
  Run B call 2: 5931 and 20428, **77.5 %**. (The table above, 44.4 / 83.8 / 64.3 %, divided cumulative cache by cumulative input.)
  The new check: call 2 delta 5927 uncached, 20421 cached, 77.5 %; call 3 3037 and 24639, 89.0 %.
- Effect on the S2 decision: none for the rule. Run A call 2 still fails (0 %, a full resend of about 26.8k tokens),
  run B call 2 still passes (77.5 %); calls 3 and later reuse the cache in every run (88 to 90 %). The only reading that changes:
  the reuse is better than S2 said once it starts, and the failing case is a complete miss, not a partial one.

### codex (A8)

Documentation only. `codex exec resume --help`: "Resume a previous session by id or pick the most recent with --last";
argument `[SESSION_ID]` "Conversation/session id (UUID) or thread name"; `[PROMPT]` "Prompt to send after resuming the session".
`codex --help` and `codex exec --help` mention `resume` but no cache. No statement about provider-side cache reuse
in any of them. Per the rule, silent documentation means **no reuse** (A8 not shown). codex is not logged in, nothing was run.

### What it means for `--continue`

- Without guaranteed reuse, `--continue` sends a **fresh call with the previous report inlined**, for both agy and codex (the spec's "without it" branch).
- `agy --conversation <id>` still works functionally and the id comes back in `conversation_id`; it can be kept as an optional optimisation,
  but resending history costs the full cumulative `input_tokens` unless the cache hits (A: 52.7k input for call 2 vs 25.9k for a fresh call).
- Long-lived roles (runner "kept alive per milestone") therefore stay on Claude; on Gemini only one-shot roles (scout, writer, second reviewer).
- The wrapper's report should record `conversation_id` and `usage` (cache_read_tokens) anyway, so a later measurement can revisit A7.

### Assumption table updates

- A4: verified (fields above).
- A7: not shown (run A call 2: 0 %; run B call 2: 64.3 %); no reliance.
- A8: not shown; documentation silent.

## S2b (persistent `agy` session on stdin vs separate `--conversation` calls)

Run in the ai-sandbox on 2026-10-08, model `gemini-3.8-flash-high`, one session, 4 turns, no tools used.

### Working command lines and message shape

```
mkfifo in.fifo
setsid nohup tail -f /dev/null > in.fifo &          # holder: keeps a writer open so agy never sees EOF between turns
setsid nohup agy --input-format stream-json --output-format stream-json --model gemini-3.8-flash-high \
    < in.fifo > out.ndjson 2> err.txt &
printf '%s\n' '{"event":"user","message":{"role":"user","content":"<prompt>"}}' > in.fifo   # one turn per line
```

- `-p` is not used: with `--input-format stream-json` agy reads stdin and prompts come only from the messages.
  `--output-format stream-json` is mandatory.
- Message shape, found by trial (the error texts name the fields): top-level `"event"` is required
  (`stream input message is missing the "event" field`); the value must be `"user"` (`user_message`, `message`,
  `input`, `prompt`, `chat`, `send` give `warning: ignoring unsupported stream input message event` and the line is
  dropped silently, the process keeps waiting); `"message"` must be an object (a string gives a Go decode error,
  `streamInputUserMessage`); `{"role":"user","content":"<text>"}` works. A `{"type":"user",...}` message without `event` fails.
  I did not find out whether `message.content` also accepts an array of parts.
- Output is NDJSON, one object per line, each with `"event"`: `init` (conversation id, tool list, `permission_mode`),
  `step_update` (per step: `step_type` `user_input`, `agent_response` with `usage` and `text_delta`, `tool` with `tool_name`),
  and one `result` per turn with the same fields as `--output-format json` plus `"event":"result"` wrapping.
- The conversation id is the same in all 4 results (`f8017169-...`), so one process is one conversation.
- `result.usage`, `result.duration_seconds` and `result.num_turns` are **cumulative over the session**, not per turn
  (result 2 duration 89.5 s while the turn took 70 s wall). Per-turn numbers come from the `agent_response` step's
  own `usage` (one step per turn here, because no tool was used), or by subtracting consecutive results.
- In this stream `input_tokens` of a step is the **uncached** part; `cache_read_tokens` is reported beside it, not inside it.
  S2's note that `input_tokens` includes the cached part does not hold for this stream: cached share below is
  `cache_read / (input + cache_read)`. The single-shot `json` output may count differently, so the two tables are not
  strictly comparable.
- Without a "Do not use any tools" prefix a bare "Say ok." made the model open a skill file with `view_file`
  (headless, the turn took 11 s and 3 steps): keep the prefix.

### Per-turn table (from the `agent_response` step usage)

| Turn | wall s (write to result) | input (uncached) | cache_read | output | thinking | cached share |
|---|---|---|---|---|---|---|
| 1 | not timed (agy `duration_seconds` 14.1) | 25827 | 0 | 1410 | 1333 | 0 % |
| 2 | 70.5 | 2885 | 24659 | 8203 | 8112 | 89.5 % |
| 3 | 11.7 | 11788 | 25894 | 1121 | 1051 | 68.7 % |
| 4 | 14.5 | 4459 | 34605 | 1534 | 1442 | 88.6 % |

Turn 1 wall time was lost to a bug in my timing script (`bc` missing in the sandbox); 14.1 s is agy's own figure for that turn. Turn 2 spent 8112 thinking tokens (a variance of the
model, not of the transport); its wall time is not a latency signal.

Comparison with the S2 `--conversation` table (same model, similar prompts):

| | S2 run A | S2 run B | S2b (persistent) |
|---|---|---|---|
| turn 2 cached | 0 % | 64.3 % | 89.5 % |
| turn 3 cached | 44.4 % | - | 68.7 % |
| turn 4 cached | 83.8 % | - | 88.6 % |
| turn 2 input sent | 52652 | 31777 | 28744 (2885 + 24659) |
| wall turn 2 / 3 / 4 | 16.3 / 30.0 / 55.5 s | 15.8 s | 70.5 / 11.7 / 14.5 s |

### Decision

- Rule of S2 (turn 2 at least 50 % cached): **met, 89.5 %**. One replicate only; the persistent session shows reuse on
  every turn after the first (69 to 90 %), but I ran one session, so it is "one run, one pass", not reproduced.
  S2's rule counted `cached/input` with `input` assumed to include the cached part; under the literal `cached/input`
  of this stream turn 2 is 855 %, which is above 50 % either way.
- Latency: no clear win. Turns 3 and 4 took 11.7 s and 14.5 s against 30 s and 55 s for run A, but run A's growth
  came mostly from thinking tokens (1133, 1399) and turn 2 of the persistent run took 70 s for 8112 thinking tokens. The
  transport saves process start (a one-shot call was 3.3 s for "ok" in S2, mostly startup) and nothing else I could
  isolate. Thinking-token variance dominates, so 4 turns cannot separate the two.
- Cache reuse is at least as good as with `--conversation` (89.5 / 68.7 / 88.6 against 0 or 64 / 44 / 84), and
  `input_tokens` per turn is not cumulative, so cost per turn is the delta only.

### What it means for roles

- A persistent writer session works technically and gets cache reuse from turn 2 on in the one run made. It removes the
  sensitivity of `--conversation` to whether the cache hits on resume, because the process keeps the history in memory.
- It does not remove the need for the fallback: the process dies with the sandbox, a crash or `--print-timeout`
  (default 5 minutes; I did not test whether it applies per turn or per idle gap), and the wrapper would have to
  re-inline the report after a death. For one-shot roles (scout, second reviewer) it brings nothing.
- Recommendation: keep one-shot calls as the default (A7 stays "not reliably shown" for `--conversation`; S2b shows reuse only
  for the persistent process). Use a persistent session only for a role with 3 or more dependent turns inside one milestone,
  and only behind a wrapper that owns the lifecycle below. This is a judgement from one run.

### Plumbing problems

- **EOF and the holder.** agy exits when stdin reaches EOF (it left within 2 s after the holder was killed, and it had
  printed all results). A fifo opened by a short `echo > fifo` per message would close the writer and end the session
  after the first message; a background holder with a writer open (`tail -f /dev/null > in.fifo`) is required. A shell
  `exec 3>in.fifo` held by a long-lived parent works the same.
- **Pid files.** `setsid nohup cmd &` in a Bash tool call recorded the pid of a wrapper, not of the process;
  `kill $(cat holder.pid)` hit "No such process" and agy stayed alive. The real pids came from `pgrep -a`.
  Cleanup that relies on `$!` is not reliable; use `pgrep -f` with the exact command line or run the pair under one process group.
- **Fifo open order.** The holder (writer) blocks on open until a reader appears; starting the holder first and agy after
  a short sleep worked. The reverse order was not tried (a FIFO open for reading normally blocks until a writer exists). Both must be started from the
  background, not the foreground, or the tool call hangs.
- **Silent drops.** An unsupported `event` value only prints a warning to stderr (here to the terminal); the wrapper
  gets no result and waits forever. A wrapper must read stderr and apply its own timeout per turn.
- **Buffering.** None seen: `out.ndjson` was written line by line and the result line appeared as soon as the turn ended
  (polling every 0.25 s). The fifo had no buffering problem with lines of about 500 bytes; longer messages were not tried
  (a message above the pipe atomic size 4096 bytes could interleave if two writers existed; there is only one).
- **Cumulative counters.** See above; a wrapper must subtract or read step usage.
- **Hangs.** None occurred. Not tested: a tool permission request in headless stream mode (`permission_mode` is
  `request-review`), a model that never answers, `--print-timeout` per turn.
- **Cleanup check.** At the end `pgrep -a agy` printed nothing. The `tail -f /dev/null` with pid 7 is the container
  entrypoint, not mine.

## S2b repeats

Two more persistent sessions (`r1`, `r2`), same command as S2b, driven by a python3 script (stdin pipe held by the
parent, per-turn timer, so no fifo or holder process). Turn 1 carries `2026-10-08-agent-roles-brief.md` (about 8 KB,
no secrets) after "Do not use any tools; answer only from the text below."; turns 2 to 4 are short questions
("answer only from the earlier text ... in two sentences"). Numbers are per turn (step usage), shares are
cache / (input + cache), input is uncached.

| Run | Turn | wall s | input (uncached) | cache_read | thinking | output | cached share |
|---|---|---|---|---|---|---|---|
| r1 | 1 | 10.4 | 27864 | 0 | 424 | 492 | 0 % |
| r1 | 2 | 15.7 | 3973 | 24508 | 1680 | 1750 | 86.1 % |
| r1 | 3 | 8.6 | 5878 | 24759 | 723 | 832 | 80.8 % |
| r1 | 4 | 19.1 | 2702 | 28981 | 2151 | 2265 | 91.5 % |
| r2 | 1 | 10.8 | 27869 | 0 | 404 | 479 | 0 % |
| r2 | 2 | 11.7 | 3966 | 24508 | 1040 | 1119 | 86.1 % |
| r2 | 3 | 7.8 | 5203 | 24610 | 773 | 870 | 82.5 % |
| r2 | 4 | 12.1 | 2082 | 28802 | 1403 | 1500 | 93.3 % |

- Reuse: 3 of 3 persistent sessions (S2b, r1, r2) show 86 to 90 % cached on turn 2 and 69 to 93 % on later turns.
  The cached part is about 24.5k tokens every time: agy's own system prompt and tool definitions. The brief
  (about 2k tokens, in turn 1's 27.9k uncached input) was not part of the cached amount seen on turn 2, so the
  cache covers the fixed prefix; whether the brief itself is cached cannot be read from these numbers
  (turn 2 uncached input of 4k includes the new question, the model's turn 1 answer and likely the brief, so
  it probably is not). I did not test a larger prefix than the brief.
- Latency: turns 2 to 4 took 8 to 19 s, mean 12.5 s; turn 1 about 10.5 s. Output plus thinking tokens decide the
  time (turn 4 of r1: 2151 thinking tokens, 19 s; turn 3 of r2: 773, 7.8 s).
- Lifecycle with a parent-held pipe: closing stdin made agy exit with code 0 within the 10 s wait in both runs;
  `pgrep -a agy` was empty afterwards. No hangs.

## Conclusions (S2 and S2b)

- **Counters.** In every `agy` output `input_tokens` is the uncached part, `cache_read_tokens` is separate,
  `total_tokens` = input + output, and all counters are cumulative over the conversation or session. Per-turn values
  need differences (json output) or the step usage (stream-json).
- **Reuse.** `--conversation` reused the cache on 5 of 6 second-or-later calls measured (S2 runs A and B plus the new check;
  S2 run A call 2 was the one complete miss; run B call 2 77.5 %; later calls 88 to 90 %). A persistent stream-json process
  showed 86 to 90 % on turn 2 in 3 of 3 sessions. The persistent process is more reliable in this small sample (3 of 3
  against 1 of 2 at the decision point), but the sample is small and the cache covers mainly agy's fixed prefix.
- **Latency.** No difference that the data can separate. Thinking tokens dominate turn time in both modes; the persistent
  process saves startup only (about 2 to 3 s per call).
- **What a persistent-session wrapper needs.** A per-turn timeout of its own (an unsupported event is dropped with a
  stderr warning and no result is produced; `--print-timeout` per turn is untested); subtraction of the cumulative
  counters or use of the step usage; a process lifecycle that owns stdin (a parent holding the pipe; closing it ends agy
  with exit 0; a holder process under `setsid` needs its real pid from `pgrep`, not `$!`); stderr capture; and a fallback
  that re-inlines the previous report when the process is gone (sandbox end, crash, timeout).
- **Recommendation and decision.** Keep one-shot `agy -p` calls with the previous report inlined for `--continue`
  (A7 stays "not reliably shown" for `--conversation`). The user decided on 2026-10-08: **one-shot calls for now;
  a persistent session mode is planned but deferred, not implemented.** The numbers above are the input for that later
  work; the recorded `conversation_id` and `usage` of each wrapper report keep the measurement open.
