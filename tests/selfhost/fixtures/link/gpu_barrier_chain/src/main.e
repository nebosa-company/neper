use e.gpu
use e.io
use e.mem

error WrongValue

type View = struct { data: []u32 }
type Packet = struct { value: u32, lane: u32 }

fn inner(lane: u32) -> u32 {
    var saved = lane + 41u32
    var round = 0u32
    while round < 3u32 {
        gpu.barrier()
        saved += 1u32
        round += 1u32
    }
    ret saved
}

// Unreached device code must not make the barrier oracle reject the kernel.
fn unused(n: u32) {
    gpu.barrier()
    if n != 0u32 { unused(n - 1u32) }
}

fn combine(view: []u32, left: u32, right: u32) -> u32 { ret right + left - left + u32(view.len) - 8u32 }

fn passthrough[T: type](value: T) -> T {
    gpu.barrier()
    ret value
}

fn packed(lane: u32) -> Packet {
    gpu.barrier()
    ret Packet { value: lane + 44u32, lane: lane }
}

fn middle(out: []u32, lane: u32) {
    for pass in 0u32..1u32 {
        // The store address, binary left operand and first call argument precede inner's barriers.
        if gpu.lid.x < 8u32 {
            out[usize(lane)] = lane + combine(out, lane, inner(lane)) - lane
            let view = View { data: out }
            view.data[usize(inner(lane) - 44u32)] = lane + 44u32
            view.data[usize(lane)] += inner(lane) - (lane + 44u32)
            view.data[usize(lane)] = passthrough(lane + 44u32)
            let packet = packed(lane)
            view.data[usize(lane)] = packet.value + packet.lane - lane
            let copied = passthrough(packet)
            view.data[usize(lane)] = copied.value + copied.lane - lane
        }
    }
}

fn outer(out: []u32, lane: u32) {
    for pass in 0u32..1u32 {
        if gpu.lid.x < 8u32 { middle(out, lane) }
    }
}

fn fourth(out: []u32, lane: u32) {
    if gpu.lid.x < 8u32 { outer(out, lane) }
}

fn fifth(out: []u32, lane: u32) {
    if gpu.lid.x < 8u32 { fourth(out, lane) }
}

@gpu(8)
fn kernel(out: []u32) { fifth(out, gpu.lid.x) }

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
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
        if output[at] != u32(at) + 44u32 { ret WrongValue }
        at += 1usize
    }
    try io.print("gpu barrier chain ok\n")
    ret ok
}
