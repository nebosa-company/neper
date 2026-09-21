// `e.gfx.vision`: Harris corners of a soft square, Hough lines through
// two drawn lines, a homography and a fundamental matrix recovered from
// synthetic correspondences, RANSAC finding the planted inlier set, phase
// correlation of a rolled image, Lucas-Kanade and Farneback flow of a
// shifted blob, ICP recovering a rigid motion, ORB and SIFT keypoints and
// descriptors against the Python replica, Zhang's intrinsics from five
// views and a two-view reconstruction. Each check exits with its own code.

use e.algo.geom3
use e.algo.rand
use e.gfx.vision
use e.io
use e.math
use e.mem
use e.os

type Lcg = struct { state: u64 }
type Fit = struct { src: []const vision.Point, dst: []const vision.Point, h: []f64 }

fn lcg_f(r: *Lcg) -> f64 {
    r.state = r.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64(r.state >> 33u32) / 2147483648.0f64
}

fn near(x: f64, want: f64, eps: f64) -> bool { ret math.abs[f64](x - want) < eps }

fn floats(a: *mem.Arena, n: usize) -> []f64 {
    let (buf, e) = mem.alloc[f64](a, n)
    if e != ok { os.exit(99i32) }
    var i = 0usize
    while i < n {
        buf[i] = 0.0f64
        i += 1usize
    }
    ret buf
}

fn add_blob(img: []f64, w: usize, h: usize, cx: f64, cy: f64, s: f64, amp: f64) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let dx = f64(x) - cx
            let dy = f64(y) - cy
            img[y * w + x] += amp * math.exp[f64](0.0f64 - (dx * dx + dy * dy) / (2.0f64 * s * s))
            x += 1usize
        }
        y += 1usize
    }
}

// Rodrigues' rotation about the unit `axis` by `angle` into nine entries.
fn rodrigues(ax: f64, ay: f64, az: f64, angle: f64, out: []f64) {
    let n = math.sqrt[f64](ax * ax + ay * ay + az * az)
    let x = ax / n
    let y = ay / n
    let z = az / n
    let c = math.cos[f64](angle)
    let s = math.sin[f64](angle)
    let t = 1.0f64 - c
    out[0usize] = c + x * x * t
    out[1usize] = x * y * t - z * s
    out[2usize] = x * z * t + y * s
    out[3usize] = y * x * t + z * s
    out[4usize] = c + y * y * t
    out[5usize] = y * z * t - x * s
    out[6usize] = z * x * t - y * s
    out[7usize] = z * y * t + x * s
    out[8usize] = c + z * z * t
}

fn project(k: []const f64, r: []const f64, t: geom3.Vec3, x: geom3.Vec3) -> vision.Point {
    let c = geom3.add(geom3.rotate(r, x), t)
    let px = k[0usize] * c.x + k[1usize] * c.y + k[2usize] * c.z
    let py = k[4usize] * c.y + k[5usize] * c.z
    ret vision.Point { x: px / c.z, y: py / c.z }
}

fn fit_h(ctx: *Fit, idx: []const usize) -> bool {
    var s: [4]vision.Point = zero
    var d: [4]vision.Point = zero
    var i = 0usize
    while i < 4usize {
        s[i] = ctx.src[idx[i]]
        d[i] = ctx.dst[idx[i]]
        i += 1usize
    }
    ret vision.homography(s[..], d[..], ctx.h) == ok
}

