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
// every runnable invocation stepped in local-id order until all have returned; before
// each step the ids are set -- this module's `gid`, `lid` and `wgid`, which a kernel
// reads as `gpu.gid.x`. Workgroup barriers wait for the group; subgroup collectives
// wait for their fixed 32-lane subgroup. Divergence within either scope traps here as
// `barrier`, the CPU form of the hang it causes on a device.
// The ids are set for the calling thread's launch only, so launches on two threads
// at once are the caller's race, as is every other use of a queue from two threads
// (section 10: a queue is one thread at a time). ponytail: no lock on the device
// block either; add one when a second thread opens a queue. A launch's frames are
// arena until the device closes; reusing them across launches is the upgrade.
//
// A kernel's `shared var`s live in one block per launch, handed to every step,
// filled with 0xCD before each workgroup (D781).
//
// Subgroup identity and collectives use hardware inputs and operations on Vulkan and
// the fixed 32-lane model on the CPU. A barrier in a helper is not here yet (only the
// kernel's own body is cut). `.Cuda` and a build
// without Vulkan answer `Unsupported`.
//
// The fault buffer (contract section 1.3, D785): a check failing in a kernel's CPU
// build calls `fault`, which writes the queue's one record if none is written yet
// and counts; the invocation is marked faulted and gone. The next `sync` or
// `download` on the queue answers `Fault` once, keeps the record for `last_fault`,
// and clears the count, so the queue keeps accepting work. On the CPU the buffer is
// the queue's own state reached through `launch_queue`, since a launch runs on the
// calling thread; a device gets it as one more argument slot. The CPU build keeps
// its traps for overflow, divide, shift, narrow and slice bounds -- the checks a
// release device build has no record for either.

use e.algo.hash
use e.fs
use e.math
use e.mem
use e.os
use e.str
use e.atomic
use e.gpu.vulkan

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
// Presentation (spec section 10, D791): an image is a device buffer of packed
// 32-bit pixels with a width, a height and a channel order; a target is what a
// frame is presented to -- an offscreen pair of images on every backend, a native
// surface on a driver backend -- and a frame is the image the next present shows.
type Format = enum u8 { Rgba8, Bgra8 }
type Image = struct { data: Buf[u32], width: u32, height: u32, format: Format }
type SurfaceKind = enum u8 { Offscreen, Win32, X11, Wayland, Cocoa }
type Surface = struct { kind: SurfaceKind, handle: *void, context: *void }
type Target = struct { state: *void }
type Frame = struct { image: Image, serial: u64 }
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
error Outdated

const MAX_BUFFERS: usize = 4096usize
const MAX_DEVICES: usize = 16usize
const MAX_QUEUES: usize = 64usize
const MAX_AXIS: usize = 4294967295usize
const SUBGROUP_PC: usize = 1073741824usize
const CPU_CAPABILITIES: usize = 375usize

// One buffer slot: the storage's bytes, the element count and size, and the
// generation a handle has to carry.
// A Vulkan device's buffer is mapped host memory (D1611): `bytes` is the mapping, so a
// write, an upload and a download are the CPU's copies, and `device` is what frees it.
type Buffer = struct { bytes: []u8, count: usize, elem: usize, generation: u32, live: bool, device: vulkan.Buffer }

// A device's state: the CPU's, or a Vulkan device's context and its pipelines, one per
// kernel module and entry it has launched (D1611).
type DeviceState = struct { arena: *mem.Arena, owner: u32, closed: bool, buffers: []Buffer, queues: u32, backend: Backend, context: vulkan.Context, physical: vulkan.Physical, pipeline_modules: [16]usize, pipeline_entries: [16]str, pipelines: [16]vulkan.Pipeline, pipeline_count: usize }

type QueueState = struct { device: *DeviceState, index: u32, serial: u64, fault_count: u32, fault: FaultRecord, last: FaultRecord, has_last: bool }

// An offscreen target: two images, the front one presented, the back one acquired.
type TargetState = struct { queue: *QueueState, images: [2]Image, front: usize, width: u32, height: u32, format: Format, serial: u64, acquired: bool, closed: bool }

// The invocation ids of the launch on the calling thread.
var gid: Id = zero
var lid: Id = zero
var wgid: Id = zero
var sid: u32 = zero
var subgroup_width: u32 = 32u32

var next_owner: u32 = 1u32
var open_devices: [16]*DeviceState = zero
var open_count: usize = 0usize

// The launch in progress: workgroup size, workgroup counts, and whether one is on.
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

fn subgroup_record(value: bool) { subgroup_values[launch_local] = value }

fn subgroup_record32(value: u32, lane: u32) {
    subgroup_words[launch_local] = u64(value)
    subgroup_lanes[launch_local] = lane
}

fn subgroup_record64(value: u64, lane: u32) {
    subgroup_words[launch_local] = value
    subgroup_lanes[launch_local] = lane
}

fn subgroup_failure(bounds: bool) {
    var line: [80]u8 = zero
    var at = 0usize
    if bounds {
        at = write_text(line[0..], at, "trap[bounds]: subgroup source lane is not active\n")
    } else {
        at = write_text(line[0..], at, "trap[barrier]: subgroup broadcast lane is not uniform\n")
    }
    let error_output = os.stderr()
    let (written, write_error) = os.write(error_output, line[..at])
    os.exit(134i32)
}

fn subgroup_exchange(kind: u32) -> u64 {
    let first = launch_local / 32usize * 32usize
    var end = first + 32usize
    let count = launch_size[0usize] * launch_size[1usize] * launch_size[2usize]
    if end > count { end = count }
    let lane = subgroup_lane_snapshot[launch_local]
    if kind == 0u32 {
        var at = first
        while at < end {
            if subgroup_active[at] && subgroup_lane_snapshot[at] != lane { subgroup_failure(false) }
            at += 1usize
        }
    }
    if usize(lane) >= end - first || !subgroup_active[first + usize(lane)] { subgroup_failure(true) }
    ret subgroup_word_snapshot[first + usize(lane)]
}

fn subgroup_exchange32(kind: u32) -> u32 { ret u32(subgroup_exchange(kind)) }
fn subgroup_exchange64(kind: u32) -> u64 { ret subgroup_exchange(kind) }

fn subgroup_begin() -> usize { ret launch_local / 32usize * 32usize }

fn subgroup_end(first: usize) -> usize {
    var end = first + 32usize
    let count = launch_size[0usize] * launch_size[1usize] * launch_size[2usize]
    if end > count { end = count }
    ret end
}

fn subgroup_add_u64(a: u64, b: u64) -> u64 {
    var left = a
    var right = b
    while right != 0u64 {
        let carry = (left & right) << 1u32
        left = left ^ right
        right = carry
    }
    ret left
}

fn subgroup_reduce_u32(kind: u32) -> u32 {
    let first = subgroup_begin()
    let end = subgroup_end(first)
    var result = 0u32
    var seen = false
    var at = first
    while at < end {
        if subgroup_active[at] {
            let value = u32(subgroup_word_snapshot[at] & 4294967295u64)
            if !seen {
                result = value
                seen = true
            } else {
                if kind == 0u32 { result = u32((u64(result) + u64(value)) & 4294967295u64) }
                if kind == 1u32 && value < result { result = value }
                if kind == 2u32 && value > result { result = value }
                if kind == 3u32 { result = result & value }
                if kind == 4u32 { result = result | value }
                if kind == 5u32 { result = result ^ value }
            }
        }
        at += 1usize
    }
    ret result
}

