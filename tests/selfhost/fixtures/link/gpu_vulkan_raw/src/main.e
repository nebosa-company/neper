// The Vulkan runtime alone (D1611): saxpy's pinned SPIR-V module, dispatched on every
// device at section 10's floor through `e.gpu.vulkan`, and every result checked against
// the CPU's `2 * x + y` bit for bit. A machine without a loader or a device says so and
// passes: the device run is hardware-gated, never a CPU fallback.
use e.mem
use e.os
use e.fs
use e.io
use e.gpu.vulkan as vk

fn put_word(bytes: []u8, at: usize, value: u32) {
    bytes[at] = u8(value & 255u32)
    bytes[at + 1usize] = u8((value >> 8u32) & 255u32)
    bytes[at + 2usize] = u8((value >> 16u32) & 255u32)
    bytes[at + 3usize] = u8((value >> 24u32) & 255u32)
}

fn word(bytes: []const u8, at: usize) -> u32 {
    ret u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32) | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn put_address(bytes: []u8, at: usize, address: u64) {
    put_word(bytes, at, u32(address & 4294967295u64))
    put_word(bytes, at + 4usize, u32(address >> 32u64))
}

// saxpy on one device: 4096 elements, `n` of them computed.
fn run(a: *mem.Arena, physical: vk.Physical, code: []const u8, n: u32) -> err {
    let (context, context_error) = vk.open(a, physical)
    if context_error != ok { ret context_error }
    defer vk.close(context)
    let (x, x_error) = vk.buffer(a, context, 16384usize)
    if x_error != ok { ret x_error }
    defer vk.free(context, x)
    let (y, y_error) = vk.buffer(a, context, 16384usize)
    if y_error != ok { ret y_error }
    defer vk.free(context, y)
    let (block, block_error) = vk.buffer(a, context, 64usize)
    if block_error != ok { ret block_error }
    defer vk.free(context, block)
    let (fault, fault_error) = vk.buffer(a, context, 32usize)
    if fault_error != ok { ret fault_error }
    defer vk.free(context, fault)
    var clear_at = 0usize
    while clear_at < fault.bytes.len {
        fault.bytes[clear_at] = 0u8
        clear_at += 1usize
    }
    var i = 0usize
    while i < 4096usize {
        put_word(x.bytes, i * 4usize, mem.bitcast[u32](f32(i)))
        put_word(y.bytes, i * 4usize, mem.bitcast[u32](1.0f32))
        i += 1usize
    }
    // The checked argument block: fault @0, n @8, a @12, x @16 and y @32.
    put_address(block.bytes, 0usize, fault.address)
    put_word(block.bytes, 8usize, n)
    put_word(block.bytes, 12usize, mem.bitcast[u32](2.0f32))
    put_address(block.bytes, 16usize, x.address)
    put_word(block.bytes, 24usize, 4096u32)
    put_address(block.bytes, 32usize, y.address)
    put_word(block.bytes, 40usize, 4096u32)
    let (made, made_error) = vk.pipeline(a, context, code, "saxpy.saxpy")
    if made_error != ok { ret made_error }
    defer vk.destroy(context, made)
    try vk.dispatch(a, context, made, block.address, 16u32, 1u32, 1u32)
    if word(fault.bytes, 0usize) != 0u32 { os.exit(9i32) }
    i = 0usize
    while i < 4096usize {
        var expected = 1.0f32
        if i < usize(n) { expected = 2.0f32 * f32(i) + 1.0f32 }
        if word(y.bytes, i * 4usize) != mem.bitcast[u32](expected) { os.exit(i32(10usize + i % 100usize)) }
        i += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { os.exit(2i32) }
    let (code, code_error) = fs.read_file(a, args[1usize], 1048576usize)
    if code_error != ok { os.exit(3i32) }
    let (found, found_error) = vk.devices(a, 16usize)
    if found_error == vk.NoLoader || found_error == vk.NoDevice {
        try io.printf["no vulkan device\n"]()
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var at = 0usize
    while at < found.len {
        if found[at].floor {
            try run(a, found[at], code, 4096u32)
            try run(a, found[at], code, 4000u32)
            ran += 1usize
        }
        at += 1usize
    }
    try io.printf["vulkan saxpy ok on {} devices\n"](ran)
    ret ok
}
