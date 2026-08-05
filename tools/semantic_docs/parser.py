import os
import re
from typing import List, Dict, Any

try:
    import pypdf
except ImportError:
    pypdf = None


class DocumentChunker:
    """Parses and chunks Markdown, plain text, RST, and PDF documents into semantic passages."""

    def __init__(self, chunk_size: int = 500, chunk_overlap: int = 50):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap

    def process_file(self, file_path: str) -> List[Dict[str, Any]]:
        """Processes a single file and returns a list of chunk dicts."""
        file_path = os.path.abspath(file_path)
        ext = os.path.splitext(file_path)[1].lower()

        if ext == ".pdf":
            return self._process_pdf(file_path)
        elif ext in [".md", ".markdown", ".txt", ".rst", ".org"]:
            return self._process_text(file_path)
        return []

    def _process_text(self, file_path: str) -> List[Dict[str, Any]]:
        try:
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
        except Exception:
            return []

        lines = content.splitlines()
        chunks: List[Dict[str, Any]] = []

        current_heading = "General"
        current_lines: List[str] = []
        start_line = 1
        current_len = 0

        for i, line in enumerate(lines, 1):
            # Track headings for context
            if line.strip().startswith("#"):
                heading_match = re.match(r"^#+\s+(.+)$", line.strip())
                if heading_match:
                    current_heading = heading_match.group(1).strip()

            current_lines.append(line)
            current_len += len(line) + 1

            # When chunk reaches chunk_size or at empty line near limit
            if current_len >= self.chunk_size:
                chunk_text = "\n".join(current_lines).strip()
                if chunk_text:
                    chunks.append({
                        "file_path": file_path,
                        "file_name": os.path.basename(file_path),
                        "heading": current_heading,
                        "start_line": start_line,
                        "end_line": i,
                        "text": chunk_text
                    })
                # Overlap
                overlap_lines = current_lines[-3:] if len(current_lines) > 3 else []
                current_lines = list(overlap_lines)
                start_line = max(1, i - len(overlap_lines) + 1)
                current_len = sum(len(l) + 1 for l in current_lines)

        if current_lines:
            chunk_text = "\n".join(current_lines).strip()
            if chunk_text:
                chunks.append({
                    "file_path": file_path,
                    "file_name": os.path.basename(file_path),
                    "heading": current_heading,
                    "start_line": start_line,
                    "end_line": len(lines),
                    "text": chunk_text
                })

        return chunks

    def _process_pdf(self, file_path: str) -> List[Dict[str, Any]]:
        if not pypdf:
            return []
        chunks: List[Dict[str, Any]] = []
        try:
            reader = pypdf.PdfReader(file_path)
            for page_num, page in enumerate(reader.pages, 1):
                text = page.extract_text() or ""
                if text.strip():
                    chunks.append({
                        "file_path": file_path,
                        "file_name": os.path.basename(file_path),
                        "heading": f"Page {page_num}",
                        "start_line": page_num,
                        "end_line": page_num,
                        "text": text.strip()
                    })
        except Exception:
            pass
        return chunks
