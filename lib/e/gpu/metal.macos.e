// Metal compute under `e.gpu` (C193, D5231): the device, a library compiled from Metal Shading Language source at run time, a
// compute pipeline, shared buffers and a dispatch, reached through the Objective-C runtime the way `e.os` reaches AppKit, so a
// program that never asks for Metal loads nothing of it. Only a Mac has it: `open` is `Unsupported` anywhere else, and so is
// `devices`' answer there, `NoDevice`. This is the runtime alone, as `e.gpu.vulkan` was before `e.gpu` used it: a kernel arrives
// as MSL text (hand written, or a compiler's emitter later) and runs on the system's default device.
//
// A buffer is `MTLResourceStorageModeShared`: `bytes` is the mapping the CPU reads and writes, as on a Vulkan device's mapped
// memory. A dispatch commits one command buffer and waits for it; there is no asynchronous queue here.

use e.mem
use e.os

error NoDevice
error Unsupported
error Failed
error CompileFailed

type Context = struct { device: usize, queue: usize }
type Buffer = struct { handle: usize, bytes: []u8 }
type Pipeline = struct { state: usize, max_threads: usize }
type Size = struct { width: usize, height: usize, depth: usize }

@import("/System/Library/Frameworks/Metal.framework/Metal", "MTLCreateSystemDefaultDevice")
extern fn default_device() -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_buffer(receiver: usize, selector: usize, a: usize, b: usize, c: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_dispatch(receiver: usize, selector: usize, groups: Size, per_group: Size) -> usize

// Whether this machine has a Metal device (a Mac does, a virtual machine's paravirtual GPU too).
fn available() -> bool {
    when target.os == .Macos {
        if os.cocoa_start() != ok { ret false }
        let metal = "/System/Library/Frameworks/Metal.framework/Metal\x00"
        if os.raw_dlopen(mem.address_of(&metal[0usize]), 2i32) == 0usize { ret false }
        ret default_device() != 0usize
    }
    ret false
}

// The default device's name, copied into `out`; the length it had.
fn name(context: Context, out: []u8) -> usize {
    ret os.cocoa_read_text(os.msg0(context.device, os.cocoa_sel("name\x00")), out)
}

fn open(a: *mem.Arena) -> (Context, err) {
    var none: Context = zero
    when target.os == .Macos {
        if !available() { ret (none, NoDevice) }
        let device = default_device()
        let queue = os.msg0(device, os.cocoa_sel("newCommandQueue\x00"))
        if queue == 0usize { ret (none, Failed) }
        ret (Context { device: device, queue: queue }, ok)
    }
    ret (none, Unsupported)
}

fn close(context: Context) {
    let dropped = os.msg0(context.queue, os.cocoa_sel("release\x00"))
}

// `bytes` of storage the CPU and the device share, zero filled by the system.
fn buffer(context: Context, bytes: usize) -> (Buffer, err) {
    var none: Buffer = zero
    if bytes == 0usize { ret (none, Failed) }
    let handle = os.msg2(context.device, os.cocoa_sel("newBufferWithLength:options:\x00"), bytes, 0usize)
    if handle == 0usize { ret (none, Failed) }
    let data = os.msg0(handle, os.cocoa_sel("contents\x00"))
    if data == 0usize { ret (none, Failed) }
    // The pointer the system gave, as a pointer: its eight bytes copied into one.
    var mapped: *u8 = zero
    var address = data
    let copied = os.raw_memcpy(mem.address_of(&mapped), mem.address_of(&address), 8usize)
    var region: mem.Arena = zero
    region.base = mapped
    region.cap = bytes
    region.off = 0usize
    ret (Buffer { handle: handle, bytes: mem.view(&region, 0usize, bytes) }, ok)
}

fn free(buffer_value: Buffer) {
    let dropped = os.msg0(buffer_value.handle, os.cocoa_sel("release\x00"))
}

// A kernel function `entry` of the MSL `source`, compiled for this device.
fn compile(context: Context, source: str, entry: str) -> (Pipeline, err) {
    var none: Pipeline = zero
    let pool = os.objc_pool_push()
    let text = os.cocoa_text(source)
    var problem = 0usize
    // Fast math off: a float operation is IEEE, as on the CPU (spec section 11).
    let options = os.msg0(os.msg0(os.cocoa_class("MTLCompileOptions\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("init\x00"))
    let slow = os.msg1(options, os.cocoa_sel("setFastMathEnabled:\x00"), 0usize)
    let library = os.msg4(context.device, os.cocoa_sel("newLibraryWithSource:options:error:\x00"), text, options, mem.address_of(&problem), 0usize)
    let released_options = os.msg0(options, os.cocoa_sel("release\x00"))
    os.cf_release(text)
    if library == 0usize {
        var report: [1500]u8 = zero
        let reported = os.cocoa_read_text(os.msg0(problem, os.cocoa_sel("localizedDescription\x00")), report[0usize..1500usize])
        let (printed, printed_error) = os.write(os.stdout(), "metal compile: ")
        let (printed2, printed2_error) = os.write(os.stdout(), report[0usize..reported])
        os.objc_pool_pop(pool)
        ret (none, CompileFailed)
    }
    let function_name = os.cocoa_text(entry)
    let function = os.msg1(library, os.cocoa_sel("newFunctionWithName:\x00"), function_name)
    os.cf_release(function_name)
    if function == 0usize {
        let released = os.msg0(library, os.cocoa_sel("release\x00"))
        os.objc_pool_pop(pool)
        ret (none, CompileFailed)
    }
    var pipeline_problem = 0usize
    let state = os.msg2(context.device, os.cocoa_sel("newComputePipelineStateWithFunction:error:\x00"), function, mem.address_of(&pipeline_problem))
    let released_function = os.msg0(function, os.cocoa_sel("release\x00"))
    let released_library = os.msg0(library, os.cocoa_sel("release\x00"))
    os.objc_pool_pop(pool)
    if state == 0usize { ret (none, CompileFailed) }
    ret (Pipeline { state: state, max_threads: os.msg0(state, os.cocoa_sel("maxTotalThreadsPerThreadgroup\x00")) }, ok)
}

fn destroy(pipeline: Pipeline) {
    let dropped = os.msg0(pipeline.state, os.cocoa_sel("release\x00"))
}

// Runs the pipeline over `groups` thread groups of `per_group` threads with `buffers[i]` at buffer index i, and waits.
// `shared_bytes` is the thread group memory of the kernel's `threadgroup` argument at index 0 (zero for none).
fn dispatch(context: Context, pipeline: Pipeline, buffers: []const Buffer, groups: Size, per_group: Size, shared_bytes: usize) -> err {
    if buffers.len > 31usize || groups.width == 0usize || groups.height == 0usize || groups.depth == 0usize { ret Failed }
    let pool = os.objc_pool_push()
    let command = os.msg0(context.queue, os.cocoa_sel("commandBuffer\x00"))
    let encoder = os.msg0(command, os.cocoa_sel("computeCommandEncoder\x00"))
    let pipelined = os.msg1(encoder, os.cocoa_sel("setComputePipelineState:\x00"), pipeline.state)
    var at = 0usize
    while at < buffers.len {
        let bound = msg_buffer(encoder, os.cocoa_sel("setBuffer:offset:atIndex:\x00"), buffers[at].handle, 0usize, at)
        // A device address inside a buffer is only good for memory the encoder was told to keep resident (read and write).
        let resident = os.msg2(encoder, os.cocoa_sel("useResource:usage:\x00"), buffers[at].handle, 3usize)
        at += 1usize
    }
    if shared_bytes != 0usize {
        let sized = msg_buffer(encoder, os.cocoa_sel("setThreadgroupMemoryLength:atIndex:\x00"), shared_bytes, 0usize, 0usize)
    }
    let dispatched = msg_dispatch(encoder, os.cocoa_sel("dispatchThreadgroups:threadsPerThreadgroup:\x00"), groups, per_group)
    let ended = os.msg0(encoder, os.cocoa_sel("endEncoding\x00"))
    let committed = os.msg0(command, os.cocoa_sel("commit\x00"))
    let waited = os.msg0(command, os.cocoa_sel("waitUntilCompleted\x00"))
    // MTLCommandBufferStatusCompleted is 4.
    let status = os.msg0(command, os.cocoa_sel("status\x00"))
    os.objc_pool_pop(pool)
    if status != 4usize { ret Failed }
    ret ok
}
