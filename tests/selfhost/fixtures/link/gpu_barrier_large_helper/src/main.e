use e.gpu
use e.io
use e.mem

error WrongValue

fn handoff(out: []u32, lane: u32) {
    var saved = lane
    if lane == 0u32 { saved += 1u32 }
    if lane == 1u32 { saved += 1u32 }
    if lane == 2u32 { saved += 1u32 }
    if lane == 3u32 { saved += 1u32 }
    if lane == 4u32 { saved += 1u32 }
    if lane == 5u32 { saved += 1u32 }
    if lane == 6u32 { saved += 1u32 }
    if lane == 7u32 { saved += 1u32 }
    if lane == 8u32 { saved += 1u32 }
    if lane == 9u32 { saved += 1u32 }
    if lane == 10u32 { saved += 1u32 }
    if lane == 11u32 { saved += 1u32 }
    if lane == 12u32 { saved += 1u32 }
    if lane == 13u32 { saved += 1u32 }
    if lane == 14u32 { saved += 1u32 }
    if lane == 15u32 { saved += 1u32 }
    if lane == 16u32 { saved += 1u32 }
    if lane == 17u32 { saved += 1u32 }
    if lane == 18u32 { saved += 1u32 }
    if lane == 19u32 { saved += 1u32 }
    if lane == 20u32 { saved += 1u32 }
    if lane == 21u32 { saved += 1u32 }
    if lane == 22u32 { saved += 1u32 }
    if lane == 23u32 { saved += 1u32 }
    if lane == 24u32 { saved += 1u32 }
    if lane == 25u32 { saved += 1u32 }
    if lane == 26u32 { saved += 1u32 }
    if lane == 27u32 { saved += 1u32 }
    if lane == 28u32 { saved += 1u32 }
    if lane == 29u32 { saved += 1u32 }
    if lane == 30u32 { saved += 1u32 }
    if lane == 31u32 { saved += 1u32 }
    if lane == 32u32 { saved += 1u32 }
    if lane == 33u32 { saved += 1u32 }
    if lane == 34u32 { saved += 1u32 }
    if lane == 35u32 { saved += 1u32 }
    if lane == 36u32 { saved += 1u32 }
    if lane == 37u32 { saved += 1u32 }
    if lane == 38u32 { saved += 1u32 }
    if lane == 39u32 { saved += 1u32 }
    if lane == 40u32 { saved += 1u32 }
    if lane == 41u32 { saved += 1u32 }
    if lane == 42u32 { saved += 1u32 }
    if lane == 43u32 { saved += 1u32 }
    if lane == 44u32 { saved += 1u32 }
    if lane == 45u32 { saved += 1u32 }
    if lane == 46u32 { saved += 1u32 }
    if lane == 47u32 { saved += 1u32 }
    if lane == 48u32 { saved += 1u32 }
    if lane == 49u32 { saved += 1u32 }
    if lane == 50u32 { saved += 1u32 }
    if lane == 51u32 { saved += 1u32 }
    if lane == 52u32 { saved += 1u32 }
    if lane == 53u32 { saved += 1u32 }
    if lane == 54u32 { saved += 1u32 }
    if lane == 55u32 { saved += 1u32 }
    if lane == 56u32 { saved += 1u32 }
    if lane == 57u32 { saved += 1u32 }
    if lane == 58u32 { saved += 1u32 }
    if lane == 59u32 { saved += 1u32 }
    if lane == 60u32 { saved += 1u32 }
    if lane == 61u32 { saved += 1u32 }
    if lane == 62u32 { saved += 1u32 }
    if lane == 63u32 { saved += 1u32 }
    if lane == 64u32 { saved += 1u32 }
    if lane == 65u32 { saved += 1u32 }
    if lane == 66u32 { saved += 1u32 }
    if lane == 67u32 { saved += 1u32 }
    if lane == 68u32 { saved += 1u32 }
    if lane == 69u32 { saved += 1u32 }
    gpu.barrier()
    out[usize(lane)] = saved
}

@gpu(8)
fn kernel(out: []u32) { handoff(out, gpu.lid.x) }

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
        if output[at] != u32(at) + 1u32 { ret WrongValue }
        at += 1usize
    }
    try io.print("gpu barrier large helper ok\n")
    ret ok
}
