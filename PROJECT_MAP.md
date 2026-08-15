# Project Architecture Map (`dev-tools`)

This document outlines the core structure, CLI scripts, and utility tools contained in the `dev-tools` repository.

---

## 📂 Core Directories & Modules

| Directory / File | Role & Responsibility |
| :--- | :--- |
| [bin/](file:///home/jlewandowski/dev/public/dev-tools/bin) | Executable bash CLI scripts for development, sandbox generation, and media processing. |
| [bin/create-ai-sandbox.sh](file:///home/jlewandowski/dev/public/dev-tools/bin/create-ai-sandbox.sh) | Generates and manages isolated Docker developer sandboxes per project with Rootless Docker, GUI/X11, Antigravity 2 IDE credential persistence, Headroom token compression, and live host brain sync. |
| [tools/](file:///home/jlewandowski/dev/public/dev-tools/tools) | Python tools and utilities designed for AI agent execution. |
| [tools/agent_log_trimmer](file:///home/jlewandowski/dev/public/dev-tools/tools/agent_log_trimmer) | CLI tool to demux, filter noise, extract errors, and save tokens from complex build outputs (Earthly, Maven, Gradle, Bazel, NPM, Pip). |
| [tools/semantic_docs](file:///home/jlewandowski/dev/public/dev-tools/tools/semantic_docs) | Lightweight local vector search CLI using LanceDB and local embeddings for indexing and searching docs, notes, specifications, and PDFs. |
| [.agents/AGENTS.md](file:///home/jlewandowski/dev/public/dev-tools/.agents/AGENTS.md) | Workspace-level agent behavioral rules, token optimizations, refactoring standards, and navigation guidelines. |
