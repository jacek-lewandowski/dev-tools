import re
from agent_log_trimmer.core.trimmer import BaseTrimmer

class NpmTrimmer(BaseTrimmer):
    NOISE_PATTERNS = [
        re.compile(r'^npm WARN (?:deprecated|tar|audit|optional)'),
        re.compile(r'^\s*added \d+ packages, and audited \d+ packages in'),
        re.compile(r'^\s*found \d+ vulnerabilities'),
        re.compile(r'^\s*$'),
    ]

    ERROR_INDICATORS = [
        re.compile(r'^npm ERR!'),
        re.compile(r'^Failed to compile\.'),
        re.compile(r'SyntaxError:'),
        re.compile(r'TypeError:'),
    ]

    def is_noise(self, line: str) -> bool:
        return any(p.search(line) for p in self.NOISE_PATTERNS)

    def is_error(self, line: str) -> bool:
        return any(p.search(line) for p in self.ERROR_INDICATORS)
