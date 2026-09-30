// SPIR-V structured loops (D1612): CPU and Vulkan run the same `while`, `continue`,
// `break` and `for` kernel, then every result is compared bit for bit.
use e.gpu
use e.io
use e.mem
use e.os

@gpu(64)
fn loops(n: u32, out: []u32) {
    let id = gpu.gid.x
    if id >= n { ret }
    var sum = 0u32
    var i = 0u32
    while i < id + 7u32 {
        i += 1u32
        if i % 3u32 == 0u32 { continue }
        if i > 11u32 { break }
        sum += i
    }
    for j in 0u32..id + 4u32 {
        if j == 2u32 { continue }
        if j >= 8u32 { break }
        sum += j * 2u32
    }
    var outer = 0u32
    while outer < 3u32 {
        outer += 1u32
        var inner = 0u32
        while inner < 5u32 {
            inner += 1u32
            if inner == 2u32 { continue }
            if outer == 3u32 {
                if inner == 4u32 { break }
            }
            sum += outer * inner
        }
    }
    out[usize(id)] = sum
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, out: []u32) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buffer, buffer_error) = gpu.upload[u32](q, out)
    if buffer_error != ok { ret buffer_error }
    defer let _ = gpu.release(q, buffer)
    try gpu.launch[loops](q, gpu.grid1(out.len), u32(out.len), buffer)
    ret gpu.download(q, buffer, out)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var cpu: [64]u32 = zero
    try run(a, .Cpu, 0u32, cpu[0..])
    var checksum = 0u32
    for value in cpu { checksum += value }
    if checksum != 9462u32 { os.exit(2i32) }
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu loop cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var device_at = 0usize
    while device_at < found.len {
        if found[device_at].supported {
            var device: [64]u32 = zero
            try run(a, .Vulkan, u32(device_at), device[0..])
            var at = 0usize
            while at < cpu.len {
                if device[at] != cpu[at] { os.exit(i32(10usize + at)) }
                at += 1usize
            }
            ran += 1usize
        }
        device_at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu loop cpu only\n")
        ret ok
    }
    try io.printf["gpu loop vulkan ok on {} devices\n"](ran)
    ret ok
}
