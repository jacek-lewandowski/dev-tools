# Google Chat channel spike (user-run, 2026-11-01)

Class: brief, no code lands. The user runs it on the host and in one sandbox and pastes the
blocks of "What to paste back". It serves R1 of
`2026-10-30-sandbox-supervisor-brief.md` (every lead's questions in one inbox on the phone).
Markers: `[v]` = verified in this sandbox on 2026-11-01 (read or `command -v`, nothing run on the
host); `[u]` = unverified, taken from the cited document.

## Goal

Settle whether a Google Chat space can carry a lead's questions and the user's answers to and from
a Claude Code session running in an ai-sandbox container, so that leads on different Claude
accounts (one per sandbox) reach one inbox: the Google Chat app on the phone.

## Questions the spike settles

- Q1. Does the user's Workspace edition (Business Starter) suffice to build and install the Chat
  app? The quickstart requires "a Business or Enterprise Google Workspace account" `[u]`.
- Q2. Does the community plugin `buglime/claude-channel-googlechat` run inside the container?
- Q3. Does the channel also work for a `--bg` session (undocumented), including the warning dialog?
- Q4. Does the plugin filter by space, so one session per project space needs no patch?
- Q5. Latency of one round trip phone -> session -> phone.
- Q6. What does the user see in the Google Chat app on the phone (notification, thread, sender)?

## Facts checked (cite as given)

- Claude Code channels are a research preview: an MCP stdio server declaring `claude/channel`,
  loaded with `claude --dangerously-load-development-channels plugin:<name>@<marketplace>` or
  `--plugin-dir` for a local plugin; interactive sessions only (ignored with `-p`); a warning dialog
  to accept; `--bg` with channels undocumented. The plugin's README and SETUP.md use
  `claude --channels plugin:googlechat@claude-channel-googlechat` instead; `[v]` `claude --help`
  of 2.1.312 lists neither flag (0 lines match "channel"), lists `--bg` and `--plugin-dir`, and
  `claude plugin marketplace add` / `claude plugin enable` exist. Per the channels docs,
  `--channels` takes only Anthropic's allowlist (a community plugin starts but never registers),
  so the spike uses `--dangerously-load-development-channels` only. The plugin's marketplace
  catalog sits at `marketplace/.claude-plugin/marketplace.json` with source `./..`, which Claude
  Code rejects, so the plugin is loaded from a clone with `--plugin-dir` on every `claude` call.
- Plugin (last push 2026-08-14): Pub/Sub pull, Workspace-email access control, default drop-all;
  config in `~/.claude/channels/googlechat/.env` (`GOOGLE_APPLICATION_CREDENTIALS`,
  `GOOGLECHAT_PROJECT_ID`, `GOOGLECHAT_SUBSCRIPTION`); `access.json` with `owner`, `allowFrom`,
  `spaces` (per-space opt-in, DMs need none); messages from spaces without an entry are not
  delivered; **one subscription per session** (subscribers on one subscription load-balance).
  `.mcp.json` runs `bun run --cwd ${CLAUDE_PLUGIN_ROOT} ... start`; `start` =
  `bun install --no-summary && bun server.ts`. `[v]` `command -v bun` finds nothing in this
  sandbox; Node 24.22.1, npm, corepack are present; npm registry has `bun@1.4.4`.
- Google side: a Chat app needs a Workspace account; one Chat app per Cloud project; the app can be
  in many spaces, each event carries `space.name`; a pull subscription needs no inbound port;
  several subscriptions on one topic each get every message; replies via Chat API with a service
  account and scope `chat.bot`, no admin approval, the app must be a member of the space; Chat API
  free, Pub/Sub 10 GiB/month free with billing attached; visibility can be the developer's own email.
- Sandbox: bridged network, outbound only; `~/.claude` is the sandbox's own copy; dev-tools is
  mounted read-only at `~/tools`; `[v]` `cloudflared 2026.10.5` and `gcloud 591.0.0` are in the
  image; `/etc/claude-code/managed-settings.json` has no `allowedChannelPlugins` key, so channel
  plugins are not filtered there. `[v]` `ai-sandbox '<snippet>'` runs the snippet in the project's
  container (`compose exec <name> bash -lc`); `ai-sandbox --print-context` prints its name.
  `.tmp/` is not gitignored: the service-account key never goes under the project tree.

## Prerequisites

The user's Workspace account with billing on Google Cloud; the Google Chat app on the phone, signed
in with that account; one sandbox of a project (call it `P`) with a working Claude login; a
terminal on the host in `P`'s directory; `gcloud` logged in as the user (Cloud Shell in the console
is enough; the sandbox's gcloud has no login). Set `<p>` = the new project id, `<me>` = the
Workspace email. Takes about an hour; the Google part is one-off.

## Steps

### A. In the Google Cloud console (or Cloud Shell), one project `<p>` `[u]` (from SETUP.md and the quickstart)

1. Create project `<p>`, attach the billing account. Then:
   `gcloud config set project <p> && gcloud services enable chat.googleapis.com pubsub.googleapis.com`
2. Topic and one pull subscription per session (two subscriptions, for step C6):
   `gcloud pubsub topics create chat-inbound`
   `gcloud pubsub subscriptions create chat-sub-a --topic=chat-inbound`
   `gcloud pubsub subscriptions create chat-sub-b --topic=chat-inbound`
3. Let Chat publish: `gcloud pubsub topics add-iam-policy-binding chat-inbound --member="serviceAccount:chat-api-push@system.gserviceaccount.com" --role="roles/pubsub.publisher"`
4. Service account and key. On the host first `mkdir -m 700 ~/gchat-spike`; the key lives only
   there, never in a project tree. Then:
   `gcloud iam service-accounts create gchat-app --display-name="Google Chat app"`
   `gcloud iam service-accounts keys create ~/gchat-spike/sa-key.json --iam-account="gchat-app@<p>.iam.gserviceaccount.com"`
   (in Cloud Shell: `keys create sa-key.json`, download it, then `mv ~/Downloads/sa-key.json ~/gchat-spike/`);
   `chmod 600 ~/gchat-spike/sa-key.json`. If `keys create` fails with the org policy
   `iam.managed.disableServiceAccountKeyCreation` (default in new organizations), add a project
   override on the Organization policies page and retry; paste the outcome either way.
   `for s in chat-sub-a chat-sub-b; do gcloud pubsub subscriptions add-iam-policy-binding $s --member="serviceAccount:gchat-app@<p>.iam.gserviceaccount.com" --role="roles/pubsub.subscriber"; done`
5. Console: APIs & Services -> Google Chat API -> Configuration. "Build this Chat app as a
   Google Workspace add-on": disabled (confirm with Disable). App name `Lead inbox`, any avatar
   URL, description; Functionality: join spaces and group conversations; Connection settings:
   Cloud Pub/Sub, topic `projects/<p>/topics/chat-inbound`; Visibility: specific people, `<me>`;
   Logs: errors to Logging. Save. (Q1 is decided here: note any refusal verbatim.)
6. In Google Chat (web or phone): create two spaces, `proj-P` and `proj-X`, add the app to both
   (search by `Lead inbox`); one space per project is the intended end state. Also open a DM
   with the app. Probe without the sandbox: post `hello` in `proj-P`, then
   `gcloud pubsub subscriptions pull chat-sub-b --limit=1` (no `--auto-ack`, so it stays
   for the session) and confirm a MESSAGE event with `"space":{"name":"spaces/..."}`
   arrives and whether `message.sender.email` is present (without it the plugin's gate matches
   only `users/<id>`, so a C4 failure would be that, not Q2); note `spaces/<id>` for `proj-P`
   and `proj-X` (from the events or the space URL).

### B. On the host, in `P`'s project directory

1. `[v]` form, `[u]` content: `ai-sandbox 'sudo npm install -g bun@1.4.4 && bun --version'`
   (sandbox-only package install, `npm` route instead of the `curl | sh` installer;
   `/usr/lib/node_modules` is root-owned in the image, hence `sudo`).
2. Place the key in the sandbox's own `~/.claude`, which is `$dir/.claude` on the host `[u]`:
   `dir=$(ai-sandbox --print-context | sed -n 's/^dir=//p')`
   `install -D -m 600 ~/gchat-spike/sa-key.json "$dir/.claude/channels/googlechat/sa-key.json"`
   (outside every git tree; no `docker cp`, which would leave a root-owned file in `/tmp`).
3. Clone the plugin inside the sandbox `[u]`; it is loaded with `--plugin-dir` on every `claude`
   call below (the repository's marketplace catalog is not loadable, see Facts):
   `ai-sandbox 'git clone https://github.com/buglime/claude-channel-googlechat ~/claude-channel-googlechat && ls ~/claude-channel-googlechat/.claude-plugin'`
   Define `PD="--plugin-dir $HOME/claude-channel-googlechat"` in the sandbox shell for C.

### C. Inside one sandbox (`ai-sandbox`, then the commands in the shell)

1. `claude $PD` (interactive, in `P`'s tree). Inside the session `[u]`:
   `/googlechat:configure key /home/<user>/.claude/channels/googlechat/sa-key.json`,
   `/googlechat:configure project <p>`, `/googlechat:configure subscription chat-sub-a`,
   `/googlechat:access owner <me>`, `/googlechat:access space add spaces/<id of proj-P> --no-mention`
   (if the subcommand is missing, edit `~/.claude/channels/googlechat/access.json` and add
   `"spaces": {"spaces/<id of proj-P>": {"requireMention": false}}`). `/exit`.
   Paste `cat ~/.claude/channels/googlechat/.env` with the key path only, and `access.json`.
   Before configure, the plugin's MCP server starts without `.env` and may show as failed under
   `/mcp`; that is expected and not a Q2 result.
   Then, host side, drop A6's leftovers so only new messages reach C3:
   `gcloud pubsub subscriptions seek chat-sub-a --time="$(date -u +%FT%TZ)"`.
2. Synthetic event, host side `[u]` (SETUP.md step 8, with `<me>` as sender email):
   `gcloud pubsub topics publish chat-inbound --message='{"type":"MESSAGE","space":{"name":"spaces/TEST","type":"DM"},"message":{"name":"spaces/TEST/messages/m1","text":"hello from a test event","createTime":"2026-11-01T10:00:00Z","sender":{"name":"users/123","displayName":"Tester","email":"<me>"}}}'`
   Run it after step 3 has started, from a second host terminal.
3. Start the interactive session with the channel `[u]`:
   `claude $PD --dangerously-load-development-channels plugin:googlechat@claude-channel-googlechat`;
   if the startup notice names no channel, retry with the id `server:googlechat` (the channel id
   under `--plugin-dir` is unverified; the notice names the registered form). Acceptance signals:
   the dialog ("I am using this for local development") and the notice "Channels (experimental)
   messages from ... inject directly in this session"; paste both. Expect a
   `<channel source="googlechat" ... role="owner">` block for the step-2 event, then say in the
   session: "When a googlechat message arrives, reply to it with PONG and the time, in its
   thread." (Q2) A "blocked by org policy" refusal means a Team/Enterprise login, or an API-key
   login under the image's managed-settings.json without `channelsEnabled` (a dev-tools change;
   goes to the supervisor spec's deferred list).
4. Round trip from the phone: in `proj-P` post `ping 1`, note the phone clock to the second;
   note when the `<channel>` block shows in the session and when `PONG` shows on the phone (Q5,
   Q6). Repeat once in the DM with the app. Then post `ping X` in `proj-X`: expect nothing in the
   session (Q4). Paste `/status` output or the last 30 lines of the session.
5. `--bg` `[u]`, same flag and channel id as step 3: `/exit`, then
   `claude $PD --bg --name gchat-lead --dangerously-load-development-channels <id> -- "Wait for googlechat messages; reply PONG-BG to each in its thread."`
   note the id it prints as `ID`; `sleep 20; claude agents --json; claude logs gchat-lead | tail -30`,
   post `ping 2` in `proj-P` from the phone, `sleep 20; claude logs gchat-lead | tail -30`. If
   nothing arrives: `claude attach $ID`, look for the channel warning dialog, accept it, detach,
   post `ping 3`, read the log again. (Q3)
6. Second session, second subscription (the one-inbox case): `claude stop $ID`; in `.env` set
   `GOOGLECHAT_SUBSCRIPTION=chat-sub-b`; switch the opt-in: `claude $PD`,
   `/googlechat:access space rm spaces/<id of proj-P>`,
   `/googlechat:access space add spaces/<id of proj-X> --no-mention`, `/exit` (or edit
   `access.json` by hand; it is re-read per message); host side
   `gcloud pubsub subscriptions seek chat-sub-b --time="$(date -u +%FT%TZ)"` (drops the unacked
   copies of A6's `hello` and C4's pings); start as in step 3; post `ping 4` in `proj-X` and
   `ping 5` in `proj-P`: expect only `ping 4`.

## What counts as success

- Q1: A5 saves with Pub/Sub and `<me>` under visibility; A6 finds the app in Chat search and the
  pull shows a MESSAGE event. Otherwise the edition is the blocker; paste the refusal.
- Q2: bun starts (B1), B3's `ls` shows `plugin.json` and `/googlechat:configure` exists in C1,
  C3 shows the synthetic `<channel>`
  block, C4 shows `PONG` on the phone in the thread of `ping 1`, posted by `Lead inbox`.
- Q3: C5's log shows the `ping 2` block and a reply tool call without attaching; "works after
  accepting the dialog once" counts as partial success and names the dialog as the open item.
- Q4: `ping X` never reaches the session in C4 and only `ping 4` reaches it in C6: filtering is
  configuration, no patch. If `ping X` arrives, a patch (or `requireMention`) is the next task.
- Q5: phone -> session under 10 s and session -> phone under 20 s on three pings; paste the times.
- Q6: a notification for the app's reply reaches the phone (lock screen or badge), the reply sits
  in the thread of the question, and the DM variant also works; describe in two lines.

## Fallback if a step fails (plan B, `[u]`)

If A6's pull never shows an event, or the plugin cannot pull from the container (C3 shows no block
for the synthetic event although `gcloud pubsub subscriptions pull chat-sub-a` on the host does),
switch the app's Connection settings to an HTTP endpoint: in the sandbox run
`python3 -m http.server 8080 --bind 127.0.0.1` in one shell and `cloudflared tunnel --url
http://127.0.0.1:8080` in another, paste the printed `https://*.trycloudflare.com` URL as the
endpoint, post `ping B` in `proj-P`, and paste the request line the listener logs (a 501 is
expected; this proves delivery into the container, the responder is a later task); switch the
Connection settings back to Pub/Sub afterwards. If bun cannot be installed (B1), paste the error
and stop; porting `server.ts` to Node is then a task of its own.

## What to paste back (one block per step, with the step letter)

A4: whether `keys create` worked at once or needed the org-policy override. A5: the saved
configuration page's fields (screenshot or text) and any refusal. A6: the pull output (first 20
lines), with or without `sender.email`. B1: `bun --version`. B3: the `ls` of `.claude-plugin`.
C1: `.env` (key path only) and `access.json`. C3: the channel id that registered, the dialog text,
the "Channels (experimental)" notice line, the `<channel>` block. C4: the three timestamps per
ping, the phone description, whether `ping X` arrived. C5: both `claude logs` tails, and whether
attaching was needed. C6: which pings arrived. Plan B, if used: the listener's log line.

## Cleanup

In the sandbox: `claude stop $ID; claude rm $ID`, `rm -rf ~/.claude/channels/googlechat
~/claude-channel-googlechat`, `sudo npm uninstall -g bun` unless the next phase keeps it. On the
host (gcloud as the user): delete the spaces or leave them;
`gcloud iam service-accounts keys delete <key-id> --iam-account=gchat-app@<p>.iam.gserviceaccount.com`
(`keys list` gives the id), then `shred -u ~/gchat-spike/sa-key.json && rmdir ~/gchat-spike`; keep
project `<p>` if the result is positive (the next phase reuses the app), else
`gcloud projects delete <p>`. The spike's results go to
`docs/superpowers/specs/2026-11-01-google-chat-channel-spike-results.md`, written by the lead from
the pasted blocks, and the supervisor spec's assumption table is updated from them.

## Review, round 1

Fiona, reviewer 1, 2026-11-01. Checked against the plugin's repository (docs, marketplace
catalog, skills, `src/`), the Claude Code channels docs, the Pub/Sub quickstart, `claude --help`
2.1.312 here, `create-ai-sandbox.sh` and `ai-sandbox`.

