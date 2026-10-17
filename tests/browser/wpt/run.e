// WPT reftest runner for the Neper browser stack (browser tracker 0.6, 9.2).
//
//   tests/browser/wpt/run.sh [--floor N] [--show] [--only TEXT] [--out DIR] [manifest]
//
// Each line of the manifest is `test | reference | match|mismatch`. Both files are loaded through `e.web.page` from disk, laid
// out and painted at 800x600 with the Ahem-like font (`tests/browser/assets/ahem.ttf`) and rendered by the CPU renderer; a
// `match` passes when the pixels are identical, a `mismatch` when they differ. `--show` lists the failures, `--out DIR`
// writes both renderings of every failure as PNGs, `--floor N` makes the exit status fail below N passes.

use e.algo.deflate as deflate
use e.fs
use e.fmt.png as png
use e.gfx.geometry as geo
use e.gfx.image as image
use e.gfx.scene as scene
use e.gpu
use e.io
use e.mem
use e.net.fetch as fetch
use e.os
use e.str
use e.text.fontset as fontset
use e.ui.html_view as view
use e.web.page as page

const W: usize = 800usize
const H: usize = 600usize

type Env = struct {
    fonts: *fontset.Set, client: *fetch.Client, q: *gpu.Queue,
    frames: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer
}

fn abs_url(a: *mem.Arena, dir: str, name: str) -> str {
    let (u1, e1) = str.concat(a, "file:///", dir)
    if e1 != ok { ret "" }
    let (u2, e2) = str.concat(a, u1, "/")
    if e2 != ok { ret "" }
    let (u3, e3) = str.concat(a, u2, name)
    if e3 != ok { ret "" }
    ret u3
}

// Renders a page file into `out` (W x H BGRA words); false when it does not load or paint.
fn render(a: *mem.Arena, env: *Env, address: str, out: []u32) -> bool {
    let (pg, le) = page.load(a, env.client, env.fonts, address, f32(W), f32(H), 134217728usize)
    if le != ok { ret false }
    page.attach_renderer(pg, env.renderer)
    let (bv, be) = scene.builder(a, 200000usize)
    if be != ok { ret false }
    var b = bv
    let custom = view.custom(pg.view)
    if custom.paint(custom.ctx, &b, geo.rect(0.0, 0.0, f32(W), f32(H))) != ok { ret false }
    let (id, ce) = scene.compile(env.renderer, scene.finish(&b))
    if ce != ok { ret false }
    if scene.render(env.renderer, id, env.canvas, geo.Size { width: f32(W), height: f32(H) }) != ok { ret false }
    let (img, pe) = gpu.presented(env.frames)
    if pe != ok { ret false }
    if gpu.read_image(env.q, img, out) != ok { ret false }
    let released = scene.release_scene(env.renderer, id)
    page.release_fonts(pg)
    ret true
}

