// `shared var` on the CPU backend (D781): the spec's block sum -- a tile in workgroup
// memory filled by every invocation, a barrier, a tree reduction across barriers --
// over several workgroups; a struct-typed shared var beside an array; and a read
// before the publishing barrier sees the 0xCD fill rather than a neighbour's value.

use e.gpu
use e.io
use e.mem
use e.os

// out[wgid] = sum of the workgroup's 64 inputs, reduced pairwise in shared memory.
@gpu(64)
fn block_sum(xs: []const f32, out: []f32) {
    shared var tile: [64]f32
    let i = gpu.lid.x
    tile[usize(i)] = xs[usize(gpu.gid.x)]
    gpu.barrier()
    var stride = 32u32
    while stride > 0u32 {
        if i < stride {
            tile[usize(i)] = tile[usize(i)] + tile[usize(i + stride)]
        }
        gpu.barrier()
        stride = stride / 2u32
    }
    if i == 0u32 { out[usize(gpu.wgid.x)] = tile[0] }
}

type Tally = struct { count: u32, largest: u32 }

// Invocation 0 publishes a struct after the barrier the others wrote their values
// under; every invocation then reads it.
@gpu(8)
fn tally(values: []const u32, out: []u32) {
    shared var slots: [8]u32
    shared var summary: Tally
    let i = gpu.lid.x
    slots[usize(i)] = values[usize(gpu.gid.x)]
    gpu.barrier()
    if i == 0u32 {
        var largest = 0u32
        var k = 0usize
        while k < 8usize {
            if slots[k] > largest { largest = slots[k] }
            k += 1usize
        }
        summary = Tally { count: 8u32, largest: largest }
    }
    gpu.barrier()
    out[usize(gpu.gid.x)] = summary.largest * summary.count + slots[usize((i + 1u32) % 8u32)]
}

// Read before the barrier: the byte the fill left, not what a peer wrote.
@gpu(4)
fn early_read(out: []u8) {
    shared var marks: [4]u8
    let i = gpu.lid.x
    out[usize(i)] = marks[usize((i + 1u32) % 4u32)]
    gpu.barrier()
    marks[usize(i)] = 1u8
}

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.001 && d > -0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }

    // block_sum over 192 inputs: three workgroups.
    var xs: [192]f32 = zero
    var i = 0usize
    while i < 192usize {
        xs[i] = f32(i % 64usize) + 0.5
        i += 1usize
    }
    let (dx, dx_error) = gpu.upload[f32](q, xs[0..])
    if dx_error != ok { os.exit(3i32) }
    let (sums, sums_error) = gpu.alloc[f32](q, 3usize)
    if sums_error != ok { os.exit(4i32) }
    if gpu.launch[block_sum](q, gpu.grid1(192usize), dx, sums) != ok { os.exit(5i32) }
    var out: [3]f32 = zero
    if gpu.download[f32](q, sums, out[0..]) != ok { os.exit(6i32) }
    // Each workgroup sums 0.5 + 1.5 + ... + 63.5 = 2048.
    if !near(out[0], 2048.0) || !near(out[1], 2048.0) || !near(out[2], 2048.0) { os.exit(7i32) }

    // tally over 16 values: two workgroups, each with its own largest.
    var values: [16]u32 = [16]u32{ 3u32, 9u32, 1u32, 4u32, 7u32, 2u32, 8u32, 5u32, 10u32, 20u32, 30u32, 40u32, 50u32, 60u32, 70u32, 80u32 }
    let (dv, dv_error) = gpu.upload[u32](q, values[0..])
    if dv_error != ok { os.exit(8i32) }
    let (dt, dt_error) = gpu.alloc[u32](q, 16usize)
    if dt_error != ok { os.exit(9i32) }
    if gpu.launch[tally](q, gpu.grid1(16usize), dv, dt) != ok { os.exit(10i32) }
    var tallies: [16]u32 = zero
    if gpu.download[u32](q, dt, tallies[0..]) != ok { os.exit(11i32) }
    // Group 0: largest 9, times 8, plus the next slot's value.
    if tallies[0] != 72u32 + 9u32 || tallies[7] != 72u32 + 3u32 { os.exit(12i32) }
    // Group 1: largest 80.
    if tallies[8] != 640u32 + 20u32 || tallies[15] != 640u32 + 10u32 { os.exit(13i32) }

    // early_read: the 0xCD fill.
    let (dm, dm_error) = gpu.alloc[u8](q, 4usize)
    if dm_error != ok { os.exit(14i32) }
    if gpu.launch[early_read](q, gpu.grid1(4usize), dm) != ok { os.exit(15i32) }
    var marks: [4]u8 = zero
    if gpu.download[u8](q, dm, marks[0..]) != ok { os.exit(16i32) }
    if marks[0] != 205u8 || marks[3] != 205u8 { os.exit(17i32) }

    try io.print("gpu shared ok\n")
    ret ok
}
