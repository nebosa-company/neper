// The fault buffer on the CPU backend (D785): a kernel indexing past `xs.len`
// writes one fault record instead of trapping, the faulting invocation is gone and
// the others finish; the next `sync` answers `Fault` once, naming the kernel's
// launch, the kind, the line and the invocation, and the queue keeps accepting
// work; `download` reports the same way; a second faulting invocation only counts;
// a faulted invocation in a barrier kernel is not divergence.

use e.gpu
use e.io
use e.mem
use e.os
use e.simd
// Invocation `bad` reads past the end; every other doubles its element.
@gpu(4)
fn poke(bad: u32, xs: []u32) {
    let i = gpu.gid.x
    var at = usize(i)
    if i == bad { at = xs.len + 3usize }
    xs[usize(i)] = xs[at] * 2u32
}

// Invocation 1 faults before the barrier; the rest wait at it and go on.
@gpu(4)
fn relay(xs: []u32) {
    let i = gpu.gid.x
    var at = usize(i)
    if i == 1u32 { at = 100usize }
    let mine = xs[at]
    gpu.barrier()
    xs[usize((i + 1u32) % 4u32)] = mine + 10u32
}

type Node = union enum u8 { Nil, Lit: u32 }

@gpu(1)
fn tagged(out: []u32) {
    var node: Node = .Nil
    out[0usize] = node.Lit
}

fn pointed(p: *u32) -> u32 { ret *p }

@gpu(1)
fn null_pointer(out: []u32) {
    var p: *u32 = nil
    out[0usize] = pointed(p)
}

@gpu(1)
fn arithmetic_unsigned(mode: u32, left: u32, right: u32, out: []u32) {
    if mode == 0u32 { out[0usize] = left + right }
    if mode == 1u32 { out[0usize] = left - right }
    if mode == 2u32 { out[0usize] = left * right }
    if mode == 3u32 { out[0usize] = left / right }
    if mode == 4u32 { out[0usize] = left % right }
}

@gpu(1)
fn arithmetic_signed(mode: u32, left: i32, right: i32, out: []u32) {
    if mode == 0u32 { out[0usize] = u32(left + right) }
    if mode == 1u32 { out[0usize] = u32(left - right) }
    if mode == 2u32 { out[0usize] = u32(left * right) }
    if mode == 3u32 { out[0usize] = u32(left / right) }
    if mode == 4u32 { out[0usize] = u32(left % right) }
}

