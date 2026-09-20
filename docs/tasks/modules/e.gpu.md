# e.gpu — 47 of 47 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gpu.e` |
| plan row | layer 5, surface `spec`, milestone M3, schedule `scheduled` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gpu.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental collection conveniences:** `e.data.stack`, `e.data.queue` and `e.data.linked` remain available for workload evaluation but have no compatibility promise. `e.gpu.tensor` is likewise experimental, follows both M3 `e.gpu` and extended `e.algo.linalg.tensor`, and keeps every operation as an explicit queue submission. Promotion requires an applicable general-purpose workload and a recorded compatibility decision.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 5 may depend on layers [0, 1, 2, 3, 4, 5].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Backend = enum u8 { Cpu, Vulkan, Cuda }
type DeviceKind = enum u8 { Unknown, Cpu, Integrated, Discrete, Virtual, Other }
type DeviceKey = struct { backend: Backend, uuid: [16]u8 }
type DeviceInfo = struct {
    key: DeviceKey,
    key_valid: bool,
    index: u32,
    name: str,
    kind: DeviceKind,
    memory_bytes: u64,
    memory_known: bool,
    capabilities: []const Cap,
    supported: bool,
}
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
type Scope = enum u8 { Workgroup, Device }
error NoDevice
error AmbiguousDevice
error Unsupported
error OutOfMemory
error TooLarge
error Lost
error WrongDevice
error InvalidHandle
error Fault

fn open(a: *mem.Arena, backend: Backend, index: u32) -> (*Device, err)
fn devices(a: *mem.Arena, backend: Backend, limit: usize) -> ([]const DeviceInfo, err)
fn open_id(a: *mem.Arena, key: DeviceKey) -> (*Device, err)
fn info(a: *mem.Arena, device: *Device) -> (DeviceInfo, err)
fn close(device: *Device) -> err
fn has(device: *Device, capability: Cap) -> bool
fn queue(device: *Device) -> (*Queue, err)
fn queue_with(device: *Device, limits: StagingLimits) -> (*Queue, err)
fn alloc[T: type](q: *Queue, n: usize) -> (Buf[T], err)
fn upload[T: type](q: *Queue, src: []const T) -> (Buf[T], err)
fn len[T: type](buf: Buf[T]) -> usize
fn write[T: type](q: *Queue, dst: Buf[T], off: usize, src: []const T) -> err
fn launch[K: fn](q: *Queue, grid: Grid, args: ...) -> err
fn token(q: *Queue) -> (Token, err)
fn wait_for(q: *Queue, dependency: Token) -> err
fn done(token_value: Token) -> (bool, err)
fn wait(token_value: Token) -> err
fn download[T: type](q: *Queue, src: Buf[T], dst: []T) -> err
fn sync(q: *Queue) -> err
fn release[T: type](q: *Queue, buf: Buf[T]) -> err
fn grid1(x: usize) -> Grid
fn grid2(x: usize, y: usize) -> Grid
fn grid3(x: usize, y: usize, z: usize) -> Grid
```

Discovery/selection is specified in [spec §10](spec.md#device-discovery-and-selection).
`devices` is a bounded, caller-arena-owned snapshot, including copied names and
capability lists; exceeding the limit fails rather than returning a partial success.
Indices are temporary backend ordinals. `open_id` requires an exact backend-scoped
UUID match, rejects duplicate matches with `AmbiguousDevice`, and never silently
falls back. `key_valid == false` means stable-key selection is unavailable, not that
a fabricated index/name hash may substitute. `info` copies the opening-time descriptor
of the selected device. Memory is reported capacity, not free or reserved storage.
Every queue/buffer belongs to one open device, including when two opens address the
same GPU. These additions are planned for M3 CPU/Vulkan, with CUDA in M4; they do not
claim implementation or an optimized production CPU fallback.

The device-only intrinsics are exactly `gid`, `lid`, `wgid`, `barrier`,
`subgroup_size`, `subgroup_lane`, `subgroup_ballot`, `subgroup_any`, `subgroup_all`,
`subgroup_broadcast`, `subgroup_add`, `subgroup_min`, `subgroup_max`, and the scoped
atomic family specified by spec §10.

## Missing declarations

- [ ] `Backend`
- [ ] `DeviceKind`
- [ ] `DeviceKey`
- [ ] `DeviceInfo`
- [ ] `Device`
- [ ] `Queue`
- [ ] `StagingLimits`
- [ ] `Buf`
- [ ] `Token`
- [ ] `Grid`
- [ ] `Id`
- [ ] `FaultKind`
- [ ] `FaultRecord`
- [ ] `Cap`
- [ ] `Scope`
- [ ] `NoDevice`
- [ ] `AmbiguousDevice`
- [ ] `Unsupported`
- [ ] `OutOfMemory`
- [ ] `TooLarge`
- [ ] `Lost`
- [ ] `WrongDevice`
- [ ] `InvalidHandle`
- [ ] `Fault`
- [ ] `open`
- [ ] `devices`
- [ ] `open_id`
- [ ] `info`
- [ ] `close`
- [ ] `has`
- [ ] `queue`
- [ ] `queue_with`
- [ ] `alloc`
- [ ] `upload`
- [ ] `len`
- [ ] `write`
- [ ] `launch`
- [ ] `token`
- [ ] `wait_for`
- [ ] `done`
- [ ] `wait`
- [ ] `download`
- [ ] `sync`
- [ ] `release`
- [ ] `grid1`
- [ ] `grid2`
- [ ] `grid3`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/ui-framework.md:13` renders them through `e.gpu`. It borrows Flutter's useful separation between
- `docs/ui-framework.md:232` - `gpu-presentation-api`: `e.gpu` support for presentation targets, textures, render
- `docs/ui-framework.md:240` `e.gpu` catalogues before the blocked modules can move from proposal to
- `docs/spec.md:3145` This is an extension of the planned M3 `e.gpu` surface, not an implemented feature

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/async.e`
- `lib/e/atomic.e`
- `lib/e/audio.e`
- `lib/e/bytes.e`
- `lib/e/cancel.e`
- `lib/e/channel.e`
- `lib/e/cli.e`
- `lib/e/db.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gpu.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gpu/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 47.

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
