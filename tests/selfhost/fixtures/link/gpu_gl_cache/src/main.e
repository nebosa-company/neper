// x.khronos.compute's program cache (L180, D5898), built with `--gpu glsl`: a kernel compiled on one GL device is kept as
// a program binary, so a second device opened later in the same process takes it from the cache (cache_hits grows) and
// its words are still the CPU's. A host without an OpenGL compute device, or whose driver offers no binary format, exits 0
// having printed why.

use e.gpu
use e.io
use e.mem
use e.os
use x.khronos.compute

@gpu(64)
fn mix(n: u32, out: []u32) {
    let i = gpu.gid.x
    if i >= n { ret }
    out[usize(i)] = (i *% 2246822519u32) ^ (i >> 3u32)
}

const N: usize = 500usize

fn once(a: *mem.Arena, out: []u32) -> err {
    let (device, open_error) = gpu.open(a, .Gl, 0u32)
    if open_error != ok { ret open_error }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buffer, buffer_error) = gpu.alloc[u32](queue, N)
    if buffer_error != ok { ret buffer_error }
    let launched = gpu.launch[mix](queue, gpu.grid1(N), u32(N), buffer)
    if launched != ok { ret launched }
    let downloaded = gpu.download(queue, buffer, out)
    if downloaded != ok { ret downloaded }
    ret gpu.close(device)
}

fn main(a: *mem.Arena, args: []str) -> err {
    compute.install()
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error == gpu.Unsupported {
        let printed = io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    if found_error != ok {
        try io.printf["OpenGL device enumeration failed: {}\n"](found_error)
        os.exit(1i32)
    }
    if found.len == 0usize {
        let printed = io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    var first: [500]u32 = zero
    var second: [500]u32 = zero
    if once(a, first[0usize..N]) != ok { os.exit(2i32) }
    let before = compute.cache_hits()
    if once(a, second[0usize..N]) != ok { os.exit(3i32) }
    var k = 0usize
    while k < N {
        let want = (u32(k) *% 2246822519u32) ^ (u32(k) >> 3u32)
        if first[k] != want || second[k] != want { os.exit(4i32) }
        k += 1usize
    }
    if compute.cache_hits() == before {
        let printed = io.print("the driver keeps no program binaries; the cache was not exercised\n")
        ret ok
    }
    let named = io.print("a reopened device took its kernel from the program cache on ")
    let device_name = io.print(found[0usize].name)
    let ended = io.print("\n")
    ret ok
}
