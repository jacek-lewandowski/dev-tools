#!/usr/bin/env bash
# split-create.sh <tree>
#
# Phase 3 mechanical split of <tree>/bin/ai/create-ai-sandbox.sh into the entry's
# remaining text, the eleven modules of bin/ai/create.d/ (each run of code wrapped
# as a stage function, bodies byte for byte) and the build-context heredocs as
# files under bin/ai/image/. Moves ai-delegate and sandbox-knowledge-sync into
# image/ and rewrites their literal old paths in the tree's text files.
# Deterministic, no git needed. It does not make the result run: the entry's
# sourcing lines and stage calls and the doctor's fill are hand edits (T04).
# The stage tail report (stderr) names, per stage, its last statement, so a stage
# whose last statement is an '&&' list is closed with 'return 0' (base status).
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <tree>" >&2; exit 2; }
umask 022
python3 -I - "$1" <<'PY'
import os, re, shutil, sys

tree = sys.argv[1]
ai = os.path.join(tree, 'bin/ai')
src = os.path.join(ai, 'create-ai-sandbox.sh')
L = open(src, encoding='utf-8').read().split('\n')
if L[-1] == '':
    L.pop()                     # the file's final newline
N = len(L)

def find(text):   # the first line equal to text
    hits = [i for i, l in enumerate(L) if l == text]
    if not hits:
        sys.exit('anchor not found: %r' % text)
    return hits[0]

def unique(text, startswith=False):
    hits = [i for i, l in enumerate(L) if (l.startswith(text) if startswith else l == text)]
    if len(hits) != 1:
        sys.exit('anchor %r found %d times' % (text, len(hits)))
    return hits[0]

def banner(title):
    i = unique('# ' + title)
    if not L[i - 1].startswith('# ------'):
        sys.exit('no dash line above %r' % title)
    return i - 1

# ---- cuts: (start line index, kind, module, stage); the segment runs to the next cut
# kind: 'entry' | 'top' (module top level) | 'stage' (wrapped as a function)
cuts = [
    (0, 'entry', None, None),
    (unique('readonly MARKER_BEGIN', True), 'top', 'rules', None),
    (unique('readonly BASHRC_BEGIN', True), 'top', 'install', None),
    (unique('# Pinned upstream versions. Bump deliberately; do not float.'), 'top', 'image', None),
    (unique('# Resource limits for the container. Docker imposes none by default, so a'), 'top', 'resources', None),
    (unique("# The host's IntelliJ IDEA installation. Mounted read-only when it exists, so"), 'entry', None, None),
    (unique("readonly SHM_SIZE='1gb'"), 'top', 'resources', None),
    (banner('Options'), 'entry', None, None),
    (unique('usage() {'), 'top', 'options', None),
    (find('for arg in "$@"; do'), 'stage', 'options', 'options_parse'),
    (banner('Small helpers'), 'top', 'project', None),
    (banner('Host prerequisites'), 'stage', 'project', 'project_prerequisites'),
    (banner("Resolve this script's own location, so we can find both the dev-tools repo"), 'entry', None, None),
    (unique('DEV_TOOLS_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)'), 'devtools', None, None),
    (unique('# Identity and path helpers, shared with the ai-sandbox-* commands so the two'), 'entry', None, None),
    (unique('# Checked here, not with the other options above, because the rule for a'), 'stage', 'options', 'options_check_memory'),
    (unique("# The host's memory budget gates every run, --no-start included, before"), 'stage', 'resources', 'resources_budget_gate'),
    (banner('Resolve the project'), 'stage', 'project', 'project_resolve'),
    (banner('Display mode'), 'stage', 'options', 'options_remembered'),
    (banner('Memory'), 'stage', 'options', 'options_remembered_memory'),
    (unique('readonly MEMORY_GB'), 'stage', 'resources', 'resources_limits'),
    (unique('if [ "$WITH_DOCKER" = "yes" ]; then IMAGE_VARIANT="docker"; else IMAGE_VARIANT="base"; fi'), 'stage', 'image', 'image_name'),
    (unique('if [ "$DISPLAY_MODE_EXPLICIT" = "no" ] && [ -f "$ENV_FILE" ]; then'), 'stage', 'options', 'options_remembered_display'),
    (unique('if [ "$DISPLAY_MODE" = "auto" ]; then'), 'stage', 'display', 'display_resolve'),
    (unique('# --- CPU set ---------------------------------------------------------------'), 'stage', 'resources', 'resources_cpuset'),
    (unique('DISPLAY_ENV_LINES=""'), 'stage', 'display', 'display_environment'),
    (banner('Audio'), 'stage', 'devices', 'devices_audio'),
    (banner('Timezone'), 'stage', 'resources', 'resources_timezone'),
    (banner('Devices'), 'stage', 'devices', 'devices_enumerate'),
    (banner('Shared brain'), 'stage', 'rules', 'rules_shared_brain'),
    (banner('Copy tool state into the sandbox'), 'stage', 'seed', 'seed_tool_state'),
    (banner('IntelliJ IDEA'), 'stage', 'seed', 'seed_idea'),
    (banner('SDKMAN'), 'stage', 'seed', 'seed_sdkman'),
    (banner('Build context'), 'stage', 'image', 'image_context'),
    (banner('.env'), 'stage', 'compose', 'compose_env'),
    (banner('docker-compose.yml'), 'stage', 'compose', 'compose_file'),
    (banner('Nested display launcher'), 'stage', 'display', 'display_launchers'),
    (banner('Shell helpers'), 'stage', 'install', 'install_helpers'),
    (banner('Build and start'), 'stage', 'start', 'start_gate'),
    (unique('step "Image"'), 'stage', 'image', 'image_build'),
    (unique('# The image no longer carries extensions, so the shared store is their only'), 'stage', 'project', 'project_extensions'),
    (unique('step "Starting $CONTAINER_NAME"'), 'stage', 'start', 'start_run'),
]
starts = [c[0] for c in cuts]
if starts != sorted(starts) or len(set(starts)) != len(starts):
    sys.exit('cuts are not in base order: %r' % starts)
