// `e.gfx.mesh`: half edges of a cube and an open patch, area-weighted and
// PCA normals, Laplacian and Taubin smoothing volumes, Loop and
// Catmull-Clark counts and volumes, quadric decimation of an icosphere to
// 100 triangles keeping its volume, marching squares and cubes counts and
// checksums (the cube count agrees with scikit-image), dual contouring of a
// sphere, signed distances against brute force with ray parity, fast
// marching and the heat method against great-circle distances, LSCM of a
// flat grid recovering its coordinates, ball pivoting closing a sphere
// cloud, a Poisson field whose contour has the sphere's volume, csg.js
// booleans of two cubes with analytic volumes, and a revolved cylinder.
// Every expected value is from a Python replica. Each check exits with its
// own code.

use e.gfx.mesh
use e.io
use e.math
use e.mem
use e.os

type Sphere = struct { cx: f64, cy: f64, cz: f64, r: f64 }

fn sphere_sdf(s: *Sphere, x: f64, y: f64, z: f64) -> f64 {
    ret math.sqrt[f64]((x - s.cx) * (x - s.cx) + (y - s.cy) * (y - s.cy) + (z - s.cz) * (z - s.cz)) - s.r
}

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tolerance
}

fn checksum(xs: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < xs.len {
        sum += xs[i] * f64(i % 7usize + 1usize)
        i += 1usize
    }
    ret sum
}

fn unit_sphere(vertices: []f64, n: usize) {
    var i = 0usize
    while i < n {
        let x = vertices[3usize * i]
        let y = vertices[3usize * i + 1usize]
        let z = vertices[3usize * i + 2usize]
        let norm = math.sqrt[f64](x * x + y * y + z * z)
        vertices[3usize * i] = x / norm
        vertices[3usize * i + 1usize] = y / norm
        vertices[3usize * i + 2usize] = z / norm
        i += 1usize
    }
}

// The icosahedron Loop-subdivided `levels` times with every vertex projected
// onto the unit sphere, answered in `va`/`ta`.
fn icosphere(levels: usize, ico_v: []const f64, ico_t: []const u32, va: []f64, ta: []u32, vb: []f64, tb: []u32, scratch: []u32) -> (usize, usize) {
    var n = 12usize
    var t = 20usize
    var k = 0usize
    while k < 60usize {
        if k < 36usize { va[k] = ico_v[k] }
        ta[k] = ico_t[k]
        k += 1usize
    }
    unit_sphere(va, n)
    var level = 0usize
    while level < levels {
        let (n2, t2, e) = mesh.subdivide_loop(va[..3usize * n], ta[..3usize * t], vb, tb, scratch)
        if e != ok { os.exit(99i32) }
        unit_sphere(vb, n2)
        var i = 0usize
        while i < 3usize * n2 {
            va[i] = vb[i]
            i += 1usize
        }
        i = 0usize
        while i < 3usize * t2 {
            ta[i] = tb[i]
            i += 1usize
        }
        n = n2
        t = t2
        level += 1usize
    }
    ret (n, t)
}

// A Fibonacci sphere of `n` points at `radius` with radial normals.
fn fibonacci(n: usize, radius: f64, points: []f64, normals: []f64) {
    var i = 0usize
    while i < n {
        let y = 1.0f64 - 2.0f64 * (f64(i) + 0.5f64) / f64(n)
        let r = math.sqrt[f64](1.0f64 - y * y)
        let angle = 2.399963229728653f64 * f64(i)
        normals[3usize * i] = r * math.cos[f64](angle)
        normals[3usize * i + 1usize] = y
        normals[3usize * i + 2usize] = r * math.sin[f64](angle)
        points[3usize * i] = normals[3usize * i] * radius
        points[3usize * i + 1usize] = y * radius
        points[3usize * i + 2usize] = normals[3usize * i + 2usize] * radius
        i += 1usize
    }
}

