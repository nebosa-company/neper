// Section 10's address spaces (D1590): a workgroup's `shared var` sliced into a
// `[]const shared u32`, addressed as a `*shared u32`, and handed to a generic helper
// that is instantiated once per space -- beside a device slice given to the same
// helper. The kernel's results are checked bit-identically on CPU and Vulkan.

use e.gpu
use e.io
use e.mem
use e.os

fn pair(xs: []const shared u32) -> u32 {
    ret xs[0usize] + xs[1usize]
}

fn head[S: type](xs: S) -> u32 {
    ret xs[0usize]
}

fn cell(p: *shared u32) -> u32 {
    ret *p
}

// out[gid] = tile[0] + tile[1] + tile[0] + src[gid] + tile[2], each invocation having
// written its id + 1 into the tile.
@gpu(4)
fn combine(src: []const u32, out: []u32) {
    shared var tile: [4]u32
    let i = gpu.lid.x
    tile[usize(i)] = i + 1u32
    gpu.barrier()
    let part = tile[0usize..3usize]
    let here = usize(gpu.gid.x)
    out[here] = pair(part) + head(part) + head(src[here..here + 1usize]) + cell(&tile[2usize])
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, values: []u32, out: []u32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (source, source_error) = gpu.upload[u32](q, values)
    if source_error != ok { ret source_error }
    defer let _ = gpu.release(q, source)
    let (results, results_error) = gpu.alloc[u32](q, 8usize)
    if results_error != ok { ret results_error }
    defer let _ = gpu.release(q, results)
    try gpu.launch[combine](q, gpu.grid1(8usize), source, results)
    ret gpu.download[u32](q, results, out)
}

fn same(a: []const u32, b: []const u32) -> bool {
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret a.len == b.len
}

fn main(a: *mem.Arena, args: []str) -> err {
    var values: [8]u32 = [8]u32{ 10u32, 20u32, 30u32, 40u32, 50u32, 60u32, 70u32, 80u32 }
    var out: [8]u32 = zero
    try run(a, .Cpu, 0u32, values[0..], out[0..])
    // 1 + 2 from the pair, 1 from the head, 3 from the cell: 7, plus the source.
    if out[0] != 17u32 || out[3] != 47u32 || out[7] != 87u32 { os.exit(7i32) }
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error != gpu.NoDevice && found_error != gpu.Unsupported {
        if found_error != ok { ret found_error }
        var at = 0usize
        while at < found.len {
            if found[at].supported {
                var answer: [8]u32 = zero
                try run(a, .Vulkan, u32(at), values[0..], answer[0..])
                if !same(out[0..], answer[0..]) {
                    var mismatch = 0usize
                    while mismatch < out.len && out[mismatch] == answer[mismatch] { mismatch += 1usize }
                    try io.printf["gpu spaces mismatch {} cpu {} device {}\n"](mismatch, out[mismatch], answer[mismatch])
                    os.exit(8i32)
                }
            }
            at += 1usize
        }
    }
    try io.print("gpu spaces ok\n")
    ret ok
}
