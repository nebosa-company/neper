# Compiler and toolchain design for token-efficient LLM coding agents

Status: non-normative research note, recorded 2026-09-18. This document surveys
compiler and toolchain support for the coding-agent loop: generate, edit, check,
diagnose, repair, run targeted tests, and repeat. It does not change the Neper
language or tooling protocol directly. Its gap review is adopted as requirements
R12–R16/H30–H34 in the hardening plan, roadmap and acceptance gates.

Related Neper documents:

- [`llm-hardening-recommendations.md`](llm-hardening-recommendations.md) contains the
  adopted recommendations.
- [`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) assigns the requirements to
  M2.5-core, T2, E2 and later release tracks.
- [`tooling.md`](tooling.md) defines Neper's current v1 tooling contract;
  [`tooling-v2-draft.md`](tooling-v2-draft.md) holds the non-normative T2 design.
- [`diagnostics.md`](diagnostics.md) defines Neper's stable diagnostic-code registry.
- [`llm-mcp-server.md`](llm-mcp-server.md) is a separate, unadopted MCP proposal.

## 1. Executive summary

There is no mature mainstream compiler that is explicitly optimized end-to-end for
an LLM coding agent. Several established toolchains nevertheless provide most of the
needed pieces:

1. **Go is the strongest general-purpose compiled default today.** It combines a
   small language, fast cached builds, canonical formatting, a standard test runner,
   stable JSON test events, and a persistent language server with low-latency
   diagnostics and code actions.
2. **Rust exposes the strongest compiler-to-agent diagnostic contract.** `rustc`
   emits structured JSON with stable codes, exact spans, suggested replacements, and
   suggestion applicability. `cargo check` avoids final code generation and
   `cargo fix` consumes machine-applicable suggestions. The tradeoff is a more
   expensive source and repair loop, especially around ownership, traits, and
   lifetimes.
3. **TypeScript provides an excellent persistent compiler service.** `tsserver`
   retains project state and exposes diagnostics, navigation, refactoring, and code
   actions through a JSON protocol. The full build/test loop is fragmented across
   several ecosystem tools.
4. **Python is often the cheapest language for agents to generate and revise, but it
   is not a compiled-language answer.** A stack using `uv`, Ruff, a type checker, and
   pytest is fast and compact, but more faults remain until execution.
5. **Zig is integrated and build-oriented, but not yet agent-oriented.** It has one
   toolchain for formatting, compilation, caching, and tests, while lacking the
   stable structured diagnostic and test protocols that distinguish Rust and Go.
6. **C and C++ can expose JSON, SARIF, LSP, and fast incremental builds, but the
   default experience remains noisy and fragmented.** Template diagnostics,
   preprocessor behavior, build-system diversity, and weakly standardized tests make
   them poor defaults for a token-constrained agent.
7. **Experimental "agent-native" compilers exist, but are not production evidence.**
   Kodo, Astra, Zero, and ANCP explore structured errors and repair plans. Their small
   ecosystems and limited training representation can cause more agent iterations
   than their protocols save.

The main opportunity is therefore not merely a new source language. It is a compact,
lossless, recoverable agent protocol over compiler, language-server, formatter,
static-analysis, execution, and test facilities. It should optimize total cost per
verified change rather than the size of one command response.

## 2. Scope and terminology

### 2.1 Included

This survey evaluates facilities used by an LLM that changes a software repository:

- reading only the semantic context needed for an edit;
- generating or amending source code;
- formatting source deterministically;
- performing a fast syntax/type/semantic check;
- receiving precise, bounded, machine-readable diagnostics;
- applying safe or explicitly reviewed repairs;
- compiling only what changed;
- executing a program safely;
- running the smallest relevant test set;
- receiving compact machine-readable test outcomes; and
- deciding reliably when the task is complete.

### 2.2 Excluded

This is not a survey of compilers that make neural-network inference faster.
TensorRT-LLM, MLC-LLM/TVM, XLA, TorchInductor, Triton, and similar systems optimize
the execution of an LLM model. They do not primarily optimize the compiler feedback
loop consumed by a coding agent.

The name "LLM Compiler" is also overloaded:

- Meta's LLM Compiler is a language model trained on LLVM IR and assembly for
  compiler-optimization research.
- Squeeze AI Lab's LLMCompiler schedules dependent and independent tool calls.
- DSPy uses "compile" for optimizing prompts and demonstrations against a metric.

None of those is the compiler/toolchain category evaluated here.

## 3. What must be optimized

Compiler speed and short source are necessary but insufficient. The target metric is:

> total time and total model tokens required to produce one independently verified,
> semantically correct change.

A useful evaluation separates at least the following dimensions.

| Dimension | Desired property | Common failure |
|---|---|---|
| Source representation | High useful behavior per token | Boilerplate reduction creates ambiguity or weak checking |
| Context retrieval | Small, complete semantic slices with provenance | Agent reads whole files or guesses unseen dependencies |
| Edit validation | Cheap syntax/type check after every edit | Full rebuild or delayed runtime discovery |
| Diagnostic density | Root cause, code, span, related sites, and fix | Long prose, repeated source excerpts, cascaded errors |
| Repairability | Typed or range-based edits with preconditions | Agent reparses prose and guesses replacements |
| Incrementality | Reuse unaffected semantic and generated results | One local edit invalidates the repository |
| Test selection | Run affected or named tests first | Entire suite runs after every small edit |
| Test transport | Failures plus aggregate success counts | Every passing test and framework banner enters context |
| Determinism | Same snapshot and inputs produce the same result | Races, stale files, hidden environment changes |
| Recoverability | Full logs available without re-execution | Compression deletes the evidence needed for diagnosis |
| Completion signal | Explicit verified success state | Agent keeps polishing and breaks passing code |
| Model familiarity | Strong training representation and stable APIs | Agent learns a novel language during the task |

The last row is easy to underestimate. Compact syntax in an unfamiliar language can
cost more overall when the agent needs repeated compile/repair turns. Conversely, a
somewhat more verbose language may reduce total cost if its compiler rejects faults
precisely on the first edit.

## 4. Comparative landscape

The ratings below are qualitative. They describe current toolchain properties, not a
cross-language benchmark on one controlled repository.

| Toolchain | Check latency | Structured diagnostics | Structured tests | Source-token pressure | Overall fit |
|---|---:|---:|---:|---:|---|
| Go | Excellent | Good through LSP; partial in CLI | Excellent | Low to medium | Best compiled default |
| Rust/Cargo | Moderate to good | Excellent | Mixed | High | Best correctness and repair signal |
| TypeScript/tsserver | Excellent while resident | Excellent | Framework-dependent | Low to medium | Best web/service loop |
| Python + uv/Ruff/type checker | Excellent | Good | Good with configuration | Low | Cheapest loop without native compilation |
| Zig | Good | Human-oriented | Integrated but not a stable agent protocol | Uncertain | Promising, incomplete agent surface |
| C/C++ + GCC/Clang/Ninja | Variable | Available but fragmented | Framework-dependent | High | Poor default; viable with a strong adapter |
| Java/Gradle or Maven | Moderate incrementally | Good through services | Framework-dependent | High | Mature, usually too verbose for this objective |
| C#/.NET/Roslyn | Good incrementally | Good through services | Framework-dependent | Medium to high | Strong ecosystem, less compact than Go/TypeScript |

## 5. Go

### 5.1 Strengths

Go's primary advantage is the coherence of the whole loop:

- `go build` and `go test` share a content-aware build cache.
- Package-list-mode tests cache successful results.
- `go test -json` emits newline-delimited test events with package, test, action,
  elapsed time, output, and failed-build information.
- Current `go build -json` and `go test -json` report build events as structured
  envelopes.
- `gofmt` provides one canonical source layout.
- `go vet`, the Go analysis framework, and `gopls` share analyzer infrastructure.
- `gopls` retains workspace state, updates syntax/type diagnostics rapidly, and
  exposes fixes as LSP code actions.
- Go 1.26 replaced `go fix` with an analyzer-based implementation that can apply
  safe transformations and preview them as diffs.
- One standard command family covers package discovery, build, test, format,
  dependency metadata, static analysis, and execution.

Representative agent operations are:

```text
gopls check path/to/file.go
gofmt -w path/to/file.go
go build -json ./...
go test -json ./...
go test -json ./path/to/pkg -run '^TestSpecificCase$'
go fix -diff ./...
```

### 5.2 Limitations

Go's CLI JSON is not a complete structured diagnostic protocol. Build events identify
the package and event type, but compiler output remains text in the `Output` field.
An agent seeking exact ranges and code actions should use `gopls`/LSP rather than parse
that text.

Go also provides fewer static guarantees than Rust. Fast feedback is valuable, but
some aliasing, protocol, state-machine, and resource-lifetime faults still require
tests, analysis, or runtime execution.

### 5.3 Assessment

For a new compiled system whose dominant maintainer is a coding agent, Go is the best
available default unless the domain requires stronger compile-time safety or a
different platform ecosystem. Its advantage comes from the integrated loop, not from
the compiler executable alone.

## 6. Rust and Cargo

### 6.1 Strengths

Rust exposes the richest stable compiler diagnostics in this comparison. `rustc`
JSON can include:

- a stable diagnostic or lint code;
- severity and parent/child relationships;
- precise file, byte, line, and column spans;
- source text associated with a span;
- macro-expansion provenance;
- suggested replacement text; and
- applicability such as `MachineApplicable`, `MaybeIncorrect`,
  `HasPlaceholders`, or `Unspecified`.

`cargo check` type-checks a package and its dependencies without final code
generation. It writes metadata for reuse by later invocations. `cargo fix` runs the
check pipeline, consumes JSON suggestions, applies eligible changes, and validates
the result.

Representative operations are:

```text
cargo check --all-targets --message-format=json
cargo check --all-targets --message-format=short
cargo fix
cargo test -q test_name
```

### 6.2 Limitations

Rust shifts many faults into compile time, but that can increase the number and
complexity of compile/repair interactions. Ownership, borrowing, trait selection,
generic bounds, macro expansions, and explicit error plumbing consume source and
reasoning tokens.

The standard Cargo message format structures compiler and artifact messages. Stable
structured output from the default Rust test harness is weaker: its JSON test format
remains unstable, so production integrations commonly require a separate test runner
or a normalizer over terse output.

### 6.3 Assessment

Rust is the best reference for Neper's diagnostic and repair protocol. It is not the
best evidence that maximum language strictness automatically minimizes total agent
cost. A held-out end-to-end measurement must decide whether earlier fault detection
outweighs additional source and repair turns for the target workload.

## 7. TypeScript and `tsserver`

### 7.1 Strengths

`tsserver` encapsulates the TypeScript compiler and language services in a persistent
process with a JSON protocol. It supports:

- syntactic and semantic diagnostics;
- compiler-option diagnostics;
- file-scoped queries;
- definitions and references;
- completion and quick information;
- rename and refactoring operations; and
- incremental work in a long-lived project context.

The language-service API can request inexpensive syntactic diagnostics without doing
whole-program semantic work, then request semantic information only where required.
This shape is well suited to an agent that edits one file and asks for the smallest
useful next result.

Representative batch operations are:

```text
tsc --noEmit --pretty false
tsc --incremental --noEmit --pretty false
```

For an agent product, `tsserver` or an LSP adapter is preferable to repeatedly
starting `tsc`.

### 7.2 Limitations

The whole TypeScript loop is not owned by one tool. Package management, formatting,
linting, bundling, execution, and tests may involve npm/pnpm, Biome/ESLint/Prettier,
Node/Bun, Jest/Vitest, and a bundler. Their messages and caches require normalization.

### 7.3 Assessment

TypeScript is an excellent choice for existing web repositories and a strong model
for persistent semantic queries. It is less attractive as a universal agent-oriented
toolchain because integration quality depends on project-specific surrounding tools.

## 8. Python with fast auxiliary tooling

Python is not a compiled-language solution, but it is an important lower bound for
agent-loop cost. A practical stack is:

- `uv` for fast, locked environment and dependency management;
- Ruff for cached linting, formatting, JSON diagnostics, and safe fixes;
- a persistent or incremental type checker; and
- pytest with quiet output and targeted tests.

Representative operations are:

```text
uv run ruff check --output-format=json .
uv run ruff check --fix .
uv run ruff format --check .
uv run pytest -q --maxfail=1 path/to/test_file.py::test_name
```

Ruff supports concise, grouped, JSON, JUnit, and other output formats. Mypy's daemon
and remote/incremental caches can reduce repeated type-check time substantially.

The price of a compact dynamic language is that fewer invalid states are rejected
before execution. Type annotations and tests mitigate but do not erase that
difference.

A 2026 controlled study of Python, Java, Rust, and OCaml across five models and 2,000
small agent trajectories found the fewest output tokens in Python. It also found that
agents often spent tokens looping on unfamiliar-language compile errors, prototyping
in Python before translating, and continuing to modify already-passing solutions.
The authors explicitly limit the result to their small competitive-programming tasks,
visible tests, agent scaffold, and model set; it is not a repository-scale language
ranking.

## 9. Zig

Zig has attractive integrated properties:

- one distribution includes compiler, formatter, build system, and test runner;
- debug mode prioritizes compilation speed and safety checks;
- the build system runs work in parallel and caches artifacts;
- tests are language-level declarations; and
- `zig test` and `zig build test` require little external framework configuration.

Its current agent-facing weakness is protocol maturity. Diagnostics and test output
are designed primarily for terminals, not as a versioned, stable stream of diagnostic
objects and typed repair operations. Model familiarity and ecosystem coverage are
also smaller than for Python, JavaScript/TypeScript, Go, Java, C++, or C#.

Zig is therefore a useful integrated-toolchain reference, but not yet the strongest
answer to token-efficient agent operation.

## 10. C and C++

Modern C/C++ tooling can expose many required primitives:

- GCC supports JSON and SARIF diagnostics and fix-it hints.
- Clang tooling and `clangd` expose structured diagnostics, semantic navigation, and
  code actions.
- Ninja and compiler caches can make local rebuilds fast.
- Test frameworks can emit JUnit or other structured reports.

The problem is composition. Preprocessor state, headers, templates, link stages,
build-system diversity, generated sources, platform flags, and framework-specific
tests frequently produce large cascades and verbose logs. A strong repository-specific
adapter can make C/C++ workable, but the unadapted toolchain is not token-efficient.

## 11. Experimental agent-native projects

### 11.1 Kodo

Kodo describes a language and compiler designed for agents, with JSON diagnostics,
stable error codes, machine-applicable patches, `kodoc fix`, contracts, and
compiler-enforced authorship/confidence metadata. These are relevant design ideas,
but the project has a very small ecosystem and its performance and correctness claims
are primarily project-reported.

### 11.2 Astra

Astra describes the compiler as an API. Its interface includes a fast verification
command, JSON diagnostics, stable codes, suggestions, an explanation command, and a
canonical generate/verify/repair loop. This is close to the desired surface but lacks
the ecosystem and evidence of an established production language.

### 11.3 Zero

Zero documents stable JSON diagnostic codes and separate structured repair plans.
The useful distinction is that a diagnostic can identify a repair kind without
silently applying it; a later command returns exact edits for review or execution.

### 11.4 ANCP

The Agent Native Compiler Protocol proposes a language-neutral wrapper over existing
compilers, linters, formatters, test runners, and build tools. It defines structured
diagnostics, repair hints, plans, verification steps, code facts, safety levels, and
versioned guidance. This architectural direction is more practical than requiring
every project to adopt a new source language, but ANCP itself is early-stage and not
an established standard.

### 11.5 Conclusion on experimental projects

These projects validate demand for machine-oriented compiler interfaces. They do not
yet establish that a novel language beats a familiar language plus a good adapter.
An LLM's lack of training representation can dominate surface-level token savings.

## 12. Token efficiency is an end-to-end property

### 12.1 Source tokens are only one component

Total task cost includes:

- repository context read by the model;
- source emitted and re-emitted;
- reasoning and tool-call tokens;
- compiler, linker, linter, and test output;
- repeated instructions and tool schemas;
- recovery calls after missing information;
- extra turns caused by ambiguous diagnostics; and
- work performed after the requested verification already passed.

The final source file can be short while the trajectory is expensive. Conversely,
explicit contracts can add source tokens while preventing several failed repair
turns.

### 12.2 Blind output truncation can lose globally

GitHub reported experiments in which indiscriminate shell-output compression reduced
individual responses but caused the agent to reopen logs or rerun commands. That
increased total tokens and task duration in the tested harness. Their more successful
policy was to:

1. preserve source-like and arbitrary output;
2. reorganize search output without losing matches;
3. compress repetitive build/test/install noise selectively; and
4. retain a direct path to the complete original output.

The result is a critical design rule:

> Minimize recoverable noise, not information required to choose the next correct
> action.

### 12.3 Completion must be machine-obvious

The 2026 cross-language study observed agents continuing to revise solutions after
all visible tests passed, sometimes regressing correct code. A tool protocol should
return an explicit terminal state containing:

- the snapshot verified;
- requested checks and tests completed;
- aggregate counts;
- whether the result is complete or truncated;
- unproved or skipped obligations; and
- a stable success/failure field.

The agent harness should stop or require an explicit new reason before editing a
fully verified snapshot.

## 13. Recommended agent-facing protocol

### 13.1 Check result

An unsuccessful check should prefer normalized semantic fields over rendered prose:

```json
{
  "schema": "agent-check/1",
  "ok": false,
  "snapshot": "sha256:...",
  "phase": "typecheck",
  "diagnostics": [
    {
      "id": "diag-1842",
      "code": "E-TYPE-0003",
      "severity": "error",
      "message": "argument type does not match its parameter",
      "file": "src/store.neper",
      "range": { "start_byte": 418, "end_byte": 426 },
      "expected": "UserId",
      "actual": "String",
      "related": [],
      "fixes": [],
      "provenance": "compiler-proved"
    }
  ],
  "omitted_diagnostics": 3,
  "complete": false,
  "full_result": ".agent/results/check-1842.json"
}
```

Requirements:

- identify the workspace snapshot and compiler/tool versions;
- use stable codes and normalized fields;
- preserve exact edit locations;
- distinguish primary causes from dependent cascades;
- bound response bytes and record counts;
- report omissions explicitly;
- make complete results retrievable without rerunning the check; and
- associate fixes with preconditions and applicability.

### 13.2 Test result

Passing tests should collapse into counts. Failing tests should retain the evidence
needed to repair them:

```json
{
  "schema": "agent-test/1",
  "ok": false,
  "snapshot": "sha256:...",
  "selected": 128,
  "passed": 127,
  "failed": [
    {
      "name": "store.deletes_expired",
      "location": "tests/store_test.neper:84",
      "message": "expected 0, actual 1",
      "stdout_ref": null,
      "stderr_ref": ".agent/results/test-842.stderr"
    }
  ],
  "skipped": 0,
  "duration_ms": 613,
  "complete": true
}
```

Requirements:

- allow exact test, module, affected-set, and full-suite selection;
- do not stream successful test bodies by default;
- include deterministic failure identity and source location;
- separate assertion evidence from arbitrary process output;
- retain stdout/stderr by reference when large;
- distinguish compile failure, setup failure, timeout, crash, and assertion failure;
- record cached results rather than presenting them as newly executed; and
- return an explicit all-requested-tests-passed state.

### 13.3 Repair result

A repair should be a transaction, not an unconditioned patch:

```json
{
  "schema": "agent-edit/1",
  "snapshot": "sha256:...",
  "operations": [
    {
      "kind": "replace-expression",
      "file": "src/store.neper",
      "precondition": { "node_id": "expr-91", "content_hash": "sha256:..." },
      "replacement": "UserId.parse(raw_id)?"
    }
  ],
  "validate": ["format", "check:affected", "test:affected"]
}
```

All preconditions must be validated before any file is written. Failure leaves the
workspace untouched. Successful application returns the new snapshot and the exact
validation evidence.

## 14. Recommended coding-agent loop

1. Capture an immutable workspace snapshot.
2. Query compiler-derived context for the target declaration and its callers,
   contracts, effects, ownership, tests, and unsafe boundaries.
3. Apply one bounded edit transaction.
4. Run the canonical formatter or reject non-canonical output.
5. Run an affected-file or affected-declaration syntax/type check.
6. Return only root diagnostics plus explicit omission metadata.
7. Apply only machine-applicable fixes automatically; present other repairs as plans.
8. Run the narrowest relevant unit tests.
9. On failure, return failure evidence and a recoverable full log reference.
10. On local success, run the required wider verification tier.
11. Return a terminal verified state for the exact snapshot.
12. Stop editing unless the user requested additional work or an explicit obligation
    remains.

The loop should use a persistent semantic service where startup or repository loading
is material. Cache identity must include source snapshot, compiler version, options,
target, dependencies, generated inputs, and relevant environment facts.

## 15. Implications for Neper

This research supports most of the direction already recorded in Neper's hardening
plan. The comparison also exposed five places where an earlier mechanism did not yet
guarantee a best-in-category agent experience; those gaps are now registered as
R12–R16/H30–H34 rather than as a parallel roadmap.

| Finding | Existing Neper mapping |
|---|---|
| Stable structured diagnostic identity and typed fields | `diagnostics.md`; H09, H18 |
| Exact, preconditioned, transactional repairs | R04/R11; H09, H17, H29 |
| Compiler-derived bounded context with provenance | R02; H08 |
| Declaration/query-level reuse | R06; H14-H16 |
| Machine-readable, compact, recoverable transport | H18 |
| Token cost measured across a verified edit | R03/R08; H12, H25, H26 |
| Formatter and tests are part of the compiler product | H10, H11, H25 |
| Enumerated unsafe boundary | R09; H27 |
| Cards and API data generated from authoritative registries | R05/R10; H11, H28 |
| Stop after complete verification | H12/H25 benchmark and harness policy |
| Explicit tiered fast-check operation and latency rank | R12; H30 |
| Root-cause compact diagnostics with durable full evidence | R13; H31 |
| Compact structured test plans/results and cache provenance | R14; H32 |
| Source plus protocol token-pressure budgets | R15; H33 |
| Discoverable end-to-end workflow and verified stop state | R16; H34 |

The external landscape adds five practical cautions:

1. **Do not optimize only source compactness.** Measure repair turns, compiler output,
   tests, and escaped defects.
2. **Do not claim that richer static checking is automatically cheaper.** It must win
   on held-out total-cost measurements.
3. **Do not expose only terminal-formatted diagnostics.** Keep normalized semantic
   fields and render prose as a view.
4. **Do not discard full evidence while compacting the common response.** Store it
   under a snapshot-bound result reference.
5. **Do not introduce a persistent daemon before snapshot identity, cancellation,
   resource lifetime, and cache correctness are specified.** A fast stale answer is
   worse than a slower correct one.

## 16. Possible future language improvements — not scheduled

The ideas in this section would change Neper source or program semantics. They are
recorded for future evaluation only: they are not adopted requirements, have no
roadmap milestone, do not block M2.5-core, T2, E2 or M3, and must not be inferred from the tooling
features recommended above. Adoption requires a separate language proposal,
versioning and explicit approval.

### 16.1 Intent blocks

An intent block would attach a structured goal or constraint to a declaration, for
example an allocation prohibition, ordering guarantee or latency bound. A normative
form could let the compiler or verifier reject an implementation that violates the
declared intent, while an advisory form could help an agent choose among otherwise
valid edits.

The normative form is a language feature, not structured documentation. Its design
would have to settle:

- which declarations accept intent and which predicates can be expressed;
- whether intent affects validity, optimization, overload resolution or only an
  optional verification mode;
- how names, generics, effects, ownership and target profiles are resolved inside an
  intent;
- whether obligations are statically proved, dynamically checked or reported as
  unknown;
- how intent participates in module interfaces, incremental identity, generated
  source, diagnostics and compatibility; and
- how deterministic tools interpret it without embedding natural-language prompts
  or vendor-specific agent instructions in source.

An advisory form should remain external structured metadata unless evidence shows
that making it syntax improves independently verified changes. A normative form
should reuse a general contract/effect mechanism rather than create a parallel
agent-only semantics. Do not add generic prose such as `intent "make this fast"`:
its meaning cannot be checked consistently and would make builds model-dependent.

Reconsider intent blocks only after ordinary contracts and effects are stable, and
only if held-out tasks show that existing types, effects, tests and documentation
cannot express the needed property. The proposal must define executable or provable
acceptance conditions and preserve deterministic compilation when no agent exists.

### 16.2 Contracts, refinement types and SMT proving

A future contract system could add preconditions, postconditions and invariants; a
later refinement layer could constrain values with predicates; an optional SMT-backed
mode could attempt to discharge those obligations statically. These are three stages,
not one indivisible feature:

1. **Executable contracts:** restricted `requires`, `ensures` and invariant clauses
   with defined debug/release behavior and ordinary structured failures.
2. **Refinement checking:** predicate-bearing aliases or parameters whose obligations
   flow through calls, generics and control flow.
3. **SMT discharge:** translate a documented, decidable subset into proof obligations
   and return proved, disproved or unknown with reproducible counterexamples and
   resource bounds.

Any proposal must define the contract expression subset; purity and effect rules;
pre-state and result references; integer overflow, floating-point, pointer, alias and
collection semantics; loop and recursion obligations; generic/module compatibility;
runtime-check insertion; ABI consequences; and proof/cache identity. Solver timeout,
unsupported theory and resource exhaustion must produce explicit `unknown` or a
required runtime check, never silent success. Solver version and options are evidence
inputs, and a solver proof cannot replace required behavioral tests outside the
modeled fragment.

The smallest credible experiment is executable contracts over existing Boolean
expressions. Refinement types should follow only if that experiment demonstrates
clear defect-prevention and repair benefits without excessive annotations. SMT
proving should remain an optional verifier until its sound fragment,
counterexamples, determinism and maintenance burden are independently validated.
No syntax spelling or enforcement policy is selected by this document.

## 17. Decision guidance

For teams choosing an existing platform:

- Choose **Go** for the strongest balance of compiled execution, loop speed,
  integrated tools, compact tests, and model familiarity.
- Choose **Rust** when compile-time prevention and precise machine-applicable
  diagnostics justify higher source and repair cost.
- Choose **TypeScript** for web systems already centered on its language service and
  JavaScript ecosystem.
- Choose **Python plus fast tooling** when development-loop cost dominates and the
  application can tolerate runtime verification backed by strong tests and types.
- Use **C/C++** only when required by the domain or existing repository, and budget
  for a repository-specific diagnostic/test normalizer.
- Treat new **agent-native languages** as experimental until they demonstrate
  held-out repository-scale success, total tokens, latency, escaped-defect rate, and
  migration/ecosystem viability.

For Neper, the recommended product is the compiler plus its semantic context,
structured edit, verification, and test protocols. The command-line compiler alone
cannot establish an LLM-optimized toolchain.

## 18. Evidence and limitations

The conclusions combine documented interfaces with engineering inference. They do
not report a controlled benchmark run by this repository.

Key limitations:

- Tool versions and protocols continue to change.
- Compiler latency depends on repository shape, dependencies, hardware, and cache
  warmth.
- Token count depends on the model tokenizer, agent harness, prompts, tool schemas,
  and task distribution.
- Language familiarity in model training may change substantially between model
  generations.
- Competitive-programming results do not automatically transfer to multi-file
  maintenance, refactoring, concurrency, FFI, or build-system work.
- Vendor and project performance claims require independent reproduction.
- Qualitative ratings in this note are decision aids, not acceptance evidence for
  Neper's H12/H25 gates.

Any claim that Neper is faster, cheaper, safer, or more LLM-friendly must still pass
the repository's pre-registered, held-out, multi-family evaluation and independent
semantic oracles.

## 19. Primary references

Mainstream toolchains:

- Go command, build/test cache, and JSON event documentation:
  <https://go.dev/cmd/go/?m=old>
- Go `test2json` event schema: <https://go.dev/cmd/test2json/?m=old>
- `gopls` diagnostics and quick fixes:
  <https://go.dev/gopls/features/diagnostics>
- `gopls` code transformations:
  <https://go.dev/gopls/features/transformation>
- Go 1.26 `go fix`: <https://go.dev/blog/gofix>
- Rust compiler JSON diagnostics: <https://doc.rust-lang.org/rustc/json.html>
- Cargo `check`: <https://doc.rust-lang.org/cargo/commands/cargo-check.html>
- Cargo `test`: <https://doc.rust-lang.org/cargo/commands/cargo-test.html>
- Rust test-runner formats: <https://doc.rust-lang.org/rustc/tests/>
- TypeScript standalone server:
  <https://github.com/microsoft/TypeScript/wiki/Standalone-Server-%28tsserver%29>
- TypeScript language-service API:
  <https://github.com/microsoft/typescript/wiki/using-the-language-service-api>
- Ruff: <https://docs.astral.sh/ruff/>
- Ruff output formats: <https://docs.astral.sh/ruff/settings/#output-format>
- uv: <https://docs.astral.sh/uv/>
- Zig language, build, formatter, and test documentation:
  <https://ziglang.org/documentation/master/>
- GCC structured diagnostic formats:
  <https://gcc.gnu.org/onlinedocs/gcc-14.1.0/gcc.pdf>

Agent and token-efficiency evidence:

- Wu, Anderson, and Guha, *The Best Programming Language for Tokenmaxxing: An
  Investigation of Coding Agent Behavior Across Programming Languages* (2026):
  <https://arxiv.org/abs/2607.22807>
- GitHub, *How we make AI coding more cost efficient without sacrificing task
  quality* (2026):
  <https://github.blog/ai-and-ml/github-copilot/how-we-make-ai-coding-more-cost-efficient-without-sacrificing-task-quality/>
- Visual Studio Code, *Improving token efficiency for GitHub Copilot in VS Code*
  (2026):
  <https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot>

Experimental agent-oriented interfaces:

- Kodo: <https://github.com/rfunix/kodo>
- Astra agent interface: <https://astra-lang.org/agents.html>
- Zero JSON diagnostics: <https://coddy.tech/docs/zero/json-diagnostics>
- Agent Native Compiler Protocol: <https://github.com/TwentySevenLabs/ancp>

Naming clarifications:

- Meta LLM Compiler:
  <https://ai.meta.com/research/publications/meta-large-language-model-compiler-foundation-models-of-compiler-optimization/>
- LLMCompiler for parallel function calling:
  <https://github.com/SqueezeAILab/LLMCompiler>
- DSPy prompt optimization:
  <https://dspy.ai/current/getting-started/gepa-optimization/>
