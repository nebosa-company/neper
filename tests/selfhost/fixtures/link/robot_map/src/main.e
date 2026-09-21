// `e.robot.map`: twenty raycast scans of a walled room build the same
// log-odds grid as scratchpad/map_ref.py (cell counts and a hash), ICP
// recovers a known pose in a square room to 1e-6, AMCL with the same PCG
// stream matches the replica's weights and particles and ends within 0.1 of
// the truth, and Gauss-Newton closes a drifted ten-pose loop to a residual
// below 1e-8. Each check exits with its own code.

use e.algo.rand
use e.math
use e.robot.map as map
use e.io
use e.mem
use e.os

fn quantized(x: f64, scale: f64) -> u64 { ret u64(i64(math.floor[f64](x * scale + 0.5f64)) + 1000000000i64) }

fn hash_values(xs: []const f64, n: usize, scale: f64) -> u64 {
    var h = 0u64
    var i = 0usize
    while i < n {
        h = h *% 31u64 +% quantized(xs[i], scale)
        i += 1usize
    }
    ret h
}

fn near(x: f64, want: f64, tolerance: f64) -> bool { ret math.abs[f64](x - want) < tolerance }

fn scan(o: *const map.Occupancy, x: f64, y: f64, th: f64, angles: []const f64, ranges: []f64) {
    var k = 0usize
    while k < angles.len {
        ranges[k] = map.raycast(o, x, y, th + angles[k], 6.0f64, 0.0f64)
        k += 1usize
    }
}

fn segment(x0: f64, y0: f64, x1: f64, y1: f64) -> map.Segment { ret map.Segment { x0: x0, y0: y0, x1: x1, y1: y1 } }

