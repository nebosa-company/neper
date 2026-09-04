# neper — general-purpose replacement verification

Status: verification plan, not language specification. This document adds no
syntax, runtime facility or standard-library API. `spec.md` remains authoritative
for the language, `grammar.ebnf` for concrete syntax, `tooling.md` for machine
interfaces, `modules.md` for the library plan, and `roadmap.md` for sequencing.

---

## 1. Claim under test

Neper's intended claim is:

> Neper is a compact, ahead-of-time general-purpose language for model-generated
> software, with explicit memory, deterministic semantics, inexpensive abstraction,
> native interoperability, and first-class CPU/GPU execution.

This is not a claim of source compatibility, runtime compatibility, ecosystem parity,
or feature parity with Python, Java, C#, C++, Rust or Go. The verification target is
that one compact language can cover a large, useful intersection of their workloads
without needing an unplanned language feature.

The expected replacement envelope is:

- C, C++, Rust and Go workloads that accept ahead-of-time compilation, explicit
  arenas, explicit concurrency and native interoperability.
- Python, Java and C# workloads that are deployed as compiled command-line tools,
  services, data processors, build tools, numerical programs or automation, and do
  not depend on a dynamic language runtime.

The following are deliberate non-claims, not verification failures:

- Rust-equivalent compile-time memory or data-race safety.
- Java/C#-equivalent managed object graphs or garbage collection.
- Python-compatible runtime evaluation, monkey patching or dynamic reflection.
- Language-level exceptions, closures, coroutines, classes or inheritance.
- Drop-in access to another language's package ecosystem.

If a workload requires one of those properties, neper is not its replacement. The
project must say that plainly rather than silently broadening the language.

---

## 2. Questions that must be answered with programs

The core language is considered general purpose only when representative programs
answer all of these questions without compiler-private escape hatches or an unplanned
language construct.

### Memory and lifetime

- Can a request, compiler pass, frame or batch own an arena and release all of its
  temporary state at one visible boundary?
- Can a long-running server, cache, editor and database client keep memory bounded
  while values have different lifetimes?
- Can persistent structures use explicit pools, free lists or arena generations
  without making their ordinary call sites error-prone?
- Are stale slices after `mem.reset`, slices across container growth and copied arena
  cursors caught reliably in debug builds?

Passing this section does not imply memory safety. Release-mode invalid memory access
and unsynchronised data races retain the semantics specified in `spec.md`; reports
must never describe neper as having Rust's static safety guarantees.

### Resource cleanup

- Does `defer` correctly clean up files, processes, threads, dynamic libraries,
  queues and buffers on ordinary return, every `try` propagation path and partial
  initialisation?
- Do debug checks reliably diagnose double close, use after close, wrong-device use
  and use of a consumed logical handle?
- Can APIs make ownership transfer legible without compiler-enforced linear types?

### Abstraction

- Can comptime parameters and protocols implement containers, sorting, formatting,
  parsing and serialization without duplicated algorithms?
- Can tagged unions and explicit function tables express state machines and dynamic
  dispatch where another language would use interfaces or classes?
- Can an explicit context pointer plus a function pointer express callbacks for an
  event loop, GUI binding and C API without closures?
- Do generated specialisations remain bounded in compile time and binary size?

### Errors and diagnostics

- Is `err` sufficient for routine propagation while explicit result/diagnostic
  structs carry payloads, source positions and causal context where required?
- Can parsers, network clients and database bindings report actionable failures
  without hidden allocation or exception state?
- Are cleanup and diagnostic context preserved when an error crosses several module
  boundaries?

### Concurrency and services

- Can the library express a bounded worker pool, channel, timeout, cancellation,
  backpressure and graceful shutdown over OS threads and explicit synchronization?
- Can an event loop serve many connections without one OS thread per connection?
- Can shutdown join or terminate every worker and release every resource
  deterministically?
- Are all shared-memory and ownership rules clear enough that model-generated code
  does not introduce races at an unacceptable rate?

### Interoperability and platforms

- Do all promised C ABI shapes round-trip on every host target?
- Do callbacks, opaque handles, calling conventions, packed records, dynamic
  libraries and ownership transfer behave identically under both linkers?
- Can existing C libraries supply capabilities that are intentionally outside the
  standard library without requiring special compiler knowledge?
- Are paths, process arguments, environment strings and filenames handled correctly
  on Windows, Linux and macOS, including non-ASCII input?

### Project scale

- Can a large program keep stable module boundaries when every module-scope
  declaration is exported?
- Can vendored dependencies be resolved reproducibly with versions, checksums,
  transitive dependencies and licences recorded outside the compiler?
