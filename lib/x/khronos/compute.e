// `x.khronos.compute` (L180, D5889): `e.gpu`'s `.Gl` backend. `install` hands `e.gpu` a heap driver over OpenGL 4.3 compute,
// whose kernels are the GLSL a `--gpu glsl` build embeds (D5888). The device is a headless GL 4.3 core context; its heap and
// each launch's argument block are shader storage buffers created with `glBufferStorage` and mapped persistently and
// coherently, so `e.gpu`'s buffers are CPU copies into the heap exactly as on Metal. A launch binds the argument block at
// binding 0 and the heap at 1, dispatches, puts a barrier and a fence behind it, and the wait is the fence's.
//
// ponytail: the context is current on the thread that opened the device, and every call on the device has to come from that
// thread; a worker thread that owns the context and takes the calls (D5881) is the upgrade when e.gpu is used across threads.

use e.gpu
use e.fs
use e.gpu.metal as mtl
use e.mem
use e.atomic
use e.sync
use e.thread
use x.khronos.context
use x.khronos.gl

error Unsupported

// Int8, Int16 and Float16 (D5914: f16 and bf16 are integer code over f32, no extension): GLSL narrow loads and atomic stores; Int64, Float64 and Subgroup below. Whether f32
// denormals survive is the driver's (GL allows either), so `open` asks: DenormPreserve when they do, Ftz when they flush.
const CAPABILITIES: usize = 11usize
const CAP_FTZ: usize = 128usize
const CAP_DENORM_PRESERVE: usize = 256usize
const MAX_DEVICES: usize = 4usize

// The smallest positive f32 denormal, doubled: 2 where denormals are kept, 0 where they are flushed.
fn denormal_probe() -> str { ret "//entry:probe\n#version 430\nlayout(local_size_x = 1) in;\nlayout(std430, binding = 1) buffer Heap { uint heap[]; };\nvoid main() { precise float d = uintBitsToFloat(heap[0]); precise float twice = d * 2.0; heap[1] = floatBitsToUint(twice); }\n" }

// Runs the probe on the device just opened and records its answer.
fn probe_denormals(handle: mtl.Context) {
    let at = slot_of(handle)
    if at == MAX_DEVICES { ret }
    slots[at].denormal_caps = 0usize
    let (heap, heap_error) = buffer_here(handle, 16usize)
    if heap_error != ok { ret }
    let (args, args_error) = buffer_here(handle, 16usize)
    if args_error != ok {
        free_here(heap)
        ret
    }
    // glBufferStorage without data leaves the bytes undefined: the whole input word is written.
    heap.bytes[0usize] = 1u8
    heap.bytes[1usize] = 0u8
    heap.bytes[2usize] = 0u8
    heap.bytes[3usize] = 0u8
    // A word no store leaves: a probe that did not run answers neither.
    heap.bytes[4usize] = 255u8
    heap.bytes[5usize] = 255u8
    heap.bytes[6usize] = 255u8
    heap.bytes[7usize] = 255u8
    let (pipeline, pipeline_error) = compile_here(handle, denormal_probe(), "probe")
    if pipeline_error == ok {
        var pair: [2]mtl.Buffer = zero
        pair[0usize] = args
        pair[1usize] = heap
        let (command, begin_error) = dispatch_begin_here(handle, pipeline, pair[0usize..2usize], mtl.Size { width: 1usize, height: 1usize, depth: 1usize }, mtl.Size { width: 1usize, height: 1usize, depth: 1usize }, 0usize)
        if begin_error == ok && dispatch_wait_here(command) == ok {
            let high = heap.bytes[5usize] | heap.bytes[6usize] | heap.bytes[7usize]
            if heap.bytes[4usize] == 2u8 && high == 0u8 { slots[at].denormal_caps = CAP_DENORM_PRESERVE }
            if heap.bytes[4usize] == 0u8 && high == 0u8 { slots[at].denormal_caps = CAP_FTZ }
        }
        destroy_here(pipeline)
    }
    free_here(args)
    free_here(heap)
}

