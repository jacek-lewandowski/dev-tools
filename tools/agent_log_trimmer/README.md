# Agent Log Trimmer

`agent_log_trimmer` is a Python utility designed to parse, demux, and condense large, noisy build and test logs into concise, actionable summaries tailored for **AI coding agents** and developers.

---

## 💡 What is this?

When running complex build commands (e.g., Maven, Gradle, Bazel, Earthly, Docker Buildx, NPM), build output frequently spans thousands of lines filled with download progress, info logs, repetitive warnings, and multiplexed target output. 

Feeding raw build logs directly into AI agent context windows can waste tokens, trigger context limits, and obscure the actual root-cause errors.

`agent_log_trimmer` solves this by:
1. **ANSI Stripping**: Removing raw terminal color and formatting control characters.
2. **Log Demuxing**: Automatically detecting multiplexed log streams (e.g., Earthly, Bazel, Docker Buildx) and separating output into per-target/per-module streams.
3. **Smart Error Detection & Context Preservation**: Retaining error stack traces, compilation errors, and failure details along with configurable context lines (`-c / --context`), while stripping repetitive noise.
4. **Tail Preservation & Stats**: Keeping final build summaries while outputting clean, separated log files and reporting line/byte reduction metrics.

---

## 🛠️ Supported Build & Log Systems

### Multiplexers (Log Demuxing)
- **Earthly** (`Earthfile` target demuxing)
- **Bazel** (Target-level log separation)
- **Docker Buildx** (Multi-stage build log demuxing)

### Inner Tool & Framework Trimmers
- **Java / JVM**: Maven (`mvn`), Gradle (`gradlew`), Spring Boot (`:: Spring Boot ::`)
- **JavaScript / Node.js**: NPM (`npm`)
- **Python**: Pip (`pip install`)

---

## 🚀 How to Use

### Basic Usage

#### 1. Read from a file (default `build.output.txt`)
```bash
python3 -m agent_log_trimmer build.log
```

#### 2. Pipe output directly from a build command
```bash
earthly +build 2>&1 | python3 -m agent_log_trimmer -
```
```bash
mvn clean test 2>&1 | python3 -m agent_log_trimmer -
```

---

## ⚙️ CLI Options & Arguments

```bash
usage: agent_log_trimmer [-h] [-c CONTEXT] [-m MAX_LINES] [--split-dir SPLIT_DIR] [--no-stats] [file]
```

| Argument / Option | Default | Description |
| :--- | :--- | :--- |
| `file` | `build.output.txt` | Path to the build log file (use `-` or stdin pipe). |
| `-c`, `--context` | `3` | Number of context lines to retain before and after error occurrences. |
| `-m`, `--max-lines` | `400` | Maximum total lines allowed per trimmed target stream. |
| `--split-dir` | `.build_logs` | Output directory where demuxed/split target logs are written. |
| `--no-stats` | Enabled | Disable printing log reduction statistics to `stderr`. |

---

## 📁 Output Structure

When run on a log with multiple target streams (e.g., Earthly or Bazel), `agent_log_trimmer` splits the output into separate target files under the `--split-dir` directory:

```
.build_logs/
├── global.log
├── +compile.log
└── +test.log
```

---

## 📊 Example Statistics Output

```text
Successfully split build log into 2 target log files in '.build_logs':
  - +compile -> .build_logs/+compile.log
  - +test -> .build_logs/+test.log

--- Agent Log Trimming Stats ---
Raw Lines:     12,450
Trimmed Lines: 320 (97.4% reduction)
Raw Bytes:     1,240,500 B
Trimmed Bytes: 28,400 B (97.7% reduction)
```
