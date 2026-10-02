// Two queues share one device's arena and handle table, while launches remain
// one thread at a time per queue. Closing invalidates both queue handles.
use e.gpu
use e.io
use e.mem
use e.os
use e.thread

@gpu(4)
fn increment(data: []u32) {
    let at = usize(gpu.gid.x)
    if at < data.len { data[at] += 1u32 }
}

type Worker = struct { device: *gpu.Device, base: u32, failed: bool }

fn run(w: *Worker) {
    let (q, queue_error) = gpu.queue(w.device)
    if queue_error != ok {
        w.failed = true
        ret
    }
    let int64_capability = gpu.has(w.device, .Int64)
    var pass = 0u32
    while pass < 8u32 {
        if gpu.has(w.device, .Int64) != int64_capability {
            w.failed = true
            ret
        }
        var input: [4]u32 = [4]u32 { w.base + pass, w.base + pass + 1u32, w.base + pass + 2u32, w.base + pass + 3u32 }
        let (buf, upload_error) = gpu.upload[u32](q, input[0..])
        if upload_error != ok {
            w.failed = true
            ret
        }
        if gpu.launch[increment](q, gpu.grid1(4usize), buf) != ok {
            w.failed = true
            ret
        }
        var output: [4]u32 = zero
        if gpu.download[u32](q, buf, output[0..]) != ok {
            w.failed = true
            ret
        }
        var at = 0usize
        while at < 4usize {
            if output[at] != input[at] + 1u32 {
                w.failed = true
                ret
            }
            at += 1usize
        }
        if gpu.release(q, buf) != ok {
            w.failed = true
            ret
        }
        pass += 1u32
    }
}

fn exercise(a: *mem.Arena, backend: gpu.Backend, index: u32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    var left = Worker { device: device, base: 10u32, failed: false }
    var right = Worker { device: device, base: 100u32, failed: false }
    let (first, first_error) = thread.spawn[Worker](run, &left, 0usize)
    if first_error != ok { ret first_error }
    let (second, second_error) = thread.spawn[Worker](run, &right, 0usize)
    if second_error != ok {
        let joined = thread.join(first)
        ret second_error
    }
    let first_join = thread.join(first)
    let second_join = thread.join(second)
    if first_join != ok || second_join != ok || left.failed || right.failed { os.exit(1i32) }
    try gpu.close(device)
    if gpu.has(device, .Int64) || gpu.close(device) != gpu.InvalidHandle { os.exit(2i32) }
    let (_, stale_error) = gpu.queue(device)
    if stale_error != gpu.InvalidHandle { os.exit(3i32) }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    try exercise(a, .Cpu, 0u32)
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu device lock cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var at = 0usize
    while at < found.len {
        if found[at].supported {
            try exercise(a, .Vulkan, u32(at))
            ran += 1usize
        }
        at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu device lock cpu only\n")
        ret ok
    }
    try io.printf["gpu device lock vulkan ok on {} devices\n"](ran)
    ret ok
}
