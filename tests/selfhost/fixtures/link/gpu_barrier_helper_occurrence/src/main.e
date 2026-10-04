use e.gpu
use e.mem
use e.os

fn step(out: []u32) {
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
fn kernel(out: []u32) {
    for outer in 0u32..2u32 { step(out) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (buf, buf_error) = gpu.alloc[u32](q, 2usize)
    if buf_error != ok { os.exit(3i32) }
    if gpu.launch[kernel](q, gpu.grid1(2usize), buf) != ok { os.exit(4i32) }
    os.exit(5i32)
    ret ok
}
