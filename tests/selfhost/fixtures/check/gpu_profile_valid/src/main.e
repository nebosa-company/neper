// Section 10 (D1588): what device code may do -- helpers, slices of device and shared
// memory, private arrays indexed in place, a shared var -- passes the kernel walk.
use e.gpu

fn scale(x: u32, k: u32) -> u32 {
    ret x * k
}

fn window(xs: []const u32, at: usize) -> []const u32 {
    ret xs[at..at + 1usize]
}

@gpu(64)
fn fill(v: []u32, src: []const u32, k: u32) {
    let i = usize(gpu.gid.x)
    if i >= v.len { ret }
    let part = window(src, i)
    var total: [2]u32 = zero
    total[0usize] = scale(part[0usize], k)
    shared var tile: [64]u32
    tile[usize(gpu.lid.x)] = total[0usize]
    let row = tile[0usize..4usize]
    v[i] = row[0usize] + total[0usize]
}
