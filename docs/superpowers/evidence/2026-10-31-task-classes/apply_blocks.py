#!/usr/bin/env python3
"""Apply the Appendix A contract blocks of the task-classes spec to ~/knowledge.

Usage: apply_blocks.py check [REV] [BLOCK ...]  verify each old text occurs exactly once at REV (default HEAD; all blocks)
       apply_blocks.py apply B1 B2 ...  apply the named blocks to the working tree, in order
Each block is read from the spec; nothing is retyped here.
"""
import re, subprocess, sys, pathlib

SPEC = pathlib.Path("/home/jlewandowski/dev/public/dev-tools/docs/superpowers/specs/2026-10-31-task-classes-design.md")
REPO = pathlib.Path("/home/jlewandowski/knowledge")

# Insertions: (file-local anchor text that must occur once; the new block is put before it,
# followed by a blank line). Anchors are quoted from the files at dff9565.
INSERT_BEFORE = {
    "P1": "## The spec\n",
    "I1": "- For a task marked as design work, begin with a short note",
    "R1": "- Verify claims against the phase's evidence files, not against the reports:",
}

def parse_spec():
    text = SPEC.read_text()
    blocks = {}
    heads = list(re.finditer(r"^### (G\d+|P\d|I\d|R\d+) `([^`]+)`\n", text, re.M))
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        body = text[h.start():end]
        fences = re.findall(r"^Old[^\n]*:\n\n```markdown\n(.*?)\n```\n.*?^New:\n\n```markdown\n(.*?)\n```", body, re.S | re.M)
        assert len(fences) == 1, h.group(1)
        old, new = fences[0]
        blocks[h.group(1)] = (h.group(2), old + "\n", new + "\n")
    return blocks

def head_text(path, rev="HEAD"):
    return subprocess.run(["git", "-C", str(REPO), "show", f"{rev}:{path}"], check=True, capture_output=True, text=True).stdout

def check(blocks, rev="HEAD", keys=()):
    ok = True
    for key, (path, old, new) in blocks.items():
        if keys and key not in keys:
            continue
        if key in INSERT_BEFORE:
            needle, kind = INSERT_BEFORE[key], "anchor"
        else:
            needle, kind = old, "old text"
        n = head_text(path, rev).count(needle)
        print(f"{key} {path}: {kind} occurs {n} time(s)" + ("" if n == 1 else "  <-- MISMATCH"))
        ok &= n == 1
    return ok

def apply(blocks, keys):
    for key in keys:
        path, old, new = blocks[key]
        f = REPO / path
        text = f.read_text()
        if key in INSERT_BEFORE:
            anchor = INSERT_BEFORE[key]
            assert text.count(anchor) == 1, (key, "anchor count", text.count(anchor))
            text = text.replace(anchor, new + "\n" + anchor)
        else:
            assert text.count(old) == 1, (key, "old count", text.count(old))
            text = text.replace(old, "" if new.strip() == "(removed)" else new)
        f.write_text(text)
        print(f"{key} applied to {path}")

if __name__ == "__main__":
    blocks = parse_spec()
    if sys.argv[1] == "check":
        sys.exit(0 if check(blocks, *sys.argv[2:3], keys=sys.argv[3:]) else 1)
    elif sys.argv[1] == "apply":
        apply(blocks, sys.argv[2:])
    elif sys.argv[1] == "show":
        path, old, new = blocks[sys.argv[2]]
        print(new, end="")
