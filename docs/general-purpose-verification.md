# neper — general-purpose replacement verification

Status: verification plan, not language specification. This document adds no
syntax, runtime facility or standard-library API. `spec.md` remains authoritative
for the language, `grammar.ebnf` for concrete syntax, `tooling.md` for the closed v1
machine interface, `tooling-v2-draft.md` for the non-normative successor design,
`modules.md` for the library plan, and `roadmap.md` for sequencing.

The post-M2 plan in
[`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) separates the narrow
M2.5-core language/GPU-contract gate from T2 tooling-v2 conformance and E2 comparative
evaluation. Only M2.5-core blocks M3. Current guarantees remain those in `spec.md`
and the closed v1 tooling protocol until their responsible track lands a versioned
replacement. None implies completion of broader workloads requiring M3, M4, M6 or
later libraries.

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
- Which stale slices after `mem.reset`, views across container growth and copied
  arena cursors are rejected or detected, and which remain unprotected? The current
  spec explicitly leaves a pre-growth slice silently stale; poison bytes are not
  reliable lifetime detection. M2.5-core H01–H03 require an enforced checked subset and
  separately reported unsafe/unknown cases rather than assuming debug fills suffice.

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
| GP-05 | Database client implementing `e.db` over a C library | FFI, callbacks, opaque handles, streaming row reads, transactions, rich errors, ownership transfer and dynamic linking |
| GP-06 | Streaming data parser | Partial input, malformed input, fallible iteration, source spans, bounded buffers and recovery |
| GP-07 | Persistent bounded cache | Mixed lifetimes, insertion, lookup, eviction, fragmentation control and concurrency |
| GP-08 | Plugin-style C ABI | Stable exported ABI, callbacks with context pointers, version checks, foreign ownership and failure isolation |
| GP-09 | SIMD codec or compressor | Explicit vectors, masks, tails, alignment, target levels, scalar fallback and output equivalence |
| GP-10 | CPU/GPU numerical workload | Kernel reachability, transfers, capabilities, launch errors and deterministic CPU/device results within specified bounds |
| GP-11 | Interactive terminal application | Incremental input, terminal state cleanup, redraw, signals, resize and event handling |
| GP-12 | Multi-package application | Reproducible vendoring, checksums, transitive resolution, namespace composition, licences and clean-room rebuilds |
| GP-13 | Binary format reader/writer | Endianness, packed/external layout, bounds checks, zero-copy slices, malformed files and round trips |
| GP-14 | Image or audio transform pipeline | Large buffers, staged arenas, native library interop, parallel work and sustained memory bounds |
| GP-15 | Declarative GPU desktop application | Embedded asset and DPI/theme/locale variants, frame-arena widgets, keyed state reconciliation, constraint layout, shaped text, ordered input, accessibility, deterministic animation, GPU presentation and headless snapshots |

Each workload must have a written design before implementation identifying its arena
topology, resource ownership, concurrency model, error representation, foreign
boundaries and expected module graph. That design is part of the verification record.

---

## 4. LLM-generation evaluation

Character count is not token count, and no syntax is universally optimal across model
tokenizers. Token efficiency is therefore measured on the target model families and
never inferred from keyword length.

The prioritized recommendation set in
[`llm-hardening-recommendations.md`](llm-hardening-recommendations.md) elevates this
principle from a measurement obligation to a **design input** (R03, R08/H26): a
grammar-versioned tokenizer profile per supported family must exist, and a proposed
syntax spelling is changed only when a measured token or repair-turn improvement on
that profile justifies it, never on a character-count argument. The per-tokenizer
report below is a required input to that decision and to the H12/H25 gate.

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
- Cold and warm p50/p95 syntax, affected-semantic and workspace check latency, plus
  p95 time to first useful diagnostic.
- Mean and 95th-percentile repair turns.
- Input, output and total model tokens.
- Tokens per non-comment source line and per syntax-tree node.
- Tokens and bytes separately for guidance, context, edits, diagnostics, tests,
  complete-result retrieval and final verification.
- Independent root diagnostics, dependent/suppressed counts, diagnostic bytes per
  repaired fault and percentage of repairs that need neither prose parsing nor a
  repeated check to recover omitted evidence.
- Diagnostic-fingerprint retention after offset-only edits and rejection after a
  changed anchor; hint-only bytes, repair-plan retrieval bytes, and plan status.
- Planned action effects by kind and scope, including false-empty effect sets for
  project execution, dependency, network, credential, VCS and external writes.
- Selected/executed/cached test counts, affected-set completeness, default all-pass
  result bytes and failure-evidence retrieval bytes.
- Verified, failed, incomplete and cancelled terminal outcomes; edits made after a
  `verified` result are counted as over-edits.
- Verification-receipt validation, missing/modified evidence rejection and proof-core
  bytes; subjective confidence or authorship labels never count as evidence.
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
merely by producing shorter files. This **broad-generation cohort** characterizes
transfer and does not support a leadership claim.

### E2 five-category agent-experience claim gate

The comparative portions of H30–H34 make the E2 claim explicit. The **registered
agent-tooling cohort** is Go, Rust, TypeScript and Python. Pre-register eligible
equivalent workloads using each ecosystem's native cached compiler/language service,
structured diagnostic path, formatter and configured test runner. A reference is
ineligible for a task it cannot express with the same behavioral
and safety oracle; exclusions and adapter/setup costs remain in the report. Freeze the
hardware, repositories, cache states, tool versions, model versions, prompts,
tokenizers, confidence method and non-inferiority margin before candidate tuning.
Also freeze the overall composite's normalization, weights and penalties for failed,
timed-out, incomplete and escaped-defect cases; a post-result weighting change is a
new experiment, not the registered gate.

Report these categories independently:

| Category | Primary measures | Required result |
|---|---|---|
| Check latency | Warm p50/p95 total and p95 first useful diagnostic for syntax, local semantic and workspace checks | First or statistically tied for first |
| Structured diagnostics | Verified one-turn repair, root-cause precision, cross-edit fingerprint correlation, hint/plan/effect accuracy, output/retrieval tokens and no prose parsing | First or statistically tied for first |
| Structured tests | Selection-to-result latency, all-pass bytes, failure evidence, repair success and selection completeness | First or statistically tied for first |
| Source/token pressure | Source tokens and all interaction tokens per verified success, including failures and retrieval | First or statistically tied for first |
| Overall fit | Receipt-backed verified completion, escaped defects, wall time, total tokens, retries and over-edits through the canonical loop | Strictly better composite verified cost than the best eligible reference in both model families |

No category may be won by weakening an oracle, hiding setup/tool-schema tokens,
discarding failures, truncating unrecoverable evidence, counting cached tests as newly
executed or stopping before the requested wider verification tier. If any category
misses its threshold, publish the measured result but do not claim the best LLM coding
experience among the registered cohort and do not close the comparative portion of
H34 or the E2 claim.
This does not reopen T2 functional conformance or block a compiler/backend milestone.

E2 may recommend a syntax or API spelling change but never authorizes one. Adoption
requires a separate versioned language/API milestone, normative amendments,
compatibility analysis and migration evidence; the proposal is not needed to close
T2 or E2 and cannot move the contract under concurrent backend work.

The applicable H35–H44 operational contracts are mandatory for the same runs. Each
accepted task has a hashed external change contract and requirement-to-evidence coverage; execution uses
an enforced policy and an environment classified as hermetic, observed or
uncontrolled; retries preserve flaky outcomes; runtime failures remain structured;
and parallel change bundles are verified again after integration. Exercise API/ABI
diffs, performance obligations and disconnect/approval/cancellation recovery where
the task requests them. A run cannot count as verified when a required obligation is
uncovered, a prohibited effect occurs, required hermeticity is absent, a required test
is flaky/quarantined, or the receipt names only a pre-integration snapshot.
The reference `neper-agent-host` or an independently conforming host must supply that
policy, environment and coverage evidence; a T2.2 evidence package alone is
`incomplete` and cannot enter the verified-success denominator.

### E2 evaluation and claim closure

H12 and the applicable E2 portions of H30–H44 in
[`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) are the additional
acceptance protocol for the versioned claim. It requires a preserved M2 baseline,
pre-registered held-out tasks, at least two independently trained model families,
real compiler/query/repair tools, independent behavioral oracles and reporting by
task stratum. Each family must meet the local-edit and repair thresholds above on
the supported CPU corpus; synthetic index or regex success does not count as
semantic verification.

Include resource/region escape, aliasing, error/cleanup, scoped concurrency,
protocol and target context, malformed source, stale transactions and long-running
resource tests. Measure defect escape and false rejection alongside tokens, repair
turns and completion. Report failures/timeouts and all retry costs, unsafe/check-
suppression additions, confidence intervals and paired baseline effects. The full
H12 sample sizes, decision rules and compiler/runtime budgets are mandatory for
E2 claim closure; they do not replace the later cross-platform workload gate and do
not block M3.

The accepted library review in [`stdlib-hardening.md`](stdlib-hardening.md) adds
SL01–SL11 fixtures to H11/H12: catalogue signatures must obey the real resolver's
shadowing/import rules, buffered I/O must compose through public adapters, generic
JSON must preserve large integer values, and process/filesystem/control operations
must expose partial effects and bounded cleanup. Exercise the migrated CPU paths
before closing the applicable T2/E2 work; do not require unfinished TLS/image
implementations in the E2 runtime report. Activate streaming HTTP/SSE, HMAC/HKDF,
fake-I/O and image/codec corpora when
their extended modules are delivered. Image value types/codecs stabilize together
without claiming that experimental GPU/UI modules passed GP-15.

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