fn subgroup_reduce_i32(kind: u32) -> i32 {
    let first = subgroup_begin()
    let end = subgroup_end(first)
    var bits = 0u32
    var result = 0i32
    var seen = false
    var at = first
    while at < end {
        if subgroup_active[at] {
            let word = u32(subgroup_word_snapshot[at] & 4294967295u64)
            let value = mem.bitcast[i32](word)
            if !seen {
                bits = word
                result = value
                seen = true
            } else {
                if kind == 0u32 { bits = u32((u64(bits) + u64(word)) & 4294967295u64) }
                if kind == 1u32 && value < result { result = value }
                if kind == 2u32 && value > result { result = value }
                if kind == 3u32 { bits = bits & word }
                if kind == 4u32 { bits = bits | word }
                if kind == 5u32 { bits = bits ^ word }
            }
        }
        at += 1usize
    }
    if kind == 1u32 || kind == 2u32 { ret result }
    ret mem.bitcast[i32](bits)
}

fn subgroup_reduce_u64(kind: u32) -> u64 {
    let first = subgroup_begin()
    let end = subgroup_end(first)
    var result = 0u64
    var seen = false
    var at = first
    while at < end {
        if subgroup_active[at] {
            let value = subgroup_word_snapshot[at]
            if !seen {
                result = value
                seen = true
            } else {
                if kind == 0u32 { result = subgroup_add_u64(result, value) }
                if kind == 1u32 && value < result { result = value }
                if kind == 2u32 && value > result { result = value }
                if kind == 3u32 { result = result & value }
                if kind == 4u32 { result = result | value }
                if kind == 5u32 { result = result ^ value }
            }
        }
        at += 1usize
    }
    ret result
}

fn subgroup_reduce_i64(kind: u32) -> i64 {
    let first = subgroup_begin()
    let end = subgroup_end(first)
    var bits = 0u64
    var result = 0i64
    var seen = false
    var at = first
    while at < end {
        if subgroup_active[at] {
            let word = subgroup_word_snapshot[at]
            let value = mem.bitcast[i64](word)
            if !seen {
                bits = word
                result = value
                seen = true
            } else {
                if kind == 0u32 { bits = subgroup_add_u64(bits, word) }
                if kind == 1u32 && value < result { result = value }
                if kind == 2u32 && value > result { result = value }
                if kind == 3u32 { bits = bits & word }
                if kind == 4u32 { bits = bits | word }
                if kind == 5u32 { bits = bits ^ word }
            }
        }
        at += 1usize
    }
    if kind == 1u32 || kind == 2u32 { ret result }
    ret mem.bitcast[i64](bits)
}

fn subgroup_reduce_f32(kind: u32) -> f32 {
    let first = subgroup_begin()
    let end = subgroup_end(first)
    var values: [32]f32 = zero
    var count = 0usize
    var at = first
    while at < end {
        if subgroup_active[at] {
            values[count] = mem.bitcast[f32](u32(subgroup_word_snapshot[at] & 4294967295u64))
            count += 1usize
        }
        at += 1usize
    }
    while count > 1usize {
        var source_at = 0usize
        var out_at = 0usize
        while source_at + 1usize < count {
            var value = values[source_at] + values[source_at + 1usize]
            if kind == 1u32 { value = math.min[f32](values[source_at], values[source_at + 1usize]) }
            if kind == 2u32 { value = math.max[f32](values[source_at], values[source_at + 1usize]) }
            values[out_at] = value
            source_at += 2usize
            out_at += 1usize
        }
        if source_at < count {
            values[out_at] = values[source_at]
            out_at += 1usize
        }
        count = out_at
    }
    ret values[0usize]
}

fn subgroup_reduce_f64(kind: u32) -> f64 {
    let first = subgroup_begin()
    let end = subgroup_end(first)
    var values: [32]f64 = zero
    var count = 0usize
    var at = first
    while at < end {
        if subgroup_active[at] {
            values[count] = mem.bitcast[f64](subgroup_word_snapshot[at])
            count += 1usize
        }
        at += 1usize
    }
    while count > 1usize {
        var source_at = 0usize
        var out_at = 0usize
        while source_at + 1usize < count {
            var value = values[source_at] + values[source_at + 1usize]
            if kind == 1u32 { value = math.min[f64](values[source_at], values[source_at + 1usize]) }
            if kind == 2u32 { value = math.max[f64](values[source_at], values[source_at + 1usize]) }
            values[out_at] = value
            source_at += 2usize
            out_at += 1usize
        }
        if source_at < count {
            values[out_at] = values[source_at]
            out_at += 1usize
        }
        count = out_at
    }
    ret values[0usize]
}

fn subgroup_vote(kind: u32) -> u64 {
    let first = launch_local / 32usize * 32usize
    var end = first + 32usize
    let count = launch_size[0usize] * launch_size[1usize] * launch_size[2usize]
    if end > count { end = count }
    var result = 0u64
    if kind == 0u32 { result = 1u64 }
    var at = first
    while at < end {
        if subgroup_active[at] {
            if kind == 0u32 && !subgroup_snapshot[at] { result = 0u64 }
            if kind == 1u32 && subgroup_snapshot[at] { result = 1u64 }
            if kind == 2u32 && subgroup_snapshot[at] { result = result | (1u64 << u32(at - first)) }
        }
        at += 1usize
    }
    ret result
}

fn capability_bit(capability: Cap) -> usize {
    if capability == .Int8 { ret 1usize }
    if capability == .Int16 { ret 2usize }
    if capability == .Int64 { ret 4usize }
    if capability == .Float16 { ret 8usize }
    if capability == .Float64 { ret 16usize }
    if capability == .Atomic64 { ret 32usize }
    if capability == .Subgroup { ret 64usize }
    if capability == .Ftz { ret 128usize }
    ret 256usize
}

fn capability_list(a: *mem.Arena, bits: usize) -> ([]const Cap, err) {
    var count = 0usize
    var bit = 1usize
    while bit <= 256usize {
        if (bits & bit) != 0usize { count += 1usize }
        bit = bit * 2usize
    }
    let (caps, caps_error) = mem.alloc[Cap](a, count)
    if caps_error != ok { ret (zero, caps_error) }
    var at = 0usize
    if (bits & 1usize) != 0usize {
        caps[at] = .Int8
        at += 1usize
    }
    if (bits & 2usize) != 0usize {
        caps[at] = .Int16
        at += 1usize
    }
    if (bits & 4usize) != 0usize {
        caps[at] = .Int64
        at += 1usize
    }
    if (bits & 8usize) != 0usize {
        caps[at] = .Float16
        at += 1usize
    }
    if (bits & 16usize) != 0usize {
        caps[at] = .Float64
        at += 1usize
    }
    if (bits & 32usize) != 0usize {
        caps[at] = .Atomic64
        at += 1usize
    }
    if (bits & 64usize) != 0usize {
        caps[at] = .Subgroup
        at += 1usize
    }
    if (bits & 128usize) != 0usize {
        caps[at] = .Ftz
        at += 1usize
    }
    if (bits & 256usize) != 0usize { caps[at] = .DenormPreserve }
    ret (caps, ok)
}

