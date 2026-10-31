# e.gpu — 1 of 168 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gpu.e` |
| plan row | layer 5, surface `partial`, milestone M3, schedule `scheduled` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gpu.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental collection conveniences:** `e.data.stack`, `e.data.queue` and `e.data.linked` remain available for workload evaluation but have no compatibility promise. `e.gpu.tensor` is likewise experimental, follows both M3 `e.gpu` and extended `e.algo.linalg.tensor`, and keeps every operation as an explicit queue submission. Promotion requires an applicable general-purpose workload and a recorded compatibility decision.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.hash` | source | `lib/e/algo/hash.e` | 2 |
| `e.atomic` | source | `lib/e/atomic.e` | 0 |
| `e.fs` | partial | `lib/e/fs.e` | 4 |
| `e.gpu.cuda` | partial | `lib/e/gpu/cuda.e` | 5 |
| `e.gpu.vulkan` | partial | `lib/e/gpu/vulkan.e` | 5 |
| `e.math` | partial | `lib/e/math.e` | 0 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 5 may depend on layers [0, 1, 2, 3, 4, 5].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Backend = enum u8 { Cpu, Vulkan, Cuda }
type DeviceKind = enum u8 { Unknown, Cpu, Integrated, Discrete, Virtual, Other }
type DeviceKey = struct { backend: Backend, uuid: [16]u8 }
type DeviceInfo = struct { key: DeviceKey, key_valid: bool, index: u32, name: str, kind: DeviceKind, memory_bytes: u64, memory_known: bool, capabilities: []const Cap, supported: bool }
type Device = struct { state: *void }
type Queue = struct { state: *void }
type StagingLimits = struct { blocks: u32, block_bytes: usize }
type Buf[T: type] = struct { owner: u32, slot: u32, generation: u32, len: usize }
type Token = struct { owner: u32, queue: u32, serial: u64 }
type Grid = struct { x: usize, y: usize, z: usize }
type Id = struct { x: u32, y: u32, z: u32 }
type FaultKind = enum u8 { Bounds, Null, Tag, Alignment, Overflow, DivideByZero }
type FaultRecord = struct { kernel: u32, kind: FaultKind, site: u32, gid: Id }
type Cap = enum u8 { Int8, Int16, Int64, Float16, Float64, Atomic64, Subgroup, Ftz, DenormPreserve }
type Format = enum u8 { Rgba8, Bgra8 }
type Image = struct { data: Buf[u32], width: u32, height: u32, format: Format }
type SurfaceKind = enum u8 { Offscreen, Win32, X11, Wayland, Cocoa }
type Surface = struct { kind: SurfaceKind, handle: *void, context: *void }
type Target = struct { state: *void }
type Frame = struct { image: Image, serial: u64 }
type Scope = enum u8 { Workgroup, Device }
type Buffer = struct { bytes: []u8, count: usize, elem: usize, generation: u32, live: bool, device: vulkan.Buffer }
type DeviceState = struct { arena: *mem.Arena, owner: u32, closed: bool, buffers: []Buffer, queues: u32, backend: Backend, context: vulkan.Context, physical: vulkan.Physical, pipeline_modules: [16]usize, pipeline_entries: [16]str, pipelines: [16]vulkan.Pipeline, pipeline_count: usize }
type QueueState = struct { device: *DeviceState, index: u32, serial: u64, fault_count: u32, fault: FaultRecord, last: FaultRecord, has_last: bool }
type TargetState = struct { queue: *QueueState, images: [2]Image, front: usize, width: u32, height: u32, format: Format, serial: u64, acquired: bool, closed: bool }
var gid: Id = zero
var lid: Id = zero
var wgid: Id = zero
var sid: u32 = zero
var subgroup_width: u32 = 32u32
var next_owner: u32 = 1u32
var open_devices: [16]*DeviceState = zero
var open_count: usize = 0usize
var launch_size: [3]usize = zero
var launch_groups: [3]usize = zero
var launch_active: bool = zero
var launch_queue: *QueueState = zero
var launch_local: usize = 0usize
var subgroup_values: [1024]bool = zero
var subgroup_snapshot: [1024]bool = zero
var subgroup_active: [1024]bool = zero
var subgroup_words: [1024]u64 = zero
var subgroup_word_snapshot: [1024]u64 = zero
var subgroup_lanes: [1024]u32 = zero
var subgroup_lane_snapshot: [1024]u32 = zero
type SortArgs = struct { keys: []u32, n: u32, j: u32, k: u32 }
type AttentionArgs = struct { query: []const f32, key: []const f32, value: []const f32, out: []f32, n: u32, d: u32, tile: u32, scale: f32 }
error NoDevice
error AmbiguousDevice
error Unsupported
error OutOfMemory
error TooLarge
error Lost
error WrongDevice
error InvalidHandle
error Fault
error Outdated
const MAX_BUFFERS: usize = 4096usize
const MAX_DEVICES: usize = 16usize
const MAX_QUEUES: usize = 64usize
const MAX_AXIS: usize = 4294967295usize
const SUBGROUP_PC: usize = 1073741824usize
const CPU_CAPABILITIES: usize = 375usize
const MAX_IMAGE_SIDE: u32 = 16384u32
const DONE: usize = 4294967295usize
const FAULTED: usize = 4294967294usize
const MAX_SORT: usize = 16777216usize
const MAX_HEAD: usize = 256usize

fn capability_bit(capability: Cap) -> usize
fn capability_list(a: *mem.Arena, bits: usize) -> ([]const Cap, err)
fn cpu_capabilities(a: *mem.Arena) -> ([]const Cap, err)
fn cpu_info(a: *mem.Arena) -> (DeviceInfo, err)
fn devices(a: *mem.Arena, backend: Backend, limit: usize) -> ([]const DeviceInfo, err)
fn state_of(device: *Device) -> (*DeviceState, err)
fn open(a: *mem.Arena, backend: Backend, index: u32) -> (*Device, err)
fn open_id(a: *mem.Arena, key: DeviceKey) -> (*Device, err)
fn info(a: *mem.Arena, device: *Device) -> (DeviceInfo, err)
fn close(device: *Device) -> err
fn has(device: *Device, capability: Cap) -> bool
fn queue(device: *Device) -> (*Queue, err)
fn queue_with(device: *Device, limits: StagingLimits) -> (*Queue, err)
fn queue_state(q: *Queue) -> (*QueueState, err)
fn slot_of(state: *QueueState, owner: u32, slot: u32, generation: u32) -> (usize, err)
fn alloc[T: type](q: *Queue, n: usize) -> (Buf[T], err)
fn host_bytes[T: type](src: []const T) -> []u8
fn upload[T: type](q: *Queue, src: []const T) -> (Buf[T], err)
fn len[T: type](buf: Buf[T]) -> usize
fn write[T: type](q: *Queue, dst: Buf[T], off: usize, src: []const T) -> err
fn token(q: *Queue) -> (Token, err)
fn token_device(token_value: Token) -> (*DeviceState, err)
fn wait_for(q: *Queue, dependency: Token) -> err
fn done(token_value: Token) -> (bool, err)
fn wait(token_value: Token) -> err
fn report_fault(state: *QueueState) -> err
fn last_fault(q: *Queue) -> (FaultRecord, bool)
fn fault(kind: u32, site: u32)
fn download[T: type](q: *Queue, src: Buf[T], dst: []T) -> err
fn sync(q: *Queue) -> err
fn release[T: type](q: *Queue, buf: Buf[T]) -> err
fn grid1(x: usize) -> Grid
fn grid2(x: usize, y: usize) -> Grid
fn grid3(x: usize, y: usize, z: usize) -> Grid
fn image(q: *Queue, width: u32, height: u32, format: Format) -> (Image, err)
fn write_image(q: *Queue, dst: Image, x: u32, y: u32, width: u32, height: u32, src: []const u32) -> err
fn read_image(q: *Queue, src: Image, dst: []u32) -> err
fn release_image(q: *Queue, img: Image) -> err
fn target_state(t: *Target) -> (*TargetState, err)
fn queue_state_of(state: *QueueState) -> (*QueueState, err)
fn target_images(state: *TargetState, width: u32, height: u32) -> err
fn open_target(q: *Queue, surface: Surface, width: u32, height: u32, format: Format) -> (*Target, err)
fn extent(t: *Target) -> (u32, u32)
fn resize(t: *Target, width: u32, height: u32) -> err
fn acquire(t: *Target) -> (Frame, err)
fn present(q: *Queue, t: *Target, frame: Frame) -> (Token, err)
fn presented(t: *Target) -> (Image, err)
fn close_target(t: *Target) -> err
fn groups_along(invocations: usize, size: usize) -> (usize, err)
fn launch_view(q: *Queue, owner: u32, slot: u32, generation: u32) -> (usize, usize, err)
fn subgroup_record(value: bool)
fn subgroup_record32(value: u32, lane: u32)
fn subgroup_record64(value: u64, lane: u32)
fn subgroup_failure(bounds: bool)
fn subgroup_exchange(kind: u32) -> u64
fn subgroup_exchange32(kind: u32) -> u32
fn subgroup_exchange64(kind: u32) -> u64
fn subgroup_begin() -> usize
fn subgroup_end(first: usize) -> usize
fn subgroup_add_u64(a: u64, b: u64) -> u64
fn subgroup_reduce_u32(kind: u32) -> u32
fn subgroup_reduce_i32(kind: u32) -> i32
fn subgroup_reduce_u64(kind: u32) -> u64
fn subgroup_reduce_i64(kind: u32) -> i64
fn subgroup_reduce_f32(kind: u32) -> f32
fn subgroup_reduce_f64(kind: u32) -> f64
fn subgroup_vote(kind: u32) -> u64
fn set_ids(group: usize, local: usize)
fn subgroup_wait(pc: usize) -> bool
fn subgroup_ready(frames: []u8, base: usize, bytes_per_frame: usize, per_group: usize, local: usize, pc: usize) -> bool
fn workgroup_ready(frames: []u8, base: usize, bytes_per_frame: usize, per_group: usize, pc: usize) -> bool
fn barrier_number(pc: usize) -> usize
fn frame_pc(frames: []u8, at: usize) -> usize
fn write_decimal(out: []u8, at: usize, v: usize) -> usize
fn write_text(out: []u8, at: usize, text: str) -> usize
fn write_id(out: []u8, at0: usize, group: usize, local: usize) -> usize
fn divergence(group: usize, stopped_local: usize, stopped_at: usize, other_local: usize, other_at: usize)
fn launch_run(q: *Queue, grid: Grid, x: usize, y: usize, z: usize, frame_bytes: usize, shared_bytes: usize, step: fn(opaque: *void, frame: *u8, workgroup: *u8), ctx: *void, requirements: usize, module: str, entry: str, layout: str) -> err
fn launch_device(state: *QueueState, grid: Grid, x: usize, y: usize, z: usize, ctx: *void, module: str, entry: str, layout: str) -> err
fn device_pipeline(device: *DeviceState, module: str, entry: str) -> (vulkan.Pipeline, err)
fn hex_bytes(a: *mem.Arena, digits: str) -> ([]u8, err)
fn hex_digit(digit: u8) -> usize
fn vulkan_info(a: *mem.Arena, physical: vulkan.Physical, index: u32) -> (DeviceInfo, err)
fn open_vulkan(a: *mem.Arena, index: u32) -> (*Device, err)
fn open_state(a: *mem.Arena, backend: Backend) -> (*Device, err)
fn device_slice[T: type](state: *QueueState, buf: Buf[T]) -> ([]T, err)
fn mark_done(frame: *u8)
fn bitonic_step(keys: []u32, i: u32, j: u32, k: u32)
fn sort_step(ctx: *void, frame: *u8, workgroup: *u8)
fn sort_bitonic(device: *Device, q: *Queue, buffer: Buf[u32], n: usize) -> err
fn attention_row(args: *AttentionArgs, row: usize)
fn attention_step(ctx: *void, frame: *u8, workgroup: *u8)
fn attention_flash(device: *Device, q: *Queue, query: Buf[f32], key: Buf[f32], value: Buf[f32], out: Buf[f32], n: usize, d: usize, tile: usize, scale: f32) -> (usize, err)
fn launch[K: fn](q: *Queue, grid: Grid, args: ...) -> err
fn barrier()
fn memory_barrier(scope: Scope)
fn subgroup_size() -> u32
fn subgroup_elect() -> bool
fn subgroup_all(value: bool) -> bool
fn subgroup_any(value: bool) -> bool
fn subgroup_ballot(value: bool) -> u64
fn subgroup_broadcast[T: type](value: T, lane: u32) -> T
fn subgroup_shuffle[T: type](value: T, lane: u32) -> T
fn subgroup_add[T: type](value: T) -> T
fn subgroup_min[T: type](value: T) -> T
fn subgroup_max[T: type](value: T) -> T
fn subgroup_and[T: type](value: T) -> T
fn subgroup_or[T: type](value: T) -> T
fn subgroup_xor[T: type](value: T) -> T
fn atomic_load[T: type](p: *Atomic[T], order: atomic.Ordering, scope: Scope) -> T
fn atomic_store[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope)
fn atomic_xchg[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
fn atomic_cas[T: type](p: *Atomic[T], expected: T, desired: T, success: atomic.Ordering, failure: atomic.Ordering, scope: Scope) -> (bool, T)
fn atomic_add[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
fn atomic_sub[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
fn atomic_and[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
fn atomic_or[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
fn atomic_xor[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
fn atomic_min[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
fn atomic_max[T: type](p: *Atomic[T], value: T, order: atomic.Ordering, scope: Scope) -> T
```

