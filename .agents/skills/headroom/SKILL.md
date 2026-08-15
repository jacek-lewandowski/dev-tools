---
name: headroom
description: Uses Headroom to compress tool outputs, JSON payloads, logs, files, RAG results, and proxy LLM requests to minimize token usage.
---

# Headroom Token Optimization Skill

Use this skill whenever processing large textual, JSON, AST, or log data where token efficiency is critical, or when running proxy/subagent sessions in environments where Headroom (`headroom-ai`) is installed.

## 1. Quick CLI & Python Usage

### Check Availability
```bash
which headroom || python3 -c "import headroom; print('Headroom available')" 2>/dev/null
```

### Compress Text, JSON, or Files
Compress stdin or data payloads using Headroom's compression engine (SmartCrusher for JSON, AST code compression, and semantic text compression):
```bash
python3 -c "import sys; from headroom import compress; print(compress(sys.stdin.read()))" < large_payload.json
```
Or inline in Python scripts:
```python
from headroom import compress

# Auto-detects and compresses JSON, code (AST pruning), or unstructured text
compressed_output = compress(raw_content)
```

## 2. Proxy & Subagent Wrapping

### Drop-in Compression Proxy
Start the local proxy to transparently intercept and compress LLM traffic:
```bash
headroom proxy --port 8787
```

### Wrap Agent Sessions
Wrap a coding agent CLI session to route requests through Headroom's compression pipeline:
```bash
headroom wrap <tool> # e.g. claude, copilot, codex
```

### Undo Wrapping
```bash
headroom unwrap <tool>
```

## 3. Session Diagnostics & Rule Learning

### Health & Savings Verification
```bash
headroom doctor
headroom output-savings
```

### Mine Failure Patterns & Adjust Verbosity
Mine session logs to optimize rule verbosity and extract learned patterns:
```bash
headroom learn --verbosity
headroom learn --verbosity --apply
```