fn cpu_capabilities(a: *mem.Arena) -> ([]const Cap, err) {
    let (caps, caps_error) = capability_list(a, CPU_CAPABILITIES)
    ret (caps, caps_error)
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

// A Vulkan device as `devices` and `info` report it (D1611): its name, kind, memory and
// whether section 10's floor holds on it. Its key is the one D83 defers to C093.
fn vulkan_info(a: *mem.Arena, physical: vulkan.Physical, index: u32) -> (DeviceInfo, err) {
    var record: DeviceInfo = zero
    let (caps, caps_error) = capability_list(a, physical.caps)
    if caps_error != ok { ret (record, caps_error) }
    record.key.backend = .Vulkan
    record.key_valid = false
    record.index = index
    record.name = physical.name
    record.kind = .Other
    if physical.device_type == 1u32 { record.kind = .Integrated }
    if physical.device_type == 2u32 { record.kind = .Discrete }
    if physical.device_type == 3u32 { record.kind = .Virtual }
    if physical.device_type == 4u32 { record.kind = .Cpu }
    record.memory_bytes = physical.memory_bytes
    record.memory_known = true
    record.capabilities = caps
    record.supported = physical.floor
    ret (record, ok)
}

fn devices(a: *mem.Arena, backend: Backend, limit: usize) -> ([]const DeviceInfo, err) {
    if backend == .Vulkan {
        let (found, found_error) = vulkan.devices(a, limit)
        if found_error == vulkan.NoLoader || found_error == vulkan.NoDevice { ret (zero, NoDevice) }
        if found_error != ok { ret (zero, Lost) }
        let (records, records_error) = mem.alloc[DeviceInfo](a, found.len)
        if records_error != ok { ret (zero, records_error) }
        var at = 0usize
        while at < found.len {
            let (record, record_error) = vulkan_info(a, found[at], u32(at))
            if record_error != ok { ret (zero, record_error) }
            records[at] = record
            at += 1usize
        }
        ret (records, ok)
    }
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
    if backend == .Vulkan {
        let (device, device_error) = open_vulkan(a, index)
        ret (device, device_error)
    }
    if backend != .Cpu { ret (zero, Unsupported) }
    if index != 0u32 { ret (zero, NoDevice) }
    let (device, device_error) = open_state(a, .Cpu)
    ret (device, device_error)
}

// The `index`th Vulkan device (D1611): `NoDevice` without a loader or with fewer devices,
// `Unsupported` below section 10's floor.
fn open_vulkan(a: *mem.Arena, index: u32) -> (*Device, err) {
    let (found, found_error) = vulkan.devices(a, MAX_DEVICES)
    if found_error == vulkan.NoLoader || found_error == vulkan.NoDevice { ret (zero, NoDevice) }
    if found_error != ok { ret (zero, Lost) }
    if usize(index) >= found.len { ret (zero, NoDevice) }
    let physical = found[usize(index)]
    if !physical.floor { ret (zero, Unsupported) }
    let (context, context_error) = vulkan.open(a, physical)
    if context_error == vulkan.Unsupported { ret (zero, Unsupported) }
    if context_error != ok { ret (zero, Lost) }
    let (device, device_error) = open_state(a, .Vulkan)
    if device_error != ok {
        vulkan.close(context)
        ret (zero, device_error)
    }
    let (state, state_error) = state_of(device)
    if state_error != ok { ret (zero, state_error) }
    state.context = context
    state.physical = physical
    ret (device, ok)
}

fn open_state(a: *mem.Arena, backend: Backend) -> (*Device, err) {
    if open_count >= MAX_DEVICES { ret (zero, TooLarge) }
    let (states, states_error) = mem.alloc[DeviceState](a, 1usize)
    if states_error != ok { ret (zero, states_error) }
    let (buffers, buffers_error) = mem.alloc[Buffer](a, MAX_BUFFERS)
    if buffers_error != ok { ret (zero, buffers_error) }
    var empty: []u8 = zero
    var i = 0usize
    while i < MAX_BUFFERS {
        buffers[i] = Buffer { bytes: empty, count: 0usize, elem: 0usize, generation: 1u32, live: false, device: zero }
        i += 1usize
    }
    let state = &states[0usize]
    state.arena = a
    state.owner = next_owner
    state.closed = false
    state.buffers = buffers
    state.queues = 0u32
    state.backend = backend
    var no_context: vulkan.Context = zero
    var no_physical: vulkan.Physical = zero
    state.context = no_context
    state.physical = no_physical
    state.pipeline_count = 0usize
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
    let (state, state_error) = state_of(device)
    if state_error != ok { ret (zero, state_error) }
    if state.backend == .Vulkan {
        let (record, record_error) = vulkan_info(a, state.physical, 0u32)
        ret (record, record_error)
    }
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
            if state.backend == .Vulkan { vulkan.free(state.context, state.buffers[i].device) }
            state.buffers[i].live = false
            state.buffers[i].generation += 1u32
        }
        i += 1usize
    }
    if state.backend == .Vulkan {
        var made = 0usize
        while made < state.pipeline_count {
            vulkan.destroy(state.context, state.pipelines[made])
            made += 1usize
        }
        vulkan.close(state.context)
    }
    ret ok
}

fn has(device: *Device, capability: Cap) -> bool {
    let (state, state_error) = state_of(device)
    if state_error != ok { ret false }
    var available = CPU_CAPABILITIES
    if state.backend == .Vulkan { available = state.physical.caps }
    ret (available & capability_bit(capability)) != 0usize
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
    states[0usize] = QueueState { device: state, index: state.queues, serial: 0u64, fault_count: 0u32, fault: zero, last: zero, has_last: false }
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
    let generation = state.device.buffers[slot].generation
    // A Vulkan buffer's bytes are its mapping (D1611).
    if state.device.backend == .Vulkan {
        let (made, made_error) = vulkan.buffer(a, state.device.context, n * elem)
        if made_error != ok { ret (zero, OutOfMemory) }
        state.device.buffers[slot] = Buffer { bytes: made.bytes, count: n, elem: elem, generation: generation, live: true, device: made }
        ret (Buf[T] { owner: state.device.owner, slot: u32(slot), generation: generation, len: n }, ok)
    }
    let (storage, storage_error) = mem.alloc[T](a, n)
    if storage_error != ok { ret (zero, storage_error) }
    // The storage is the arena's top: its bytes are the last `n * elem` allocated.
    var bytes: []u8 = zero
    if n > 0usize { bytes = mem.view(a, a.off - n * elem, n * elem) }
    state.device.buffers[slot] = Buffer { bytes: bytes, count: n, elem: elem, generation: generation, live: true, device: zero }
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
        if state.device.backend == .Vulkan { vulkan.free(state.device.context, state.device.buffers[usize(buf.slot)].device) }
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
    copy_bytes(buffer.bytes[off * elem..(off + src.len) * elem], host_bytes[T](src))
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

// The queue's fault, reported once: `Fault`, the record kept for `last_fault`.
fn report_fault(state: *QueueState) -> err {
    if state.fault_count == 0u32 { ret ok }
    state.last = state.fault
    state.has_last = true
    state.fault_count = 0u32
    ret Fault
}

// The record behind the last `Fault` this queue answered; `false` before one.
fn last_fault(q: *Queue) -> (FaultRecord, bool) {
    let (state, state_error) = queue_state(q)
    if state_error != ok || !state.has_last { ret (zero, false) }
    ret (state.last, true)
}

// Called from a kernel's fault path (D785): `kind` is the `FaultKind` value.
fn fault(kind: u32, site: u32) {
    if !launch_active { ret }
    let state = launch_queue
    state.fault_count += 1u32
    if state.fault_count != 1u32 { ret }
    var fault_kind: FaultKind = .Bounds
    if kind == 1u32 { fault_kind = .Null }
    if kind == 2u32 { fault_kind = .Tag }
    if kind == 3u32 { fault_kind = .Alignment }
    if kind == 4u32 { fault_kind = .Overflow }
    if kind == 5u32 { fault_kind = .DivideByZero }
    state.fault = FaultRecord { kernel: u32(state.serial), kind: fault_kind, site: site, gid: gid }
}

// A byte copy eight at a time: `mem.copy[u8]` moves a byte per iteration, and a
// frame's download through it was a quarter of the frame (D914).
fn copy_bytes(dst: []u8, src: []const u8) {
    var count = src.len
    if dst.len < count { count = dst.len }
    var at = 0usize
    while at + 8usize <= count {
        let to = mem.cast[*u64](&dst[at])
        let from = mem.cast[*const u64](&src[at])
        *to = *from
        at += 8usize
    }
    while at < count {
        dst[at] = src[at]
        at += 1usize
    }
}

fn download[T: type](q: *Queue, src: Buf[T], dst: []T) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    try report_fault(state)
    let (slot, slot_error) = slot_of(state, src.owner, src.slot, src.generation)
    if slot_error != ok { ret slot_error }
    let buffer = state.device.buffers[slot]
    if dst.len < buffer.count { ret TooLarge }
    if buffer.count == 0usize { ret ok }
    copy_bytes(host_bytes[T](dst[..buffer.count]), buffer.bytes)
    ret ok
}

