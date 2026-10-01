// A CPU subgroup width selected by `neper run --subgroup-width` reaches every
// collective and scheduler boundary, including the partial last subgroup of 100.
use e.gpu
use e.io
use e.mem
use e.os

@gpu(100, caps(.Subgroup))
fn probe(out: []u32, floats: []f32) {
    let lane = usize(gpu.lid.x)
    let at = lane * 4usize
    let count = gpu.subgroup_add(1u32)
    let first = gpu.subgroup_broadcast(gpu.lid.x, 0u32)
    let float_count = gpu.subgroup_add(1.0f32)
    out[at] = gpu.subgroup_size()
    out[at + 1usize] = gpu.sid
    out[at + 2usize] = count
    out[at + 3usize] = first
    floats[lane] = float_count
}

fn main(a: *mem.Arena, args: []str) -> err {
    var width = 32usize
    if args.len == 2usize {
        let supplied = args[1usize]
        if supplied.len == 1usize && supplied[0usize] == 56u8 { width = 8usize } else {
            if supplied.len == 2usize && supplied[0usize] == 49u8 && supplied[1usize] == 54u8 { width = 16usize } else {
                if supplied.len == 2usize && supplied[0usize] == 51u8 && supplied[1usize] == 50u8 { width = 32usize } else {
                    if supplied.len == 2usize && supplied[0usize] == 54u8 && supplied[1usize] == 52u8 { width = 64usize } else { os.exit(2i32) }
                }
            }
        }
    } else {
        if args.len != 1usize { os.exit(3i32) }
    }
    let (device, device_error) = gpu.open(a, .Cpu, 0u32)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buf, buf_error) = gpu.alloc[u32](q, 400usize)
    if buf_error != ok { ret buf_error }
    defer let _ = gpu.release(q, buf)
    let (float_buf, float_error) = gpu.alloc[f32](q, 100usize)
    if float_error != ok { ret float_error }
    defer let _ = gpu.release(q, float_buf)
    try gpu.launch[probe](q, gpu.grid1(100usize), buf, float_buf)
    var values: [400]u32 = zero
    var floats: [100]f32 = zero
    try gpu.download[u32](q, buf, values[0..])
    try gpu.download[f32](q, float_buf, floats[0..])
    var lane = 0usize
    while lane < 100usize {
        let first = lane / width * width
        var active = width
        if first + active > 100usize { active = 100usize - first }
        let at = lane * 4usize
        if values[at] != u32(width) || values[at + 1usize] != u32(lane - first) || values[at + 2usize] != u32(active) || values[at + 3usize] != u32(first) || floats[lane] != f32(active) { os.exit(4i32) }
        lane += 1usize
    }
    try io.print("gpu subgroup width ok\n")
    ret ok
}
