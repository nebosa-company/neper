# Neper Model Context Protocol (MCP) Server & LLM Optimization Specification

Status: **proposal, not adopted.** Nothing here is normative, and nothing here is
evidence of implementation. `spec.md`, `grammar.ebnf`, `tooling.md`, `modules.md` and
`decisions.md` remain authoritative, and this document changes none of them; it would
become normative only through a versioned amendment during the T2 track scheduled in
[`post-m2-llm-hardening.md`](post-m2-llm-hardening.md).

Read it against the adopted set in
[`llm-hardening-recommendations.md`](llm-hardening-recommendations.md) before acting on
it. Three points of contact are open and have to be settled first:

- **`neper patch` (section 4) conflicts with R11/H29.** R11 demotes byte spans to the
  lossless and trivia cases and requires semantic refactors to be typed operations with
  pre- and postconditions: "no edit is applied from a span that the compiler has not
  re-validated against the target snapshot." The payload in section 4 carries no
  snapshot precondition at all, and R04/H09 additionally require apply to be
  transactional across files.
- **`neper header` (section 4) overlaps R05**, the executable retrievable API
  catalogue, under a different name. One of the two should own the surface.
- **The targets in section 5 are unadopted numbers.** R03 owns token-cost measurement
  and is explicit that character count is not token count; fixed thresholds like
  "< 150 tokens per valid edit" need R03's measurement basis and R07's held-out
  evidence gate behind them before they can gate anything.

The MCP server itself (sections 1-3) is the part with no counterpart elsewhere in the
doc set. It is a client over `neper index --json`, `neper parse --json` and
`neper check`, not a language or compiler rule, so it needs an owning milestone rather
than a place in the specification.

## 1. Need

Language models operating in automated loop pipelines (e.g., local models running over IPC or socket transports) suffer from context degradation and token waste when forced to ingest whole source files. Neper’s verbosity and explicit casts guarantee semantic clarity for human reviewers, but reading full files into an inference context incurs heavy prompt latency and context window depletion.

A native Neper Model Context Protocol (MCP) server acts as a zero-overhead structural filter between the project DAG and the model context. By executing directly against the compiler's lossless JSONL streams, the server exposes targeted tools that return minimal, high-density syntax and diagnostic subsets.

## 2. Native MCP Server Architecture & Design

```
+-------------------+      JSON-RPC / stdio      +-------------------------+
| Editor / Agent    | <------------------------> | Neper Native MCP Server |
| (Zed / VS Code)   |                            | (e.os, e.mem, e.str)    |
+-------------------+                            +-------------------------+
                                                              |
                                                    os.spawn  | JSONL Stream
                                                              v
                                                 +-------------------------+
                                                 | neper toolchain CLI     |
                                                 | (index, parse, check)   |
                                                 +-------------------------+
```

* **Transport & Event Loop:** Implemented as a standalone Neper binary using `e.os`. It listens on `os.stdin()` and writes framed JSON-RPC 2.0 messages to `os.stdout()`. Non-blocking IO multiplexing uses `os.poller_wait` on standard stream handles to prevent notification deadlocks.
* **Memory Cycle:** Per-request allocations are bound to a request-scoped `mem.Arena`. After parsing the payload, dispatching a child process via `os.spawn`, and writing the filtered RPC output using a flushing `str.Builder`, the loop invokes `mem.reset` to maintain a flat memory footprint across long-running sessions.
* **Process Supervision:** Compiler invocations run as asynchronous subprocesses piped to `os.pipe` ends. Output streams are consumed directly into memory buffers without intermediate disk writes.

## 3. Required MCP Tool Exposures

| Tool Name | Parameters | Input Compiler Target | Return Payload Requirement |
|---|---|---|---|
| `get_symbol_definition` | `symbol: str` | `neper index --json` | Exact `selection_span`, signature, and `///` documentation string. |
| `get_build_diagnostics` | `module: str` | `neper build` or `neper check` | Array of `diagnostic` records containing byte-precise spans and structured `fixes`. |
| `get_symbol_references` | `symbol: str`, `role: str` | `neper index --json` | List of reference locations filtered by role (`call`, `type`, `protocol`, `instantiate`). |
| `get_ast_subtree` | `path: str`, `span: Span` | `neper parse --json` | Lossless node subtree with all `space` and `comment` trivia stripped. |

## 4. Compiler Tooling Enhancements for LLM Performance

* **Surgical Byte-Patch Engine (`neper patch`):** A dedicated CLI command `neper patch [--check] [FILE.e|-]` must accept structured replacement payloads directly from JSON:
  ```json
  {"path":"src/lex.e", "edits":[{"byte_start":128, "byte_end":140, "replacement":"let count: u32 = 0"}]}
  ```
  Rather than requiring the model to rewrite whole functions or emit fragile unified diffs, the model streams exact byte offset replacements. The compiler applies the patch in-memory, executes type checking, and returns immediate pass/fail feedback.
* **Trivia-Aware Compiler Strip Mode:** Expose a native `--no-trivia` flag on `neper tokens` and `neper parse`. Moving trivia suppression into the parser core eliminates array allocation and string scanning overhead in client tools, returning raw AST structures instantly.
* **Interface Dumps (`.em` Header Queries):** Implement `neper header <module.em>` to allow direct binary extraction of exported module interfaces from compiled `.em` files. This provides models with a pre-compiled, exact API signature map of external dependencies without re-parsing source `.e` files.

## 5. Benchmark and Measurement Suite

To benchmark and optimize Neper's performance as an LLM target, implement a dedicated test harness under `benchmarks/llm_edit`:

| Metric | Target Goal | Measurement Method |
|---|---|---|
| **Token Efficiency Ratio (TER)** | $< 150$ tokens per valid edit | Ratio of prompt and completion tokens used to perform a multi-file refactor versus the total token size of affected modules. |
| **Repair Latency (RTT)** | $< 250\text{ ms}$ total loop | Time elapsed from diagnostic emission to MCP response, model patch, and clean compilation. |
| **First-Pass Pass Rate (FPPR)** | $> 85\%$ compilation success | Percentage of model-generated function bodies that compile cleanly on the first attempt without type or cast errors. |
| **Edit Locality Index (ELI)** | $1.0$ (Ideal) | Measured as $(\text{Targeted Edit Byte Span}) / (\text{Total Bytes Modified by Model})$. Values above $1.0$ indicate unintended model drift. |