fn sync(q: *Queue) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    ret report_fault(state)
}

fn release[T: type](q: *Queue, buf: Buf[T]) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = slot_of(state, buf.owner, buf.slot, buf.generation)
    if slot_error != ok { ret slot_error }
    var empty: []u8 = zero
    if state.device.backend == .Vulkan { vulkan.free(state.device.context, state.device.buffers[slot].device) }
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

// ------------------------------------------------------------ presentation

const MAX_IMAGE_SIDE: u32 = 16384u32

fn image(q: *Queue, width: u32, height: u32, format: Format) -> (Image, err) {
    if width == 0u32 || height == 0u32 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE { ret (zero, TooLarge) }
    let (data, data_error) = alloc[u32](q, usize(width) * usize(height))
    if data_error != ok { ret (zero, data_error) }
    ret (Image { data: data, width: width, height: height, format: format }, ok)
}

// `src` is `width * height` pixels, row-major and tightly packed, written at (x, y).
fn write_image(q: *Queue, dst: Image, x: u32, y: u32, width: u32, height: u32, src: []const u32) -> err {
    if x > dst.width || width > dst.width - x || y > dst.height || height > dst.height - y { ret TooLarge }
    if src.len != usize(width) * usize(height) { ret TooLarge }
    var row = 0usize
    while row < usize(height) {
        let at = (usize(y) + row) * usize(dst.width) + usize(x)
        try write[u32](q, dst.data, at, src[row * usize(width)..(row + 1usize) * usize(width)])
        row += 1usize
    }
    ret ok
}

fn read_image(q: *Queue, src: Image, dst: []u32) -> err {
    ret download[u32](q, src.data, dst)
}

fn release_image(q: *Queue, img: Image) -> err {
    ret release[u32](q, img.data)
}

fn target_state(t: *Target) -> (*TargetState, err) {
    let state = mem.cast[*TargetState](t.state)
    if mem.address_of(state) == 0usize || state.closed { ret (zero, InvalidHandle) }
    let (_, queue_error) = queue_state_of(state.queue)
    if queue_error != ok { ret (state, queue_error) }
    ret (state, ok)
}

fn queue_state_of(state: *QueueState) -> (*QueueState, err) {
    if state.device.closed { ret (state, InvalidHandle) }
    ret (state, ok)
}

fn target_images(state: *TargetState, width: u32, height: u32) -> err {
    var handle = Queue { state: mem.cast[*void](state.queue) }
    let (front, front_error) = image(&handle, width, height, state.format)
    if front_error != ok { ret front_error }
    let (back, back_error) = image(&handle, width, height, state.format)
    if back_error != ok {
        let abandoned = release_image(&handle, front)
        ret back_error
    }
    state.images[0usize] = front
    state.images[1usize] = back
    state.width = width
    state.height = height
    ret ok
}

// A native surface needs a driver backend; the CPU device presents offscreen only.
fn open_target(q: *Queue, surface: Surface, width: u32, height: u32, format: Format) -> (*Target, err) {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret (zero, state_error) }
    if surface.kind != .Offscreen { ret (zero, Unsupported) }
    let (states, states_error) = mem.alloc[TargetState](state.device.arena, 1usize)
    if states_error != ok { ret (zero, states_error) }
    states[0usize] = TargetState { queue: state, images: zero, front: 0usize, width: 0u32, height: 0u32, format: format, serial: 0u64, acquired: false, closed: false }
    let images_error = target_images(&states[0usize], width, height)
    if images_error != ok { ret (zero, images_error) }
    let (handles, handles_error) = mem.alloc[Target](state.device.arena, 1usize)
    if handles_error != ok { ret (zero, handles_error) }
    handles[0usize] = Target { state: mem.cast[*void](&states[0usize]) }
    ret (&handles[0usize], ok)
}

fn extent(t: *Target) -> (u32, u32) {
    let (state, state_error) = target_state(t)
    if state_error != ok { ret (0u32, 0u32) }
    ret (state.width, state.height)
}

// The images are remade at the new size; an acquired frame is dropped.
fn resize(t: *Target, width: u32, height: u32) -> err {
    let (state, state_error) = target_state(t)
    if state_error != ok { ret state_error }
    var handle = Queue { state: mem.cast[*void](state.queue) }
    try release_image(&handle, state.images[0usize])
    try release_image(&handle, state.images[1usize])
    state.acquired = false
    ret target_images(state, width, height)
}

// The back image, to draw the next frame into; one frame in flight, so a second
// acquire before its present is `InvalidHandle`.
fn acquire(t: *Target) -> (Frame, err) {
    let (state, state_error) = target_state(t)
    if state_error != ok { ret (zero, state_error) }
    if state.acquired { ret (zero, InvalidHandle) }
    state.acquired = true
    ret (Frame { image: state.images[1usize - state.front], serial: state.serial }, ok)
}

// Orders the present behind every submission on `q`, swaps the images, and answers
// the token of the work it waited for. A frame that is not the acquired one is stale.
fn present(q: *Queue, t: *Target, frame: Frame) -> (Token, err) {
    let (state, state_error) = target_state(t)
    if state_error != ok { ret (zero, state_error) }
    let (presenter, presenter_error) = queue_state(q)
    if presenter_error != ok { ret (zero, presenter_error) }
    if presenter.device.owner != state.queue.device.owner { ret (zero, WrongDevice) }
    if !state.acquired || frame.serial != state.serial { ret (zero, InvalidHandle) }
    let sync_error = sync(q)
    if sync_error != ok { ret (zero, sync_error) }
    state.front = 1usize - state.front
    state.serial += 1u64
    state.acquired = false
    let (shown, token_error) = token(q)
    ret (shown, token_error)
}

