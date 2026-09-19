# Neper — post-M2 language and compiler hardening for LLMs

Status: scheduled design and implementation plan, recorded 2026-09-05 and extended
2026-09-18. Work starts after M2 but closes through separate delivery tracks. The
narrow **M2.5-core** language/GPU-contract gate blocks M3; agent tooling v2 (T2), its
trusted host/executor and the comparative claim gate (E2) proceed independently and
do not block compiler/backend milestones. H45 remains later release work. No item is
implemented by this document. Current language, grammar, APIs and tooling remain
authoritative until the responsible track lands an explicitly versioned replacement.
[`hardening-tracks.json`](hardening-tracks.json) is the machine-readable authority
for track membership and current status; this document remains the authority for
requirement meaning and acceptance.

The prioritized, concrete recommendation set distilled from this review lives in
[`llm-hardening-recommendations.md`](llm-hardening-recommendations.md). It maps each
recommendation onto the H items below. R08–R11 are registered here as H26–H29. The
later toolchain landscape review adds R12–R16, registered as H30–H34, to close the
remaining check-latency, diagnostic, test-transport, token-pressure and integrated-
workflow gaps. The subsequent operational gap audit adds H35–H44 to make requested
intent, authority, execution environment, parallel changes and verification quality
part of that loop; H45 is an explicitly later release-provenance bridge. H26–H44 are
supplementary T2/E2 obligations under the same evidence policy as H01–H25; they do
not supersede any earlier item.

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

The governing design objective for all post-M2 hardening tracks is:

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
- [`llm-agent-compiler-toolchain-research.md`](llm-agent-compiler-toolchain-research.md)
  compares the agent-facing loops of Go, Rust, TypeScript, Python, Zig and C/C++.
  Its comparative ratings are research input, not evidence that Neper already leads
  any category; H30–H34 turn the identified gaps into measured requirements.
