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

@gpu(8)
fn for_rounds(buf: []u32, n: u32) {
    let limit = n + 1u32
    for round in 0u32..limit {
        buf[usize(gpu.lid.x)] += round + 1u32
        gpu.barrier()
    }
}

@gpu(8)
fn collection_rounds(out: []u32, weights: []u32) {
    for weight in weights {
        out[usize(gpu.lid.x)] += weight
        gpu.barrier()
    }
}

@gpu(8)
fn large_frame(out: []u32) {
    var local: [96]u64 = zero
    local[0usize] = u64(gpu.lid.x) + 41u64
    gpu.barrier()
    out[usize(gpu.lid.x)] = u32(local[0usize])
}

@gpu(16)
fn plain(n: u32, out: []u32) {
    if gpu.gid.x >= n { ret }
    out[usize(gpu.gid.x)] = gpu.gid.x * 3u32
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, relay_out: []u32, round_out: []u32, plain_out: []u32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }

    // relay over two workgroups of 64.
    var values: [128]u32 = zero
    var i = 0usize
    while i < 128usize {
        values[i] = u32(i) * 10u32
        i += 1usize
    }
    let (buf, buf_error) = gpu.upload[u32](q, values[0..])
    if buf_error != ok { ret buf_error }
    defer let _ = gpu.release(q, buf)
    try gpu.launch[relay](q, gpu.grid1(128usize), buf)
    try gpu.download[u32](q, buf, relay_out)

    // rounds: from [1, 0, 0, 0, 0, 0, 0, 0] three rounds of adding the left neighbour.
    var ring: [8]u32 = zero
    ring[0] = 1u32
    let (ring_buf, ring_error) = gpu.upload[u32](q, ring[0..])
    if ring_error != ok { ret ring_error }
    defer let _ = gpu.release(q, ring_buf)
    try gpu.launch[rounds](q, gpu.grid1(8usize), ring_buf)
    try gpu.download[u32](q, ring_buf, round_out)

    // A runtime-bound for loop must retain its bound and counter across cuts.
    var for_values: [8]u32 = zero
    let (for_buf, for_error) = gpu.upload[u32](q, for_values[0..])
    if for_error != ok { ret for_error }
    defer let _ = gpu.release(q, for_buf)
    let scratch_before = mem.mark(a)
    try gpu.launch[for_rounds](q, gpu.grid1(8usize), for_buf, 2u32)
    if backend == .Cpu && mem.mark(a) != scratch_before { os.exit(17i32) }
    var for_out: [8]u32 = zero
    try gpu.download[u32](q, for_buf, for_out[0..])
    var for_at = 0usize
    while for_at < for_out.len {
        if for_out[for_at] != 6u32 { os.exit(15i32) }
        for_at += 1usize
    }
    var weights: [3]u32 = [3]u32{ 1u32, 2u32, 3u32 }
    let (weights_buf, weights_error) = gpu.upload[u32](q, weights[0..])
    if weights_error != ok { ret weights_error }
    defer let _ = gpu.release(q, weights_buf)
    var collection_values: [8]u32 = zero
    let (collection_buf, collection_error) = gpu.upload[u32](q, collection_values[0..])
    if collection_error != ok { ret collection_error }
    defer let _ = gpu.release(q, collection_buf)
    try gpu.launch[collection_rounds](q, gpu.grid1(8usize), collection_buf, weights_buf)
    var collection_out: [8]u32 = zero
    try gpu.download[u32](q, collection_buf, collection_out[0..])
    var collection_at = 0usize
    while collection_at < collection_out.len {
        if collection_out[collection_at] != 6u32 { os.exit(16i32) }
        collection_at += 1usize
    }
    if backend == .Cpu {
        var large_values: [8]u32 = zero
        let (large_buf, large_error) = gpu.upload[u32](q, large_values[0..])
        if large_error != ok { ret large_error }
        defer let _ = gpu.release(q, large_buf)
        try gpu.launch[large_frame](q, gpu.grid1(8usize), large_buf)
        var large_out: [8]u32 = zero
        try gpu.download[u32](q, large_buf, large_out[0..])
        var large_at = 0usize
        while large_at < large_out.len {
            if large_out[large_at] != u32(large_at) + 41u32 { os.exit(18i32) }
            large_at += 1usize
        }
    }

    // A kernel without a barrier under the same model.
    let (plain_buf, plain_error) = gpu.alloc[u32](q, 40usize)
    if plain_error != ok { ret plain_error }
    defer let _ = gpu.release(q, plain_buf)
    try gpu.launch[plain](q, gpu.grid1(40usize), 40u32, plain_buf)
    ret gpu.download[u32](q, plain_buf, plain_out)
}

fn same(a: []const u32, b: []const u32) -> bool {
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret a.len == b.len
}

fn main(a: *mem.Arena, args: []str) -> err {
    var out: [128]u32 = zero
    var after: [8]u32 = zero
    var plain_out: [40]u32 = zero
    try run(a, .Cpu, 0u32, out[0..], after[0..], plain_out[0..])
    var i = 0usize
    while i < 128usize {
        let group = i / 64usize
        let local = i % 64usize
        let predecessor = group * 64usize + (local + 63usize) % 64usize
        if out[i] != (u32(predecessor) * 10u32 + 1u32) * 2u32 { os.exit(6i32) }
        i += 1usize
    }
    // Round 1: [1, 1, 0, ...]; round 2: [1, 2, 1, 0, ...]; round 3: [1, 3, 3, 1, 0, ...].
    if after[0] != 1u32 || after[1] != 3u32 || after[2] != 3u32 || after[3] != 1u32 || after[4] != 0u32 || after[7] != 0u32 { os.exit(10i32) }
    if plain_out[39] != 117u32 || plain_out[0] != 0u32 { os.exit(13i32) }

    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error != gpu.NoDevice && found_error != gpu.Unsupported {
        if found_error != ok { ret found_error }
        var at = 0usize
        while at < found.len {
            if found[at].supported {
                var device_out: [128]u32 = zero
                var device_after: [8]u32 = zero
                var device_plain: [40]u32 = zero
                try run(a, .Vulkan, u32(at), device_out[0..], device_after[0..], device_plain[0..])
                if !same(out[0..], device_out[0..]) || !same(after[0..], device_after[0..]) || !same(plain_out[0..], device_plain[0..]) { os.exit(14i32) }
            }
            at += 1usize
        }
    }

    try io.print("gpu barrier ok\n")
    ret ok
}
