# Workspace Agent Rules

## Build Log Filtering & Token Optimization

When running complex build/test commands (e.g., Earthly, Maven, Gradle, Bazel, NPM, Pip) or analyzing large build output logs:
- Always process or pipe log output through `agent_log_trimmer` (e.g., `command 2>&1 | python3 -m agent_log_trimmer -` or using `tools/agent_log_trimmer`).
- Use the trimmed output files (generated in `.build_logs/`) to analyze compilation/test errors and root causes.
- This filters progress bars, download noise, and repetitive warnings, preserving context tokens and pinpointing failure points.

## Code Refactoring and Structural Rewrites

To optimize token consumption and ensure accurate structural edits across files, follow these guidelines when performing refactorings or pattern replacements:
1. **Primary Tool:** Use **`ast-grep` (`sg`)** for structural search and replace if the language is supported (e.g., Java, JavaScript, TypeScript, React/TSX, Python, JSON). 
   - *Example:* `sg run -p 'pattern($A)' -r 'replacement($A)' --update-all`
2. **Fallback Tool:** Use **`comby`** if the language or specific nested structure is not well-supported by `ast-grep`.
   - *Example:* `comby 'if (:[cond]) { :[body] }' 'if (!(:[cond])) return; :[body]' .js`
3. **Deep Semantic Rewrites:** For complex, project-wide semantic refactorings (especially in Java), use **OpenRewrite**. Modify the project's `pom.xml` or `build.gradle` to include the appropriate OpenRewrite recipe plugins rather than using command-line text replacements.

## Bounded File Viewing & Code Navigation

- Always locate target symbols or functions using `grep_search` or `ast-grep` (`sg`) before viewing files.
- Use `view_file` with explicit `StartLine` and `EndLine` bounds (e.g., 50-100 line window around target code) rather than reading entire large files into context.

## Surgical Code Editing

- Always use `replace_file_content` or `multi_replace_file_content` with minimal, pinpoint replacement chunks.
- Never rewrite full files or re-generate large unchanged blocks of code.
- Preserve existing comments, docstrings, and unrelated formatting.

## Targeted Test Execution

- Never run full test suites when debugging a single test failure. Always restrict execution to the specific test class or method:
  - **Maven:** `mvn test -Dtest=TestClassName#methodName`
  - **Gradle:** `./gradlew test --tests TestClassName.methodName`
  - **Pytest:** `pytest path/to/test.py::test_name`
  - **NPM/Jest:** `npm test -- -t "test name pattern"`
- Always pipe test execution output through `agent_log_trimmer`.

## Schema & Log Verification

- Never guess API request/response structures, DTO schemas, or method signatures. Inspect the authoritative symbol definition before writing integration code.
- Base diagnostic hypotheses strictly on empirical log evidence and error tracebacks.

## Project Architecture Mapping (`PROJECT_MAP.md`)

- In any workspace, create and maintain a concise `PROJECT_MAP.md` (or `.agents/PROJECT_MAP.md`) file detailing:
  - High-level project architecture and module breakdown.
  - Key entrypoints, CLI scripts, configuration files, and core service components.
  - Role and responsibility of major directories and core source files.
- **Maintenance:** Update `PROJECT_MAP.md` whenever adding new components, deleting modules, or performing structural refactorings.
- **Token Efficiency:** Keep descriptions concise (1-2 sentences per file/component) so the map remains a lightweight index rather than a detailed code dump.