Presentation (spec section 10, D791) is images over kernels: an `Image` is a `Buf[u32]`
of packed pixels a kernel writes, a `Target` presents frames to an offscreen pair on
every backend or to a native `Surface` on a driver backend, and there is no
fixed-function pipeline.

Discovery/selection is specified in [spec §10](spec.md#device-discovery-and-selection).
`devices` is a bounded, caller-arena-owned snapshot, including copied names and
capability lists; exceeding the limit fails rather than returning a partial success.
Indices are temporary backend ordinals. `open_id` requires an exact backend-scoped
UUID match, rejects duplicate matches with `AmbiguousDevice`, and never silently
falls back. `key_valid == false` means stable-key selection is unavailable, not that
a fabricated index/name hash may substitute. `info` copies the opening-time descriptor
of the selected device. Memory is reported capacity, not free or reserved storage.
Every queue/buffer belongs to one open device, including when two opens address the
same GPU. A check failing in a kernel writes the queue's one `FaultRecord` and ends
that invocation; the next `sync` or `download` answers `Fault` once and `last_fault`
answers the record behind the last `Fault` the queue reported (D785). These additions are planned for M3 CPU/Vulkan, with CUDA in M4; they do not
claim implementation or an optimized production CPU fallback.

A `.Vulkan` device (D1611) is `e.gpu.vulkan` underneath: `devices` lists every physical
device with `supported` meaning section 10's floor (`Unsupported` without a loader, an
empty list with a loader and no device, `TooLarge` past the limit, D4200), each record's
key the driver's deviceUUID with `key_valid` false when the driver reports none, `open`
answers `NoDevice` without a loader or a device at that index and `Unsupported` below the
floor, `open_id` matches that key exactly, and a buffer is
mapped host memory, so `upload`, `write` and `download` are copies. `gpu.launch` hands
`launch_run` the kernel's SPIR-V, as hex digits from its module's `K$spirv` companion,
its entry point and a character per parameter; a launch on a Vulkan device lays out
D1610's argument block, makes the kernel's pipeline once per device, dispatches and
waits. The generated launcher also carries the checker's inferred capability mask;
`launch_run` compares it with the selected device before dispatch and answers
`Unsupported` when any required capability is absent. A kernel the SPIR-V emitter
cannot write yet has no module there, and its Vulkan
launch answers `Unsupported`; the CPU device still runs it.

