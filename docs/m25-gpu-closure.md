# M2.5-core GPU design closure: H13, H21, H22 and H23

This is the design-only closure record for the four GPU requirements that block M3.
It freezes contracts and a machine-checkable fixture manifest; it does not claim that
the CPU or Vulkan GPU runtime exists. Runtime evidence remains pending in M3, and PTX
evidence remains pending in M4.

The normative prose is `spec.md` sections 10–12 and the planned `e.gpu` fence in
`module-apis.md`. `m25-gpu-contracts.md` explains the design. The exact matrices and
32 fixture obligations are `m25-gpu-contracts.json`, checked by
`scripts/check_gpu_contracts.py`.

## H13 — CPU/device safety mapping

### Selected design

A device is a region, a queue is an in-order stream inside it, and a buffer is owned
storage of that region. Host transfers retain the synchronous copy/wait boundary.
Retained device checks write one typed `FaultRecord`; `gpu.Fault` reports it at the
next synchronizing operation. The manifest maps H01–H07 in order and freezes every
debug/release/unchecked check disposition.

### Alternatives

Implicit host-pointer lifetime tracking, device-wide aborts, silent removal of
unsupported checks, and treating CPU poisoning as device-race proof were rejected.
They either create an uncheckable cross-boundary borrow or overstate runtime evidence.

### Normative changes

The `e.gpu` fence adds `FaultKind`, `FaultRecord` and `Fault`; the existing H03
checked-release policy applies to device bounds, null, tag and alignment checks.

### Implementation and tests

D660 adds the exact ABI and validates three named fault fixtures. Their execution is
owned by M3 and remains `pending_m3` in the manifest.

### Compatibility

The surface is planned and unimplemented, so this freezes rather than migrates an
ABI. No emitted artifact format or delivered callable API changes in M2.5-core.

### Measurements

This slice adds documentation and validators only. It performs no device work and
therefore supplies no runtime or performance measurement.

### Remaining limitations

The fault buffer, source-site lookup, CPU emulator and Vulkan implementation are M3.
CUDA/PTX execution is M4. A barrier hang remains detectable only by CPU emulation.

## H21 — completion, dependencies and resource state

### Selected design

`Token { owner, queue, serial }` names already-submitted work. `wait_for` can therefore
order only future work behind past work, making a dependency cycle inexpressible.
Whole-buffer use tracking is the conservative first implementation; release waits for
uses on every queue. Discovery remains explicit and exact-key selection never falls
back.

### Alternatives

Future-work promises, implicit cross-queue ordering, range tracking in the first
runtime, transparent cancellation, and automatic device substitution were rejected.

### Normative changes

The planned API adds `Token`, `token`, `wait_for`, `done` and `wait`. State/error
tables cover completion, faults, loss, stale tokens, wrong devices and partial chains.

### Implementation and tests

D661 freezes the API, state machine and twelve dependency/discovery fixtures. The
validator proves that the exact fixture set and past-only states remain present.

### Compatibility

The additions are to the unimplemented M3 surface. Existing `sync` and synchronous
`download` stay available; tokens add composition without changing their meaning.

### Measurements

The design budgets two token comparisons and two stored token values per buffer slot.
Runtime cost and overlap measurements remain M3 evidence.

### Remaining limitations

The first runtime does not detect unordered cross-queue races, track sub-buffer
ranges, cancel submissions or synchronize across devices.

## H22 — cost, staging and artifact lifecycle

### Selected design

A versioned timeline keeps host/device clocks separate, a pipeline-cache key includes
every code-affecting input, and each queue owns a fixed staging pool that waits rather
than grows. `queue_with` exposes its limits; `queue` selects four 16 MiB blocks.

### Alternatives

Unbounded staging, summing unrelated clocks, trusting driver blobs, implicit pinned
borrows, batching, reusable graphs and an optimized CPU fallback were rejected from
the M3 baseline or deferred to separately justified work.

### Normative changes

The planned API adds `StagingLimits` and `queue_with`. The manifest freezes twelve
timeline fields, nine phases, ten cache-key components, staging failure behavior and
the M3/deferred feature split.

### Implementation and tests

D662 validates the schema and five cold/warm, bounded-pool and corrupt-cache fixtures.
Every fixture remains pending until the M3 runtime emits and checks its records.

### Compatibility

Default `queue` behavior is preserved and specified by the new explicit limits. No
delivered cache format or command-line schema changes before M3 advertises them.

### Measurements

The fixed default is four blocks × 16 MiB per queue. The timeline reports its own
instrumentation overhead; cold/warm latency distributions are M3/H25 evidence.

### Remaining limitations

Pinned transfers, batched submission, execution graphs and an optimized CPU backend
have no implementation commitment in this closure.

## H23 — numerical and capability behavior

### Selected design

The matrix states exactness or a bound per operation and backend. Subgroup equivalence
requires matching width/mapping or subgroup independence. Non-FTZ kernels require
`DenormPreserve`; absence is `Unsupported`, never silent flushing.

### Alternatives

Blanket bit-identity, assuming desktop denormal behavior, native-opcode exactness and
a global fast-math switch were rejected because each contradicts a backend condition.

### Normative changes

Spec sections 10–11 retain D367's subgroup and denormal corrections. The frozen JSON
matrix has 21 rows and requires CPU/SPIR-V/PTX behavior, result oracle, exceptional
inputs, width/layout, capabilities, subgroup dependence and nondeterminism per row.

### Implementation and tests

D663 validates the matrix, six launch-precondition classes and twelve numerical/
capability fixtures. CPU/Vulkan execution is M3; PTX execution is M4.

### Compatibility

The correction narrows earlier overbroad future claims before an implementation can
depend on them. It introduces no delivered CPU semantic or artifact-format change.

### Measurements

Exact rows require bit identity under their stated preconditions. Transcendentals and
`rsqrt` carry the stated 2-ULP bound; subgroup float reductions carry their explicit
rounding bound. No device measurements are claimed here.

### Remaining limitations

Hardware modes, refusal paths, reduction bounds and device behavior remain runtime
evidence pending. The CPU emulator is an oracle only for the cases it executes.

## Verification evidence

The focused contract suite has six passing tests; the validator reports four closed
design contracts and 32 pending fixtures, and the module-plan checker accepts all 150
modules and the expanded `e.gpu` fence. The complete Windows and Linux self-host
suites pass at D664, including compiler-resolved API surfaces, metamorphic and
differential checks, stream validation, fixed-point/determinism and structured-edit
coverage. Each static gate judges four cells with zero breaches: Windows remains
2,285/2,990 MB arena high-water and 2,982,400/2,081,792-byte images in debug/release;
Linux remains 2,283/2,989 MB and 2,980,096/2,079,472 bytes. These prove that freezing
the contracts did not perturb delivered CPU compiler artifacts; they are not GPU
runtime measurements.

## Closure decision

H13, H21, H22 and H23 are closed for the M2.5-core **design** scope. D660–D664 supply
the frozen API, schemas, machine-checkable matrices, fixture manifest and closure
record. M3 must implement those contracts and replace each `pending_m3` fixture with
real CPU/Vulkan evidence; none is counted as a passing runtime test by this closure.
