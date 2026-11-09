# 2026-11-09-static-trace-tool

Commit (~/knowledge main, unpushed): a093800. Files changed: rules/global.md, decisions.md only.
wc -w rules/global.md: before 6693, after 6884.

Rule text (rules/global.md section 4, after the known-case bullet):

- **A code-tracing task runs a static tool for the stack.** A task that asks
  how data or control flows (where a value goes, whether it is escaped or
  sanitised before output, who calls what, which paths reach a sink) is not
  answered by reading file after file. The agent picks the tool by the stack: a
  taint or dataflow analyser for security traces (CodeQL, Joern, Semgrep taint
  mode, FindSecBugs), the language server's call hierarchy and references for
  call questions, `sg` for shapes. Where the project has none, the agent
  installs it, pinned and checked against the registry as under Dependency
  hygiene: in the sandbox that is 🟢+; on the host it is a new external
  dependency, 🟡, declared in the plan. A tool installed only to run the
  analysis is not a project dependency and stays out of the build and the
  lockfiles unless the task adds it there. The tool is first run on one known
  path, as under the known-case rule. The answer cites the tool's paths as
  `file:line` and adds only what the tool cannot judge: false positives, and
  sanitisers or framework behaviour it does not model.