// Mean and greatest relative error of `distance` against the great circle
// from vertex 0 on the unit sphere, over vertices further than 0.5.
fn geodesic_error(vertices: []const f64, n: usize, distance: []const f64) -> (f64, f64) {
    var sum = 0.0f64
    var worst = 0.0f64
    var counted = 0usize
    var i = 0usize
    while i < n {
        var cosine = vertices[0usize] * vertices[3usize * i] + vertices[1usize] * vertices[3usize * i + 1usize] + vertices[2usize] * vertices[3usize * i + 2usize]
        if cosine > 1.0f64 { cosine = 1.0f64 }
        if cosine < 0.0f64 - 1.0f64 { cosine = 0.0f64 - 1.0f64 }
        let truth = math.acos[f64](cosine)
        if truth > 0.5f64 {
            var e = (distance[i] - truth) / truth
            if e < 0.0f64 { e = 0.0f64 - e }
            sum += e
            if e > worst { worst = e }
            counted += 1usize
        }
        i += 1usize
    }
    ret (sum / f64(counted), worst)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var ico_v: [36]f64 = [36]f64{ -1.0, 1.618033988749895, 0.0, 1.0, 1.618033988749895, 0.0, -1.0, -1.618033988749895, 0.0, 1.0, -1.618033988749895, 0.0, 0.0, -1.0, 1.618033988749895, 0.0, 1.0, 1.618033988749895, 0.0, -1.0, -1.618033988749895, 0.0, 1.0, -1.618033988749895, 1.618033988749895, 0.0, -1.0, 1.618033988749895, 0.0, 1.0, -1.618033988749895, 0.0, -1.0, -1.618033988749895, 0.0, 1.0 }
    var ico_t: [60]u32 = [60]u32{ 0u32, 11u32, 5u32, 0u32, 5u32, 1u32, 0u32, 1u32, 7u32, 0u32, 7u32, 10u32, 0u32, 10u32, 11u32, 1u32, 5u32, 9u32, 5u32, 11u32, 4u32, 11u32, 10u32, 2u32, 10u32, 7u32, 6u32, 7u32, 1u32, 8u32, 3u32, 9u32, 4u32, 3u32, 4u32, 2u32, 3u32, 2u32, 6u32, 3u32, 6u32, 8u32, 3u32, 8u32, 9u32, 4u32, 9u32, 5u32, 2u32, 4u32, 11u32, 6u32, 2u32, 10u32, 8u32, 6u32, 7u32, 9u32, 8u32, 1u32 }
    var cube_v: [24]f64 = [24]f64{ 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0 }
    var cube_q: [24]u32 = [24]u32{ 0u32, 3u32, 2u32, 1u32, 4u32, 5u32, 6u32, 7u32, 0u32, 1u32, 5u32, 4u32, 3u32, 7u32, 6u32, 2u32, 0u32, 4u32, 7u32, 3u32, 1u32, 2u32, 6u32, 5u32 }
    var cube_t: [36]u32 = [36]u32{ 0u32, 3u32, 2u32, 0u32, 2u32, 1u32, 4u32, 5u32, 6u32, 4u32, 6u32, 7u32, 0u32, 1u32, 5u32, 0u32, 5u32, 4u32, 3u32, 7u32, 6u32, 3u32, 6u32, 2u32, 0u32, 4u32, 7u32, 0u32, 7u32, 3u32, 1u32, 2u32, 6u32, 1u32, 6u32, 5u32 }
    let (va, va_error) = mem.alloc[f64](a, 2000usize)
    if va_error != ok { ret va_error }
    let (vb, vb_error) = mem.alloc[f64](a, 2000usize)
    if vb_error != ok { ret vb_error }
    let (ta, ta_error) = mem.alloc[u32](a, 4000usize)
    if ta_error != ok { ret ta_error }
    let (tb, tb_error) = mem.alloc[u32](a, 4000usize)
    if tb_error != ok { ret tb_error }
    let (su, su_error) = mem.alloc[u32](a, 8000usize)
    if su_error != ok { ret su_error }
    let (sf, sf_error) = mem.alloc[f64](a, 40000usize)
    if sf_error != ok { ret sf_error }
    var he_v: [48]u32 = zero
    var he_t: [48]u32 = zero
    var he_n: [48]u32 = zero
    var he_f: [48]u32 = zero
    var he_s: [48]u32 = zero

    // 1: half edges of the cube (closed, 18 edges) and of two triangles (5 edges, open).
    let (cube_he, cube_he_error) = mesh.half_edge(cube_t[..], 3usize, he_v[..], he_t[..], he_n[..], he_f[..], he_s[..])
    var cube_he_var = cube_he
    if cube_he_error != ok || !mesh.is_closed(&cube_he_var) || mesh.number_edges(&cube_he_var, 0usize, su) != 18usize { os.exit(1i32) }
    var patch: [6]u32 = [6]u32{ 0u32, 1u32, 2u32, 0u32, 2u32, 3u32 }
    let (patch_he, patch_he_error) = mesh.half_edge(patch[..], 3usize, he_v[..], he_t[..], he_n[..], he_f[..], he_s[..])
    var patch_he_var = patch_he
    if patch_he_error != ok || mesh.is_closed(&patch_he_var) || mesh.number_edges(&patch_he_var, 0usize, su) != 5usize { os.exit(1i32) }
    if patch_he_var.twin[2usize] != 3u32 || patch_he_var.twin[3usize] != 2u32 || patch_he_var.twin[0usize] != 4294967295u32 { os.exit(1i32) }

    // 2: area-weighted normals of the icosahedron are radial.
    var normals: [36]f64 = zero
    if mesh.vertex_normals(ico_v[..], ico_t[..], normals[..]) != ok { os.exit(2i32) }
    var radial = 0.0f64
    var i = 0usize
    while i < 12usize {
        let norm = math.sqrt[f64](ico_v[3usize * i] * ico_v[3usize * i] + ico_v[3usize * i + 1usize] * ico_v[3usize * i + 1usize] + ico_v[3usize * i + 2usize] * ico_v[3usize * i + 2usize])
        radial += (normals[3usize * i] * ico_v[3usize * i] + normals[3usize * i + 1usize] * ico_v[3usize * i + 1usize] + normals[3usize * i + 2usize] * ico_v[3usize * i + 2usize]) / norm
        i += 1usize
    }
    if !near(radial, 12.0f64, 1.0e-9f64) { os.exit(2i32) }

    // 3: PCA normals of a 64-point sphere cloud agree with the radial direction (numpy: least 0.9867).
    var cloud: [192]f64 = zero
    var cloud_n: [192]f64 = zero
    var pca: [192]f64 = zero
    var near_i: [8]u32 = zero
    var near_d: [8]f64 = zero
    fibonacci(64usize, 2.0f64, cloud[..], cloud_n[..])
    if mesh.estimate_normals(cloud[..], 8usize, pca[..], near_i[..], near_d[..]) != ok { os.exit(3i32) }
    i = 0usize
    while i < 64usize {
        let d = pca[3usize * i] * cloud_n[3usize * i] + pca[3usize * i + 1usize] * cloud_n[3usize * i + 1usize] + pca[3usize * i + 2usize] * cloud_n[3usize * i + 2usize]
        if d < 0.95f64 { os.exit(3i32) }
        i += 1usize
    }

    // 4: Laplacian smoothing of icosphere(1) shrinks it, Taubin barely.
    let (n1, t1) = icosphere(1usize, ico_v[..], ico_t[..], va, ta, vb, tb, su)
    if n1 != 42usize || t1 != 80usize || !near(mesh.volume(va[..3usize * n1], ta[..3usize * t1]), 3.6587122085121533f64, 1.0e-9f64) { os.exit(4i32) }
    i = 0usize
    while i < 3usize * n1 {
        vb[i] = va[i]
        i += 1usize
    }
    if mesh.smooth_laplacian(vb[..3usize * n1], ta[..3usize * t1], 0.5f64, 5usize, sf) != ok { os.exit(4i32) }
    if !near(mesh.volume(vb[..3usize * n1], ta[..3usize * t1]), 0.9637901260748613f64, 1.0e-9f64) { os.exit(4i32) }
    i = 0usize
    while i < 3usize * n1 {
        vb[i] = va[i]
        i += 1usize
    }
    if mesh.smooth_taubin(vb[..3usize * n1], ta[..3usize * t1], 0.5f64, 0.0f64 - 0.53f64, 5usize, sf) != ok { os.exit(5i32) }
    if !near(mesh.volume(vb[..3usize * n1], ta[..3usize * t1]), 3.516694853167074f64, 1.0e-9f64) { os.exit(5i32) }

    // 6: Loop subdivision of the icosahedron twice: counts, closed, volumes.
    let (l1n, l1t, l1e) = mesh.subdivide_loop(ico_v[..], ico_t[..], va, ta, su)
    if l1e != ok || l1n != 42usize || l1t != 80usize || !near(mesh.volume(va[..3usize * l1n], ta[..3usize * l1t]), 11.44929424607288f64, 1.0e-9f64) { os.exit(6i32) }
    let (l2n, l2t, l2e) = mesh.subdivide_loop(va[..3usize * l1n], ta[..3usize * l1t], vb, tb, su)
    if l2e != ok || l2n != 162usize || l2t != 320usize || !near(mesh.volume(vb[..3usize * l2n], tb[..3usize * l2t]), 10.329454376453691f64, 1.0e-9f64) { os.exit(6i32) }
    let (l2he, l2he_error) = mesh.half_edge(tb[..3usize * l2t], 3usize, su[..960usize], su[960usize..1920usize], su[1920usize..2880usize], su[2880usize..3840usize], su[3840usize..4800usize])
    var l2he_var = l2he
    if l2he_error != ok || !mesh.is_closed(&l2he_var) { os.exit(6i32) }

    // 7: Catmull-Clark of the cube twice.
    let (c1n, c1q, c1e) = mesh.subdivide_catmull_clark(cube_v[..], cube_q[..], va, ta, su)
    if c1e != ok || c1n != 26usize || c1q != 24usize { os.exit(7i32) }
    let (c2n, c2q, c2e) = mesh.subdivide_catmull_clark(va[..3usize * c1n], ta[..4usize * c1q], vb, tb, su)
    if c2e != ok || c2n != 98usize || c2q != 96usize { os.exit(7i32) }
    i = 0usize
    while i < c2q {
        su[6usize * i] = tb[4usize * i]
        su[6usize * i + 1usize] = tb[4usize * i + 1usize]
        su[6usize * i + 2usize] = tb[4usize * i + 2usize]
        su[6usize * i + 3usize] = tb[4usize * i]
        su[6usize * i + 4usize] = tb[4usize * i + 2usize]
        su[6usize * i + 5usize] = tb[4usize * i + 3usize]
        i += 1usize
    }
    if !near(mesh.volume(vb[..3usize * c2n], su[..6usize * c2q]), 0.3501172059193886f64, 1.0e-9f64) { os.exit(7i32) }
    if !near(va[0usize], 0.2222222222222222f64, 1.0e-12f64) || !near(va[3usize * 14usize + 1usize], 0.5f64, 1.0e-12f64) { os.exit(7i32) }

    // 8: decimating icosphere(2) to 100 triangles keeps over 95% of its volume (Python: 96.5%;
    // the collapse order differs with the last bit of a cosine, so the exact volume is not compared).
    let (n2, t2) = icosphere(2usize, ico_v[..], ico_t[..], va, ta, vb, tb, su)
    if n2 != 162usize || t2 != 320usize || !near(mesh.volume(va[..3usize * n2], ta[..3usize * t2]), 4.0476811029937405f64, 1.0e-9f64) { os.exit(8i32) }
    i = 0usize
    while i < 3usize * n2 {
        vb[i] = va[i]
        i += 1usize
    }
    i = 0usize
    while i < 3usize * t2 {
        tb[i] = ta[i]
        i += 1usize
    }
    let (dn, dt, de) = mesh.decimate(vb[..3usize * n2], tb[..3usize * t2], 100usize, sf, su)
    if de != ok || dn != 52usize || dt != 100usize { os.exit(8i32) }
    let kept = mesh.volume(vb[..3usize * dn], tb[..3usize * dt]) / 4.0476811029937405f64
    if kept < 0.95f64 || kept > 1.0f64 { os.exit(8i32) }

    // 9: marching squares of a circle on a 12x12 grid: 30 segments.
    var field2: [144]f64 = zero
    i = 0usize
    while i < 144usize {
        let x = f64(i % 12usize) - 5.3f64
        let y = f64(i / 12usize) - 5.6f64
        field2[i] = math.sqrt[f64](x * x + y * y) - 3.7f64
        i += 1usize
    }
    let (segments, ms_error) = mesh.marching_squares(field2[..], 12usize, 12usize, 0.0f64, sf)
    if ms_error != ok || segments != 30usize || !near(checksum(sf[..4usize * segments]), 2578.982068018138f64, 1.0e-9f64) { os.exit(9i32) }

    // 10: marching cubes of a sphere on a 12^3 grid: 628 triangles (as scikit-image), volume near the sphere.
    let field3 = sf[20000usize..21728usize]
    i = 0usize
    while i < 1728usize {
        let x = f64(i % 12usize) - 5.4f64
        let y = f64((i / 12usize) % 12usize) - 5.5f64
        let z = f64(i / 144usize) - 5.6f64
        field3[i] = math.sqrt[f64](x * x + y * y + z * z) - 4.2f64
        i += 1usize
    }
    let (cubes, mc_error) = mesh.marching_cubes(field3, 12usize, 12usize, 12usize, 0.0f64, sf[..20000usize])
    if mc_error != ok || cubes != 628usize || !near(checksum(sf[..9usize * cubes]), 124416.81065634474f64, 1.0e-6f64) { os.exit(10i32) }
    if !near(mesh.soup_volume(sf[..9usize * cubes]), 300.0076258840889f64, 1.0e-9f64) { os.exit(10i32) }
    let (_, mc_room) = mesh.marching_cubes(field3, 12usize, 12usize, 12usize, 0.0f64, sf[..900usize])
    if mc_room != mesh.TooSmall { os.exit(10i32) }

    // 11: dual contouring of a sphere SDF over 8^3 cells: 228 vertices, 452 triangles, closed, volume near the sphere.
    var sphere = Sphere { cx: 0.05f64, cy: 0.1f64, cz: 0.0f64 - 0.05f64, r: 1.7f64 }
    let (dcn, dct, dce) = mesh.dual_contouring[Sphere](&sphere, sphere_sdf, 8usize, 8usize, 8usize, 0.0f64 - 2.0f64, 0.0f64 - 2.0f64, 0.0f64 - 2.0f64, 0.5f64, va, ta, sf, su)
    if dce != ok || dcn != 228usize || dct != 452usize { os.exit(11i32) }
    if !near(mesh.volume(va[..3usize * dcn], ta[..3usize * dct]), 20.74511014079695f64, 1.0e-9f64) || !near(checksum(va[..3usize * dcn]), 48.80292397812679f64, 1.0e-9f64) { os.exit(11i32) }
    let (dche, dche_error) = mesh.half_edge(ta[..3usize * dct], 3usize, su[..1356usize], su[1356usize..2712usize], su[2712usize..4068usize], su[4068usize..5424usize], su[5424usize..6780usize])
    var dche_var = dche
    if dche_error != ok || !mesh.is_closed(&dche_var) { os.exit(11i32) }

    // 12: signed distances to icosphere(2) against brute force with ray parity.
    let (s2n, s2t) = icosphere(2usize, ico_v[..], ico_t[..], va, ta, vb, tb, su)
    let sv = va[..3usize * s2n]
    let st = ta[..3usize * s2t]
    if !near(mesh.signed_distance(sv, st, 0.3f64, 0.2f64, 0.1f64), 0.0f64 - 0.6131547349865276f64, 1.0e-9f64) { os.exit(12i32) }
    if !near(mesh.signed_distance(sv, st, 1.5f64, 0.4f64, 0.0f64 - 0.2f64), 0.5664639268449272f64, 1.0e-9f64) { os.exit(12i32) }
    if !near(mesh.signed_distance(sv, st, 0.0f64, 0.0f64, 0.0f64), 0.0f64 - 0.9837419162223598f64, 1.0e-9f64) { os.exit(12i32) }
    if !near(mesh.signed_distance(sv, st, 0.0f64 - 0.9f64, 0.9f64, 0.9f64), 0.5746767063462012f64, 1.0e-9f64) { os.exit(12i32) }
    if !near(mesh.signed_distance(sv, st, 0.99f64, 0.0f64, 0.0f64), 0.0f64 - 0.009837419162223476f64, 1.0e-9f64) { os.exit(12i32) }

    // 13: fast marching on icosphere(3): mean error 1.7%, worst 5.5% against great circles.
    let (s3n, s3t) = icosphere(3usize, ico_v[..], ico_t[..], va, ta, vb, tb, su)
    if s3n != 642usize || s3t != 1280usize { os.exit(13i32) }
    var state: [642]u8 = zero
    let distance = sf[..642usize]
    if mesh.geodesic_fast_marching(va[..3usize * s3n], ta[..3usize * s3t], 0u32, distance, state[..]) != ok { os.exit(13i32) }
    var total = 0.0f64
    i = 0usize
    while i < s3n {
        total += distance[i]
        i += 1usize
    }
    if !near(total, 1022.9434407705775f64, 1.0e-6f64) { os.exit(13i32) }
    let (fm_mean, fm_worst) = geodesic_error(va, s3n, distance)
    if fm_mean > 0.03f64 || fm_worst > 0.07f64 { os.exit(13i32) }

    // 14: the heat method on icosphere(3): mean error 1.5%, worst 3.5%.
    if mesh.geodesic_heat(va[..3usize * s3n], ta[..3usize * s3t], 0u32, 300usize, distance, sf[1000usize..20000usize]) != ok { os.exit(14i32) }
    total = 0.0f64
    i = 0usize
    while i < s3n {
        total += distance[i]
        i += 1usize
    }
    if !near(total, 994.7893969321409f64, 1.0e-6f64) { os.exit(14i32) }
    let (heat_mean, heat_worst) = geodesic_error(va, s3n, distance)
    if heat_mean > 0.03f64 || heat_worst > 0.05f64 { os.exit(14i32) }

    // 15: LSCM of a flat 4x4 grid with vertex 0 at (0, 0) and 3 at (1, 0) is (x/3, y/3).
    var grid_v: [48]f64 = zero
    var grid_t: [54]u32 = zero
    i = 0usize
    while i < 16usize {
        grid_v[3usize * i] = f64(i % 4usize)
        grid_v[3usize * i + 1usize] = f64(i / 4usize)
        i += 1usize
    }
    i = 0usize
    while i < 9usize {
        let corner = u32((i / 3usize) * 4usize + i % 3usize)
        grid_t[6usize * i] = corner
        grid_t[6usize * i + 1usize] = corner + 1u32
        grid_t[6usize * i + 2usize] = corner + 5u32
        grid_t[6usize * i + 3usize] = corner
        grid_t[6usize * i + 4usize] = corner + 5u32
        grid_t[6usize * i + 5usize] = corner + 4u32
        i += 1usize
    }
    var uv: [32]f64 = zero
    if mesh.parameterize_lscm(grid_v[..], grid_t[..], 0u32, 3u32, 200usize, uv[..], sf) != ok { os.exit(15i32) }
    i = 0usize
    while i < 16usize {
        if !near(uv[2usize * i], grid_v[3usize * i] / 3.0f64, 1.0e-9f64) || !near(uv[2usize * i + 1usize], grid_v[3usize * i + 1usize] / 3.0f64, 1.0e-9f64) { os.exit(15i32) }
        i += 1usize
    }

    // 16: ball pivoting over a 60-point sphere cloud closes it with 116 triangles.
    fibonacci(60usize, 1.0f64, cloud[..180usize], cloud_n[..180usize])
    let (bp_count, bp_error) = mesh.reconstruct_ball_pivot(cloud[..180usize], cloud_n[..180usize], 0.45f64, tb, su)
    if bp_error != ok || bp_count != 116usize || !near(mesh.volume(cloud[..180usize], tb[..3usize * bp_count]), 3.7934479238561973f64, 1.0e-9f64) { os.exit(16i32) }
    let (bphe, bphe_error) = mesh.half_edge(tb[..3usize * bp_count], 3usize, su[..348usize], su[348usize..696usize], su[696usize..1044usize], su[1044usize..1392usize], su[1392usize..1740usize])
    var bphe_var = bphe
    if bphe_error != ok || !mesh.is_closed(&bphe_var) { os.exit(16i32) }

    // 17: the Poisson field of a 300-point sphere cloud contours to 1008 triangles with the sphere's volume.
    fibonacci(300usize, 1.5f64, va[..900usize], vb[..900usize])
    let pfield = sf[..4096usize]
    let (iso, poisson_error) = mesh.reconstruct_poisson(va[..900usize], vb[..900usize], 16usize, 16usize, 16usize, 0.0f64 - 2.4f64, 0.0f64 - 2.4f64, 0.0f64 - 2.4f64, 0.3f64, 150usize, pfield, sf[4096usize..20480usize])
    if poisson_error != ok || !near(iso, 0.0f64 - 0.12353396381600085f64, 1.0e-9f64) { os.exit(17i32) }
    let (pcount, pmc_error) = mesh.marching_cubes(pfield, 16usize, 16usize, 16usize, iso, sf[20480usize..])
    if pmc_error != ok || pcount != 1008usize { os.exit(17i32) }
    if !near(mesh.soup_volume(sf[20480usize..20480usize + 9usize * pcount]) * 0.027f64, 14.243801611593764f64, 1.0e-6f64) { os.exit(17i32) }

    // 18: csg.js booleans of two unit cubes offset by half: 1.5, 0.5, 0.5.
    let (pool_t, pool_t_error) = mem.alloc[f64](a, 27000usize)
    if pool_t_error != ok { ret pool_t_error }
    let (pool_p, pool_p_error) = mem.alloc[f64](a, 12000usize)
    if pool_p_error != ok { ret pool_p_error }
    let (pool_l, pool_l_error) = mem.alloc[u32](a, 3000usize)
    if pool_l_error != ok { ret pool_l_error }
    let (node_p, node_p_error) = mem.alloc[f64](a, 2000usize)
    if node_p_error != ok { ret node_p_error }
    let (node_l, node_l_error) = mem.alloc[u32](a, 1500usize)
    if node_l_error != ok { ret node_l_error }
    var pool = mesh.csg(pool_t, pool_p, pool_l, node_p, node_l[..500usize], node_l[500usize..1000usize], node_l[1000usize..])
    var cube_b: [24]f64 = zero
    i = 0usize
    while i < 24usize {
        cube_b[i] = cube_v[i]
        if i % 3usize == 0usize { cube_b[i] += 0.5f64 }
        i += 1usize
    }
    let (union_count, union_error) = mesh.boolean_bsp(&pool, cube_v[..], cube_t[..], cube_b[..], cube_t[..], .Union, sf)
    if union_error != ok || !near(mesh.soup_volume(sf[..9usize * union_count]), 1.5f64, 1.0e-9f64) { os.exit(18i32) }
    let (inter_count, inter_error) = mesh.boolean_bsp(&pool, cube_v[..], cube_t[..], cube_b[..], cube_t[..], .Intersection, sf)
    if inter_error != ok || !near(mesh.soup_volume(sf[..9usize * inter_count]), 0.5f64, 1.0e-9f64) { os.exit(18i32) }
    let (diff_count, diff_error) = mesh.boolean_bsp(&pool, cube_v[..], cube_t[..], cube_b[..], cube_t[..], .Difference, sf)
    if diff_error != ok || !near(mesh.soup_volume(sf[..9usize * diff_count]), 0.5f64, 1.0e-9f64) { os.exit(18i32) }

    // 19: a closed cylinder profile revolved in 24 segments.
    var profile: [8]f64 = [8]f64{ 0.0, 0.0, 1.0, 0.0, 1.0, 2.0, 0.0, 2.0 }
    let (rn, rt, re) = mesh.revolve(profile[..], 24usize, va, ta)
    if re != ok || rn != 96usize || rt != 144usize || !near(mesh.volume(va[..3usize * rn], ta[..3usize * rt]), 6.211657082460498f64, 1.0e-9f64) { os.exit(19i32) }

    try io.print("gfx mesh ok\n")
    ret ok
}
