use e.gpu
use e.io
use e.mem

error WrongValue

fn handoff(out: []u32, lane: u32) {
    let saved = lane + 41u32
    gpu.barrier()
    out[usize(lane)] = saved
}

@gpu(8)
fn kernel(out: []u32) {
    handoff(out, gpu.lid.x)
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buf, alloc_error) = gpu.alloc[u32](q, 8usize)
    if alloc_error != ok { ret alloc_error }
    defer let _ = gpu.release(q, buf)
    try gpu.launch[kernel](q, gpu.grid1(8usize), buf)
    var output: [8]u32 = zero
    try gpu.download[u32](q, buf, output[0..])
    var at = 0usize
    while at < output.len {
        if output[at] != u32(at) + 41u32 { ret WrongValue }
        at += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    try run(a, .Cpu, 0u32)
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error != gpu.NoDevice && found_error != gpu.Unsupported {
        if found_error != ok { ret found_error }
        var at = 0usize
        while at < found.len {
            if found[at].supported { try run(a, .Vulkan, u32(at)) }
            at += 1usize
        }
    }
    try io.print("gpu barrier helper ok\n")
    ret ok
}
