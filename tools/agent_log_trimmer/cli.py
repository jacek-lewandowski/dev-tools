import os
import sys
import shutil
import argparse
from typing import Dict, List
from agent_log_trimmer.core.pipeline import Pipeline

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Universal Build Log Trimmer for AI Agents."
    )
    parser.add_argument("file", nargs="?", type=str, default="build.output.txt", help="Path to build log file (default: build.output.txt).")
    parser.add_argument("-c", "--context", type=int, default=3, help="Context lines to retain around error occurrences (default: 3).")
    parser.add_argument("-m", "--max-lines", type=int, default=400, help="Max total lines for trimmed output per target (default: 400).")
    parser.add_argument("--split-dir", type=str, default=".build_logs", help="Directory to save separated log files per module/target (default: .build_logs).")
    parser.add_argument("--no-stats", dest="stats", action="store_false", default=True, help="Disable printing log reduction statistics to stderr.")

    args = parser.parse_args()

    # Read input
    if args.file == "-" or not sys.stdin.isatty():
        raw_text = sys.stdin.read()
    else:
        if not os.path.exists(args.file):
            print(f"Error: Default input file not found: {args.file}. Please provide a valid file or pipe input.", file=sys.stderr)
            return 1
        with open(args.file, "r", encoding="utf-8", errors="replace") as f:
            raw_text = f.read()

    if not raw_text.strip():
        print("Warning: Empty input received.", file=sys.stderr)
        return 0
        
    pipeline = Pipeline(context_lines=args.context, max_lines_per_target=args.max_lines)
    trimmed_streams = pipeline.run(raw_text)
    
    # Calculate stats
    raw_lines = len(raw_text.splitlines())
    raw_bytes = len(raw_text.encode('utf-8'))
    
    trimmed_lines = sum(len(stream) for stream in trimmed_streams.values())
    trimmed_bytes = sum(len("\n".join(stream).encode('utf-8')) for stream in trimmed_streams.values())
    
    # Output handling
    output_dir = args.split_dir
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    
    for target, lines in trimmed_streams.items():
        file_path = os.path.join(output_dir, f"{target}.log")
        with open(file_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
            
    print(f"Successfully split build log into {len(trimmed_streams)} target log files in '{output_dir}':")
    for target in trimmed_streams:
        print(f"  - {target} -> {os.path.join(output_dir, target + '.log')}")

    if args.stats:
        reduction_pct = round((1 - trimmed_lines / raw_lines) * 100, 1) if raw_lines else 0
        bytes_pct = round((1 - trimmed_bytes / raw_bytes) * 100, 1) if raw_bytes else 0
        print("\n--- Agent Log Trimming Stats ---", file=sys.stderr)
        print(f"Raw Lines:     {raw_lines:,}", file=sys.stderr)
        print(f"Trimmed Lines: {trimmed_lines:,} ({reduction_pct}% reduction)", file=sys.stderr)
        print(f"Raw Bytes:     {raw_bytes:,} B", file=sys.stderr)
        print(f"Trimmed Bytes: {trimmed_bytes:,} B ({bytes_pct}% reduction)", file=sys.stderr)

    return 0

if __name__ == "__main__":
    sys.exit(main())
