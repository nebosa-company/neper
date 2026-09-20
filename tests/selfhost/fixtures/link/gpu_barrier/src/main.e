// `gpu.barrier()` on the CPU backend (D780): a kernel whose invocations hand values
// to their neighbours through device memory across three barriers, with locals
// that live across them, comes out exactly as the workgroup-synchronous order
// says; a barrier inside a loop is reached once per iteration by every invocation;
// two workgroups of the same launch do not see each other's barriers; and a kernel
// with no barrier still runs under the same frames.

use e.gpu
use e.io
use e.mem
use e.os

// Each invocation reads its own slot, publishes it to the next slot, reads what its
// predecessor published, and doubles it: buf[j] = (old buf[j - 1] + 1) * 2, ring-wise.
@gpu(64)
fn relay(buf: []u32) {
    let i = gpu.lid.x
    let base = gpu.wgid.x * 64u32
    let mine = buf[usize(base + i)]
    gpu.barrier()
    buf[usize(base + (i + 1u32) % 64u32)] = mine + 1u32
    gpu.barrier()
    let seen = buf[usize(base + i)]
    gpu.barrier()
    buf[usize(base + i)] = seen * 2u32
}

// Three rounds: every round each invocation adds its predecessor's current value,
// so the barrier in the loop keeps the rounds apart.
@gpu(8)
fn rounds(buf: []u32) {
    let i = gpu.lid.x
    var round = 0u32
    while round < 3u32 {
        let left = buf[usize((i + 7u32) % 8u32)]
        gpu.barrier()
        buf[usize(i)] = buf[usize(i)] + left
        gpu.barrier()
        round += 1u32
    }
}

@gpu(16)
fn plain(n: u32, out: []u32) {
    if gpu.gid.x >= n { ret }
    out[usize(gpu.gid.x)] = gpu.gid.x * 3u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }

    // relay over two workgroups of 64.
    var values: [128]u32 = zero
    var i = 0usize
    while i < 128usize {
        values[i] = u32(i) * 10u32
        i += 1usize
    }
    let (buf, buf_error) = gpu.upload[u32](q, values[0..])
    if buf_error != ok { os.exit(3i32) }
    if gpu.launch[relay](q, gpu.grid1(128usize), buf) != ok { os.exit(4i32) }
    var out: [128]u32 = zero
    if gpu.download[u32](q, buf, out[0..]) != ok { os.exit(5i32) }
    i = 0usize
    while i < 128usize {
        let group = i / 64usize
        let local = i % 64usize
        let predecessor = group * 64usize + (local + 63usize) % 64usize
        if out[i] != (values[predecessor] + 1u32) * 2u32 { os.exit(6i32) }
        i += 1usize
    }

    // rounds: from [1, 0, 0, 0, 0, 0, 0, 0] three rounds of adding the left neighbour.
    var ring: [8]u32 = zero
    ring[0] = 1u32
    let (ring_buf, ring_error) = gpu.upload[u32](q, ring[0..])
    if ring_error != ok { os.exit(7i32) }
    if gpu.launch[rounds](q, gpu.grid1(8usize), ring_buf) != ok { os.exit(8i32) }
    var after: [8]u32 = zero
    if gpu.download[u32](q, ring_buf, after[0..]) != ok { os.exit(9i32) }
    // Round 1: [1, 1, 0, ...]; round 2: [1, 2, 1, 0, ...]; round 3: [1, 3, 3, 1, 0, ...].
    if after[0] != 1u32 || after[1] != 3u32 || after[2] != 3u32 || after[3] != 1u32 || after[4] != 0u32 || after[7] != 0u32 { os.exit(10i32) }

    // A kernel without a barrier under the same model.
    let (plain_buf, plain_error) = gpu.alloc[u32](q, 40usize)
    if plain_error != ok { os.exit(11i32) }
    if gpu.launch[plain](q, gpu.grid1(40usize), 40u32, plain_buf) != ok { os.exit(12i32) }
    var plain_out: [40]u32 = zero
    if gpu.download[u32](q, plain_buf, plain_out[0..]) != ok || plain_out[39] != 117u32 || plain_out[0] != 0u32 { os.exit(13i32) }

    try io.print("gpu barrier ok\n")
    ret ok
}
