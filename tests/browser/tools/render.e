// Renders a web page to a PNG file (browser tracker 0.6, the render tool): loads the URL through `e.web.page`, paints the
// first `height` pixels (or the whole page with `--full`) into the CPU renderer and writes the pixels.
//
//   tests/browser/tools/render.sh URL OUT.png [--width N] [--height N] [--full] [--scroll N]
//
// Fonts: the Windows system fonts when present (Arial, Times New Roman, Courier New, Verdana, Georgia, Segoe UI, Tahoma),
// else the Cantarell faces in docs/ui/looks/ref/linux/fonts. `serif`, `sans-serif` and `monospace` map to Times, Arial and
// Courier New.

use e.data.list as list
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
use e.net.tls.hoststore as hoststore
use e.os
use e.str
use e.text.fontset as fontset
use e.ui.html_view as view
use e.web.page as page

type Face = struct { file: str, family: str, weight: u32, italic: bool }

fn face(file: str, family: str, weight: u32, italic: bool) -> Face {
    ret Face { file: file, family: family, weight: weight, italic: italic }
}

fn add_faces(a: *mem.Arena, set: *fontset.Set, faces: []const Face) -> usize {
    var added = 0usize
    var i = 0usize
    while i < faces.len {
        let (bytes, e) = fs.read_file(a, faces[i].file, 33554432usize)
        if e == ok {
            if fontset.add(set, faces[i].family, faces[i].weight, faces[i].italic, bytes, 0u32) == ok { added += 1usize }
        }
        i += 1usize
    }
    ret added
}

