import re
from agent_log_trimmer.core.trimmer import BaseTrimmer

class MavenTrimmer(BaseTrimmer):
    NOISE_PATTERNS = [
        re.compile(r'^\[INFO\] Download(?:ing|ed) from [^:]+: https?://'),
        re.compile(r'^\[INFO\] (?:--- )?maven-[a-z-]+-plugin:'),
        re.compile(r'^\[INFO\] Resolved plugin descriptor for '),
        re.compile(r'^\[INFO\] Dependency-set '),
        re.compile(r'^\[INFO\] Copying \d+ resource'),
        re.compile(r'^\[INFO\] Scanning for projects\.\.\.'),
        re.compile(r'^\[INFO\] \-+$'),
        re.compile(r'^\[INFO\] Building \S+ \d+\.\d+'),
        re.compile(r'^\[INFO\] Nothing to compile'),
        re.compile(r'^\[INFO\] skip non existing resourceDirectory'),
        re.compile(r'^\[INFO\] \s*$'),
        re.compile(r'^\s*$'), # Empty lines
    ]

    ERROR_INDICATORS = [
        re.compile(r'^\[ERROR\]'),
        re.compile(r'<<< FAILURE!'),
        re.compile(r'<<< ERROR!'),
        re.compile(r'at (?:sun|java|org|com)\.'), # Stack traces
    ]

    def is_noise(self, line: str) -> bool:
        return any(p.search(line) for p in self.NOISE_PATTERNS)

    def is_error(self, line: str) -> bool:
        return any(p.search(line) for p in self.ERROR_INDICATORS)
