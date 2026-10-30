// A launch carries its kernel's requirements wherever the kernel was checked (D5700):
// the kernels are in `kern`, launched from here, so the module that checks them can be
// another worker's or, in an incremental build, an artifact's Interface. On the CPU an
// `ftz` kernel runs under FTZ, so half the smallest normal `f32` comes back zero, and
// an `ftz` kernel over `f64` is refused with `Unsupported` rather than run flushed.
// The runner builds this at several worker counts and incrementally after
// `edits/main_body.e`, and requires one image.
use e.gpu
use e.io
use e.mem
use e.os
use kern

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    var x: [8]f32 = zero
    x[0usize] = mem.bitcast[f32](8388608u32)
    let (dx, dx_error) = gpu.upload[f32](q, x[0..])
    if dx_error != ok { ret dx_error }
    let (dout, dout_error) = gpu.alloc[f32](q, 8usize)
    if dout_error != ok { ret dout_error }
    try gpu.launch[kern.halve_ftz](q, gpu.grid1(8usize), dx, dout)
    var out: [8]f32 = zero
    try gpu.download[f32](q, dout, out[0..])
    if mem.bitcast[u32](out[0usize]) != 0u32 { os.exit(11i32) }
    var y: [8]f64 = zero
    let (dy, dy_error) = gpu.upload[f64](q, y[0..])
    if dy_error != ok { ret dy_error }
    let (dz, dz_error) = gpu.alloc[f64](q, 8usize)
    if dz_error != ok { ret dz_error }
    if gpu.launch[kern.halve64_ftz](q, gpu.grid1(8usize), dy, dz) != gpu.Unsupported { os.exit(12i32) }
    try io.print("gpu launch facts ok again\n")
    ret ok
}
