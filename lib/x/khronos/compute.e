// `x.khronos.compute` (L180, D5889): `e.gpu`'s `.Gl` backend. `install` hands `e.gpu` a heap driver over OpenGL 4.3 compute,
// whose kernels are the GLSL a `--gpu glsl` build embeds (D5888). The device is a headless GL 4.3 core context; its heap and
// each launch's argument block are shader storage buffers created with `glBufferStorage` and mapped persistently and
// coherently, so `e.gpu`'s buffers are CPU copies into the heap exactly as on Metal. A launch binds the argument block at
// binding 0 and the heap at 1, dispatches, puts a barrier and a fence behind it, and the wait is the fence's.
//
// ponytail: the context is current on the thread that opened the device, and every call on the device has to come from that
// thread; a worker thread that owns the context and takes the calls (D5881) is the upgrade when e.gpu is used across threads.

use e.gpu
use e.gpu.metal as mtl
use e.mem
use x.khronos.context
use x.khronos.gl

error Unsupported

// Int8 and Int16: GLSL narrow loads and atomic stores; Int64 below. Float16, Float64 and subgroups wait for L181. Whether f32
// denormals survive is the driver's (GL allows either), so `open` asks: DenormPreserve when they do, Ftz when they flush.
const CAPABILITIES: usize = 3usize
const CAP_FTZ: usize = 128usize
const CAP_DENORM_PRESERVE: usize = 256usize
const MAX_DEVICES: usize = 4usize

// The smallest positive f32 denormal, doubled: 2 where denormals are kept, 0 where they are flushed.
fn denormal_probe() -> str { ret "//entry:probe\n#version 430\nlayout(local_size_x = 1) in;\nlayout(std430, binding = 1) buffer Heap { uint heap[]; };\nvoid main() { precise float d = uintBitsToFloat(heap[0]); precise float twice = d * 2.0; heap[1] = floatBitsToUint(twice); }\n" }

fn capabilities() -> usize { ret CAPABILITIES | denormal_caps | int64_caps }