// The last presented image, for a snapshot; a native surface has none to answer.
fn presented(t: *Target) -> (Image, err) {
    let (state, state_error) = target_state(t)
    if state_error != ok { ret (zero, state_error) }
    if state.serial == 0u64 { ret (zero, InvalidHandle) }
    ret (state.images[state.front], ok)
}

fn close_target(t: *Target) -> err {
    let (state, state_error) = target_state(t)
    if state_error != ok { ret state_error }
    var handle = Queue { state: mem.cast[*void](state.queue) }
    try release_image(&handle, state.images[0usize])
    try release_image(&handle, state.images[1usize])
    state.closed = true
    ret ok
}

// ------------------------------------------------------------------ the launch

const DONE: usize = 4294967295usize
// A faulted invocation's mark: gone, and not divergence.
const FAULTED: usize = 4294967294usize

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
    // A Vulkan buffer crosses as its device address (D1611).
    if state.device.backend == .Vulkan { ret (usize(buffer.device.address), buffer.count, ok) }
    if buffer.count == 0usize { ret (0usize, 0usize, ok) }
    ret (mem.address_of(&buffer.bytes[0usize]), buffer.count, ok)
}

// A launch on a Vulkan device (D1611): the launcher's block -- sixteen bytes a parameter,
// a scalar's bytes or a slice's device address and length -- laid out again as D1610's
// argument block in a buffer of its own. Checked embedded module text starts with `!`:
// its hidden first u64 is a mapped fault buffer's device address; the pipeline sees the
// hex after it.
// A kernel the emitter could not
// write has no module and is `Unsupported` here; the CPU still runs it.
fn launch_device(state: *QueueState, grid: Grid, x: usize, y: usize, z: usize, ctx: *void, module: str, entry: str, layout: str) -> err {
    if module.len == 0usize { ret Unsupported }
    let (gx, gx_error) = groups_along(grid.x, x)
    if gx_error != ok { ret gx_error }
    let (gy, gy_error) = groups_along(grid.y, y)
    if gy_error != ok { ret gy_error }
    let (gz, gz_error) = groups_along(grid.z, z)
    if gz_error != ok { ret gz_error }
    if gx > 65535usize || gy > 65535usize || gz > 65535usize { ret TooLarge }
    if gx == 0usize || gy == 0usize || gz == 0usize { ret ok }
    let device = state.device
    let a = device.arena
    let checked = module[0usize] == 33u8
    var module_code = module
    if checked { module_code = module[1usize..] }
    let parameter_count = layout.len
    var over: mem.Arena = zero
    over.base = mem.cast[*u8](ctx)
    over.cap = 16usize * parameter_count
    over.off = 16usize * parameter_count
    let source = mem.view(&over, 0usize, 16usize * parameter_count)
    let (block, block_error) = vulkan.buffer(a, device.context, 16usize * parameter_count + 24usize)
    if block_error != ok { ret OutOfMemory }
    var offset = 0usize
    var fault_buffer: vulkan.Buffer = zero
    if checked {
        let (made_fault, fault_error) = vulkan.buffer(a, device.context, 32usize)
        if fault_error != ok {
            vulkan.free(device.context, block)
            ret OutOfMemory
        }
        fault_buffer = made_fault
        var clear_at = 0usize
        while clear_at < fault_buffer.bytes.len {
            fault_buffer.bytes[clear_at] = 0u8
            clear_at += 1usize
        }
        *mem.cast[*u64](&block.bytes[0usize]) = fault_buffer.address
        *mem.cast[*u32](&fault_buffer.bytes[4usize]) = u32(state.serial)
        offset = 8usize
    }
    var at = 0usize
    var source_at = 0usize
    while at < layout.len {
        if layout[at] != 115u8 && (layout[at] < 49u8 || layout[at] > 56u8) {
            if checked { vulkan.free(device.context, fault_buffer) }
            vulkan.free(device.context, block)
            ret Unsupported
        }
        let code = usize(layout[at]) - 48usize
        if layout[at] == 115u8 {
            offset = (offset + 7usize) / 8usize * 8usize
            copy_bytes(block.bytes[offset..offset + 8usize], source[16usize * source_at..16usize * source_at + 8usize])
            copy_bytes(block.bytes[offset + 8usize..offset + 12usize], source[16usize * source_at + 8usize..16usize * source_at + 12usize])
            offset += 16usize
        } else {
            offset = (offset + code - 1usize) / code * code
            copy_bytes(block.bytes[offset..offset + code], source[16usize * source_at..16usize * source_at + code])
            offset += code
        }
        at += 1usize
        source_at += 1usize
    }
    let (made, made_error) = device_pipeline(device, module_code, entry)
    if made_error != ok {
        if checked { vulkan.free(device.context, fault_buffer) }
        vulkan.free(device.context, block)
        ret made_error
    }
    let dispatch_error = vulkan.dispatch(a, device.context, made, block.address, u32(gx), u32(gy), u32(gz))
    vulkan.free(device.context, block)
    if dispatch_error != ok {
        if checked { vulkan.free(device.context, fault_buffer) }
        ret Lost
    }
    if checked {
        let count = *mem.cast[*u32](&fault_buffer.bytes[0usize])
        if count != 0u32 {
            if state.fault_count == 0u32 {
                var kind: FaultKind = .Bounds
                let kind_value = fault_buffer.bytes[8usize]
                if kind_value == 1u8 { kind = .Null }
                if kind_value == 2u8 { kind = .Tag }
                if kind_value == 3u8 { kind = .Alignment }
                if kind_value == 4u8 { kind = .Overflow }
                if kind_value == 5u8 { kind = .DivideByZero }
                state.fault = FaultRecord {
                    kernel: *mem.cast[*u32](&fault_buffer.bytes[4usize]),
                    kind: kind,
                    site: *mem.cast[*u32](&fault_buffer.bytes[12usize]),
                    gid: Id {
                        x: *mem.cast[*u32](&fault_buffer.bytes[16usize]),
                        y: *mem.cast[*u32](&fault_buffer.bytes[20usize]),
                        z: *mem.cast[*u32](&fault_buffer.bytes[24usize]),
                    },
                }
            }
            state.fault_count += count
        }
        vulkan.free(device.context, fault_buffer)
    }
    state.serial += 1u64
    ret ok
}

// The pipeline for a kernel's module and entry on this device, made the first time.
fn device_pipeline(device: *DeviceState, module: str, entry: str) -> (vulkan.Pipeline, err) {
    let key = mem.address_of(&module[0usize])
    var at = 0usize
    while at < device.pipeline_count {
        if device.pipeline_modules[at] == key && device.pipeline_entries[at].len == entry.len {
            var same = true
            var k = 0usize
            while k < entry.len {
                if device.pipeline_entries[at][k] != entry[k] { same = false }
                k += 1usize
            }
            if same { ret (device.pipelines[at], ok) }
        }
        at += 1usize
    }
    if device.pipeline_count >= 16usize { ret (zero, TooLarge) }
    let (code, code_error) = hex_bytes(device.arena, module)
    if code_error != ok { ret (zero, code_error) }
    let cache_key = pipeline_cache_key(device.physical, code, entry)
    var cached: []u8 = zero
    let (cache_path, path_error) = pipeline_cache_path(device.arena, cache_key)
    if path_error == ok { cached = pipeline_cache_read(device.arena, cache_path, cache_key) }
    let (made, refreshed, made_error) = vulkan.pipeline(device.arena, device.context, code, entry, cached)
    if made_error != ok { ret (made, Unsupported) }
    if path_error == ok { pipeline_cache_publish(device.arena, cache_path, cache_key, refreshed) }
    device.pipeline_modules[device.pipeline_count] = key
    device.pipeline_entries[device.pipeline_count] = entry
    device.pipelines[device.pipeline_count] = made
    device.pipeline_count += 1usize
    ret (made, ok)
}