// Everything that differs across live contexts belongs to its slot. The backend
// can hold a desktop and an ES context concurrently, each on its own worker.
type Slot = struct { c: context.Context, live: bool, arena: *mem.Arena, denormal_caps: usize, int64_caps: usize, float64_caps: usize, subgroup_caps: usize, is_es: bool, es_profile: u8, storage_ext: usize }

@cc(c)
type BufferStorageExt = extern fn(u32, isize, *void, u32)
type BufferStoragePun = union { function: BufferStorageExt, bits: usize }

var slots: [4]Slot = zero
// This selects future opens only; `open` snapshots it into its request so a
// later install switch cannot change an already-live device.
var opening_es: bool = false

fn slot_capabilities(s: *const Slot) -> usize { ret CAPABILITIES | s.denormal_caps | s.int64_caps | s.float64_caps | s.subgroup_caps }

fn capabilities(handle: mtl.Context) -> usize {
    let at = slot_of(handle)
    if at == MAX_DEVICES || !slots[at].live { ret CAPABILITIES }
    ret slot_capabilities(&slots[at])
}

// (D5904) Which header an ES device's shaders take: 0 is 3.2's own, 1 or 2
// is 3.1 plus the extension that gives it `precise`.
fn es_header(s: *const Slot) -> str {
    if s.es_profile == 1u8 { ret "#version 310 es\n#extension GL_EXT_gpu_shader5 : require\nprecision highp float;\nprecision highp int;\n" }
    if s.es_profile == 2u8 { ret "#version 310 es\n#extension GL_OES_gpu_shader5 : require\nprecision highp float;\nprecision highp int;\n" }
    ret "#version 320 es\nprecision highp float;\nprecision highp int;\n"
}

fn shader_header(s: *const Slot) -> str {
    if s.is_es { ret es_header(s) }
    ret "#version 430\n"
}

fn storage_extension(s: *const Slot) -> usize { ret s.storage_ext }
var cache_hit_count: usize = 0usize

fn available() -> bool { ret true }

// ---- the device's own thread (D5881, D5897) ----------------------------------------------------------------------------
// A GL context is current on one thread. Each device's context is made on a thread of its own, which runs every call on
// that device: the driver functions below post a request into the device's slot and wait for the answer. e.gpu already
// serializes calls per device, so one request slot is enough. Buffers and programs carry their slot in their high 32 bits,
// and a fence is found through the slot whose last launch made it.

const DO_OPEN: u8 = 1u8
const DO_CLOSE: u8 = 2u8
const DO_NAME: u8 = 3u8
const DO_BUFFER: u8 = 4u8
const DO_FREE: u8 = 5u8
const DO_COMPILE: u8 = 6u8
const DO_DESTROY: u8 = 7u8
const DO_BEGIN: u8 = 8u8
const DO_WAIT: u8 = 9u8

type Request = struct {
    kind: u8,
    arena: *mem.Arena,
    at: usize,
    is_es: bool,
    handle: mtl.Context,
    size: usize,
    out: []u8,
    text: str,
    entry: str,
    buffer_value: mtl.Buffer,
    pipeline: mtl.Pipeline,
    buffers: []const mtl.Buffer,
    groups: mtl.Size,
    per_group: mtl.Size,
    command: usize,
    count: usize,
    opened: mtl.Context,
    made_buffer: mtl.Buffer,
    made_pipeline: mtl.Pipeline,
    // 0 ok, 1 Unsupported: what the call on the device's thread answered.
    outcome: u8,
}

type Worker = struct { lock: sync.Mutex, posted: sync.Condition, done: sync.Condition, pending: bool, request: Request, running: Atomic[u32], fence: usize }

var workers: [4]Worker = zero

// A worker is claimed before its request state is initialized, so concurrent opens cannot
// both rebuild the mutex and conditions for the same slot. `running` is also the lifetime
// marker every public operation observes; release only happens after the worker has answered.
fn worker_running(at: usize) -> bool {
    if at >= MAX_DEVICES { ret false }
    ret atomic.load(&workers[at].running, .Acquire) != 0u32
}

fn reserve_worker() -> usize {
    var at = 0usize
    while at < MAX_DEVICES {
        let (won, seen) = atomic.cas(&workers[at].running, 0u32, 1u32, .AcqRel, .Acquire)
        if won { ret at }
        at += 1usize
    }
    ret MAX_DEVICES
}

