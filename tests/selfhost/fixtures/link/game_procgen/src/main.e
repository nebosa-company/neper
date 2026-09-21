// `e.game.procgen`: Perlin with the reference permutation (and a shuffled seed,
// and the 3-d form), simplex and Worley agree with a Python transcription at
// twenty points; wave function collapse honours every adjacency on five seeds
// and hashes to the replica's grid, and a corridor no tile can fill answers
// `Invalid`. Each check exits with its own code.

use e.algo.rand
use e.game.procgen as pg
use e.io
use e.mem
use e.os

fn near(got: f64, want: f64) -> bool {
    var d = got - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 1.0e-12f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var xs: [20]f64 = zero
    var ys: [20]f64 = zero
    var want_perlin: [20]f64 = zero
    var want_simplex: [20]f64 = zero
    var want_perlin3: [5]f64 = zero
    var want_perlin7: [5]f64 = zero
    var want_f1: [8]f64 = zero
    var want_f2: [8]f64 = zero
    var want_wfc: [5]u64 = zero
    let p0 = pg.perm(0u64)
    let p7 = pg.perm(7u64)
    xs[0usize] = 0.3f64
    ys[0usize] = 0.7f64
    want_perlin[0usize] = -0.11415600000000006f64
    want_simplex[0usize] = 0.2552206334201348f64
    xs[1usize] = 1.5f64
    ys[1usize] = 2.25f64
    want_perlin[1usize] = 0.34912109375f64
    want_simplex[1usize] = -0.08087486102784608f64
    xs[2usize] = -0.4f64
    ys[2usize] = 3.1f64
    want_perlin[2usize] = 0.43086115583999995f64
    want_simplex[2usize] = -0.643189669808981f64
    xs[3usize] = 10.125f64
    ys[3usize] = -7.375f64
    want_perlin[3usize] = 0.24100466445088387f64
    want_simplex[3usize] = -0.4019666665532312f64
    xs[4usize] = 0.0f64
    ys[4usize] = 0.0f64
    want_perlin[4usize] = 0.0f64
    want_simplex[4usize] = 0.0f64
    xs[5usize] = 0.5f64
    ys[5usize] = 0.5f64
    want_perlin[5usize] = -0.25f64
    want_simplex[5usize] = -0.3071565136272162f64
    xs[6usize] = 100.3f64
    ys[6usize] = 200.9f64
    want_perlin[6usize] = -0.043050385920001544f64
    want_simplex[6usize] = 0.47051730729906177f64
    xs[7usize] = -3.7f64
    ys[7usize] = -2.2f64
    want_perlin[7usize] = -0.3898431347199997f64
    want_simplex[7usize] = -0.006416040065246192f64
    xs[8usize] = 0.99f64
    ys[8usize] = 0.01f64
    want_perlin[8usize] = -0.009999901493999649f64
    want_simplex[8usize] = -0.11176121125109781f64
    xs[9usize] = 5.55f64
    ys[9usize] = 5.55f64
    want_perlin[9usize] = 0.474587116179258f64
    want_simplex[9usize] = -0.8978920852131111f64
    xs[10usize] = 2.718f64
    ys[10usize] = 3.1416f64
    want_perlin[10usize] = -0.15772291608176794f64
    want_simplex[10usize] = -0.3967985832733751f64
    xs[11usize] = -0.001f64
    ys[11usize] = 0.999f64
    want_perlin[11usize] = -0.001999999960059975f64
    want_simplex[11usize] = -0.49489161323577036f64
    xs[12usize] = 7.25f64
    ys[12usize] = 0.75f64
    want_perlin[12usize] = 0.2633943557739258f64
    want_simplex[12usize] = -0.5539447117353732f64
    xs[13usize] = 12.5f64
    ys[13usize] = 12.5f64
    want_perlin[13usize] = 0.375f64
    want_simplex[13usize] = -0.4336464189356008f64
    xs[14usize] = 1.0f64
    ys[14usize] = 1.0f64
    want_perlin[14usize] = 0.0f64
    want_simplex[14usize] = -0.44026771907549944f64
    xs[15usize] = 0.123f64
    ys[15usize] = 0.456f64
    want_perlin[15usize] = -0.11969545091950293f64
    want_simplex[15usize] = 0.036205779991861656f64
    xs[16usize] = 300.7f64
    ys[16usize] = 1.3f64
    want_perlin[16usize] = 0.1555365604799974f64
    want_simplex[16usize] = -0.43803690078595314f64
    xs[17usize] = -50.5f64
    ys[17usize] = 50.5f64
    want_perlin[17usize] = 0.0f64
    want_simplex[17usize] = 0.2494723385387233f64
    xs[18usize] = 0.875f64
    ys[18usize] = 0.125f64
    want_perlin[18usize] = -0.12299346923828125f64
    want_simplex[18usize] = -0.4480527043492788f64
    xs[19usize] = 4.4f64
    ys[19usize] = 6.6f64
    want_perlin[19usize] = 0.060460892160000224f64
    want_simplex[19usize] = -0.25109705884466427f64
    want_perlin3[0usize] = -0.1270623045761341f64
    want_perlin7[0usize] = -0.04051038768000015f64
    want_perlin3[1usize] = 0.06185254131911527f64
    want_perlin7[1usize] = 0.038818359375f64
    want_perlin3[2usize] = 0.16113473984437446f64
    want_perlin7[2usize] = -0.1618600703999999f64
    want_perlin3[3usize] = -0.10154285160970314f64
    want_perlin7[3usize] = 0.08414487168192863f64
    want_perlin3[4usize] = 0.439423178292f64
    want_perlin7[4usize] = 0.0f64
    want_f1[0usize] = 0.6593822406148585f64
    want_f2[0usize] = 0.729651877080739f64
    want_f1[1usize] = 0.4496561728742667f64
    want_f2[1usize] = 0.8645851462314317f64
    want_f1[2usize] = 0.28437399725327345f64
    want_f2[2usize] = 0.29256601795789067f64
    want_f1[3usize] = 0.21954181509307713f64
    want_f2[3usize] = 0.4205655648251268f64
    want_f1[4usize] = 0.6112944282113966f64
    want_f2[4usize] = 0.6712512470670525f64
    want_f1[5usize] = 0.46177220265499513f64
    want_f2[5usize] = 0.8042849455750258f64
    want_f1[6usize] = 0.5390218236327419f64
    want_f2[6usize] = 0.9751627991558227f64
    want_f1[7usize] = 0.309716971903158f64
    want_f2[7usize] = 0.9866204100030298f64
    if p7.p[0usize] != 91u8 { os.exit(2i32) }
    if p7.p[1usize] != 223u8 { os.exit(2i32) }
    if p7.p[2usize] != 8u8 { os.exit(2i32) }
    if p7.p[3usize] != 40u8 { os.exit(2i32) }
    if p7.p[4usize] != 203u8 { os.exit(2i32) }
    if p7.p[5usize] != 116u8 { os.exit(2i32) }
    if p7.p[6usize] != 194u8 { os.exit(2i32) }
    if p7.p[7usize] != 252u8 { os.exit(2i32) }
    want_wfc[0usize] = 1583637270573695956u64
    want_wfc[1usize] = 14682978109559791260u64
    want_wfc[2usize] = 482696824399366588u64
    want_wfc[3usize] = 15623639591366271981u64
    want_wfc[4usize] = 8215812835156047685u64

    // 1: Perlin at twenty points against the reference table, in 3-d, and under seed 7.
    var i = 0usize
    while i < 20usize {
        if !near(pg.perlin(&p0, xs[i], ys[i]), want_perlin[i]) { os.exit(1i32) }
        i += 1usize
    }
    if p0.p[0usize] != 151u8 || p0.p[256usize] != 151u8 || p0.p[511usize] != 180u8 { os.exit(1i32) }
    i = 0usize
    while i < 5usize {
        if !near(pg.perlin3(&p0, xs[i], ys[i], 0.37f64), want_perlin3[i]) { os.exit(1i32) }
        if !near(pg.perlin(&p7, xs[i], ys[i]), want_perlin7[i]) { os.exit(2i32) }
        i += 1usize
    }

    // 3: simplex.
    i = 0usize
    while i < 20usize {
        if !near(pg.simplex(&p0, xs[i], ys[i]), want_simplex[i]) { os.exit(3i32) }
        i += 1usize
    }

    // 4: Worley F1/F2.
    i = 0usize
    while i < 8usize {
        let (f1, f2) = pg.worley(xs[i], ys[i], 42u64)
        if !near(f1, want_f1[i]) || !near(f2, want_f2[i]) || f1 > f2 { os.exit(4i32) }
        i += 1usize
    }

    // 5: wave function collapse, four tiles each next to itself and its neighbours by value.
    var allow: [16]u64 = zero
    var t = 0usize
    while t < 4usize {
        var mask = 0u64
        var u = 0usize
        while u < 4usize {
            if u + 1usize >= t && u <= t + 1usize { mask = mask | (1u64 << u32(u)) }
            u += 1usize
        }
        allow[t * 4usize] = mask
        allow[t * 4usize + 1usize] = mask
        allow[t * 4usize + 2usize] = mask
        allow[t * 4usize + 3usize] = mask
        t += 1usize
    }
    var domains: [64]u64 = zero
    var stack: [256]u32 = zero
    var grid: [64]u8 = zero
    var seed = 0usize
    while seed < 5usize {
        var r = rand.pcg64(100u64 + u64(seed), 3u64)
        if pg.wave_function_collapse(allow[..], 4usize, 8usize, 8usize, &r, domains[..], stack[..], grid[..]) != ok { os.exit(5i32) }
        var hash = 0u64
        var c = 0usize
        while c < 64usize {
            hash = hash *% 31u64 +% u64(grid[c])
            let x = c % 8usize
            let y = c / 8usize
            let here = usize(grid[c])
            if here >= 4usize { os.exit(5i32) }
            if x + 1usize < 8usize && ((allow[here * 4usize] >> u32(grid[c + 1usize])) & 1u64) == 0u64 { os.exit(6i32) }
            if y + 1usize < 8usize && ((allow[here * 4usize + 1usize] >> u32(grid[c + 8usize])) & 1u64) == 0u64 { os.exit(6i32) }
            if x > 0usize && ((allow[here * 4usize + 2usize] >> u32(grid[c - 1usize])) & 1u64) == 0u64 { os.exit(6i32) }
            if y > 0usize && ((allow[here * 4usize + 3usize] >> u32(grid[c - 8usize])) & 1u64) == 0u64 { os.exit(6i32) }
            c += 1usize
        }
        if hash != want_wfc[seed] { os.exit(7i32) }
        seed += 1usize
    }
    // Two tiles, nothing may follow tile 1 eastward and nothing may precede tile 0: a 3x1 strip cannot be filled.
    var bad: [8]u64 = zero
    bad[0usize] = 2u64
    bad[1usize] = 3u64
    bad[2usize] = 0u64
    bad[3usize] = 3u64
    bad[4usize] = 0u64
    bad[5usize] = 3u64
    bad[6usize] = 1u64
    bad[7usize] = 3u64
    var r2 = rand.pcg64(1u64, 0u64)
    if pg.wave_function_collapse(bad[..], 2usize, 3usize, 1usize, &r2, domains[..], stack[..], grid[..]) != pg.Invalid { os.exit(8i32) }
    if pg.wave_function_collapse(bad[..], 65usize, 3usize, 1usize, &r2, domains[..], stack[..], grid[..]) != pg.Invalid { os.exit(8i32) }

    try io.print("game procgen ok\n")
    ret ok
}