- Do incremental and clean builds remain byte-identical as the module graph grows?
- Can tools rename, index and edit code without reparsing human diagnostic text?

---

## 3. Reference workload corpus

These programs are acceptance artifacts. Their purpose is to expose missing
semantics; they do not justify adding a feature automatically. When a program is
awkward, first attempt a library or design solution using the existing language. If
that remains unacceptable, record the workload as outside the replacement envelope
before proposing a language change.

| ID | Program | What it proves |
|---|---|---|
| GP-01 | Self-hosted neper compiler | Large program structure, parsers, interned strings, generic containers, incremental artifacts and deterministic parallel compilation |
| GP-02 | Cross-platform CLI | Arguments, configuration, Unicode input, JSON, filesystem traversal, diagnostics, exit codes and subprocesses |
| GP-03 | Parallel build executor | Worker pool, dependency scheduling, cancellation, timeouts, captured output and graceful shutdown |
| GP-04 | Long-running HTTP service | Bounded steady-state memory, sockets, event loop, backpressure, request arenas, logging and concurrent shutdown |
| GP-05 | Database client over a C library | FFI, callbacks, opaque handles, transactions, rich errors, ownership transfer and dynamic linking |
| GP-06 | Streaming data parser | Partial input, malformed input, fallible iteration, source spans, bounded buffers and recovery |
| GP-07 | Persistent bounded cache | Mixed lifetimes, insertion, lookup, eviction, fragmentation control and concurrency |
| GP-08 | Plugin-style C ABI | Stable exported ABI, callbacks with context pointers, version checks, foreign ownership and failure isolation |
| GP-09 | SIMD codec or compressor | Explicit vectors, masks, tails, alignment, target levels, scalar fallback and output equivalence |
| GP-10 | CPU/GPU numerical workload | Kernel reachability, transfers, capabilities, launch errors and deterministic CPU/device results within specified bounds |
| GP-11 | Interactive terminal application | Incremental input, terminal state cleanup, redraw, signals, resize and event handling |
| GP-12 | Multi-package application | Reproducible vendoring, checksums, transitive resolution, namespace composition, licences and clean-room rebuilds |
| GP-13 | Binary format reader/writer | Endianness, packed/external layout, bounds checks, zero-copy slices, malformed files and round trips |
| GP-14 | Image or audio transform pipeline | Large buffers, staged arenas, native library interop, parallel work and sustained memory bounds |

Each workload must have a written design before implementation identifying its arena
topology, resource ownership, concurrency model, error representation, foreign
boundaries and expected module graph. That design is part of the verification record.

---

## 4. LLM-generation evaluation

Character count is not token count, and no syntax is universally optimal across model
tokenizers. Token efficiency is therefore measured on the target model families and
never inferred from keyword length.

### Task set

For every workload, evaluate at least these task shapes:

1. Generate one complete module from a prose contract.
2. Add a function to an existing module without unrelated edits.
3. Change one constant or condition exactly as requested.
4. Repair a compiler diagnostic using only structured tool output.
5. Add a cross-module call and its import.
6. Add an error path with correct cleanup.
7. Refactor a type or function across multiple modules.
8. Complete an intentionally truncated or delimiter-damaged file.
9. Review code containing a lifetime, race, bounds or ABI defect.
10. Generate tests from a public signature and behavioral contract.

### Metrics

Record all of the following by model and model version:

- First-pass parse rate and first-pass type-check rate.
- First-pass test pass rate.
- Mean and 95th-percentile repair turns.
- Input, output and total model tokens.
- Tokens per non-comment source line and per syntax-tree node.
- Unrequested diff lines after canonical formatting.
- Hallucinated keywords, APIs, implicit conversions and language features.
- Identifier/import collisions and incorrect protocol names.
- Missing cleanup, ignored `err`, invalid lifetime and race defects.
- Percentage of repairs completed from JSON diagnostics without opening unrelated
  files.

The benchmark corpus, prompts, compiler version, formatter version, schemas, model
identifier and tokenizer identifier are versioned together. A syntax spelling is not
called more token-efficient unless the same semantic tasks improve total-token or
repair-turn results across the supported model set.

### Initial acceptance thresholds

Thresholds may be tightened after a baseline exists, but may not be silently relaxed:

- At least 95% of local edits parse on the first attempt.
- At least 90% of local edits type-check on the first attempt.
- Median unrelated diff lines after formatting: zero.
- At least 95% of compiler-error repairs complete in one additional turn.
- No benchmark task requires parsing human-formatted diagnostics.
- No accepted task relies on an undocumented compiler behavior or intrinsic.

Generation quality must also be compared with equivalent C, C++, Rust, Go, Python,
Java and C# tasks. Neper succeeds by reducing total model effort and review risk, not
merely by producing shorter files.

