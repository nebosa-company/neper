// Subgroup collectives through the GLSL emitter (D5902), built with `--gpu glsl`: ids, elect, vote, ballot, broadcast,
// shuffle and the integer and float reductions over a workgroup of 40, so the last subgroup is partial wherever the
// width is below 64. The driver picks the width (Intel 8 to 32, llvmpipe 8), so the answers are worked out on the host
// from the width the kernel reports, lane by lane as section 8 defines each collective. A ballot answers a u64, so it
// runs only where the device also has Int64 (llvmpipe; not Intel's Windows driver). A device without the Subgroup
// capability, or a host without an OpenGL compute device, says so and passes.
use e.gpu
use e.io
use e.mem
use e.os
use x.khronos.compute

const N: usize = 40usize

@gpu(40, caps(.Subgroup, .Int64))
fn ballots(b: []u64) {
    b[usize(gpu.lid.x)] = gpu.subgroup_ballot(gpu.sid % 3u32 == 0u32)
}

@gpu(40, ftz, caps(.Subgroup))
fn collectives(a: []u32, c: []f32) {
    let at = usize(gpu.lid.x)
    let width = gpu.subgroup_size()
    var elected = 0u32
    if gpu.subgroup_elect() { elected = 1u32 }
    a[at] = width * 65536u32 + elected * 256u32 + gpu.sid
    var flags = 0u32
    if gpu.subgroup_all(gpu.sid < gpu.subgroup_size()) { flags = 1u32 }
    if gpu.subgroup_any(gpu.sid + 1u32 == gpu.subgroup_size()) { flags = flags | 2u32 }
    a[N + at] = flags
    a[2usize * N + at] = gpu.subgroup_broadcast(gpu.lid.x + 100u32, 0u32)
    c[at] = gpu.subgroup_shuffle(f32(gpu.lid.x) + 0.25f32, gpu.sid ^ 1u32)
    let narrow = gpu.lid.x * 3u32 + 5u32
    a[3usize * N + at] = gpu.subgroup_add(narrow)
    a[4usize * N + at] = gpu.subgroup_min(narrow)
    a[5usize * N + at] = gpu.subgroup_max(narrow)
    a[6usize * N + at] = gpu.subgroup_and(narrow | 1u32)
    a[7usize * N + at] = gpu.subgroup_or(narrow)
    a[8usize * N + at] = gpu.subgroup_xor(narrow)
    c[N + at] = gpu.subgroup_add(f32(gpu.lid.x))
}

fn check(code: i32, at: usize, got: u64, want: u64) {
    if got != want {
        let printed = io.printf["lane {}: got {} want {}\n"](at, got, want)
        os.exit(code)
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    compute.install()
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error != ok || found.len == 0usize {
        try io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    var subgroups = false
    var wide = false
    for capability in found[0usize].capabilities {
        if capability == .Subgroup { subgroups = true }
        if capability == .Int64 { wide = true }
    }
    if !subgroups {
        try io.print("no subgroups on this OpenGL device; nothing checked\n")
        ret ok
    }
    var ga: [360]u32 = zero
    var gb: [40]u64 = zero
    var gc: [80]f32 = zero
    let (device, open_error) = gpu.open(a, .Gl, 0u32)
    if open_error != ok { os.exit(2i32) }
    let (q, q_error) = gpu.queue(device)
    if q_error != ok { os.exit(3i32) }
    let (da, a_error) = gpu.upload[u32](q, ga[0..])
    let (db, b_error) = gpu.upload[u64](q, gb[0..])
    let (dc, c_error) = gpu.upload[f32](q, gc[0..])
    if a_error != ok || b_error != ok || c_error != ok { os.exit(4i32) }
    if gpu.launch[collectives](q, gpu.grid1(N), da, dc) != ok { os.exit(5i32) }
    if wide && gpu.launch[ballots](q, gpu.grid1(N), db) != ok { os.exit(8i32) }
    if gpu.download(q, da, ga[0..]) != ok || gpu.download(q, db, gb[0..]) != ok || gpu.download(q, dc, gc[0..]) != ok { os.exit(6i32) }
    let width = usize(ga[0usize] / 65536u32)
    if width == 0usize || width > 64usize { os.exit(7i32) }
    var at = 0usize
    while at < N {
        let first = at / width * width
        var end = first + width
        if end > N { end = N }
        let lane = at - first
        var elected = 0usize
        if lane == 0usize { elected = 1usize }
        check(10i32, at, u64(ga[at]), u64(width * 65536usize + elected * 256usize + lane))
        var flags = 1u64
        if end - first == width { flags = 3u64 }
        check(11i32, at, u64(ga[N + at]), flags)
        var ballot = 0u64
        var sum = 0u32
        var low = 4294967295u32
        var high = 0u32
        var all_and = 4294967295u32
        var any_or = 0u32
        var parity = 0u32
        var float_sum: f32 = 0.0
        var other = first
        while other < end {
            if (other - first) % 3usize == 0usize { ballot = ballot | (1u64 << u32(other - first)) }
            let narrow = u32(other) * 3u32 + 5u32
            sum = sum +% narrow
            if narrow < low { low = narrow }
            if narrow > high { high = narrow }
            all_and = all_and & (narrow | 1u32)
            any_or = any_or | narrow
            parity = parity ^ narrow
            float_sum = float_sum + f32(other)
            other += 1usize
        }
        if wide { check(12i32, at, gb[at], ballot) }
        check(13i32, at, u64(ga[2usize * N + at]), u64(first + 100usize))
        let partner = first + (lane ^ 1usize)
        check(14i32, at, u64(mem.bitcast[u32](gc[at])), u64(mem.bitcast[u32](f32(partner) + 0.25f32)))
        check(15i32, at, u64(ga[3usize * N + at]), u64(sum))
        check(16i32, at, u64(ga[4usize * N + at]), u64(low))
        check(17i32, at, u64(ga[5usize * N + at]), u64(high))
        check(18i32, at, u64(ga[6usize * N + at]), u64(all_and))
        check(19i32, at, u64(ga[7usize * N + at]), u64(any_or))
        check(20i32, at, u64(ga[8usize * N + at]), u64(parity))
        check(21i32, at, u64(mem.bitcast[u32](gc[N + at])), u64(mem.bitcast[u32](float_sum)))
        at += 1usize
    }
    if !wide { try io.print("(no ballot without Int64) ") }
    try io.printf["subgroup collectives of width {} correct on {}\n"](width, found[0usize].name)
    ret gpu.close(device)
}