segs = []
for k, (s, kind, mod, stage) in enumerate(cuts):
    e = cuts[k + 1][0] if k + 1 < len(cuts) else N
    segs.append([kind, mod, stage, L[s:e]])

# ---- the build-context heredocs (image_context): files under image/
image_files = {}            # name -> text
HD = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)(\w+)\1")

def body_of(lines, i, tag):
    j = i + 1
    while lines[j] != tag:
        j += 1
    return lines[i + 1:j], j

def unquoted_text(body, name):
    # what the shell writes for an unquoted heredoc whose only escape is '\\'
    t = '\n'.join(body) + '\n'
    if '$' in t or '`' in t:
        sys.exit('%s: an expansion in an unquoted heredoc' % name)
    out = []; i = 0
    while i < len(t):
        c = t[i]
        if c == '\\':
            if t[i + 1:i + 2] == '\\':
                out.append('\\'); i += 2; continue
            sys.exit('%s: an escape other than \\\\' % name)
        out.append(c); i += 1
    return ''.join(out)

DOCTOR_PLACEHOLDER = '@BUILD_CACHE_LOOP@'
FILE_TAGS = {
    'ENTRYPOINT_EOF': 'entrypoint.sh', 'DESKTOP_EOF': 'sandbox-desktop', 'IDEA_EOF': 'sandbox-idea',
    'XDGOPEN_EOF': 'xdg-open', 'BASHRC_EOF': 'sandbox-bashrc.sh', 'ENVFILE_EOF': 'sandbox-env.sh',
    'SDK_EOF': 'sandbox-sdk', 'MANAGED_EOF': 'claude-managed-settings.json',
}
PART_TAGS = {'DOCKERFILE_EOF': 'Dockerfile.base', 'DOCKERFILE_DOCKER': 'Dockerfile.docker', 'DOCKERFILE_TAIL': 'Dockerfile.tail'}

def convert_context(lines):
    out = []; i = 0; doctor_parts = []
    while i < len(lines):
        l = lines[i]; m = HD.search(l) if not l.lstrip().startswith('#') else None
        if not m:
            out.append(l); i += 1; continue
        tag = m.group(2); body, j = body_of(lines, i, tag)
        text = '\n'.join(body) + '\n'
        if tag in FILE_TAGS:
            name = FILE_TAGS[tag]
            if l != 'cat > "$BUILD_DIR/%s" <<\'%s\'' % (name, tag):
                sys.exit('unexpected opener %r' % l)
            image_files[name] = text
            out.append('cp "$SCRIPT_DIR/image/%s" "$BUILD_DIR/%s"' % (name, name))
        elif tag == 'DOCTOR_EOF':
            doctor_parts.append(text)
            if len(doctor_parts) == 1:
                if l != 'cat > "$BUILD_DIR/sandbox-doctor" <<\'DOCTOR_EOF\'':
                    sys.exit('unexpected opener %r' % l)
                out.append('cp "$SCRIPT_DIR/image/sandbox-doctor" "$BUILD_DIR/sandbox-doctor"')
            else:
                if l != 'cat >> "$BUILD_DIR/sandbox-doctor" <<\'DOCTOR_EOF\'':
                    sys.exit('unexpected opener %r' % l)
                if out and out[-1] == '':
                    out.pop()           # the blank line that followed the removed statement
        elif tag == 'DOCKERFILE_HEAD':
            if l != 'cat > "$BUILD_DIR/Dockerfile" <<DOCKERFILE_HEAD':
                sys.exit('unexpected opener %r' % l)
            image_files['Dockerfile.head'] = unquoted_text(body, 'Dockerfile.head')
            out.append('cp "$SCRIPT_DIR/image/Dockerfile.head" "$BUILD_DIR/Dockerfile"')
        elif tag in PART_TAGS:
            name = PART_TAGS[tag]
            if l != 'cat >> "$BUILD_DIR/Dockerfile" <<\'%s\'' % tag:
                sys.exit('unexpected opener %r' % l)
            image_files[name] = text
            out.append('cat "$SCRIPT_DIR/image/%s" >> "$BUILD_DIR/Dockerfile"' % name)
        else:
            sys.exit('unknown heredoc %s in the build context' % tag)
        i = j + 1
    if len(doctor_parts) != 2:
        sys.exit('the doctor has %d parts' % len(doctor_parts))
    if DOCTOR_PLACEHOLDER in doctor_parts[0] + doctor_parts[1]:
        sys.exit('placeholder already in the doctor')
    image_files['sandbox-doctor'] = doctor_parts[0] + DOCTOR_PLACEHOLDER + '\n' + doctor_parts[1]
    res = []
    for l in out:
        if l == 'cp "$SCRIPT_DIR/ai-delegate" "$BUILD_DIR/ai-delegate"':
            l = 'cp "$SCRIPT_DIR/image/ai-delegate" "$BUILD_DIR/ai-delegate"'
        elif l == 'cp "$SCRIPT_DIR/sandbox-knowledge-sync" "$BUILD_DIR/sandbox-knowledge-sync"':
            l = 'cp "$SCRIPT_DIR/image/sandbox-knowledge-sync" "$BUILD_DIR/sandbox-knowledge-sync"'
        res.append(l)
    return res

