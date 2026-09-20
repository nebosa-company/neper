// The `e.gpu` runtime over its CPU backend (spec section 10, D778): the one device
// that always exists, at `.Cpu` index 0. `open` takes one bookkeeping block from the
// caller's arena -- the device, its queues and a handle table of MAX_BUFFERS slots --
// and every `Buf[T]` is storage from that same arena, allocated once by `alloc` or
// `upload`; `upload`, `write` and `download` are memcpys, `sync` and the waits answer
// at once because a launch has run to completion before `gpu.launch` returns.
//
// A launch is the compiler's: `gpu.launch[K](q, grid, args...)` expands into a
// generated function that turns every `Buf` argument into the slice over its
// storage (`launch_view`), packs the kernel's arguments into a block, and hands
// `launch_run` the grid, the kernel's workgroup size and frame size, and a step
// function that calls the kernel's CPU build once for one invocation. That build
// is the CPU execution model of section 10 (D780): every local lives in a frame of
// the invocation's own, the body is cut at every `gpu.barrier()`, and a step runs
// an invocation from where it stopped to its next barrier or its return, leaving
// the barrier's number -- or the done mark -- in the frame's first eight bytes.
// `launch_run` is the scheduler: workgroups in workgroup-id order, and within one,
// every invocation stepped in local-id order until all have returned; before each
// step the ids are set -- this module's `gid`, `lid` and `wgid`, which a kernel reads
// as `gpu.gid.x`. After each round the invocations still running must all stand
// at the same barrier: one that returned while its peers wait, or reached another
// barrier, is the bug a device turns into a hang, and traps here as `barrier`.
// The ids are set for the calling thread's launch only, so launches on two threads
// at once are the caller's race, as is every other use of a queue from two threads
// (section 10: a queue is one thread at a time). ponytail: no lock on the device
// block either; add one when a second thread opens a queue. A launch's frames are
// arena until the device closes; reusing them across launches is the upgrade.
//
// A kernel's `shared var`s live in one block per launch, handed to every step,
// filled with 0xCD before each workgroup (D781).
//
// Not here yet: the subgroup builtins, `Atomic` slices, a barrier in a helper a
// kernel calls (only the kernel's own body is cut); `.Vulkan` and `.Cuda` answer
// `Unsupported`, as a backend the build did not embed does; the fault buffer,
// since the CPU build's checks trap where they fire.

use e.mem
use e.os

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

const MAX_BUFFERS: usize = 4096usize
const MAX_DEVICES: usize = 16usize
const MAX_QUEUES: usize = 64usize
const MAX_AXIS: usize = 4294967295usize

// One buffer slot: the storage's bytes, the element count and size, and the
// generation a handle has to carry.
type Buffer = struct { bytes: []u8, count: usize, elem: usize, generation: u32, live: bool }

type DeviceState = struct {
    arena: *mem.Arena,
    owner: u32,
    closed: bool,
    buffers: []Buffer,
    queues: u32,
}

type QueueState = struct { device: *DeviceState, index: u32, serial: u64 }

// The invocation ids of the launch on the calling thread.
var gid: Id = zero
var lid: Id = zero
var wgid: Id = zero

var next_owner: u32 = 1u32
var open_devices: [16]*DeviceState = zero
var open_count: usize = 0usize

// The launch in progress: workgroup size, workgroup counts, and whether one is on.
var launch_size: [3]usize = zero
var launch_groups: [3]usize = zero
var launch_active: bool = zero

fn cpu_capabilities(a: *mem.Arena) -> ([]const Cap, err) {
    let (caps, caps_error) = mem.alloc[Cap](a, 5usize)
    if caps_error != ok { ret (zero, caps_error) }
    caps[0usize] = .Int8
    caps[1usize] = .Int16
    caps[2usize] = .Int64
    caps[3usize] = .Float64
    caps[4usize] = .Atomic64
    ret (caps, ok)
}

