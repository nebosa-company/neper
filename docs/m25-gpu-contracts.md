# M2.5-core design: H13, H21, H22, H23 -- GPU contracts frozen before M3

This is the design-only closure [`post-m2-llm-hardening.md`](post-m2-llm-hardening.md)
sections 16, 24, 25 and 26 ask for: how the CPU contracts of H01-H07 map onto
devices, how host and device work compose, what an end-to-end launch costs and how
its artifacts are cached, and which numerical claims of spec §10 and §11 survive
review. Nothing here is a passing GPU runtime test. Every fixture named below is
**runtime evidence pending**: it is written against the CPU backend
(`gpu.open(a, .Cpu, 0)`) and a device in M3. The M2.5-core rows measure the
frozen design obligation, never runtime delivery. The spec's `e.gpu` surface (§10, Host side; D37, D38, D39,
D45, D83) is the base; where this document corrects the spec, the section says so
and the spec was edited in the same commit (D367).

The one shape under everything: **a device is a region, a queue is an in-order
stream inside it, a buffer is storage of the region, and the host's only
asynchronous accesses to host memory are the ones it has already finished.**
`upload` and `write` copy their source before returning; `download` waits before
it writes. So a host lexical scope never has to know what the device is doing to
its own storage -- the spec's synchronous-upload rule (§10, Queues) is what makes
H01 and H02 hold across the boundary without a lifetime the checker cannot see.
Everything that would break that (a pinned asynchronous transfer, H22) is a
separate delivery with its own obligation.

## 1. H13 -- the CPU/device mapping of H01-H07

### 1.1 Ownership and liveness (H01)

| Value | Kind under H01 | Obligation | Consumed by | Error after |
|---|---|---|---|---|
| `*gpu.Device` from `open`/`open_id` | resource, `closer = gpu.close` | closed on every exit of the owning block | `gpu.close(dev)` | `InvalidHandle` |
| `*gpu.Queue` from `queue` | view of its device (§1.2); no closer | none -- `close` destroys every queue | `gpu.close` of the device | `InvalidHandle` |
| `gpu.Buf[T]` from `alloc`/`upload` | resource, `closer = gpu.release` | released on every exit, on **any queue of its device** | `gpu.release(q, b)` | `InvalidHandle` |
| a launch, a write, a release | a submission (§2); not a value | none on the host: the queue orders it | completion | -- |

`Buf[T]` is the one resource whose closer takes a second argument. H01's
`resource(closer)` accepts a closer whose **last** parameter is the `own` one
(D613), and the checker
consumes on the call regardless of the queue argument -- the queue is a view of the
same device or the call is `WrongDevice` at runtime, which the checker does not
model. The `defer let _ = gpu.release(q, dx)` idiom of §10 is the ordinary shape;
under H01 it is the release at every exit, and a `Buf` that is bound and never
released is `E-SAFETY-0002` naming `gpu.release`, exactly as an `os.File` is.

A `Buf[T]` is copied by the language (its fields are public, D83); the copies are
one logical handle, and `release` consumes them all: under H01 the *local* is
affine -- a second local bound from the same handle is E-SAFETY-0001 on the
second use after the release, and a copy stored into an aggregate is outside the
rule, as every field is (`m25-h01-ownership.md` §15). `gpu.len(b)` is a read, not
a use of the obligation.

**What a host scope may not release.** The arena `a` given to `open` holds the
device's bookkeeping block until `close`; on `.Cpu` it holds every `Buf`'s storage
too. Under H02 the `*Device` is therefore a **view of `a`** (§1.2): a
`mem.reset(&a)` while the device is open is E-SAFETY-0013 with the open as the
related span, and `close` before the reset is the fix. No other host storage is
reachable from an outstanding submission: `upload`/`write` have copied `src` when
they return and `download` has finished writing `dst` -- so a `[]T` handed to any
of them carries no obligation past the call, and H05's snapshot rule does not
apply (the copy is the operation, listed in §6).

**Transitions.**

| Device | on | to | note |
|---|---|---|---|
| Open | `close` | Closing | acquires the device lock, rejects new fallible calls (`InvalidHandle`), `has` answers `false` |
| Closing | every queue drained, buffers and queues released | Closed | the bookkeeping block is `a`'s again; `close` returns |
| Open, Closing | driver reset, irrecoverable submit/wait/transfer | Lost | every later fallible call returns `Lost`; `close` still completes and returns `Lost` |
| Closed | any call | -- | `InvalidHandle`; a second `close` too |

