from typing import Dict, List
from agent_log_trimmer.core.demuxer import BaseDemuxer

class DockerDemuxer(BaseDemuxer):
    def demux(self, raw_lines: List[str]) -> Dict[str, List[str]]:
        # Docker Buildx output (e.g., #11 [stage 2/3]) can be grouped by step.
        return {"global": raw_lines}
