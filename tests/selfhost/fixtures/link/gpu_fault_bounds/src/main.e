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
    try io.print("gpu fault ok\n")
    ret ok
}
