import re
from agent_log_trimmer.core.trimmer import BaseTrimmer

class SpringTrimmer(BaseTrimmer):
    NOISE_PATTERNS = [
        re.compile(r'^\s*:: Spring Boot ::'),
        re.compile(r'^\s*MockHttpServletRequest:'),
        re.compile(r'^\s*HTTP Method ='),
        re.compile(r'^\s*Request URI ='),
        re.compile(r'^\s*Parameters ='),
        re.compile(r'^\s*Headers ='),
        re.compile(r'^\s*Handler:'),
        re.compile(r'^\s*Type ='),
        re.compile(r'^\s*Method ='),
        re.compile(r'^\s*Async:'),
        re.compile(r'^\s*Async started ='),
        re.compile(r'^\s*Async result ='),
        re.compile(r'^\s*Resolved Exception:'),
        re.compile(r'^\s*ModelAndView:'),
        re.compile(r'^\s*View name ='),
        re.compile(r'^\s*View ='),
        re.compile(r'^\s*Model ='),
        re.compile(r'^\s*FlashMap:'),
        re.compile(r'^\s*Attributes ='),
        re.compile(r'^\s*MockHttpServletResponse:'),
        re.compile(r'^\s*Forwarded URL ='),
        re.compile(r'^\s*Redirected URL ='),
        re.compile(r'^\s*Cookies ='),
        re.compile(r'^\s*$'),
    ]

    # Status and Body are useful for MockMvc debugging!
    ERROR_INDICATORS = [
        re.compile(r'^\s*Status = [45]\d\d'),
        re.compile(r'^\s*Body = \{.*"error".*\}'),
    ]

    def is_noise(self, line: str) -> bool:
        return any(p.search(line) for p in self.NOISE_PATTERNS)

    def is_error(self, line: str) -> bool:
        return any(p.search(line) for p in self.ERROR_INDICATORS)
