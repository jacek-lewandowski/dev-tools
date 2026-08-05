from typing import Dict, List
from agent_log_trimmer.core.demuxer import BaseDemuxer

class BazelDemuxer(BaseDemuxer):
    def demux(self, raw_lines: List[str]) -> Dict[str, List[str]]:
        # Bazel doesn't multiplex quite like Earthly, but we can group by targets if we parse the
        # INFO: Analyzed target //foo:bar lines.
        # For simplicity in this base version, we return global stream.
        # A more advanced parser would split at //target:name boundaries.
        return {"global": raw_lines}