fn release_worker(at: usize) {
    if at >= MAX_DEVICES { ret }
    atomic.store(&workers[at].running, 0u32, .Release)
}

fn outcome_of(e: err) -> u8 {
    if e == ok { ret 0u8 }
    ret 1u8
}

// The device's thread: every request in turn until the device closes.
fn serve(w: *Worker) {
    sync.mutex_lock(&w.lock)
    var running = true
    while running {
        while !w.pending { sync.condition_wait(&w.posted, &w.lock) }
        let r = &w.request
        if r.kind == DO_OPEN {
            let (opened, open_error) = open_here(r.arena, r.at, r.is_es)
            r.opened = opened
            r.outcome = outcome_of(open_error)
            if open_error != ok { running = false }
        }
        if r.kind == DO_CLOSE {
            close_here(r.handle)
            running = false
        }
        if r.kind == DO_NAME { r.count = name_here(r.handle, r.out) }
        if r.kind == DO_BUFFER {
            let (made, made_error) = buffer_here(r.handle, r.size)
            r.made_buffer = made
            r.outcome = outcome_of(made_error)
        }
        if r.kind == DO_FREE { free_here(r.buffer_value) }
        if r.kind == DO_COMPILE {
            let (made, made_error) = compile_here(r.handle, r.text, r.entry)
            r.made_pipeline = made
            r.outcome = outcome_of(made_error)
        }
        if r.kind == DO_DESTROY { destroy_here(r.pipeline) }
        if r.kind == DO_BEGIN {
            let (command, begin_error) = dispatch_begin_here(r.handle, r.pipeline, r.buffers, r.groups, r.per_group, r.size)
            r.command = command
            r.outcome = outcome_of(begin_error)
        }
        if r.kind == DO_WAIT { r.outcome = outcome_of(dispatch_wait_here(r.command)) }
        w.pending = false
        sync.condition_broadcast(&w.done)
    }
    sync.mutex_unlock(&w.lock)
}

// Hands `request` to slot `at`'s thread and waits for its answer.
fn post(at: usize, request: Request) -> Request {
    let w = &workers[at]
    sync.mutex_lock(&w.lock)
    w.request = request
    w.pending = true
    sync.condition_signal(&w.posted)
    while w.pending { sync.condition_wait(&w.done, &w.lock) }
    let answered = w.request
    sync.mutex_unlock(&w.lock)
    ret answered
}

// The slot's thread leaves its loop on its own after a close or a failed open; it was detached when it started.
fn retire(at: usize) { release_worker(at) }

fn start_worker(at: usize) -> err {
    let (spawned, spawn_error) = thread.spawn[Worker](serve, &workers[at], 8388608usize)
    if spawn_error != ok { ret spawn_error }
    ret thread.detach(spawned)
}

fn open(a: *mem.Arena) -> (mtl.Context, err) {
    var none: mtl.Context = zero
    let at = reserve_worker()
    if at == MAX_DEVICES { ret (none, Unsupported) }
    workers[at].lock = sync.mutex()
    workers[at].posted = sync.condition()
    workers[at].done = sync.condition()
    workers[at].pending = false
    workers[at].fence = 0usize
    if start_worker(at) != ok {
        release_worker(at)
        ret (none, Unsupported)
    }
    var request: Request = zero
    request.kind = DO_OPEN
    request.arena = a
    request.at = at
    request.is_es = opening_es
    let answered = post(at, request)
    if answered.outcome != 0u8 {
        retire(at)
        ret (none, Unsupported)
    }
    ret (answered.opened, ok)
}

fn close(handle: mtl.Context) {
    let at = slot_of(handle)
    if !worker_running(at) { ret }
    var request: Request = zero
    request.kind = DO_CLOSE
    request.handle = handle
    let answered = post(at, request)
    retire(at)
}

fn name(handle: mtl.Context, out: []u8) -> usize {
    let at = slot_of(handle)
    if !worker_running(at) { ret 0usize }
    var request: Request = zero
    request.kind = DO_NAME
    request.handle = handle
    request.out = out
    let answered = post(at, request)
    ret answered.count
}