for sg in segs:
    if sg[2] == 'image_context':
        sg[3] = convert_context(sg[3])

# ---- assemble
entry = []; tops = {}; stages = {}; order = []
devtools_line = None
for kind, mod, stage, lines in segs:
    if kind == 'entry':
        entry += lines
    elif kind == 'devtools':
        devtools_line = lines            # moved to the end of project_prerequisites
    elif kind == 'top':
        tops.setdefault(mod, []).append(lines)
    else:
        stages.setdefault(mod, []).append((stage, lines))
        order.append((mod, stage))
if devtools_line is None:
    sys.exit('no DEV_TOOLS_DIR line')
for k, (stage, lines) in enumerate(stages['project']):
    if stage == 'project_prerequisites':
        while lines and lines[-1] == '':
            lines.pop()
        stages['project'][k] = (stage, lines + devtools_line)

AND_TAIL = re.compile(r'^[^\s#].*&&')
KEYWORDS = ('if ', 'elif ', 'fi', 'done', 'esac', '}', 'for ', 'while ', 'case ', 'else')

def last_statement(lines):
    code = [l for l in lines if l.strip() and not l.lstrip().startswith('#')]
    return code[-1]

def is_and_tail(l):
    # a '&&' inside a substitution or a quoted string is not a list operator of the statement
    l = re.sub(r'\$\([^()]*\)|"[^"]*"|\'[^\']*\'', '', l)
    if not AND_TAIL.match(l) or l.startswith(KEYWORDS) or l.endswith('\\') or l.endswith(';;'):
        return False
    return '||' not in l[l.rindex('&&'):]

def func_text(stage, lines):
    body = list(lines)
    while body and body[-1] == '':
        body.pop()
    last = last_statement(body)
    tail = is_and_tail(last)
    sys.stderr.write('stage-tail %-26s %s%s\n' % (stage, 'AND-TAIL ' if tail else '', last[:100]))
    return ['%s() {' % stage] + body + (['return 0'] if tail else []) + ['}']

def write(path, text, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    os.chmod(path, mode)

modules = ['options', 'project', 'display', 'resources', 'devices', 'rules', 'seed', 'image', 'compose', 'install', 'start']
for mod in modules:
    chunks = []
    for lines in tops.get(mod, []):
        t = list(lines)
        while t and t[-1] == '':
            t.pop()
        chunks.append('\n'.join(t))
    for stage, lines in stages.get(mod, []):
        chunks.append('\n'.join(func_text(stage, lines)))
    write(os.path.join(ai, 'create.d', mod + '.sh'), '\n\n'.join(chunks) + '\n', 0o644)

while entry and entry[-1] == '':
    entry.pop()
mode = os.stat(src).st_mode & 0o7777
write(src, '\n'.join(entry) + '\n', mode)

for name, text in image_files.items():
    write(os.path.join(ai, 'image', name), text, 0o644)
for prog in ('ai-delegate', 'sandbox-knowledge-sync'):
    dst = os.path.join(ai, 'image', prog)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.move(os.path.join(ai, prog), dst)

# ---- the literal old paths in the tree's text files
OLD = re.compile(r'bin/ai/(ai-delegate|sandbox-knowledge-sync)')
SKIP = {'.git', '.worktrees', 'node_modules', '.tmp'}
changed = []
for root, dirs, files in os.walk(tree):
    rel = os.path.relpath(root, tree)
    dirs[:] = sorted(d for d in dirs if d not in SKIP and os.path.join(rel, d) != 'docs/superpowers')
    for f in sorted(files):
        p = os.path.join(root, f)
        if os.path.islink(p):
            continue
        try:
            t = open(p, encoding='utf-8').read()
        except (UnicodeDecodeError, OSError):
            continue
        n = OLD.sub(lambda m: 'bin/ai/image/' + m.group(1), t)
        if n != t:
            open(p, 'w', encoding='utf-8', newline='').write(n)
            changed.append(os.path.relpath(p, tree))
sys.stderr.write('old paths rewritten in: %s\n' % ' '.join(changed))
PY
