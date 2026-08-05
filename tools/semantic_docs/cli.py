#!/usr/bin/env python3
import sys
import os
import argparse
from typing import List

from tools.semantic_docs.parser import DocumentChunker
from tools.semantic_docs.store import VectorStore


def index_command(paths: List[str], store: VectorStore, chunker: DocumentChunker):
    total_files = 0
    total_chunks = 0

    files_to_process = []
    for path in paths:
        abs_path = os.path.abspath(path)
        if os.path.isfile(abs_path):
            files_to_process.append(abs_path)
        elif os.path.isdir(abs_path):
            for root, _, files in os.walk(abs_path):
                for f in files:
                    ext = os.path.splitext(f)[1].lower()
                    if ext in [".md", ".markdown", ".txt", ".rst", ".pdf", ".org"]:
                        files_to_process.append(os.path.join(root, f))

    print(f"🔍 Indexing {len(files_to_process)} document file(s)...")

    for file_path in files_to_process:
        chunks = chunker.process_file(file_path)
        if chunks:
            added = store.add_chunks(chunks)
            total_files += 1
            total_chunks += added

    print(f"✅ Successfully indexed {total_chunks} passage(s) across {total_files} file(s) into LanceDB!")


def search_command(query: str, top_k: int, store: VectorStore):
    print(f"🔍 Searching for: '{query}' (top {top_k} results)\n")
    results = store.search(query, top_k=top_k)

    if not results:
        print("No matching document passages found in index.")
        return

    for i, res in enumerate(results, 1):
        file_path = res.get("file_path", "")
        file_name = res.get("file_name", os.path.basename(file_path))
        heading = res.get("heading", "General")
        start_line = res.get("start_line", 1)
        end_line = res.get("end_line", 1)
        text = res.get("text", "").strip()
        score = res.get("_distance", None)

        score_str = f" (distance: {score:.4f})" if score is not None else ""
        link_str = f"[{file_name}:{start_line}-{end_line}](file://{file_path}#L{start_line}-L{end_line})"

        print(f"### Result {i}: {heading}{score_str}")
        print(f"**Source:** {link_str}")
        print("```markdown")
        print(text)
        print("```\n")


def status_command(store: VectorStore):
    info = store.status()
    print("📊 Semantic Docs Index Status:")
    print(f"  * DB Path: {info['db_path']}")
    print(f"  * Table Exists: {info['table_exists']}")
    print(f"  * Total Chunks: {info['total_chunks']}")


def clear_command(store: VectorStore):
    if store.clear():
        print("🗑️ Document index cleared successfully.")
    else:
        print("Index was already empty.")


def main():
    parser = argparse.ArgumentParser(
        description="Semantic Docs - Local vector search for documentation and daily tasks."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Index command
    index_parser = subparsers.add_parser("index", help="Index document files or directories")
    index_parser.add_argument("paths", nargs="+", help="Files or directories to index")

    # Search command
    search_parser = subparsers.add_parser("search", help="Perform semantic vector search")
    search_parser.add_argument("query", type=str, help="Search query string")
    search_parser.add_argument("--top-k", type=int, default=5, help="Number of results to return")

    # Status command
    subparsers.add_parser("status", help="Show index statistics")

    # Clear command
    subparsers.add_parser("clear", help="Clear all stored embeddings")

    args = parser.parse_args()
    store = VectorStore()
    chunker = DocumentChunker()

    if args.command == "index":
        index_command(args.paths, store, chunker)
    elif args.command == "search":
        search_command(args.query, args.top_k, store)
    elif args.command == "status":
        status_command(store)
    elif args.command == "clear":
        clear_command(store)


if __name__ == "__main__":
    main()
