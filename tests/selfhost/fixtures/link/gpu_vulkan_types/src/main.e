// Narrow and wide integers, aggregate locals and ordinary/generic helper calls
// (D1614): CPU and Vulkan execute the same kernel and agree word for word.
use e.gpu
use e.io
use e.mem
use e.os

fn supports(caps: []const gpu.Cap, wanted: gpu.Cap) -> bool {
    for capability in caps {
        if capability == wanted { ret true }
    }
    ret false
}

type Pair = struct { byte: u8, delta: i16, wide: u64 }

fn sum[T: type](left: T, right: T) -> T { ret left + right }

fn combine(value: Pair, lane: u16) -> u64 {
    var words: [2]u64 = [2]u64{ value.wide, u64(u16(value.delta)) }
    words[1usize] = sum(words[1usize], u64(lane))
    ret words[0usize] + words[1usize] + u64(value.byte)
}

@gpu(64, caps(.Int8, .Int16, .Int64))
fn types(n: u32, input: []const Pair, output: []u64) {
    let lane = gpu.gid.x
    if lane >= n { ret }
    let at = usize(lane)
    var value = Pair { byte: 0u8, delta: 0i16, wide: 0u64 }
    value.byte = input[at].byte
    value.delta = input[at].delta
    value.wide = input[at].wide
    output[at] = combine(value, u16(lane))
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, input: []Pair, output: []u64) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (source, source_error) = gpu.upload[Pair](q, input)
    if source_error != ok { ret source_error }
    defer let _ = gpu.release(q, source)
    let (result, result_error) = gpu.upload[u64](q, output)
    if result_error != ok { ret result_error }
    defer let _ = gpu.release(q, result)
    try gpu.launch[types](q, gpu.grid1(input.len), u32(input.len), source, result)
    ret gpu.download(q, result, output)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var input: [64]Pair = zero
    var at = 0usize
    while at < input.len {
        input[at] = Pair { byte: u8(at * 3usize), delta: i16(at * 2usize), wide: u64(at) * 10000000019u64 }
        at += 1usize
    }
    var cpu: [64]u64 = zero
    try run(a, .Cpu, 0u32, input[0..], cpu[0..])
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu types cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var device_at = 0usize
    while device_at < found.len {
        if found[device_at].supported && supports(found[device_at].capabilities, .Int8) && supports(found[device_at].capabilities, .Int16) && supports(found[device_at].capabilities, .Int64) {
            var answer: [64]u64 = zero
            try run(a, .Vulkan, u32(device_at), input[0..], answer[0..])
            at = 0usize
            while at < cpu.len {
                if answer[at] != cpu[at] {
                    try io.printf["gpu types mismatch {} cpu {} device {}\n"](at, cpu[at], answer[at])
                    os.exit(i32(10usize + at))
                }
                at += 1usize
            }
            ran += 1usize
        }
        device_at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu types cpu only\n")
        ret ok
    }
    try io.printf["gpu types vulkan ok on {} devices\n"](ran)
    ret ok
}
