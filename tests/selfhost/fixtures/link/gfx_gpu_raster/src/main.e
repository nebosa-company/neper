// The tile rasteriser (D5929) against the CPU rasteriser on the same scenes: a gradient page, solid and fractional rectangles, a
// filled circle, a stroked ring, a rounded clip over a radial gradient, an opacity layer and an image, 640 x 480. The rasteriser
// runs on the CPU device (the kernel's CPU build, so every host checks the kernel's logic) and on every Vulkan device the host
// has; a Vulkan device whose self-test refuses it (the RTX 3080 draws images as nothing, D5950) is skipped and reported. Per
// channel the two may differ by 2 levels (float rounding of the box filter); the test also wants no differing pixel at all.


use e.mem
use e.gpu
use e.io
use e.str
use e.time
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.image
use e.gfx.gpuraster



fn stops3(a: *mem.Arena, c0: paint.Color, c1: paint.Color) -> []paint.Stop {
    let (s, e) = mem.alloc[paint.Stop](a, 3usize)
    s[0usize] = paint.Stop { offset: 0.0, color: c0 }
    s[1usize] = paint.Stop { offset: 0.5, color: paint.rgba(0.6, 0.2, 0.5, 1.0) }
    s[2usize] = paint.Stop { offset: 1.0, color: c1 }
    ret s
}

fn circle_path(a: *mem.Arena, cx: f32, cy: f32, r: f32) -> geometry.Path {
    let (verbs, e1) = mem.alloc[geometry.PathVerb](a, 6usize)
    let (points, e2) = mem.alloc[geometry.Point](a, 13usize)
    let k: f32 = 0.5522848 * r
    verbs[0usize] = .Move
    verbs[1usize] = .Cubic
    verbs[2usize] = .Cubic
    verbs[3usize] = .Cubic
    verbs[4usize] = .Cubic
    verbs[5usize] = .Close
    points[0usize] = geometry.Point { x: cx + r, y: cy }
    points[1usize] = geometry.Point { x: cx + r, y: cy + k }
    points[2usize] = geometry.Point { x: cx + k, y: cy + r }
    points[3usize] = geometry.Point { x: cx, y: cy + r }
    points[4usize] = geometry.Point { x: cx - k, y: cy + r }
    points[5usize] = geometry.Point { x: cx - r, y: cy + k }
    points[6usize] = geometry.Point { x: cx - r, y: cy }
    points[7usize] = geometry.Point { x: cx - r, y: cy - k }
    points[8usize] = geometry.Point { x: cx - k, y: cy - r }
    points[9usize] = geometry.Point { x: cx, y: cy - r }
    points[10usize] = geometry.Point { x: cx + k, y: cy - r }
    points[11usize] = geometry.Point { x: cx + r, y: cy - k }
    points[12usize] = geometry.Point { x: cx + r, y: cy }
    ret geometry.Path { verbs: verbs, points: points }
}

fn rect_cmd(x: f32, y: f32, w: f32, h: f32, brush: paint.Brush) -> scene.Command {
    ret scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: x, y: y, width: w, height: h }, brush: brush } }
}

fn solid(r: f32, g: f32, b: f32, a: f32) -> paint.Brush {
    ret paint.Brush { Solid: paint.rgba(r, g, b, a) }
}

