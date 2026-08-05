import re

# Regex to strip ANSI escape codes
ANSI_ESCAPE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

def strip_ansi(line: str) -> str:
    """Removes ANSI escape codes (colors, formatting) from a line."""
    return ANSI_ESCAPE.sub('', line)

def sanitize_target_filename(target: str) -> str:
    """Converts a target name (e.g. ./module+test) into a safe filename."""
    s = re.sub(r'[^a-zA-Z0-9_\-\.]', '_', target)
    return s.strip('_')