// Vulkan's blob is local optimisation state. The embedded SPIR-V hash carries the
// launch specialisation, capability, numerical, safety and build-mode choices that
// changed its code; the remaining bytes distinguish the entry and driver device.
fn pipeline_cache_key(physical: vulkan.Physical, code: []const u8, entry: str) -> u64 {
    let kernel = hash.xxhash64(code, 0u64)
    var fields: [40]u8 = zero
    cache_put_u64(fields[..], 0usize, kernel)
    cache_put_u64(fields[..], 8usize, u64(entry.len))
    cache_put_u32(fields[..], 16usize, physical.driver_version)
    cache_put_u32(fields[..], 20usize, physical.api_version)
    cache_put_u32(fields[..], 24usize, physical.vendor)
    cache_put_u32(fields[..], 28usize, physical.device)
    cache_put_u64(fields[..], 32usize, u64(physical.caps))
    var identity = hash.xxhash64_init(0u64)
    hash.xxhash64_update(&identity, "vulkan")
    hash.xxhash64_update(&identity, fields[..])
    hash.xxhash64_update(&identity, physical.uuid[..])
    hash.xxhash64_update(&identity, entry)
    ret hash.xxhash64_done(&identity)
}

fn pipeline_cache_path(a: *mem.Arena, key: u64) -> (str, err) {
    let (override_root, overridden) = fs.env_directory(a, "NEPER_GPU_CACHE")
    var base = override_root
    var suffix = "/v1"
    if !overridden {
        var variable = "XDG_CACHE_HOME"
        if os.NATIVE_SEPARATOR == 92u8 { variable = "LOCALAPPDATA" }
        let (platform_root, platform_found) = fs.env_directory(a, variable)
        base = platform_root
        suffix = "/neper/gpu/v1"
        if !platform_found {
            let (home, home_error) = fs.home_dir(a)
            if home_error != ok { ret ("", home_error) }
            base = home
            suffix = "/.cache/neper/gpu/v1"
        }
    }
    let (directory, directory_error) = str.concat(a, base, suffix)
    if directory_error != ok { ret ("", directory_error) }
    let made_error = fs.make_dirs(a, directory)
    if made_error != ok { ret ("", made_error) }
    var (path, builder_error) = str.builder(a, directory.len + 22usize)
    if builder_error != ok { ret ("", builder_error) }
    try str.push(&path, directory)
    try str.push(&path, "/")
    try str.push_hex_u64(&path, key)
    try str.push(&path, ".bin")
    ret (str.done(&path), ok)
}

fn pipeline_cache_read(a: *mem.Arena, path: str, key: u64) -> []u8 {
    var none: []u8 = zero
    let (file, file_error) = fs.read_file(a, path, 67108892usize)
    if file_error != ok || file.len < 28usize { ret none }
    let magic = "NEPGPU01"
    var at = 0usize
    while at < magic.len {
        if file[at] != magic[at] { ret none }
        at += 1usize
    }
    let blob = file[28usize..]
    if cache_u64(file, 8usize) != key || cache_u64(file, 16usize) != u64(blob.len) { ret none }
    if cache_u32(file, 24usize) != hash.crc32c(blob) { ret none }
    ret blob
}

fn pipeline_cache_publish(a: *mem.Arena, path: str, key: u64, blob: []const u8) {
    if blob.len == 0usize || blob.len > 67108864usize { ret }
    let (file, file_error) = mem.alloc[u8](a, 28usize + blob.len)
    if file_error != ok { ret }
    copy_bytes(file[0usize..8usize], "NEPGPU01")
    cache_put_u64(file, 8usize, key)
    cache_put_u64(file, 16usize, u64(blob.len))
    cache_put_u32(file, 24usize, hash.crc32c(blob))
    copy_bytes(file[28usize..], blob)
    var (temporary, temporary_error) = str.builder(a, path.len + 32usize)
    if temporary_error != ok { ret }
    if str.push(&temporary, path) != ok || str.push(&temporary, ".tmp-") != ok || str.push_usize(&temporary, os.current_thread_id()) != ok { ret }
    let temporary_path = str.done(&temporary)
    if fs.write_file(a, temporary_path, file) != ok {
        let removed = fs.remove_file(a, temporary_path)
        ret
    }
    var options: fs.ReplaceOptions = zero
    options.overwrite = true
    options.durable = true
    if fs.replace(a, temporary_path, path, options) != ok {
        let removed = fs.remove_file(a, temporary_path)
    }
}

fn cache_put_u32(bytes: []u8, at: usize, value: u32) {
    var rest = value
    var k = 0usize
    while k < 4usize {
        bytes[at + k] = u8(rest & 255u32)
        rest = rest >> 8u32
        k += 1usize
    }
}

fn cache_put_u64(bytes: []u8, at: usize, value: u64) {
    var rest = value
    var k = 0usize
    while k < 8usize {
        bytes[at + k] = u8(rest & 255u64)
        rest = rest >> 8u32
        k += 1usize
    }
}

fn cache_u32(bytes: []const u8, at: usize) -> u32 {
    ret u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32) | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn cache_u64(bytes: []const u8, at: usize) -> u64 {
    ret u64(cache_u32(bytes, at)) | (u64(cache_u32(bytes, at + 4usize)) << 32u32)
}

// A kernel's module back from its hex digits (D1611).
fn hex_bytes(a: *mem.Arena, digits: str) -> ([]u8, err) {
    if digits.len % 2usize != 0usize { ret (zero, Unsupported) }
    let (bytes, bytes_error) = mem.alloc[u8](a, digits.len / 2usize)
    if bytes_error != ok { ret (zero, bytes_error) }
    var at = 0usize
    while at < bytes.len {
        let high = hex_digit(digits[2usize * at])
        let low = hex_digit(digits[2usize * at + 1usize])
        if high > 15usize || low > 15usize { ret (zero, Unsupported) }
        bytes[at] = u8(high * 16usize + low)
        at += 1usize
    }
    ret (bytes, ok)
}

fn hex_digit(digit: u8) -> usize {
    if digit >= 48u8 && digit <= 57u8 { ret usize(digit) - 48usize }
    if digit >= 97u8 && digit <= 102u8 { ret usize(digit) - 87usize }
    ret 16usize
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
    sid = u32(local % 32usize)
    launch_local = local
}

fn subgroup_wait(pc: usize) -> bool { ret pc >= SUBGROUP_PC && pc < FAULTED }

