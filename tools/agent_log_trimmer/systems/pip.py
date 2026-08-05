import re
from agent_log_trimmer.core.trimmer import BaseTrimmer

class PipTrimmer(BaseTrimmer):
    NOISE_PATTERNS = [
        re.compile(r'^Requirement already satisfied:'),
        re.compile(r'^Collecting '),
        re.compile(r'^Downloading '),
        re.compile(r'^Installing collected packages:'),
        re.compile(r'^Successfully installed '),
        re.compile(r'^\s*━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'), # Pip progress bars
        re.compile(r'^\s*$'),
    ]

    ERROR_INDICATORS = [
        re.compile(r'^ERROR: '),
        re.compile(r'^Exception: '),
        re.compile(r'^Traceback \(most recent call last\):'),
    ]

    def is_noise(self, line: str) -> bool:
        return any(p.search(line) for p in self.NOISE_PATTERNS)

    def is_error(self, line: str) -> bool:
        return any(p.search(line) for p in self.ERROR_INDICATORS)