fn buffer(handle: mtl.Context, requested: usize) -> (mtl.Buffer, err) {
    var none: mtl.Buffer = zero
    let at = slot_of(handle)
    if !worker_running(at) { ret (none, Unsupported) }
    var request: Request = zero
    request.kind = DO_BUFFER
    request.handle = handle
    request.size = requested
    let answered = post(at, request)
    if answered.outcome != 0u8 { ret (none, Unsupported) }
    ret (answered.made_buffer, ok)
}

fn slot_of_tagged(tagged: usize) -> usize {
    let tag = tagged >> 32usize
    if tag == 0usize || tag > MAX_DEVICES { ret MAX_DEVICES }
    ret tag - 1usize
}

fn free(buffer_value: mtl.Buffer) {
    let at = slot_of_tagged(buffer_value.handle)
    if !worker_running(at) { ret }
    var request: Request = zero
    request.kind = DO_FREE
    request.buffer_value = buffer_value
    let answered = post(at, request)
}

fn compile(handle: mtl.Context, source: str, entry: str) -> (mtl.Pipeline, err) {
    var none: mtl.Pipeline = zero
    let at = slot_of(handle)
    if !worker_running(at) { ret (none, Unsupported) }
    var request: Request = zero
    request.kind = DO_COMPILE
    request.handle = handle
    request.text = source
    request.entry = entry
    let answered = post(at, request)
    if answered.outcome != 0u8 { ret (none, Unsupported) }
    ret (answered.made_pipeline, ok)
}

fn destroy(pipeline: mtl.Pipeline) {
    let at = slot_of_tagged(pipeline.state)
    if !worker_running(at) { ret }
    var request: Request = zero
    request.kind = DO_DESTROY
    request.pipeline = pipeline
    let answered = post(at, request)
}

fn dispatch_begin(handle: mtl.Context, pipeline: mtl.Pipeline, buffers: []const mtl.Buffer, groups: mtl.Size, per_group: mtl.Size, shared_bytes: usize) -> (usize, err) {
    let at = slot_of(handle)
    if !worker_running(at) { ret (0usize, Unsupported) }
    var request: Request = zero
    request.kind = DO_BEGIN
    request.handle = handle
    request.pipeline = pipeline
    request.buffers = buffers
    request.groups = groups
    request.per_group = per_group
    request.size = shared_bytes
    let answered = post(at, request)
    if answered.outcome != 0u8 { ret (0usize, Unsupported) }
    workers[at].fence = answered.command
    ret (answered.command, ok)
}

fn dispatch_wait(command: usize) -> err {
    var at = 0usize
    while at < MAX_DEVICES && !(worker_running(at) && workers[at].fence == command) { at += 1usize }
    if at == MAX_DEVICES { ret Unsupported }
    var request: Request = zero
    request.kind = DO_WAIT
    request.command = command
    let answered = post(at, request)
    workers[at].fence = 0usize
    if answered.outcome != 0u8 { ret Unsupported }
    ret ok
}

fn slot_of(handle: mtl.Context) -> usize {
    if handle.device == 0usize || handle.device > MAX_DEVICES { ret MAX_DEVICES }
    ret handle.device - 1usize
}

