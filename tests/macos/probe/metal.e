// Whether Metal compute works on this machine, before any emitter is written: a device, a library compiled from MSL source at run
// time, a pipeline, two buffers, a dispatch and the answer read back. saxpy over 1024 floats: y = 2 * x + y.
use e.mem
use e.os

type MtlSize = struct { width: usize, height: usize, depth: usize }

@import("/System/Library/Frameworks/Metal.framework/Metal", "MTLCreateSystemDefaultDevice")
extern fn mtl_default_device() -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_buffer(receiver: usize, selector: usize, a: usize, b: usize, c: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_dispatch(receiver: usize, selector: usize, groups: MtlSize, per_group: MtlSize) -> usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    let metal = "/System/Library/Frameworks/Metal.framework/Metal\x00"
    let loaded = os.raw_dlopen(mem.address_of(&metal[0usize]), 2i32)
    let pool = os.objc_pool_push()
    let device = mtl_default_device()
    if device == 0usize {
        say("no metal device\n")
        os.exit(3i32)
    }
    let device_name = os.msg0(device, os.cocoa_sel("name\x00"))
    var name: [96]u8 = zero
    let name_length = os.cocoa_read_text(device_name, name[0usize..95usize])
    say("device: ")
    let (shown, show_error) = os.write(os.stdout(), name[0usize..name_length])
    say("\n")
    let source = os.cocoa_text("#include <metal_stdlib>\nusing namespace metal;\nkernel void saxpy(device const float* x [[buffer(0)]], device float* y [[buffer(1)]], uint i [[thread_position_in_grid]]) { y[i] = 2.0f * x[i] + y[i]; }\n")
    var problem = 0usize
    let library = os.msg4(device, os.cocoa_sel("newLibraryWithSource:options:error:\x00"), source, 0usize, mem.address_of(&problem), 0usize)
    if library == 0usize {
        say("library failed\n")
        os.exit(4i32)
    }
    say("library compiled\n")
    let function_name = os.cocoa_text("saxpy")
    let function = os.msg1(library, os.cocoa_sel("newFunctionWithName:\x00"), function_name)
    if function == 0usize { os.exit(5i32) }
    var pipeline_problem = 0usize
    let pipeline = os.msg2(device, os.cocoa_sel("newComputePipelineStateWithFunction:error:\x00"), function, mem.address_of(&pipeline_problem))
    if pipeline == 0usize {
        say("pipeline failed\n")
        os.exit(6i32)
    }
    say("pipeline made\n")
    let bytes = 4096usize
    // MTLResourceStorageModeShared is 0
    let x_buffer = os.msg2(device, os.cocoa_sel("newBufferWithLength:options:\x00"), bytes, 0usize)
    let y_buffer = os.msg2(device, os.cocoa_sel("newBufferWithLength:options:\x00"), bytes, 0usize)
    if x_buffer == 0usize || y_buffer == 0usize { os.exit(7i32) }
    let x_data = os.msg0(x_buffer, os.cocoa_sel("contents\x00"))
    let y_data = os.msg0(y_buffer, os.cocoa_sel("contents\x00"))
    var one: [1]f32 = zero
    one[0usize] = 1.0f32
    var three: [1]f32 = zero
    three[0usize] = 3.0f32
    var at = 0usize
    while at < 1024usize {
        let a1 = os.raw_memcpy(x_data + at * 4usize, mem.address_of(&one[0usize]), 4usize)
        let a2 = os.raw_memcpy(y_data + at * 4usize, mem.address_of(&three[0usize]), 4usize)
        at += 1usize
    }
    let queue = os.msg0(device, os.cocoa_sel("newCommandQueue\x00"))
    let command = os.msg0(queue, os.cocoa_sel("commandBuffer\x00"))
    let encoder = os.msg0(command, os.cocoa_sel("computeCommandEncoder\x00"))
    let set_pipeline = os.msg1(encoder, os.cocoa_sel("setComputePipelineState:\x00"), pipeline)
    let set_x = msg_buffer(encoder, os.cocoa_sel("setBuffer:offset:atIndex:\x00"), x_buffer, 0usize, 0usize)
    let set_y = msg_buffer(encoder, os.cocoa_sel("setBuffer:offset:atIndex:\x00"), y_buffer, 0usize, 1usize)
    let dispatched = msg_dispatch(encoder, os.cocoa_sel("dispatchThreadgroups:threadsPerThreadgroup:\x00"), MtlSize { width: 4usize, height: 1usize, depth: 1usize }, MtlSize { width: 256usize, height: 1usize, depth: 1usize })
    let ended = os.msg0(encoder, os.cocoa_sel("endEncoding\x00"))
    let committed = os.msg0(command, os.cocoa_sel("commit\x00"))
    let waited = os.msg0(command, os.cocoa_sel("waitUntilCompleted\x00"))
    var result: [1]f32 = zero
    let r1 = os.raw_memcpy(mem.address_of(&result[0usize]), y_data + 1023usize * 4usize, 4usize)
    if result[0usize] != 5.0f32 {
        say("wrong answer\n")
        os.exit(8i32)
    }
    say("metal saxpy ok\n")
    os.objc_pool_pop(pool)
    ret ok
}
