// `e.gfx.scene`'s 3-D techniques: the triangle rasterizer, the painter's order,
// deferred shading, clustered lights, shadow cascades, PCF, SSAO, SSR, TAA, FXAA,
// depth peeling, SDF sphere tracing and volumetric fog, each over 16x16 LCG inputs
// and compared as a weighted fold against scratchpad/gfx_scene_plan/ref.py.

use e.gfx.scene
use e.io
use e.math
use e.mem
use e.os

type Gen = struct { state: u64 }
type Sdf = struct { cx: f32, cy: f32, cz: f32, r: f32 }

fn rnd(g: *Gen, lo: f32, span: f32) -> f32 {
    g.state = g.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret lo + span * (f32(g.state >> 41u32) / 8388608.0)
}

fn floats(a: *mem.Arena, n: usize, v: f32) -> []f32 {
    let (b, e) = mem.alloc[f32](a, n)
    if e != ok { os.exit(99i32) }
    var i = 0usize
    while i < n {
        b[i] = v
        i += 1usize
    }
    ret b
}

fn fill(a: *mem.Arena, g: *Gen, n: usize) -> []f32 {
    let b = floats(a, n, 0.0)
    var i = 0usize
    while i < n {
        b[i] = rnd(g, -1.0, 2.0)
        i += 1usize
    }
    ret b
}

fn half_unit(v: f32) -> f32 { ret (v + 1.0) * 0.5 }

// A vertex array of `stride` floats: x, y doubled, z into 0..1, w into 1..3, and
// the attributes `from..to` into 0..1.
fn shape_vertices(tris: []f32, stride: usize, from: usize, to: usize) {
    var v = 0usize
    while v < tris.len {
        tris[v] = tris[v] * 2.0
        tris[v + 1usize] = tris[v + 1usize] * 2.0
        tris[v + 2usize] = half_unit(tris[v + 2usize])
        tris[v + 3usize] = tris[v + 3usize] + 2.0
        var c = from
        while c < to {
            tris[v + c] = half_unit(tris[v + c])
            c += 1usize
        }
        v += stride
    }
}

fn fold(buf: []const f32) -> f64 {
    var s: f64 = 0.0
    var i = 0usize
    while i < buf.len {
        s = s + f64(buf[i]) * f64((i % 7usize) + 1usize)
        i += 1usize
    }
    ret s
}

fn check(n: i32, got: f64, want: f64) {
    let d = math.abs[f64](got - want)
    if !(d <= 0.0001 * (1.0 + math.abs[f64](want))) { os.exit(n) }
}