fn subgroup_ready(frames: []u8, base: usize, bytes_per_frame: usize, per_group: usize, local: usize, pc: usize) -> bool {
    let first = local / 32usize * 32usize
    var end = first + 32usize
    if end > per_group { end = per_group }
    var at = first
    while at < end {
        let reached = frame_pc(frames, base + at * bytes_per_frame)
        if reached != FAULTED && reached != pc { ret false }
        at += 1usize
    }
    ret true
}

fn workgroup_ready(frames: []u8, base: usize, bytes_per_frame: usize, per_group: usize, pc: usize) -> bool {
    var at = 0usize
    while at < per_group {
        let reached = frame_pc(frames, base + at * bytes_per_frame)
        if reached != FAULTED && reached != pc { ret false }
        at += 1usize
    }
    ret true
}

fn barrier_number(pc: usize) -> usize {
    if subgroup_wait(pc) { ret pc - SUBGROUP_PC }
    ret pc
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
        at = write_decimal(line[0..], at, barrier_number(other_at))
        at = write_text(line[0..], at, " that ")
        at = write_id(line[0..], at, group, other_local)
        at = write_text(line[0..], at, " reached")
    } else {
        at = write_text(line[0..], at, " reached barrier ")
        at = write_decimal(line[0..], at, barrier_number(stopped_at))
        at = write_text(line[0..], at, " while ")
        at = write_id(line[0..], at, group, other_local)
        at = write_text(line[0..], at, " reached barrier ")
        at = write_decimal(line[0..], at, barrier_number(other_at))
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
// `module`, `entry` and `layout` are the kernel's for a Vulkan device (D1611): its
// SPIR-V as hex digits, its entry point, and a character per parameter -- `s` a slice,
// `1` to `8` a scalar's size in bytes, `?` what the argument block cannot carry yet. The
// CPU ignores them.
fn launch_run(q: *Queue, grid: Grid, x: usize, y: usize, z: usize, frame_bytes: usize, shared_bytes: usize, step: fn(opaque: *void, frame: *u8, workgroup: *u8), ctx: *void, requirements: usize, module: str, entry: str, layout: str) -> err {
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    var available = CPU_CAPABILITIES
    if state.device.backend == .Vulkan { available = state.device.physical.caps }
    if (requirements & available) != requirements { ret Unsupported }
    if state.device.backend == .Vulkan { ret launch_device(state, grid, x, y, z, ctx, module, entry, layout) }
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
    launch_queue = state
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
        var runnable: [1024]bool = zero
        while true {
            var any_active = false
            var any_runnable = false
            var local = 0usize
            while local < per_group {
                let pc = frame_pc(frames, base + local * bytes_per_frame)
                runnable[local] = false
                if pc != DONE && pc != FAULTED {
                    any_active = true
                    if pc == 0usize { runnable[local] = true }
                    if subgroup_wait(pc) { runnable[local] = subgroup_ready(frames, base, bytes_per_frame, per_group, local, pc) }
                    if pc != 0usize && !subgroup_wait(pc) { runnable[local] = workgroup_ready(frames, base, bytes_per_frame, per_group, pc) }
                    if runnable[local] { any_runnable = true }
                }
                local += 1usize
            }
            if !any_active { break }
            if !any_runnable {
                var waiting_at = DONE
                var waiting_local = 0usize
                local = 0usize
                while local < per_group {
                    let reached = frame_pc(frames, base + local * bytes_per_frame)
                    if reached != DONE && reached != FAULTED {
                        waiting_at = reached
                        waiting_local = local
                        break
                    }
                    local += 1usize
                }
                var first = 0usize
                var end = per_group
                if subgroup_wait(waiting_at) {
                    first = waiting_local / 32usize * 32usize
                    end = first + 32usize
                    if end > per_group { end = per_group }
                }
                local = first
                while local < end {
                    let reached = frame_pc(frames, base + local * bytes_per_frame)
                    if reached != FAULTED && reached != waiting_at { divergence(group, local, reached, waiting_local, waiting_at) }
                    local += 1usize
                }
                divergence(group, waiting_local, waiting_at, waiting_local, waiting_at)
            }
            local = 0usize
            while local < per_group {
                subgroup_snapshot[local] = subgroup_values[local]
                subgroup_word_snapshot[local] = subgroup_words[local]
                subgroup_lane_snapshot[local] = subgroup_lanes[local]
                let state_at = frame_pc(frames, base + local * bytes_per_frame)
                subgroup_active[local] = state_at != DONE && state_at != FAULTED
                local += 1usize
            }
            local = 0usize
            while local < per_group {
                if runnable[local] {
                    set_ids(group, local)
                    step(ctx, &frames[base + local * bytes_per_frame], &shared_storage[shared_base])
                }
                local += 1usize
            }
        }
        group += 1usize
    }
    launch_active = false
    state.serial += 1u64
    ret ok
}

// ------------------------------------------------------- sort and attention
//
// Two kernels the plan names on this module: `sort_bitonic` and `attention_flash`.
// `gpu.launch[K]` is a qualified spelling the checker matches on an import of
// `e.gpu`, which this module cannot be, so each launch here is the launcher's own
// shape written by hand: an argument block, a step that runs one invocation by
// `gid.x` and writes the done mark, and `launch_run` over the grid -- one
// submission per launch, the same scheduler and fault buffer as any kernel.

// A typed slice over a live buffer's storage: `mem.alloc` on an arena laid over its
// bytes, the one way source turns bytes into a `[]T`. The debug build's alloc
// fills what it hands out with 0xCD (D217), so the bytes are held in a copy at
// the device arena's top meanwhile and the top is given back. ponytail: one
// memcpy each way per view; a typed `mem.view` would make it free.
fn device_slice[T: type](state: *QueueState, buf: Buf[T]) -> ([]T, err) {
    let (slot, slot_error) = slot_of(state, buf.owner, buf.slot, buf.generation)
    if slot_error != ok { ret (zero, slot_error) }
    let buffer = state.device.buffers[slot]
    if buffer.count == 0usize { ret (zero, ok) }
    let a = state.device.arena
    let top = mem.mark(a)
    let (held, held_error) = mem.alloc[u8](a, buffer.bytes.len)
    if held_error != ok { ret (zero, held_error) }
    copy_bytes(held, buffer.bytes)
    var over: mem.Arena = zero
    over.base = &buffer.bytes[0usize]
    over.cap = buffer.bytes.len
    over.off = 0usize
    let (elements, elements_error) = mem.alloc[T](&over, buffer.count)
    if elements_error != ok { ret (zero, elements_error) }
    copy_bytes(buffer.bytes, held)
    mem.reset(a, top)
    ret (elements, ok)
}

// The done mark a returning invocation leaves in its frame.
fn mark_done(frame: *u8) {
    let pc = mem.cast[*usize](frame)
    *pc = DONE
}

// One compare-exchange of the bitonic network: invocation `i` against its partner
// `i ^ j` in the stage of size `k`, ascending where bit `k` of `i` is clear; the
// lower index of the pair does the exchange, the higher returns.
fn bitonic_step(keys: []u32, i: u32, j: u32, k: u32) {
    let partner = i ^ j
    if partner <= i || usize(partner) >= keys.len { ret }
    let x = keys[usize(i)]
    let y = keys[usize(partner)]
    let ascending = (i & k) == 0u32
    if (ascending && x > y) || (!ascending && x < y) {
        keys[usize(i)] = y
        keys[usize(partner)] = x
    }
}

type SortArgs = struct { keys: []u32, n: u32, j: u32, k: u32 }