// Scene `variant` over a gradient page: 0 a SLUST-like mix, 1 the same plus a small rectangle, 2 the page alone, 3 a solid
// rectangle, 4 a filled circle, 5 a stroked ring, 6 a rounded clip with a gradient panel, 7 an opacity layer, 8 an image.
fn build_scene(a: *mem.Arena, r: *scene.Renderer, w: f32, h: f32, variant: u32, tex: scene.TextureId) -> (scene.SceneId, err) {
    let (b, be) = scene.builder(a, 256usize)
    var bb = b
    var save: scene.Command = .Save
    var restore: scene.Command = .Restore
    let bg = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 0.0, y: 0.0 }, end: geometry.Point { x: w * 0.3, y: h }, stops: stops3(a, paint.rgba(0.10, 0.02, 0.12, 1.0), paint.rgba(0.02, 0.0, 0.05, 1.0)) } }
    if variant != 9u32 { try scene.push(&bb, rect_cmd(0.0, 0.0, w, h, bg)) }
    if variant == 10u32 { try scene.push(&bb, rect_cmd(0.0, 0.0, w, h, solid(0.2, 0.1, 0.3, 1.0))) }
    let panel = paint.Brush { Radial: paint.RadialGradient { center: geometry.Point { x: 240.0, y: 230.0 }, radius: 260.0, stops: stops3(a, paint.rgba(0.9, 0.2, 0.5, 1.0), paint.rgba(0.2, 0.05, 0.3, 1.0)) } }
    let rr = scene.Clip { Rounded: geometry.RRect { rect: geometry.Rect { x: 60.0, y: 120.0, width: 360.0, height: 220.0 }, top_left: geometry.Radius { x: 24.0, y: 24.0 }, top_right: geometry.Radius { x: 24.0, y: 24.0 }, bottom_right: geometry.Radius { x: 24.0, y: 24.0 }, bottom_left: geometry.Radius { x: 24.0, y: 24.0 } } }
    let ring = scene.Command { StrokePath: scene.StrokePath { path: circle_path(a, 600.0, 200.0, 90.0), brush: solid(1.0, 0.9, 0.5, 1.0), stroke: paint.Stroke { width: 3.5, cap: .Round, join: .Round, miter_limit: 4.0 } } }
    let picture = scene.Command { Image: scene.DrawImage { texture: tex, source: geometry.Rect { x: 0.0, y: 0.0, width: 8.0, height: 8.0 }, destination: geometry.Rect { x: 560.0, y: 400.0, width: 160.0, height: 120.0 }, opacity: 0.9 } }
    if variant == 0u32 || variant == 1u32 {
        try scene.push(&bb, rect_cmd(40.5, 30.25, 300.0, 60.5, solid(0.9, 0.7, 0.3, 0.8)))
        try scene.push(&bb, save)
        try scene.push(&bb, scene.Command { Clip: rr })
        try scene.push(&bb, rect_cmd(50.0, 110.0, 400.0, 260.0, panel))
        try scene.push(&bb, scene.Command { FillPath: scene.FillPath { path: circle_path(a, 150.0, 200.0, 40.0), brush: solid(1.0, 1.0, 1.0, 0.5) } })
        try scene.push(&bb, restore)
        try scene.push(&bb, scene.Command { FillPath: scene.FillPath { path: circle_path(a, 600.0, 200.0, 77.3), brush: solid(0.2, 0.8, 0.9, 1.0) } })
        try scene.push(&bb, ring)
        try scene.push(&bb, scene.Command { OpacityLayer: scene.OpacityLayer { bounds: geometry.Rect { x: 100.0, y: 380.0, width: 400.0, height: 200.0 }, opacity: 0.6 } })
        try scene.push(&bb, rect_cmd(120.0, 400.0, 200.0, 120.0, solid(1.0, 0.3, 0.3, 1.0)))
        try scene.push(&bb, scene.Command { FillPath: scene.FillPath { path: circle_path(a, 300.0, 480.0, 70.0), brush: solid(0.3, 0.3, 1.0, 1.0) } })
        try scene.push(&bb, restore)
        try scene.push(&bb, picture)
        if variant == 1u32 { try scene.push(&bb, rect_cmd(700.0, 560.0, 60.0, 60.0, solid(1.0, 1.0, 0.0, 1.0))) }
    }
    if variant == 3u32 { try scene.push(&bb, rect_cmd(100.25, 100.5, 500.0, 300.0, solid(0.3, 0.2, 0.6, 1.0))) }
    if variant == 4u32 { try scene.push(&bb, scene.Command { FillPath: scene.FillPath { path: circle_path(a, 600.0, 200.0, 77.3), brush: solid(0.2, 0.8, 0.9, 1.0) } }) }
    if variant == 5u32 { try scene.push(&bb, ring) }
    if variant == 6u32 {
        try scene.push(&bb, save)
        try scene.push(&bb, scene.Command { Clip: rr })
        try scene.push(&bb, rect_cmd(50.0, 110.0, 400.0, 260.0, panel))
        try scene.push(&bb, restore)
    }
    if variant == 7u32 {
        try scene.push(&bb, scene.Command { OpacityLayer: scene.OpacityLayer { bounds: geometry.Rect { x: 100.0, y: 380.0, width: 400.0, height: 200.0 }, opacity: 0.6 } })
        try scene.push(&bb, rect_cmd(120.0, 400.0, 200.0, 120.0, solid(1.0, 0.3, 0.3, 1.0)))
        try scene.push(&bb, restore)
    }
    if variant == 8u32 || variant == 9u32 || variant == 10u32 { try scene.push(&bb, picture) }
    let list = scene.finish(&bb)
    let (id, ce) = scene.compile(r, list)
    if ce != ok { ret (zero, ce) }
    ret (id, ok)
}