Blocking (Important):

1. A4/B2/Cleanup, key location. "Current directory" is the host terminal in `P`'s tree, mounted
   read-write into the sandbox and under git; with Cloud Shell the key is not on the host at all.
   Fix: `mkdir -m 700 ~/gchat-spike` on the host, `keys create ~/gchat-spike/sa-key.json`; from
   Cloud Shell download and `mv` it there, so no copy stays in `~/Downloads`; `chmod 600`; B2 and
   cleanup use that path.
2. B2. `docker cp` writes a root-owned file into sticky `/tmp`; the `mv` fails. The sandbox's
   `~/.claude` is `$dir/.claude` on the host (`ai-sandbox --print-context`, `dir=`), so
   `install -D -m 600 ~/gchat-spike/sa-key.json "$dir/.claude/channels/googlechat/sa-key.json"`
   replaces B2; the path is outside every git tree.
3. B3. The marketplace shorthand will not work: the catalog sits at
   `marketplace/.claude-plugin/marketplace.json` with source `./..`; Claude Code expects it at
   the repo root and rejects `..` sources. Make the clone with `--plugin-dir` the primary
   route and pass it on every `claude` call (C1, C3, C5, C6), or C1 has no
   `/googlechat:configure`. The channel id under `--plugin-dir` is unverified: try the
   `plugin:` form, then `server:googlechat`; the startup notice names the registered form.