fn cpu_info(a: *mem.Arena) -> (DeviceInfo, err) {
    let (caps, caps_error) = cpu_capabilities(a)
    if caps_error != ok { ret (zero, caps_error) }
    var record: DeviceInfo = zero
    record.key.backend = .Cpu
    record.key_valid = false
    record.index = 0u32
    record.name = "cpu"
    record.kind = .Cpu
    record.memory_bytes = 0u64
    record.memory_known = false
    record.capabilities = caps
    record.supported = true
    ret (record, ok)
}

fn devices(a: *mem.Arena, backend: Backend, limit: usize) -> ([]const DeviceInfo, err) {
    if backend != .Cpu { ret (zero, Unsupported) }
    if limit < 1usize { ret (zero, TooLarge) }
    let (records, records_error) = mem.alloc[DeviceInfo](a, 1usize)
    if records_error != ok { ret (zero, records_error) }
    let (record, record_error) = cpu_info(a)
    if record_error != ok { ret (zero, record_error) }
    records[0usize] = record
    ret (records, ok)
}

fn state_of(device: *Device) -> (*DeviceState, err) {
    let pointer = mem.cast[*DeviceState](device.state)
    let wanted = mem.address_of(pointer)
    var i = 0usize
    while i < open_count {
        let candidate = open_devices[i]
        if mem.address_of(candidate) == wanted {
            if candidate.closed { ret (candidate, InvalidHandle) }
            ret (candidate, ok)
        }
        i += 1usize
    }
    ret (zero, InvalidHandle)
}

fn open(a: *mem.Arena, backend: Backend, index: u32) -> (*Device, err) {
    if backend != .Cpu { ret (zero, Unsupported) }
    if index != 0u32 { ret (zero, NoDevice) }
    if open_count >= MAX_DEVICES { ret (zero, TooLarge) }
    let (states, states_error) = mem.alloc[DeviceState](a, 1usize)
    if states_error != ok { ret (zero, states_error) }
    let (buffers, buffers_error) = mem.alloc[Buffer](a, MAX_BUFFERS)
    if buffers_error != ok { ret (zero, buffers_error) }
    var empty: []u8 = zero
    var i = 0usize
    while i < MAX_BUFFERS {
        buffers[i] = Buffer { bytes: empty, count: 0usize, elem: 0usize, generation: 1u32, live: false }
        i += 1usize
    }
    let state = &states[0usize]
    state.arena = a
    state.owner = next_owner
    state.closed = false
    state.buffers = buffers
    state.queues = 0u32
    next_owner += 1u32
    open_devices[open_count] = state
    open_count += 1usize
    let (handles, handles_error) = mem.alloc[Device](a, 1usize)
    if handles_error != ok { ret (zero, handles_error) }
    handles[0usize] = Device { state: mem.cast[*void](state) }
    ret (&handles[0usize], ok)
}

fn open_id(a: *mem.Arena, key: DeviceKey) -> (*Device, err) {
    if key.backend != .Cpu { ret (zero, Unsupported) }
    // The CPU device has no stable key (`key_valid` is false), so no key names it.
    ret (zero, NoDevice)
}

fn info(a: *mem.Arena, device: *Device) -> (DeviceInfo, err) {
    let (_, state_error) = state_of(device)
    if state_error != ok { ret (zero, state_error) }
    let (record, record_error) = cpu_info(a)
    ret (record, record_error)
}

fn close(device: *Device) -> err {
    let (state, state_error) = state_of(device)
    if state_error != ok { ret state_error }
    state.closed = true
    var i = 0usize
    while i < state.buffers.len {
        if state.buffers[i].live {
            state.buffers[i].live = false
            state.buffers[i].generation += 1u32
        }
        i += 1usize
    }
    ret ok
}

fn has(device: *Device, capability: Cap) -> bool {
    let (_, state_error) = state_of(device)
    if state_error != ok { ret false }
    ret capability == .Int8 || capability == .Int16 || capability == .Int64 || capability == .Float64 || capability == .Atomic64
}

fn queue(device: *Device) -> (*Queue, err) {
    let (q, queue_error) = queue_with(device, StagingLimits { blocks: 1u32, block_bytes: 1usize })
    ret (q, queue_error)
}