// Runs the probe on the device just opened and records its answer.
fn probe_denormals(handle: mtl.Context) {
    denormal_caps = 0usize
    let (heap, heap_error) = buffer(handle, 16usize)
    if heap_error != ok { ret }
    let (args, args_error) = buffer(handle, 16usize)
    if args_error != ok {
        free(heap)
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
    let (pipeline, pipeline_error) = compile(handle, denormal_probe(), "probe")
    if pipeline_error == ok {
        var pair: [2]mtl.Buffer = zero
        pair[0usize] = args
        pair[1usize] = heap
        let (command, begin_error) = dispatch_begin(handle, pipeline, pair[0usize..2usize], mtl.Size { width: 1usize, height: 1usize, depth: 1usize }, mtl.Size { width: 1usize, height: 1usize, depth: 1usize }, 0usize)
        if begin_error == ok && dispatch_wait(command) == ok {
            let high = heap.bytes[5usize] | heap.bytes[6usize] | heap.bytes[7usize]
            if heap.bytes[4usize] == 2u8 && high == 0u8 { denormal_caps = CAP_DENORM_PRESERVE }
            if heap.bytes[4usize] == 0u8 && high == 0u8 { denormal_caps = CAP_FTZ }
        }
        destroy(pipeline)
    }
    free(args)
    free(heap)
}

type Slot = struct { c: context.Context, live: bool }

@cc(c)
type BufferStorageExt = extern fn(u32, isize, *void, u32)
type BufferStoragePun = union { function: BufferStorageExt, bits: usize }

var slots: [4]Slot = zero
// The denormal answer of the last device opened; every device in a process is the same driver.
var denormal_caps: usize = 0usize
// Int64 (`Cap` bit 4) where the desktop driver has GL_ARB_gpu_shader_int64, which the emitter's 64-bit values need.
var int64_caps: usize = 0usize
// (C218) Devices are OpenGL ES 3.2 contexts rather than GL 4.3 core ones; ES 3.2 is the first with `precise`.
var use_es: bool = false
// `glBufferStorageEXT` where the context has only the extension (OpenGL ES), else 0.
var storage_ext: usize = 0usize

fn available() -> bool { ret true }

fn slot_of(handle: mtl.Context) -> usize {
    if handle.device == 0usize || handle.device > MAX_DEVICES { ret MAX_DEVICES }
    ret handle.device - 1usize
}

fn open(a: *mem.Arena) -> (mtl.Context, err) {
    var none: mtl.Context = zero
    var at = 0usize
    while at < MAX_DEVICES && slots[at].live { at += 1usize }
    if at == MAX_DEVICES { ret (none, Unsupported) }
    var options = context.Options { api: .Gl, major: 4u32, minor: 3u32 }
    if use_es { options = context.Options { api: .Gles, major: 3u32, minor: 2u32 } }
    let (c, c_error) = context.headless(a, options)
    if c_error != ok { ret (none, Unsupported) }
    slots[at] = Slot { c: c, live: true }
    storage_ext = 0usize
    var loaded = context.load(a, options)
    if loaded == ok && !gl.present(gl.BUFFER_STORAGE_ENTRY) {
        storage_ext = context.resolve(a, 0usize, "glBufferStorageEXT")
        if storage_ext == 0usize { loaded = Unsupported }
    }
    if loaded == ok {
        let (major, minor, es, version_error) = gl.version()
        if version_error != ok || es != use_es || major < options.major || (major == options.major && minor < options.minor) { loaded = Unsupported }
    }
    if loaded != ok {
        close(mtl.Context { device: at + 1usize, queue: 0usize })
        ret (none, Unsupported)
    }
    let opened = mtl.Context { device: at + 1usize, queue: 0usize }
    probe_denormals(opened)
    int64_caps = 0usize
    if !use_es && gl.has_extension("GL_ARB_gpu_shader_int64") { int64_caps = 4usize }
    ret (opened, ok)
}

fn close(handle: mtl.Context) {
    let at = slot_of(handle)
    if at == MAX_DEVICES || !slots[at].live { ret }
    let closed = context.close(&slots[at].c)
    slots[at].live = false
}

fn name(handle: mtl.Context, out: []u8) -> usize {
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
fn buffer(handle: mtl.Context, requested: usize) -> (mtl.Buffer, err) {
    var none: mtl.Buffer = zero
    if slot_of(handle) == MAX_DEVICES { ret (none, Unsupported) }
    var bytes = requested
    var largest = 0i32
    gl.get_integerv(gl.MAX_SHADER_STORAGE_BLOCK_SIZE, &largest)
    if largest > 0i32 && bytes > usize(largest) { bytes = usize(largest) / 256usize * 256usize }
    var name_value = 0u32
    gl.gen_buffers(1i32, &name_value)
    gl.bind_buffer(gl.SHADER_STORAGE_BUFFER, name_value)
    let flags = gl.MAP_READ_BIT | gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT
    if storage_ext != 0usize {
        var pun: BufferStoragePun = zero
        pun.bits = storage_ext
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
    ret (mtl.Buffer { handle: usize(name_value), bytes: mem.view(&region, 0usize, bytes) }, ok)
}

fn free(buffer_value: mtl.Buffer) {
    var name_value = u32(buffer_value.handle)
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
fn compile(handle: mtl.Context, source: str, entry: str) -> (mtl.Pipeline, err) {
    var none: mtl.Pipeline = zero
    if slot_of(handle) == MAX_DEVICES { ret (none, Unsupported) }
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
    // On OpenGL ES the emitter's `#version 430` line gives way to ES 3.2's, with every precision high.
    var header = ""
    let desktop = "#version 430\n"
    if use_es && text.len > desktop.len && mem.eq[u8](text[0usize..desktop.len], desktop) {
        header = "#version 320 es\nprecision highp float;\nprecision highp int;\n"
        text = text[desktop.len..text.len]
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
    gl.attach_shader(program, shader)
    gl.link_program(program)
    gl.delete_shader(shader)
    gl.get_programiv(program, gl.LINK_STATUS, &status)
    if status == 0i32 {
        gl.delete_program(program)
        ret (none, Unsupported)
    }
    var most = 0i32
    gl.get_integerv(gl.MAX_COMPUTE_WORK_GROUP_INVOCATIONS, &most)
    ret (mtl.Pipeline { state: usize(program), max_threads: usize(most) }, ok)
}

fn destroy(pipeline: mtl.Pipeline) { gl.delete_program(u32(pipeline.state)) }

fn dispatch_begin(handle: mtl.Context, pipeline: mtl.Pipeline, buffers: []const mtl.Buffer, groups: mtl.Size, per_group: mtl.Size, shared_bytes: usize) -> (usize, err) {
    if slot_of(handle) == MAX_DEVICES || buffers.len != 2usize { ret (0usize, Unsupported) }
    gl.bind_buffer_base(gl.SHADER_STORAGE_BUFFER, 0u32, u32(buffers[0usize].handle))
    gl.bind_buffer_base(gl.SHADER_STORAGE_BUFFER, 1u32, u32(buffers[1usize].handle))
    gl.use_program(u32(pipeline.state))
    gl.dispatch_compute(u32(groups.width), u32(groups.height), u32(groups.depth))
    // What the kernel wrote is the host's to read once the fence has passed.
    gl.memory_barrier(gl.ALL_BARRIER_BITS)
    let fence = gl.fence_sync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0u32)
    gl.flush()
    if fence == 0usize || gl.get_error() != gl.NO_ERROR { ret (0usize, Unsupported) }
    ret (fence, ok)
}

fn dispatch_wait(command: usize) -> err {
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

// Makes `.Gl` an `e.gpu` backend over OpenGL ES 3.2 instead (C218): EGL's on Linux, ANGLE's `libEGL.dll` on Windows.
// The emitted shaders are the same; ES needs `GL_EXT_buffer_storage` for the mapped heap.
fn install_es() {
    use_es = true
    register()
}

// Makes `.Gl` an `e.gpu` backend for this program.
fn install() {
    use_es = false
    register()
}

fn register() {
    gpu.install_gl(gpu.HeapDriver { available: available, name: name, open: open, close: close, buffer: buffer, free: free, compile: compile, destroy: destroy, dispatch_begin: dispatch_begin, dispatch_wait: dispatch_wait, capabilities: capabilities })
}
