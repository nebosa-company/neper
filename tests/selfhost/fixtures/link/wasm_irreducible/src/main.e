// A function the structured control flow of wasm32-wasi cannot take (D5635): a kernel with a
// barrier inside nested loops runs in frame mode, which cuts the loops at the barrier and leaves
// a retreating edge into a block that does not dominate its source -- an irreducible graph,
// written by the dispatch loop instead. Nothing in the source says goto; the barrier does it.
// The exit status says which check failed. `NEPER_WASM_STATS=1` makes the emitter report the
// fallback (`dispatch 1 (irreducible 1)`), which tests/selfhost/run.sh asserts.
use e.gpu
use e.mem
use e.os

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

fn main(a: *mem.Arena) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (buf, buf_error) = gpu.alloc[u32](q, 2usize)
    if buf_error != ok { os.exit(3i32) }
    var values: [2]u32 = zero
    if gpu.launch[nested](q, gpu.grid1(2usize), buf) != ok { os.exit(4i32) }
    if gpu.download[u32](q, buf, values[0..]) != ok { os.exit(5i32) }
    if values[0usize] != 4u32 || values[1usize] != 4u32 { os.exit(6i32) }
    ret ok
}
