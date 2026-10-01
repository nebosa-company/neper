// A `@nocheck` block in a kernel (D785, contract section 1.3) carries no bounds
// check and no fault: the read past the end is whatever follows the buffer, the
// launch syncs `ok` with no record, and the result is unspecified.

use e.gpu
use e.io
use e.mem
use e.os

@gpu(4)
fn poke(offset: u32, xs: []u32, ys: []u32) {
    let i = gpu.gid.x
    @nocheck {
        ys[usize(i)] = xs[usize(i) + usize(offset)] + 10u32
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    var xs: [8]u32 = zero
    let (dx, dx_error) = gpu.upload[u32](q, xs[0..])
    if dx_error != ok { os.exit(3i32) }
    let (dy, dy_error) = gpu.alloc[u32](q, 4usize)
    if dy_error != ok { os.exit(4i32) }
    if gpu.launch[poke](q, gpu.grid1(4usize), 8u32, dx, dy) != ok { os.exit(5i32) }
    if gpu.sync(q) != ok { os.exit(6i32) }
    let (_, found) = gpu.last_fault(q)
    if found { os.exit(7i32) }
    var seen: [4]u32 = zero
    if gpu.download(q, dy, seen[0..]) != ok { os.exit(8i32) }
    if gpu.close(device) != ok { os.exit(9i32) }
    try vulkan_nochecks(a)
    try io.print("gpu nocheck ok\n")
    ret ok
}

// The check-free SPIR-V ABI has no hidden fault address: exact parameter values and
// output prove that its first ordinary argument starts at byte zero.
fn vulkan_nocheck(a: *mem.Arena, index: u32) -> err {
    let (device, device_error) = gpu.open(a, .Vulkan, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    var source: [8]u32 = [8]u32{ 1u32, 2u32, 3u32, 4u32, 5u32, 6u32, 7u32, 8u32 }
    let (dx, dx_error) = gpu.upload[u32](q, source[0..])
    if dx_error != ok { ret dx_error }
    let (dy, dy_error) = gpu.alloc[u32](q, 4usize)
    if dy_error != ok { ret dy_error }
    try gpu.launch[poke](q, gpu.grid1(4usize), 0u32, dx, dy)
    if gpu.sync(q) != ok { os.exit(10i32) }
    let (_, found) = gpu.last_fault(q)
    if found { os.exit(11i32) }
    var seen: [4]u32 = zero
    if gpu.download(q, dy, seen[0..]) != ok { os.exit(12i32) }
    if seen[0] != 11u32 || seen[1] != 12u32 || seen[2] != 13u32 || seen[3] != 14u32 { os.exit(13i32) }
    ret ok
}

fn vulkan_nochecks(a: *mem.Arena) -> err {
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported { ret ok }
    if found_error != ok { ret found_error }
    var at = 0usize
    while at < found.len {
        if found[at].supported { try vulkan_nocheck(a, u32(at)) }
        at += 1usize
    }
    ret ok
}
