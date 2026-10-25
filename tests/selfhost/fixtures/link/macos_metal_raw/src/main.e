// `e.gpu.metal` alone (D5231): a device, kernels compiled from MSL text at run time, shared buffers and dispatches, each answer
// checked on the CPU. saxpy (y = 2 x + y over 1024 floats, four groups of 256) and a reversal of each group through threadgroup
// memory and a barrier (the shared-memory path a kernel with `shared var` needs), then a kernel that does not compile, which must
// answer CompileFailed and leave the device usable. A machine with no Metal device says so and passes. macOS only.
use e.mem
use e.os
use e.gpu.metal as mtl

fn word(bytes: []u8, index: usize) -> f32 {
    var holder: [1]f32 = zero
    let copied = os.raw_memcpy(mem.address_of(&holder[0usize]), mem.address_of(&bytes[index * 4usize]), 4usize)
    ret holder[0usize]
}

fn put(bytes: []u8, index: usize, value: f32) {
    var holder: [1]f32 = zero
    holder[0usize] = value
    let copied = os.raw_memcpy(mem.address_of(&bytes[index * 4usize]), mem.address_of(&holder[0usize]), 4usize)
}

fn main(a: *mem.Arena) -> err {
    if !mtl.available() {
        os.exit(0i32)
    }
    let (context, open_error) = mtl.open(a)
    if open_error != ok { os.exit(2i32) }
    let (x, x_error) = mtl.buffer(context, 4096usize)
    let (y, y_error) = mtl.buffer(context, 4096usize)
    if x_error != ok { os.exit(3i32) }
    if y_error != ok { os.exit(4i32) }
    var at = 0usize
    while at < 1024usize {
        put(x.bytes, at, f32(at))
        put(y.bytes, at, 3.0f32)
        at += 1usize
    }
    let saxpy = "#include <metal_stdlib>\nusing namespace metal;\nkernel void saxpy(device const float* x [[buffer(0)]], device float* y [[buffer(1)]], uint i [[thread_position_in_grid]]) { y[i] = 2.0f * x[i] + y[i]; }\n"
    let (pipeline, compile_error) = mtl.compile(context, saxpy, "saxpy")
    if compile_error != ok { os.exit(5i32) }
    var both: [2]mtl.Buffer = zero
    both[0usize] = x
    both[1usize] = y
    let run = mtl.dispatch(context, pipeline, both[..], mtl.Size { width: 4usize, height: 1usize, depth: 1usize }, mtl.Size { width: 256usize, height: 1usize, depth: 1usize }, 0usize)
    if run != ok { os.exit(6i32) }
    at = 0usize
    while at < 1024usize {
        if word(y.bytes, at) != 2.0f32 * f32(at) + 3.0f32 { os.exit(7i32) }
        at += 1usize
    }
    // Each group of 256 reversed through threadgroup memory: out[g*256 + i] = in[g*256 + 255 - i].
    let reverse = "#include <metal_stdlib>\nusing namespace metal;\nkernel void reverse(device const float* in [[buffer(0)]], device float* out [[buffer(1)]], threadgroup float* tile [[threadgroup(0)]], uint i [[thread_index_in_threadgroup]], uint g [[threadgroup_position_in_grid]]) { tile[i] = in[g * 256u + i]; threadgroup_barrier(mem_flags::mem_threadgroup); out[g * 256u + i] = tile[255u - i]; }\n"
    let (reverser, reverse_error) = mtl.compile(context, reverse, "reverse")
    if reverse_error != ok { os.exit(8i32) }
    let reversed = mtl.dispatch(context, reverser, both[..], mtl.Size { width: 4usize, height: 1usize, depth: 1usize }, mtl.Size { width: 256usize, height: 1usize, depth: 1usize }, 1024usize)
    if reversed != ok { os.exit(9i32) }
    at = 0usize
    while at < 1024usize {
        let group = at / 256usize
        let lane = at % 256usize
        if word(y.bytes, at) != f32(group * 256usize + 255usize - lane) { os.exit(10i32) }
        at += 1usize
    }
    // A kernel with a mistake in it is refused by name and the device goes on working.
    let (broken, broken_error) = mtl.compile(context, "kernel void oops( {", "oops")
    if broken_error != mtl.CompileFailed { os.exit(11i32) }
    put(y.bytes, 0usize, 1.0f32)
    put(x.bytes, 0usize, 1.0f32)
    let again = mtl.dispatch(context, pipeline, both[..], mtl.Size { width: 1usize, height: 1usize, depth: 1usize }, mtl.Size { width: 1usize, height: 1usize, depth: 1usize }, 0usize)
    if again != ok { os.exit(12i32) }
    if word(y.bytes, 0usize) != 3.0f32 { os.exit(13i32) }
    mtl.destroy(pipeline)
    mtl.destroy(reverser)
    mtl.free(x)
    mtl.free(y)
    mtl.close(context)
    ret ok
}
