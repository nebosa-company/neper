// Divergence on the CPU backend (D780): invocation 2 of the workgroup returns before
// the barrier its peers reach, which a device would turn into a hang; the CPU build
// traps as `barrier`, naming both invocations. The runner expects the trap.

use e.gpu
use e.mem
use e.os

@gpu(4)
fn early(buf: []u32) {
    if gpu.lid.x == 2u32 { ret }
    buf[usize(gpu.lid.x)] = 1u32
    gpu.barrier()
    buf[usize(gpu.lid.x)] = 2u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (buf, buf_error) = gpu.alloc[u32](q, 4usize)
    if buf_error != ok { os.exit(3i32) }
    if gpu.launch[early](q, gpu.grid1(4usize), buf) != ok { os.exit(4i32) }
    os.exit(5i32)
    ret ok
}