fn open_here(a: *mem.Arena, at: usize, is_es: bool) -> (mtl.Context, err) {
    var none: mtl.Context = zero
    var options = context.Options { api: .Gl, major: 4u32, minor: 3u32 }
    if is_es { options = context.Options { api: .Gles, major: 3u32, minor: 1u32 } }
    let (c, c_error) = context.headless(a, options)
    if c_error != ok { ret (none, Unsupported) }
    slots[at] = Slot { c: c, live: true, arena: a, denormal_caps: 0usize, int64_caps: 0usize, float64_caps: 0usize, subgroup_caps: 0usize, is_es: is_es, es_profile: 0u8, storage_ext: 0usize }
    var loaded = context.load(a, &slots[at].c, options)
    if loaded == ok && !gl.present(gl.BUFFER_STORAGE_ENTRY) {
        slots[at].storage_ext = context.resolve(a, context.resolver_context(&slots[at].c), "glBufferStorageEXT")
        if slots[at].storage_ext == 0usize { loaded = Unsupported }
    }
    if loaded == ok {
        let (major, minor, es, version_error) = gl.version()
        if version_error != ok || es != is_es || major < options.major || (major == options.major && minor < options.minor) { loaded = Unsupported }
        // ES 3.1 has no `precise` of its own; GL_EXT_gpu_shader5 (or the OES one) gives it, and without either no multiply-add
        // is safe from fusing, so the device is refused.
        if loaded == ok && is_es && major == 3u32 && minor == 1u32 {
            if gl.has_extension("GL_EXT_gpu_shader5") { slots[at].es_profile = 1u8 }
            if gl.has_extension("GL_OES_gpu_shader5") { slots[at].es_profile = 2u8 }
            if slots[at].es_profile == 0u8 { loaded = Unsupported }
        }
    }
    if loaded != ok {
        close_here(mtl.Context { device: at + 1usize, queue: 0usize })
        ret (none, Unsupported)
    }
    let opened = mtl.Context { device: at + 1usize, queue: 0usize }
    probe_denormals(opened)
    if !is_es && gl.has_extension("GL_ARB_gpu_shader_int64") { slots[at].int64_caps = 4usize }
    if !is_es { slots[at].float64_caps = 16usize }
    if gl.has_extension("GL_KHR_shader_subgroup") {
        var stages = 0i32
        var features = 0i32
        gl.get_integerv(gl.SUBGROUP_SUPPORTED_STAGES_KHR, &stages)
        gl.get_integerv(gl.SUBGROUP_SUPPORTED_FEATURES_KHR, &features)
        if (stages & 32i32) != 0i32 && (features & 31i32) == 31i32 { slots[at].subgroup_caps = 64usize }
    }
    ret (opened, ok)
}

fn close_here(handle: mtl.Context) {
    let at = slot_of(handle)
    if at == MAX_DEVICES || !slots[at].live { ret }
    let closed = context.close(&slots[at].c)
    slots[at].live = false
}

fn name_here(handle: mtl.Context, out: []u8) -> usize {
    let at = slot_of(handle)
    if at == MAX_DEVICES || !slots[at].live { ret 0usize }
    let renderer = gl.c_text(gl.get_string(gl.RENDERER))
    var n = 0usize
    while n < renderer.len && n < out.len {
        out[n] = renderer[n]
        n += 1usize
    }
    ret n
}

// A shader storage buffer of `bytes`, mapped for reading and writing for as long as it lives. A request past the driver's
// largest shader storage block (the ES floor is 128 MiB; e.gpu asks 256 MiB for the heap) gets that largest block, and
// e.gpu carves from the length the mapping has.
fn buffer_here(handle: mtl.Context, requested: usize) -> (mtl.Buffer, err) {
    var none: mtl.Buffer = zero
    let at = slot_of(handle)
    if at == MAX_DEVICES || !slots[at].live { ret (none, Unsupported) }
    var bytes = requested
    var largest = 0i32
    gl.get_integerv(gl.MAX_SHADER_STORAGE_BLOCK_SIZE, &largest)
    if largest > 0i32 && bytes > usize(largest) { bytes = usize(largest) / 256usize * 256usize }
    var name_value = 0u32
    gl.gen_buffers(1i32, &name_value)
    gl.bind_buffer(gl.SHADER_STORAGE_BUFFER, name_value)
    let flags = gl.MAP_READ_BIT | gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT
    let extension = storage_extension(&slots[at])
    if extension != 0usize {
        var pun: BufferStoragePun = zero
        pun.bits = extension
        pun.function(gl.SHADER_STORAGE_BUFFER, isize(bytes), nil, flags)
    } else {
        gl.buffer_storage(gl.SHADER_STORAGE_BUFFER, isize(bytes), nil, flags)
    }
    let mapped = gl.map_buffer_range(gl.SHADER_STORAGE_BUFFER, 0isize, isize(bytes), flags)
    let address = mem.address_of(mapped)
    if address == 0usize || gl.get_error() != gl.NO_ERROR {
        gl.delete_buffers(1i32, &name_value)
        ret (none, Unsupported)
    }
    var region: mem.Arena = zero
    region.base = context.as_bytes(address)
    region.cap = bytes
    region.off = 0usize
    ret (mtl.Buffer { handle: usize(name_value) | ((slot_of(handle) + 1usize) << 32usize), bytes: mem.view(&region, 0usize, bytes) }, ok)
}

