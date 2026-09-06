# Neper — post-M2 language and compiler hardening for LLMs

Status: scheduled design and implementation plan, recorded 2026-09-05. This is the
mandatory **M2.5** gate: work starts after M2 is complete and all M2.5 obligations
below must close before M3 implementation begins. Explicit later deliveries are
tracked separately. No item is implemented by this document.
The current language, grammar, APIs and tooling protocol remain authoritative until
their explicitly versioned replacements land during M2.5.

The prioritized, concrete recommendation set distilled from this review lives in
[`llm-hardening-recommendations.md`](llm-hardening-recommendations.md). It maps each
recommendation onto the H items below and adds four new items — R08–R11, registered
here as H26–H29 — that close the gap between "readable by a human reviewer" and
"operated on by a model end-to-end". H26–H29 are supplementary obligations under the
same closure policy as H01–H25; they do not supersede any earlier item.

A separate **proposal**, not adopted and not scheduled, sits in
[`llm-mcp-server.md`](llm-mcp-server.md): a native MCP server over the compiler's
JSONL streams, plus `neper patch`, `neper header` and an edit-loop benchmark suite.
Its server is the part with no counterpart here and would need an owning milestone.
Its other three parts touch adopted items and have to be settled against them before
any of it is scheduled — `neper patch` as written conflicts with H29, which requires
typed operations with preconditions rather than raw byte replacement; `neper header`
overlaps R05's retrievable API catalogue; and its benchmark thresholds are numbers no
adopted item stands behind, which R03's measurement basis and R07's evidence gate
would have to supply. Nothing in it is normative.

## 1. Motivation, evidence and limits

Jose Crespo's [Why AI Sucks at These Programming Languages](https://aiadvances.org/why-ai-sucks-at-these-programming-languages-f35c14ac4a8e)
(AI Advances, 2026-08-22) prompted this review. The public introduction and the
author's [syndicated preview](https://www.josecrespophd.org/p/the-programming-languages-that-break)
argue that plausible syntax can conceal dependencies on lookup, lifetimes,
ownership and concurrency. The full articles require a subscription; this plan
does not claim to have reviewed their paywalled examples. The available argument
is a useful engineering hypothesis, not evidence that a particular model cannot
reason about these languages or that Neper outperforms them.

Neper already reduces incidental context with qualified names, no overloading or
textual macros, explicit numeric casts, statement-level `try`, a fixed formatter
and public syntax/index data. Those choices should survive unless measurements
show a better alternative. However, readable syntax does not enforce ownership,
prevent races or make a compiler correct. Short source and first-pass compilation
are insufficient measures of LLM success.

The governing design objective for M2.5 is:

> Every correctness-relevant dependency must be visible in a checked contract,
> enforced by the compiler, or reported as an explicit unproved obligation with
> its origin. Tools must distinguish these cases.

An unproved obligation is not a safety guarantee. Operations outside the promised
checked subset must require an explicit unsafe boundary. Business correctness,
deadlock freedom, all possible schedules, foreign implementations and arbitrary
raw-pointer lifetimes are not proved merely by exposing their contracts.

Primary design references:

- [Rust destructor rules](https://doc.rust-lang.org/reference/destructors.html)
  illustrate the complexity of partial initialization and cleanup ordering. Neper
  should specify these interactions before adding resource syntax.
- [Rust scoped threads](https://doc.rust-lang.org/std/thread/fn.scope.html)
  illustrate joining before borrowed data expires; scope alone is not a race proof.
- [Clang thread-safety analysis](https://clang.llvm.org/docs/ThreadSafetyAnalysis.html)
  illustrates explicit lock capabilities and their analysis limits.
- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html) illustrates
  runtime instrumentation. Its existence does not give Neper's direct emitter that
  instrumentation, nor does memory poisoning alone prove lifetime validity.
- [Rust's undefined-behavior inventory](https://doc.rust-lang.org/reference/behavior-considered-undefined.html)
  reinforces the need to enumerate unsafe obligations precisely.

These references inform tradeoffs; they establish no comparative LLM performance.

The follow-up performance/tooling review adds H14–H25. It distinguishes three
objectives: low compiler feedback latency, efficient generated programs, and low
total harness cost per verified change. None implies the other. These additions
are scheduled requirements, not claims about current implementation performance.

Additional primary design references:

- [Rust's incremental query model](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation-in-detail.html)
  illustrates stopping dependency invalidation when a recomputed result is unchanged.
- [Vulkan's SPIR-V environment](https://docs.vulkan.org/spec/latest/appendices/spirvenv.html)
  defines floating-point execution-mode requirements; default denormal behavior is
  not equivalent to support for explicitly preserving denormals.
- [Vulkan timeline semaphores](https://docs.vulkan.org/samples/latest/samples/extensions/timeline_semaphore/README.html)
  illustrate device-side ordering across queues without a whole-queue host wait.

## 2. Scheduling and decision policy

The order is M2 completion, a recorded M2 baseline, M2.5 design freeze,
implementation/migration/verification, then M3. M2 is assessed against its existing
contract. M2.5 does not retroactively move its completion criteria or add work to
the throwaway C bootstrap. Passing M2.5 revalidates self-hosting and determinism
under the revised language.

Each H item below requires a closure record containing the selected design,
alternatives, exact normative changes, implementation and test references,
compatibility effects, measurements and remaining limitations. All start as
**scheduled, unresolved**. No syntax examples in an earlier conversation reserve
keywords or define an API. In particular `resource type`, `move`, `scope`,
`mem.child`, `finish` and `neper context` need concrete designs before implementation.

The recommendations below are the default direction. A replacement can close an
item only if it satisfies that item's acceptance obligations and records why it is
better. Deferring an unresolved requirement past M3, relabeling a prototype as
complete, or substituting a documentation warning for required enforcement does
not close it. Relaxing a requirement needs an explicit user-approved scope change.

For H14–H25, each section explicitly separates **M2.5 delivery** from **later
delivery**. All M2.5 obligations must close before M3. Freezing a future GPU contract
does not require implementing a GPU backend during M2.5. Optional optimization,
execution-graph and fast CPU-kernel projects are not silently added to this gate.
Design-only closure must identify the exact future obligations and fixtures, with
runtime evidence marked pending rather than passed.

## 3. Inventory and recommended disposition

| ID | Current exposure | Required M2.5 outcome | Main cost |
|---|---|---|---|
| H01 | Arenas and OS handles are logically single-owner but bitwise copyable | Checked ownership, consumption and cleanup contracts | Control-flow analysis and API migration |
| H02 | Slices/pointers can outlive a reset or container mutation | Enforced region/view validity in a defined checked subset | Lifetime summaries and container redesign |
| H03 | Release removes memory checks; poisoning is treated too strongly | Checked optimized default and explicit unsafe obligations | Runtime checks and direct-emitter support |
| H04 | Thread scope and shared aliases carry informal obligations | Scoped task lifetime and checked sharing/lock contracts | Capture analysis and library changes |
| H05 | Large by-value arguments secretly impose no-write restrictions | Real value semantics or explicit checked borrowing | Copies or alias analysis |
| H06 | Protocol selection depends on a type's declaring module | Explainable dispatch and explicit strategy support | Generic interface/cache changes |
| H07 | Error detail depends on the last failing OS call | Explicit error detail and failure-state contracts | OS/wrapper ABI and cleanup changes |
| H08 | Context retrieval requires many files and uncertain coverage | Bounded compiler-derived context with provenance | Query/index infrastructure |
| H09 | Repairs can use stale spans or hide incomplete analysis | Transactional edits and causal diagnostics | Tool protocol and editor support |
| H10 | Cold starts, stale caches and compiler bugs tax every repair | Fast, cancellable, independently verified feedback | Instrumentation, cache tests and fuzzing |
| H11 | Large API catalogue and novel language invite invented code | Versioned, executable, retrievable language/API guidance | Documentation generation and conformance |
| H12 | Existing editing benchmarks do not establish program safety | Held-out semantic and repair evaluation on real tools | Repeated model runs and independent oracles |
| H13 | GPU will multiply ownership and execution contexts | Frozen GPU integration contracts before backend work | Design fixtures now; device verification in M3 |
| H14 | Function-level parallelism does not guarantee function-level reuse | Declaration/query-level incremental reuse and observable invalidation | Semantic dependency graph and reusable emission |
| H15 | Queries, edits and builds can observe different workspace versions | Immutable snapshots, complete cache identities and atomic publication | Overlay, transaction and cache coordination |
| H16 | Process-exit arena reclamation does not support repeated tooling requests | Bounded request/snapshot/cache lifetimes and cancellation | Memory ownership and resource accounting |
| H17 | Text search cannot establish semantic edit or deletion safety | Compiler-backed search and conservative rename/move/delete impact | Reference/effect graph and edit planning |
| H18 | Full-fidelity output can overwhelm a harness | Versioned compact, bounded and cancellable transport | Protocol/schema migration |
| H19 | Generated origin locations need not be editable locations | Explicit provenance and regeneration-aware edits | Source-map and generator contracts |
| H20 | Fast emission alone does not establish fast execution | Measured build-policy tradeoffs and optimization explanations | CPU measurements and bounded optimization design |
| H21 | Whole-queue waits and informal lifetime rules limit CPU/GPU composition | Frozen completion/dependency/resource-state contracts | Design now; device implementation in M3 |
| H22 | Kernel time hides staging, submission and device compilation | Frozen end-to-end GPU cost and cache contracts | Design now; device measurement in M3 |
| H23 | Numerical equivalence claims exceed stated backend conditions | Corrected executable numerical/capability matrix | Contract corrections now; device tests in M3 |
| H24 | Malformed artifacts and aggregate work can bypass local limits | Bounded readers, verified cache publication and adversarial tests | Decoder hardening and fault injection |
| H25 | “Ultra fast” lacks a reproducible multidimensional gate | Registered performance workloads, budgets and comparable reports | Measurement and regression infrastructure |
| H26 | Token cost is deferred rather than steered | Measured per-tokenizer token/repair budgets that gate syntax changes | Model/tokenizer harness and corpus freeze |
| H27 | Unsafe/escape-hatch sites are not enumerable | One-command enumeration of every unsafe boundary with provenance | Index/context extension and provenance tags |
| H28 | LLM cards are hand-written prose that can drift | Compiler-generated, grammar-versioned cards with content hash | Card generator and schema |
| H29 | Semantic refactors are expressed as raw text spans | Structured AST-level edit operations with pre/postconditions in the v2 stream | Tool protocol v2 and edit planning |

## 4. H01 — ownership, resource states and cleanup

Adopt a small compiler-enforced resource model for `Arena`, builders and owned OS
handles. An affine value permits at most one use of ownership; requiring eventual
cleanup is a separate obligation. The earlier proposal conflated those properties.
Specify both rather than promising that non-copyability prevents leaks.

Required rules:

- Distinguish owned resources, temporary borrows and explicitly duplicated
  resources. An OS duplication operation creates a new ownership identity; copying
  handle bits does not. Immutability of a binding does not imply unique ownership.
- Ownership transfer must be visible in signatures and source. Define argument
  evaluation order, moves into aggregates, return values, reassignment and joins
  after branches/loops. Moving an object cannot invalidate outstanding borrows.
- Resource containment propagates non-copyability through structs, arrays,
  tagged unions, generics and slices of owned resources. Disallow partial moves in
  the initial design unless field-sensitive state tracking is fully specified.
- Define valid states for `zero`, `undef`, failed construction and partially built
  containers. Generic copy, serialization, reflection, `mem.bitcast` and pointer
  casts must not manufacture ownership or duplicate a resource in checked code.
- Every normal scope exit, `ret`, `try`, `break` and `continue` must discharge live
  cleanup obligations or transfer them. Keep cleanup visible through `defer` or an
  explicit scope construct; do not add arbitrary hidden user destructors.
- Resolve when deferred arguments are captured and whether scheduling a close
  reserves consumption. Reject a later move/close that would make the deferred
  operation invalid. Define reverse cleanup order and partial-acquisition behavior.
- Classify consuming operations on both success and failure. A failed close/join
  cannot leave ownership unspecified, invite a blind retry of a reused OS handle,
  or lose the primary error when cleanup also fails.
- Traps, process exit and forced termination retain a separate contract: no promise
  that every resource is cleaned up after an abort. Never use cleanup as the sole
  mechanism preventing another thread from accessing freed storage.

Resource representations need protection: currently every module declaration is
exported and handles expose ordinary data. Evaluate narrowly opaque resource
representations/access restrictions before introducing a general visibility system.
Raw imports/exports of handles belong to audited unsafe wrappers. Resource identity
must survive safe API boundaries without requiring a global release-mode registry.

Acceptance: reject duplicate ownership, deferred double-close, use-after-move,
resource-copy through a generic/aggregate and forgotten required cleanup; accept
transfer, explicit OS duplication and correct cleanup on all control-flow exits.
Exercise allocation failure at each acquisition step and erroring cleanup. Each
diagnostic identifies acquisition, conflicting use and exit/consumption sites.

## 5. H02 — regions, borrowing and stable container views

Prefer lexically delimited scratch regions and build-then-freeze containers, but
do not describe escape prevention as a trivial block rule. A pointer can escape
inside a struct, through a callback, into a global, via an imported function or
through a different alias of the arena. Preventing those escapes requires analysis.

Define a bounded checked subset with these properties:

- Track the storage owner of borrowed pointers/slices recursively through
  aggregates. Public signatures describe no-escape inputs and which input/region
  a result borrows from. Body inference checks the contract; cross-module calls
  use serialized summaries rather than reading arbitrary bodies.
- A region may end only when its live borrows are dead. Parent reset/allocation
  interactions, nested regions, arena transfer and reborrowing have one specified
  rule. A borrowed region view is not an independently movable arena owner.
- Return, global stores, heap-like arena stores, callbacks, indirect calls and
  thread handoff cannot erase the origin. Unknown foreign/raw-pointer behavior
  requires an unsafe boundary, not an inferred no-escape claim.
- Start conservatively with lexical lifetimes. Measure whether false rejections
  justify non-lexical liveness; do not quietly infer arbitrary whole-program
  ownership. Persistent graphs must have a documented handle/pool construction or
  an explicit unsafe implementation with a checked public interface.
- Replace publicly escaping mutable-container backing slices with a scoped borrow
  or consuming freeze operation. During a scoped view, reject invalidating growth,
  mutation and reset through all tracked aliases. Returning raw pointers from
  `get` would recreate the problem; copy accessors and borrowing accessors differ.
- A frozen slice still borrows its backing arena. Freezing a builder prevents its
  growth, not the arena's destruction or reset. State the remaining lifetime.
- Repeated append-only temporary buffers should reuse scratch regions rather than
  exhaust the root arena. Correctness includes bounded steady-state memory.

Generation-tagged checked handles are a possible alternative for selected dynamic
containers. They require an owner identity, generation-wrap policy, runtime costs
and checks on every protected access. Filling released bytes with `0xDD` detects
neither every use-after-reset nor a stale yet addressable pre-growth slice.

Acceptance: nested-region escapes, aliases across reset, returned borrowed fields,
retained callbacks, live views across growth, freeze followed by reset and repeated
request/frame loops. Include valid nonescaping counterparts to measure false
positives. Reject or trap each protected violation before invalid memory is used;
record raw-pointer cases explicitly outside the guarantee.

## 6. H03 — checked optimized execution and unsafe boundaries

Separate optimization from check removal. Recommend that ordinary optimized builds
retain bounds, null, tag, alignment and defined invalid-state checks wherever the
representation supports them. Eliminate redundant checks only with a valid proof.
Enumerate the complete revised check table; avoid the misleading label "safe
release" until the claimed checked subset has a defensible safety argument.

- A null check cannot establish pointer liveness; a bounds check cannot establish
  that a slice's base/length were validly constructed. H01/H02 and trusted boundary
  validation are prerequisites for stronger claims.
- Specify explicit unsafe operations and caller obligations for raw dereference,
  casts, external calls, uninitialized reads, packed/unaligned access and unchecked
  indexing. Unsafe is neither a guarantee of correctness nor blanket permission
  for unrelated operations in a callee.
- Preserve mandatory checks even in unsafe code where the contract requires them.
  Replace/reconcile `@nocheck` deliberately; do not create overlapping switches
  with unclear precedence. Report every suppressed check and its source origin.
- Keep existing defined arithmetic choices unless independently changed and
  versioned. Check retention alone does not reconcile debug overflow traps with
  release wrapping. Record build mode as context until each divergence is resolved.
- Invalid reference/resource representations and invalid `zero`/`undef` values
  must not enter checked code unnoticed. Definite-initialization checks need
  field/element handling or conservative rejection; byte patterns are not proof.
- Inventory unchecked dependencies in the build manifest and context output.
  A checked caller does not sanitize an unchecked callee. Version/cache identity
  includes safety policy, ABI and summary format.

Acceptance: optimized and debug runs for every check-table row, with expected
differences named; equivalent safe-program results; failed checks before memory
side effects; codegen tests for eliminated and retained checks. Audit emitted loads,
stores and optimizer assumptions, including foreign callbacks and packed records.

## 7. H04 — scoped concurrency and shared-state contracts

Prefer scoped workers with a compiler-visible join obligation. A detached worker
must own its inputs or use explicitly valid long-lived shared storage. Borrowing a
stack frame for a detached task is rejected, including through an indirect callback.

Joining alone does not prevent races. A read-only pointer may alias another thread's
writer. Define thread transfer and sharing recursively, including pointer-bearing
containers, arena cursors, globals and callback environments. Checked code shares
either transitively immutable storage, atomics, or storage accessed through a
recognized lock capability. Raw shared access remains an unsafe obligation.

Lock guards must refer to the protected data/lock identity and cannot expose a
borrow that survives release. Specify reentrancy, moving guards, condition-variable
wait/reacquire and cancellation. Static lock checking does not prove deadlock
freedom or correct atomic ordering; expose those limitations and test protocols.

Joining on error paths must precede reset/cleanup of worker-visible state. A timeout
cannot safely release a worker's memory while it still runs. Define join errors,
partial spawn failure, cancellation acknowledgement and unresponsive workers.
Keep scheduling a library concern; no green-thread runtime is implied.

Acceptance: stack escape, shared mutable alias, wrong-lock access, guard escape,
worker arena sharing, early `try` with live workers and partial spawn failure.
Test valid disjoint partitions and synchronized mutation as well as negative cases.
Schedule perturbation is evidence over tested runs, not an exhaustive race proof.

## 8. H05 — by-value ABI and alias semantics

Spec §5 currently permits large aggregates to be passed by hidden reference only
under a caller no-write obligation, even through another pointer. This makes an
apparently ordinary value argument carry a nonlocal temporal restriction.

Recommend ordinary snapshot semantics for copyable by-value arguments: the callee
observes the value at the specified argument-evaluation point. Passing indirectly
is an ABI choice; the compiler must materialize a copy unless it proves equivalence.
Copies are shallow: slice/pointer fields retain their explicit borrowing contracts.
Non-copyable resources use H01 transfer/borrow rules. Explicit borrowing can avoid
copies, but its alias restrictions must be checked rather than assumed as UB.

Acceptance: `f(x, &x)` where `f` mutates the original, nested pointer fields, large
aggregate returns, multiple returns, generic instances, external ABI wrappers and
inlining on/off. Measure copy-elision and runtime costs. Update D14 and the ABI
contract only with migration tests and a new compatibility identity.

## 9. H06 — protocols, generics and compile-time context

Do not automatically replace every protocol call with function arguments. Current
lookup is already closed and deterministic; compulsory explicit operations may
increase repair burden and specialization count. The earlier `map.init` sketch
also omitted how callback identity persists in the map type and how signatures,
hash/equality coherence and cross-module use are checked.

Required outcome: every implicit dispatch and generic substitution is queryable
from the real compiler, including fallback selection, failed candidates, dependent
requirements and the source that triggered instantiation. Add explicit strategy
selection for callers that need custom behavior, preferably using the existing
comptime function mechanism. Freeze exact APIs only after comparing explicit
selection with current protocols on equivalent tasks.

Specify operation identity in type/instance identity where behavior depends on it.
Reject mixing incompatible strategies. Include additions/removals of fallback-
overriding declarations in cache invalidation. Export checked generic requirements
with diagnostics showing requested and actual signatures. Semantic laws such as
equal keys having equal hashes still need contracts and property tests.

Bound comptime evaluation, recursion, specialization count and diagnostic expansion
with explicit budgets and structured exhaustion results. Expose target-dependent
layout and the runtime/comptime phase. Exhaustion never means successful checking.
Keep `try` and other syntax spellings until total-token and repair evidence supports
a change; lexical token count is not model token count.

Acceptance: aliases, nominal/structural types, competing strategies, absent or
wrong-signature protocols, fallback changes, dependent types, recursive instances,
budget exhaustion and target-dependent constants. Measure code size and check time.

## 10. H07 — error detail and partial failure

Replace the temporal requirement to call `os.last_error_detail` before another
failed operation with explicitly returned or caller-supplied detail in the checked
API path. Preserve the compact `err` propagation model where it suffices; design
rich detail as ordinary typed data, not ambient exception state.

For each fallible API specify valid outputs on failure, partial progress, ownership
retained/consumed, detail lifetime and whether retry is valid. Prevent using a result
that is only initialized on success without checking that success. Decide how this
is represented in the existing multiple-return model before adopting new syntax.
Cleanup failure must not overwrite the original operation's detail. Deferred
discard of an `err` remains an explicit source choice and appears in context output.

Acceptance: primary I/O failure followed by failed cleanup, nested wrappers,
concurrent errors, borrowed diagnostic labels, partial writes and allocation failure.
Tests assert resource state and error provenance, not only the error number.

## 11. H08 — bounded semantic context for harnesses

Deliver a compiler query, provisionally `neper context`, rather than requiring a
harness to infer semantics from prose. Reuse the resolver, checker and dependency
graph; do not build a second approximate language implementation.

The versioned query contract must support symbol/span selection and return:

- Exact signatures, resolved types/imports/call targets, generic arguments,
  compiler-generated calls and applicable API contracts.
- Ownership transfer, borrow origins, invalidations, cleanup/exit paths, possible
  effects/errors, unsafe boundaries, shared-state and lock obligations.
- Selected language/profile/target/check policy, source/build hashes, dependency
  summary hashes, and identities for the snapshot and requested subject.
- For each fact: compiler-proved, declared-and-checked, trusted external contract,
  runtime-observed or unknown, with provenance. Comments and model-written claims
  are documentation, never promoted to proved facts.

Use caller-selected projections and deterministic byte/record budgets. Return
omission counts, completeness flags and snapshot-bound continuation cursors; never
silently truncate a contract or pretend an incomplete graph is complete. A compact
summary links to exact source instead of dumping whole bodies and the whole API catalogue.
The compiler budgets bytes/records; the harness measures tokenizer-specific tokens.

Represent indirect calls conservatively. Unknown targets/effects are unknown, not
pure or empty. Recursive effect summaries need a convergent rule, public boundary
contracts and budget handling. Avoid creating a second general effect language
unless the requirements justify it.

Existing index numeric IDs are stable only within identical source. Cross-query
edits require snapshot identity plus source hashes; numeric IDs are not persistent
global symbol identities. Source changes invalidate cursors and edits. Target,
generic, protocol, contract and safety changes invalidate cached summaries even
when the function body is unchanged.

Acceptance: deterministic pagination, partial/broken sources, missing imports,
unresolved calls, two generic instances, stale snapshots, removed symbols and
target/check-policy changes. No compiler-proved label may be assigned to an
unverified external assertion. Include misleading instructions in source comments
as inert data in harness tests.

## 12. H09 — diagnosis, recovery and transactional repair

- Emit causal diagnostics with stable codes, an error origin, related locations,
  expected/actual types or resource states, and a bounded instantiation/call chain.
  Group cascades under the primary cause without hiding independent failures.
- Keep lexer/parser recovery deterministic and lossless. Consume input or stop at
  each recovery step, preserve invalid bytes and expose error nodes. Never silently
  insert/delete/transpose characters and compile the repaired interpretation.
- Distinguish syntactically recovered, semantically incomplete, rejected and fully
  checked output. Unsupported analysis and budget exhaustion fail closed. Valid
  declarations elsewhere may still be indexed with explicit completeness metadata.
- Structured fixes identify the source snapshot, expected bytes/hash, exact
  nonoverlapping edits and postconditions. Multi-file refactors validate every
  precondition before writing; failure leaves all sources untouched. Define a
  recoverable transaction/journal and coordination with concurrent editor changes.
- Preview semantic impact: callers, borrowed results, affected generics, protocols,
  tests and public APIs. Format only within a well-defined transaction; preserve
  comments and unrelated source. Recheck after applying, since a suggested fix is
  not a proof of program correctness.
- Never mark a fix automatically safe merely because it compiles. Narrowing casts,
  added error discards, changed ownership, disabling checks and introducing unsafe
  code need explicit semantic justification and must not be hidden repair defaults.

Acceptance: truncated code, malformed UTF-8, missing delimiters, several independent
errors, stale source during a rename, cross-file partial failure and diagnostic
floods. Test the real command schema and ordering, not regexes over human messages.

## 13. H10 — compiler responsiveness and correctness

Optimize successful end-to-end repair time while retaining correctness. Measure
cold and warm checks, query latency, time to first useful diagnostic, peak memory,
incremental invalidation size and cancellation response. A lines-per-second target
does not describe the latency of editing one function in a large project.

- Separate parsing, interface checking, body checking and emission so a check/query
  does not unnecessarily link or generate code. Reuse immutable snapshots and
  phase results with complete dependency keys. Batch queries before adding a
  persistent server; introduce a versioned cancellable session only if measured
  startup/reparse costs justify its additional state and invalidation complexity.
- Cancellation cannot publish a successful partial result or corrupt reusable
  caches. Resource exhaustion has deterministic error behavior. Bound source,
  nesting, nodes, instantiations, comptime work, output and worker allocations.
- Add verifiers at typed IR and lowering boundaries for dominance, types, resource
  states, ABI shapes and generated cleanup. Checks must survive optimization or
  be removed only under documented valid assumptions.
- Use grammar/mutation fuzzing for arbitrary bytes and valid/invalid syntax;
  differential execution against a reference interpreter or independent oracle
  for the checked subset; metamorphic tests for formatting, alpha-renaming and
  clean/incremental equivalence. No common backend means independence by default.
- Compare stage-2/stage-3 self-host outputs and tested program behavior. A compiler
  compiling itself proves bootstrap consistency, not absence of miscompilation.
- Offer dependency-based test impact queries with explicit completeness. Unknown
  indirect effects, global state, ABI or contract changes widen the selected suite;
  a minimal test set must never be advertised as complete without the dependency
  evidence. Retain periodic full-suite runs to detect selection bugs.
- Revalidate Windows/Linux ABIs, debug/source mapping and deterministic artifacts
  across worker counts. Direct-emitter instrumentation must be implemented and
  verified before advertising sanitizer-like coverage.

Acceptance: deliberate stale-cache bugs are detected by the harness; bounded
malformed input never hangs/crashes; cancellation leaves an intact old snapshot;
IR-verifier failures never yield runnable artifacts. Record baseline and changed
latency/memory distributions using the same host, workload and compiler options.

## 14. H11 — learnability and executable API documentation

The adopted [standard-library review](stdlib-hardening.md) (D84, SL01–SL11) is part
of this closure: fix catalogue shadowing/import collisions without new syntax,
validate extracted declarations with the real resolver, migrate delivered CPU I/O,
JSON, filesystem/process and iteration surfaces, and deliver `e.cancel` and basic
`text.utf8` through this cross-cutting gate. H01/H02/H07 control ownership and native
error-detail migration; H17 controls naming/refactor impact and H18 the installed
capability inventory. Later crypto/network/image/test-support libraries require
frozen contracts and named future fixtures, not premature implementation claims.

Generate compact language cards and per-symbol API records from the selected
language/profile and checked library sources. Distinguish planned, present,
supported-on-target and verified APIs. The current card's examples and tool names
are guidance, not evidence that an executable implements every promised command.

Each API record should expose ownership, borrowing, invalidation, mutation,
allocation, error/partial-success behavior, thread restrictions, phase/target,
examples and executable tests. Provide positive and near-miss negative examples
for novel rules. Publicly shipped examples must compile and run, or be explicitly
labeled rejection tests/proposals with their expected diagnostic.

Avoid requiring every model invocation to read the full specification. Serve a
small versioned entry card plus task-relevant contracts with hashes and provenance.
Measure whether added metadata reduces total repair cost. Keep source/JSON schemas
canonical and allow compact query projections instead of inventing a second terse
programming notation. Lexical tokens and different model tokenizers remain distinct.

Audit API defaults and naming for accidental semantic differences: copying versus
borrowing, mutable versus frozen, consume versus close-on-success, element versus
byte count, and CPU versus device. Correct undocumented exceptions and generate
examples for them. Do not rename stable syntax or APIs on character-count grounds.

Acceptance: cards for old and revised language versions cannot be confused; no
planned-only API is suggested as implemented; examples compile with the advertised
toolchain; retrieval finds exact ownership/failure contracts without unrelated APIs.

## 15. H12 — evaluation and M2.5 acceptance evidence

Extend [the verification plan](general-purpose-verification.md#4-llm-generation-evaluation)
and [the editing benchmark](../benchmarks/llm_edit/README.md). Existing synthetic
search/edit corpora measure navigation and edit precision. Regex/oracle success
and a synthetic index do not establish compilation, lifetime safety or behavioral
correctness. Million-line filler does not replace a real dependency graph.

Required task strata:

| Stratum | Cases and oracle |
|---|---|
| Local generation/editing | Parse, check, formatter and independent behavioral tests |
| Nonlocal change | Cross-module signature, resource ownership and borrow-result migration; resolved references and tests |
| Temporal defects | Reset/growth, consume/close, alias mutation and error-path cleanup; negative/positive pairs |
| Concurrency | Scoped/detached lifetime, lock contracts, shared aliases and shutdown; static outcomes plus schedules |
| Semantic context | Protocol fallback, generic phase, build policy, unsafe boundary and indirect-call unknowns |
| Broken/adversarial input | Truncation, stale patches, incomplete index, huge diagnostics, deceptive comments and malformed tool data |
| Long-running behavior | Repeated requests/builds, bounded memory and handles, cancellation and partial failure |
| Compiler correctness | Differential execution, IR verification and clean/incremental/parallel artifact equality |

Before altering the compiler, archive the M2 executable, source revision, schema,
cards, prompts, fixtures, environment and baseline results. Pre-register the held-out
task set and decision criteria before inspecting candidate results. Use at least
two independently trained model families with fixed model versions/settings and
three runs per task. Model names/versions and tokenizer identities belong in reports,
not permanent language rules. Do not pool families to hide one failing family.

For statistical thresholds use at least 200 distinct local-edit tasks and 200
compiler-error repair tasks per family, distributed across applicable strata;
seeds and repetitions of one template are not independent tasks. Report task-level
confidence intervals and raw counts. These sample sizes are a minimum evidence
floor, not proof of universal performance or absence of rare failures.

Run three controlled arms: M2 baseline, revised compiler with equivalent minimal
guidance, and revised compiler with context/repair tools. Where feasible isolate
individual H changes. Compare equivalent C, C++, Rust, Go, Python, Java and C#
tasks only where the language supports the workload; report exclusions. Give each
language its real compiler, native semantic tools and equivalent access budgets.
Do not invent a Neper feature such as re-exports to make a comparison symmetrical.

Required pre-M3 gate:

1. On supported CPU tasks, each model family meets the existing thresholds: 95%
   first-pass local-edit parsing, 90% first-pass type checking, median unrelated
   formatted diff zero, and 95% repair within one additional turn. No accepted task
   needs human-output scraping or undocumented compiler behavior.
2. Every fixed CPU/tooling conformance fixture for H01–H11 and H14–H29 passes;
   design-only GPU cases satisfy their explicit pre-M3 design obligations instead
   of being reported as runtime passes. All planted violations inside
   a promised checked guarantee are rejected or trapped as specified; valid paired
   fixtures pass. No known miscompilation or missed guaranteed violation remains.
   Unknown/unsafe cases are reported separately and never counted as proved safe.
3. Every model-produced patch counted as accepted passes independent behavioral
   tests and the applicable safety/resource checks. Report overall completion rate,
   first-pass test rate, false rejection, defect escape and unsafe/error-suppression
   introduction by stratum. Aborted tasks, retries, timeouts and failures retain
   their token/time costs in the totals.
4. Demonstrate a reduction in total tokens per verified success or repair turns on
   the held-out context-sensitive CPU tasks in both families, without an unexplained
   loss of verified completion. Publish paired effects and uncertainty; if evidence
   is inconclusive, expand the held-out evaluation rather than assert superiority.
5. Report p50/p95 cold/warm compiler and query latency, peak memory, code size and
   runtime, including an ablation for retained checks. Freeze workload-specific
   performance budgets from the M2 baseline before tuning. Any exceeded budget
   requires a documented tradeoff decision; safety obligations cannot be waived
   to meet the speed budget.

Use GP-01 plus the applicable M2 CPU workloads and minimal direct-FFI fixtures.
Do not require unfinished M3 GPU, M4 dynamic-linker, M6 package or later networking
implementations to close this gate. The broader general-purpose gate still waits
for its own prerequisites and reruns these tests as new capabilities arrive.

## 16. H13 — GPU contracts frozen before M3

Design the mapping of H01–H09 onto devices now; implement and execute device tests
in M3. A pre-M3 design fixture is not recorded as a passing GPU runtime test.

- Define ownership/liveness of devices, queues, buffers and outstanding submissions;
  a host lexical scope cannot release storage that a device still uses. Specify
  deferred/in-order release, synchronization and cancellation/failure transitions.
- Distinguish host, device, workgroup and subgroup memory in types/contracts and
  context records. Decide which resource/region forms are legal in each profile.
- Freeze barrier-uniformity, atomic scope/order and device-error reporting contracts.
  CPU emulation and poisoned shared bytes cannot prove absence of every device race.
- Resolve how checked optimized CPU policy maps to device bounds/tag/alignment
  checks and traps. Device traps need a concrete reporting/termination mechanism;
  silently removing unsupported checks is forbidden. Reserve runtime proof for M3.
- Extend `.em` identities with profile, capability, safety and contract dependencies.
  Specify diagnostic/source provenance for helper specialization and inlined calls.

Acceptance before M3: each applicable H requirement has a reviewed CPU/device
mapping, grammar/type/ABI/error contract and named M3 positive/negative fixture.
No unresolved GPU design question may invalidate the new CPU ownership or tooling
contract. Device correctness remains an explicit M3 delivery requirement.

## 17. H14 — declaration-level incremental semantic work

**M2.5 delivery: implemented CPU compiler/query reuse.** Extend H10; do not count
parallel module compilation as incremental function reuse. Spec §12 currently
recompiles a module when its source hash changes. The module may remain the artifact
and linking unit while unchanged internal work is reused.

- Define query identities/results for declaration parsing, lookup, type checking,
  resource/lifetime analysis, generic instantiation, lowering and function emission.
  They share the real semantic engine used by build/check; no approximate checker.
- Record actual dependencies, including absent lookups, generic strategies, safety
  summaries, compile-time inputs and target-dependent layout. Recompute affected
  queries; if their relevant result is unchanged, stop downstream invalidation.
- Separate source/trivia, semantic, debug-location and tooling-provenance identities.
  A comment edit may require source/debug remapping without repeating unaffected
  checking or instruction selection. Do not reuse stale locations to save work.
- Reuse unchanged function emission and relocation descriptions when their full
  dependencies match. Layout/link/debug work may still be necessary; account for
  it separately rather than promising every edit avoids relinking.
- Bound recursive summary convergence and specialization. Public checked summaries
  should permit local analysis without repeatedly inspecting arbitrary callee bodies.
  Exhaustion is an explicit incomplete/failure result, not an optimistic summary.
- Expose structured dirty reasons, dependency paths, cache hits/misses, declarations
  rechecked, instances expanded, functions emitted and bytes/artifacts regenerated.

Acceptance fixtures: comment-only edit; local non-inlined body edit; unrelated
declaration insertion; signature/layout change; fallback protocol insertion/removal;
generic/comptime dependency change; deleted declaration; broken edit then repair;
edit then revert. Specify the expected reused/invalidated units for each fixture.
Assert clean/incremental semantic and deterministic artifact equivalence where the
same build contract promises byte equality. Compare relocated debug mappings too.
Performance closure uses H25, not an assertion that caching is always faster.

## 18. H15 — immutable snapshots and correct cache identity

**M2.5 delivery: implemented snapshot, overlay and publication contracts.** Extend
H08/H09 across the entire build/query/edit workflow, not only individual fix spans.

- A snapshot identifies exact source bytes, resolution graph, generated inputs,
  compiler/toolchain identity, language/grammar/IR/ABI/summary versions, target/CPU
  features, check/optimization policy and other declared build inputs. Files read
  lazily must be pinned or verified; concurrent filesystem changes cannot create
  a mixed-version snapshot. Never rely on modification time alone.
- Derive stage-specific keys from the relevant subset of inputs. Diagnostic/index
  keys include location/provenance data even when code-generation keys need not.
  Define canonical serialization; process-local intern IDs are not persistent keys.
- Support multi-file in-memory overlays with additions, replacements, moves and
  deletions. Check an overlay before publishing it. Every result identifies its
  snapshot; a stale ID/cursor/edit is rejected or explicitly rebased and revalidated.
- Give concurrent builds isolated temporary outputs and publish complete artifacts
  atomically. Separate targets, CPU features and policies even where today's cache
  filename would collide. Cancellation must preserve the previous valid artifact.
- Define the supported transaction coordination boundary. A source transaction must
  lock or otherwise coordinate participating editors and validate all preconditions;
  arbitrary noncooperating writers cannot be made atomic by a last-second hash
  check. Detect conflicts, preserve recoverable originals, and never silently
  overwrite an intervening edit. Document crash recovery and visibility guarantees.
- Treat xxHash64 as a fast candidate fingerprint, not an unexplained equality
  proof. For local semantic reuse require canonical-input/result equality or a
  specified collision-verification strategy. Shared/untrusted artifacts additionally
  need strong content integrity and explicit trust/provenance rules under H24.

Acceptance: concurrent edits during lazy reads; two policy/CPU-feature builds;
stale multi-file patches; interrupted publication; identical inputs at different
worker counts; injected hash collisions; toolchain/schema change; package-resolution
and generator-input changes. No result may silently mix snapshots or overwrite a
different build identity. Later package support supplies its immutable resolution
identity without requiring M6 implementation now.

## 19. H16 — bounded tooling lifetimes and responsiveness

**M2.5 delivery: explicit lifetimes, accounting and verified reclamation.** Spec
§15's process-exit reclamation remains appropriate for one-shot work, not a blanket
policy for reusable query sessions. This extends H10 without mandating a daemon.

- Separate request arenas, snapshot storage and evictable reusable caches. Define
  who pins a snapshot, when a pin expires/releases, and what a stale handle returns.
  Never evict storage still referenced by an active query or edit plan.
- Implement bounded multi-request/batch reuse. Add a persistent transport only if
  H25 startup/reparse measurements justify it; record the decision either way.
  A selected persistent implementation must satisfy the same reclamation tests.
- Account for total source/IR storage, workers, outstanding requests, generic and
  comptime work, diagnostic bytes and artifact buffers. Per-evaluation limits do
  not bound thousands of simultaneous individually legal evaluations.
- Define cancellation checkpoints, outstanding work disposal and cache publication
  boundaries. Deadlines are distinct from deterministic work budgets. An aborted
  check cannot leave a successful snapshot or an inferred empty dependency set.
- Prefer a scheduler with explicit memory/backpressure limits over automatically
  launching one memory-heavy task per logical core. Measure dependency critical
  paths, queue wait and peak aggregate allocation before changing worker defaults.

Acceptance: at least 10,000 edit/query/revert cycles under a fixed cache budget;
eviction with pinned/unpinned snapshots; cancelled generics/checks; worker failures;
queued-request saturation and repeated allocation failure. Report retained memory
after warmup and reclamation, not just process-exit memory. H25 sets named latency
and memory limits before tuning; allocator reservation and live allocations are
reported separately.

## 20. H17 — semantic search and safe change planning

**M2.5 delivery: compiler-backed CPU search and rename/move/delete planning.**
Extend H08/H09; exact command spellings and schemas are decided during Stage B.

- Query by declaration kind/signature, resolved reference, call/address-taken edge,
  field read/write, ownership/borrow use, allocation, blocking, unsafe boundary and
  compile-time phase. Return provenance and completeness per relation. Unsupported
  GPU/later-module relations are unavailable, not falsely empty.
- Plans report source edits, affected contracts, public/ABI effects, affected
  instances and validation obligations. Distinguish behavior-preserving refactors
  from behavior-changing migrations. A successful type check alone proves neither.
- Define roots for deletion: executable entry points, tests, exports/FFI, function
  values, compile-time uses, kernel entries and generator registrations. Unknown
  indirect/external consumers prevent a complete safe-delete claim. Offer an
  explicitly incomplete impact report, not a fabricated closed-world proof.
- Module moves must preserve or explicitly migrate lookup/nominal/protocol identity.
  Renaming qualified error names can change numeric `err` values; exports, foreign
  symbols and externally meaningful strings also require compatibility review.
  No blanket text substitution across comments, data or string-based registrations.
- Preserve unrelated text/comments and snapshot-check every edit. Changed or deleted
  symbols invalidate relevant IDs/cursors; plans cannot silently retarget by name.
- Define public API compatibility separately from internal reachability. Until an
  export/visibility boundary is revised, honor the current exported module surface.

Acceptance: shadowed names; aliases; same spelling in unrelated modules; callbacks;
public symbol without internal uses; error/module rename; protocol-sensitive move;
generic-only and comptime-only reference; generated reference; missing dependency;
stale plan and incomplete graph. Verify changed references and behavior independently.
Future GPU/FFI/package roots have named fixtures enabled when their features arrive;
their absence cannot become evidence that a deletion is globally safe.

## 21. H18 — bounded, versioned harness transport

**M2.5 delivery: real protocol/schema migration and bounded output.** Extend H08
compact context to diagnostics, indexing, parse export, tests and program capture.

- Define selectable projections and document/symbol tables with snapshot-local IDs.
  Keep a lossless export for consumers that need it; do not require a full token or
  AST dump to answer a narrow semantic question. Include version/capability discovery.
- Every bounded result reports completeness and why it stopped. Exact omitted
  counts may be unknown when traversal stops early; report unknown rather than
  inventing a count. Cursors bind snapshot, query and projection and expire explicitly.
- Fix the roadmap/schema discrepancy: current v1 `edit`/`fix` cannot carry the
  promised expected-source hash. Introduce a versioned schema with document/snapshot
  preconditions, byte spans, edits, applicability and validation obligations. Do not
  add fields to a closed v1 record while continuing to label it v1.
- Add machine-readable diagnostic reasons and typed facts such as expected/actual
  type, resource state, failed phase, unsupported capability or exhausted budget.
  Keep stable causal relations; message wording is not the machine discriminator.
- Replace unbounded complete-output capture as the sole `run --json` contract.
  Bound memory, disk capture and transport; define stdout/stderr chunks or artifact
  references, byte counts, truncation, binary encoding and overflow policy. Draining
  or terminating a flooding child must avoid pipe deadlock and report lost output.
- Separate timely progress from canonical final results. Specify ordering, sequence
  IDs, backpressure, disconnect/cancellation and final status for each transport.
  Output completion must not be confused with child-process success.
- Validate every published JSON example against its selected schema, including
  mandatory diagnostic-parent fields. Reconcile package source coordinates and
  future manifest fields through a versioned extension, not an incompatible v1 reuse.

Acceptance: schema validation of real commands and examples; old-client rejection
or negotiated support; narrow query on a large index; early pagination; binary and
flooding child output; slow/disconnected consumer; cancelled test suite; invalid
cursor; stale fix. Measure serialized bytes and actual tokenizer costs under H25.
No output limit may silently turn an incomplete check/test into a passing result.

## 22. H19 — generated-source provenance and editability

**M2.5 delivery: source-map/tooling contracts and supported generated-input fixtures.**
Do not require the future package runner or a new general generator framework.

- Distinguish the physical compiled span, displayed origin, generator identity,
  input/artifact hashes and permitted edit target. Provenance mappings may be
  many-to-one or noninvertible; an origin location is not automatically a fix span.
- Mark generated output as directly editable, regeneration-owned or unknown.
  Regeneration-owned changes target the generator/input through a validated plan;
  do not automatically execute arbitrary generator commands from metadata.
- Propagate provenance through specialization, inlining, cleanup generation and
  CPU/device lowering. Preserve chains with bounded expansion and explicit omissions.
- Include maps/origins in tooling cache identities. Changing only a source map must
  refresh diagnostics and references without unnecessarily invalidating executable
  code. Stale or unavailable maps fall back to honest physical locations.
- Specify regeneration determinism, stale-output detection and conflict handling.
  Directly modified outputs must not be overwritten silently during a repair.

Acceptance: one input producing several declarations; combined inputs; nested maps;
map-only change; missing generator; hand-edited generated output; mapped diagnostic
with no inverse edit; stale generator hash. Verify fixes never modify an approximate
origin as though it were an exact editable span. Metadata text remains untrusted
data, not harness instructions or authority to run tools.

## 23. H20 — compilation policy and generated-code performance

**M2.5 delivery: measured CPU policy decision, versioned semantics and explanation
records.** This is not a requirement to build every advanced optimizer before M3.

- Separate semantic check, development emission and bounded release optimization
  objectives. Decide supported modes and expose them in build/query identities.
  H03 safety guarantees cannot silently disappear in the faster mode.
- Reevaluate the permanent cross-module 40-NIR-instruction cap and fixed pipeline
  against representative workloads. Retain them if justified; otherwise record a
  versioned replacement with compile-work/code-size budgets. No cap is universally
  optimal and faster emission alone does not establish faster programs.
- Measure copies, redundant checks, allocations, loop code, specialization growth,
  register pressure and inlining effects. Serialize enough checked type/effect/alias
  information to support valid optimization without unsafe assumptions or repeatedly
  importing entire bodies. Define lazy access to `.em` sections where useful.
- Emit structured reasons for performed/missed transformations supported by the
  implementation: origin, decision, relevant precondition and cost/budget. Features
  not implemented, such as a proposed vectorizer, must be reported as unavailable.
- Require semantic/IR verification across transformations and independent execution
  tests. Removing a check requires an actual proof under the selected contract.

Acceptance: same valid CPU workloads across supported policies; retained/eliminated
checks; observable aggregate copies; generic growth; inline-sensitive workloads;
phase timings and executable size/runtime reports. Replace unconditional speed
claims with measured targets. H25 freezes regression budgets and decisions.

**Later delivery:** advanced loop/vector optimizers, profile-guided optimization
and additional optimization tiers require separate workload-backed decisions and
named milestones. M2.5 closes their architectural constraints and disposition,
not nonexistent implementation/performance evidence.

## 24. H21 — explicit CPU/GPU dependency composition

**M2.5 delivery: frozen design, schemas and positive/negative fixture manifest.**
Extend H13. Neper composes host execution with device kernels and explicit memory
domains; it does not promise a single arbitrary CPU/GPU instruction stream.

- Define completion tokens/events, submission identity, same-queue ordering and
  cross-queue device-side waits. A host whole-queue wait remains available but is
  not the only way to express a dependency. Report implicit synchronization.
- Specify buffer/range read and write uses, alias/overlap treatment, ownership and
  outstanding access. Safe release/reuse must wait for every relevant use across
  queues, not merely the release queue. Conservative whole-buffer tracking is a
  valid first implementation if its restrictions and costs are explicit.
- Freeze host/device visibility, atomic scope/order, barriers and ownership-state
  transitions. A token's completion must specify which work and visibility it covers.
- Define failed/partial submission, asynchronous failure, device loss, cancellation,
  destruction and cross-device token misuse. Requesting cancellation is not proof
  that device memory can be released. Decide rejection/reporting for dependency cycles.
- Expose kernel requirements and submission dependencies in H08/H18 records with
  checked/declared/unknown provenance. Dynamic graphs cannot be claimed statically
  deadlock-free without a defined proof.
- Freeze the concrete discovery/selection extension in spec §10 (D83): bounded
  `devices`, `DeviceInfo`/`DeviceKey`/`DeviceKind`, `open_id` and `info`. Document
  backend-local ordinals, provider-limited UUID stability, duplicate-key rejection,
  unknown identity/capacity, per-open ownership and explicit application selection.
  H18 must expose requested and actually selected backend/key distinctly; no silent
  fallback or cross-backend identity inference. Validate CPU/Vulkan mock inventory
  fixtures during design; real backend execution remains M3/M4.

Acceptance before M3: reviewed state-transition tables, exact planned API/type/error
contracts and fixtures for two queues sharing buffers, chained transfers, early
release, range overlap, failure, stale tokens and device loss. Design/schema tests
may run now; actual device acceptance remains pending.

**M3 delivery:** implement the chosen contracts and run CPU/device positive and
negative fixtures, including overlap/order observations and lifetime enforcement.

## 25. H22 — end-to-end GPU cost and artifact lifecycle

**M2.5 delivery: frozen accounting, baseline API/cache design and later-work
disposition.** Device measurements are not a pre-M3 runtime requirement.

- Specify measurements for host staging/allocation/copy, transfer, submission,
  queue wait, driver/pipeline compilation, kernel execution and readback. Separate
  cold and warm end-to-end latency; SPIR-V/PTX emission does not finish compilation.
- Define bounded staging reuse/pooling, caller-visible limits and allocation-failure
  behavior. Keep simple safe upload APIs. Optional pinned/borrowed asynchronous
  transfer must carry explicit host lifetime and mutation obligations under H01/H02.
- Design batched submission and pipeline warmup/cache interfaces. Cache identity
  includes relevant device/driver, shader, specialization, capability, numerical,
  safety and compilation options. Corrupt/stale caches rebuild safely under H24.
- Specify instrumentation availability and timestamp limitations. Host and device
  clocks are not assumed interchangeable; overlapping phase durations are not
  blindly summed into wall time. Report instrumentation overhead separately.
- Preserve the current CPU kernel backend's role as a checked debugger. Decide
  whether an optimized CPU kernel path is a future product requirement; do not
  advertise debugging state-machine execution as a fast fallback.

Acceptance before M3: timeline record schema, cache-key matrix, bounded staging
state model, failure fixtures and cold/warm workload definitions with output oracles.
Record exactly which baseline staging/batching/cache features M3 will implement.

**Later delivery:** M3 supplies device execution and overhead measurements. Reusable
execution graphs, optional pinned paths and an optimized CPU kernel backend require
separate named delivery decisions. Their interfaces must not undermine the frozen
lifetime contract, but implementing them is not necessary to close M2.5.

## 26. H23 — executable numerical and capability contracts

**M2.5 delivery: correct normative claims, versioned capability matrix and fixtures;
execute applicable CPU cases.** GPU execution evidence belongs to M3.

- Correct spec §10's exhaustive equivalence exceptions: CPU subgroups are currently
  fixed at 32 while device widths vary. A kernel writing `gpu.subgroup_size()` is a
  counterexample even without floating-point approximation. Define equivalence
  under matching width/mapping/active-lane assumptions; separately define kernels
  intended to be subgroup-independent. Freeze configurable emulator test cases.
- Correct spec §11's denormal rule: `shaderDenormPreserveFloat32` indicates support
  for preservation, not a guarantee that omitting an execution mode preserves it.
  Query required capabilities and emit matching modes. Define explicit rejection
  or supported fallback; remove assumptions about every desktop device. Cover FTZ,
  `f64`, rounding, signed zero, infinities, NaNs and contraction independently.
- Build a per-operation/backend matrix of exact results or error bounds, legal
  widths/layouts, exceptional inputs, required capabilities, subgroup dependence
  and atomic nondeterminism. Avoid postponing normative accuracy bounds to future
  library implementation or treating a native opcode as proof of exactness.
- Preserve explicit approximation choices; do not introduce blanket fast-math
  behavior through a build flag. Cache identity includes numerical policy.
- Specify unsupported-capability diagnostics, launch preconditions and the device
  safety-check/reporting contract agreed under H03/H13. CPU poisoning/emulation is
  evidence for tested cases, not proof of race freedom or universal GPU equivalence.

Acceptance: machine-checkable matrix with linked CPU/M3 fixtures for supported
subgroup widths and partial groups; denormals and boundary rounding; exceptional
values; FMA/contraction; reductions; width-sensitive integers and capability refusal.
Every equivalence claim names its preconditions and oracle. Verify emitted device
execution modes and hardware behavior in M3, not just numerical output on one CPU.

## 27. H24 — hostile inputs, artifact integrity and aggregate limits

**M2.5 delivery: harden implemented readers/caches and CPU work scheduling.** Future
device/package readers inherit the frozen contract when those features arrive.

- Treat source, cache modules, source maps, protocol requests and metadata as
  potentially malformed. Validate versions, tags, lengths, offsets, integer
  arithmetic, section overlap, graph references and checksums before use. Bound
  decompression/decoding, recursion, allocations and diagnostic expansion.
- Distinguish trusted local optimization caches from imported/shared artifacts.
  CRC/fast hashes detect some corruption but do not authenticate untrusted content.
  Specify strong content integrity, compatibility checks and provenance requirements;
  untrusted cache metadata must not grant execution or generator permissions.
- Validate serialized typed IR and relocations before emission/reuse. Corrupt
  disposable caches can be quarantined/rebuilt; mandatory corrupt inputs produce
  explicit failures. Never fall back to unchecked execution of an invalid artifact.
- Enforce whole-request/build budgets across workers, instantiations and comptime
  evaluations. Limit caches/indexes/output as well as computation. Deterministic
  work exhaustion, cancellation and infrastructure failure have distinct statuses.
- Publish cache entries only after successful validation and complete writes.
  Concurrent writers, crashes and injected storage errors cannot create accepted
  partial records. Preserve the last known valid entry where applicable.

Acceptance: byte/mutation fuzzing of every implemented decoder; adversarial sizes
and cyclic references; hash collision/corruption injection; interrupted writes;
version mismatch; decompression bombs where compression exists; many individually
legal jobs exceeding the global budget; incremental cache fault injection.
Bounded inputs must not hang/crash the compiler or produce runnable invalid output.
Retain minimized reproducers and regression tests; clean/incremental semantic
equivalence is a required oracle, not the sole independent correctness oracle.

## 28. H25 — reproducible performance and harness acceptance

**M2.5 delivery: executable CPU/tooling measurements and registered GPU workload
designs.** Extend H12; do not replace its semantic/LLM thresholds with throughput.

| Workflow | Required measurements and correctness guard |
|---|---|
| Cold build | Wall/CPU time, peak memory, phase/critical-path timing; clean output oracle |
| No-op check | p50/p95 latency, reads and actual semantic/emission work; current snapshot |
| Local edit/revert | Rechecked declarations, emitted functions, invalidation edges, bytes; H14 reuse oracle |
| Rename/move/delete | Query/plan/apply/check latency, changed references, unrelated diff; H17 completeness |
| Context/repair | Serialized bytes, tokenizer-specific tokens, calls/retries, total time; verified success |
| Persistent/batch session | Warm memory slope, cache eviction and cancellation latency; no stale results |
| CPU program | Throughput/tail latency, allocations/copies, executable size; same defined behavior |
| GPU cold/warm, M3 | End-to-end and phase times, transfer bytes/synchronization; H21/H23 output oracle |

- Freeze hardware/OS/toolchain, compiler revision, workload/data hashes, options,
  cache states, worker counts, repetitions and numeric budgets before candidate
  tuning. Archive raw observations and reproducible commands. Distinguish empty
  compiler caches from cold OS caches; record thermal/power/background-work controls.
- Use small interactive projects and real larger dependency graphs, generic-heavy
  code, generated files, high fan-out, malformed intermediate edits and repeated
  refactors. Include CPU/GPU transfer-bound as well as compute-bound future cases.
- Report per-workload distributions and paired changes; averages cannot hide tail
  regressions. Record measurement noise, instrumentation overhead and exclusions.
  A cache hit without a timing win is not itself a performance success.
- Attribute compiler stages, dependency wait, filesystem/link work and driver work
  separately. Compare runtime only for equivalent semantics and safety contracts;
  report intentional differences rather than rewarding unchecked behavior.
- Evaluate full harness cost per verified success, including unsuccessful runs,
  retries, timeouts and output retrieval. Measure tokenizer identities empirically;
  source characters, lexer tokens and model tokens are different quantities.
- Set numeric latency/memory/code-size/runtime regression thresholds from the M2
  baseline in Stage A, with rationale and noise margins. For features absent in M2,
  freeze workload and absolute budget before implementing/tuning the candidate.
  Exceeded budgets require an explicit recorded decision before closure; no silent
  rebaselining or removal of safety obligations.

Acceptance: reproducible Windows/Linux CPU reports, H12 two-family evidence, H14–H24
applicable conformance/fault tests and a budget decision for every regression.
GPU reports are marked pending with named M3 owners/workloads, never filled with
emulator timings and labeled device performance. No claim to be fastest overall is
made from this suite; claims name the workload, configuration and measured evidence.

## 29. Migration, affected documents and exit checklist

Execute the work in dependency order:

| Stage | Work | Exit evidence |
|---|---|---|
| A — M2 baseline | Preserve compiler/source; freeze H12/H25 tasks, models, measurement environment and budgets | Reproducible baseline and held-out evaluation manifest |
| B — integrated design | Resolve H01–H07; specify H08/H09 and H14–H20/H24 architecture; freeze H13/H21–H23 GPU contracts | Versioned semantics/API/schema drafts, checked-subset boundary, CPU/M3 fixture manifest and later-work dispositions |
| C — CPU implementation | Implement H01–H11 and H14–H19/H24 CPU obligations on one semantic graph; deliver H20 policy/explanation work and applicable H23 corrections | Implemented contracts, reusable queries, bounded verified artifacts, transactional tools and executable guidance |
| D — migration and proof | Migrate compiler/M2 libraries; run H10/H12/H25 and all applicable H14–H24 tests; close GPU design dependencies | Self-host, ABI, determinism, conformance, resource/performance and two-family evidence reports |
| E — M3 admission | Validate the closure ledger against artifacts and normative versions | All H01–H29 M2.5 obligations closed; M3 begins against frozen contracts with device evidence explicitly pending |

H02 depends on H01's identity/borrowing model; H04 depends on both. H05 must agree
with their alias rules. H08/H09 consume the actual checked semantics and H11 exposes
them. Stage B must resolve these interactions before adding syntax independently.
Later-library API alignment can proceed after the core model freezes, but cannot
substitute for migrating implemented M2 code.

H15 snapshot/cache identity underpins H14 reuse, H17 plans and H18 cursors. H16/H24
bound their resources and hostile-input behavior. H19 provenance participates in
tooling cache identity, not just rendering. H20 may consume H01–H06 summaries but
must not weaken their guarantees. H21–H23 extend H13 and depend on the same resource,
snapshot, numerical and transport contracts. H25 measures these interactions.

Stage B must explicitly disposition these four known contract defects: subgroup
equivalence (H23), denormal capability versus execution mode (H23), missing fix
preconditions in the closed stream schema (H15/H18), and dependency-cache collision
verification (H15/H24). They require actual normative corrections and applicable
tests during M2.5, not only links to this planning document.

First preserve a reproducible M2 compiler artifact and matching source for the
transition. Decide and record the new language, grammar, stream and `.em` format
versions rather than silently changing draft 0.1 or adding fields to closed v1
records. Existing consumers can keep using the old profile during migration only
where the implementation actually supports it; unsupported profiles fail explicitly.

Compile the first new compiler with the M2 predecessor using old-language source,
then migrate its own sources once it implements the new rules. Reproduce that
sequence on both hosts and compare final self-host stages. Do not require restoring
or extending the C bootstrap. Cache safety summaries and protocol contracts enter
signature/dependency hashes, so stale artifacts are invalidated across migration.

| Area | Required synchronized changes during M2.5 |
|---|---|
| Language/compiler | `spec.md` §§1, 4–15; `grammar.ebnf`; decisions including D3/D14, incremental reuse, pipeline budgets, numerical and protocol/tooling rules |
| Machine interfaces | `tooling.md`, versioned schemas, diagnostics, snapshot/overlay/refactor/context contracts, bounded streams, capability/profile discovery, build/source-map identities |
| Libraries | `e.mem`, `e.str`, containers, `e.os`, I/O, threads/sync/channel and affected wrappers; exact API fences and source |
| Module plan | `modules.md`, `module-apis.md`, `modules.json`; preserve delivery milestones, record actual revised surfaces/dependencies |
| Verification | conformance fixtures, GP workload designs, LLM cards, benchmark manifests/oracles/reports, compiler/ABI tests, cache/decoder fault injection and performance budgets |
| GPU design | spec §§10–11 and planned `e.gpu` contracts, numerical/capability matrix, events/ranges/staging/cache/timeline records, plus asset/gfx/ui dependencies; runtime work remains M3/later |

M2.5 is a cross-cutting gate, not a new module delivery tier or an unvalidated
`milestone` enum in `modules.json`. Do not mark planned modules delivered to satisfy
it. The library migration covers actual M2 surfaces; later API proposals must be
aligned with the new contract before their implementation.

During M2.5, add a machine-checkable closure manifest and read-only validation
command to CI. Each record binds an H ID, decision revision, implementation/source
revision, conformance results, benchmark report and applicable target/profile.
Record delivery scope (implemented CPU/tooling or frozen future contract), owner,
normative version, fixture IDs, evidence hashes and any explicitly later milestone.
Design-only GPU closure must bind the frozen API/state/matrix and M3 fixture
manifest; runtime results remain pending. Optional later projects need an explicit
deferred/rejected/adopted disposition and must not masquerade as implemented features.
Missing, stale, failed or explicitly incomplete required M2.5 evidence keeps the item open;
status text alone cannot mark it complete. Define the manifest schema as part of
the tooling work, without overloading the existing module-delivery manifest.

M3 may begin only when all H01–H29 M2.5 closure records exist, chosen CPU changes and
tools are implemented, normative documents agree, the self-hosted compiler and M2
libraries are migrated, conformance/determinism/ABI tests pass on Windows and Linux,
the H12/H25 reports pass, and H13/H21–H23 future device fixtures/contracts are frozen.
An open defect within a promised guarantee, missing performance decision, unversioned
protocol change or unmeasured LLM claim keeps M2.5 open.

Rejected as automatic additions: a general Rust-style trait/borrow language,
implicit destructors, automatic source correction, universal effect polymorphism,
mandatory callback arguments at every use, a persistent compiler daemon without
latency evidence, or syntax compression optimized for one tokenizer. Any of these
would need its own evidence-backed decision; none follows just from the article.

## 30. H26–H29 — LLM-processing recommendations

Added 2026-09-06 by the recommendation review in
[`llm-hardening-recommendations.md`](llm-hardening-recommendations.md). These four
items close the difference between a language that is *readable by the human reviewing
model output* and one that is *operated on by a model end-to-end*. They are
supplementary M2.5 obligations under the same closure policy as H01–H25, each with its
own closure record, conformance fixtures and measurements. They do not supersede any
earlier item, and their acceptance rules are the R08–R11 sections of the
recommendations document.

- **H26 — tokenizer grounding.** Publish a grammar-versioned tokenizer profile per
  supported model family (a documented BPE extension or a canonical vocabulary table)
  so token cost is a design input rather than a post-hoc measurement. Consumed by H25's
  harness-cost accounting and H06's "lexical token count is not model token count"
  distinction.
- **H27 — unsafe/escape-hatch enumeration.** Every `@nocheck`, bare `union`,
  `mem.bitcast`/`mem.cast`, raw dereference and `extern` site must be enumerable in one
  bounded pass with `trusted`/`unknown` provenance. This is a precondition for the
  H03 "checked subset" claim: the boundary must be enumerable, not merely declared.
- **H28 — compiled LLM cards.** Language cards are generated from `grammar.ebnf` and
  the closed registries with a grammar-revision stamp and content hash, so a card and
  the grammar cannot drift. Prerequisite for H11's "old and revised cards cannot be
  confused".
- **H29 — structured edits.** The v2 tool stream expresses semantic refactors as typed
  AST operations with pre/postconditions in addition to byte spans, so H09/H17
  multi-file migrations are verifiable rather than text-replacement-fragile.

Each of H26–H29 is a tooling/protocol obligation, not a new language construct; none
introduces syntax, and none relaxes a check or a threshold established by H01–H25.