fn sort_step(ctx: *void, frame: *u8, workgroup: *u8) {
    let args = mem.cast[*SortArgs](ctx)
    let i = gid.x
    if i < args.n { bitonic_step(args.keys, i, args.j, args.k) }
    mark_done(frame)
}

const MAX_SORT: usize = 16777216usize

// The first `n` keys of `buffer` sorted ascending by a bitonic network: for every
// stage `k` (2, 4, ..., p) and pass `j` (k/2, ..., 1) one launch of `p` invocations,
// each one compare-exchange. `p` is `n` rounded up to a power of two; a shorter
// `n` is sorted through a padded device copy whose tail is `0xFFFFFFFF`, the
// largest key, and written back over the first `n`. `n` past the buffer's length,
// or past MAX_SORT (65535 workgroups of 256), is `TooLarge`.
fn sort_bitonic(device: *Device, q: *Queue, buffer: Buf[u32], n: usize) -> err {
    let (owner, owner_error) = state_of(device)
    if owner_error != ok { ret owner_error }
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret state_error }
    if owner.owner != state.device.owner || buffer.owner != owner.owner { ret WrongDevice }
    if n > buffer.len || n > MAX_SORT { ret TooLarge }
    if n < 2usize { ret ok }
    var p = 1usize
    while p < n { p = p << 1u32 }
    let (keys, keys_error) = device_slice[u32](state, buffer)
    if keys_error != ok { ret keys_error }
    var work = keys[..n]
    var padded: Buf[u32] = zero
    if p != n {
        let (padded_buf, padded_error) = alloc[u32](q, p)
        if padded_error != ok { ret padded_error }
        padded = padded_buf
        let (scratch, scratch_error) = device_slice[u32](state, padded)
        if scratch_error != ok { ret scratch_error }
        mem.copy[u32](scratch, keys[..n])
        var fill = n
        while fill < p {
            scratch[fill] = 4294967295u32
            fill += 1usize
        }
        work = scratch
    }
    var args = SortArgs { keys: work, n: u32(p), j: 0u32, k: 0u32 }
    var k = 2usize
    while k <= p {
        var j = k >> 1u32
        while j > 0usize {
            args.j = u32(j)
            args.k = u32(k)
            try launch_run(q, grid1(p), 256usize, 1usize, 1usize, 16usize, 0usize, sort_step, mem.cast[*void](&args), 0usize, "", "", "")
            j = j >> 1u32
        }
        k = k << 1u32
    }
    if p != n {
        mem.copy[u32](keys[..n], work[..n])
        try release[u32](q, padded)
    }
    ret ok
}

const MAX_HEAD: usize = 256usize

type AttentionArgs = struct { query: []const f32, key: []const f32, value: []const f32, out: []f32, n: u32, d: u32, tile: u32, scale: f32 }

// One query row of FlashAttention: the key tiles in order, each scored against the
// row, and the running max, sum and accumulator rescaled by `exp(old - new)` when
// a tile raises the max -- the online softmax, so no second pass over the keys.
// `scores` holds one tile, `acc` one output row; both cap at MAX_HEAD.
fn attention_row(args: *AttentionArgs, row: usize) {
    let n = usize(args.n)
    let d = usize(args.d)
    let tile = usize(args.tile)
    var scores: [256]f32 = zero
    var acc: [256]f32 = zero
    var running_max: f32 = -3.0e38
    var running_sum: f32 = 0.0
    var start = 0usize
    while start < n {
        var stop = start + tile
        if stop > n { stop = n }
        var tile_max: f32 = -3.0e38
        var j = start
        while j < stop {
            var dot: f32 = 0.0
            var dim = 0usize
            while dim < d {
                dot = dot + args.query[row * d + dim] * args.key[j * d + dim]
                dim += 1usize
            }
            let s = dot * args.scale
            scores[j - start] = s
            if s > tile_max { tile_max = s }
            j += 1usize
        }
        var new_max = running_max
        if tile_max > new_max { new_max = tile_max }
        let correction = math.exp[f32](running_max - new_max)
        running_sum = running_sum * correction
        var col = 0usize
        while col < d {
            acc[col] = acc[col] * correction
            col += 1usize
        }
        j = start
        while j < stop {
            let weight = math.exp[f32](scores[j - start] - new_max)
            running_sum = running_sum + weight
            var lane = 0usize
            while lane < d {
                acc[lane] = acc[lane] + weight * args.value[j * d + lane]
                lane += 1usize
            }
            j += 1usize
        }
        running_max = new_max
        start = stop
    }
    var o = 0usize
    while o < d {
        args.out[row * d + o] = acc[o] / running_sum
        o += 1usize
    }
}

fn attention_step(ctx: *void, frame: *u8, workgroup: *u8) {
    let args = mem.cast[*AttentionArgs](ctx)
    let i = gid.x
    if i < args.n { attention_row(args, usize(i)) }
    mark_done(frame)
}

// FlashAttention over `query`, `key`, `value` of shape `(n, d)`, row-major, into
// `out` of the same shape: one launch of `n` invocations, each one query row over
// the keys in tiles of `tile` rows (`attention_row`), `scale` applied to every
// score (`1 / sqrt(d)` for the usual attention). Answers the tiles each row
// walked, `ceil(n / tile)`. `d` or `tile` past MAX_HEAD, a zero `tile`, or a
// buffer shorter than `n * d` is `TooLarge`.
fn attention_flash(device: *Device, q: *Queue, query: Buf[f32], key: Buf[f32], value: Buf[f32], out: Buf[f32], n: usize, d: usize, tile: usize, scale: f32) -> (usize, err) {
    let (owner, owner_error) = state_of(device)
    if owner_error != ok { ret (0usize, owner_error) }
    let (state, state_error) = queue_state(q)
    if state_error != ok { ret (0usize, state_error) }
    if owner.owner != state.device.owner { ret (0usize, WrongDevice) }
    if query.owner != owner.owner || key.owner != owner.owner || value.owner != owner.owner || out.owner != owner.owner { ret (0usize, WrongDevice) }
    if d == 0usize || d > MAX_HEAD || tile == 0usize || tile > MAX_HEAD || n > MAX_SORT { ret (0usize, TooLarge) }
    let total = n * d
    if query.len < total || key.len < total || value.len < total || out.len < total { ret (0usize, TooLarge) }
    let tiles = (n + tile - 1usize) / tile
    if n == 0usize { ret (0usize, ok) }
    let (query_view, query_error) = device_slice[f32](state, query)
    if query_error != ok { ret (0usize, query_error) }
    let (key_view, key_error) = device_slice[f32](state, key)
    if key_error != ok { ret (0usize, key_error) }
    let (value_view, value_error) = device_slice[f32](state, value)
    if value_error != ok { ret (0usize, value_error) }
    let (out_view, out_error) = device_slice[f32](state, out)
    if out_error != ok { ret (0usize, out_error) }
    var args = AttentionArgs { query: query_view, key: key_view, value: value_view, out: out_view, n: u32(n), d: u32(d), tile: u32(tile), scale: scale }
    let run_error = launch_run(q, grid1(n), 256usize, 1usize, 1usize, 16usize, 0usize, attention_step, mem.cast[*void](&args), 0usize, "", "", "")
    if run_error != ok { ret (0usize, run_error) }
    ret (tiles, ok)
}