| Buffer | on | to | note |
|---|---|---|---|
| Allocated (contents unspecified) | `write`/`upload` | Written | in submission order of the queue used |
| Allocated, Written | `release(q, b)` | Releasing | the handle is consumed now; the memory waits for every outstanding use (§2.2) |
| Releasing | the last outstanding use completes | Released | the slot's generation advances; a stale copy is `InvalidHandle` |
| any | device Lost | Lost | `release` returns `Lost` and still consumes the handle -- the obligation is met, the memory is the driver's problem |

`release` on a lost device consuming the handle is the rule H07 needs: a cleanup
that fails still discharges the obligation (D360), and the detail is the driver's
result code, recorded through `record_cleanup_error_detail` as the os closers do.

### 1.2 Regions and views (H02)

| Region | View of it | Dangles at |
|---|---|---|
| the arena `a` of `open` | the `*Device` | `mem.reset(&a)` (E-SAFETY-0013) |
| the `*Device` | every `*Queue` of it; on `.Cpu`, every `Buf` (its storage is `a`'s) | `gpu.close(dev)` -- a use of the queue after it, visible in the same function, is E-SAFETY-0013 with the close as the related span; outside the function it is `InvalidHandle` at runtime |
| the `*Queue` | nothing: a submission is not a value | -- |
| a `Buf[T]` | nothing on the host: device memory has no host view | -- |

Which forms are legal per profile:

| Form | host | kernel (device build) | kernel (CPU build) |
|---|---|---|---|
| `resource` values, `own` parameters, closers | yes | **no** -- a kernel returns nothing and owns nothing; a `resource` type in a kernel signature or a device helper is a compile error naming the type (`E-GPU-0003`) | erased with the kernel: the CPU build of a kernel is the same function |
| `mem.Arena`, regions, views | yes | no: no allocation on the device (§10, "Nothing crosses the boundary implicitly") | no |
| `[]T`, `[]const T` into device memory | never: a host slice is not device memory | yes, from a `Buf` through the argument block | yes, over the `Buf`'s arena storage |
| `[]shared T`, `shared var` | never | yes | yes, over the workgroup frame |
| private (`&x` on a local) | yes | no (§10 Restrictions) | as the device: the restriction is checked once, on the shared source |

The four memory domains -- host, device, workgroup, subgroup -- are therefore
type-visible on the device side (`[]T` / `[]shared T` / register-only) and
absent from the host (`Buf[T]` is a handle, never a slice). H08's context records
say which (§1.7).

### 1.3 Checks and traps on the device (H03)

Spec §10 said "the device carries no checks". H13 forbids removing a check
silently, and H03's release policy keeps bounds, null, tag and alignment checks
in release CPU code (D355). The mapping:

| Check (§11) | CPU debug | CPU release | device debug | device release | `--unchecked` |
|---|---|---|---|---|---|
| bounds, tag, alignment | trap | trap | **fault record** | **fault record** | none |
| null | trap | trap | fault record (a device pointer is never null through the argument block; a null check reaches a kernel only through a helper's `*T`) | fault record | none |
| integer overflow, integer divide by zero | trap | none | fault record | none | none |
| `barrier` divergence | trap | none | -- (a hang; the CPU build is where it is found) | -- | -- |
| `invalid` (stale `Buf` through `len`) | trap | trap | n/a (host-side) | n/a | none |

A **fault record** is the device's trap. Its frozen public shape is
`FaultRecord { kernel: u32, kind: FaultKind, site: u32, gid: Id }`, where
`FaultKind` is `Bounds`, `Null`, `Tag`, `Alignment`, `Overflow` or
`DivideByZero`; `gpu.Fault` is the associated error. SPIR-V and PTX have no trap that reaches
the host, so a failing check writes one record -- `{ kernel: u32, kind: u8, site:
u32, gid: Id }` -- into a per-queue **fault buffer** with a device atomic
compare-and-swap on its `count` (the first writer wins; later faults only count),
then **returns from the invocation**. The fault buffer's device address is one
more slot in every kernel's argument block, written by `launch`; `@nocheck`
blocks and `--unchecked` builds carry no checks and no slot. The queue reports it:
the next `gpu.sync(q)` or `gpu.download(q, ...)` returns **`gpu.Fault`** (a new
error, D367) with the record as the error detail -- kernel, kind, site as
`file:line:col`, invocation -- and the queue keeps accepting work: a fault is the
kernel's failure, not the device's. Termination is per invocation, not per grid:
the other invocations finish, their results are what a returned invocation left
them, and the program that reads them without checking `sync` has the silent wrong
answer the fault exists to prevent -- which is why `download` also reports it.

The cost is one `u64` per argument block and, per checked operation, the same
compare the CPU pays plus a branch to the fault path; a bounds check the BCE
proof of D355 elides on the CPU is elided on the device too, since the proof is
lowering's and the kernel is lowered once. The fault buffer is not H21's token; a
token completing says the work ran, `Fault` says what it found.

Fixtures: `gpu_fault_bounds` (a kernel indexing past `xs.len`; `sync` returns
`Fault` naming the site and invocation on the CPU backend and on a device),
`gpu_fault_unchecked` (the same under `--unchecked`: no fault, unspecified
result, the manifest's `options.checks` says `off`), `gpu_fault_nocheck` (the
same in a `@nocheck` block, listed in the manifest's `unsafe` array with
`kind: "nocheck"`).

### 1.4 Concurrency (H04)

| Contract | host side | device side |
|---|---|---|
| a `*Device` | usable from any thread (its own lock) | -- |
| a `*Queue` | one thread at a time; a thread given `&q` in its context holds it until the join under D365's lending, once the lending covers pointer locals (`m25-h04-concurrency.md` §5) -- until then D14 UB, as the spec says | -- |
| a `Buf[T]` | belongs to the device; any queue | two queues touching one buffer without a token wait (§2) between them race, undefined under D14; the runtime does not detect it |
| atomics | `e.atomic` on host memory, never on device memory | `gpu.atomic_*` with scope `.Workgroup` or `.Device`, `AcquireRelease` order (D37); never on host memory |
| barriers | none | `gpu.barrier()` uniform, workgroup scope; `gpu.memory_barrier(scope)` |
| host/device visibility | what `sync`, `download` and a completed token (§2.1) give: everything submitted before is visible after | nothing the device writes is visible to the host until one of those |

Barrier uniformity stays a CPU-build trap and a device hang; the fault buffer
cannot report a hang. The CPU build's poisoned `shared` bytes and its divergence
trap are evidence for the invocations a test runs, not proof of race freedom
(H13, H23), and the readiness rows say so.

### 1.5 By-value arguments (H05)

The argument block is built at the `launch` call: every by-value parameter is a
copy taken **at the call**, before the launch is queued, so a host mutation after
the call cannot reach the kernel -- H05's snapshot rule (D356) holds by
construction and the copy is on the page as §10's argument table. `Buf[T]` is a
value handle copied likewise. A slice parameter is the `{ address, len }` pair
copied at the call; what it points at is device memory, which the queue orders.

### 1.6 Specialisation and provenance (H06)

A kernel is monomorphised per launch site's `K` and per device target; a helper
generic over the slice type (`fn sum[S: type](xs: S)`) is instantiated once per
address space. Every instance is an H06 explain record (`explain-file`, kind 2)
whose subject carries a `profile` -- `"cpu"`, `"spv"` or `"ptx"` -- and the
`.spv.em`/`.ptx.em` Interface entry of the kernel records, beside the inferred
capability set, each reached helper's source identity and its specialisation
arguments, so a device diagnostic (`Fault`'s site, a capability refusal's call
chain) names the source line of the helper, not the kernel it was inlined into.
This is the identity extension §3.2's cache-key matrix relies on.

### 1.7 Context records (H08) and diagnosis (H09)

`context-file --symbol module.kernel` adds, for a kernel or a device-only helper:

| fact | value |
|---|---|
| `profile` | `"kernel"` or `"device-helper"`; a plain reached helper is `"both"` |
| `workgroup` | `[x, y, z]` |
| `capabilities` | the inferred set, e.g. `["Int64", "Subgroup"]`; `caps_bound` when `caps(...)` is given |
| `parameters[i].space` | `"device"`, `"shared"`, `"value"` |
| `checks` | `"retained"`, `"off"` (`--unchecked`), or `"nocheck"` per block, as the manifest's `options.checks` |

The `E-GPU` codes this design names, each two-site with a related span (D364):

| code | violation | sites |
|---|---|---|
| `E-GPU-0001` | a launch argument's type or address space does not match the kernel's parameter | the argument, the parameter |
| `E-GPU-0002` | an inferred capability outside the kernel's `caps(...)` bound | the use, the kernel (with the call chain in the note) |
| `E-GPU-0003` | a `resource`, `own`, arena or host-only type in a kernel or device helper signature | the type, the kernel |
| `E-GPU-0004` | a device-only helper called from CPU code | the call, the helper's first `gpu.*` use |
| `E-GPU-0005` | a `Buf[T]` element type that is not device storage | the `Buf` type, the offending element type |

Runtime errors (`Unsupported`, `TooLarge`, `WrongDevice`, `InvalidHandle`,
`Lost`, `Fault`) carry their detail through H07's slot: the kernel and capability
for `Unsupported`, the driver code for `Lost`, the fault record for `Fault`.

## 2. H21 -- explicit CPU/GPU dependency composition

### 2.1 Tokens

A **token** names one submission on one queue:

```
type Token = struct { owner: u32, queue: u32, serial: u64 }
fn token(q: *Queue) -> (Token, err)             // the last submission on q; serial 0 when none
fn wait_for(q: *Queue, dependency: Token) -> err // device-side: later submissions on q run after it completes
fn done(token_value: Token) -> (bool, err)       // host poll, no blocking
fn wait(token_value: Token) -> err               // host wait for it alone, not the whole queue
```

These declarations are now the exact planned `e.gpu` API fence rather than prose
shorthand; `docs/m25-gpu-contracts.json` mirrors the state and fixture contracts.

`serial` counts submissions on `queue` from 1; a token is therefore always in the
past of its queue, and **a dependency graph over tokens cannot contain a cycle**:
`wait_for` can only name work that was already submitted. That is the rejection
policy for cycles -- there is nothing to reject, and the compiler proves nothing
dynamic (H21's "cannot be claimed statically deadlock-free" is met by having no
claim to make). Two queues that each wait for the other's *future* work cannot be
expressed.

| Token | on | to | `done` | `wait`/`wait_for` |
|---|---|---|---|---|
| Queued | the device starts it | Running | `false` | block / order behind |
| Running | the last invocation finishes and its writes are visible at device scope | Complete | `true` | return `ok` |
| Queued, Running | a fault record is written | Complete (the token completes; `Fault` is the queue's, §1.3) | `true` | `ok`; the next `sync`/`download` on the queue is `Fault` |
| Queued, Running | driver reset | Lost | `Lost` | `Lost` |
| any | its queue destroyed by `close` | Stale | `InvalidHandle` | `InvalidHandle` |
| any | given to a queue of another device | -- | -- | `WrongDevice` |

**What a completed token covers:** every submission on its queue with a serial at
most its own, and the visibility of their writes to device memory at `.Device`
scope -- so a second queue that `wait_for`s it reads them -- and, for a host
`wait`, to the host, so a `download` after `wait(t)` needs no further sync (it
still performs one, as the spec fixes; it costs nothing when the queue is
drained). A token says nothing about later submissions on its queue.

`gpu.sync(q)` is `wait(token(q))`; `gpu.download` is an **implicit
synchronisation** and is reported as one: `--stats` gains a row `gpu implicit
syncs`, and the timeline record (§3.1) marks the sync `implicit: true`. A whole-queue
wait stays available and is not the only dependency, which is the H21 ask.

### 2.2 Buffer uses, overlap and release

| Use | read/write | range | tracked as |
|---|---|---|---|
| `write(q, dst, off, src)` | write | `dst[off .. off+src.len]` | whole buffer |
| `launch` with `[]const T` | read | whole | whole buffer |
| `launch` with `[]T` or `[]Atomic[T]` | write | whole | whole buffer |
| `download(q, src, dst)` | read | whole | whole buffer |
| `release(q, b)` | -- | -- | waits for every tracked use |

**Conservative whole-buffer tracking is the first implementation**, and its cost
and restriction are these: per `Buf` slot the runtime keeps `last_write: Token`
and `last_read: Token` (the latest across queues). `release(q, b)` enqueues on
`q` a `wait_for` on both before the free, so the memory waits for every
outstanding use **on every queue**, not only the release queue -- 16 bytes per
slot and two compares per submission. Two range writes to disjoint halves of one
buffer from two queues are serialised by nobody and race by nobody either; they
are legal on the device and *reported as overlapping by this tracking only if
they are on one queue*, which orders them anyway. Range-level tracking is a later
delivery; nothing in the token contract changes for it.

What the runtime does **not** do: order two queues' accesses to one buffer. A
write on `q1` and a read on `q2` without `wait_for(q2, token(q1))` between them
is the race §10 already calls undefined under D14. The fixture pair
`gpu_two_queues_ordered` / `gpu_two_queues_race` is the positive and the negative:
the first downloads what the second queue computed after a token wait, the second
is refused by nothing and is *observed* -- the CPU backend runs queues in order on
one thread and cannot show the race, which is exactly why it is runtime evidence
pending on a device, and the readiness row says so.

### 2.3 Failure

| Event | what happens | what the program sees |
|---|---|---|
| `launch` refused (`Unsupported`, `TooLarge`, `WrongDevice`) | nothing is queued; `token(q)` is unchanged | the error, at the call |
| staging or submission failure in `upload` | the allocation is reclaimed, no handle escapes | `OutOfMemory` at the call |
| a fault record | the invocation returned; the token completes | `Fault` at the next `sync`/`download` on that queue |
| device loss | every token Lost; every later fallible call `Lost`; `close` completes | `Lost` |
| partial failure of a chain (`write` ok, `launch` refused) | the queue holds the write; nothing after it | the launch's error; the program decides |
| `close` with work outstanding | waits for every queue, then releases | `ok`, or `Lost` |
| cancellation | **none in v1.** There is no `cancel`: a request to cancel is not proof that device memory can be released (H21), and `close` is the one exclusive transition. A program that wants to stop a chain stops submitting and waits | -- |

### 2.4 Discovery and selection (D83), and the H18 record

Spec §10's discovery contract is frozen as written: bounded `devices` (`TooLarge`
past the limit, never truncation), `DeviceInfo`/`DeviceKey`/`DeviceKind`, exact
`open_id` (`NoDevice`, `AmbiguousDevice`, `Unsupported` -- never an index, a
name, another backend or the CPU substituted), `info` as the opening-time
descriptor, `key_valid` over a zero UUID, MIG partitions as separate devices,
cross-backend identity never inferred. The harness record (H18, when the
transport lands) carries both what was **requested** and what was **selected**:

```
{ "kind": "device", "requested": { "backend": "vulkan", "key": "vulkan:0123...ef" | null, "index": 1 | null },
  "selected":  { "backend": "vulkan", "key": "vulkan:0123...ef", "key_valid": true, "index": 1, "name": "...", "supported": true },
  "provenance": "checked" }
```

`provenance` is `checked` when the runtime opened the device, `declared` when a
manifest names it and no open happened, `unknown` otherwise. A kernel's
requirements record is the H08 fact set of §1.7 with the same provenance field
(`checked` from a compiled `.em`, `declared` from `caps(...)` alone).

Mock inventory fixtures, design-time: `gpu_devices_cpu` (`.Cpu` exposes exactly
one record: index 0, zero key, `key_valid`, name `Neper CPU`), `gpu_devices_mock_dup`
(a mock Vulkan inventory with two records of one key: `open_id` is
`AmbiguousDevice`, `open` by index succeeds), `gpu_devices_mock_invalid` (a record
with `key_valid == false` is excluded from `open_id` matching and opens by index).
The mock inventory is a `--gpu-inventory FILE` option of the M3 runtime, not of
the compiler.

### 2.5 Fixtures named for M3

| fixture | shape | expected |
|---|---|---|
| `gpu_two_queues_ordered` | q1 writes, q2 `wait_for(token(q1))` then launches, download on q2 | the computed values |
| `gpu_two_queues_race` | the same without the wait | undefined; observed on a device, not on `.Cpu` |
| `gpu_chain_transfers` | upload, three launches, write into the middle, download | the values of the chain in submission order |
| `gpu_early_release` | release on q1 while q2's launch still reads the buffer | the release waits for q2's token; the download is correct |
| `gpu_range_overlap` | two `write`s on one queue to overlapping ranges | the later write wins, whole-buffer tracking reports the overlap |
| `gpu_failed_launch` | `launch` with a grid past the limit after a write | `TooLarge`; the write's token completes; the buffer holds the write |
| `gpu_stale_token` | `token(q)`, `close(dev)`, `done(t)` | `InvalidHandle` |
| `gpu_device_lost` | a mock backend that reports loss after the first launch | `Lost` from `sync`, from `release` (handle consumed), from `close` |
| `gpu_wrong_device_token` | `wait_for` on a queue of another device | `WrongDevice` |

## 3. H22 -- end-to-end cost and the artifact lifecycle

### 3.1 The timeline record

One JSON line per phase, written by the runtime under `--gpu-timeline FILE` (M3):

```
{ "kind": "gpu-phase", "phase": "staging-alloc" | "staging-copy" | "transfer" | "submit" | "queue-wait" |
  "pipeline-compile" | "kernel" | "readback" | "sync",
  "queue": 1, "serial": 7, "kernel": "mod.saxpy" | null, "bytes": 4096 | null,
  "clock": "host" | "device", "start_ns": 0, "end_ns": 0, "implicit": false,
  "cold": true, "instrumentation_ns": 120 }
```

Rules the schema encodes: host phases are on the host clock, `kernel` and
`transfer` on the device timestamp clock when the device has one
(`timestampComputeAndGraphics`; otherwise the phase is recorded with `clock:
"host"` around the submission and wait, which over-measures, and the record says
so by its clock); the two clocks are **never subtracted from each other**; a
report sums phases of one clock and one queue into a busy time and reports wall
time separately, since phases overlap; `instrumentation_ns` is what the
instrumentation itself cost and is reported apart from every phase. **Cold** is
the first launch of a kernel on a device in a process -- it includes
`pipeline-compile`, which SPIR-V emission does not finish -- and **warm** is every
later launch of it; the cold/warm workload definitions are the H25 registry's
(`benchmarks/baseline/`), each with an output oracle (a download compared with the
CPU backend's), and the gate judges them with the same budgets once measured.

### 3.2 Cache identity

A pipeline cache entry (the driver's compiled form of one kernel on one device)
is keyed by every input that changes the code:

| key part | source |
|---|---|
| kernel identity | the `.spv.em`/`.ptx.em` Code section's content hash (xxHash64, §12) |
| specialisation | the launch site's `K` and, per reached helper, its specialisation arguments (§1.6) |
| device and driver | `DeviceKey`, driver version string, backend |
| capability set | the inferred set as recorded in the Interface entry |
| numerical policy | `ftz` per kernel; the D39 rule otherwise carries no options and the key says `"exact"` |
| safety policy | `retained` / `off` / per-block `nocheck` (§1.3), since the checks change the code |
| compilation options | `--cpu sm_*`, `--release`, the neper compiler's own content hash |

A stale or corrupt cache entry (a key that decodes but a blob the driver rejects,
or a checksum mismatch) is **rebuilt, never trusted**: H24's readers apply -- the
entry is validated before use, published only after a complete write, and the
last valid entry kept when a rebuild fails. The cache is a local optimisation
cache; nothing in it authorises execution of anything the build did not embed.

### 3.3 Staging

`upload`/`write` copy into driver-owned staging (§10). The bounded model:

| | rule |
|---|---|
| pool | per queue, `blocks` staging blocks of `block_bytes` each, from the driver once at the first use; `type StagingLimits = struct { blocks: u32, block_bytes: usize }` given to `queue_with(dev, limits)`; `queue(dev)` uses `{ 4, 16 MiB }` |
| a source larger than a block | split across blocks in one submission when enough are free; otherwise `TooLarge`, not a silent growth |
| every block in flight | `upload`/`write` **wait for the oldest transfer** on that queue (a synchronous wait, reported as a `queue-wait` phase with `implicit: true`); they never allocate past the pool |
| allocation failure of the pool itself | `OutOfMemory` at the first `upload`/`write`, the queue stays usable for launches |
| `.Cpu` | no staging: a memcpy into the `Buf`'s arena storage, `mem.Exhausted` at `alloc`/`upload` |
| pinned / borrowed asynchronous transfer | **not in the baseline.** Its shape when it comes: `upload_borrowed(q, src: []const T) -> (Buf[T], Token, err)` where `src` is *lent* to the queue until the token completes -- D365's lending, over a slice, which H04 §5 lists as undelivered -- so the checker refuses a write to `src` before `wait(t)`. Not until both the lending over slices and a workload that needs it exist |

What M3 implements of this: the pool with the fixed default, the wait-on-full
rule, the timeline record, the pipeline cache keyed as §3.2 with rebuild on
mismatch, the H25 cold/warm rows. Not M3: batched submission (a `begin`/`end`
pair that submits N launches in one driver call -- the token contract does not
change, `serial` advances per launch inside the batch), reusable execution
graphs, the pinned path, and an optimised CPU kernel backend. The CPU backend
stays the checked debugger and is **not advertised as a fallback**: the
state-machine execution of D38 is the reference, the `.Cpu` record's `kind` is
`.Cpu`, and a program that chooses it chooses it.

### 3.4 Fixtures named for M3

| fixture | shape | expected |
|---|---|---|
| `gpu_timeline_cold` | first launch of one kernel on a newly opened device | a cold `pipeline-compile` record, per-clock phase totals and CPU-matching output |
| `gpu_timeline_warm` | repeat the same launch and inputs | warm records, no compilation phase and the same output oracle |
| `gpu_staging_bound` | fill every staging block, then write again | wait for the oldest transfer, one implicit `queue-wait`, no pool growth |
| `gpu_staging_exhausted` | inject failure into the first pool allocation | `OutOfMemory`; no block retained; later launches remain usable |
| `gpu_cache_corrupt` | checksum-valid key with a corrupt driver blob, then injected rebuild failure | reject and rebuild; a failed rebuild does not replace the last valid entry |

These fixture IDs, the timeline fields, cache-key parts and staging defaults are
mirrored in `docs/m25-gpu-contracts.json`; M3 records their runtime evidence.

## 4. H23 -- numerical and capability contracts

### 4.1 Corrections to the spec (edited in D367)

**Subgroups.** §10 claimed bit-identity "subject only to" four exceptions, and a
kernel that writes `gpu.subgroup_size()` to a buffer is a counterexample without
any float involved: 32 on the CPU, 32 or 64 on a device, 32 on NVIDIA. The claim is
now stated under a precondition: **equivalence holds for a kernel that is
subgroup-independent** -- one whose result does not depend on `subgroup_size()`,
`sid`, the lane mapping or which lanes are active -- and for any kernel **under a
matching subgroup width and lane mapping**, which the CPU emulator can be
configured to (`--subgroup-width 8|16|32|64` of the M3 runtime; the default stays
32). A partial last subgroup behaves alike at every width (D38). The fixtures:
`gpu_subgroup_width` (the same reduction at 16, 32 and 64 on the emulator, each
against the device of that width), `gpu_subgroup_partial` (a workgroup of 100 at
every width), `gpu_subgroup_dependent` (a kernel that stores `subgroup_size()`:
its CPU and device results differ by design, and the fixture *expects* the
difference).

**Denormals.** §11 said a device "preserves `f32` denormals exactly when it does so
by default -- which `gpu.has(dev, .DenormPreserve)` reports, and every desktop
part does." `shaderDenormPreserveFloat32` says the device *supports* the
`DenormPreserve` execution mode, not that a module carrying no mode preserves
them; and "every desktop part" is not a contract. The rule now: a kernel not
marked `ftz` **requires** denormal preservation and the module **carries the
`DenormPreserve` execution mode** for `f32` (and `f64` when used); `.DenormPreserve`
moves from "reported, never required" to the inferred capability set of every
such kernel, and a device without it fails at `launch` with `Unsupported` naming
the kernel and `DenormPreserve` -- explicit rejection, no silent flush. A kernel
marked `ftz` requires `.Ftz` and carries `DenormFlushToZero`, as before. There is
no fallback in between: a program that wants to run on a device with neither
writes the `ftz` kernel and says so. PTX preserves without `.ftz`, so the `ptx`
target satisfies the requirement everywhere.

### 4.2 The matrix

Every row names its oracle: **CPU** is the CPU build of the same kernel; **ref** is
a correctly rounded software reference (mpmath, as `e.math` was measured, D147).
The same 21 rows are serialized in `docs/m25-gpu-contracts.json`; its validator
requires CPU, SPIR-V and PTX behavior, a result oracle/bound, exceptional behavior,
width/layout, capabilities, subgroup dependence and nondeterminism for every row.

| operation | CPU backend | `spv` | `ptx` | exact / bound | exceptional inputs | width / layout | capability | subgroup-dependent | nondeterministic |
|---|---|---|---|---|---|---|---|---|---|
| `+ - *` on `f32`/`f64` | IEEE, no contraction | `NoContraction` | `.rn` | exact | NaN canonical, signed zero, inf as IEEE | `f64` needs `.Float64` | `.Float64` for `f64` | no | no |
| `/` | IEEE | correctly rounded sequence over `Fma` | `div.rn` | exact | `x/0` inf, `0/0` NaN, never a check | -- | -- | no | no |
| `math.sqrt` | `sqrtss`/`sqrtsd` | correctly rounded sequence | `sqrt.rn` | exact | negative is NaN | -- | -- | no | no |
| `math.fma` | fused (`x64-v3`+) or exact software | `Fma` + `NoContraction` | `fma.rn` | exact, one rounding | as IEEE | -- | -- | no | no |
| `a*b + c` written so | two roundings | two roundings | two roundings | exact, two roundings; never contracted | -- | -- | -- | no | no |
| `math.min`/`max` | IEEE `minimum`/`maximum` | compare-and-select | compare-and-select | exact | one NaN gives NaN; `min(-0,+0)` is `-0` | -- | -- | no | no |
| `round` | ties-to-even | `RoundEven` | `cvt.rni` | exact | -- | -- | -- | no | no |
| `floor` `ceil` `trunc` `abs` `copysign` | exact | exact | exact | exact | -- | -- | -- | no | no |
| `sin cos tan asin acos atan atan2 exp exp2 log log2 log10 pow` | ≤ 2 ULP vs ref | Vulkan precision table | CUDA precision table | **bounded, not identical** | domain errors as `e.math` | -- | -- | no | no |
| `math.rsqrt` | ≤ 2 ULP | ≤ 2 ULP | ≤ 2 ULP | bounded | -- | -- | -- | no | no |
| `f16` arithmetic | computed in `f32`, rounded | `Float16` ops | `sm_53`+ | exact per D25 (round-to-nearest of the `f32` result) | -- | 16-bit storage under `.Int16` | `.Float16` | no | no |
| `bf16` | computed in `f32`, rounded | the same | the same (native only at `sm_80`) | exact per D25 | -- | 16-bit under `.Int16` | `.Int16` | no | no |
| denormal `f32` inputs/results | preserved (no FTZ/DAZ) | preserved under `DenormPreserve`; refused otherwise | preserved | exact | -- | -- | `.DenormPreserve` (§4.1) | no | no |
| `ftz` kernel | FTZ+DAZ around the run | `DenormFlushToZero` | `.ftz` | exact (flush both sides) | denormal results are `±0` | -- | `.Ftz` | no | no |
| integer `+ - * /` at 8/16/32/64 | two's complement | at width | at width | exact | debug overflow trap on CPU, fault record on device (§1.3) | `i8`/`i16`/`i64` need `.Int8`/`.Int16`/`.Int64` | as listed | no | no |
| `usize` arithmetic | 64-bit | **32-bit** | 64-bit | exact **at the width**; a kernel that overflows 32 bits differs by design | -- | not a storage type | -- | no | no |
| `gpu.atomic_add` etc. on integers | sequential in `lid` order | hardware order | hardware order | exact result; order unspecified | -- | 64-bit needs `.Atomic64` | `.Atomic64` | no | **the order** |
| `subgroup_add/min/max` on integers | fixed tree over 32 | hardware | hardware | exact | -- | -- | `.Subgroup` | **yes** (width) | no |
| `subgroup_add/min/max` on floats | fixed tree over 32 | hardware order | hardware order | **bounded by the reduction's rounding; not identical** | -- | -- | `.Subgroup` | yes | yes (order) |
| `subgroup_size`, `sid`, `ballot`, `elect`, `broadcast`, `shuffle` | 32-lane model | device width | 32 | exact under matching width | inactive lanes `false` / contribute nothing | `ballot` is `u64` | `.Subgroup`, `.Int64` for `ballot` | **yes** | no |
| `simd.reduce_add` (Vec) | fixed tree | fixed tree | fixed tree | exact, identical | -- | `N > 4` split into 4-lane vectors | that of `T` | no | no |

There is no fast-math flag and the key of §3.2 says `"exact"` because there is
nothing else it could say; `ftz` is per kernel and in the key. A native opcode is
not proof of exactness: the `spv` division and square root are sequences because
Vulkan bounds the opcodes to 2.5 ULP, and the row says "correctly rounded
sequence", not `OpFDiv`.

### 4.3 Capability refusal and launch preconditions

| precondition | checked | failure |
|---|---|---|
| the device is at the floor (Vulkan 1.2, `bufferDeviceAddress`, `scalarBlockLayout`) | `open`/`open_id` | `Unsupported` |
| every inferred capability of `K`, `.DenormPreserve` included for a non-`ftz` kernel | `launch` | `Unsupported` naming the kernel and the capability |
| workgroup size and `shared` bytes within the device's limits | `launch` | `Unsupported` |
| the grid within the dispatch limits; every `Buf` under 2³² elements on `spv` | `launch`; `alloc`/`upload` | `TooLarge` |
| `caps(...)` upper bound | compile time | `E-GPU-0002` with the call chain |
| `subgroupSize` at most 64 | `open` | `Unsupported` |

Fixtures (CPU cases executable in M3's first week, device cases pending):
`gpu_num_denormal` (a denormal input through `+`, preserved on the CPU and on a
`DenormPreserve` device, refused on a device without it), `gpu_num_ftz` (the same
kernel with `ftz`: `±0` on all three), `gpu_num_rounding` (ties and boundary
rounding of `round`, `f16` conversion at the halfway cases), `gpu_num_exceptional`
(NaN canonicalisation, signed zero through `min`/`max`, `x/0`), `gpu_num_fma`
(`math.fma` against `a*b + c` on inputs where they differ by one ULP; the
difference is the expected result), `gpu_num_reduce` (`simd.reduce_add` identical;
`subgroup_add` on floats within bound, not identical), `gpu_num_usize` (a kernel
that wraps at 2³²: the `spv` result differs by design and the fixture expects
it), `gpu_cap_refused` (an `f64` kernel on a mock device without `.Float64`:
`Unsupported` naming both), `gpu_cap_bound` (`caps(.Int64)` with an `f64` three
helpers down: `E-GPU-0002` with the chain).

## 5. What this closes and what it does not

Closed, by design: every applicable H01-H07 requirement has a CPU/device mapping,
a type/ABI/error contract and a named positive/negative fixture (§1); the
token, buffer-use, failure and discovery contracts with their state tables (§2);
the timeline schema, cache-key matrix and staging model, and the list of what M3
implements of them (§3); the two spec corrections and the matrix with its oracles
(§4). No question here changes the CPU ownership or tooling contracts of D345-D365:
the boundary is synchronous where the checker needs it to be, and the one
additive extension is delivered by D613 before M3. The formal closure and all 32
exact fixture obligations are `m25-gpu-closure.md` and
`m25-gpu-contracts.json`.

Not closed, and not claimed: any runtime evidence. The fixtures exist as names;
the `gpu.Fault` error, the fault buffer, tokens, the staging pool, the timeline,
the cache, `--subgroup-width`, `--gpu-inventory` and the `DenormPreserve`
execution mode are M3 deliveries. Every fixture remains `pending_m3` until the
CPU/Vulkan implementation supplies evidence; PTX execution remains M4.
