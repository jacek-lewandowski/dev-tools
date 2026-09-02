# Project Architecture Map (`dev-tools`)

This document outlines the core structure, CLI scripts, and utility tools contained in the `dev-tools` repository.

---

## 📂 Core Directories & Modules

| Directory / File | Role & Responsibility |
| :--- | :--- |
| [bin/](file:///home/jlewandowski/dev/public/dev-tools/bin) | Executable bash CLI scripts for development, sandbox generation, and media processing. |
| [bin/create-ai-sandbox.sh](file:///home/jlewandowski/dev/public/dev-tools/bin/create-ai-sandbox.sh) | Generates and manages isolated Docker developer sandboxes per project with Rootless Docker, GUI/X11, Antigravity 2 IDE & Claude Desktop / Claude Code credential persistence, Headroom token compression, and live host brain sync. |
| [bin/ai-sandbox-lib.sh](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-lib.sh) | Shared bash library, sourced by `create-ai-sandbox.sh` and every `ai-sandbox-*` command: path-derived project identity, sandbox paths, compose invocation, the shared-mount and credential-seed tables, and the image build hash. The identity formula lives here and nowhere else. |
| [bin/ai-sandbox](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox) | Enter or start the current project's sandbox; runs migration first. `--print-context` reports the resolved sandbox. |
| [bin/ai-sandbox-account](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-account) | `status` / `refresh` / `reset` for the AI credentials a project's sandbox uses, so each project can hold a different Claude, Codex or Gemini account. |
| [bin/ai-sandbox-migrate](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-migrate) | Idempotent migration of `~/.ai-sandbox` to the current layout; runs automatically before every start. Moves directories, never deletes. |
| [bin/ai-sandbox-gc](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-gc) | Reclaims per-sandbox duplicates of shared assets and images from the old per-project naming scheme, after listing them and confirming. |
| [bin/ai-sandbox-extensions](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-extensions) | Populates the shared IDE extension stores from the host, or from a throwaway container when the host has none. |
| [bin/ai-sandbox-stop](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-stop), [-restart](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-restart), [-attach](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-attach), [-rm](file:///home/jlewandowski/dev/public/dev-tools/bin/ai-sandbox-rm) | Lifecycle and device helpers for the current project's sandbox. |
| [tests/ai-sandbox/](file:///home/jlewandowski/dev/public/dev-tools/tests/ai-sandbox) | Bash test suite for the sandbox tooling, run against a temp `HOME` with a stubbed `docker`: `bash tests/ai-sandbox/run-tests.sh`. No framework required. |
| [tools/](file:///home/jlewandowski/dev/public/dev-tools/tools) | Python tools and utilities designed for AI agent execution. |
| [tools/agent_log_trimmer](file:///home/jlewandowski/dev/public/dev-tools/tools/agent_log_trimmer) | CLI tool to demux, filter noise, extract errors, and save tokens from complex build outputs (Earthly, Maven, Gradle, Bazel, NPM, Pip). |
| [tools/semantic_docs](file:///home/jlewandowski/dev/public/dev-tools/tools/semantic_docs) | Lightweight local vector search CLI using LanceDB and local embeddings for indexing and searching docs, notes, specifications, and PDFs. |
| [.agents/AGENTS.md](file:///home/jlewandowski/dev/public/dev-tools/.agents/AGENTS.md) | Workspace-level agent behavioral rules, token optimizations, refactoring standards, and navigation guidelines. |
