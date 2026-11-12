Task: 2026-11-11-sandbox-hardening
Class: phase

# Phase 1 plan: searches and probes behind the impact set

Written by Bartek (planner 2) on 2026-11-11 against `4d6f677` (`main`), inside the
dev-tools sandbox. Every search below was run with `command grep` (the interactive
`grep` here is a shell function that skips ignored and binary files) and `-a`, so no
file is skipped for its content. Plan: `docs/superpowers/plans/2026-11-11-sandbox-hardening-p1-plan.md`.
Revised the same day after the plan review (round 1), still against `4d6f677`: P-A and
P-D are restated at the level of input classes (review F6), P-E and the B1 run of P-D
are new, the structural search is redone with the rule of O3 (review F2), and S20b and
S23 to S25 are added. Inputs are named by class only; fixture code and the mechanisms
behind findings stay in untracked files under `.tmp/security/`. Revised on 2026-11-12
after round 2, against the same tree (`4d6f677`, `bin/` and `tests/` unchanged): the
rule's `command_name` line and its known case (N4), the R1b pattern (N4), and S20c and
S26 are new.

## Base suite

`bash tests/ai-sandbox/run-tests.sh` on `4d6f677`, 2 min 25 s: 20 files, 1217 cases,
2 failed, both in `test-delegate.sh` (`not ok 54 - writer prompt has no-tools line`,
`not ok 59 - second-reviewer prompt has no-commands line`); every other file `0 failed`.
`test-knowledge.sh`: 473 run, 0 failed. Agrees with the spec's A4.

## Probes (git 2.34.1, the version of the sandbox image's Ubuntu 22.04)

- P-A, a git process reads the repository its working directory lies in, also for a
  command given a URL. In a scratch repository whose own configuration bears on remote
  URLs, `git ls-remote <url>` run with the working directory inside it did not reach
  `<url>`; run outside any repository it listed the refs. Consequence for the plan:
  `ai-knowledge` is started by `ai-sandbox` from the project directory, so a URL-only
  command (`ls-remote`, `clone`) must also run with no repository discovered.
- P-B, the remote program of a fetch. `git fetch` from a host-owned bare repository
  whose remote URL is a path that does not exist on the host, with the remote's
  upload-pack program set to a wrapper: the wrapper received the URL path as its one
  argument (`ARG=/does/not/exist/knowledge`), served another repository, and the refs
  arrived under `refs/sandbox/x/heads/*`. The URL need not name a host path.
- P-C, `git bundle create - --all` writes the bundle to standard output
  (`# v2 git bundle` header), the transport of A1's fallback.
- P-D, batch B1a of the revised plan, with the revised fixture file (SHA-256
  `4a4a652eb4dadb4e2a6022d8742349ae1b452f7ee0520baa854edd93efc25d8a`, the value B1a
  checks), run here from a scratch copy with `bash -n` (syntax ok) and then against a
  shim for `docker` that runs the entrypoint locally with no isolation (there is no
  Docker in this sandbox), `GIT_CONFIG_GLOBAL=/dev/null`. Result: both fetches `exit 0`;
  refs delivered `same`; refs outside the namespace `none`; markers `none`; bundle lines
  `exit 0`, `same`, `none`, `none`; control `live`; A2 `no sandbox running`. Method check,
  the batch's checks on known bad inputs: with the confinement option of the fetch
  removed from the batch, "refs outside the namespace" listed two refs in the fetch
  form and one in the bundle form; with one byte appended to the fixture, the batch
  printed `FIXTURE DIFFERS FROM THE ONE READ: stop` and ran nothing else. B1b was
  checked with `bash -n` only (it reads the host's `~/.ai-sandbox`, which this sandbox
  does not have). What only the host can answer is how the real container behaves,
  how long it takes and what the host's git does (X1).
- P-E, the property behind review F1, scratch repositories, git 2.34.1. A fetch in the
  first plan's form (explicit refspec with a destination below `refs/sandbox/x/`) from
  a served repository holding refs of a kind the fixture plants left refs outside
  `refs/sandbox/x/` in the fetching repository, in the upload-pack and in the bundle
  transport, and a short name the host uses then resolved to the served repository's
  choice. The same fetch with T09's confinement left none, in both transports; it still
  left none with each of four user-level `fetch.*` and `remote.*` settings set that
  could widen what a fetch writes (named in the planner's report to the lead, kept
  untracked). The mechanism is in
  `.tmp/security/2026-11-11-sandbox-hardening-p1-plan-review-private.md` (untracked).

## Structural search for host git starts (method and base count)

ast-grep 0.51.0 with this scratch configuration (`sgconfig.yml`, `rules/git.yml`), the
rule of O3 without its restriction to the two C-GIT bodies (which do not exist on the
base) and without the named exceptions (counted below):

```
ruleDirs: [rules]
languageGlobs:
  bash: ["ai-*", "*-ai-*", "context-statusline", "handover-ready"]
```
```
id: probe-host-git
language: bash
rule:
  kind: command
  has:
    any:
      - { kind: command_name, regex: "^[\"']?(\\S*/)?git[\"']?$" }
      - { kind: word, regex: '^(\S*/)?git$' }
      - { kind: string, regex: '^"(\S*/)?git"$' }
      - { kind: raw_string, regex: "^'(\\S*/)?git'$" }
  not:
    any:
      - has: { kind: command_name, regex: '^(hint|require)$' }
      - all:
          - has: { kind: command_name, regex: '^command$' }
          - has: { kind: word, regex: '^-v$' }
severity: error
message: git
```

Command: `ast-grep scan -c <dir>/sgconfig.yml bin/ai --json=stream`, findings counted
per file. Result with the `not` block: 106 starts: `ai-knowledge` 75,
`ai-sandbox-migrate-knowledge` 26, `create-ai-sandbox.sh` 2 (2188 and 2189, the
identity read), `ai-delegate` 2 (28, 54), `ai-sandbox-lib.sh` 1 (55). Without the `not`
block: 123 reports; the 17 more are the exempt forms, `hint git` 15 (ai-knowledge 217,
375, 415, 421, 719, 749, 758, 804, 808, 818, 822, 881, 885, 918, 1223), `command -v git`
(ai-knowledge 199) and `require git` (create-ai-sandbox.sh 323).

The first round's rule (`has: {field: name|argument, regex: '^git$'}`) gave 119 on the
same tree. Checked on a scratch file: its `has` with `field: argument` matched
`timeout git a` but not `timeout 60 git a`, so `git` as a later argument of a wrapper
was missed (ai-knowledge 61, migrate-knowledge 18); and in the brace group of the
condition at ai-knowledge 1158 the parser takes `{` as the command's name (the revised
rule's report there starts with `{ GIT_INDEX_FILE=`), which makes `git` a later
argument too. The four lines the listing below lacks are those three and
ai-knowledge 199.

Method checks:
- Known case for the revised rule: a scratch file `ai-known` with
  `a() { GIT_TERMINAL_PROMPT=0 timeout 60 git "$@"; }`, an `if ! { GIT_INDEX_FILE=$idx git -C "$r" read-tree x && y=$(git -C "$r" write-tree); }`
  line, `/usr/bin/git status`, `command git log`, `command -v git`, `hint git push`,
  `require git`, `exec nice -n 5 git gc` and a heredoc holding a git line gave exactly
  the 6 starts (lines 1, 2 twice, 3, 4, 8) and nothing for the three exempt forms and the
  heredoc.
- Round 3 (N4): the `command_name` line of round 2, `regex: '^(\S*/)?git$'`, did not
  report a quoted command name: the name's text keeps its quotes. On the same scratch
  file with four lines added before the heredoc, as lines 9 to 12 (`"git" status`, `'git' status`, `"/usr/bin/git" status`,
  `timeout 5 "git" fetch`), round 2's rule reported 7 (lines 1, 2 twice, 3, 4, 8, 12:
  the quoted argument only); the revised line above reports 10 (adding 9, 10, 11), and
  without the `not` block 13 (the three exempt forms 5, 6, 7 added); the heredoc line
  is reported by neither. On the base the revised rule gives the same counts as
  round 2's: 106 with the `not` block, 123 without
  (`ast-grep scan -c <dir>/sgconfig.yml bin/ai --json=stream | wc -l`); the base holds
  no quoted command name `git`.
- Failure mode found and avoided: `ast-grep run -l bash -p 'git $$$A' bin/ai/ai-knowledge`
  returned 0 findings with no error, because a file without a `.sh` extension is not
  parsed unless `languageGlobs` maps it. The repository's rule carries that mapping and
  its test proves that every bash file under `bin/ai` is parsed or a named exception.
  On the base, `command grep -rlaE '^#!.*\b(ba)?sh\b' bin/ai` and `ls bin/ai/*.sh` give
  18 files, all matched by the globs above.
- Heredoc bodies are not parsed as commands: the git calls inside the generated
  `sandbox-doctor` (create-ai-sandbox.sh 1606, 1607, 1615) and the generated bashrc
  (1798 to 1807) are not among the findings. They run inside the container; R1b reads
  them.

Listing of the first round's 119 reports (file:line: text); the revised rule adds the
four lines named above:

