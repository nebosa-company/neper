// `sid`, `subgroup_size` and `subgroup_elect` on a full and a partial subgroup.
use e.gpu
use e.io
use e.mem
use e.os

@gpu(40, caps(.Subgroup))
fn subgroup_identity(output: []u32) {
    var elected = 0u32
    if gpu.subgroup_elect() { elected = 1u32 }
    output[usize(gpu.lid.x)] = gpu.subgroup_size() * 65536u32 + elected * 256u32 + gpu.sid
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, output: []u32) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (result, result_error) = gpu.alloc[u32](q, output.len)
    if result_error != ok { ret result_error }
    defer let _ = gpu.release(q, result)
    try gpu.launch[subgroup_identity](q, gpu.grid1(output.len), result)
    ret gpu.download(q, result, output)
}

fn valid(output: []const u32) -> bool {
    var elected = 0usize
    var at = 0usize
    var width = 0u32
    while at < output.len {
        let value = output[at]
        let lane = value & 255u32
        let chosen = (value / 256u32) & 255u32
        let seen_width = value / 65536u32
        if seen_width < 4u32 || seen_width > 64u32 || lane >= seen_width { ret false }
        if at == 0usize { width = seen_width }
        if seen_width != width || lane != u32(at) % width { ret false }
        if chosen != 0u32 {
            if chosen != 1u32 || lane != 0u32 { ret false }
            elected += 1usize
        }
        at += 1usize
    }
    ret elected == (output.len + usize(width) - 1usize) / usize(width)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var output: [40]u32 = zero
    try run(a, .Cpu, 0u32, output[0..])
    if !valid(output[0..]) || output[0usize] / 65536u32 != 32u32 { os.exit(1i32) }
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu subgroup identity cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var device_at = 0usize
    while device_at < found.len {
        if found[device_at].supported {
            var device_output: [40]u32 = zero
            try run(a, .Vulkan, u32(device_at), device_output[0..])
            if !valid(device_output[0..]) { os.exit(2i32) }
            ran += 1usize
        }
        device_at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu subgroup identity cpu only\n")
        ret ok
    }
    try io.printf["gpu subgroup identity vulkan ok on {} devices\n"](ran)
    ret ok
}
