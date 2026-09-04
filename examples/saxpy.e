// The same kernel compiles to SPIR-V/PTX and to CPU machine code.
// The CPU backend is the debugger: step one work item, inspect the workgroup,
// then run it on the device.

use e.mem
use e.gpu
use e.io

// The workgroup size is part of the attribute (spec §10): 256 invocations along x.
// gpu.launch[saxpy] is the only way to call it, on the CPU as on the device.
@gpu(256)
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) {
    let i = gpu.gid.x // u32, like every invocation id
    if i >= n { // launch rounds the grid up to whole workgroups
        ret
    }
    let k = usize(i) // slice indices are usize; no implicit widening
    y[k] = a*x[k] + y[k] // a multiply, then an add: never fused (spec §11)
}

fn run(q: *gpu.Queue, a: f32, x: []const f32, y: []f32) -> err {
    // upload copies x into driver-owned staging before it returns, so x is
    // free to reuse. The device-side transfer is queued in order behind it.
    let dx = try gpu.upload[f32](q, x)
    defer gpu.release(q, dx) // queued behind everything below: safe to defer

    let dy = try gpu.upload[f32](q, y)
    defer gpu.release(q, dy)

    // The kernel is a comptime argument, so the trailing arguments are checked
    // against saxpy's parameter list at compile time. grid1 counts invocations;
    // launch divides by 256 and rounds up.
    try gpu.launch[saxpy](q, gpu.grid1(x.len), u32(x.len), a, dx, dy)

    // download waits for everything queued before it on q, then copies back.
    try gpu.download[f32](q, dy, y)
    ret ok
}

// A plain sum: one IEEE add per element, so the CPU and the device agree bit
// for bit on the result (spec §11).
fn checksum(y: []const f32) -> f32 {
    var s: f32 = 0.0
    for v in y { // v is a copy of the element
        s = s + v
    }
    ret s
}

fn fill(x: []f32, y: []f32) {
    for i in 0usize..x.len {
        x[i] = f32(i)
        y[i] = 1.0
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [4096]f32 = zero
    var y: [4096]f32 = zero

    // .Cpu always exists at index 0: the same kernel, run on this thread one
    // workgroup at a time, steppable in any debugger.
    fill(x[0..], y[0..])
    let cpu = try gpu.open(a, .Cpu, 0)
    defer gpu.close(cpu)
    let cq = try gpu.queue(cpu)
    try run(cq, 2.0, x[0..], y[0..])
    try io.printf["cpu    checksum {}\n"](checksum(y[0..]))

    // A Vulkan device may be absent; NoDevice is an ordinary outcome here, not
    // a failure. Anything else is.
    let (dev, e) = gpu.open(a, .Vulkan, 0)
    if e == gpu.NoDevice {
        ret ok
    }
    if e != ok {
        ret e
    }
    defer gpu.close(dev)
    let q = try gpu.queue(dev)
    fill(x[0..], y[0..])
    try run(q, 2.0, x[0..], y[0..])
    try io.printf["vulkan checksum {}\n"](checksum(y[0..]))
    ret ok
}