fn sphere_plane(s: *Sdf, x: f32, y: f32, z: f32) -> f32 {
    let dx = x - s.cx
    let dy = y - s.cy
    let dz = z - s.cz
    ret math.min[f32](math.sqrt[f32](dx * dx + dy * dy + dz * dz) - s.r, y + 1.0)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let w = 16usize
    let n = 256usize
    // 1: the rasterizer, back faces culled.
    var g = Gen { state: 1001u64 }
    let tris1 = fill(a, &g, 126usize)
    shape_vertices(tris1, 7usize, 4usize, 7usize)
    let depth1 = floats(a, n, 1.0)
    let color1 = floats(a, n * 3usize, 0.0)
    if scene.rasterize(tris1, w, w, depth1, color1, true) != ok { os.exit(1i32) }
    check(1i32, fold(color1), 76.07383179569838)
    check(1i32, fold(depth1), 984.909944572505)
    // 2: the painter's order.
    g = Gen { state: 1002u64 }
    let centres = fill(a, &g, 24usize)
    let view = fill(a, &g, 16usize)
    let (order, order_error) = mem.alloc[u32](a, 8usize)
    if order_error != ok { os.exit(99i32) }
    let depths = floats(a, 8usize, 0.0)
    if scene.paint_order(centres, view, order, depths) != ok { os.exit(2i32) }
    var h = 0u64
    var i = 0usize
    while i < 8usize {
        h = h + u64(order[i]) * (1u64 << u32(3usize * i))
        i += 1usize
    }
    if h != 875833u64 { os.exit(2i32) }
    // 3: deferred shading.
    g = Gen { state: 1003u64 }
    let tris3 = fill(a, &g, 180usize)
    shape_vertices(tris3, 15usize, 7usize, 10usize)
    var v = 0usize
    while v < 180usize {
        tris3[v + 13usize] = half_unit(tris3[v + 13usize])
        tris3[v + 14usize] = (tris3[v + 14usize] + 1.0) * 16.0 + 4.0
        v += 15usize
    }
    let lights3 = fill(a, &g, 12usize)
    var l = 0usize
    while l < 12usize {
        lights3[l + 3usize] = half_unit(lights3[l + 3usize])
        lights3[l + 4usize] = half_unit(lights3[l + 4usize])
        lights3[l + 5usize] = half_unit(lights3[l + 5usize])
        l += 6usize
    }
    let depth3 = floats(a, n, 1.0)
    let gbuffer = floats(a, n * 11usize, 0.0)
    let color3 = floats(a, n * 3usize, 0.0)
    var eye = [3]f32{ 0.0, 0.0, 3.0 }
    if scene.deferred(tris3, w, w, depth3, gbuffer, lights3, eye[0..], 0.125, color3, false) != ok { os.exit(3i32) }
    check(3i32, fold(color3), 199.02229964643348)
    // 4: clustered lights.
    g = Gen { state: 1004u64 }
    let lights4 = fill(a, &g, 48usize)
    l = 0usize
    while l < 48usize {
        lights4[l] = lights4[l] * 4.0
        lights4[l + 1usize] = lights4[l + 1usize] * 4.0
        lights4[l + 2usize] = lights4[l + 2usize] * 4.0 - 4.5
        lights4[l + 3usize] = lights4[l + 3usize] + 1.5
        l += 4usize
    }
    let (counts, counts_error) = mem.alloc[u32](a, 64usize)
    let (lists, lists_error) = mem.alloc[u32](a, 768usize)
    if counts_error != ok || lists_error != ok { os.exit(99i32) }
    if scene.clustered_lights(1.0, 1.0, 0.5, 8.0, 4usize, 4usize, 4usize, lights4, 12usize, counts, lists) != ok { os.exit(4i32) }
    h = 0u64
    var c = 0usize
    while c < 64usize {
        h = h *% 31u64 +% u64(counts[c])
        var k = 0usize
        while k < usize(counts[c]) {
            h = h *% 31u64 +% u64(lists[c * 12usize + k])
            k += 1usize
        }
        c += 1usize
    }
    if h != 16978770349483659149u64 { os.exit(4i32) }
    // 5: shadow cascades.
    g = Gen { state: 1005u64 }
    let cam = fill(a, &g, 16usize)
    cam[12] = 0.0
    cam[13] = 0.0
    cam[14] = 0.0
    cam[15] = 1.0
    let light_dir = fill(a, &g, 3usize)
    let splits = floats(a, 4usize, 0.0)
    let matrices = floats(a, 48usize, 0.0)
    if scene.shadow_cascades(0.5, 32.5, 0.75, cam, 1.0, 1.0, light_dir, splits, matrices) != ok { os.exit(5i32) }
    check(5i32, fold(splits), 173.66089273127938)
    check(5i32, fold(matrices), 20.97092664266637)
    // 6: percentage-closer filtering.
    g = Gen { state: 1006u64 }
    let smap = fill(a, &g, 64usize)
    let frags = fill(a, &g, 96usize)
    i = 0usize
    while i < 96usize {
        if i < 64usize { smap[i] = half_unit(smap[i]) }
        frags[i] = half_unit(frags[i])
        i += 1usize
    }
    let pcf = floats(a, 32usize, 0.0)
    if scene.shadow_pcf(smap, 8usize, 8usize, frags, 3usize, 0.0078125, pcf) != ok { os.exit(6i32) }
    check(6i32, fold(pcf), 68.33333333333331)
    // 7: SSAO over view-space positions and normals.
    g = Gen { state: 1007u64 }
    let positions = fill(a, &g, n * 3usize)
    var p = 0usize
    while p < n * 3usize {
        positions[p] = positions[p] * 2.0
        positions[p + 1usize] = positions[p + 1usize] * 2.0
        positions[p + 2usize] = positions[p + 2usize] * 4.0 - 4.5
        p += 3usize
    }
    let normals = fill(a, &g, n * 3usize)
    let kernel = fill(a, &g, 24usize)
    i = 2usize
    while i < 24usize {
        kernel[i] = half_unit(kernel[i])
        i += 3usize
    }
    let noise = fill(a, &g, 48usize)
    i = 2usize
    while i < 48usize {
        noise[i] = 0.0
        i += 3usize
    }
    var proj = [16]f32{ 2.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 0.0, -1.125, -1.0625, 0.0, 0.0, -1.0, 0.0 }
    let ao = floats(a, n, 0.0)
    let scratch = floats(a, n, 0.0)
    if scene.ssao(positions, normals, w, w, kernel, noise, proj[0..], 0.5, 0.03125, ao, scratch) != ok { os.exit(7i32) }
    check(7i32, fold(ao), 857.8436756753097)
    // 8: SSR over the same buffers.
    let hit_uv = floats(a, n * 2usize, 0.0)
    let mask = floats(a, n, 0.0)
    if scene.ssr(positions, normals, w, w, proj[0..], 0.25, 16usize, 0.5, 4usize, hit_uv, mask) != ok { os.exit(8i32) }
    check(8i32, fold(hit_uv), 4062.7933948466894)
    check(8i32, fold(mask), 268.0)
    // 9: TAA.
    g = Gen { state: 1009u64 }
    let current = fill(a, &g, n * 3usize)
    let history = fill(a, &g, n * 3usize)
    i = 0usize
    while i < n * 3usize {
        current[i] = half_unit(current[i])
        history[i] = half_unit(history[i])
        i += 1usize
    }
    let depth9 = fill(a, &g, n)
    let inv_vp = fill(a, &g, 16usize)
    let prev_vp = fill(a, &g, 16usize)
    let resolved = floats(a, n * 3usize, 0.0)
    if scene.taa(current, history, depth9, w, w, inv_vp, prev_vp, 0.125, resolved) != ok { os.exit(9i32) }
    check(9i32, fold(resolved), 1432.3602119044792)
    // 10: FXAA over a two-tone image with a diagonal and noise.
    g = Gen { state: 1010u64 }
    let rgb = fill(a, &g, n * 3usize)
    var y = 0usize
    while y < w {
        var x = 0usize
        while x < w {
            var base: f32 = 0.25
            if x >= 8usize { base = 0.75 }
            if x + y < 10usize { base = base + 0.125 }
            c = 0usize
            while c < 3usize {
                rgb[(y * w + x) * 3usize + c] = base + rgb[(y * w + x) * 3usize + c] * 0.125
                c += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    let luma = floats(a, n, 0.0)
    let filtered = floats(a, n * 3usize, 0.0)
    if scene.fxaa(rgb, w, w, luma, filtered) != ok { os.exit(10i32) }
    check(10i32, fold(filtered), 1631.5890601876765)
    // 11: depth peeling, three layers.
    g = Gen { state: 1011u64 }
    let tris11 = fill(a, &g, 120usize)
    shape_vertices(tris11, 8usize, 4usize, 8usize)
    let depth_a = floats(a, n, 0.0)
    let depth_b = floats(a, n, 0.0)
    let layer_color = floats(a, n * 4usize, 0.0)
    let peeled = floats(a, n * 4usize, 0.0)
    if scene.depth_peel(tris11, w, w, 3usize, depth_a, depth_b, layer_color, peeled) != ok { os.exit(11i32) }
    check(11i32, fold(peeled), 640.0625286821903)
    // 12: sphere tracing a sphere over a plane.
    var field = Sdf { cx: 0.25, cy: -0.25, cz: -3.0, r: 1.0 }
    var origin = [3]f32{ 0.0, 0.0, 0.0 }
    let hits = floats(a, n, 0.0)
    let hit_normals = floats(a, n * 3usize, 0.0)
    if scene.sdf_raymarch[Sdf](&field, sphere_plane, w, w, origin[0..], 1.0, 1.0, 48usize, 0.0078125, 16.0, hits, hit_normals) != ok { os.exit(12i32) }
    check(12i32, fold(hits), 838.8441820116344)
    check(12i32, fold(hit_normals), 500.18144932677444)
    // 13: volumetric fog along the SSAO positions.
    var light = [6]f32{ 1.0, 2.0, -3.0, 1.0, 0.5, 0.25 }
    let fog = floats(a, n * 3usize, 0.0)
    let transmittance = floats(a, n, 0.0)
    if scene.volumetric_fog(positions, w, w, 8usize, 0.25, 0.5, light[0..], 0.5, fog, transmittance) != ok { os.exit(13i32) }
    check(13i32, fold(fog), 5.483224175602928)
    check(13i32, fold(transmittance), 360.7998968293218)
    try io.print("gfx scene plan ok\n")
    ret ok
}