fn residual_h(ctx: *Fit, i: usize) -> f64 {
    let p = vision.apply_homography(ctx.h, ctx.src[i])
    let dx = p.x - ctx.dst[i].x
    let dy = p.y - ctx.dst[i].y
    ret math.sqrt[f64](dx * dx + dy * dy)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: Harris corners of a soft square under noise.
    var r = Lcg { state: 1u64 }
    var img = floats(a, 1024usize)
    var y = 0usize
    while y < 32usize {
        var x = 0usize
        while x < 32usize {
            var v = 0.01f64 * lcg_f(&r)
            if x >= 8usize && x < 20usize && y >= 10usize && y < 22usize { v += 1.0f64 }
            img[y * 32usize + x] = v
            x += 1usize
        }
        y += 1usize
    }
    var scratch = floats(a, 1024usize)
    var corners: [8]vision.Keypoint = zero
    let (corner_count, corner_error) = vision.harris_corners(img, 32usize, 32usize, 0.04f64, 1.5f64, 1.0e-4f64, corners[..], scratch)
    if corner_error != ok || corner_count != 4usize { os.exit(1i32) }
    let want_x = [4]f64{ 8.0f64, 19.0f64, 8.0f64, 19.0f64 }
    let want_y = [4]f64{ 10.0f64, 10.0f64, 21.0f64, 21.0f64 }
    let want_r = [4]f64{ 0.0044838943804036135f64, 0.004507484789558781f64, 0.004519009452750049f64, 0.004550671548181269f64 }
    var i = 0usize
    while i < 4usize {
        if corners[i].x != want_x[i] || corners[i].y != want_y[i] || !near(corners[i].response, want_r[i], 1.0e-12f64) { os.exit(1i32) }
        i += 1usize
    }

    // 2: Hough lines through a diagonal and a horizontal.
    var edges: [1024]bool = zero
    i = 3usize
    while i < 29usize {
        edges[i * 32usize + i] = true
        edges[20usize * 32usize + i] = true
        i += 1usize
    }
    let (acc, acc_error) = mem.alloc[u32](a, 93usize * 180usize)
    if acc_error != ok { os.exit(2i32) }
    var lines: [8]vision.Line = zero
    let (line_count, line_error) = vision.hough_lines(edges[..], 32usize, 32usize, 93usize, 180usize, 15u32, acc, lines[..])
    if line_error != ok || line_count != 5usize { os.exit(2i32) }
    let want_rho = [5]f64{ -20.0f64, -19.0f64, 0.0f64, 20.0f64, 21.0f64 }
    let want_theta = [5]f64{ -1.5707963267948966f64, -1.5184364492350666f64, -0.7853981633974483f64, 1.5533430342749535f64, 1.5184364492350668f64 }
    let want_votes = [5]u32{ 26u32, 19u32, 26u32, 26u32, 18u32 }
    i = 0usize
    while i < 5usize {
        if !near(lines[i].rho, want_rho[i], 1.0e-9f64) || !near(lines[i].theta, want_theta[i], 1.0e-12f64) || lines[i].votes != want_votes[i] { os.exit(2i32) }
        i += 1usize
    }

    // 3: a homography recovered from six correspondences.
    r = Lcg { state: 2u64 }
    let h_true = [9]f64{ 1.2f64, 0.1f64, 5.0f64, -0.2f64, 0.9f64, -3.0f64, 0.001f64, -0.002f64, 1.0f64 }
    var src: [20]vision.Point = zero
    var dst: [20]vision.Point = zero
    i = 0usize
    while i < 6usize {
        let px = lcg_f(&r) * 100.0f64
        src[i] = vision.Point { x: px, y: lcg_f(&r) * 100.0f64 }
        dst[i] = vision.apply_homography(h_true[..], src[i])
        i += 1usize
    }
    var hm: [9]f64 = zero
    if vision.homography(src[..6usize], dst[..6usize], hm[..]) != ok { os.exit(3i32) }
    i = 0usize
    while i < 9usize {
        if !near(hm[i], h_true[i], 1.0e-6f64) { os.exit(3i32) }
        i += 1usize
    }

    // 4: the fundamental matrix of two synthetic views.
    r = Lcg { state: 3u64 }
    let k = [9]f64{ 800.0f64, 0.0f64, 320.0f64, 0.0f64, 780.0f64, 240.0f64, 0.0f64, 0.0f64, 1.0f64 }
    var world: [12]geom3.Vec3 = zero
    let r_true = [9]f64{ 0.9891988463956216f64, -0.012444826140331088f64, 0.14605056861206772f64, 0.01672251073612452f64, 0.9994652894255258f64, -0.02809791572750725f64, -0.14562280015248835f64, 0.030236758025403966f64, 0.9888780200509371f64 }
    let t_true = geom3.vec3(-1.0f64, 0.2f64, 0.3f64)
    let identity = [9]f64{ 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64 }
    var pa: [12]vision.Point = zero
    var pb: [12]vision.Point = zero
    i = 0usize
    while i < 12usize {
        let wx = lcg_f(&r) * 4.0f64 - 2.0f64
        let wy = lcg_f(&r) * 4.0f64 - 2.0f64
        world[i] = geom3.vec3(wx, wy, 6.0f64 + lcg_f(&r) * 4.0f64)
        pa[i] = project(k[..], identity[..], geom3.vec3(0.0f64, 0.0f64, 0.0f64), world[i])
        pb[i] = project(k[..], r_true[..], t_true, world[i])
        i += 1usize
    }
    var fm: [9]f64 = zero
    if vision.fundamental_matrix(pa[..], pb[..], fm[..]) != ok { os.exit(4i32) }
    i = 0usize
    while i < 12usize {
        if math.abs[f64](vision.epipolar_residual(fm[..], pa[i], pb[i])) > 1.0e-8f64 { os.exit(4i32) }
        i += 1usize
    }
    if math.abs[f64](vision.det3(fm[..])) > 1.0e-12f64 { os.exit(4i32) }
    let f_want = [9]f64{ 1.8192810865691014e-06f64, 1.605666244842261e-05f64, -0.013226170471451764f64, -8.260100658690151e-06f64, -1.485629348515633e-06f64, -0.042152141096715175f64, 0.010546922783752275f64, 0.03880871285049158f64, 0.9982138605082288f64 }
    var sign = 1.0f64
    if fm[8usize] < 0.0f64 { sign = -1.0f64 }
    i = 0usize
    while i < 9usize {
        if !near(sign * fm[i], f_want[i], 1.0e-6f64) { os.exit(4i32) }
        i += 1usize
    }

    // 5: RANSAC over a homography with six planted outliers of twenty.
    r = Lcg { state: 4u64 }
    i = 0usize
    while i < 20usize {
        let px = lcg_f(&r) * 100.0f64
        src[i] = vision.Point { x: px, y: lcg_f(&r) * 100.0f64 }
        dst[i] = vision.apply_homography(h_true[..], src[i])
        i += 1usize
    }
    let outliers = [6]usize{ 1usize, 4usize, 7usize, 11usize, 15usize, 18usize }
    i = 0usize
    while i < 6usize {
        let ox = dst[outliers[i]].x + 20.0f64 + lcg_f(&r) * 10.0f64
        dst[outliers[i]] = vision.Point { x: ox, y: dst[outliers[i]].y - 15.0f64 - lcg_f(&r) * 10.0f64 }
        i += 1usize
    }
    var model: [9]f64 = zero
    var fit = Fit { src: src[..], dst: dst[..], h: model[..] }
    var rng = rand.pcg64(11u64, 3u64)
    var inliers: [20]bool = zero
    var sample: [8]usize = zero
    let (inlier_count, ransac_error) = vision.ransac[Fit](&fit, 20usize, 4usize, 100u32, 1.0e-6f64, fit_h, residual_h, &rng, inliers[..], sample[..])
    if ransac_error != ok || inlier_count != 14usize { os.exit(5i32) }
    i = 0usize
    while i < 20usize {
        var planted = false
        var j = 0usize
        while j < 6usize {
            if outliers[j] == i { planted = true }
            j += 1usize
        }
        if inliers[i] == planted { os.exit(5i32) }
        i += 1usize
    }
    i = 0usize
    while i < 9usize {
        if !near(model[i], h_true[i], 1.0e-6f64) { os.exit(5i32) }
        i += 1usize
    }

    // 6: phase correlation of a cyclic shift by (3, -2).
    r = Lcg { state: 5u64 }
    var pa16 = floats(a, 256usize)
    var pb16 = floats(a, 256usize)
    i = 0usize
    while i < 256usize {
        pa16[i] = lcg_f(&r)
        i += 1usize
    }
    y = 0usize
    while y < 16usize {
        var x = 0usize
        while x < 16usize {
            pb16[y * 16usize + x] = pa16[((y + 2usize) % 16usize) * 16usize + (x + 13usize) % 16usize]
            x += 1usize
        }
        y += 1usize
    }
    var phase_scratch = floats(a, 4usize * 256usize + 32usize)
    let (sx, sy, peak, phase_error) = vision.phase_correlate(pa16, pb16, 16usize, 16usize, phase_scratch)
    if phase_error != ok || sx != 3.0f64 || sy != -2.0f64 || !near(peak, 1.0f64, 1.0e-9f64) { os.exit(6i32) }

    // 7: Lucas-Kanade on a blob shifted by (0.4, -0.3).
    var ba = floats(a, 1024usize)
    var bb = floats(a, 1024usize)
    add_blob(ba, 32usize, 32usize, 15.0f64, 14.0f64, 3.0f64, 1.0f64)
    add_blob(bb, 32usize, 32usize, 15.4f64, 13.7f64, 3.0f64, 1.0f64)
    let track = [2]vision.Point{ vision.Point { x: 15.0f64, y: 14.0f64 }, vision.Point { x: 17.0f64, y: 12.0f64 } }
    var flows: [2]vision.Point = zero
    if vision.optical_flow_lk(ba, bb, 32usize, 32usize, track[..], 5usize, 10u32, flows[..]) != ok { os.exit(7i32) }
    if !near(flows[0usize].x, 0.4015554452248894f64, 1.0e-9f64) || !near(flows[0usize].y, -0.30272749420670825f64, 1.0e-9f64) { os.exit(7i32) }
    if !near(flows[1usize].x, 0.40790402236364565f64, 1.0e-9f64) || !near(flows[1usize].y, -0.30732367095108903f64, 1.0e-9f64) { os.exit(7i32) }
    if !near(flows[0usize].x, 0.4f64, 0.05f64) || !near(flows[0usize].y, -0.3f64, 0.05f64) { os.exit(7i32) }

    // 8: Farneback on a 16x16 blob shifted by one pixel.
    var fa = floats(a, 256usize)
    var fb = floats(a, 256usize)
    add_blob(fa, 16usize, 16usize, 7.0f64, 8.0f64, 2.5f64, 1.0f64)
    add_blob(fb, 16usize, 16usize, 8.0f64, 8.0f64, 2.5f64, 1.0f64)
    let (dense, dense_error) = mem.alloc[vision.Point](a, 256usize)
    if dense_error != ok { os.exit(8i32) }
    var dense_scratch = floats(a, 2560usize)
    if vision.optical_flow_farneback(fa, fb, 16usize, 16usize, 2usize, dense, dense_scratch) != ok { os.exit(8i32) }
    var sum_x = 0.0f64
    var sum_y = 0.0f64
    i = 0usize
    while i < 256usize {
        sum_x += dense[i].x
        sum_y += dense[i].y
        i += 1usize
    }
    if !near(dense[8usize * 16usize + 7usize].x, 0.9487012215456566f64, 1.0e-9f64) || !near(dense[8usize * 16usize + 7usize].y, 0.0f64, 1.0e-9f64) { os.exit(8i32) }
    if !near(sum_x, 242.57441091418482f64, 1.0e-7f64) || !near(sum_y, 0.0f64, 1.0e-9f64) { os.exit(8i32) }

    // 9: ICP recovers a rigid motion.
    r = Lcg { state: 6u64 }
    var cloud: [12]geom3.Vec3 = zero
    var moved_cloud: [12]geom3.Vec3 = zero
    var matched: [12]geom3.Vec3 = zero
    var r_icp: [9]f64 = zero
    rodrigues(1.0f64, 2.0f64, 0.5f64, 10.0f64 * 3.141592653589793f64 / 180.0f64, r_icp[..])
    let t_icp = geom3.vec3(0.3f64, -0.2f64, 0.5f64)
    i = 0usize
    while i < 12usize {
        let cx = lcg_f(&r) * 10.0f64
        let cy = lcg_f(&r) * 10.0f64
        cloud[i] = geom3.vec3(cx, cy, lcg_f(&r) * 10.0f64)
        moved_cloud[i] = geom3.add(geom3.rotate(r_icp[..], cloud[i]), t_icp)
        i += 1usize
    }
    var r_found: [9]f64 = zero
    let (t_found, icp_error_value, icp_error) = vision.icp(cloud[..], moved_cloud[..], 20u32, r_found[..], matched[..])
    if icp_error != ok || icp_error_value > 1.0e-12f64 { os.exit(9i32) }
    if !near(t_found.x, 0.3f64, 1.0e-6f64) || !near(t_found.y, -0.2f64, 1.0e-6f64) || !near(t_found.z, 0.5f64, 1.0e-6f64) { os.exit(9i32) }
    i = 0usize
    while i < 9usize {
        if !near(r_found[i], r_icp[i], 1.0e-6f64) { os.exit(9i32) }
        i += 1usize
    }

    // 10: ORB keypoints and descriptors on squares under noise.
    r = Lcg { state: 7u64 }
    var orb_img = floats(a, 96usize * 96usize)
    y = 0usize
    while y < 96usize {
        var x = 0usize
        while x < 96usize {
            var v = 0.1f64 * lcg_f(&r)
            if x >= 26usize && x < 38usize && y >= 24usize && y < 40usize { v += 1.0f64 }
            if x >= 50usize && x < 62usize && y >= 30usize && y < 44usize { v += 0.7f64 }
            if x >= 30usize && x < 44usize && y >= 50usize && y < 66usize { v += 0.5f64 }
            if x >= 56usize && x < 70usize && y >= 54usize && y < 68usize { v += 0.9f64 }
            orb_img[y * 96usize + x] = v
            x += 1usize
        }
        y += 1usize
    }
    var keypoints: [10]vision.Keypoint = zero
    var descriptors: [320]u8 = zero
    let (orb_count, orb_error) = vision.orb(orb_img, 96usize, 96usize, 0.2f64, keypoints[..], descriptors[..])
    if orb_error != ok || orb_count != 10usize { os.exit(10i32) }
    let orb_xy = [20]usize{ 36usize, 38usize, 27usize, 25usize, 36usize, 25usize, 27usize, 38usize, 57usize, 55usize, 57usize, 66usize, 68usize, 66usize, 68usize, 55usize, 51usize, 42usize, 60usize, 31usize }
    let orb_angles = [10]f64{ -2.2280735231106985f64, 0.9606675608612336f64, 2.1740330231905416f64, -0.894016998968013f64, 0.6436115453630419f64, -0.8156021981087298f64, -2.3573648400919582f64, 2.387461619996362f64, -0.8023747264941044f64, 2.261076877239589f64 }
    var hash = 2166136261u32
    i = 0usize
    while i < 10usize {
        if keypoints[i].x != f64(orb_xy[2usize * i]) || keypoints[i].y != f64(orb_xy[2usize * i + 1usize]) || !near(keypoints[i].angle, orb_angles[i], 1.0e-9f64) { os.exit(10i32) }
        var j = 0usize
        while j < 32usize {
            hash = (hash ^ u32(descriptors[i * 32usize + j])) *% 16777619u32
            j += 1usize
        }
        i += 1usize
    }
    if hash != 2481775173u32 { os.exit(10i32) }
    if descriptors[0usize] != 161u8 || descriptors[1usize] != 216u8 || descriptors[32usize] != 4u8 { os.exit(10i32) }
    if vision.hamming(descriptors[..32usize], descriptors[..32usize]) != 0u32 { os.exit(10i32) }

    // 11: SIFT on two blobs under noise.
    r = Lcg { state: 8u64 }
    var sift_img = floats(a, 4096usize)
    add_blob(sift_img, 64usize, 64usize, 30.0f64, 28.0f64, 4.0f64, 1.0f64)
    add_blob(sift_img, 64usize, 64usize, 48.0f64, 50.0f64, 2.5f64, 0.8f64)
    i = 0usize
    while i < 4096usize {
        sift_img[i] += 0.02f64 * lcg_f(&r)
        i += 1usize
    }
    var sift_scratch = floats(a, 12usize * 4096usize)
    var sift_keys: [16]vision.Keypoint = zero
    var sift_desc = floats(a, 16usize * 128usize)
    let (sift_count, sift_error) = vision.sift(sift_img, 64usize, 64usize, 0.03f64, sift_keys[..], sift_desc, sift_scratch)
    if sift_error != ok || sift_count != 2usize { os.exit(11i32) }
    if sift_keys[0usize].x != 48.0f64 || sift_keys[0usize].y != 50.0f64 || !near(sift_keys[0usize].angle, 3.1389776404341636f64, 1.0e-9f64) || !near(sift_keys[0usize].scale, 2.015873679831797f64, 1.0e-12f64) { os.exit(11i32) }
    if sift_keys[1usize].x != 30.0f64 || sift_keys[1usize].y != 28.0f64 || !near(sift_keys[1usize].angle, 5.322155088201378f64, 1.0e-9f64) || !near(sift_keys[1usize].response, -0.11550409023587416f64, 1.0e-12f64) || sift_keys[1usize].scale != 3.2f64 { os.exit(11i32) }
    let want_sum = [2]f64{ 354.3966612668277f64, 361.13207830023623f64 }
    let want_max = [2]f64{ 0.25829657111378845f64, 0.2575185050176335f64 }
    i = 0usize
    while i < 2usize {
        var weighted = 0.0f64
        var largest = 0.0f64
        var j = 0usize
        while j < 128usize {
            let d = sift_desc[i * 128usize + j]
            weighted += f64(j + 1usize) * d
            if d > largest { largest = d }
            j += 1usize
        }
        if !near(weighted, want_sum[i], 1.0e-6f64) || !near(largest, want_max[i], 1.0e-9f64) { os.exit(11i32) }
        i += 1usize
    }

    // 12: Zhang's intrinsics from five views of a planar grid.
    r = Lcg { state: 9u64 }
    var grid: [20]vision.Point = zero
    i = 0usize
    while i < 20usize {
        grid[i] = vision.Point { x: f64(i % 5usize), y: f64(i / 5usize) }
        i += 1usize
    }
    var views: [100]vision.Point = zero
    var view = 0usize
    while view < 5usize {
        let ax = lcg_f(&r) - 0.5f64
        let ay = lcg_f(&r) - 0.5f64
        let az = lcg_f(&r) - 0.5f64
        var rv: [9]f64 = zero
        rodrigues(ax, ay, az, 0.3f64 + 0.2f64 * lcg_f(&r), rv[..])
        let tx = lcg_f(&r) * 2.0f64 - 3.0f64
        let ty = lcg_f(&r) * 2.0f64 - 2.5f64
        let tv = geom3.vec3(tx, ty, 12.0f64 + lcg_f(&r) * 4.0f64)
        i = 0usize
        while i < 20usize {
            views[view * 20usize + i] = project(k[..], rv[..], tv, geom3.vec3(grid[i].x, grid[i].y, 0.0f64))
            i += 1usize
        }
        view += 1usize
    }
    var k_found: [9]f64 = zero
    if vision.calibrate_camera(grid[..], views[..], 5usize, k_found[..]) != ok { os.exit(12i32) }
    i = 0usize
    while i < 9usize {
        if !near(k_found[i], k[i], 1.0e-4f64) { os.exit(12i32) }
        i += 1usize
    }

    // 13: structure from motion of the two views of check 4.
    var r_sfm: [9]f64 = zero
    var t_sfm: [3]f64 = zero
    var cloud_sfm: [12]geom3.Vec3 = zero
    var sfm_scratch: [24]vision.Point = zero
    if vision.structure_from_motion(k[..], pa[..], pb[..], r_sfm[..], t_sfm[..], cloud_sfm[..], sfm_scratch[..]) != ok { os.exit(13i32) }
    let t_norm = geom3.length(t_true)
    if !near(t_sfm[0usize], t_true.x / t_norm, 1.0e-6f64) || !near(t_sfm[1usize], t_true.y / t_norm, 1.0e-6f64) || !near(t_sfm[2usize], t_true.z / t_norm, 1.0e-6f64) { os.exit(13i32) }
    i = 0usize
    while i < 9usize {
        if !near(r_sfm[i], r_true[i], 1.0e-6f64) { os.exit(13i32) }
        i += 1usize
    }
    i = 0usize
    while i < 12usize {
        let p = geom3.scale(cloud_sfm[i], t_norm)
        if !near(p.x, world[i].x, 1.0e-4f64) || !near(p.y, world[i].y, 1.0e-4f64) || !near(p.z, world[i].z, 1.0e-4f64) { os.exit(13i32) }
        i += 1usize
    }

    try io.print("gfx vision ok\n")
    ret ok
}