---

## 5. Semantic and implementation verification

### Conformance

- Every grammar production has at least one accepted case and every restriction has
  at least one rejected case with a stable diagnostic code.
- Operator, literal, cast, layout, control-flow, `try`, protocol and comptime rules
  have boundary-value tests.
- The bootstrap and self-hosted compilers accept and reject the same `neper-0`
  programs and emit the same structured diagnostics.
- Debug and release differences are enumerated; no unlisted semantic difference is
  accepted.

### Determinism

- Rebuild each workload clean and incrementally.
- Build with `-j 1`, every supported worker count and perturbed scheduling.
- Relocate the project and toolchain directories.
- Compare all deterministic artifacts byte for byte after excluding only fields the
  specification explicitly marks nondeterministic.
- Verify that JSONL records retain their specified order independent of completion
  order.

### Adversarial safety

Inject bounds errors, integer boundaries, stale slices, use-after-reset, invalid enum
representations, duplicate handle consumption, allocation exhaustion, failed partial
initialisation, races, malformed foreign input, device loss and process termination.
The observed result must be exactly the debug trap, returned `err`, defined release
result or documented undefined behavior promised by the specification.

### Portability

Every CPU-only workload runs on all supported host triples. Portable output and
behavior agree, excluding only explicitly platform-defined data such as path syntax,
clock values and enumeration order. ABI fixtures are compiled on both sides of every
C boundary and validate sizes, alignments, offsets, calling conventions and return
classes.

### Operational behavior

For every long-running workload, record peak memory, steady-state memory after warmup,
open handles, thread count, shutdown duration and behavior under repeated failure.
General-purpose readiness requires bounded resource use, not merely successful short
tests.

---

## 6. Replacement matrix

This matrix states what must be demonstrated before comparison language names appear
in project claims.

| Comparison | Neper must demonstrate | Claim that remains prohibited |
|---|---|---|
| C | Equivalent ABI reach, freestanding/native programs, predictable layout and competitive low-level performance | That release memory errors are defined or safe |
| C++ | Large native applications, generic containers, explicit polymorphism and reliable cleanup without constructors or RAII | Feature or ecosystem parity |
| Rust | Native performance, deterministic cleanup patterns and robust debug detection of lifetime/resource mistakes | Borrow-checker, memory-safety or race-safety equivalence |
| Go | Fast builds, cross-platform services, worker pools, networking and simple deployment | Goroutine, GC or language-level channel equivalence |
| Python | CLI tools, automation, parsers, data processing and rapid model-driven iteration | Dynamic evaluation, runtime reflection or source/package compatibility |
| Java/C# | Long-running services, FFI-backed applications, structured tooling and maintainable large projects | Managed-runtime, GC, reflection or exception equivalence |

Passing a row means neper is a viable implementation-language alternative for the
demonstrated workload class. It never means every program in the comparison language
should be ported.

---

## 7. Release gates

### Language-complete gate

- `spec.md` and `grammar.ebnf` contain no unresolved contradiction.
- The conformance plan covers every syntax and semantic rule.
- Each deliberate non-goal has an explicit existing-language construction or a
  documented excluded workload.
- No reference workload design identifies a required new language feature.

### Tool-complete gate

- Formatter, tokenizer/parser output, index, diagnostics, tests and build manifests
  use their versioned machine contracts from `tooling.md`.
- All source locations have exact byte spans suitable for automated edits.
- Clean, incremental, parallel and relocated builds pass determinism checks.

### General-purpose gate

- GP-01 through GP-08 and GP-12 pass on Windows and Linux.
- No long-running workload shows unbounded resource growth under its documented
  operating profile.
- The FFI and failure-injection suites pass on every promised host ABI.
- The LLM thresholds in §4 pass on at least two independently trained model families.

### Performance-language gate

- GP-09 and GP-10 meet their correctness requirements on every applicable backend.
- Compile-time, runtime and memory results are published against comparable C, C++,
  Rust and Go implementations using the same algorithms.
- Performance claims report distributions and workloads, not isolated best cases.

---

## 8. Decision rule when verification fails

A failed workload does not automatically authorize a language feature. Resolve it in
this order:

1. Correct an ambiguity or contradiction in the existing specification.
2. Use an existing construct more directly.
3. Move reusable policy into an ordinary library.
4. Use the specified C ABI to reuse a mature external implementation.
5. Narrow the replacement claim and document the excluded workload.
6. Only then open a separate language proposal, measured against the complexity and
   LLM-generation costs it introduces.

This order preserves the compact-language goal. The verification program exists to
test whether the chosen small core is sufficient, not to turn comparison-language
feature lists into neper's roadmap.