fn queue_with(device: *Device, limits: StagingLimits) -> (*Queue, err) {
    if limits.blocks == 0u32 || limits.block_bytes == 0usize { ret (zero, TooLarge) }
    let (state, state_error) = state_of(device)
    if state_error != ok { ret (zero, state_error) }
    if usize(state.queues) >= MAX_QUEUES { ret (zero, TooLarge) }
    let (states, states_error) = mem.alloc[QueueState](state.arena, 1usize)
    if states_error != ok { ret (zero, states_error) }
    states[0usize] = QueueState { device: state, index: state.queues, serial: 0u64 }
    state.queues += 1u32
    let (handles, handles_error) = mem.alloc[Queue](state.arena, 1usize)
    if handles_error != ok { ret (zero, handles_error) }
    handles[0usize] = Queue { state: mem.cast[*void](&states[0usize]) }
    ret (&handles[0usize], ok)
}

fn queue_state(q: *Queue) -> (*QueueState, err) {
    let state = mem.cast[*QueueState](q.state)
    if mem.address_of(state) == 0usize { ret (zero, InvalidHandle) }
    if state.device.closed { ret (state, InvalidHandle) }
    ret (state, ok)
}

// The live slot a handle names on this queue's device.
fn slot_of(state: *QueueState, owner: u32, slot: u32, generation: u32) -> (usize, err) {
    if owner != state.device.owner { ret (0usize, WrongDevice) }
    if usize(slot) >= state.device.buffers.len { ret (0usize, InvalidHandle) }
    let buffer = state.device.buffers[usize(slot)]
    if !buffer.live || buffer.generation != generation { ret (0usize, InvalidHandle) }
    ret (usize(slot), ok)
}

fn alloc[T: type](q: *Queue, n: usize) -> (Buf[T], err) {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret (zero, state_error) }
    let elem = mem.size_of[T]()
    if elem == 0usize || n > MAX_AXIS / elem { ret (zero, TooLarge) }
    var slot = 0usize
    while slot < state.device.buffers.len && state.device.buffers[slot].live { slot += 1usize }
    if slot >= state.device.buffers.len { ret (zero, TooLarge) }
    let a = state.device.arena
    let (storage, storage_error) = mem.alloc[T](a, n)
    if storage_error != ok { ret (zero, storage_error) }
    // The storage is the arena's top: its bytes are the last `n * elem` allocated.
    var bytes: []u8 = zero
    if n > 0usize { bytes = mem.view(a, a.off - n * elem, n * elem) }
    let generation = state.device.buffers[slot].generation
    state.device.buffers[slot] = Buffer { bytes: bytes, count: n, elem: elem, generation: generation, live: true }
    ret (Buf[T] { owner: state.device.owner, slot: u32(slot), generation: generation, len: n }, ok)
}

// The bytes of a host slice, through an arena laid over its storage.
fn host_bytes[T: type](src: []const T) -> []u8 {
    if src.len == 0usize { ret zero }
    let elem = mem.size_of[T]()
    var over: mem.Arena = zero
    over.base = mem.cast[*u8](&src[0usize])
    over.cap = src.len * elem
    over.off = src.len * elem
    ret mem.view(&over, 0usize, src.len * elem)
}

fn upload[T: type](q: *Queue, src: []const T) -> (Buf[T], err) {
    let (buf, alloc_error) = alloc[T](q, src.len)
    if alloc_error != ok { ret (zero, alloc_error) }
    let write_error = write[T](q, buf, 0usize, src)
    if write_error != ok {
        let (state, _) = queue_state(q)
        state.device.buffers[usize(buf.slot)].live = false
        state.device.buffers[usize(buf.slot)].generation += 1u32
        ret (zero, write_error)
    }
    ret (buf, ok)
}

fn len[T: type](buf: Buf[T]) -> usize {
    ret buf.len
}

