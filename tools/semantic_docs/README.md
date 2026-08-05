# Semantic Docs (`tools/semantic_docs`)

`semantic_docs` is a lightweight, zero-maintenance local vector search utility built with **LanceDB** and **fastembed**. It enables AI agents and developers to index and semantically search documentation, specifications, PDFs, meeting notes, and research files by intent.

---

## 💡 Key Features

- **Embedded Local Storage:** Stores vector embeddings in `~/.gemini/semantic_docs_db/`. No background daemons, servers, or open ports required.
- **Fast CPU Embeddings:** Uses ONNX-accelerated `BAAI/bge-small-en-v1.5` embeddings locally. 100% private, no API keys needed.
- **Multi-Format Support:** Chunks Markdown (`.md`), plain text (`.txt`), reStructuredText (`.rst`), and PDFs (`.pdf`).
- **Formatted Results:** Returns formatted Markdown passages with clickable `file://` links and exact line/page ranges.

---

## 🚀 CLI Usage

### 1. Index a File or Directory
```bash
python3 -m tools.semantic_docs.cli index ~/docs/ ~/projects/specifications/
```

### 2. Perform Semantic Search
```bash
python3 -m tools.semantic_docs.cli search "how do we handle database backups" --top-k 5
```

### 3. Check Index Status
```bash
python3 -m tools.semantic_docs.cli status
```

### 4. Clear Index
```bash
python3 -m tools.semantic_docs.cli clear
```