// An 8 x 8 checker image with alpha, uploaded to `r`.
fn make_texture(a: *mem.Arena, r: *scene.Renderer) -> (scene.TextureId, err) {
    let (px, pe) = mem.alloc[u8](a, 8usize * 8usize * 4usize)
    var y = 0usize
    while y < 8usize {
        var x = 0usize
        while x < 8usize {
            let at = (y * 8usize + x) * 4usize
            var on = 0u8
            if (x + y) % 2usize == 0usize { on = 255u8 }
            px[at] = on
            px[at + 1usize] = u8(x * 32usize)
            px[at + 2usize] = u8(y * 32usize)
            px[at + 3usize] = u8(128usize + x * 16usize)
            x += 1usize
        }
        y += 1usize
    }
    let view = image.ConstImage { pixels: px, width: 8u32, height: 8u32, stride: 32usize, format: .Rgba8, alpha: .Straight }
    let (tid, terr) = scene.upload_image(r, view)
    ret (tid, terr)
}


fn say(a: *mem.Arena, tag: str, v: u64) {
    let (sb, sbe) = str.builder(a, 200usize)
    var so = sb
    let e1 = str.push(&so, tag)
    let e2 = str.push(&so, "=")
    let e3 = str.push_u64(&so, v)
    let e4 = str.push(&so, " ")
    let pr = io.print(str.done(&so))
}

