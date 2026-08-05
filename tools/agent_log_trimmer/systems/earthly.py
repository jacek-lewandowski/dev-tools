import re
from typing import Dict, List
from agent_log_trimmer.core.demuxer import BaseDemuxer
from agent_log_trimmer.core.utils import sanitize_target_filename

class EarthlyDemuxer(BaseDemuxer):
    def demux(self, raw_lines: List[str]) -> Dict[str, List[str]]:
        target_logs = {}
        current_target = "global"
        in_repeat_section = False

        # Pre-compile regex for performance
        target_regex = re.compile(r'^\s*([^\s|]+(?:\+[\w-]+)?(?:\s+\*failed\*)?)\s*\|')

        for line in raw_lines:
            if "Repeating the failure error..." in line:
                in_repeat_section = True
                continue

            match = target_regex.match(line)
            if match:
                target_str = match.group(1)
                current_target = sanitize_target_filename(target_str)
                # Remove the target prefix from the line
                clean_line = re.sub(r'^\s*([^\s|]+(?:\s+\*failed\*)?\s*\|)\s*', '', line)
            else:
                clean_line = line
                target_str = None

            # Skip repeat sections in the demuxed module logs because they are duplicates
            if in_repeat_section and target_str:
                continue

            if current_target not in target_logs:
                target_logs[current_target] = []
            
            # Basic identical consecutive line deduplication (like stack frames)
            if target_logs[current_target] and target_logs[current_target][-1] == clean_line and len(clean_line) > 10:
                continue

            target_logs[current_target].append(clean_line)

        return target_logs
