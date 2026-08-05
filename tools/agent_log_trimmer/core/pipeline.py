import os
import shutil
from typing import Dict, List, Optional
from agent_log_trimmer.core.demuxer import BaseDemuxer
from agent_log_trimmer.core.trimmer import BaseTrimmer
from agent_log_trimmer.detectors.detector import detect_demuxer, detect_trimmers
from agent_log_trimmer.core.utils import strip_ansi

class Pipeline:
    def __init__(self, context_lines: int = 3, max_lines_per_target: int = 400):
        self.context_lines = context_lines
        self.max_lines_per_target = max_lines_per_target

    def run(self, raw_text: str) -> Dict[str, List[str]]:
        """
        1. Strips ANSI
        2. Detects Demuxer and demuxes lines
        3. For each target stream, detects inner Trimmers and applies them
        4. Coalesces output and limits length
        """
        lines = [strip_ansi(line) for line in raw_text.splitlines()]
        if not lines:
            return {}

        # 1. Demuxing
        demuxer = detect_demuxer(lines)
        if demuxer:
            target_streams = demuxer.demux(lines)
        else:
            target_streams = {"global": lines}

        # 2. Trimming
        trimmed_streams: Dict[str, List[str]] = {}
        for target, target_lines in target_streams.items():
            if not target_lines:
                continue

            trimmers = detect_trimmers(target_lines)
            trimmed_lines = self._apply_trimmers(target_lines, trimmers)
            trimmed_streams[target] = trimmed_lines

        return trimmed_streams

    def _apply_trimmers(self, lines: List[str], trimmers: List[BaseTrimmer]) -> List[str]:
        if not trimmers:
            # If no trimmers, just return the last max_lines
            return lines[-self.max_lines_per_target:]

        filtered_lines = []
        error_indices = set()

        for idx, line in enumerate(lines):
            # Check if any trimmer considers this line noise
            if any(trimmer.is_noise(line) for trimmer in trimmers):
                continue
                
            filtered_lines.append(line)
            # Check if any trimmer considers this line an error
            if any(trimmer.is_error(line) for trimmer in trimmers):
                error_indices.add(len(filtered_lines) - 1)

        # Retain context around errors
        retained_indices = set()
        for idx in error_indices:
            start = max(0, idx - self.context_lines)
            end = min(len(filtered_lines), idx + self.context_lines + 1)
            retained_indices.update(range(start, end))

        # Always keep the last N lines (e.g. build summary)
        tail_start = max(0, len(filtered_lines) - 40)
        retained_indices.update(range(tail_start, len(filtered_lines)))

        final_lines = []
        last_idx = -2
        for idx in sorted(retained_indices):
            if idx > last_idx + 1 and final_lines:
                final_lines.append(f"... (skipped {idx - last_idx - 1} lines) ...")
            final_lines.append(filtered_lines[idx])
            last_idx = idx

        return final_lines[-self.max_lines_per_target:]
