// The device-reached edit case (C096, D4202; spec section 12, D24 and D36): a kernel
// calls `midhelp.mix`, which calls `lowhelp.add3` and `lowhelp.pair`, both in other
// modules. The kernel's own module carries the device copy of the whole chain in its
// `K$spirv`, so an edit to `lowhelp`'s body has to rebuild `main` even though `main`'s
// host code only calls `midhelp.mix`. The runner builds this tree incrementally, edits
// `lowhelp.e` with `edits/lowhelp_body.e`, builds again and compares with a clean build;
// the program checks the device against the host, which calls the same functions, so a
// stale device copy answers differently from the edited host code.
use e.gpu
use e.io
use e.mem
use midhelp

@gpu(8)
fn kernel(out: []u32) {
    let i = gpu.gid.x
    out[usize(i)] = midhelp.mix(i) + 1u32
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buf, alloc_error) = gpu.alloc[u32](q, 8usize)
    if alloc_error != ok { ret alloc_error }
    try gpu.launch[kernel](q, gpu.grid1(8usize), buf)
    var output: [8]u32 = zero
    try gpu.download[u32](q, buf, output[0..])
    var at = 0usize
    while at < 8usize {
        if output[at] != midhelp.mix(u32(at)) + 1u32 { ret gpu.Fault }
        at += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    try run(a, .Cpu, 0u32)
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == ok {
        var at = 0usize
        while at < found.len {
            if found[at].supported { try run(a, .Vulkan, u32(at)) }
            at += 1usize
        }
    }
    try io.print("gpu device edit ok\n")
    ret ok
}
