from abc import ABC, abstractmethod
from typing import Dict, List

class BaseDemuxer(ABC):
    """
    Base class for demuxing a multiplexed log stream (like Earthly or Bazel)
    into separate streams per target/module.
    """
    
    @abstractmethod
    def demux(self, raw_lines: List[str]) -> Dict[str, List[str]]:
        """
        Takes raw lines and returns a dictionary mapping target names
        to their respective log lines.
        If no demuxing is needed, return {'global': raw_lines}.
        """
        pass