fn free_here(buffer_value: mtl.Buffer) {
    var name_value = u32(buffer_value.handle & 4294967295usize)
    if name_value != 0u32 { gl.delete_buffers(1i32, &name_value) }
}

fn starts_entry(source: str, at: usize, entry: str) -> bool {
    let marker = "//entry:"
    if at + marker.len + entry.len + 1usize > source.len { ret false }
    if !mem.eq[u8](source[at..at + marker.len], marker) { ret false }
    if !mem.eq[u8](source[at + marker.len..at + marker.len + entry.len], entry) { ret false }
    ret source[at + marker.len + entry.len] == 10u8
}

// The program for `entry`: the shader that follows its `//entry:` line, up to the next one.
// The decimal number after the first `key` in a shader the emitter wrote; 0 where there is none.
fn declared(text: str, key: str) -> usize {
    var at = 0usize
    while at + key.len <= text.len {
        if mem.eq[u8](text[at..at + key.len], key) {
            var value = 0usize
            var digit = at + key.len
            while digit < text.len && text[digit] >= 48u8 && text[digit] <= 57u8 {
                value = value * 10usize + usize(text[digit] - 48u8)
                digit += 1usize
            }
            ret value
        }
        at += 1usize
    }
    ret 0usize
}

fn compile_here(handle: mtl.Context, source: str, entry: str) -> (mtl.Pipeline, err) {
    var none: mtl.Pipeline = zero
    let device_slot = slot_of(handle)
    if device_slot == MAX_DEVICES || !slots[device_slot].live { ret (none, Unsupported) }
    var start = source.len
    var at = 0usize
    while at < source.len {
        if (at == 0usize || source[at - 1usize] == 10u8) && starts_entry(source, at, entry) {
            start = at + 9usize + entry.len
            break
        }
        at += 1usize
    }
    if start >= source.len { ret (none, Unsupported) }
    var end = start
    while end < source.len {
        if source[end - 1usize] == 10u8 && end + 8usize <= source.len && mem.eq[u8](source[end..end + 8usize], "//entry:") { break }
        end += 1usize
    }
    var text = source[start..end]
    // The per-slot header replaces the emitter's desktop version line. It is the
    // same line for desktop GL and the ES profile's precise-capability header for ES.
    var header = ""
    let desktop = "#version 430\n"
    if text.len > desktop.len && mem.eq[u8](text[0usize..desktop.len], desktop) {
        header = shader_header(&slots[device_slot])
        text = text[desktop.len..text.len]
    }
    var most = 0i32
    gl.get_integerv(gl.MAX_COMPUTE_WORK_GROUP_INVOCATIONS, &most)
    // (L181, D5903) A workgroup longer than the device allows along an axis, or shared memory past its size, would fail in
    // the driver's compiler as `Unsupported`; it is `TooLarge`, which a pipeline of no threads makes the launch answer.
    var axis = 0u32
    while axis < 3u32 {
        var longest = 0i32
        gl.get_integeri_v(gl.MAX_COMPUTE_WORK_GROUP_SIZE, axis, &longest)
        var key = "local_size_x = "
        if axis == 1u32 { key = "local_size_y = " }
        if axis == 2u32 { key = "local_size_z = " }
        if declared(text, key) > usize(longest) { ret (mtl.Pipeline { state: 0usize, max_threads: 0usize }, ok) }
        axis += 1u32
    }
    var shared_most = 0i32
    gl.get_integerv(gl.MAX_COMPUTE_SHARED_MEMORY_SIZE, &shared_most)
    if declared(text, "shared uint tg[") * 4usize > usize(shared_most) { ret (mtl.Pipeline { state: 0usize, max_threads: 0usize }, ok) }
    let (cache_path, cache_path_error) = cache_path_of(slots[device_slot].arena, header, text)
    if cache_path_error == ok {
        let cached = cached_program(slots[device_slot].arena, cache_path)
        if cached != 0u32 { ret (mtl.Pipeline { state: usize(cached) | ((device_slot + 1usize) << 32usize), max_threads: usize(most) }, ok) }
    }
    let shader = gl.create_shader(gl.COMPUTE_SHADER)
    var pointers: [2]usize = zero
    var lengths: [2]i32 = zero
    var count = 0usize
    if header.len != 0usize {
        pointers[0usize] = mem.address_of(&header[0usize])
        lengths[0usize] = i32(header.len)
        count = 1usize
    }
    pointers[count] = mem.address_of(&text[0usize])
    lengths[count] = i32(text.len)
    gl.shader_source(shader, i32(count + 1usize), mem.address_of(&pointers[0usize]), &lengths[0usize])
    gl.compile_shader(shader)
    var status = 0i32
    gl.get_shaderiv(shader, gl.COMPILE_STATUS, &status)
    if status == 0i32 {
        gl.delete_shader(shader)
        ret (none, Unsupported)
    }
    let program = gl.create_program()
    gl.program_parameteri(program, gl.PROGRAM_BINARY_RETRIEVABLE_HINT, 1i32)
    gl.attach_shader(program, shader)
    gl.link_program(program)
    gl.delete_shader(shader)
    gl.get_programiv(program, gl.LINK_STATUS, &status)
    if status == 0i32 {
        gl.delete_program(program)
        ret (none, Unsupported)
    }
    if cache_path_error == ok { save_program(slots[device_slot].arena, cache_path, program) }
    ret (mtl.Pipeline { state: usize(program) | ((device_slot + 1usize) << 32usize), max_threads: usize(most) }, ok)
}