A `.Cuda` device (D4705) is `e.gpu.cuda` underneath and is enumerated, not opened: `devices`
lists the driver's devices (`Unsupported` without the driver, an empty list with a driver and
no device, `TooLarge` past the limit), each key the device's `cuDeviceGetUuid` bytes under the
`.Cuda` backend, `supported` false, memory known; `open` is `Unsupported`, and `open_id` of a
listed key is `Unsupported` (found, nothing to open it with) where an absent key is `NoDevice`
and two devices of one key `AmbiguousDevice`. The count/list race of a Vulkan enumeration is
retried (`VK_INCOMPLETE` asks the count again, three attempts, then `Lost`, D4700).

`NEPER_GPU_INVENTORY` names a text file of mock devices (`neper run --gpu-inventory FILE`
sets it for the program): one line each, `<vulkan|cuda> <1|0 key valid> <32 hex digits or -> <name>`.
When it is set it replaces the `.Vulkan` and `.Cuda` enumeration (`.Cpu` is untouched):
`devices` and `open_id` resolve over its records with the real `resolve_key`, an index opens a
CPU-backed device whose `info` is the record, and an unreadable or malformed file is
`Unsupported`. It is how selection (duplicate keys, a record without a key) is tested on a
machine with one device.

The landed device-only intrinsics are `gid`, `lid`, `wgid`, `sid`, `barrier`,
`memory_barrier`, `subgroup_size`, `subgroup_elect`, `subgroup_all`, `subgroup_any`,
`subgroup_ballot`, `subgroup_broadcast`, `subgroup_shuffle`, the six arithmetic and
bitwise reductions, and the scoped atomic family above.

## Missing declarations

- [ ] `token_device`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/ui-framework.md:13` renders them through `e.gpu`. It borrows Flutter's useful separation between
- `docs/ui-framework.md:234` - `gpu-presentation-api`: `e.gpu` support for presentation targets, textures, render
- `docs/ui-framework.md:250` `e.gpu` catalogues before the blocked modules can move from proposal to
- `docs/spec.md:2733` SPIR-V. `e.gpu` reaches it as `Backend.Gl` once `x.khronos.compute.install()` has run, because `e.*` does not import
- `docs/spec.md:3279` This is an extension of the planned M3 `e.gpu` surface, not an implemented feature

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/asset.e`
- `lib/e/async.e`
- `lib/e/atomic.e`
- `lib/e/audio.e`
- `lib/e/barcode.e`†
- `lib/e/bytes.e`
- `lib/e/cancel.e`
- `lib/e/channel.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gpu.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gpu/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
