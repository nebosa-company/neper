// One lane skips the first loop body's barrier and reaches the same static
// barrier in iteration two; its peer reaches it in iteration one. The CPU
// backend must not pair these different dynamic occurrences.
use e.gpu
use e.mem
use e.os

@gpu(2)
fn mismatched(out: []u32) {
    var iteration = 0u32
    while iteration < 2u32 {
        if gpu.lid.x == 0u32 && iteration == 0u32 {
            iteration += 1u32
            continue
        }
        if gpu.lid.x == 1u32 && iteration == 1u32 { break }
        gpu.barrier()
        out[usize(gpu.lid.x)] = iteration
        iteration += 1u32
    }
}

@gpu(2)
fn mismatched_for(out: []u32) {
    for iteration in 0u32..2u32 {
        if gpu.lid.x == 0u32 && iteration == 0u32 { continue }
        if gpu.lid.x == 1u32 && iteration == 1u32 { break }
        gpu.barrier()
        out[usize(gpu.lid.x)] = iteration
    }
}

@gpu(2)
fn nested(out: []u32) {
    var outer = 0u32
    var total = 0u32
    while outer < 2u32 {
        for inner in 0u32..2u32 {
            total += 1u32
            gpu.barrier()
        }
        outer += 1u32
    }
    out[usize(gpu.lid.x)] = total
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (buf, buf_error) = gpu.alloc[u32](q, 2usize)
    if buf_error != ok { os.exit(3i32) }
    if gpu.launch[nested](q, gpu.grid1(2usize), buf) != ok { os.exit(6i32) }
    var values: [2]u32 = zero
    if gpu.download[u32](q, buf, values[0..]) != ok || values[0usize] != 4u32 || values[1usize] != 4u32 { os.exit(7i32) }
    if args.len == 2usize {
        if gpu.launch[mismatched_for](q, gpu.grid1(2usize), buf) != ok { os.exit(4i32) }
    } else {
        if gpu.launch[mismatched](q, gpu.grid1(2usize), buf) != ok { os.exit(4i32) }
    }
    os.exit(5i32)
    ret ok
}