4. C3, flag order. The docs say `--channels` accepts only the Anthropic allowlist; a community
   plugin "starts normally but the channel doesn't register", so `--channels` counts as accepted
   and the step reads as a plugin failure. Use `--dangerously-load-development-channels`
   directly; the acceptance signal is the dialog ("I am using this for local development") and
   the notice "Channels (experimental) messages from … inject directly in this session"; add
   that line to the C3 paste block.
5. C6, Q4 criterion. `chat-sub-b` holds unacked copies of everything since A6, including
   `ping X` from C4, which C6's gate accepts, so "expect only ping 4" reads as a failure. Before
   C6: `gcloud pubsub subscriptions seek chat-sub-b --time="$(date -u +%FT%TZ)"` (and
   `chat-sub-a` before C3, or the A6 `hello` arrives there).

Lesser:

6. A4. New Cloud organizations enforce `iam.managed.disableServiceAccountKeyCreation`; `keys
   create` then fails. Add the project override (Organization policies page) and A4's outcome
   to the paste list.
7. B1. `/usr/lib/node_modules` is root-owned in the image: go straight to
   `sudo npm install -g bun@1.4.4`; cleanup `sudo npm uninstall -g bun`.
8. C1. The skill has `/googlechat:access space add spaces/<id> --no-mention`; name it. In A6
   confirm the event carries `sender.email`; without it the gate matches only `users/<id>` and
   C4 fails for that reason, not Q2.
