// 32-bit relaxed atomics and workgroup memory through the MSL emitter (C193, D5840): every invocation adds to one device word and
// to one workgroup word, a workgroup barrier, and the totals must be exact. The kernel is the program's own, written
// as MSL by the compiler and run through `gpu.launch` on a Metal device. A machine with no Metal device says so and passes. macOS only.
use e.mem
use e.os
use e.gpu
use e.atomic

@gpu(64, ftz)
fn count(words: []Atomic[u32], output: []u32) {
    shared var local: Atomic[u32]
    shared var tile: [64]u32
    let lane = gpu.lid.x
    if lane == 0u32 { gpu.atomic_store(&local, 0u32, .Relaxed, .Workgroup) }
    gpu.barrier()
    tile[usize(lane)] = lane + 1u32
    let before = gpu.atomic_add(&local, 1u32, .Relaxed, .Workgroup)
    let device_before = gpu.atomic_add(&words[0usize], 2u32, .Relaxed, .Device)
    gpu.barrier()
    if lane == 0u32 { output[usize(gpu.wgid.x)] = tile[63usize] + gpu.atomic_load(&local, .Relaxed, .Workgroup) }
}

@gpu(64, ftz)
fn ordered(words: []Atomic[u32]) {
    let before = gpu.atomic_add(&words[0usize], 1u32, .AcqRel, .Device)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (found, found_error) = gpu.devices(a, .Metal, 4usize)
    if found_error != ok { os.exit(0i32) }
    if found.len == 0usize { os.exit(0i32) }
    let (dev, open_error) = gpu.open(a, .Metal, 0u32)
    if open_error != ok { os.exit(2i32) }
    let (q, q_error) = gpu.queue(dev)
    if q_error != ok { os.exit(3i32) }
    var words: [1]Atomic[u32] = zero
    words[0usize] = atomic.init(0u32)
    var output: [8]u32 = zero
    let (dw, dw_error) = gpu.upload[Atomic[u32]](q, words[0..])
    let (dout, dout_error) = gpu.upload[u32](q, output[0..])
    if dw_error != ok || dout_error != ok { os.exit(4i32) }
    if gpu.launch[count](q, gpu.grid1(512usize), dw, dout) != ok { os.exit(5i32) }
    if gpu.download(q, dw, words[0..]) != ok { os.exit(6i32) }
    if gpu.download(q, dout, output[0..]) != ok { os.exit(7i32) }
    if atomic.load(&words[0usize], .Acquire) != 1024u32 { os.exit(8i32) }
    var at = 0usize
    while at < 8usize {
        if output[at] != 64u32 + 64u32 { os.exit(9i32) }
        at += 1usize
    }
    // An order stronger than relaxed has no MSL here: the launch is refused, not run weaker (spec section 12).
    if gpu.launch[ordered](q, gpu.grid1(64usize), dw) != gpu.Unsupported { os.exit(10i32) }
    let closed = gpu.close(dev)
    ret ok
}
