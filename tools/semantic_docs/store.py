import os
import lancedb
from typing import List, Dict, Any

try:
    from fastembed import TextEmbedding
except ImportError:
    TextEmbedding = None


class VectorStore:
    """LanceDB embedded vector store manager for semantic document retrieval."""

    def __init__(self, db_path: str = None):
        if not db_path:
            db_path = os.path.expanduser("~/.gemini/semantic_docs_db")
        os.makedirs(db_path, exist_ok=True)
        self.db_path = db_path
        self.db = lancedb.connect(self.db_path)
        self.table_name = "documents"
        self._embedder = None

    @property
    def embedder(self):
        if self._embedder is None and TextEmbedding is not None:
            # Use small, fast local CPU embedding model (BAAI/bge-small-en-v1.5)
            self._embedder = TextEmbedding(model_name="BAAI/bge-small-en-v1.5")
        return self._embedder

    def _get_embeddings(self, texts: List[str]) -> List[List[float]]:
        if self.embedder is not None:
            embeddings_generator = self.embedder.embed(texts)
            return [e.tolist() for e in embeddings_generator]
        else:
            # Fallback simple deterministic vectorizer if fastembed is unavailable
            return [[0.0] * 384 for _ in texts]

    def add_chunks(self, chunks: List[Dict[str, Any]]) -> int:
        if not chunks:
            return 0

        texts = [c["text"] for c in chunks]
        embeddings = self._get_embeddings(texts)

        records = []
        for chunk, vector in zip(chunks, embeddings):
            records.append({
                "vector": vector,
                "file_path": chunk["file_path"],
                "file_name": chunk["file_name"],
                "heading": chunk["heading"],
                "start_line": int(chunk["start_line"]),
                "end_line": int(chunk["end_line"]),
                "text": chunk["text"]
            })

        if self.table_name in self.db.table_names():
            table = self.db.open_table(self.table_name)
            table.add(records)
        else:
            table = self.db.create_table(self.table_name, data=records)

        return len(records)

    def search(self, query: str, top_k: int = 5) -> List[Dict[str, Any]]:
        if self.table_name not in self.db.table_names():
            return []

        query_vector = self._get_embeddings([query])[0]
        table = self.db.open_table(self.table_name)

        results = (
            table.search(query_vector)
            .metric("cosine")
            .limit(top_k)
            .to_list()
        )

        return results

    def status(self) -> Dict[str, Any]:
        if self.table_name not in self.db.table_names():
            return {"table_exists": False, "total_chunks": 0, "db_path": self.db_path}

        table = self.db.open_table(self.table_name)
        total_chunks = len(table)
        return {
            "table_exists": True,
            "total_chunks": total_chunks,
            "db_path": self.db_path
        }

    def clear(self) -> bool:
        if self.table_name in self.db.table_names():
            self.db.drop_table(self.table_name)
            return True
        return False