@gpu(1)
fn alignment(out: []u32) {
    var value: Vec[u32, 4] = zero
    simd.store_aligned[Vec[u32, 4]](out, 1usize, value)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    var xs: [8]u32 = [8]u32{ 1u32, 2u32, 3u32, 4u32, 5u32, 6u32, 7u32, 8u32 }
    let (dx, dx_error) = gpu.upload[u32](q, xs[0..])
    if dx_error != ok { os.exit(3i32) }
    let (_, none) = gpu.last_fault(q)
    if none { os.exit(4i32) }
    // No fault: sync is ok and every element doubled.
    if gpu.launch[poke](q, gpu.grid1(8usize), 99u32, dx) != ok { os.exit(5i32) }
    if gpu.sync(q) != ok { os.exit(6i32) }
    var seen: [8]u32 = zero
    if gpu.download(q, dx, seen[0..]) != ok || seen[0] != 2u32 || seen[7] != 16u32 { os.exit(7i32) }
    // Invocation 5 faults: sync says so once, the record names it, the others ran.
    if gpu.launch[poke](q, gpu.grid1(8usize), 5u32, dx) != ok { os.exit(8i32) }
    if gpu.sync(q) != gpu.Fault { os.exit(9i32) }
    if gpu.sync(q) != ok { os.exit(10i32) }
    let (record, found) = gpu.last_fault(q)
    if !found || record.kernel != 1u32 || record.kind != .Bounds || record.site != 19u32 { os.exit(11i32) }
    if record.gid.x != 5u32 || record.gid.y != 0u32 || record.gid.z != 0u32 { os.exit(12i32) }
    if gpu.download(q, dx, seen[0..]) != ok || seen[4] != 20u32 || seen[5] != 12u32 || seen[6] != 28u32 { os.exit(13i32) }
    // `download` reports the fault too, and the queue keeps working.
    if gpu.launch[poke](q, gpu.grid1(8usize), 0u32, dx) != ok { os.exit(14i32) }
    if gpu.download(q, dx, seen[0..]) != gpu.Fault { os.exit(15i32) }
    if gpu.download(q, dx, seen[0..]) != ok || seen[0] != 4u32 || seen[1] != 16u32 { os.exit(16i32) }
    let (again, again_found) = gpu.last_fault(q)
    if !again_found || again.kernel != 2u32 || again.gid.x != 0u32 { os.exit(17i32) }
    // Two invocations fault in one launch: the first writer's record stands.
    let (dy, dy_error) = gpu.upload[u32](q, xs[0..])
    if dy_error != ok { os.exit(18i32) }
    if gpu.launch[poke](q, gpu.grid1(2usize), 1u32, dy) != ok { os.exit(19i32) }
    if gpu.launch[poke](q, gpu.grid1(2usize), 0u32, dy) != ok { os.exit(20i32) }
    if gpu.sync(q) != gpu.Fault { os.exit(21i32) }
    let (first, first_found) = gpu.last_fault(q)
    if !first_found || first.kernel != 3u32 || first.gid.x != 1u32 { os.exit(22i32) }
    // A barrier kernel: invocation 1 faults, 0, 2 and 3 pass the barrier and write.
    let (dz, dz_error) = gpu.upload[u32](q, xs[0..4])
    if dz_error != ok { os.exit(23i32) }
    if gpu.launch[relay](q, gpu.grid1(4usize), dz) != ok { os.exit(24i32) }
    if gpu.sync(q) != gpu.Fault { os.exit(25i32) }
    let (relayed, relayed_found) = gpu.last_fault(q)
    if !relayed_found || relayed.gid.x != 1u32 || relayed.site != 28u32 { os.exit(26i32) }
    if gpu.download(q, dz, seen[0..4]) != ok || seen[1] != 11u32 || seen[3] != 13u32 || seen[0] != 14u32 || seen[2] != 3u32 { os.exit(27i32) }
    if gpu.close(device) != ok { os.exit(28i32) }
    try vulkan_faults(a)
    try io.print("gpu fault ok\n")
    ret ok
}

fn expect_device_fault(q: *gpu.Queue, kernel: u32, kind: gpu.FaultKind, site: u32, code: i32) {
    if gpu.sync(q) != gpu.Fault { os.exit(code) }
    let (record, found) = gpu.last_fault(q)
    if !found || record.kernel != kernel || record.kind != kind || record.site != site || record.gid.x != 0u32 { os.exit(code) }
}

