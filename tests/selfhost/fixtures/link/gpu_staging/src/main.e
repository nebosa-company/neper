use e.gpu
use e.io
use e.mem
use e.os

@gpu(4)
fn increment(data: []u32) {
    let at = usize(gpu.gid.x)
    if at >= data.len { ret }
    data[at] += 1u32
}

fn check(a: *mem.Arena, backend: gpu.Backend, index: u32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (_, empty_error) = gpu.queue_with(device, gpu.StagingLimits { blocks: 0u32, block_bytes: 3usize })
    if empty_error != gpu.TooLarge { os.exit(1i32) }
    let (q, queue_error) = gpu.queue_with(device, gpu.StagingLimits { blocks: 2u32, block_bytes: 3usize })
    if queue_error != ok { ret queue_error }
    var initial: [5]u32 = [5]u32 { 1u32, 2u32, 3u32, 4u32, 5u32 }
    let (buf, upload_error) = gpu.upload[u32](q, initial[0..])
    if upload_error != ok { ret upload_error }
    defer let _ = gpu.release(q, buf)
    let patch: [3]u32 = [3]u32 { 20u32, 30u32, 40u32 }
    try gpu.write[u32](q, buf, 1usize, patch[0..])
    try gpu.launch[increment](q, gpu.grid1(5usize), buf)
    var result: [5]u32 = zero
    try gpu.download[u32](q, buf, result[0..])
    if result[0usize] != 2u32 || result[1usize] != 21u32 || result[2usize] != 31u32 || result[3usize] != 41u32 || result[4usize] != 6u32 { os.exit(2i32) }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    try check(a, .Cpu, 0u32)
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu staging cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var at = 0usize
    while at < found.len {
        if found[at].supported {
            try check(a, .Vulkan, u32(at))
            ran += 1usize
        }
        at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu staging cpu only\n")
        ret ok
    }
    try io.printf["gpu staging vulkan ok on {} devices\n"](ran)
    ret ok
}
