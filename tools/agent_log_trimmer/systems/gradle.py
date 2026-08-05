import re
from agent_log_trimmer.core.trimmer import BaseTrimmer

class GradleTrimmer(BaseTrimmer):
    NOISE_PATTERNS = [
        re.compile(r'^> Task :[a-zA-Z0-9_-]+ (UP-TO-DATE|FROM-CACHE|NO-SOURCE)$'),
        re.compile(r'^Download https?://'),
        re.compile(r'^Starting a Gradle Daemon'),
        re.compile(r'^\s*$'),
    ]

    ERROR_INDICATORS = [
        re.compile(r'^> Task :[a-zA-Z0-9_-]+ FAILED'),
        re.compile(r'FAILURE: Build failed with an exception.'),
        re.compile(r'^\s*at org\.gradle\.api\.'),
        re.compile(r'^\s*at java\.base/'),
    ]

    def is_noise(self, line: str) -> bool:
        return any(p.search(line) for p in self.NOISE_PATTERNS)

    def is_error(self, line: str) -> bool:
        return any(p.search(line) for p in self.ERROR_INDICATORS)