// The device path reports the same record, reports it once, and remains usable.
fn vulkan_fault(a: *mem.Arena, index: u32) -> err {
    let (device, device_error) = gpu.open(a, .Vulkan, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    var source: [8]u32 = [8]u32{ 1u32, 2u32, 3u32, 4u32, 5u32, 6u32, 7u32, 8u32 }
    let (buffer, buffer_error) = gpu.upload[u32](q, source[0..])
    if buffer_error != ok { ret buffer_error }
    defer let _ = gpu.release(q, buffer)
    try gpu.launch[poke](q, gpu.grid1(8usize), 5u32, buffer)
    if gpu.sync(q) != gpu.Fault || gpu.sync(q) != ok { os.exit(30i32) }
    let (record, found) = gpu.last_fault(q)
    if !found || record.kernel != 0u32 || record.kind != .Bounds || record.site != 19u32 || record.gid.x != 5u32 || record.gid.y != 0u32 || record.gid.z != 0u32 { os.exit(31i32) }
    var seen: [8]u32 = zero
    if gpu.download(q, buffer, seen[0..]) != ok || seen[4] != 10u32 || seen[5] != 6u32 || seen[6] != 14u32 { os.exit(32i32) }
    try gpu.launch[poke](q, gpu.grid1(8usize), 99u32, buffer)
    if gpu.download(q, buffer, seen[0..]) != ok || seen[0] != 4u32 || seen[5] != 12u32 { os.exit(33i32) }
    try gpu.launch[poke](q, gpu.grid1(8usize), 0u32, buffer)
    if gpu.download(q, buffer, seen[0..]) != gpu.Fault || gpu.download(q, buffer, seen[0..]) != ok { os.exit(34i32) }
    let (again, again_found) = gpu.last_fault(q)
    if !again_found || again.kernel != 2u32 || again.gid.x != 0u32 { os.exit(35i32) }
    try gpu.launch[tagged](q, gpu.grid1(1usize), buffer)
    if gpu.sync(q) != gpu.Fault { os.exit(36i32) }
    let (tagged_record, tagged_found) = gpu.last_fault(q)
    if !tagged_found || tagged_record.kernel != 3u32 || tagged_record.kind != .Tag || tagged_record.site != 38u32 || tagged_record.gid.x != 0u32 { os.exit(37i32) }
    try gpu.launch[null_pointer](q, gpu.grid1(1usize), buffer)
    if gpu.sync(q) != gpu.Fault { os.exit(38i32) }
    let (null_record, null_found) = gpu.last_fault(q)
    if !null_found || null_record.kernel != 4u32 || null_record.kind != .Null || null_record.site != 41u32 || null_record.gid.x != 0u32 { os.exit(39i32) }
    try gpu.launch[arithmetic_unsigned](q, gpu.grid1(1usize), 0u32, 4294967295u32, 1u32, buffer)
    expect_device_fault(q, 5u32, .Overflow, 51u32, 40i32)
    try gpu.launch[arithmetic_unsigned](q, gpu.grid1(1usize), 1u32, 0u32, 1u32, buffer)
    expect_device_fault(q, 6u32, .Overflow, 52u32, 41i32)
    try gpu.launch[arithmetic_unsigned](q, gpu.grid1(1usize), 2u32, 4294967295u32, 2u32, buffer)
    expect_device_fault(q, 7u32, .Overflow, 53u32, 42i32)
    try gpu.launch[arithmetic_unsigned](q, gpu.grid1(1usize), 3u32, 1u32, 0u32, buffer)
    expect_device_fault(q, 8u32, .DivideByZero, 54u32, 43i32)
    try gpu.launch[arithmetic_unsigned](q, gpu.grid1(1usize), 4u32, 1u32, 0u32, buffer)
    expect_device_fault(q, 9u32, .DivideByZero, 55u32, 44i32)
    let greatest = 2147483647i32
    let least = 0i32 - greatest - 1i32
    try gpu.launch[arithmetic_signed](q, gpu.grid1(1usize), 0u32, greatest, 1i32, buffer)
    expect_device_fault(q, 10u32, .Overflow, 60u32, 45i32)
    try gpu.launch[arithmetic_signed](q, gpu.grid1(1usize), 1u32, least, 1i32, buffer)
    expect_device_fault(q, 11u32, .Overflow, 61u32, 46i32)
    try gpu.launch[arithmetic_signed](q, gpu.grid1(1usize), 2u32, least, -1i32, buffer)
    expect_device_fault(q, 12u32, .Overflow, 62u32, 47i32)
    try gpu.launch[arithmetic_signed](q, gpu.grid1(1usize), 3u32, least, -1i32, buffer)
    expect_device_fault(q, 13u32, .DivideByZero, 63u32, 48i32)
    try gpu.launch[arithmetic_signed](q, gpu.grid1(1usize), 4u32, least, -1i32, buffer)
    expect_device_fault(q, 14u32, .DivideByZero, 64u32, 49i32)
    try gpu.launch[alignment](q, gpu.grid1(1usize), buffer)
    expect_device_fault(q, 15u32, .Alignment, 70u32, 50i32)
    ret ok
}

fn vulkan_faults(a: *mem.Arena) -> err {
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported { ret ok }
    if found_error != ok { ret found_error }
    var at = 0usize
    while at < found.len {
        if found[at].supported { try vulkan_fault(a, u32(at)) }
        at += 1usize
    }
    ret ok
}