// ---- the program cache (D5898) -------------------------------------------------------------------------------------------
// A linked program's binary is kept under the temporary directory's `neper-gl` folder, named by the FNV-1a hash of the
// renderer, the GL version and the shader text, so a later run on the same driver skips the GLSL compiler. A cached binary
// the driver refuses (a driver update) is ignored and compiled again; a cache that cannot be written is no cache.

fn fnv_mix(hash: u64, text: str) -> u64 {
    var mixed = hash
    for byte in text { mixed = (mixed ^ u64(byte)) *% 1099511628211u64 }
    ret mixed
}

fn cache_path_of(a: *mem.Arena, header: str, text: str) -> (str, err) {
    var hash = 14695981039346656037u64
    hash = fnv_mix(hash, gl.c_text(gl.get_string(gl.RENDERER)))
    hash = fnv_mix(hash, gl.c_text(gl.get_string(gl.VERSION)))
    hash = fnv_mix(hash, header)
    hash = fnv_mix(hash, text)
    let (directory, directory_error) = fs.temp_dir(a)
    if directory_error != ok { ret ("", directory_error) }
    let folder = "/neper-gl/"
    let (path, path_error) = mem.alloc[u8](a, directory.len + folder.len + 20usize)
    if path_error != ok { ret ("", path_error) }
    var at = 0usize
    while at < directory.len {
        path[at] = directory[at]
        at += 1usize
    }
    var k = 0usize
    while k < folder.len {
        path[at] = folder[k]
        at += 1usize
        k += 1usize
    }
    let digits = "0123456789abcdef"
    var shift = 60u64
    while true {
        path[at] = digits[usize((hash >> shift) & 15u64)]
        at += 1usize
        if shift == 0u64 { break }
        shift = shift - 4u64
    }
    let suffix = ".bin"
    k = 0usize
    while k < suffix.len {
        path[at] = suffix[k]
        at += 1usize
        k += 1usize
    }
    ret (path[0usize..at], ok)
}

// The program the cache holds for `path`, linked; 0 when there is none or the driver refuses it.
fn cached_program(a: *mem.Arena, path: str) -> u32 {
    let (bytes, read_error) = fs.read_file(a, path, 67108864usize)
    if read_error != ok || bytes.len <= 4usize { ret 0u32 }
    let format = u32(bytes[0usize]) | (u32(bytes[1usize]) << 8u32) | (u32(bytes[2usize]) << 16u32) | (u32(bytes[3usize]) << 24u32)
    let program = gl.create_program()
    gl.program_binary(program, format, context.as_pointer(mem.address_of(&bytes[4usize])), i32(bytes.len - 4usize))
    var status = 0i32
    gl.get_programiv(program, gl.LINK_STATUS, &status)
    if status == 0i32 || gl.get_error() != gl.NO_ERROR {
        gl.delete_program(program)
        ret 0u32
    }
    cache_hit_count += 1usize
    ret program
}

