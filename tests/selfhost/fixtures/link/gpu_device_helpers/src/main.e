// C094's remainder: what a kernel reaches in other modules besides a plain function -- a
// generic helper instantiated in a module the kernel does not own (two element types), a
// constant read in a helper's module from a third, a helper with an early return and one
// with a loop. The kernel's module carries the device copy; the host's own answer to the
// same calls is the oracle, on the CPU build and on every Vulkan device whose float
// kernels run.
use e.gpu
use e.io
use e.mem
use e.os
use midhelp

const N: usize = 8usize

@gpu(8)
fn kernel(out: []u32, real: []f32) {
    let i = gpu.gid.x
    out[usize(i)] = midhelp.mix(i)
    real[usize(i)] = midhelp.scaled(f32(i) + 0.25f32)
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buf, alloc_error) = gpu.alloc[u32](q, N)
    if alloc_error != ok { ret alloc_error }
    let (reals, reals_error) = gpu.alloc[f32](q, N)
    if reals_error != ok { ret reals_error }
    try gpu.launch[kernel](q, gpu.grid1(N), buf, reals)
    var output: [8]u32 = zero
    var output_real: [8]f32 = zero
    try gpu.download[u32](q, buf, output[0..])
    try gpu.download[f32](q, reals, output_real[0..])
    var at = 0usize
    while at < N {
        if output[at] != midhelp.mix(u32(at)) { os.exit(10i32 + i32(at)) }
        if mem.bitcast[u32](output_real[at]) != mem.bitcast[u32](midhelp.scaled(f32(at) + 0.25f32)) { os.exit(30i32 + i32(at)) }
        at += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    try run(a, .Cpu, 0u32)
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    var ran = 0usize
    if found_error == ok {
        var at = 0usize
        while at < found.len {
            // A float kernel is written with `DenormPreserve`; a device without it
            // refuses the launch (D2118), which is not what this fixture checks.
            var preserves = false
            var cap_at = 0usize
            while cap_at < found[at].capabilities.len {
                if found[at].capabilities[cap_at] == .DenormPreserve { preserves = true }
                cap_at += 1usize
            }
            if found[at].supported && preserves {
                try run(a, .Vulkan, u32(at))
                ran += 1usize
            }
            at += 1usize
        }
    }
    try io.printf["gpu device helpers ok on cpu and {} devices\n"](ran)
    ret ok
}