```
bin/ai/ai-delegate:28: top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ai-delegate: not inside a git repository" >&2; exit 2; }
bin/ai/ai-delegate:54: exclude=$(git rev-parse --path-format=absolute --git-path info/exclude)
bin/ai/ai-knowledge:217: printf '     %s\n' "$(hint git clone "$remote" "$KNOWLEDGE_MAIN")" >&2
bin/ai/ai-knowledge:231: if git -C "$KNOWLEDGE_MAIN" show-ref -q --verify refs/remotes/origin/main; then
bin/ai/ai-knowledge:232: git -C "$KNOWLEDGE_MAIN" rev-parse -q --verify HEAD >/dev/null 2>&1 \
bin/ai/ai-knowledge:233: || git -C "$KNOWLEDGE_MAIN" checkout -q -B main origin/main
bin/ai/ai-knowledge:234: elif ! git -C "$KNOWLEDGE_MAIN" rev-parse -q --verify HEAD >/dev/null 2>&1; then
bin/ai/ai-knowledge:237: git -C "$KNOWLEDGE_MAIN" checkout -q main 2>/dev/null \
bin/ai/ai-knowledge:268: git -C "$KNOWLEDGE_MAIN" show-ref -q --verify refs/remotes/origin/main || return 0
bin/ai/ai-knowledge:269: readme=$(git -C "$KNOWLEDGE_MAIN" show origin/main:README.md 2>/dev/null || true)
bin/ai/ai-knowledge:280: if [ -d "$iclone/.git" ] && git -C "$iclone" merge-base --is-ancestor origin/main main 2>/dev/null \
bin/ai/ai-knowledge:281: && [ "$(git -C "$iclone" rev-parse main)" != "$(git -C "$iclone" rev-parse origin/main)" ]; then
bin/ai/ai-knowledge:281: && [ "$(git -C "$iclone" rev-parse main)" != "$(git -C "$iclone" rev-parse origin/main)" ]; then
bin/ai/ai-knowledge:292: git -C "$KNOWLEDGE_MAIN" merge -q --ff-only origin/main >/dev/null 2>&1 || true
bin/ai/ai-knowledge:311: git -C "$KNOWLEDGE_MAIN" show-ref -q --verify refs/remotes/origin/main || return 0
bin/ai/ai-knowledge:314: git -C "$KNOWLEDGE_MAIN" show origin/main:rules/global.md > "$remote_rules" 2>/dev/null || : > "$remote_rules"
bin/ai/ai-knowledge:363: git -C "$KNOWLEDGE_MAIN" symbolic-ref HEAD refs/heads/main
bin/ai/ai-knowledge:364: git -C "$KNOWLEDGE_MAIN" add -A
bin/ai/ai-knowledge:365: git -C "$KNOWLEDGE_MAIN" config user.email >/dev/null 2>&1 \
bin/ai/ai-knowledge:367: git -C "$KNOWLEDGE_MAIN" "${identity[@]+"${identity[@]}"}" commit -qm "chore: seed the knowledge repository"
bin/ai/ai-knowledge:375: HINT_PUSH+=("$(hint git -C "$KNOWLEDGE_MAIN" push -u origin main)")
bin/ai/ai-knowledge:415: HINT_FETCH+=("$(hint git -C "$KNOWLEDGE_MAIN" fetch --prune origin)")
bin/ai/ai-knowledge:419: if git -C "$KNOWLEDGE_MAIN" show-ref -q --verify refs/remotes/origin/main; then
bin/ai/ai-knowledge:420: git -C "$KNOWLEDGE_MAIN" merge -q --ff-only origin/main >/dev/null 2>&1 \
bin/ai/ai-knowledge:421: || warn "$KNOWLEDGE_MAIN is not a fast-forward of origin/main; it is never edited by hand, so repair it with: $(hint git
bin/ai/ai-knowledge:627: git -C "$CLONE" show-ref -q --verify refs/remotes/origin/main || return 2
bin/ai/ai-knowledge:628: git -C "$CLONE" merge-base --is-ancestor "$1" origin/main 2>/dev/null || return 2
bin/ai/ai-knowledge:629: if grep -qxF "$1" <<<"$(git -C "$CLONE" rev-list --first-parent origin/main)"; then return 1; fi
bin/ai/ai-knowledge:680: git -C "$1" show-ref -q --verify refs/remotes/origin/main || return 0
bin/ai/ai-knowledge:684: if [ "$3" = integrator ] && git -C "$1" merge-base --is-ancestor origin/main main 2>/dev/null; then
bin/ai/ai-knowledge:687: git -C "$1" merge-base --is-ancestor main origin/main 2>/dev/null || return 1
bin/ai/ai-knowledge:689: git -C "$1" merge -q --ff-only origin/main >/dev/null 2>&1
bin/ai/ai-knowledge:691: git -C "$1" update-ref refs/heads/main origin/main
bin/ai/ai-knowledge:719: HINT_FETCH+=("$(hint git clone "$REMOTE" "$CLONE")")
bin/ai/ai-knowledge:726: if ! git -C "$CLONE" rev-parse -q --verify HEAD >/dev/null 2>&1 \
bin/ai/ai-knowledge:727: && git -C "$CLONE" show-ref -q --verify refs/remotes/origin/main; then
bin/ai/ai-knowledge:728: git -C "$CLONE" checkout -q -B main origin/main || warn "cannot put $CLONE on main"
bin/ai/ai-knowledge:735: if [ -n "$(git -C "$CLONE" status --porcelain)" ]; then
bin/ai/ai-knowledge:739: current=$(git -C "$CLONE" branch --show-current)
bin/ai/ai-knowledge:749: HINT_FETCH+=("$(hint git -C "$CLONE" fetch --prune origin)")
bin/ai/ai-knowledge:758: HINT_FETCH+=("$(hint git -C "$CLONE" fetch origin 'refs/heads/proposal/*:refs/heads/proposal/*')")
bin/ai/ai-knowledge:765: out=$(git -C "$CLONE" ls-tree -r --name-only main -- proposals/ 2>/dev/null \
bin/ai/ai-knowledge:776: tip=$(git -C "$CLONE" rev-parse "$b")
bin/ai/ai-knowledge:782: 0)  if [ "$current" = "$b" ]; then git -C "$CLONE" checkout -q main; current=main; fi
bin/ai/ai-knowledge:783: git -C "$CLONE" branch -q -D "$b"
bin/ai/ai-knowledge:790: rc=0; out=$(git -C "$CLONE" diff --name-only --no-renames "origin/main...$b" 2>/dev/null) || rc=$?
bin/ai/ai-knowledge:798: remote_tip=$(git -C "$CLONE" rev-parse -q --verify "refs/remotes/origin/$b" 2>/dev/null || true)
bin/ai/ai-knowledge:800: if [ -n "$remote_tip" ] && ! git -C "$CLONE" merge-base --is-ancestor "$remote_tip" "$b"; then
bin/ai/ai-knowledge:804: HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$b:refs/heads/$b")"); pending=$((pending + 1)); continue
bin/ai/ai-knowledge:808: net_failed "$rc" "$out"; HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$b:refs/heads/$b")")
bin/ai/ai-knowledge:812: done < <(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*')
bin/ai/ai-knowledge:816: && [ "$(git -C "$CLONE" rev-parse main)" != "$(git -C "$CLONE" rev-parse -q --verify origin/main 2>/dev/null || true)" ]
bin/ai/ai-knowledge:816: && [ "$(git -C "$CLONE" rev-parse main)" != "$(git -C "$CLONE" rev-parse -q --verify origin/main 2>/dev/null || true)" ]
bin/ai/ai-knowledge:818: HINT_PUSH+=("$(hint git -C "$CLONE" push origin main)"); main_note="main pending"
bin/ai/ai-knowledge:822: else net_failed "$rc" "$out"; HINT_PUSH+=("$(hint git -C "$CLONE" push origin main)"); main_note="main push failed"
bin/ai/ai-knowledge:835: tip_state "$(git -C "$CLONE" rev-parse "$b")" && st=0 || st=$?
bin/ai/ai-knowledge:837: if [ "$current" = "$b" ]; then git -C "$CLONE" checkout -q main; current=main; fi
bin/ai/ai-knowledge:838: git -C "$CLONE" branch -q -D "$b"; closed=$((closed + 1))
bin/ai/ai-knowledge:839: done < <(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*')
bin/ai/ai-knowledge:842: tip=$(git -C "$CLONE" rev-parse "refs/remotes/$b")
bin/ai/ai-knowledge:848: done < <(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/remotes/origin/proposal/*')
bin/ai/ai-knowledge:865: if [ "$role" = integrator ] && git -C "$CLONE" show-ref -q --verify "refs/reports-closed/$rname"; then continue; fi
bin/ai/ai-knowledge:869: rtip=$(git -C "$CLONE" rev-parse -q --verify "$rref^{commit}" 2>/dev/null || true)
bin/ai/ai-knowledge:871: rc=0; out=$(git -C "$CLONE" diff --name-only --no-renames "origin/main...$rtip" 2>/dev/null) || rc=$?
bin/ai/ai-knowledge:881: HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$rref:$rref")"); pending=$((pending + 1)); continue
bin/ai/ai-knowledge:885: net_failed "$rc" "$out"; HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$rref:$rref")")
bin/ai/ai-knowledge:889: [ "$role" = integrator ] || git -C "$CLONE" update-ref -d "$rref"
bin/ai/ai-knowledge:890: done < <(git -C "$CLONE" for-each-ref --format='%(refname)' 'refs/reports/*')
bin/ai/ai-knowledge:899: rtip=$(git -C "$CLONE" rev-parse "$rref")
bin/ai/ai-knowledge:913: git -C "$CLONE" update-ref -d "refs/reports/$rname"
bin/ai/ai-knowledge:914: git -C "$CLONE" update-ref -d "$rref"
bin/ai/ai-knowledge:915: done < <(git -C "$CLONE" for-each-ref --format='%(refname)' 'refs/reports-closed/*')
bin/ai/ai-knowledge:918: HINT_FETCH+=("$(hint git -C "$CLONE" fetch origin 'refs/reports/*:refs/reports/*')")
bin/ai/ai-knowledge:1012: before=$(git -C "$KNOWLEDGE_MAIN" rev-parse HEAD 2>/dev/null || true)
bin/ai/ai-knowledge:1043: after=$(git -C "$KNOWLEDGE_MAIN" rev-parse HEAD 2>/dev/null || true)
bin/ai/ai-knowledge:1082: "$(git -C "$KNOWLEDGE_MAIN" rev-parse --short HEAD 2>/dev/null || echo none)" \
bin/ai/ai-knowledge:1120: git -C "$repo" merge-base --is-ancestor "$b" main 2>/dev/null && continue
bin/ai/ai-knowledge:1121: git -C "$repo" ls-tree -r --name-only "$b" -- proposals/ \
bin/ai/ai-knowledge:1123: done < <(git -C "$repo" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*')
bin/ai/ai-knowledge:1144: git -C "$repo" show-ref -q --verify "refs/reports-closed/$name" && continue
bin/ai/ai-knowledge:1145: git -C "$repo" ls-tree -r --name-only "$r" -- reports/ | { grep '\.md$' || true; } | sed "s|^|$name |"
bin/ai/ai-knowledge:1146: done < <(git -C "$repo" for-each-ref --format='%(refname)' 'refs/reports/*')
bin/ai/ai-knowledge:1154: git -C "$repo" config user.email >/dev/null 2>&1 \
bin/ai/ai-knowledge:1159: && blob=$(git -C "$repo" hash-object -w "$file") \
bin/ai/ai-knowledge:1160: && GIT_INDEX_FILE=$idx git -C "$repo" update-index --add --cacheinfo "100644,$blob,$path" \
bin/ai/ai-knowledge:1161: && tree=$(GIT_INDEX_FILE=$idx git -C "$repo" write-tree); }; then
bin/ai/ai-knowledge:1165: git -C "$repo" "${identity[@]+"${identity[@]}"}" commit-tree "$tree" -p "$base" -m "$msg"
bin/ai/ai-knowledge:1187: git -C "$repo" show-ref -q --verify refs/remotes/origin/main || die "$repo has no origin/main"
bin/ai/ai-knowledge:1217: git -C "$repo" update-ref "refs/heads/$branch" "$commit"
bin/ai/ai-knowledge:1223: HINT_PUSH+=("$(hint git -C "$repo" push origin "$branch:refs/heads/$branch")"); print_hints
bin/ai/ai-sandbox-lib.sh:55: if top=$(git rev-parse --show-toplevel 2>/dev/null); then
bin/ai/ai-sandbox-migrate-knowledge:165: | sed '/./,$!d' | git -C "$main" hash-object --stdin
bin/ai/ai-sandbox-migrate-knowledge:173: want=$(git -C "$2" show "$3:$4" 2>/dev/null | body_hash) || return 1
bin/ai/ai-sandbox-migrate-knowledge:177: git -C "$main" cat-file -e "$tip^{commit}" 2>/dev/null || gnet -C "$main" fetch -q origin "refs/heads/$cb" 2>/dev/null |
bin/ai/ai-sandbox-migrate-knowledge:178: [ "$(git -C "$main" show "$tip:$path" 2>/dev/null | body_hash)" != "$want" ] || return 0
bin/ai/ai-sandbox-migrate-knowledge:193: git -C "$1" ls-tree -r --name-only "$2" -- "proposals/$3/" 2>/dev/null \
bin/ai/ai-sandbox-migrate-knowledge:212: done < <(git -C "$c" for-each-ref --format='%(refname:short)' 'refs/heads/proposals/*')
bin/ai/ai-sandbox-migrate-knowledge:218: ltip=$(git -C "$c" rev-parse "$b"); rtip=$(remote_tip "$b")
bin/ai/ai-sandbox-migrate-knowledge:223: elif [ "$rtip" = "$ltip" ] || git -C "$c" merge-base --is-ancestor "$ltip" "$rtip" 2>/dev/null; then
bin/ai/ai-sandbox-migrate-knowledge:225: elif git -C "$c" merge-base --is-ancestor "$rtip" "$ltip" 2>/dev/null \
bin/ai/ai-sandbox-migrate-knowledge:232: done < <(git -C "$c" for-each-ref --format='%(refname:short)' 'refs/heads/proposals/*')
bin/ai/ai-sandbox-migrate-knowledge:248: if ! git -C "$repo" cat-file -e "$ref^{commit}" 2>/dev/null; then
bin/ai/ai-sandbox-migrate-knowledge:261: tmpf=$(mktemp); git -C "$repo" show "$ref:$f" > "$tmpf" 2>/dev/null || true
bin/ai/ai-sandbox-migrate-knowledge:287: cur=$(git -C "$c" branch --show-current)
bin/ai/ai-sandbox-migrate-knowledge:289: case "$cur $(git -C "$c" for-each-ref 'refs/heads/proposals/*')" in
bin/ai/ai-sandbox-migrate-knowledge:296: if [ -n "$(git -C "$c" status --porcelain)" ]; then
bin/ai/ai-sandbox-migrate-knowledge:300: git -C "$c" show-ref -q --verify refs/heads/main || git -C "$c" branch -q main origin/main
bin/ai/ai-sandbox-migrate-knowledge:300: git -C "$c" show-ref -q --verify refs/heads/main || git -C "$c" branch -q main origin/main
bin/ai/ai-sandbox-migrate-knowledge:301: git -C "$c" checkout -q main
bin/ai/ai-sandbox-migrate-knowledge:312: git -C "$c" branch -q -D "$b" 2>/dev/null || true
bin/ai/ai-sandbox-migrate-knowledge:316: done < <(git -C "$c" for-each-ref --format='%(refname:short)' 'refs/heads/proposals/*')
bin/ai/ai-sandbox-migrate-knowledge:327: [ "$(git -C "$iclone" branch --show-current)" = main ] || { BRANCH_FAILED+=("integrator clone $iclone is not on main; ol
bin/ai/ai-sandbox-migrate-knowledge:328: [ -z "$(git -C "$iclone" status --porcelain)" ] || { BRANCH_FAILED+=("integrator clone $iclone has uncommitted changes; 
bin/ai/ai-sandbox-migrate-knowledge:335: tip=$(git -C "$iclone" rev-parse "origin/$b")
bin/ai/ai-sandbox-migrate-knowledge:336: git -C "$iclone" merge -q -s ours --no-ff -m "close legacy branch $b (its proposals are proposal/* branches now)" "$tip"
bin/ai/ai-sandbox-migrate-knowledge:342: git -C "$iclone" branch -q -D "$b" 2>/dev/null || true
bin/ai/create-ai-sandbox.sh:323: require git
bin/ai/create-ai-sandbox.sh:2188: HOST_GIT_NAME=$(git config user.name 2>/dev/null || true)
bin/ai/create-ai-sandbox.sh:2189: HOST_GIT_EMAIL=$(git config user.email 2>/dev/null || true)
```