// How many kernels this process took from the program cache rather than compiling.
fn cache_hits() -> usize { ret cache_hit_count }

fn save_program(a: *mem.Arena, path: str, program: u32) {
    var formats = 0i32
    gl.get_integerv(gl.NUM_PROGRAM_BINARY_FORMATS, &formats)
    var length = 0i32
    gl.get_programiv(program, gl.PROGRAM_BINARY_LENGTH, &length)
    if formats <= 0i32 || length <= 0i32 { ret }
    let (bytes, bytes_error) = mem.alloc[u8](a, usize(length) + 4usize)
    if bytes_error != ok { ret }
    var written = 0i32
    var format = 0u32
    gl.get_program_binary(program, length, &written, &format, context.as_pointer(mem.address_of(&bytes[4usize])))
    if written <= 0i32 || gl.get_error() != gl.NO_ERROR { ret }
    bytes[0usize] = u8(format & 255u32)
    bytes[1usize] = u8((format >> 8u32) & 255u32)
    bytes[2usize] = u8((format >> 16u32) & 255u32)
    bytes[3usize] = u8(format >> 24u32)
    var cut = path.len
    while cut > 0usize && path[cut - 1usize] != 47u8 { cut -= 1usize }
    let made = fs.make_dirs(a, path[0usize..cut])
    let saved = fs.write_file(a, path, bytes[0usize..usize(written) + 4usize])
}

fn destroy_here(pipeline: mtl.Pipeline) { gl.delete_program(u32(pipeline.state & 4294967295usize)) }

fn dispatch_begin_here(handle: mtl.Context, pipeline: mtl.Pipeline, buffers: []const mtl.Buffer, groups: mtl.Size, per_group: mtl.Size, shared_bytes: usize) -> (usize, err) {
    if slot_of(handle) == MAX_DEVICES || buffers.len != 2usize { ret (0usize, Unsupported) }
    gl.bind_buffer_base(gl.SHADER_STORAGE_BUFFER, 0u32, u32(buffers[0usize].handle & 4294967295usize))
    gl.bind_buffer_base(gl.SHADER_STORAGE_BUFFER, 1u32, u32(buffers[1usize].handle & 4294967295usize))
    gl.use_program(u32(pipeline.state & 4294967295usize))
    gl.dispatch_compute(u32(groups.width), u32(groups.height), u32(groups.depth))
    // What the kernel wrote is the host's to read once the fence has passed.
    gl.memory_barrier(gl.ALL_BARRIER_BITS)
    let fence = gl.fence_sync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0u32)
    gl.flush()
    if fence == 0usize || gl.get_error() != gl.NO_ERROR { ret (0usize, Unsupported) }
    ret (fence, ok)
}

fn dispatch_wait_here(command: usize) -> err {
    while true {
        let waited = gl.client_wait_sync(command, gl.SYNC_FLUSH_COMMANDS_BIT, 1000000000u64)
        if waited == gl.ALREADY_SIGNALED || waited == gl.CONDITION_SATISFIED { break }
        if waited == gl.WAIT_FAILED {
            gl.delete_sync(command)
            ret Unsupported
        }
    }
    gl.delete_sync(command)
    ret ok
}

// Makes `.Gl` an `e.gpu` backend over OpenGL ES 3.2, or 3.1 with GL_EXT_gpu_shader5 (C218, D5904), instead: EGL's on Linux,
// ANGLE's `libEGL.dll` on Windows.
// The emitted shaders are the same; ES needs `GL_EXT_buffer_storage` for the mapped heap.
fn install_es() {
    opening_es = true
    register()
}

// Makes `.Gl` an `e.gpu` backend for this program.
fn install() {
    opening_es = false
    register()
}

fn register() {
    gpu.install_gl(gpu.HeapDriver { available: available, name: name, open: open, close: close, buffer: buffer, free: free, compile: compile, destroy: destroy, dispatch_begin: dispatch_begin, dispatch_wait: dispatch_wait, capabilities: capabilities })
}