fn write[T: type](q: *Queue, dst: Buf[T], off: usize, src: []const T) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = slot_of(state, dst.owner, dst.slot, dst.generation)
    if slot_error != ok { ret slot_error }
    let buffer = state.device.buffers[slot]
    if off > buffer.count || src.len > buffer.count - off { ret TooLarge }
    if src.len == 0usize { ret ok }
    let elem = buffer.elem
    mem.copy[u8](buffer.bytes[off * elem..(off + src.len) * elem], host_bytes[T](src))
    ret ok
}

fn token(q: *Queue) -> (Token, err) {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret (zero, state_error) }
    ret (Token { owner: state.device.owner, queue: state.index, serial: state.serial }, ok)
}

fn token_device(token_value: Token) -> (*DeviceState, err) {
    var i = 0usize
    while i < open_count {
        if open_devices[i].owner == token_value.owner {
            if open_devices[i].closed { ret (open_devices[i], InvalidHandle) }
            ret (open_devices[i], ok)
        }
        i += 1usize
    }
    ret (zero, InvalidHandle)
}

fn wait_for(q: *Queue, dependency: Token) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    if dependency.serial == 0u64 { ret ok }
    let (device, device_error) = token_device(dependency)
    if device_error != ok { ret device_error }
    if device.owner != state.device.owner { ret WrongDevice }
    ret ok
}

fn done(token_value: Token) -> (bool, err) {
    if token_value.serial == 0u64 { ret (true, ok) }
    let (_, device_error) = token_device(token_value)
    if device_error != ok { ret (false, device_error) }
    // Every submission on the CPU backend has completed before its launch returned.
    ret (true, ok)
}

fn wait(token_value: Token) -> err {
    let (finished, done_error) = done(token_value)
    if done_error != ok { ret done_error }
    if !finished { ret Lost }
    ret ok
}

fn download[T: type](q: *Queue, src: Buf[T], dst: []T) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = slot_of(state, src.owner, src.slot, src.generation)
    if slot_error != ok { ret slot_error }
    let buffer = state.device.buffers[slot]
    if dst.len < buffer.count { ret TooLarge }
    if buffer.count == 0usize { ret ok }
    mem.copy[u8](host_bytes[T](dst[..buffer.count]), buffer.bytes)
    ret ok
}

fn sync(q: *Queue) -> err {
    let (_, state_error) = queue_state(q)
    ret state_error
}

fn release[T: type](q: *Queue, buf: Buf[T]) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = slot_of(state, buf.owner, buf.slot, buf.generation)
    if slot_error != ok { ret slot_error }
    var empty: []u8 = zero
    state.device.buffers[slot].live = false
    state.device.buffers[slot].generation += 1u32
    state.device.buffers[slot].bytes = empty
    state.device.buffers[slot].count = 0usize
    ret ok
}

fn grid1(x: usize) -> Grid {
    ret Grid { x: x, y: 1usize, z: 1usize }
}

fn grid2(x: usize, y: usize) -> Grid {
    ret Grid { x: x, y: y, z: 1usize }
}

fn grid3(x: usize, y: usize, z: usize) -> Grid {
    ret Grid { x: x, y: y, z: z }
}

// ------------------------------------------------------------------ the launch

const DONE: usize = 4294967295usize

// Workgroups along one axis: the invocation count divided by the workgroup size,
// rounded up; zero invocations is zero workgroups.
fn groups_along(invocations: usize, size: usize) -> (usize, err) {
    if invocations > MAX_AXIS { ret (0usize, TooLarge) }
    if invocations == 0usize { ret (0usize, ok) }
    let groups = (invocations + size - 1usize) / size
    if groups > 65535usize { ret (0usize, TooLarge) }
    ret (groups, ok)
}

// The storage a Buf names, as an address and an element count.
fn launch_view(q: *Queue, owner: u32, slot: u32, generation: u32) -> (usize, usize, err) {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret (0usize, 0usize, state_error) }
    let (index, slot_error) = slot_of(state, owner, slot, generation)
    if slot_error != ok { ret (0usize, 0usize, slot_error) }
    let buffer = state.device.buffers[index]
    if buffer.count == 0usize { ret (0usize, 0usize, ok) }
    ret (mem.address_of(&buffer.bytes[0usize]), buffer.count, ok)
}