fn parse_number(s: str, fallback: usize) -> usize {
    let (n, e) = str.parse_i64(s)
    if e != ok || n < 0i64 { ret fallback }
    ret usize(n)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var address = ""
    var out_path = ""
    var width = 1280usize
    var height = 800usize
    var full = false
    var scroll = 0usize
    var i = 1usize
    while i < args.len {
        if str.eq(args[i], "--width") {
            i += 1usize
            width = parse_number(args[i], width)
        } else if str.eq(args[i], "--height") {
            i += 1usize
            height = parse_number(args[i], height)
        } else if str.eq(args[i], "--scroll") {
            i += 1usize
            scroll = parse_number(args[i], 0usize)
        } else if str.eq(args[i], "--full") {
            full = true
        } else if address.len == 0usize {
            address = args[i]
        } else {
            out_path = args[i]
        }
        i += 1usize
    }
    if address.len == 0usize || out_path.len == 0usize {
        let printed = io.printf["usage: render URL OUT.png [--width N] [--height N] [--full] [--scroll N]\n"]()
        os.exit(2i32)
    }
    // Fonts.
    let (made, made_error) = fontset.new(a)
    if made_error != ok { os.exit(3i32) }
    var fonts = made
    let win = "C:/Windows/Fonts/"
    let system_faces = [15]Face {
        face("C:/Windows/Fonts/arial.ttf", "Arial", 400u32, false), face("C:/Windows/Fonts/arialbd.ttf", "Arial", 700u32, false),
        face("C:/Windows/Fonts/ariali.ttf", "Arial", 400u32, true), face("C:/Windows/Fonts/arialbi.ttf", "Arial", 700u32, true),
        face("C:/Windows/Fonts/times.ttf", "Times New Roman", 400u32, false), face("C:/Windows/Fonts/timesbd.ttf", "Times New Roman", 700u32, false),
        face("C:/Windows/Fonts/timesi.ttf", "Times New Roman", 400u32, true),
        face("C:/Windows/Fonts/cour.ttf", "Courier New", 400u32, false), face("C:/Windows/Fonts/courbd.ttf", "Courier New", 700u32, false),
        face("C:/Windows/Fonts/verdana.ttf", "Verdana", 400u32, false), face("C:/Windows/Fonts/verdanab.ttf", "Verdana", 700u32, false),
        face("C:/Windows/Fonts/georgia.ttf", "Georgia", 400u32, false), face("C:/Windows/Fonts/segoeui.ttf", "Segoe UI", 400u32, false),
        face("C:/Windows/Fonts/segoeuib.ttf", "Segoe UI", 700u32, false), face("C:/Windows/Fonts/tahoma.ttf", "Tahoma", 400u32, false)
    }
    var count = add_faces(a, &fonts, system_faces[0usize..15usize])
    if count == 0usize {
        let fallback = [2]Face { face("docs/ui/looks/ref/linux/fonts/Cantarell-Regular.ttf", "Arial", 400u32, false), face("docs/ui/looks/ref/linux/fonts/Cantarell-Bold.ttf", "Arial", 700u32, false) }
        count = add_faces(a, &fonts, fallback[0usize..2usize])
    }
    if count == 0usize {
        let printed = io.printf["no fonts found\n"]()
        os.exit(4i32)
    }
    fontset.set_generic(&fonts, "sans-serif", "Arial")
    fontset.set_generic(&fonts, "serif", "Times New Roman")
    fontset.set_generic(&fonts, "monospace", "Courier New")
    fontset.set_generic(&fonts, "system-ui", "Segoe UI")
    // Network and page.
    let (roots, roots_error) = hoststore.system_roots(a, 4194304usize)
    if roots_error != ok { os.exit(5i32) }
    let (cl, client_error) = fetch.client(a, fetch.default_config(roots.der), 256usize)
    if client_error != ok { os.exit(6i32) }
    var client = cl
    let (pg, load_error) = page.load(a, &client, &fonts, address, f32(width), f32(height), 268435456usize)
    if load_error != ok {
        let printed = io.printf["load failed\n"]()
        os.exit(7i32)
    }
    let doc_h = usize(view.document_height(pg.view))
    if full {
        height = doc_h
        if height > 16384usize { height = 16384usize }
        if view.resize(pg.view, f32(width), f32(height)) != ok { os.exit(8i32) }
    }
    view.scroll_to(pg.view, 0.0, f32(scroll))
    // Renderer.
    let (device, device_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if device_error != ok { os.exit(9i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(9i32) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(width), u32(height), gpu.Format.Bgra8)
    if frames_error != ok { os.exit(10i32) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { os.exit(10i32) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 2u32, 256u32)
    if renderer_error != ok { os.exit(11i32) }
    var renderer = renderer_value
    var f = 0usize
    while f < fonts.faces.len && f < 16usize {
        if scene.register_font(&renderer, fonts.faces.items[f].font) != ok { os.exit(12i32) }
        f += 1usize
    }
    page.attach_renderer(pg, &renderer)
    let (bv, be) = scene.builder(a, 200000usize)
    if be != ok { os.exit(13i32) }
    var b = bv
    let custom = view.custom(pg.view)
    let paint_error = custom.paint(custom.ctx, &b, geo.rect(0.0, 0.0, f32(width), f32(height)))
    if paint_error != ok {
        let printed = io.printf["paint failed (scene limits?)\n"]()
        os.exit(14i32)
    }
    let (id, compile_error) = scene.compile(&renderer, scene.finish(&b))
    if compile_error != ok { os.exit(15i32) }
    if scene.render(&renderer, id, canvas, geo.Size { width: f32(width), height: f32(height) }) != ok { os.exit(16i32) }
    let (img, presented_error) = gpu.presented(frames)
    if presented_error != ok { os.exit(17i32) }
    let (pixels, pixels_error) = mem.alloc[u32](a, width * height)
    if pixels_error != ok { os.exit(18i32) }
    if gpu.read_image(q, img, pixels) != ok { os.exit(19i32) }
    // BGRA words to RGBA bytes.
    let (rgba, rgba_error) = mem.alloc[u8](a, width * height * 4usize)
    if rgba_error != ok { os.exit(20i32) }
    var k = 0usize
    while k < width * height {
        let px = pixels[k]
        rgba[k * 4usize] = u8((px >> 16u32) & 255u32)
        rgba[k * 4usize + 1usize] = u8((px >> 8u32) & 255u32)
        rgba[k * 4usize + 2usize] = u8(px & 255u32)
        rgba[k * 4usize + 3usize] = u8((px >> 24u32) & 255u32)
        k += 1usize
    }
    let cimg = image.ConstImage { pixels: rgba, width: u32(width), height: u32(height), stride: width * 4usize, format: image.Format.Rgba8, alpha: image.Alpha.Straight }
    let (sink_bytes, sink_error) = mem.alloc[u8](a, width * height * 4usize + 65536usize)
    if sink_error != ok { os.exit(21i32) }
    var sw = io.SliceWriter { data: sink_bytes, off: 0usize }
    var writer = io.slice_writer(&sw)
    if png.encode(&writer, cimg, png.EncodeOptions { compression: deflate.Level.Fast, interlace: false }) != ok { os.exit(22i32) }
    if fs.write_file(a, out_path, sink_bytes[0usize..sw.off]) != ok { os.exit(23i32) }
    try io.printf["rendered {} ({}x{}, title: {}, document height {})\n"](address, width, height, pg.title, doc_h)
    ret ok
}