// Compares the rasteriser on `device` with the CPU renderer over every scene; the worst channel difference and the count of
// pixels more than 2 levels apart. `Refused` is answered as `skipped`.
fn compare(a: *mem.Arena, device: *gpu.Device, cdev: *gpu.Device, w: u32, h: u32) -> (u32, usize, bool, err) {
    let (cq, cqe) = gpu.queue(cdev)
    if cqe != ok { ret (0u32, 0usize, false, cqe) }
    let (vq, vqe) = gpu.queue(device)
    if vqe != ok { ret (0u32, 0usize, false, vqe) }
    var (cr, cre) = scene.renderer(a, cdev, cq, 4u32, 16u32)
    if cre != ok { ret (0u32, 0usize, false, cre) }
    var (vr, vre) = scene.renderer(a, device, vq, 4u32, 16u32)
    if vre != ok { ret (0u32, 0usize, false, vre) }
    let (gr, gre) = gpuraster.install(&vr, a, vq, 16usize, false)
    if gre == gpuraster.Refused { ret (0u32, 0usize, true, ok) }
    if gre != ok { ret (0u32, 0usize, false, gre) }
    let (ct, cte) = gpu.open_target(cq, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, w, h, .Bgra8)
    if cte != ok { ret (0u32, 0usize, false, cte) }
    let (vt, vte) = gpu.open_target(vq, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, w, h, .Bgra8)
    if vte != ok { ret (0u32, 0usize, false, vte) }
    let (cdraw, cde) = scene.target_of(a, ct)
    if cde != ok { ret (0u32, 0usize, false, cde) }
    let (vdraw, vde) = scene.target_of(a, vt)
    if vde != ok { ret (0u32, 0usize, false, vde) }
    let (ctex, cte2) = make_texture(a, &cr)
    if cte2 != ok { ret (0u32, 0usize, false, cte2) }
    let (vtex, vte2) = make_texture(a, &vr)
    if vte2 != ok { ret (0u32, 0usize, false, vte2) }
    let (cpx, e1) = mem.alloc[u32](a, usize(w) * usize(h))
    let (vpx, e2) = mem.alloc[u32](a, usize(w) * usize(h))
    var worst_all = 0u32
    var bad_all = 0usize
    var prev_c: scene.SceneId = zero
    var prev_v: scene.SceneId = zero
    var variant = 0u32
    while variant < 9u32 {
        let (cs, cse) = build_scene(a, &cr, f32(w), f32(h), variant, ctex)
        if cse != ok { ret (0u32, 0usize, false, cse) }
        let (vs, vse) = build_scene(a, &vr, f32(w), f32(h), variant, vtex)
        if vse != ok { ret (0u32, 0usize, false, vse) }
        let size = geometry.Size { width: f32(w), height: f32(h) }
        let ce1 = scene.render_scaled(&cr, cs, cdraw, size, 1.0)
        if ce1 != ok { ret (0u32, 0usize, false, ce1) }
        let ve1 = scene.render_scaled(&vr, vs, vdraw, size, 1.0)
        if ve1 != ok { ret (0u32, 0usize, false, ve1) }
        if variant > 0u32 {
            let r1 = scene.release_scene(&cr, prev_c)
            let r2 = scene.release_scene(&vr, prev_v)
        }
        prev_c = cs
        prev_v = vs
        let (cimg, cie) = gpu.presented(ct)
        if cie != ok { ret (0u32, 0usize, false, cie) }
        let (vimg, vie) = gpu.presented(vt)
        if vie != ok { ret (0u32, 0usize, false, vie) }
        let rc = gpu.read_image(cq, cimg, cpx)
        if rc != ok { ret (0u32, 0usize, false, rc) }
        let rv = gpu.read_image(vq, vimg, vpx)
        if rv != ok { ret (0u32, 0usize, false, rv) }
        var i = 0usize
        while i < cpx.len {
            var ch = 0u32
            var over = false
            while ch < 4u32 {
                let x = (cpx[i] >> (ch * 8u32)) & 255u32
                let y = (vpx[i] >> (ch * 8u32)) & 255u32
                var d = x
                if y > x { d = y - x } else { d = x - y }
                if y > x { d = y - x }
                if d > worst_all { worst_all = d }
                if d > 2u32 { over = true }
                ch += 1u32
            }
            if over { bad_all += 1usize }
            i += 1usize
        }
        variant += 1u32
    }
    // Every scene was drawn by the rasteriser, none handed back.
    let (drawn, handed_back, enc, lau, ents, eds, tls) = gpuraster.counts(&vr, gr)
    if handed_back != 0u64 || drawn == 0u64 { ret (worst_all, bad_all + 1000000usize, false, ok) }
    ret (worst_all, bad_all, false, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let w = 640u32
    let h = 480u32
    let (cdev, ce) = gpu.open(a, .Cpu, 0u32)
    if ce != ok { os.exit(10i32) }
    // The rasteriser's kernel run by the CPU build, against the CPU renderer.
    let (kdev, ke) = gpu.open(a, .Cpu, 0u32)
    if ke != ok { os.exit(11i32) }
    let (worst, bad, skipped, cmp_error) = compare(a, kdev, cdev, w, h)
    if cmp_error != ok { os.exit(12i32) }
    let dbg1 = io.print("cpu-kernel compare: ")
    say(a, "worst", u64(worst))
    say(a, "bad", u64(bad))
    if skipped { say(a, "skipped_at_step", u64(gpuraster.refusal())) }
    if skipped || worst > 2u32 || bad != 0usize { os.exit(13i32) }
    // Every Vulkan device the host has (a host without Vulkan has none).
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == ok {
        var at = 0usize
        while at < found.len {
            if found[at].supported {
                let (device, open_error) = gpu.open(a, .Vulkan, u32(at))
                if open_error == ok {
                    let (vworst, vbad, vskipped, vcmp) = compare(a, device, cdev, w, h)
                    if vcmp != ok { os.exit(20i32) }
                    if !vskipped && (vworst > 2u32 || vbad != 0usize) { os.exit(21i32) }
                    let closed = gpu.close(device)
                }
            }
            at += 1usize
        }
    }
    try io.print("gfx gpu raster ok\n")
    ret ok
}