## R1b on the base

`command grep -rnaE '(^|[^A-Za-z0-9_.-])git(["'"'"']?([[:space:]]|$))' bin/ai`: 177 lines,
the same lines as round 2's pattern `(^|[^A-Za-z0-9_./-])git([[:space:]]|$)` (a `diff`
of the two outputs is empty). Known case, the round 3 scratch file above: round 2's
pattern matched lines 1, 2, 4 to 8 and the heredoc line, the revised one also 3 and 9
to 12 (a path-qualified and a quoted command name, N4). Less the
lines the revised rule reports (all lines of each report's range, exempt forms
included): 57 lines, by kind:
- comments, 16: ai-knowledge 4, 13, 55, 56, 93, 228, 677, 724, 753, 905;
  create-ai-sandbox.sh 956, 2011; ai-sandbox-migrate-knowledge 17;
  ai-sandbox-lib.sh 49; ai-sync 182, 284;
- message, usage or status text, 13: ai-knowledge 83, 210, 712, 770, 778, 929, 931,
  1117, 1140, 1186; create-ai-sandbox.sh 108, 986, 1051;
- heredoc bodies that run in the container, 14: ai-knowledge 649, 651, 659, 665 (the
  pre-commit hook written into the clone; T06 moves it into the in-sandbox command);
  create-ai-sandbox.sh 1606, 1607, 1615 (the doctor), 1798, 1799, 1801, 1802, 1804,
  1807 (the bashrc), 1965 (the Dockerfile's package list);
- Markdown under `bin/ai/knowledge-seed/`, 14: `skills/propose-rule/SKILL.md` 26, 27,
  31, 40, 62, 63, 64, 65, 79; `proposals/README.md` 39, 42, 43; `README.md` 37, 48.

## Text searches

Each block: the exact command, then its output.

### S1 (14 lines)

```
$ command grep -rna 'ai_sandbox_project_root' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/create-ai-sandbox.sh:369:PROJECT_ABS_DIR=$(ai_sandbox_project_root "${PROJECT_ARG:-.}") \
bin/ai/ai-knowledge:191:                            integrator=$(ai_sandbox_project_root "$2") || die "not a directory: $2"; shift 2 ;;
bin/ai/ai-knowledge:192:            --integrator=*) integrator=$(ai_sandbox_project_root "${1#*=}") || die "not a directory: ${1#*=}"; shift ;;
bin/ai/ai-knowledge:968:    project=$(ai_sandbox_project_root "$1") || die "not a directory: $1"
bin/ai/ai-knowledge:987:    project=$(ai_sandbox_project_root "$1") || die "not a directory: $1"
bin/ai/ai-knowledge:1088:        project=$(ai_sandbox_project_root "$1") || die "not a directory: $1"
bin/ai/ai-sandbox-lib.sh:50:ai_sandbox_project_root() {
bin/ai/ai-sandbox-lib.sh:126:    AI_SANDBOX_PROJECT=$(ai_sandbox_project_root) || return 1
tests/ai-sandbox/test-identity.sh:42:# Test ai_sandbox_project_root: inside a git repo from a subdirectory
tests/ai-sandbox/test-identity.sh:48:    "$(cd "$git_tmp/subdir" && ai_sandbox_project_root)" "$git_tmp"
tests/ai-sandbox/test-identity.sh:51:# Test ai_sandbox_project_root: outside a git repo
tests/ai-sandbox/test-identity.sh:54:    "$(ai_sandbox_project_root "$no_git")" "$no_git"
tests/ai-sandbox/test-identity.sh:57:# Test ai_sandbox_project_root: nonexistent directory fails
tests/ai-sandbox/test-identity.sh:59:result=$(ai_sandbox_project_root "$nonexist" 2>&1) || exit_code=$?
```

### S2 (7 lines)

```
$ command grep -rna 'ai_sandbox_require_ctx' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/ai-sandbox-stop:4:ai_sandbox_require_ctx || exit 1
bin/ai/ai-sandbox-rm:6:ai_sandbox_require_ctx || exit 1
bin/ai/ai-sandbox:9:ai_sandbox_require_ctx || exit 1
bin/ai/ai-sandbox-restart:4:ai_sandbox_require_ctx || exit 1
bin/ai/ai-sandbox-attach:6:ai_sandbox_require_ctx || exit 1
bin/ai/ai-sandbox-lib.sh:125:ai_sandbox_require_ctx() {
bin/ai/ai-sandbox-account:11:ai_sandbox_require_ctx || exit 1
```

### S3 (29 lines)

```
$ command grep -rnaE 'ai_sandbox_knowledge_(state|stamp)|ai_sandbox_require_current' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/ai-sandbox-migrate-knowledge:64:    state=$(ai_sandbox_knowledge_state "$sb")
bin/ai/ai-sandbox:31:    ai_sandbox_require_current "$AI_SANDBOX_DIR" || exit 1
bin/ai/ai-sandbox-restart:18:ai_sandbox_require_current "$AI_SANDBOX_DIR" || exit 1
bin/ai/ai-knowledge:1019:        [ "$(ai_sandbox_knowledge_state "$sb")" = current ] || continue   # stale: refused at start too
bin/ai/ai-knowledge:1054:        state=$(ai_sandbox_knowledge_state "$sb")
bin/ai/ai-knowledge:1097:        printf '%-45s %-10s %s; %s\n' "$(basename "$sb")" "$(ai_sandbox_knowledge_state "$sb")" \
bin/ai/ai-sandbox-lib.sh:85:ai_sandbox_knowledge_stamp() { ai_sandbox_env_value "$1" SANDBOX_KNOWLEDGE; }
bin/ai/ai-sandbox-lib.sh:90:ai_sandbox_knowledge_state() {
bin/ai/ai-sandbox-lib.sh:92:    stamp=$(ai_sandbox_knowledge_stamp "$1")
bin/ai/ai-sandbox-lib.sh:103:ai_sandbox_require_current() {   # <sandbox dir>
bin/ai/ai-sandbox-lib.sh:105:    state=$(ai_sandbox_knowledge_state "$1")
tests/ai-sandbox/test-knowledge.sh:348:assert_eq "stamp read" "$(ai_sandbox_knowledge_stamp "$AI_SANDBOX_ROOT/fab-a-agent")" 1
tests/ai-sandbox/test-knowledge.sh:349:assert_eq "missing stamp is empty" "$(ai_sandbox_knowledge_stamp "$AI_SANDBOX_ROOT/fab-c-agent")" ""
tests/ai-sandbox/test-knowledge.sh:350:assert_eq "stamp 1 is current when configured" "$(ai_sandbox_knowledge_state "$AI_SANDBOX_ROOT/fab-a-agent")" current
tests/ai-sandbox/test-knowledge.sh:351:assert_eq "stamp 0 is stale when configured" "$(ai_sandbox_knowledge_state "$AI_SANDBOX_ROOT/fab-b-agent")" stale
tests/ai-sandbox/test-knowledge.sh:352:assert_eq "no stamp is unstamped" "$(ai_sandbox_knowledge_state "$AI_SANDBOX_ROOT/fab-c-agent")" unstamped
tests/ai-sandbox/test-knowledge.sh:357:ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-a-agent" 2>/dev/null && r=0 || r=$?
tests/ai-sandbox/test-knowledge.sh:359:msg=$(ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-b-agent" 2>&1) && r=0 || r=$?
tests/ai-sandbox/test-knowledge.sh:365:msg=$(ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-c-agent" 2>&1) || true
tests/ai-sandbox/test-knowledge.sh:369:msg=$(ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-c-agent" 2>&1) || true
tests/ai-sandbox/test-knowledge.sh:472:assert_eq "nothing migrated on a refused run" "$(ai_sandbox_knowledge_state "$mdir2")" unstamped
tests/ai-sandbox/test-knowledge.sh:483:assert_eq "unstamped sandbox recreated from its compose mount" "$(ai_sandbox_knowledge_state "$mdir2")" current
tests/ai-sandbox/test-knowledge.sh:484:assert_eq "unstamped sandbox recreated from project-path" "$(ai_sandbox_knowledge_state "$ndir")" current
tests/ai-sandbox/test-knowledge.sh:485:assert_eq "stale sandbox recreated from its stamp" "$(ai_sandbox_knowledge_state "$sdir")" current
tests/ai-sandbox/test-knowledge.sh:486:assert_eq "failed sandbox left stale" "$(ai_sandbox_knowledge_state "$bdir")" stale
tests/ai-sandbox/test-knowledge.sh:565:assert_eq "running stale sandbox left stale" "$(ai_sandbox_knowledge_state "$rdir")" stale
tests/ai-sandbox/test-knowledge.sh:579:assert_eq "running stale sandbox recreated after y" "$(ai_sandbox_knowledge_state "$rdir")" current
tests/ai-sandbox/test-knowledge.sh:677:assert_eq "ssh remote without an agent: stale sandbox untouched" "$(ai_sandbox_knowledge_state "$sdir")" stale
tests/ai-sandbox/test-knowledge.sh:685:assert_eq "file remote: the stale sandbox is recreated" "$(ai_sandbox_knowledge_state "$sdir")" current
```

### S5 (27 lines)

```
$ command grep -rnaF '.sync-status' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/create-ai-sandbox.sh:1602:    1)     if [ -f "$HOME/knowledge/.sync-status" ]; then
bin/ai/create-ai-sandbox.sh:1603:               _age=$(( ($(date +%s) - $(stat -c %Y "$HOME/knowledge/.sync-status")) / 60 ))
bin/ai/create-ai-sandbox.sh:1604:               status "knowledge" "$(cat "$HOME/knowledge/.sync-status") [${_age} min ago]"
bin/ai/ai-knowledge:15:# written to <clone>/.sync-status, which sandbox-doctor shows.
bin/ai/ai-knowledge:30:# without this trap it would do so silently and leave a stale .sync-status behind.
bin/ai/ai-knowledge:618:    printf '%s %s%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" "${STATUS_NOTE:+; $STATUS_NOTE}" > "$CLONE/.sync-status"
bin/ai/ai-knowledge:696:# caller: every outcome is one line in .sync-status.
bin/ai/ai-knowledge:730:    grep -qx '.sync-status' "$CLONE/.git/info/exclude" 2>/dev/null \
bin/ai/ai-knowledge:731:        || printf '.sync-status\n' >> "$CLONE/.git/info/exclude"
bin/ai/ai-knowledge:1067:            status=$(cat "$sb/knowledge/.sync-status" 2>/dev/null || echo never)
bin/ai/ai-knowledge:1091:            "$project" "$sb/knowledge" "$(cat "$sb/knowledge/.sync-status" 2>/dev/null || echo never)"
bin/ai/ai-knowledge:1098:            "${project:-unknown}" "$(cat "$sb/knowledge/.sync-status" 2>/dev/null || echo never)"
tests/ai-sandbox/test-knowledge.sh:23:    sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} //' "$1/.sync-status" 2>/dev/null
tests/ai-sandbox/test-knowledge.sh:123:assert_contains "status counts the push" "$(cat "$clone/.sync-status")" "pushed 1"
tests/ai-sandbox/test-knowledge.sh:130:assert_contains "refusal names the branch" "$(cat "$clone/.sync-status")" "escape-abcd"
tests/ai-sandbox/test-knowledge.sh:131:assert_contains "malformed name refused" "$(cat "$clone/.sync-status")" "tmp-half"
tests/ai-sandbox/test-knowledge.sh:188:assert_contains "status counts the close" "$(cat "$clone/.sync-status")" "closed 1"
tests/ai-sandbox/test-knowledge.sh:264:assert_contains "offline status names the pending push" "$(cat "$clone/.sync-status")" "push"
tests/ai-sandbox/test-knowledge.sh:287:assert_contains "old-style skip names the migration" "$(cat "$mdir/knowledge/.sync-status")" "migrate-knowledge"
tests/ai-sandbox/test-knowledge.sh:830:sum_before=$(md5sum < "$AI_KNOWLEDGE_RENDER/GLOBAL.md"); rm -f "$clone/.sync-status"
tests/ai-sandbox/test-knowledge.sh:841:rm -f "$clone/.sync-status"
tests/ai-sandbox/test-knowledge.sh:1109:assert_contains "stale lease reported" "$(cat "$iclone/.sync-status")" "$rn2"
tests/ai-sandbox/test-knowledge.sh:1130:assert_eq "own report closed: no false moved note" "$(grep -c 'not closed' "$iclone/.sync-status")" 0
tests/ai-sandbox/test-knowledge.sh:1143:assert_eq "no-op integrator sync does not count fetched reports as pushed" "$(grep -c 'reports pushed' "$iclone/.sync-status")" 0
tests/ai-sandbox/test-knowledge.sh:1148:assert_contains "moved remote ref: reported" "$(cat "$iclone/.sync-status")" "${rr6#refs/reports/}"
.agents/skills/knowledge-integrate/SKILL.md:26:   is empty. If `.sync-status` in the clone says main diverged or the last sync
docs/shared-knowledge.md:248:is one line in `<clone>/.sync-status`, shown by `sandbox-doctor` and
```

### S6 (9 lines)

```
$ command grep -rnaF 'ai-knowledge-role' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/knowledge-seed/skills/propose-rule/SKILL.md:38:   `<project-id>` is the second word of `~/knowledge/.git/ai-knowledge-role`.
bin/ai/knowledge-seed/proposals/README.md:13:project_id: <slug-hash of the project checkout, from ~/knowledge/.git/ai-knowledge-role>
bin/ai/create-ai-sandbox.sh:1614:               _role=$(cut -d' ' -f1 "$HOME/knowledge/.git/ai-knowledge-role" 2>/dev/null)
bin/ai/ai-knowledge:649:role=$(cut -d' ' -f1 "$(git rev-parse --git-dir)/ai-knowledge-role" 2>/dev/null)
bin/ai/ai-knowledge:732:    printf '%s %s\n' "$role" "$id" > "$CLONE/.git/ai-knowledge-role"
tests/ai-sandbox/test-knowledge.sh:95:assert_eq "role file names the role and project id" "$(cat "$clone/.git/ai-knowledge-role")" "proposals $pid"
tests/ai-sandbox/test-knowledge.sh:163:assert_eq "integrator role file" "$(cut -d' ' -f1 "$iclone/.git/ai-knowledge-role")" integrator
tests/ai-sandbox/test-knowledge.sh:1158:assert_contains "doctor labels reports by role" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'ai-knowledge-role'
docs/shared-knowledge.md:311:host writes `.git/ai-knowledge-role` (`proposals <project-id>`) and a pre-commit
```

### S7 (23 lines)

```
$ command grep -rnaF 'SANDBOX_KNOWLEDGE' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/create-ai-sandbox.sh:1598:# SANDBOX_KNOWLEDGE comes from the sandbox's .env through compose: unset means
bin/ai/create-ai-sandbox.sh:1601:case "${SANDBOX_KNOWLEDGE-unset}" in
bin/ai/create-ai-sandbox.sh:2218:    "SANDBOX_KNOWLEDGE": "1" if os.environ.get("KNOWLEDGE") == "yes" else "0",
bin/ai/create-ai-sandbox.sh:2306:      - "SANDBOX_KNOWLEDGE=\${SANDBOX_KNOWLEDGE}"
bin/ai/ai-sandbox-lib.sh:85:ai_sandbox_knowledge_stamp() { ai_sandbox_env_value "$1" SANDBOX_KNOWLEDGE; }
tests/ai-sandbox/test-knowledge.sh:334:assert_contains "create stamps SANDBOX_KNOWLEDGE=1" "$(cat "$pdir/.env")" 'SANDBOX_KNOWLEDGE=1'
tests/ai-sandbox/test-knowledge.sh:336:assert_contains "stamp passed into the container" "$compose" 'SANDBOX_KNOWLEDGE=${SANDBOX_KNOWLEDGE}'
tests/ai-sandbox/test-knowledge.sh:344:fab fab-a "SANDBOX_KNOWLEDGE=1" "SANDBOX_PROJECT_DIR=$tmp/work/fab-a"
tests/ai-sandbox/test-knowledge.sh:345:fab fab-b "SANDBOX_KNOWLEDGE=0" "SANDBOX_PROJECT_DIR=$tmp/work/fab-b"
tests/ai-sandbox/test-knowledge.sh:381:printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$third" > "$tdir/.env"
tests/ai-sandbox/test-knowledge.sh:382:printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$proj" > "$pdir/.env.keep"; cp "$pdir/.env.keep" "$pdir/.env"
tests/ai-sandbox/test-knowledge.sh:383:printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$integ" > "$idir/.env"
tests/ai-sandbox/test-knowledge.sh:398:printf 'services: {}\n' > "$edir/docker-compose.yml"; printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$eproj" > "$edir/.env"
tests/ai-sandbox/test-knowledge.sh:423:assert_contains "doctor reads the stamp" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'SANDBOX_KNOWLEDGE'
tests/ai-sandbox/test-knowledge.sh:430:printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$stale" > "$sdir/.env"
tests/ai-sandbox/test-knowledge.sh:478:printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$bproj" > "$bdir/.env"
tests/ai-sandbox/test-knowledge.sh:508:printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$manual" > "$mdir/.env"
tests/ai-sandbox/test-knowledge.sh:557:printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$rproj" > "$rdir/.env"
tests/ai-sandbox/test-knowledge.sh:599:printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$qproj" > "$qdir/.env"
tests/ai-sandbox/test-knowledge.sh:671:printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$stale" > "$sdir/.env"
tests/ai-sandbox/test-knowledge.sh:1172:assert_contains "create stamps SANDBOX_KNOWLEDGE=0 without config" "$(cat "$(ai_sandbox_dir_for "$other")/.env")" 'SANDBOX_KNOWLEDGE=0'
PROJECT_MAP.md:24:| [bin/ai/ai-sandbox-migrate-knowledge](file:///home/jlewandowski/dev/public/dev-tools/bin/ai/ai-sandbox-migrate-knowledge) | Temporary, not installed: lists the running sandboxes and asks before stoppi
docs/shared-knowledge.md:105:Every sandbox carries a stamp in its `.env`, `SANDBOX_KNOWLEDGE=0|1`, written by
```

### S8 (16 lines)

```
$ command grep -rnaF 'migrate-knowledge' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/ai-sandbox-migrate-knowledge:2:# ai-sandbox-migrate-knowledge -- one-off repair of sandboxes created before the
bin/ai/create-ai-sandbox.sh:1623:    *)     status "knowledge" "NOT migrated: this sandbox predates the knowledge mounts; on the host run create-ai-sandbox.sh <project> (every sandbox at once: dev-tools/bin/ai/ai-sandbox
bin/ai/ai-knowledge:742:            set_status "skipped: ~/knowledge is on the old-style branch '$current'; run ai-sandbox-migrate-knowledge on the host"
bin/ai/ai-knowledge:1059:            status="not synced: unstamped; recreate it: create-ai-sandbox.sh ${hint_project:-<project dir>} (every sandbox at once: ai-sandbox-migrate-knowledge)"
bin/ai/ai-knowledge:1061:            status="not synced: $state; recreate it: create-ai-sandbox.sh $project (every sandbox at once: ai-sandbox-migrate-knowledge)"
bin/ai/ai-sandbox-lib.sh:119:        echo "    ${dev_tools:-<dev-tools checkout>}/bin/ai/ai-sandbox-migrate-knowledge"
tests/ai-sandbox/test-knowledge.sh:287:assert_contains "old-style skip names the migration" "$(cat "$mdir/knowledge/.sync-status")" "migrate-knowledge"
tests/ai-sandbox/test-knowledge.sh:361:assert_contains "refusal names the migration script" "$msg" "ai-sandbox-migrate-knowledge"
tests/ai-sandbox/test-knowledge.sh:394:assert_contains "all: stale row names the bulk script as the shortcut" "$(grep fab-b-agent "$tmp/all1.out" | tail -1)" "ai-sandbox-migrate-knowledge"
tests/ai-sandbox/test-knowledge.sh:424:assert_contains "doctor names the migration script" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'ai-sandbox-migrate-knowledge'
tests/ai-sandbox/test-knowledge.sh:441:assert_contains "ai-sandbox names the migration script" "$msg" "ai-sandbox-migrate-knowledge"
tests/ai-sandbox/test-knowledge.sh:456:migrate() { bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate-knowledge" "$@"; }
tests/ai-sandbox/test-knowledge.sh:457:assert_eq "migration script is not an installed helper" "$(ai_sandbox_helpers | grep -c migrate-knowledge)" 0
PROJECT_MAP.md:24:| [bin/ai/ai-sandbox-migrate-knowledge](file:///home/jlewandowski/dev/public/dev-tools/bin/ai/ai-sandbox-migrate-knowledge) | Temporary, not installed: lists the running sandboxes and asks before stoppi
docs/shared-knowledge.md:44:3. Run `<dev-tools>/bin/ai/ai-sandbox-migrate-knowledge` from the checkout. It
docs/shared-knowledge.md:121:<dev-tools>/bin/ai/ai-sandbox-migrate-knowledge      # stop and recreate each stale or unstamped one
```

### S9 (6 lines)

```
$ command grep -rnaF '_sync-clone' bin tests tools verify-ai-sandbox-on-host.sh .agents PROJECT_MAP.md README.md docs/shared-knowledge.md
bin/ai/ai-knowledge:1024:            rc=0; bash "$0" _sync-clone "$project" "$sb" >"$sb/.sync-output.$$" 2>&1 || rc=$?
bin/ai/ai-knowledge:1232:    _sync-clone) shift; cmd_sync_clone "$@" ;;
tests/ai-sandbox/test-knowledge.sh:372:# --- _sync-clone syncs one clone and never renders (phase 2)
tests/ai-sandbox/test-knowledge.sh:373:knowledge _sync-clone "$proj" "$pdir" >"$tmp/one.out" 2>&1 || cat "$tmp/one.out"
tests/ai-sandbox/test-knowledge.sh:374:assert_status "_sync-clone leaves the clone ok" "$clone" "ok:"
tests/ai-sandbox/test-knowledge.sh:375:assert_eq "_sync-clone does not render" "$(grep -c 'rendered' "$tmp/one.out")" 0
```

### S10 (2 lines)

```
$ command grep -rnaF 'rev-parse --show-toplevel' bin tools
bin/ai/ai-delegate:28:top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ai-delegate: not inside a git repository" >&2; exit 2; }
bin/ai/ai-sandbox-lib.sh:55:        if top=$(git rev-parse --show-toplevel 2>/dev/null); then
```

### S11 (4 lines)

```
$ command grep -rnaE 'PROPOSAL_RE=|REPORT_RE=|first-parent' bin
bin/ai/ai-knowledge:623:# origin/main's first-parent chain. An ours-merge puts the tip on the second
bin/ai/ai-knowledge:629:    if grep -qxF "$1" <<<"$(git -C "$CLONE" rev-list --first-parent origin/main)"; then return 1; fi
bin/ai/ai-knowledge:633:PROPOSAL_RE='^proposal/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+-[0-9a-f]{4}$'
bin/ai/ai-knowledge:637:REPORT_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+-[0-9a-f]{4}$'
```

### S12 (2 lines; `~/knowledge` is this sandbox's knowledge clone, its `main` current with the remote at the last sync, 2026-11-11T08:56)

```
$ command grep -rnaE 'sync-status|ai-knowledge-role|knowledge/\.git' /home/jlewandowski/knowledge --exclude-dir=.git
/home/jlewandowski/knowledge/skills/propose-rule/SKILL.md:38:   `<project-id>` is the second word of `~/knowledge/.git/ai-knowledge-role`.
/home/jlewandowski/knowledge/proposals/README.md:13:project_id: <slug-hash of the project checkout, from ~/knowledge/.git/ai-knowledge-role>
```

### S13 (20 lines)

```
$ command grep -rnaE '(^|[^_a-z])git_net ' bin/ai
bin/ai/ai-knowledge:96:# The caller ignores the result: git_net runs either way and reports as before.
bin/ai/ai-knowledge:109:    out=$(git_net ls-remote -q "$url" HEAD 2>&1) || rc=$?
bin/ai/ai-knowledge:145:    rc=0; git_net ls-remote -q "$url" HEAD >/dev/null 2>&1 || rc=$?
bin/ai/ai-knowledge:211:        rc=0; out=$(git_net clone -q "$remote" "$KNOWLEDGE_MAIN" 2>&1) || rc=$?
bin/ai/ai-knowledge:224:        rc=0; out=$(git_net -C "$KNOWLEDGE_MAIN" fetch -q --prune origin 2>&1) || rc=$?
bin/ai/ai-knowledge:290:        out=$(git_net -C "$KNOWLEDGE_MAIN" push -q origin "$commit:refs/heads/main" 2>&1) || rc=$?
bin/ai/ai-knowledge:369:    out=$(git_net -C "$KNOWLEDGE_MAIN" push -q -u origin main 2>&1) || rc=$?
bin/ai/ai-knowledge:411:    out=$(git_net -C "$KNOWLEDGE_MAIN" fetch -q --prune origin 2>&1) || rc=$?
bin/ai/ai-knowledge:715:        rc=0; out=$(git_net clone -q "$REMOTE" "$CLONE" 2>&1) || rc=$?
bin/ai/ai-knowledge:746:    rc=0; out=$(git_net -C "$CLONE" fetch -q --prune origin 2>&1) || rc=$?
bin/ai/ai-knowledge:756:            git_net -C "$CLONE" fetch -q origin 'refs/heads/proposal/*:refs/heads/proposal/*' >/dev/null 2>&1 || true
bin/ai/ai-knowledge:806:        rc=0; out=$(git_net -C "$CLONE" push -q origin "$b:refs/heads/$b" 2>&1) || rc=$?
bin/ai/ai-knowledge:820:            rc=0; out=$(git_net -C "$CLONE" push -q origin main 2>&1) || rc=$?
bin/ai/ai-knowledge:846:            out=$(git_net -C "$CLONE" push -q "--force-with-lease=refs/heads/$b:$tip" origin ":refs/heads/$b" 2>&1) \
bin/ai/ai-knowledge:860:        rremote=$(git_net -C "$CLONE" ls-remote origin 'refs/reports/*' 2>/dev/null) || rremote=""
bin/ai/ai-knowledge:883:        rc=0; out=$(git_net -C "$CLONE" push -q origin "$rref:$rref" 2>&1) || rc=$?
bin/ai/ai-knowledge:900:            rc=0; out=$(git_net -C "$CLONE" push -q "--force-with-lease=refs/reports/$rname:$rtip" origin ":refs/reports/$rname" 2>&1) || rc=$?
bin/ai/ai-knowledge:907:                        if git_net -C "$CLONE" ls-remote origin "refs/reports/$rname" 2>/dev/null | grep -q .; then
bin/ai/ai-knowledge:916:        git_net -C "$CLONE" fetch -q origin 'refs/reports/*:refs/reports/*' >/dev/null 2>&1 || true
bin/ai/ai-knowledge:1220:        out=$(git_net -C "$repo" push -q origin "$branch:refs/heads/$branch" 2>&1) || rc=$?
```

### S14 (86 lines)

```
$ command grep -rnaE '\$CLONE|\$sb/knowledge|\$iclone' bin/ai
bin/ai/ai-sandbox-migrate-knowledge:207:        c="$sb/knowledge"; [ -d "$c/.git" ] || continue
bin/ai/ai-sandbox-migrate-knowledge:286:        c="$sb/knowledge"; [ -d "$c/.git" ] || continue
bin/ai/ai-sandbox-migrate-knowledge:326:    [ -d "$iclone/.git" ] || { BRANCH_FAILED+=("no integrator clone at $iclone; old branches kept on the remote"); return 1; }
bin/ai/ai-sandbox-migrate-knowledge:327:    [ "$(git -C "$iclone" branch --show-current)" = main ] || { BRANCH_FAILED+=("integrator clone $iclone is not on main; old branches kept on the remote"); return 1; }
bin/ai/ai-sandbox-migrate-knowledge:328:    [ -z "$(git -C "$iclone" status --porcelain)" ] || { BRANCH_FAILED+=("integrator clone $iclone has uncommitted changes; old branches kept on the remote"); return 1; }
bin/ai/ai-sandbox-migrate-knowledge:329:    gnet -C "$iclone" fetch -q origin 2>/dev/null || true
bin/ai/ai-sandbox-migrate-knowledge:335:                tip=$(git -C "$iclone" rev-parse "origin/$b")
bin/ai/ai-sandbox-migrate-knowledge:336:                git -C "$iclone" merge -q -s ours --no-ff -m "close legacy branch $b (its proposals are proposal/* branches now)" "$tip" \
bin/ai/ai-sandbox-migrate-knowledge:338:                gnet -C "$iclone" push -q origin main || { BRANCH_FAILED+=("cannot push main; $b kept"); continue; }
bin/ai/ai-sandbox-migrate-knowledge:341:                if gnet -C "$iclone" push -q "--force-with-lease=refs/heads/$b:$tip" origin ":refs/heads/$b" 2>/dev/null; then
bin/ai/ai-sandbox-migrate-knowledge:342:                    git -C "$iclone" branch -q -D "$b" 2>/dev/null || true
bin/ai/ai-knowledge:280:        if [ -d "$iclone/.git" ] && git -C "$iclone" merge-base --is-ancestor origin/main main 2>/dev/null \
bin/ai/ai-knowledge:281:           && [ "$(git -C "$iclone" rev-parse main)" != "$(git -C "$iclone" rev-parse origin/main)" ]; then
bin/ai/ai-knowledge:282:            warn "the integrator clone $iclone has commits on main that are not on origin/main yet; the record is skipped so that main does not diverge."
bin/ai/ai-knowledge:618:    printf '%s %s%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" "${STATUS_NOTE:+; $STATUS_NOTE}" > "$CLONE/.sync-status"
bin/ai/ai-knowledge:627:    git -C "$CLONE" show-ref -q --verify refs/remotes/origin/main || return 2
bin/ai/ai-knowledge:628:    git -C "$CLONE" merge-base --is-ancestor "$1" origin/main 2>/dev/null || return 2
bin/ai/ai-knowledge:629:    if grep -qxF "$1" <<<"$(git -C "$CLONE" rev-list --first-parent origin/main)"; then return 1; fi
bin/ai/ai-knowledge:707:    CLONE="$sb/knowledge"; STATUS_NOTE=""
bin/ai/ai-knowledge:709:    if [ ! -d "$CLONE/.git" ]; then
bin/ai/ai-knowledge:710:        aside=$(move_aside "$CLONE")
bin/ai/ai-knowledge:712:            warn "$CLONE was not a git checkout; moved it to $aside"
bin/ai/ai-knowledge:713:            STATUS_NOTE="the previous $(basename "$CLONE") was not a clone and was moved to $(basename "$aside")"
bin/ai/ai-knowledge:715:        rc=0; out=$(git_net clone -q "$REMOTE" "$CLONE" 2>&1) || rc=$?
bin/ai/ai-knowledge:718:            warn "cannot clone $REMOTE into $CLONE: $NET_REASON"
bin/ai/ai-knowledge:719:            HINT_FETCH+=("$(hint git clone "$REMOTE" "$CLONE")")
bin/ai/ai-knowledge:722:        log "cloned $REMOTE -> $CLONE"
bin/ai/ai-knowledge:726:    if ! git -C "$CLONE" rev-parse -q --verify HEAD >/dev/null 2>&1 \
bin/ai/ai-knowledge:727:       && git -C "$CLONE" show-ref -q --verify refs/remotes/origin/main; then
bin/ai/ai-knowledge:728:        git -C "$CLONE" checkout -q -B main origin/main || warn "cannot put $CLONE on main"
bin/ai/ai-knowledge:730:    grep -qx '.sync-status' "$CLONE/.git/info/exclude" 2>/dev/null \
bin/ai/ai-knowledge:731:        || printf '.sync-status\n' >> "$CLONE/.git/info/exclude"
bin/ai/ai-knowledge:732:    printf '%s %s\n' "$role" "$id" > "$CLONE/.git/ai-knowledge-role"
bin/ai/ai-knowledge:733:    install_hook "$CLONE"
bin/ai/ai-knowledge:735:    if [ -n "$(git -C "$CLONE" status --porcelain)" ]; then
bin/ai/ai-knowledge:739:    current=$(git -C "$CLONE" branch --show-current)
bin/ai/ai-knowledge:746:    rc=0; out=$(git_net -C "$CLONE" fetch -q --prune origin 2>&1) || rc=$?
bin/ai/ai-knowledge:749:        HINT_FETCH+=("$(hint git -C "$CLONE" fetch --prune origin)")
bin/ai/ai-knowledge:756:            git_net -C "$CLONE" fetch -q origin 'refs/heads/proposal/*:refs/heads/proposal/*' >/dev/null 2>&1 || true
bin/ai/ai-knowledge:758:            HINT_FETCH+=("$(hint git -C "$CLONE" fetch origin 'refs/heads/proposal/*:refs/heads/proposal/*')")
bin/ai/ai-knowledge:761:    ff_main "$CLONE" "$current" "$role" || main_state=diverged
bin/ai/ai-knowledge:765:        out=$(git -C "$CLONE" ls-tree -r --name-only main -- proposals/ 2>/dev/null \
bin/ai/ai-knowledge:776:        tip=$(git -C "$CLONE" rev-parse "$b")
bin/ai/ai-knowledge:782:            0)  if [ "$current" = "$b" ]; then git -C "$CLONE" checkout -q main; current=main; fi
bin/ai/ai-knowledge:783:                git -C "$CLONE" branch -q -D "$b"
bin/ai/ai-knowledge:790:        rc=0; out=$(git -C "$CLONE" diff --name-only --no-renames "origin/main...$b" 2>/dev/null) || rc=$?
bin/ai/ai-knowledge:798:        remote_tip=$(git -C "$CLONE" rev-parse -q --verify "refs/remotes/origin/$b" 2>/dev/null || true)
bin/ai/ai-knowledge:800:        if [ -n "$remote_tip" ] && ! git -C "$CLONE" merge-base --is-ancestor "$remote_tip" "$b"; then
bin/ai/ai-knowledge:804:            HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$b:refs/heads/$b")"); pending=$((pending + 1)); continue
bin/ai/ai-knowledge:806:        rc=0; out=$(git_net -C "$CLONE" push -q origin "$b:refs/heads/$b" 2>&1) || rc=$?
bin/ai/ai-knowledge:808:            net_failed "$rc" "$out"; HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$b:refs/heads/$b")")
bin/ai/ai-knowledge:812:    done < <(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*')
bin/ai/ai-knowledge:816:       && [ "$(git -C "$CLONE" rev-parse main)" != "$(git -C "$CLONE" rev-parse -q --verify origin/main 2>/dev/null || true)" ]; then
bin/ai/ai-knowledge:818:            HINT_PUSH+=("$(hint git -C "$CLONE" push origin main)"); main_note="main pending"
bin/ai/ai-knowledge:820:            rc=0; out=$(git_net -C "$CLONE" push -q origin main 2>&1) || rc=$?
bin/ai/ai-knowledge:822:            else net_failed "$rc" "$out"; HINT_PUSH+=("$(hint git -C "$CLONE" push origin main)"); main_note="main push failed"
bin/ai/ai-knowledge:835:            tip_state "$(git -C "$CLONE" rev-parse "$b")" && st=0 || st=$?
bin/ai/ai-knowledge:837:            if [ "$current" = "$b" ]; then git -C "$CLONE" checkout -q main; current=main; fi
bin/ai/ai-knowledge:838:            git -C "$CLONE" branch -q -D "$b"; closed=$((closed + 1))
bin/ai/ai-knowledge:839:        done < <(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*')
bin/ai/ai-knowledge:842:            tip=$(git -C "$CLONE" rev-parse "refs/remotes/$b")
bin/ai/ai-knowledge:846:            out=$(git_net -C "$CLONE" push -q "--force-with-lease=refs/heads/$b:$tip" origin ":refs/heads/$b" 2>&1) \
bin/ai/ai-knowledge:848:        done < <(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/remotes/origin/proposal/*')
bin/ai/ai-knowledge:860:        rremote=$(git_net -C "$CLONE" ls-remote origin 'refs/reports/*' 2>/dev/null) || rremote=""
bin/ai/ai-knowledge:865:        if [ "$role" = integrator ] && git -C "$CLONE" show-ref -q --verify "refs/reports-closed/$rname"; then continue; fi
bin/ai/ai-knowledge:869:        rtip=$(git -C "$CLONE" rev-parse -q --verify "$rref^{commit}" 2>/dev/null || true)
bin/ai/ai-knowledge:871:        rc=0; out=$(git -C "$CLONE" diff --name-only --no-renames "origin/main...$rtip" 2>/dev/null) || rc=$?
bin/ai/ai-knowledge:881:            HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$rref:$rref")"); pending=$((pending + 1)); continue
bin/ai/ai-knowledge:883:        rc=0; out=$(git_net -C "$CLONE" push -q origin "$rref:$rref" 2>&1) || rc=$?
bin/ai/ai-knowledge:885:            net_failed "$rc" "$out"; HINT_PUSH+=("$(hint git -C "$CLONE" push origin "$rref:$rref")")
bin/ai/ai-knowledge:889:        [ "$role" = integrator ] || git -C "$CLONE" update-ref -d "$rref"
bin/ai/ai-knowledge:890:    done < <(git -C "$CLONE" for-each-ref --format='%(refname)' 'refs/reports/*')
bin/ai/ai-knowledge:899:            rtip=$(git -C "$CLONE" rev-parse "$rref")
bin/ai/ai-knowledge:900:            rc=0; out=$(git_net -C "$CLONE" push -q "--force-with-lease=refs/reports/$rname:$rtip" origin ":refs/reports/$rname" 2>&1) || rc=$?
bin/ai/ai-knowledge:907:                        if git_net -C "$CLONE" ls-remote origin "refs/reports/$rname" 2>/dev/null | grep -q .; then
bin/ai/ai-knowledge:913:            git -C "$CLONE" update-ref -d "refs/reports/$rname"
bin/ai/ai-knowledge:914:            git -C "$CLONE" update-ref -d "$rref"
bin/ai/ai-knowledge:915:        done < <(git -C "$CLONE" for-each-ref --format='%(refname)' 'refs/reports-closed/*')
bin/ai/ai-knowledge:916:        git_net -C "$CLONE" fetch -q origin 'refs/reports/*:refs/reports/*' >/dev/null 2>&1 || true
bin/ai/ai-knowledge:918:        HINT_FETCH+=("$(hint git -C "$CLONE" fetch origin 'refs/reports/*:refs/reports/*')")
bin/ai/ai-knowledge:953:        CLONE="$sb/knowledge"; STATUS_NOTE=""
bin/ai/ai-knowledge:954:        if [ -d "$CLONE/.git" ]; then set_status "skipped: lock busy; another ai-knowledge is syncing this clone"
bin/ai/ai-knowledge:955:        else warn "skipped $CLONE: lock busy; another ai-knowledge is syncing it"; fi
bin/ai/ai-knowledge:1067:            status=$(cat "$sb/knowledge/.sync-status" 2>/dev/null || echo never)
bin/ai/ai-knowledge:1091:            "$project" "$sb/knowledge" "$(cat "$sb/knowledge/.sync-status" 2>/dev/null || echo never)"
bin/ai/ai-knowledge:1098:            "${project:-unknown}" "$(cat "$sb/knowledge/.sync-status" 2>/dev/null || echo never)"
```

### S15 (0 lines)

```
$ command grep -rnaE 'subprocess|os\.system|popen|Popen' tools --include=*.py
```

### S16 (10 lines)

```
$ command grep -rlaE 'sync-status|migrate-knowledge|ai-knowledge-role|SANDBOX_KNOWLEDGE' docs
docs/superpowers/specs/2026-10-30-sandbox-supervisor-design.md
docs/superpowers/specs/2026-10-02-ai-sandbox-build-caches-design.md
docs/superpowers/specs/2026-11-11-sandbox-hardening-design.md
docs/superpowers/specs/2026-09-18-shared-knowledge-v2-design.md
docs/superpowers/specs/2026-09-14-shared-knowledge-design.md
docs/superpowers/specs/2026-11-09-report-sync-brief.md
docs/superpowers/specs/2026-11-09-ui-prototype-track-design.md
docs/superpowers/evidence/2026-11-09-report-sync-review.md
docs/superpowers/evidence/2026-11-09-report-sync.md
docs/shared-knowledge.md
```

### S17 (42 lines)

```
$ command grep -rnaF 'knowledge' bin/ai/create-ai-sandbox.sh
175:  ai-knowledge          init <url> [--integrator DIR] | sync | render | status |
176:                        proposals -- the shared knowledge repository (global
178:                        proposed to through the sandbox's clone at ~/knowledge
205:Shared knowledge (optional): after 'ai-knowledge init <private-git-url>
209:gets its own clone at ~/knowledge with main checked out; the 'propose-rule'
211:pushes it on the next sandbox start or 'ai-knowledge sync --all'. A
955:# Shared knowledge repository: when configured, the rendered main branch is what
959:if ai_knowledge_configured; then
960:    step "Shared knowledge repository"
961:    "$SCRIPT_DIR/ai-knowledge" sync "$PROJECT_ABS_DIR" || warn "knowledge sync reported a problem; see above"
1050:Shared knowledge: the global rules and roles you read are rendered read-only from
1051:a private git repository. Your own clone of it is at ~/knowledge with main checked
1055:\`ai-knowledge sync --all\`) and the integrator sandbox, which commits on main,
1056:decides with the \`knowledge-integrate\` skill. \`sandbox-doctor\` shows what is
1102:    # The rules file is rendered from the knowledge repository. The block lives
1105:    "$SCRIPT_DIR/ai-knowledge" render >/dev/null || warn "knowledge render failed; see above"
1497:# read_file(<dir>) lets agy read the shared knowledge clone outside its workspace; a
1503:GRANTS.append("read_file(%s)" % os.path.expanduser("~/knowledge"))
1599:# the compose file predates the knowledge mounts and the host refuses to start
1602:    1)     if [ -f "$HOME/knowledge/.sync-status" ]; then
1603:               _age=$(( ($(date +%s) - $(stat -c %Y "$HOME/knowledge/.sync-status")) / 60 ))
1604:               status "knowledge" "$(cat "$HOME/knowledge/.sync-status") [${_age} min ago]"
1606:               for _b in $(git -C "$HOME/knowledge" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' 2>/dev/null); do
1607:                   if [ "$(git -C "$HOME/knowledge" rev-parse -q --verify "refs/remotes/origin/$_b" 2>/dev/null)" = "$(git -C "$HOME/knowledge" rev-parse "$_b" 2>/dev/null)" ]; then
1614:               _role=$(cut -d' ' -f1 "$HOME/knowledge/.git/ai-knowledge-role" 2>/dev/null)
1615:               for _b in $(git -C "$HOME/knowledge" for-each-ref --format='%(refname)' 'refs/reports/*' 2>/dev/null); do
1620:               status "knowledge" "configured; clone not synced yet (host: ai-knowledge sync)"
1622:    0)     status "knowledge" "not configured on the host (host: ai-knowledge init <url>)" ;;
1623:    *)     status "knowledge" "NOT migrated: this sandbox predates the knowledge mounts; on the host run create-ai-sandbox.sh <project> (every sandbox at once: dev-tools/bin/ai/ai-sandbox-migrate-knowledge)" ;;
2215:    # The knowledge stamp: the start scripts refuse a sandbox whose stamp does
2361:      # Shared knowledge: the rendered main branch of the knowledge repository,
2363:      - "${SHARED_DIR}/knowledge/GLOBAL.md:${CONTAINER_HOME}/.gemini/GEMINI.md:ro"
2364:      - "${SHARED_DIR}/knowledge/GLOBAL.md:${CONTAINER_HOME}/.claude/CLAUDE.md:ro"
2365:      - "${SHARED_DIR}/knowledge/GLOBAL.md:${CONTAINER_HOME}/.codex/AGENTS.md:ro"
2366:      - "${SHARED_DIR}/knowledge/claude/agents:${CONTAINER_HOME}/.claude/agents:ro"
2367:      - "${SHARED_DIR}/knowledge/gemini/agents:${CONTAINER_HOME}/.gemini/agents:ro"
2368:      - "${SHARED_DIR}/knowledge/codex/agents:${CONTAINER_HOME}/.codex/agents:ro"
2369:      # This sandbox's own clone of the knowledge repository, read-write, on its
2372:      - "${SANDBOX_DIR}/knowledge:${CONTAINER_HOME}/knowledge"
2715:# The knowledge seed travels with the helper, so 'ai-knowledge init' on a fresh
2717:rsync -a --delete "$SCRIPT_DIR/knowledge-seed/" "$AI_SANDBOX_ROOT/bin/knowledge-seed/"
2848:    BRAIN_SUMMARY="$AI_KNOWLEDGE_RENDER/GLOBAL.md  (rendered from the knowledge repository; ~/knowledge is this sandbox's clone)"
```

### S18 (9 lines)

```
$ command grep -rnaE 'ai_sandbox_state_dirs|prepare_targets|link_skills_into' bin tests
bin/ai/create-ai-sandbox.sh:456:# would make a missing one root-owned. The list is ai_sandbox_state_dirs in
bin/ai/create-ai-sandbox.sh:461:done < <(ai_sandbox_state_dirs)
bin/ai/ai-knowledge:577:    link_skills_into "$HOME"
bin/ai/ai-knowledge:585:link_skills_into() {
bin/ai/ai-knowledge:602:prepare_targets() {
bin/ai/ai-knowledge:958:    prepare_targets "$sb"
bin/ai/ai-knowledge:959:    link_skills_into "$sb"
bin/ai/ai-sandbox-lib.sh:362:ai_sandbox_state_dirs() {
bin/ai/ai-sandbox-account:93:    done < <(ai_sandbox_state_dirs)
```

### S19 (32 lines)

```
$ command grep -naE '\b(sync_clone|tip_state|ff_main|install_hook|set_status|record_integrator|sync_project_clone|cmd_sync_clone|move_aside)\b' bin/ai/ai-knowledge
176:move_aside() {   # <path>
209:        aside=$(move_aside "$KNOWLEDGE_MAIN")
239:    record_integrator
266:record_integrator() {
617:set_status() {
626:tip_state() {   # <tip>
642:install_hook() {   # <clone>
679:ff_main() {   # <clone> <current branch> <role>
699:# local proposal/* branch as malformed, closed (tip_state), empty, or open ->
703:sync_clone() {
710:        aside=$(move_aside "$CLONE")
733:    install_hook "$CLONE"
736:        set_status "skipped: uncommitted changes in ~/knowledge; commit them and sync again"
742:            set_status "skipped: ~/knowledge is on the old-style branch '$current'; run ai-sandbox-migrate-knowledge on the host"
761:    ff_main "$CLONE" "$current" "$role" || main_state=diverged
780:        tip_state "$tip" && st=0 || st=$?
835:            tip_state "$(git -C "$CLONE" rev-parse "$b")" && st=0 || st=$?
843:            tip_state "$tip" && st=0 || st=$?
922:        set_status "refused: not pushed:$refused; fix or delete those branches"
924:        set_status "conflict: remote has commits these branches lack:$conflicts; merge origin/<branch> inside the sandbox"
929:            set_status "diverged: main has local commits and origin/main moved on; merge it inside the sandbox: git -C ~/knowledge merge origin/main (the next sync pushes the result); pushed $pushed"
931:            set_status "diverged: main has local commits (only the integrator commits on main); keep them on a proposal branch first: git -C ~/knowledge branch proposal/tmp-<slug> main, then git -C ~/knowledge reset 
934:        set_status "offline: cannot reach $REMOTE; pending push: $pending branch(es)${main_note:+, $main_note} (see the commands below)"
936:        set_status "push failed: $NET_REASON (${main_note:+$main_note}${pushfail:+; branches:$pushfail})"
938:        set_status "ok: main current${main_note:+, $main_note}; pushed $pushed; closed $closed$([ "$empty" -eq 0 ] || printf '; empty %d' "$empty")$([ "$rpushed" -eq 0 ] || printf '; reports pushed %d' "$rpushed")"
948:sync_project_clone() {   # <project dir> <sandbox dir>
954:        if [ -d "$CLONE/.git" ]; then set_status "skipped: lock busy; another ai-knowledge is syncing this clone"
960:    sync_clone "$sb" "$id" "$role"
965:cmd_sync_clone() {   # <project dir> [sandbox dir]
971:    sync_project_clone "$project" "$sb"
993:    sync_project_clone "$project" "$sb"
1232:    _sync-clone) shift; cmd_sync_clone "$@" ;;
```

### S20 (0 lines)

```
$ command grep -rnaE 'run/ai-sandbox|knowledge-origin|refs/sandbox/|sandbox-knowledge-sync|refs/origin-reports|ai_sandbox_confined_git|ai_sandbox_host_git|ai_sandbox_image_name' bin tests tools .agents PROJECT_MAP.md
```

### S21 (7 lines; the 3 hits in an ignored `tools/context_statusline/__pycache__/*.pyc` copy are left out below)

```
$ command grep -rnaF 'reads-outside:' bin tools tests
bin/ai/ai-knowledge:634:# reads-outside: refs/reports/<name> and refs/reports-closed/<name> of the private
tools/context_statusline/statusline.py:10:# reads-outside: Claude Code 2.1.312 status line JSON on stdin
tools/context_statusline/statusline.py:15:# reads-outside: Claude Code 2.1.312 subagent transcripts under
tools/context_statusline/statusline.py:22:# reads-outside: the handover mark, dirname(transcript_path)/<session_id>/
```

### S22 (2 lines)

```
$ command grep -rnaE 'IMAGE_NAME=|ai-sandbox:\$\{?IMAGE_VARIANT|-u\$\{?HOST_UID' bin/ai
bin/ai/create-ai-sandbox.sh:529:IMAGE_NAME="ai-sandbox:${IMAGE_VARIANT}-u${HOST_UID}"
bin/ai/create-ai-sandbox.sh:530:IMAGE_STAMP="$IMAGE_DIR/${IMAGE_VARIANT}-u${HOST_UID}.stamp"
```

### S20b (0 lines; the names added in round 1 with those of S20)

```
$ command grep -rnaE 'run/ai-sandbox|knowledge-origin|refs/sandbox/|sandbox-knowledge-sync|refs/origin-reports|refs/pushed-reports|ai_sandbox_confined_git|ai_sandbox_host_git|ai_sandbox_image_name|ai_sandbox_writable_path|AI_SANDBOX_GIT_TIMEOUT|ai_sandbox_create_root' bin tests tools .agents PROJECT_MAP.md
```

### S23 (5 lines)

```
$ command grep -rnaF 'ai_sandbox_helpers' bin tests tools PROJECT_MAP.md docs/shared-knowledge.md
bin/ai/create-ai-sandbox.sh:2712:done < <(ai_sandbox_helpers)
bin/ai/ai-sandbox-migrate:36:        done < <(ai_sandbox_helpers)
bin/ai/ai-sandbox-lib.sh:203:ai_sandbox_helpers() {
tests/ai-sandbox/test-knowledge.sh:16:assert_contains "ai-knowledge is an installed helper" "$(ai_sandbox_helpers)" "ai-knowledge"
tests/ai-sandbox/test-knowledge.sh:457:assert_eq "migration script is not an installed helper" "$(ai_sandbox_helpers | grep -c migrate-knowledge)" 0
```

`ai-delegate` is the list's last entry (`ai-sandbox-lib.sh:216`); `tests/ai-sandbox/test-helpers.sh:17`
asserts an installed copy for each listed helper, so it follows the list.

### S24 (28 lines: R10 on the base)

```
$ command grep -naE '\b(git|git_net|ai_sandbox_host_git)\b[^#]*[[:space:]"'"'"'](origin/[A-Za-z$"]|main([[:space:]"'"'"':.]|$))' bin/ai/ai-knowledge | cut -d: -f1
233 237 269 280 281 292 314 369 420 421 628 629 684 687 689 691 728 765 790 816 818 820 822 871 929 931 1120 1187
```

Three of them are `hint git` lines (421, 818, 822), 929 and 931 are status text, 237
gives only a branch name to `checkout`; the other 22 name a revision by its short name
(233 and 728 as the start point of `checkout -B`). Known
case: a four-line scratch file with `merge --ff-only origin/main`, `show origin/main:README.md`,
`merge --ff-only refs/remotes/origin/main` and `checkout -q main` gave lines 1, 2 and 4.

Round 3 review: R10 also names `bin/ai/ai-sandbox-lib.sh`, where the confined fetch
lands (T09). The same pattern over that file on the base gives no line:

```
$ command grep -naE '\b(git|git_net|ai_sandbox_host_git)\b[^#]*[[:space:]"'"'"'](origin/[A-Za-z$"]|main([[:space:]"'"'"':.]|$))' bin/ai/ai-sandbox-lib.sh
```

### S25 (0 lines: R11 on the base)

```
$ command grep -naE '\b(git|git_net|ai_sandbox_host_git)\b[^#]*[[:space:]]push([[:space:]]|$)' bin/ai/ai-knowledge bin/ai/ai-sandbox-lib.sh | command grep -E -- '--force([^-]|$)|--mirror|[[:space:]]-f([[:space:]]|$)|[[:space:]]"?\+(refs|[$A-Za-z])'
```

Known case: a four-line scratch file with a push of `"+$b:refs/heads/$b"`, one with
`--force`, one with `-f` and one with `--force-with-lease=a:b` gave 3, the leased one
excluded.

### S20c (0 lines; the names added in round 3)

```
$ command grep -rnaE 'closed-report|ai_sandbox_confined_fetch' bin tests tools .agents PROJECT_MAP.md
```

Known case: a two-line scratch file holding `closed-report=x` and
`ai_sandbox_confined_fetch a` gave lines 1 and 2.

### S26 (0 lines: the `FETCH_HEAD` part of R10 on the base)

```
$ command grep -rnaF 'FETCH_HEAD' bin/ai
```

Known case: a three-line scratch file with `merge --ff-only FETCH_HEAD`,
`rev-parse FETCH_HEAD` and `fetch origin main` gave lines 1 and 2.

## Amendments after implementation (2026-11-12, Bartek)

### Probe: RP1 range after a merge (item 7)

A scratch repository (git 2.34.1): a base commit on `main`; branch `p1` changes line 1
of a file; `main` changes the same line; `p1` merges `main` with a conflict, resolved by
hand, and commits. Then `B=$(git merge-base main p1)` is `main`'s tip, and
`git --no-pager log --reverse -p --no-ext-diff --no-textconv $B..p1 -- f` lists `p1`'s
commit with its diff and the merge commit with no diff; the same with `--cc` adds the
merge's combined diff (`- a1`, ` -a2`, `++a12`), the hand resolution. `main`'s own
commit is in neither listing. Hence RP1's range from `merge-base main <tip>` and its
`--cc`.