fn same_pixels(x: []const u32, y: []const u32) -> bool {
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn all_white(x: []const u32) -> bool {
    var i = 0usize
    while i < x.len {
        if x[i] != 4294967295u32 { ret false }
        i += 1usize
    }
    ret true
}

fn write_png(a: *mem.Arena, path: str, px: []const u32) {
    let (rgba, e1) = mem.alloc[u8](a, W * H * 4usize)
    if e1 != ok { ret }
    var k = 0usize
    while k < W * H {
        let v = px[k]
        rgba[k * 4usize] = u8((v >> 16u32) & 255u32)
        rgba[k * 4usize + 1usize] = u8((v >> 8u32) & 255u32)
        rgba[k * 4usize + 2usize] = u8(v & 255u32)
        rgba[k * 4usize + 3usize] = u8((v >> 24u32) & 255u32)
        k += 1usize
    }
    let cimg = image.ConstImage { pixels: rgba, width: u32(W), height: u32(H), stride: W * 4usize, format: image.Format.Rgba8, alpha: image.Alpha.Straight }
    let (sink, e2) = mem.alloc[u8](a, W * H * 4usize + 65536usize)
    if e2 != ok { ret }
    var sw = io.SliceWriter { data: sink, off: 0usize }
    var writer = io.slice_writer(&sw)
    if png.encode(&writer, cimg, png.EncodeOptions { compression: deflate.Level.Fast, interlace: false }) != ok { ret }
    let written = fs.write_file(a, path, sink[0usize..sw.off])
}

fn trim(s: str) -> str { ret str.trim(s) }

fn main(a: *mem.Arena, args: []str) -> err {
    var manifest = "tests/browser/wpt/reftests/manifest.txt"
    var floor = 0usize
    var show = false
    var poison = false
    var only = ""
    var out_dir = ""
    var i = 1usize
    while i < args.len {
        if str.eq(args[i], "--floor") {
            i += 1usize
            let (n, ne) = str.parse_i64(args[i])
            if ne == ok { floor = usize(n) }
        } else if str.eq(args[i], "--show") {
            show = true
        } else if str.eq(args[i], "--poison") {
            poison = true
        } else if str.eq(args[i], "--only") {
            i += 1usize
            only = args[i]
        } else if str.eq(args[i], "--out") {
            i += 1usize
            out_dir = args[i]
        } else {
            manifest = args[i]
        }
        i += 1usize
    }
    let (text, fe) = fs.read_file(a, manifest, 4194304usize)
    if fe != ok {
        let printed = io.printf["cannot read {}\n"](manifest)
        os.exit(2i32)
    }
    // Fonts and the renderer, once.
    let (font_bytes, font_error) = fs.read_file(a, "tests/browser/assets/ahem.ttf", 1048576usize)
    if font_error != ok { os.exit(3i32) }
    let (made, made_error) = fontset.new(a)
    if made_error != ok { os.exit(3i32) }
    var fonts = made
    if fontset.add(&fonts, "Ahem", 400u32, false, font_bytes, 0u32) != ok { os.exit(3i32) }
    fontset.set_generic(&fonts, "sans-serif", "Ahem")
    fontset.set_generic(&fonts, "serif", "Ahem")
    fontset.set_generic(&fonts, "monospace", "Ahem")
    // The renderer allocates lazily from its arena, so it must not share the one rewound between tests.
    let (rbuf, rbuf_error) = mem.alloc[u8](a, 402653184usize)
    if rbuf_error != ok { os.exit(3i32) }
    var rarena = mem.arena_from(rbuf)
    let ra = &rarena
    let (device, device_error) = gpu.open(ra, gpu.Backend.Cpu, 0u32)
    if device_error != ok { os.exit(4i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(4i32) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(W), u32(H), gpu.Format.Bgra8)
    if frames_error != ok { os.exit(5i32) }
    let (canvas, canvas_error) = scene.target_of(ra, frames)
    if canvas_error != ok { os.exit(5i32) }
    let (renderer_value, renderer_error) = scene.renderer(ra, device, q, 4u32, 256u32)
    if renderer_error != ok { os.exit(6i32) }
    var renderer = renderer_value
    if scene.register_font(&renderer, fonts.faces.items[0usize].font) != ok { os.exit(6i32) }
    let roots = zero_roots()
    var cfg = fetch.default_config(roots)
    cfg.allow_file = true
    let (cl, client_error) = fetch.client(a, cfg, 8usize)
    if client_error != ok { os.exit(7i32) }
    var client = cl
    var env = Env { fonts: &fonts, client: &client, q: q, frames: frames, canvas: canvas, renderer: &renderer }
    let (pa_cell, pe1) = mem.alloc[u32](a, W * H)
    let (pb_cell, pe2) = mem.alloc[u32](a, W * H)
    if pe1 != ok || pe2 != ok { os.exit(8i32) }
    // The directory of the manifest, for the relative file names.
    var dir_end = manifest.len
    while dir_end > 0usize && manifest[dir_end - 1usize] != 47u8 { dir_end -= 1usize }
    var dir = manifest[0usize..dir_end]
    if dir.len > 0usize { dir = dir[0usize..dir.len - 1usize] }
    // Absolute directory for file URLs: cwd-relative paths become absolute.
    let (cwd, cwd_error) = os.current_dir(a)
    if cwd_error != ok { os.exit(9i32) }
    let (abs_dir_a, ad) = str.concat(a, cwd, "/")
    if ad != ok { os.exit(9i32) }
    let (abs_dir_c, ad2) = str.concat(a, abs_dir_a, dir)
    if ad2 != ok { os.exit(9i32) }
    // A manifest given by absolute path (`D:/...` or `/...`) names its directory as it is.
    var abs_dir = abs_dir_c
    if dir.len > 1usize && (dir[0usize] == 47u8 || dir[1usize] == 58u8) { abs_dir = dir }
    let mark = mem.mark(a)
    var total = 0usize
    var passed = 0usize
    var broken = 0usize
    var blank = 0usize
    var pos = 0usize
    while pos < text.len {
        var end = pos
        while end < text.len && text[end] != 10u8 { end += 1usize }
        let line = trim(text[pos..end])
        pos = end + 1usize
        if line.len == 0usize || line[0usize] == 35u8 { continue }
        // test | reference | kind
        var bar1 = 0usize
        while bar1 < line.len && line[bar1] != 124u8 { bar1 += 1usize }
        var bar2 = bar1 + 1usize
        while bar2 < line.len && line[bar2] != 124u8 { bar2 += 1usize }
        if bar2 >= line.len { continue }
        let test_name = trim(line[0usize..bar1])
        let ref_name = trim(line[bar1 + 1usize..bar2])
        let kind = trim(line[bar2 + 1usize..])
        if only.len > 0usize {
            let (found, has) = str.find(test_name, only)
            if !has { continue }
        }
        total += 1usize
        let work = mem.mark(a)
        let ta = pa_cell
        let tb = pb_cell
        let ok_a = render(a, &env, abs_url(a, abs_dir, test_name), ta)
        let ok_b = render(a, &env, abs_url(a, abs_dir, ref_name), tb)
        var good = false
        if ok_a && ok_b {
            let same = same_pixels(ta, tb)
            good = same
            if same && all_white(ta) { blank += 1usize }
            if str.eq(kind, "mismatch") { good = !same }
        } else {
            broken += 1usize
            if show { let printed = io.printf["UNLOAD {} test={} ref={}\n"](test_name, ok_a, ok_b) }
        }
        if good { passed += 1usize } else {
            if show { let printed = io.printf["FAIL {} ({})\n"](test_name, kind) }
            if out_dir.len > 0usize && ok_a && ok_b {
                let (p1, p1e) = str.concat(a, out_dir, "/")
                if p1e == ok {
                    var safe_buf: [256]u8 = zero
                    var sn = 0usize
                    while sn < test_name.len && sn < 255usize {
                        var ch = test_name[sn]
                        if ch == 47u8 { ch = 95u8 }
                        safe_buf[sn] = ch
                        sn += 1usize
                    }
                    let (p2, p2e) = str.concat(a, p1, safe_buf[0usize..sn])
                    if p2e == ok {
                        let (p3, p3e) = str.concat(a, p2, ".test.png")
                        let (p4, p4e) = str.concat(a, p2, ".ref.png")
                        if p3e == ok && p4e == ok {
                            write_png(a, p3, ta)
                            write_png(a, p4, tb)
                        }
                    }
                }
            }
        }
        // `--poison`: overwrite the memory the test used so any read of memory it never wrote shows up at once.
        if poison {
            let used = a.off - work
            mem.reset(a, work)
            let (junk, je) = mem.alloc[u8](a, used)
            if je == ok {
                var pq = 0usize
                while pq < junk.len {
                    junk[pq] = 170u8
                    pq += 1usize
                }
            }
        }
        mem.reset(a, work)
    }
    mem.reset(a, mark)
    try io.printf["wpt reftests {} pass {} (unloadable {}, blank pairs {})\n"](total, passed, broken, blank)
    if passed < floor { os.exit(1i32) }
    ret ok
}

fn zero_roots() -> []const u8 {
    let none: []const u8 = zero
    ret none
}