fn main(a: *mem.Arena, args: []str) -> err {
    var truth_grid: [1600]f64 = zero
    var i = 0usize
    while i < 1600usize {
        let ix = i % 40usize
        let iy = i / 40usize
        let wall = ix == 0usize || iy == 0usize || ix == 39usize || iy == 39usize || (ix >= 18usize && ix <= 21usize && iy >= 18usize && iy <= 21usize)
        truth_grid[i] = 0.0f64 - 4.0f64
        if wall { truth_grid[i] = 4.0f64 }
        i += 1usize
    }
    let (truth, truth_error) = map.occupancy(truth_grid[..], 40usize, 40usize, 0.25f64)
    if truth_error != ok { os.exit(1i32) }

    // 1: twenty scans into a fresh grid.
    var learned_grid: [1600]f64 = zero
    let (learned, _) = map.occupancy(learned_grid[..], 40usize, 40usize, 0.25f64)
    var learned_o = learned
    var angles36: [36]f64 = zero
    var ranges36: [36]f64 = zero
    i = 0usize
    while i < 36usize {
        angles36[i] = 0.05f64 + f64(i) * (6.283185307179586f64 / 36.0f64)
        i += 1usize
    }
    var k = 0usize
    while k < 20usize {
        let px = 2.0f64 + 0.3f64 * f64(k)
        let py = 2.0f64 + 0.1f64 * f64(k)
        let pth = 0.1f64 * f64(k)
        scan(&truth, px, py, pth, angles36[..], ranges36[..])
        if map.occupancy_update(&learned_o, px, py, pth, ranges36[..], angles36[..], 6.0f64, 0.85f64, 0.0f64 - 0.4f64) != ok { os.exit(1i32) }
        k += 1usize
    }
    var occupied_cells = 0usize
    var free_cells = 0usize
    i = 0usize
    while i < 1600usize {
        if learned_grid[i] > 0.0f64 { occupied_cells += 1usize }
        if learned_grid[i] < 0.0f64 { free_cells += 1usize }
        i += 1usize
    }
    if occupied_cells != 109usize || free_cells != 1289usize { os.exit(1i32) }
    if hash_values(learned_grid[..], 1600usize, 1000000.0f64) != 16207296481033709120u64 { os.exit(1i32) }
    if !near(map.occupancy_probability(0.85f64), 0.700567142473973f64, 0.000000000001f64) { os.exit(1i32) }

    // 2: ICP against the four walls of a 10 x 10 room from a pose 0.3 off.
    var lines: [4]map.Segment = zero
    lines[0usize] = segment(0.0f64, 0.0f64, 10.0f64, 0.0f64)
    lines[1usize] = segment(10.0f64, 0.0f64, 10.0f64, 10.0f64)
    lines[2usize] = segment(10.0f64, 10.0f64, 0.0f64, 10.0f64)
    lines[3usize] = segment(0.0f64, 10.0f64, 0.0f64, 0.0f64)
    var px: [40]f64 = zero
    var py: [40]f64 = zero
    let c = math.cos[f64](0.0f64 - 0.35f64)
    let s = math.sin[f64](0.0f64 - 0.35f64)
    k = 0usize
    while k < 10usize {
        let t = 0.5f64 + f64(k)
        var wx: [4]f64 = zero
        var wy: [4]f64 = zero
        wx[0usize] = t
        wx[1usize] = 10.0f64
        wy[1usize] = t
        wx[2usize] = t
        wy[2usize] = 10.0f64
        wy[3usize] = t
        var q = 0usize
        while q < 4usize {
            px[4usize * k + q] = c * (wx[q] - 4.3f64) - s * (wy[q] - 3.7f64)
            py[4usize * k + q] = s * (wx[q] - 4.3f64) + c * (wy[q] - 3.7f64)
            q += 1usize
        }
        k += 1usize
    }
    let (ix, iy, ith, mse) = map.scan_match(px[..], py[..], lines[..], 4.0f64, 4.0f64, 0.2f64, 100usize)
    if !near(ix, 4.3f64, 0.000001f64) || !near(iy, 3.7f64, 0.000001f64) || !near(ith, 0.35f64, 0.000001f64) { os.exit(2i32) }
    if mse >= 0.000000000001f64 { os.exit(2i32) }

    // 3: AMCL over the truth grid's likelihood field for thirty steps.
    var field: [1600]f64 = zero
    if map.likelihood_field(&truth, 0.0f64, field[..]) != ok { os.exit(3i32) }
    if hash_values(field[..], 1600usize, 1000000.0f64) != 17506308652638182336u64 { os.exit(3i32) }
    let sensor = map.Sensor { field: field[..], max_range: 6.0f64, sigma: 0.2f64, off_grid: 2.0f64 }
    let motion = map.Motion { dx: 0.2f64, dy: 0.0f64, dth: 0.15f64, noise_xy: 0.05f64, noise_th: 0.03f64 }
    var angles18: [18]f64 = zero
    var ranges18: [18]f64 = zero
    i = 0usize
    while i < 18usize {
        angles18[i] = 0.05f64 + f64(i) * (6.283185307179586f64 / 18.0f64)
        i += 1usize
    }
    var xs: [200]f64 = zero
    var ys: [200]f64 = zero
    var ths: [200]f64 = zero
    var weights: [200]f64 = zero
    var scratch: [600]f64 = zero
    var r = rand.pcg64(21u64, 3u64)
    let (particles, particles_error) = map.particles(xs[..], ys[..], ths[..], weights[..], scratch[..], 200usize)
    if particles_error != ok { os.exit(3i32) }
    var swarm = particles
    map.particles_init(&swarm, &r, 2.0f64, 2.0f64, 0.0f64, 0.5f64, 0.3f64)
    var ax = 2.5f64
    var ay = 2.5f64
    var ath = 0.0f64
    var mx = 0.0f64
    var my = 0.0f64
    var mth = 0.0f64
    k = 0usize
    while k < 30usize {
        ax += 0.2f64 * math.cos[f64](ath)
        ay += 0.2f64 * math.sin[f64](ath)
        ath = map.wrap_angle(ath + 0.15f64)
        scan(&truth, ax, ay, ath, angles18[..], ranges18[..])
        if k == 0usize {
            map.amcl_predict(&swarm, &motion, &r)
            if map.amcl_weigh(&swarm, &truth, &sensor, ranges18[..], angles18[..]) != ok { os.exit(3i32) }
            if hash_values(weights[..], 200usize, 1000000000.0f64) != 14573594499797862912u64 { os.exit(3i32) }
            map.amcl_resample(&swarm, &r)
        } else {
            let (sx, sy, sth, step_error) = map.localize_amcl(&swarm, &motion, &truth, &sensor, ranges18[..], angles18[..], &r)
            if step_error != ok { os.exit(3i32) }
            mx = sx
            my = sy
            mth = sth
        }
        k += 1usize
    }
    if !near(mx, ax, 0.1f64) || !near(my, ay, 0.1f64) || math.abs[f64](map.wrap_angle(mth - ath)) >= 0.1f64 { os.exit(3i32) }
    var particle_hash = 0u64
    i = 0usize
    while i < 200usize {
        particle_hash = particle_hash *% 31u64 +% quantized(xs[i], 1000000.0f64)
        particle_hash = particle_hash *% 31u64 +% quantized(ys[i], 1000000.0f64)
        i += 1usize
    }
    if particle_hash != 7396634260303956132u64 { os.exit(3i32) }

    // 4: a drifted decagon of poses with exact odometry and one loop closure.
    var txs: [10]f64 = zero
    var tys: [10]f64 = zero
    var tths: [10]f64 = zero
    var gxs: [10]f64 = zero
    var gys: [10]f64 = zero
    var gths: [10]f64 = zero
    var edges: [10]map.Edge = zero
    let turn = 6.283185307179586f64 / 10.0f64
    k = 1usize
    while k < 10usize {
        txs[k] = txs[k - 1usize] + math.cos[f64](tths[k - 1usize])
        tys[k] = tys[k - 1usize] + math.sin[f64](tths[k - 1usize])
        tths[k] = map.wrap_angle(tths[k - 1usize] + turn)
        gxs[k] = gxs[k - 1usize] + (1.0f64 + 0.02f64 * f64(k)) * math.cos[f64](gths[k - 1usize])
        gys[k] = gys[k - 1usize] + (1.0f64 + 0.02f64 * f64(k)) * math.sin[f64](gths[k - 1usize])
        gths[k] = map.wrap_angle(gths[k - 1usize] + turn + 0.01f64)
        edges[k - 1usize] = map.Edge { i: u32(k - 1usize), j: u32(k), dx: 1.0f64, dy: 0.0f64, dth: turn, info_xy: 1.0f64, info_th: 100.0f64 }
        k += 1usize
    }
    let c9 = math.cos[f64](tths[9usize])
    let s9 = math.sin[f64](tths[9usize])
    let ldx = txs[0usize] - txs[9usize]
    let ldy = tys[0usize] - tys[9usize]
    edges[9usize] = map.Edge { i: 9u32, j: 0u32, dx: c9 * ldx + s9 * ldy, dy: 0.0f64 - s9 * ldx + c9 * ldy, dth: map.wrap_angle(tths[0usize] - tths[9usize]), info_xy: 1.0f64, info_th: 100.0f64 }
    if !near(map.residual(gxs[..], gys[..], gths[..], edges[..]), 1.0820137138914592f64, 0.000000001f64) { os.exit(4i32) }
    var work: [800]f64 = zero
    let (after, optimize_error) = map.pose_graph_optimize(gxs[..], gys[..], gths[..], edges[..], 10usize, work[..])
    if optimize_error != ok || after >= 0.00000001f64 { os.exit(4i32) }
    k = 0usize
    while k < 10usize {
        if !near(gxs[k], txs[k], 0.000001f64) || !near(gys[k], tys[k], 0.000001f64) || math.abs[f64](map.wrap_angle(gths[k] - tths[k])) >= 0.000001f64 { os.exit(4i32) }
        k += 1usize
    }

    // 5: the storage and shape errors.
    let (_, short_grid) = map.occupancy(learned_grid[..100usize], 40usize, 40usize, 0.25f64)
    if short_grid != map.TooSmall { os.exit(5i32) }
    if map.occupancy_update(&learned_o, 1.0f64, 1.0f64, 0.0f64, ranges18[..], angles36[..], 6.0f64, 0.85f64, 0.0f64 - 0.4f64) != map.Invalid { os.exit(5i32) }
    let (_, few) = map.particles(xs[..], ys[..], ths[..], weights[..], scratch[..10usize], 200usize)
    if few != map.TooSmall { os.exit(5i32) }
    let (_, short_work) = map.pose_graph_optimize(gxs[..], gys[..], gths[..], edges[..], 1usize, work[..100usize])
    if short_work != map.TooSmall { os.exit(5i32) }
    edges[9usize].j = 9u32
    let (_, self_edge) = map.pose_graph_optimize(gxs[..], gys[..], gths[..], edges[..], 1usize, work[..])
    if self_edge != map.Invalid { os.exit(5i32) }

    try io.print("robot map ok\n")
    ret ok
}
