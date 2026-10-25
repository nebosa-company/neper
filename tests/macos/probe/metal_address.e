// Can an MSL kernel use a device address as a pointer, as the SPIR-V kernels do (the launch block holds buffer addresses)? A block
// of two 64-bit addresses (MTLBuffer gpuAddress) is bound as buffer 0; the kernel casts them to device pointers and runs saxpy.
use e.mem
use e.os
use e.gpu.metal as mtl

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn number(value: usize) {
    if value >= 10usize { number(value / 10usize) }
    var one: [1]u8 = zero
    one[0usize] = u8(48usize + value % 10usize)
    let (written, write_error) = os.write(os.stdout(), one[..])
}

fn main(a: *mem.Arena) -> err {
    if !mtl.available() { os.exit(2i32) }
    let (context, open_error) = mtl.open(a)
    if open_error != ok { os.exit(3i32) }
    let (x, x_error) = mtl.buffer(context, 4096usize)
    let (y, y_error) = mtl.buffer(context, 4096usize)
    let (block, block_error) = mtl.buffer(context, 64usize)
    if x_error != ok || y_error != ok || block_error != ok { os.exit(4i32) }
    var one: [1]f32 = zero
    one[0usize] = 1.0f32
    var three: [1]f32 = zero
    three[0usize] = 3.0f32
    var at = 0usize
    while at < 1024usize {
        let c1 = os.raw_memcpy(mem.address_of(&x.bytes[at * 4usize]), mem.address_of(&one[0usize]), 4usize)
        let c2 = os.raw_memcpy(mem.address_of(&y.bytes[at * 4usize]), mem.address_of(&three[0usize]), 4usize)
        at += 1usize
    }
    // gpuAddress is a 64-bit property (MTLBuffer, macOS 13+): read through objc_msgSend returning an integer.
    let x_address = os.msg0(x.handle, os.cocoa_sel("gpuAddress\x00"))
    let y_address = os.msg0(y.handle, os.cocoa_sel("gpuAddress\x00"))
    var words: [2]usize = zero
    words[0usize] = x_address
    words[1usize] = y_address
    let c3 = os.raw_memcpy(mem.address_of(&block.bytes[0usize]), mem.address_of(&words[0usize]), 16usize)
    let source = "#include <metal_stdlib>\nusing namespace metal;\nkernel void by_address(device const ulong* block [[buffer(0)]], uint i [[thread_position_in_grid]]) { device const float* x = (device const float*)block[0]; device float* y = (device float*)block[1]; y[i] = 2.0f * x[i] + y[i]; }\n"
    let (pipeline, compile_error) = mtl.compile(context, source, "by_address")
    if compile_error != ok {
        say("address cast did not compile\n")
        os.exit(5i32)
    }
    say("address cast compiled\n")
    // The pointed-to buffers must be resident: useResource on the encoder, which dispatch() does not do, so the buffers are also
    // bound at higher indices where the system makes them resident.
    var all: [3]mtl.Buffer = zero
    all[0usize] = block
    all[1usize] = x
    all[2usize] = y
    let run = mtl.dispatch(context, pipeline, all[..], mtl.Size { width: 4usize, height: 1usize, depth: 1usize }, mtl.Size { width: 256usize, height: 1usize, depth: 1usize }, 0usize)
    if run != ok { os.exit(6i32) }
    var result: [1]f32 = zero
    let c4 = os.raw_memcpy(mem.address_of(&result[0usize]), mem.address_of(&y.bytes[1023usize * 4usize]), 4usize)
    if result[0usize] != 5.0f32 {
        say("y[1023] was ")
        number(usize(result[0usize]))
        say(" (3 untouched, 5 right)\n")
        say("wrong answer through addresses\n")
        os.exit(7i32)
    }
    say("metal by address ok\n")
    ret ok
}
