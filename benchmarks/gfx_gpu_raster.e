// Benchmark and comparison of the tile rasteriser (D5929) with the CPU rasteriser on the device named by NEPER_VK_DEVICE (or RT_BACKEND=cpu
// for the kernel's CPU build): per scene the CPU frame time, the GPU frame time split into encode and launch, and the pixel difference.
// Build: neper-try emit-executable gfx_gpu_raster.e <neper root> x64 windows out.exe --release; an optional argument is the first scene.
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

fn say(a: *mem.Arena, tag: str, v: u64) {
    let (sb, sbe) = str.builder(a, 200usize)
    var so = sb
    let e1 = str.push(&so, tag)
    let e2 = str.push(&so, "=")
    let e3 = str.push_u64(&so, v)
    let e4 = str.push(&so, " ")
    let pr = io.print(str.done(&so))
}

fn now() -> i64 {
    let (t, e) = time.monotonic()
    ret t.nanos
}

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

fn main(a: *mem.Arena, args: []str) -> err {
    let w = 960u32
    let h = 640u32
    let (cdev, ce) = gpu.open(a, .Cpu, 0u32)
    if ce != ok { ret ce }
    let (cq, cqe) = gpu.queue(cdev)
    if cqe != ok { ret cqe }
    var vdev: *gpu.Device = zero
    var ve = ok
    let (benv, benv_error) = os.env(a, "RT_BACKEND")
    if benv_error == ok && str.eq(benv, "cpu") { (vdev, ve) = gpu.open(a, .Cpu, 0u32) } else { (vdev, ve) = gpu.open_preferred(a, .Vulkan) }
    if ve != ok { ret ve }
    let (vq, vqe) = gpu.queue(vdev)
    if vqe != ok { ret vqe }
    var (cr, cre) = scene.renderer(a, cdev, cq, 4u32, 16u32)
    if cre != ok { ret cre }
    var (vr, vre) = scene.renderer(a, vdev, vq, 4u32, 16u32)
    if vre != ok { ret vre }
    let (gr, gre) = gpuraster.install(&vr, a, vq, 16usize, false)
    if gre == gpuraster.Refused {
        let pr0 = io.print("RASTER REFUSED by its self-test: the CPU renders on this device")
        ret ok
    }
    if gre != ok { ret gre }
    let (ct, cte) = gpu.open_target(cq, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, w, h, .Bgra8)
    if cte != ok { ret cte }
    let (vt, vte) = gpu.open_target(vq, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, w, h, .Bgra8)
    if vte != ok { ret vte }
    let (cdraw, cde) = scene.target_of(a, ct)
    if cde != ok { ret cde }
    let (vdraw, vde) = scene.target_of(a, vt)
    if vde != ok { ret vde }
    let (ctex, cte2) = make_texture(a, &cr)
    if cte2 != ok { ret cte2 }
    let (vtex, vte2) = make_texture(a, &vr)
    if vte2 != ok { ret vte2 }
    let (cpx, e1) = mem.alloc[u32](a, usize(w) * usize(h))
    let (vpx, e2) = mem.alloc[u32](a, usize(w) * usize(h))
    var variant = 0u32
    if args.len > 1usize { variant = u32(args[1usize][0usize] - 48u8) }
    var prev_c: scene.SceneId = zero
    var prev_v: scene.SceneId = zero
    var worst_all = 0u32
    var bad_all = 0usize
    while variant < 11u32 {
        let (cs, cse) = build_scene(a, &cr, f32(w), f32(h), variant, ctex)
        if cse != ok { ret cse }
        let (vs, vse) = build_scene(a, &vr, f32(w), f32(h), variant, vtex)
        if vse != ok { ret vse }
        let t0 = now()
        try scene.render_scaled(&cr, cs, cdraw, geometry.Size { width: f32(w), height: f32(h) }, 1.0)
        let t1 = now()
        try scene.render_scaled(&vr, vs, vdraw, geometry.Size { width: f32(w), height: f32(h) }, 1.0)
        let t2 = now()
        if variant > 0u32 { let r1 = scene.release_scene(&cr, prev_c) }
        if variant > 0u32 { let r2 = scene.release_scene(&vr, prev_v) }
        prev_c = cs
        prev_v = vs
        let (gf, dbg, enc, lau, ents, eds, tls) = gpuraster.counts(&vr, gr)
        let (cimg, cie) = gpu.presented(ct)
        if cie != ok { ret cie }
        let (vimg, vie) = gpu.presented(vt)
        if vie != ok { ret vie }
        try gpu.read_image(cq, cimg, cpx)
        try gpu.read_image(vq, vimg, vpx)
        var first_read_bad = 0usize
        var qa = 0usize
        while qa < vpx.len {
            if vpx[qa] != cpx[qa] { first_read_bad += 1usize }
            qa += 1usize
        }
        let spin_until = now() + 200000000i64
        while now() < spin_until { }
        try gpu.read_image(vq, vimg, vpx)
        var second_read_bad = 0usize
        qa = 0usize
        while qa < vpx.len {
            if vpx[qa] != cpx[qa] { second_read_bad += 1usize }
            qa += 1usize
        }
        say(a, "read1_differs", u64(first_read_bad))
        say(a, "read2_differs", u64(second_read_bad))
        var worst = 0u32
        var bad = 0usize
        var first_bad_at = 0usize
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
                if d > worst { worst = d }
                if d > 2u32 { over = true }
                ch += 1u32
            }
            if over {
                if bad == 0usize { first_bad_at = i }
                bad += 1usize
            }
            i += 1usize
        }
        say(a, "\nvariant", u64(variant))
        if variant == 4u32 {
            let slot = usize(gr.slot_of[8usize * gr.ntx + 36usize])
            let first = usize(gr.h_tiles[slot * 4usize + 1usize])
            let cnt = usize(gr.h_tiles[slot * 4usize + 2usize])
            say(a, "T36_8_entries", u64(cnt))
            var q = 0usize
            while q < cnt {
                let at = (first + q) * 4usize
                say(a, "op", u64(gr.h_entries[at]))
                say(a, "edges", u64(gr.h_entries[at + 2usize]))
                say(a, "bd", u64(gr.h_entries[at + 3usize]))
                q += 1usize
            }
        }
        say(a, "cpu_us", u64((t1 - t0) / 1000i64))
        say(a, "gpu_frame_us", u64((t2 - t1) / 1000i64))
        say(a, "encode_us", u64(enc))
        say(a, "launch_us", u64(lau))
        say(a, "drawn_on_gpu", gf)
        say(a, "launch_error", dbg)
        say(a, "tiles", u64(tls))
        say(a, "entries", u64(ents))
        say(a, "worst_diff", u64(worst))
        var hsh = 2166136261u64
        var hq = 0usize
        while hq < vpx.len {
            hsh = (hsh ^ u64(vpx[hq])) * 16777619u64 % 4294967291u64
            hq += 1usize
        }
        say(a, "gpu_hash", hsh)
        say(a, "pixels_over_2", u64(bad))
        if variant == 9u32 {
            var mty = 0usize
            while mty < 8usize {
                var line_bad: [10]u32 = zero
                var mtx = 0usize
                while mtx < 10usize {
                    var cnt = 0u32
                    var yy = 0usize
                    while yy < 16usize {
                        var xx = 0usize
                        while xx < 16usize {
                            let at = (400usize + mty * 16usize + yy) * usize(w) + 560usize + mtx * 16usize + xx
                            if vpx[at] != cpx[at] { cnt += 1u32 }
                            xx += 1usize
                        }
                        yy += 1usize
                    }
                    line_bad[mtx] = cnt
                    mtx += 1usize
                }
                say(a, "tilerow", u64(mty))
                var q = 0usize
                while q < 10usize {
                    say(a, "", u64(line_bad[q]))
                    q += 1usize
                }
                mty += 1usize
            }
        }
        if bad > 0usize {
            say(a, "first_bad_x", u64(first_bad_at % usize(w)))
            say(a, "y", u64(first_bad_at / usize(w)))
            say(a, "cpu", u64(cpx[first_bad_at]))
            say(a, "gpu", u64(vpx[first_bad_at]))
        }
        if variant >= 8u32 {
            say(a, "c560_400", u64(cpx[400usize * usize(w) + 560usize]))
            say(a, "g560_400", u64(vpx[400usize * usize(w) + 560usize]))
            say(a, "c561_401", u64(cpx[401usize * usize(w) + 561usize]))
            say(a, "g561_401", u64(vpx[401usize * usize(w) + 561usize]))
            say(a, "c600_450", u64(cpx[450usize * usize(w) + 600usize]))
            say(a, "g600_450", u64(vpx[450usize * usize(w) + 600usize]))
            say(a, "c559_400", u64(cpx[400usize * usize(w) + 559usize]))
            say(a, "g559_400", u64(vpx[400usize * usize(w) + 559usize]))
        }
        if worst > worst_all { worst_all = worst }
        bad_all += bad
        variant += 1u32
    }
    say(a, "\nTOTAL worst", u64(worst_all))
    say(a, "bad", u64(bad_all))
    let pr = io.print("\n")
    ret ok
}

