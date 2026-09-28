// A kernel's `@gpu` and workgroup size are in its signature (D1677): `main`'s launcher
// bakes the size in, and a direct call to a kernel is refused, so a warm build after
// either changes rebuilds `main` or refuses it as a clean build does. `k.seed` puts 10
// where no invocation writes, and the exit is the buffer's sum: 50 over four
// workgroups of 4, 82 over two of 8.
use e.gpu
use e.mem
use e.os
use k

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(101i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(102i32) }
    var o: [64]u32 = zero
    k.seed(o[0..])
    let (buf, buf_error) = gpu.upload[u32](q, o[0..])
    if buf_error != ok { os.exit(103i32) }
    if gpu.launch[k.fill](q, gpu.grid1(16usize), buf) != ok { os.exit(104i32) }
    var back: [64]u32 = zero
    if gpu.download[u32](q, buf, back[0..]) != ok { os.exit(105i32) }
    var sum = 0u32
    var at = 0usize
    while at < 64usize {
        sum += back[at]
        at += 1usize
    }
    os.exit(i32(sum))
    ret ok
}
