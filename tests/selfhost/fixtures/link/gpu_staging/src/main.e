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
    var initial: [5]u32 = [5]u32 { 1u32, 2u32, 3u32, 4u32, 5u32 }
    // Twenty bytes need seven three-byte blocks. CPU queues copy directly; a
    // Vulkan queue must reject the one-block pool instead of silently chunking.
    let (limited, limited_error) = gpu.queue_with(device, gpu.StagingLimits { blocks: 1u32, block_bytes: 3usize })
    if limited_error != ok { ret limited_error }
    let (limited_buf, limited_upload_error) = gpu.upload[u32](limited, initial[0..])
    if backend == .Cpu {
        if limited_upload_error != ok { os.exit(2i32) }
        if gpu.release(limited, limited_buf) != ok { os.exit(3i32) }
    } else {
        if limited_upload_error != gpu.TooLarge { os.exit(2i32) }
    }
    let (q, queue_error) = gpu.queue_with(device, gpu.StagingLimits { blocks: 7u32, block_bytes: 3usize })
    if queue_error != ok { ret queue_error }
    let (buf, upload_error) = gpu.upload[u32](q, initial[0..])
    if upload_error != ok { ret upload_error }
    defer let _ = gpu.release(q, buf)
    let patch: [3]u32 = [3]u32 { 20u32, 30u32, 40u32 }
    try gpu.write[u32](q, buf, 1usize, patch[0..])
    try gpu.launch[increment](q, gpu.grid1(5usize), buf)
    var result: [5]u32 = zero
    try gpu.download[u32](q, buf, result[0..])
    if result[0usize] != 2u32 || result[1usize] != 21u32 || result[2usize] != 31u32 || result[3usize] != 41u32 || result[4usize] != 6u32 { os.exit(4i32) }
    // #645: a byte copy takes arbitrary slices. Writing from payload[1..] and downloading
    // into read[1..] must not dereference either unaligned address as a u64.
    var payload: [9]u8 = [9]u8 { 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8 }
    let (bytes, bytes_error) = gpu.upload[u8](q, payload[0..])
    if bytes_error != ok { ret bytes_error }
    if gpu.write[u8](q, bytes, 0usize, payload[1..]) != ok { os.exit(5i32) }
    var read: [10]u8 = zero
    if gpu.download[u8](q, bytes, read[1..]) != ok { os.exit(6i32) }
    if read[1usize] != 2u8 || read[9usize] != 9u8 { os.exit(7i32) }
    if gpu.release(q, bytes) != ok { os.exit(8i32) }
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