fn set_ids(group: usize, local: usize) {
    let lx = local % launch_size[0usize]
    let ly = (local / launch_size[0usize]) % launch_size[1usize]
    let lz = local / (launch_size[0usize] * launch_size[1usize])
    let wx = group % launch_groups[0usize]
    let wy = (group / launch_groups[0usize]) % launch_groups[1usize]
    let wz = group / (launch_groups[0usize] * launch_groups[1usize])
    lid = Id { x: u32(lx), y: u32(ly), z: u32(lz) }
    wgid = Id { x: u32(wx), y: u32(wy), z: u32(wz) }
    gid = Id { x: u32(wx * launch_size[0usize] + lx), y: u32(wy * launch_size[1usize] + ly), z: u32(wz * launch_size[2usize] + lz) }
}

fn frame_pc(frames: []u8, at: usize) -> usize {
    var value = 0usize
    var i = 8usize
    while i > 0usize {
        i -= 1usize
        value = (value << 8usize) | usize(frames[at + i])
    }
    ret value
}

fn write_decimal(out: []u8, at: usize, v: usize) -> usize {
    var digits: [20]u8 = zero
    var n = 0usize
    var rest = v
    if rest == 0usize {
        digits[0usize] = 48u8
        n = 1usize
    }
    while rest > 0usize {
        digits[n] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        n += 1usize
    }
    var i = 0usize
    while i < n {
        out[at + i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret at + n
}

fn write_text(out: []u8, at: usize, text: str) -> usize {
    var i = 0usize
    while i < text.len {
        out[at + i] = text[i]
        i += 1usize
    }
    ret at + text.len
}

fn write_id(out: []u8, at0: usize, group: usize, local: usize) -> usize {
    set_ids(group, local)
    var at = write_text(out, at0, "invocation (")
    at = write_decimal(out, at, usize(gid.x))
    at = write_text(out, at, ", ")
    at = write_decimal(out, at, usize(gid.y))
    at = write_text(out, at, ", ")
    at = write_decimal(out, at, usize(gid.z))
    at = write_text(out, at, ") of workgroup (")
    at = write_decimal(out, at, usize(wgid.x))
    at = write_text(out, at, ", ")
    at = write_decimal(out, at, usize(wgid.y))
    at = write_text(out, at, ", ")
    at = write_decimal(out, at, usize(wgid.z))
    ret write_text(out, at, ")")
}

// The divergence trap (spec section 10): `trap[barrier]: invocation (7, 0, 0) of
// workgroup (3, 0, 0) returned before barrier 1 that invocation (0, 0, 0) reached`,
// or `... reached barrier 2 while invocation (0, 0, 0) reached barrier 1`, written
// to stderr; then the process ends as a trap does.
fn divergence(group: usize, stopped_local: usize, stopped_at: usize, other_local: usize, other_at: usize) {
    var line: [256]u8 = zero
    var at = write_text(line[0..], 0usize, "trap[barrier]: ")
    at = write_id(line[0..], at, group, stopped_local)
    if stopped_at == DONE {
        at = write_text(line[0..], at, " returned before barrier ")
        at = write_decimal(line[0..], at, other_at)
        at = write_text(line[0..], at, " that ")
        at = write_id(line[0..], at, group, other_local)
        at = write_text(line[0..], at, " reached")
    } else {
        at = write_text(line[0..], at, " reached barrier ")
        at = write_decimal(line[0..], at, stopped_at)
        at = write_text(line[0..], at, " while ")
        at = write_id(line[0..], at, group, other_local)
        at = write_text(line[0..], at, " reached barrier ")
        at = write_decimal(line[0..], at, other_at)
    }
    line[at] = 10u8
    at += 1usize
    let error_output = os.stderr()
    let (written, write_error) = os.write(error_output, line[..at])
    os.exit(134i32)
}

// A whole launch on the calling thread: the grid against the kernel's workgroup
// size `(x, y, z)`, one frame of `frame_bytes` per invocation of a workgroup, and
// `step(ctx, frame)` run for every invocation in local-id order, round after round,
// until all have returned -- each round ending at one barrier for all of them.
fn launch_run(q: *Queue, grid: Grid, x: usize, y: usize, z: usize, frame_bytes: usize, shared_bytes: usize, step: fn(ctx: *void, frame: *u8, workgroup: *u8), ctx: *void) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    if launch_active { ret Unsupported }
    if x == 0usize || y == 0usize || z == 0usize || x * y * z > 1024usize { ret Unsupported }
    let (gx, gx_error) = groups_along(grid.x, x)
    if gx_error != ok { ret gx_error }
    let (gy, gy_error) = groups_along(grid.y, y)
    if gy_error != ok { ret gy_error }
    let (gz, gz_error) = groups_along(grid.z, z)
    if gz_error != ok { ret gz_error }
    let per_group = x * y * z
    var bytes_per_frame = frame_bytes
    if bytes_per_frame < 8usize { bytes_per_frame = 8usize }
    bytes_per_frame = (bytes_per_frame + 15usize) / 16usize * 16usize
    let (frames, frames_error) = mem.alloc[u8](state.device.arena, per_group * bytes_per_frame + 16usize)
    if frames_error != ok { ret frames_error }
    // Frames start sixteen-aligned: the arena's cursor may not.
    var base = 0usize
    let misalign = mem.address_of(&frames[0usize]) % 16usize
    if misalign != 0usize { base = 16usize - misalign }
    // The workgroup's shared memory (section 10): 48 KB is every desktop part's
    // limit; filled with 0xCD before every workgroup, so a read before the barrier
    // that publishes it is recognisable.
    if shared_bytes > 49152usize { ret TooLarge }
    var shared_size = shared_bytes
    if shared_size < 16usize { shared_size = 16usize }
    let (shared_storage, shared_error) = mem.alloc[u8](state.device.arena, shared_size + 16usize)
    if shared_error != ok { ret shared_error }
    var shared_base = 0usize
    let shared_misalign = mem.address_of(&shared_storage[0usize]) % 16usize
    if shared_misalign != 0usize { shared_base = 16usize - shared_misalign }
    launch_size[0usize] = x
    launch_size[1usize] = y
    launch_size[2usize] = z
    launch_groups[0usize] = gx
    launch_groups[1usize] = gy
    launch_groups[2usize] = gz
    launch_active = true
    var group = 0usize
    let group_count = gx * gy * gz
    while group < group_count {
        var i = 0usize
        while i < per_group * bytes_per_frame {
            frames[base + i] = 0u8
            i += 1usize
        }
        i = 0usize
        while i < shared_size {
            shared_storage[shared_base + i] = 205u8
            i += 1usize
        }
        while true {
            var any_active = false
            var local = 0usize
            while local < per_group {
                let frame_at = base + local * bytes_per_frame
                if frame_pc(frames, frame_at) != DONE {
                    any_active = true
                    set_ids(group, local)
                    step(ctx, &frames[frame_at], &shared_storage[shared_base])
                }
                local += 1usize
            }
            if !any_active { break }
            // Every invocation still running stands at one barrier; one that
            // returned while others wait, or stopped elsewhere, is divergence.
            var waiting_at = DONE
            var waiting_local = 0usize
            local = 0usize
            while local < per_group {
                let reached = frame_pc(frames, base + local * bytes_per_frame)
                if reached != DONE {
                    if waiting_at == DONE {
                        waiting_at = reached
                        waiting_local = local
                    } else {
                        if reached != waiting_at { divergence(group, local, reached, waiting_local, waiting_at) }
                    }
                }
                local += 1usize
            }
            if waiting_at == DONE { break }
            local = 0usize
            while local < per_group {
                if frame_pc(frames, base + local * bytes_per_frame) == DONE { divergence(group, local, DONE, waiting_local, waiting_at) }
                local += 1usize
            }
        }
        group += 1usize
    }
    launch_active = false
    state.serial += 1u64
    ret ok
}