- [MCP's tool-annotation guidance](https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)
  distinguishes descriptive risk hints from authorization or sandbox enforcement;
  H36 therefore does not trust effect labels as a security boundary.
- [Bazel's test environment specification](https://bazel.build/reference/test-encyclopedia)
  motivates declared, hermetic test inputs and explicit infrastructure failure for
  H37/H39 rather than retrying ambient nondeterminism into a pass.
- [VS Code's parallel-agent worktree guidance](https://code.visualstudio.com/docs/agents/guides/delegate-two-tasks)
  distinguishes file isolation from security and still requires integration/retest;
  H38 specifies the compiler-facing bundle and semantic revalidation contract.
- [MCP Tasks](https://tasks.extensions.modelcontextprotocol.io/) illustrates durable
  handles, structured input/approval, reconnect and cooperative cancellation for H44.
- [SLSA 1.2 provenance](https://slsa.dev/spec/v1.2/provenance) provides the external
  source/build provenance model targeted by the later H45 exporter.

## 2. Scheduling and decision policy

All tracks start after a recorded M2 baseline. M2.5-core freezes and implements the
language changes and GPU-facing contracts on which M3 depends. T2 ships tooling v2
in independently usable vertical slices and may overlap M3. E2 evaluates versioned
product claims after the relevant T2 slices exist. H45 integrates with M6 release
provenance. M2 is assessed against its existing contract; none of these tracks adds
work to the throwaway C bootstrap.

Each H item below requires a closure record containing the selected design,
alternatives, exact normative changes, implementation and test references,
compatibility effects, measurements and remaining limitations. The owning track
stays open until that scoped record closes it. Existing v1 commands, stage-B
experiments and partial H implementations are inputs and evidence, not automatic
closure of a T2 or E2 obligation. Historical `m25-*` filenames and decision labels
record where work originated; this table determines its current owner. No syntax
example in an earlier conversation reserves a keyword or defines an API. In
particular `resource type`, `move`, `scope`, `mem.child`, `finish` and `neper
context` need concrete designs before implementation.

The recommendations below are the default direction. A replacement can close an
item only if it satisfies that item's acceptance obligations and records why it is
better. Relabeling a prototype as complete or substituting a documentation warning
for required enforcement does not close it. Relaxing a requirement needs an explicit
user-approved scope change.

| Track | Primary H scope | Owner and gate |
|---|---|---|
| M2.5-core | H01–H07, H13, H21–H23 | Language/compiler team; blocks M3 |
| T2 compiler/tool service | Functional/conformance H08–H11, H14–H20, H24, H26–H32, H35, H39, H41–H42 | Tooling-v2 schema and implementation; does not block M3 |
| T2 trusted host/executor | H34, H36–H38, H40, H44 | `neper-agent-host`; owns final verification, authority, sandboxing, credentials, worktrees and durable tasks |
| E2 measured claim | H12, measured H20, H25, H33, H43 and comparative clauses of H30–H34 | Evaluation harness; gates only versioned superiority claims |
| M6 release provenance | H45 | Package/release system; later delivery |

Cross-track dependencies are explicit interfaces, not reasons to collapse ownership.
The compiler publishes semantic facts and requested effects; only the trusted host
grants authority and enforces OS policy. T2 may ship after conformance even when E2
does not win a comparison. A competitor or model update can expire an E2 claim but
cannot reopen a completed implementation milestone. Design-only GPU closure names
the future fixtures and keeps runtime evidence pending rather than passed.

## 3. Inventory and recommended disposition

| ID | Current exposure | Required outcome | Main cost |
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
| H26 | Token cost is deferred rather than steered | Measured per-tokenizer token/repair budgets that gate syntax-change proposals, not adoption | Model/tokenizer harness and corpus freeze |
| H27 | Unsafe/escape-hatch sites are not enumerable | One-command enumeration of every unsafe boundary with provenance | Index/context extension and provenance tags |
| H28 | LLM cards are hand-written prose that can drift | Compiler-generated, grammar-versioned cards with content hash | Card generator and schema |
| H29 | Semantic refactors are expressed as raw text spans | Structured AST-level edit operations with pre/postconditions in the v2 stream | Tool protocol v2 and edit planning |
| H30 | A local edit has no explicitly cheapest sound validation path | Tiered syntax/affected/workspace checks with category-leading p50/p95 latency | Phased checker, reuse and optional retained session |
| H31 | Structured diagnostics still mix compact response and full evidence | Causal graph, cross-run fingerprints, staged repair plans, effect labels and retrievable complete results | Tool protocol v2, result store and repair fixtures |
| H32 | Test JSON emits every pass and arbitrary output inline | Structured selection plans, constant-size pass summaries and normalized failure evidence | Test protocol v2 and impact/caching integration |
| H33 | Source compactness is not budgeted with the rest of the interaction | Per-component and total token budgets per verified success | Token harness, compact projections and result references |
| H34 | Good commands do not yet form one discoverable agent workflow | One snapshot-consistent loop with an explicit verified stop state and evidence receipt | Capability/workflow schema and end-to-end comparative gate |
| H35 | Verification does not bind the user's requested behavior and constraints | External, content-addressed change contract bound into the receipt | Contract schema, executable obligations and provenance |
| H36 | Effect labels describe risk but do not enforce authority | Default-deny execution policy with grants, approvals, observation and audit | Policy engine, sandbox/executor integration and denial fixtures |
| H37 | Host state can change results without entering identity | Hermetic/observed/uncontrolled environment manifests and replay | Environment capture, isolation and cache/receipt integration |
| H38 | Independently valid agent changes can conflict when combined | Snapshot-based change bundles, semantic conflict detection and integration verification | Bundle schema, worktree integration and graph-aware merge checks |
| H39 | Retries can turn nondeterminism into an apparent pass | Explicit flaky outcome, attempt evidence and non-verifying quarantine | Test runner semantics, seeds and cache policy |
| H40 | Passing selected tests does not prove acceptance obligations were covered | Requirement-to-evidence coverage graph with explicit unknown/uncovered state | Obligation mapping and verification policy |
| H41 | Runtime failures still require interpreting process text | Normalized run outcomes, source-mapped frames and bounded evidence | Runner/runtime protocol and source maps |
| H42 | Public change impact lacks a canonical compatibility result | Source/ABI/behavior/serialization API diff and migration plan | Interface snapshots, target rules and structured plans |
| H43 | A functional pass can hide a required performance regression | Contract-bound benchmark obligations with reproducible distributions | Benchmark protocol, baselines and statistical decisions |
| H44 | Long operations cannot survive disconnect or structured approval waits | Durable authorized task handles, progress, input and cancellation | Task store, lifecycle schema and recovery tests |
| H45 | Local verification receipts do not connect to release provenance | Later standards-based source/build provenance export | M6/release integration, signing and verifier interoperability |

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
`e.text.utf8` through this cross-cutting gate. H01/H02/H07 control ownership and native
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

## 15. H12 — E2 evaluation and claim evidence

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
This is the **broad-generation cohort** and characterizes transfer; it does not support
a leadership claim. The separate **registered agent-tooling cohort** is Go, Rust,
TypeScript and Python and alone supports the five-category E2 claim.

Required E2 claim gate:

1. On supported CPU tasks, each model family meets the existing thresholds: 95%
   first-pass local-edit parsing, 90% first-pass type checking, median unrelated
   formatted diff zero, and 95% repair within one additional turn. No accepted task
   needs human-output scraping or undocumented compiler behavior.
2. Every applicable fixed CPU/tooling conformance fixture passes; design-only GPU
   cases satisfy their explicit M2.5-core design obligations instead
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

Design the mapping of H01–H07 onto devices now; implement and execute device tests
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

**T2 tooling-v2 delivery: implemented CPU compiler/query reuse.** Extend H10; do not count
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

**T2 tooling-v2 delivery: implemented snapshot, overlay and publication contracts.** Extend
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

**T2 tooling-v2 delivery: explicit lifetimes, accounting and verified reclamation.** Spec
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

The batch transport now exposes the first reusable accounting slice (D558): live
and reserved arena bytes, the checked snapshot, the session baseline after loading
the batch, and peak temporary request bytes. The before/after fixture proves that a
nonzero peak is reclaimed to the same retained baseline. Eviction, pinning and the
full edit/query/revert fixed-budget acceptance remain open.

The fixed-budget batch soak now runs ten thousand context queries against one checked
snapshot on both hosts (D559). Its final memory report counts all ten thousand,
records a nonzero temporary peak, and has returned exactly to the original session
baseline. Edit/revert cycling, eviction and pinning remain open.

## 20. H17 — semantic search and safe change planning

**T2 tooling-v2 delivery: compiler-backed CPU search and rename/move/delete planning.**
Extend H08/H09; exact command spellings and schemas are frozen in the owning T2
slice.

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

**T2 tooling-v2 delivery: real protocol/schema migration and bounded output.** Extend H08
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

**T2 tooling-v2 delivery: source-map/tooling contracts and supported generated-input fixtures.**
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

**T2 implementation and E2 measured closure: versioned CPU policy and explanation
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
named milestones. T2 closes their architectural constraints and disposition,
not nonexistent implementation/performance evidence.

## 24. H21 — explicit CPU/GPU dependency composition

**M2.5-core delivery: frozen design, schemas and positive/negative fixture manifest.**
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
- Reserve schema hooks for kernel requirements and submission dependencies. T2
  exposes them through H08/H18 records with checked/declared/unknown provenance;
  that projection is not an M2.5-core exit condition. Dynamic graphs cannot be
  claimed statically deadlock-free without a defined proof.
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

**M2.5-core delivery: frozen accounting, baseline API/cache design and later-work
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
lifetime contract, but implementing them is not necessary to close M2.5-core.

## 26. H23 — executable numerical and capability contracts

**M2.5-core delivery: correct normative claims, versioned capability matrix and fixtures;
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

**T2 tooling-v2 delivery: harden implemented readers/caches and CPU work scheduling.** Future
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

**E2 claim-gate delivery: executable CPU/tooling measurements and registered GPU workload
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
  shared M2 baseline, with rationale and noise margins. For features absent in M2,
  freeze workload and absolute budget before implementing/tuning the candidate.
  Exceeded budgets require an explicit recorded decision before closure; no silent
  rebaselining or removal of safety obligations.

Acceptance: reproducible Windows/Linux CPU reports, H12 two-family evidence, H14–H24
and H30–H44 applicable conformance/fault/comparative tests and a budget decision for
every regression.
GPU reports are marked pending with named M3 owners/workloads, never filled with
emulator timings and labeled device performance. No claim to be fastest overall is
made from this suite; claims name the workload, configuration and measured evidence.

## 29. Delivery tracks, dependencies and closure

The H inventory is one requirement catalogue, not one release critical path.
Requirement semantics and acceptance live here; [`roadmap.md`](roadmap.md) owns
sequencing; [`tooling-v2-draft.md`](tooling-v2-draft.md) owns the non-normative T2
protocol design until it freezes; [`general-purpose-verification.md`](general-purpose-verification.md)
owns E2 measurement; [`hardening-tracks.json`](hardening-tracks.json) owns current
track membership and status. Other documents summarize or reference these authorities
rather than restating full requirements.

| Stage | Work | Exit evidence | Blocks |
|---|---|---|---|
| Baseline | Preserve M2 source/compiler and freeze shared workloads and identities | Reproducible artifact, source and environment manifest | Start of every track |
| M2.5-core design | Resolve H01–H07 and freeze H13/H21–H23 | Versioned language/ABI drafts and M3 fixture manifest | M2.5-core implementation |
| M2.5-core implementation | Implement/migrate selected semantics in compiler and delivered M2 libraries | Self-host, ABI, determinism, conformance and two-host migration evidence | M3 |
| T2.0 foundations | H15/H16/H18/H24 snapshots, identity, bounded transport/storage and publication | Frozen slice schema and conformance corpus | Later T2 slices |
| T2.1 understand/check | H08/H10/H11/H14/H19/H20/H26–H28/H30/H31 | Usable context/check/diagnostic workflow | T2.2 |
| T2.2 edit/test evidence | H09/H17/H29/H32/H35/H39/H41/H42 | Contract-bound evidence package; terminal state no stronger than `incomplete` | T2.3 |
| T2.3 trusted verification | H34/H36/H37/H40 in `neper-agent-host` | Policy/environment/coverage enforcement and scoped `verified` receipt | T2.4 and E2 |
| T2.4 integration/operation | H38/H44 in `neper-agent-host` | Integrated-snapshot revalidation and durable-task conformance | Trusted parallel/durable operation |
| E2 claim | H12/H20/H25/H33/H43 and comparative H30–H34 clauses | Reproducible versioned claim report | Only the associated public claim |
| M6 provenance | H45 | External-schema provenance and independent verification | Release provenance claim |

H02 depends on H01's identity/borrowing model; H04 depends on both; H05 agrees with
their alias rules. H08/H09 consume actual checked semantics. H15 identity underpins
all T2 results, H16/H24 bound their resources, H19 supplies generated provenance and
H31/H32 feed H34 receipts. H35 defines the requested obligations; H36/H37 bind
authority and environment; H40 proves coverage before H34 may say `verified`; H38
always revalidates an integrated snapshot; H39 prevents retries from manufacturing
verification. H21–H23 depend on H13 but not on T2 or E2.

`hardening-tracks.json` is the machine-checkable status and ownership index. Every
closed track additionally uses a closure manifest whose records bind an H ID and
track, normative or draft version, implementation revision, fixture IDs, evidence
hashes, applicable target/profile and remaining limitations. A requirement shared by
tracks has separate scoped closure records; evidence from one scope cannot silently
close another. Missing, stale, failed or incomplete evidence keeps only its owning
track open.

M3 may begin when H01–H07, H13 and H21–H23 close, the selected language/ABI changes
are implemented, the self-hosted compiler and affected M2 libraries migrate
reproducibly, and the frozen M3 fixture manifest is reviewed. T2, E2 and H45 remain
scheduled but do not block M3. T2 completion requires functional conformance, not a
competitive win. E2 thresholds control only claims tied to their exact benchmark
manifest; changed competitors, models or hardware require a new claim run, not a
reopening of M2.5-core, T2, M3 or later completed milestones.

Rejected as automatic additions remain a general Rust-style trait/borrow language,
implicit destructors, automatic source correction, universal effect polymorphism,
mandatory callback arguments at every use, a persistent compiler daemon without
latency evidence, and syntax compression optimized for one tokenizer. Each needs its
own evidence-backed decision.

## 30. H26–H29 — LLM-processing recommendations

Added 2026-09-06 by the recommendation review in
[`llm-hardening-recommendations.md`](llm-hardening-recommendations.md). These four
items close the difference between a language that is *readable by the human reviewing
model output* and one that is *operated on by a model end-to-end*. They are
supplementary T2 tooling-v2 obligations, each with its
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

## 31. H30–H34 — comparative agent-experience requirements

Added 2026-09-18 after the landscape review in
[`llm-agent-compiler-toolchain-research.md`](llm-agent-compiler-toolchain-research.md).
The earlier plan contains most necessary mechanisms, but mechanisms alone do not
guarantee that the common edit loop is fast, compact or coherent. These five items
split between T2 functional conformance and E2 comparative claims. They add no language syntax by
themselves and must reuse H08–H19's semantic graph, snapshots, transactions and
bounded transport.

### H30 — tiered, snapshot-correct fast checks

**T2 functional delivery; E2 comparative closure: implement the cheapest sound validation path for each edit.**

- The v2 tool surface exposes syntax, affected-semantic and workspace check scopes.
  Syntax checks parse/recover only the changed overlays. Affected checks validate
  the edited declarations and the transitive semantic dependants required by H14's
  graph. Workspace checks establish the full selected-program contract. None emits
  machine code, links, runs tests or probes runtime devices.
- Every result names the immutable H15 snapshot, source overlays, language/profile,
  target, options and compiler identity. It reports time to first diagnostic, total
  time, declarations/modules checked, reused units, invalidation causes,
  completeness, omissions and cancellation state.
- All scopes use the production parser, resolver and checker. A fast path may omit
  work only when the result states that narrower contract; it cannot use an
  approximate parser, stale index or separate type system and call the answer a
  complete semantic check.
- Batch requests are the initial retained-work mechanism. Before implementation,
  T2 freezes an absolute warm-latency, startup and resource budget independent of
  competitor rankings. If finite batch requests cannot meet it, implement a versioned
  retained session with bounded memory, explicit snapshot creation/release, overlays,
  cancellation, idle expiry and H16 reclamation. CLI, batch and retained forms must
  return equivalent canonical results for the same snapshot. E2 results cannot add a
  new T2 completion condition.
- Default output returns the smallest complete status or independent root
  diagnostics. Full evidence follows H31's result-reference contract; speed is not
  obtained by losing diagnostic information.

Acceptance: cold, warm no-op, single-body edit, public-signature edit, broken edit,
edit/revert and cancelled workloads on Windows and Linux. Assert clean/incremental/
batch/session equivalence, exact invalidation, no stale success and bounded retained
memory. On the pre-registered eligible workloads, warm p50/p95 total latency and p95
time to first useful diagnostic must rank first or be statistically tied for first
among the registered Go, Rust, TypeScript and Python agent-tooling cohort under
equivalent correctness obligations. Hardware, cache state, repository shape and
non-inferiority margin are frozen before candidate tuning under H25.

### H31 — causal diagnostics and recoverable compact evidence

**T2 functional delivery; E2 comparative closure: version the v2 diagnostic/result contract and implement both compact
and complete views.**

- Each diagnostic carries a result-local stable ID, nullable primary-cause ID and a
  versioned position-independent fingerprint for correlation across offset-only
  edits. The fingerprint is derived from code, source identity and semantic/syntax/
  content anchors, never prose or numeric positions. It is not a snapshot identity,
  precondition or proof. Diagnostics also carry phase, registered code, severity,
  exact span, normalized semantic fields, role-labelled related spans, provenance
  and bounded instantiation/call/generated-source chains. Dependent diagnostics are
  distinguishable from independent roots.
- The compact diagnostic carries stable namespaced repair hints, not full patches.
  A hint distinguishes applicability (`machine`, `review`, `placeholders`,
  `unspecified`) from execution safety (`automatic`, `review_required`, `dangerous`,
  `unsupported`) and states whether more context is required. A separate
  snapshot-bound query returns the minimal H29 repair plan with target diagnostic
  ID/fingerprint, status, all preconditions, typed actions, effects and verification
  obligations. A plan without executable verification is partial. Applying it is a
  separate transaction and produces a new snapshot or no mutation.
- Every planned action has an explicit effect set. Commands use argument vectors,
  name their working directory and classify workspace/outside writes, project-code
  execution, dependency change, network, credential, VCS and external-service effects
  with scope, safety and reason. Missing capability or policy prevents automatic
  execution. Applicability never implies safety or behavioral correctness, and
  secrets never enter plans.
- The default agent view emits independent root causes, bounded supporting notes and
  aggregate counts for dependent/suppressed/omitted diagnostics. It does not repeat
  source excerpts already addressable by span. Human rendering is a view over the
  same normalized objects, never the only representation.
- Whenever a bound omits information, the result includes a content-addressed
  `result_ref`, content hash, byte count and advertised lifetime for the canonical
  complete JSONL artifact. Reading that artifact does not rerun analysis and verifies
  the same snapshot/tool identity. Expiry is explicit; it is never confused with an
  empty result.
- Diagnostic ordering and IDs are deterministic for an identical snapshot and
  configuration. Broken source still returns a well-formed final status with the
  distinctions in H09; initialization failure remains the sole stderr exception.

Acceptance: independent and cascading failures, generic instantiation, related
ownership sites, malformed source, output bounds, stale fixes and result expiry.
Compact and complete views have the same independent-root set and counts; every
omitted record is retrievable until declared expiry. The held-out repair tasks require
no prose parsing and no compiler rerun solely to recover omitted evidence. Fixtures
prove fingerprint stability across unrelated preceding edits and change on a replaced
semantic anchor; hint-only output stays bounded; ambiguous/partial plans do not apply;
and commands with planted project execution, network, dependency, credential, VCS or
outside-workspace effects cannot appear effect-free or run under an insufficient
policy. Measure
diagnostic bytes/tokens, repair turns and successful machine-applicable fixes against
Rust JSON, Go/gopls and TypeScript language-service references; H34 owns the ranking.

### H32 — structured test planning, execution and evidence

**T2 functional delivery; E2 comparative closure: replace v1's pass-by-pass agent stream with a v2 plan/result
contract while retaining an opt-in complete event view.**

- Test discovery returns stable test identities, declarations and applicable target/
  mode. Execution accepts exact-test, module, H10 affected-set and full-suite plans.
  A plan records selection reasons, graph/snapshot identity, completeness and the
  conservative widening applied for unknown calls, global state, ABI or contracts.
- The default result is compact: requested/selected/executed/cached/passed/failed/
  skipped counts, duration and detailed records only for non-passing outcomes.
  Passing test bodies, banners and empty output are not emitted by default. An
  all-pass result is constant-size apart from fixed identity metadata.
- Outcomes distinguish source/build failure, runner setup failure, assertion,
  returned error, language trap, abnormal crash, timeout and cancellation. Failures
  carry test and assertion locations, structured expected/actual values when known,
  trap/error identity, retry count and deterministic failure identity.
- Arbitrary stdout/stderr is bounded inline and stored as H31 result artifacts when
  larger. Every byte remains recoverable without rerunning the test. Source/build
  diagnostics use H31 rather than becoming test-output text.
- Each record says whether evidence was executed, reused from an exact cache identity
  or not run. Cached success is never reported as fresh execution. The terminal
  result states whether every requested obligation ran or was validly cached.
- A complete event projection remains available for debugging and conformance. Its
  aggregate outcome must equal the compact view. Periodic full-suite jobs and planted
  selection faults audit the affected-set algorithm.

Acceptance: zero-test, all-pass, assertion, returned-error, trap, crash, timeout,
compile failure, setup failure, cached, affected-incomplete and output-flood cases.
Exact/affected plans run no unselected tests; incomplete impact widens rather than
claiming completeness. Default all-pass size is independent of test count. Compare
selection-to-result latency, bytes/tokens and one-turn repair success with Go's test
JSON and configured Rust/TypeScript/Python runners under H34.

### H33 — source and protocol token-pressure budgets

**E2 claim-gate delivery: make token pressure a component budget over the whole verified
trajectory, not a source-only statistic.**

- H25/H26 reports source generation, source rereads, language/API guidance, context
  queries, edit plans, diagnostic views, test views, complete-result retrieval,
  tool schemas, retries and final verification separately and in total. Failed,
  timed-out and abandoned trajectories remain in the denominator.
- Freeze default byte and tokenizer-specific budgets for the entry language card,
  common context projection, successful check, root diagnostic, all-pass test result
  and final verification before implementation tuning. Caller-selected larger views
  report their actual cost and completeness.
- Compact views remove repetition, passing noise and duplicated excerpts while H31/
  H32 retain complete evidence by reference. They do not replace semantic field names
  with undocumented abbreviations, discard arbitrary program output or force a rerun
  to recover context.
- The canonical formatter, one-definition/qualified-name rules and generated cards
  remain the source-density baseline. E2 may propose a syntax/API spelling change only
  when both supported model families improve total tokens or repair turns on held-out
  semantically equivalent tasks with no worse completion, safety, first-pass check,
  defect escape or unrelated diff. Adoption is outside T2/E2 and requires a separate
  versioned language/API milestone, normative amendments, compatibility analysis and
  migration evidence. Character or lexer-token count alone is rejected.
- Reports include model familiarity effects: hallucinated constructs, requests for
  nonexistent APIs, compiler-learning turns and Python-prototype/translation detours.
  A novel-language penalty is measured rather than explained away.

Acceptance: reproduce every component from archived traces and content-addressed
artifacts. On eligible held-out tasks, Neper must rank first or be statistically tied
for first on source-token pressure and total interaction tokens per verified success
among the registered Go, Rust, TypeScript and Python agent-tooling cohort. No win may depend on missing setup prompts,
hidden tool schemas, discarded failures, unavailable full evidence or weaker oracles.

### H34 — integrated agent workflow and comparative overall fit

**T2.3 reference-host delivery; E2 comparative closure: one discoverable, versioned workflow over the compiler product.**

- `neper info` advertises the supported agent workflow, schemas, check scopes,
  diagnostic/test projections, result-reference lifetime, edit operations, limits and
  optional retained-session capability. A harness uses no undocumented command,
  parser, sidecar linter, formatter, test normalizer or repository-specific adapter.
- Context, plan/apply, format, check, test and build share H15 snapshot identity,
  H08 semantic facts, H17/H29 edit operations, H31 diagnostics, H32 test evidence and
  H18 status vocabulary. The formatter is canonical and all validation after an edit
  refers to the returned new snapshot.
- A final verification record names requested obligations, scopes, executed/cached
  checks and tests, counts, omissions, skipped/unproved obligations, result references
  and exactly one state: `verified`, `failed`, `incomplete` or `cancelled`. Before
  `neper-agent-host` supplies H36/H37 enforcement and H40 coverage, the strongest
  legal state is `incomplete`. `verified`
  means every requested obligation completed for that exact snapshot with no omitted
  failure and no unproved required item. Once H35–H37 apply it also names the exact
  change-contract, policy and environment identities. The state is shorthand for
  "verified for those named obligations and conditions", never a claim of arbitrary
  semantic correctness.
- A terminal result can be persisted as a canonical, content-addressed verification
  receipt. Its deterministic proof core binds the snapshot; compiler, language,
  grammar, stream, target, profile and options; requested obligations; executed or
  exactly cached evidence and hashes; unsafe inventory; omissions; skipped/unproved
  items; and terminal state. A read-only verifier checks the receipt and referenced
  evidence without rerunning work. Timing/timestamps stay outside the proof core, and
  subjective confidence, self-declared authorship or review are never evidence.
- The reference agent loop is: snapshot, bounded context, transactional edit,
  format, affected check, root-cause repair, affected tests, required wider tier,
  verification. A harness stops editing on `verified` unless the user supplies a new
  obligation. Continuing to polish a verified snapshot is recorded as an over-edit.
- Finite CLI, batch and retained transports are interchangeable projections of the
  same operations. Full logs/results survive compaction for their advertised lifetime;
  session loss cannot erase the canonical result artifacts already promised.

Acceptance: an implementation-independent harness discovers and completes the loop
from `info`, including restart after compact output and result retrieval, with no text
scraping. Receipt fixtures cover altered source, tool/profile mismatch, missing or
modified evidence, cached evidence, unsafe inventory changes and every terminal state;
only an intact fully evidenced receipt validates as `verified`. In the H12 held-out
evaluation, Neper must be first or statistically tied among the registered
agent-tooling cohort in each of the four reported categories: check latency,
diagnostic repair, structured testing and source/token pressure. Across both model
families it must
strictly improve the pre-registered composite of wall time and total model tokens per
verified success over the best eligible reference, while not increasing escaped
defects, false acceptance, unsafe/check-suppression edits or incomplete results. If a
category does not meet that bar, Neper may report its measured position but may not
claim the best LLM coding experience among that cohort or close the E2 comparative
record for H34. The T2.3 functional H34 record remains governed by workflow
conformance, not the ranking.

## 32. H35–H44 — operationally trustworthy agent execution

Added 2026-09-18 by the operational gap audit. These are T2 tooling/host obligations,
not source-language features. They extend H34 so `verified` means that the requested
change was checked under known authority and environment, not merely that some
compiler and test commands happened to pass.

The reference implementation is the planned in-repository `neper-agent-host`
executable under `tools/neper-agent-host/`. T2.2 artifacts remain portable protocol
objects, but only this host or an independently conforming replacement may enforce
H36/H37/H40 and promote an otherwise complete result to `verified`. H38/H44 extend
the same host in T2.4; they are not compiler-core responsibilities.

### H35 — external change contract

**T2 tool-service delivery: bind verification to a machine-readable request outside source.**

- Define a canonical, content-addressed `neper-change-contract` with its base
  snapshot, descriptive objective and provenance, permitted source/artifact scope,
  forbidden changes/effects, executable acceptance obligations and required
  verification tier. Descriptive prose remains inert and is never treated as proof.
- Each obligation has a stable ID, kind, exact expected outcome and disposition:
  required or advisory. Unsupported, ambiguous or non-executable required criteria
  remain unproved and force `incomplete`; they cannot be silently converted into a
  passing test.
- Plans, task handles, change bundles and the final receipt bind the exact contract
  hash. Contract amendment creates a new identity and records the predecessor; it
  never rewrites the meaning of existing evidence.

Acceptance: altered base, scope, expected outcome or required tier invalidates old
evidence; advisory prose cannot create a verified claim; an unimplemented required
criterion produces `incomplete`; and the same canonical contract hashes identically
on Windows and Linux.

### H36 — enforced action policy and audit

**T2 trusted-host delivery: enforce H31 effects independently of the proposing agent.**

- A versioned policy selected by the invoker maps effect kind and scope to `allow`,
  `deny` or `approval_required`. Network, credentials, dependency changes, project
  execution, VCS mutation, external services and outside-workspace writes default to
  denied unless the invocation grants them explicitly.
- The trusted executor validates argument vectors, working directory, resolved paths,
  capabilities and approval tokens, then uses available OS sandboxing or mediation to
  constrain actual effects. A declaration from an untrusted plan is a request, not an
  enforcement boundary. If an effect cannot be constrained or observed, policy says
  so and fails closed whenever the contract requires enforcement.
- Results distinguish declared, granted, denied and observed effects. The receipt
  binds the policy hash and grant/denial evidence without storing credential values.
  Secret-bearing inputs are redacted from diagnostics, logs and stored artifacts.

Acceptance: planted undeclared writes, process launches, network use and path escapes
are blocked or make the result non-verified; stale, replayed or wrong-scope approvals
fail; denial is structured; and no secret fixture appears in output or artifacts.

### H37 — hermetic environment identity and replay

**T2 trusted-host delivery: make ambient execution inputs explicit.**

- Checks, builds, runs, tests and benchmarks emit an environment manifest covering
  executable/tool hashes, OS/architecture, dependency lock, mounted/readable/writable
  roots, inherited environment allowlist, locale/timezone, clock/random policy,
  network policy, resource limits and declared external services. Secrets are named
  by opaque identity or value hash, never persisted as plaintext.
- Each operation reports `hermetic`, `observed` or `uncontrolled` with explicit
  omissions. Every relevant input participates in cache identity and receipt evidence;
  a contract that requires hermetic execution cannot verify from an observed or
  uncontrolled run.
- Provide a replay description that reconstructs declared inputs or reports exactly
  which unavailable input prevents replay. Host observation is kept separate from
  the deterministic proof core where it cannot be canonicalized.

Acceptance: perturb locale, timezone, environment, executable, lockfile, random seed,
clock/network policy and mounted input independently; each either changes identity or
is proven irrelevant. An undeclared dependency cannot produce a hermetic result.

### H38 — parallel-agent change bundles and integration

**T2 trusted-host delivery: compose isolated verified changes without composing their claims.**

- Export a content-addressed change bundle containing base/result snapshots, typed
  edits and preconditions, changed semantic identities, declared/observed effects,
  change-contract hash and verification receipt. A worktree is one possible storage
  isolation mechanism, never an execution sandbox.
- Integration checks byte overlap plus semantic conflicts in declarations, imports,
  call/effect/ownership contracts, generated inputs, tests, public API/ABI and build
  configuration. Results are `clean`, `conflict`, `incomplete` or `stale` with
  structured causes and candidate re-planning operations; no name-based blind merge.
- Combining bundles creates a new snapshot. Source, affected checks/tests and all
  invalidated obligations are rerun or exactly reused under H34; independent receipts
  never imply that the combined snapshot is verified.

Acceptance: cover same-byte conflicts, text-disjoint semantic conflicts, compatible
same-file edits, changed dependencies, generated sources, stale bases and bundles
from different policies/environments. Only the verified integrated snapshot may
receive a new receipt.

### H39 — flaky and nondeterministic test semantics

**T2 tool-service delivery: make retries evidence rather than a pass filter.**

- Add a distinct `flaky` outcome. Each attempt records identity, seed, order/shard,
  environment, outcome and evidence; configured retries never overwrite earlier
  failures or convert the aggregate into an ordinary pass.
- Quarantine is explicit policy with owner/reason/expiry. A flaky or quarantined
  required obligation is skipped or unproved and prevents `verified`; cached success
  cannot hide contradictory attempts or cross an incompatible seed/environment key.
- Provide deterministic replay where the test declares control of randomness and
  scheduling. Otherwise report the uncontrolled source rather than claiming a
  reproducible failure.

Acceptance: alternating pass/fail, order dependence, timeout, crash, stale quarantine,
cached contradiction and seed/environment mismatch retain all attempts and cannot
produce an unqualified verified receipt.

### H40 — verification-adequacy coverage

**T2 tool-service delivery: relate requested and inferred risks to evidence.**

- Build an obligation graph from H35 acceptance items, changed semantic/public
  identities, safety/effect changes and required compatibility/performance policy.
  Each obligation is `covered`, `uncovered`, `inapplicable` or `unknown`, with the
  exact check/test/property/benchmark evidence and provenance supporting that state.
- H32 selection completeness and H40 adequacy are distinct: running every selected
  test does not prove that a required behavior has an oracle. Coverage, property,
  fuzz and mutation results may contribute evidence but never become universal proof
  outside their measured scope.
- `verified` requires every required obligation to be covered by accepted evidence.
  User waivers are explicit, scoped, hashed policy inputs and remain visible as
  skipped/unproved rather than being relabeled as coverage.

Acceptance: planted untested requirements, deleted assertions, unknown external
behavior, irrelevant coverage and waived obligations cannot appear covered; adding a
valid oracle closes only its matching obligation.

### H41 — structured runtime failures

**T2 tool-service delivery: normalize program execution with bounded recoverable evidence.**

- A run result distinguishes setup/build failure, returned application error,
  language trap, signal/exception, abnormal exit, timeout, resource limit,
  cancellation and success. It records the exact invocation/environment identities,
  exit data and resource observations available on the host.
- Runtime failures carry a deterministic failure identity where possible and bounded
  source-mapped frames with physical/generated origins. Large/binary stdout, stderr,
  dumps and traces use H31 result references; human text is a rendering, not the
  machine discriminator.
- Redaction and H36 policy apply before evidence persistence. Missing symbols or
  truncated frames are explicit, not an empty successful trace.

Acceptance: returned error, trap, access fault, signal/exception, timeout, memory/CPU
limit, output flood, missing symbols and generated frames all produce schema-valid,
bounded and retrievable results without terminal-text parsing.

### H42 — public API and ABI compatibility diff

**T2 tool-service delivery: make compatibility a first-class comparison.**

- Compare two snapshot/interface artifacts by target/profile and classify source,
  binary/ABI, behavioral-contract and serialization/schema compatibility separately.
  Report additions, removals and changes by semantic identity with affected consumers
  and `compatible`, `breaking`, `unknown` or `not_applicable` status.
- Never infer behavioral compatibility solely from equal types or an empty internal
  use graph. Caller-supplied version/release policy determines whether a classified
  change is allowed.
- Produce H29 migration plans where a complete mechanical migration exists; otherwise
  return review requirements and unknown/external consumers without fabricated edits.

Acceptance: signature, layout/calling convention, error/ownership/effect contract,
generic/protocol, serialized field and target-dependent changes are independently
classified; incomplete external-consumer knowledge cannot yield a safe claim.

### H43 — performance-regression obligations

**E2 claim-gate delivery: allow performance to be a verified task requirement.**

- H35 may name benchmark obligations with a baseline snapshot/artifact, workload and
  data hashes, environment requirements, metric/direction, threshold, repetitions,
  warmup and pre-registered statistical decision. Results are `pass`, `regression`,
  `inconclusive` or `invalid`; an isolated best run is never the decision statistic.
- Bind raw observations, distribution summaries, noise controls and H37 environment
  to result artifacts and the receipt. A changed workload, baseline, instrumentation
  or environment invalidates reuse.
- Functional verification and performance verification remain separate obligations;
  neither can hide failure of the other.

Acceptance: known regression, noisy/inconclusive data, changed baseline, thermal or
background disturbance and cherry-picked samples cannot produce a performance pass.

### H44 — durable asynchronous operation lifecycle

**T2 trusted-host delivery: support bounded long work and approval waits without a live stream.**

- Long checks/tests/builds/benchmarks may return an unguessable, authorized task
  handle with queued, running, `input_required`, cancelling and terminal status.
  Clients can read, supply structured approval/input and request cancellation; task
  enumeration is not required and possession alone grants no broader authority.
- State and canonical result artifacts survive disconnect and service restart for an
  advertised lifetime. Progress is ordered but noncanonical; the terminal result is
  exactly the same H34 result obtainable synchronously. Cancellation is cooperative
  and never rewrites work that already reached a terminal state.
- Inputs and approvals bind task, operation, policy, scope and expiry. Retention and
  reclamation follow H16; late or duplicate updates are idempotent or rejected
  explicitly.

Acceptance: disconnect/reconnect, restart, concurrent polling, structured approval,
wrong caller, guessed/replayed handle, expiry, cancel races and result retrieval all
preserve authorization, status monotonicity and one canonical terminal result.

## 33. H45 — release provenance bridge

**Later delivery, scheduled with M6 package/release work: export Neper evidence into
standards-based source and build provenance.** This does not block M3 because the
post-M2 tracks have no complete package publication boundary.

- Export the unchanged H34 receipt, H35 contract, H37 environment identity,
  dependency lock and produced artifact digests into a versioned provenance envelope
  compatible with the selected release ecosystem. The export may reference, but may
  not reinterpret or strengthen, native evidence.
- Signing, builder/source identity, key isolation, trust policy, revocation and
  distribution are explicit platform responsibilities. Unsigned local provenance is
  useful traceability, not authenticated proof; self-reported model confidence or
  authorship is never substituted for an attested identity.
- Verification is monotonic: deleting or ignoring an extension cannot change deny to
  allow, and missing/untrusted provenance produces unknown or rejection under the
  consumer's policy.

Acceptance: validate against the selected external schema and independent verifier;
cover altered source, dependency, builder, artifact, receipt and signature; reproduce
the native evidence link; and reject any export that claims a stronger property than
its inputs establish.