9. C5/Cleanup. `claude stop` and `rm` take `<id>`; use the id `--bg` prints.
   Cleanup's "Host:" line runs in the sandbox.
10. C3. "blocked by org policy" means a Team/Enterprise login, or an API-key login under the
    image's managed-settings.json without `channelsEnabled` (dev-tools change, deferred list).

Q1 to Q6 each have a settling observation (Q4 after item 5). Plan B is sound; switch the
Connection settings back afterwards. No step touches another sandbox or the image: bun and
plugin state stay in the container and `$SANDBOX_DIR/.claude`.

## Fix round 1

Bartek, planner 2, 2026-11-01. All ten items applied:

1. Key created in `~/gchat-spike` (dir 700, key 600) in A4, Cloud Shell download moved there; B2 and cleanup use that path.
2. B2 is `install -D -m 600` into `$dir/.claude/channels/googlechat/`, `dir` from `ai-sandbox --print-context`; no `docker cp`.
3. B3 clones the plugin; `$PD` (`--plugin-dir`) on every `claude` call in C1, C3, C5, C6; marketplace route dropped, Facts say why; id `plugin:` then `server:googlechat`.
4. C3 uses `--dangerously-load-development-channels` only; the dialog and the "Channels (experimental)" notice are the acceptance signals and are in the C3 paste block; `--channels` allowlist noted in Facts.
5. `seek` to now on `chat-sub-a` after C1 and on `chat-sub-b` in C6, so Q4's "only ping 4" holds.
6. A4 names the org policy and the project override; A4's outcome is in the paste list.
7. B1 is `sudo npm install -g bun@1.4.4`; cleanup `sudo npm uninstall -g bun`.
8. C1 names `/googlechat:access space add spaces/<id> --no-mention`; A6 checks `sender.email` and the paste block reports it.
9. C5 records the id `--bg` prints as `ID`; `attach`, `stop`, `rm` take it; cleanup labels are "In the sandbox" and "On the host".
10. C3 explains "blocked by org policy" (Team/Enterprise login, or API-key login without `channelsEnabled` in the image's managed-settings.json; deferred-list item for dev-tools); plan B switches the Connection settings back.

## Review, round 2

Fiona, reviewer 1, 2026-11-01. Delta only: A4, B1-B3, C1, C3, C5, C6, cleanup, plan B, Facts
and the paste list, against the same sources as round 1.

Round-1 findings: 1 (key path) closed; 2 (`install -D` into `$dir/.claude`, host user owns the
file) closed; 3 (`--plugin-dir` on every call, marketplace dropped, fallback id named) closed;
4 (dev flag only, dialog and notice as signals, in the paste block) closed; 5 (`seek` on both
subscriptions, in the right order: after C1, before C2/C3, and in C6) closed; 6 to 10 closed.

No new blocking finding. Lesser, no re-review needed:

1. "What counts as success", Q2 still says "`claude plugin list` shows `googlechat`"; a
   `--plugin-dir` plugin is not listed there, so the user reads a pass as a failure. Replace
   with "B3's `ls` shows `plugin.json` and `/googlechat:configure` exists in C1".
2. C6 says "opt in `proj-X` instead of `proj-P`" without the command: either
   `claude $PD`, `/googlechat:access space rm spaces/<P>`, `space add spaces/<X> --no-mention`,
   `/exit`, or edit `access.json` by hand (it is re-read per message).
3. C1: on plain `claude $PD` before configure the plugin's MCP server starts without `.env`
   and may show as failed under `/mcp`; say that this is expected and not a Q2 result.
4. A4, Cloud Shell branch: "create it there" reads as the directory; write "in Cloud Shell
   `keys create sa-key.json`, download it, then `mv`".

Verdict: accepted; the round closes the review of the document as written, the lesser items
are the planner's to fold in without another round.

## Fix round 2

Bartek, planner 2, 2026-11-01. The four lesser items folded in: Q2's success line cites B3's `ls` and `/googlechat:configure`; C6 gives the `space rm` / `space add --no-mention` switch; C1 says an `/mcp` failure before configure is expected; A4's Cloud Shell branch names `keys create sa-key.json`, download, `mv`.
