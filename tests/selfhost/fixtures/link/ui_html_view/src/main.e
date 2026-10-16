// `e.ui.html_view` end to end: HTML and CSS in, pixels out. The page is parsed, styled and laid out against an
// Ahem-like font (every glyph a 1em square, ascent 0.8, descent 0.2), painted by `html_view`'s canvas into a scene and
// rendered by the CPU renderer; the pixels of the glyph squares, a blue block and the background are read back. Also
// the link under a point, wheel scrolling and the document height.

use e.fs
use e.fmt.css.paint as cpaint
use e.gfx.geometry as geo
use e.gfx.scene as scene
use e.gpu
use e.mem
use e.os
use e.str
use e.text.fontset as fontset
use e.text.shape as shape
use e.ui.html_view as view

const SIDE: usize = 128usize
const BLACK: u32 = 4278190080u32
const WHITE: u32 = 4294967295u32
const BLUE: u32 = 4278190335u32

fn main(a: *mem.Arena, args: []str) -> err {
    let (font_bytes, font_error) = fs.read_file(a, "tests/browser/assets/ahem.ttf", 1048576usize)
    if font_error != ok { os.exit(1i32) }
    let (made, made_error) = fontset.new(a)
    if made_error != ok { os.exit(2i32) }
    var fonts_value = made
    if fontset.add(&fonts_value, "Ahem", 400u32, false, font_bytes, 0u32) != ok { os.exit(3i32) }
    fontset.set_generic(&fonts_value, "sans-serif", "Ahem")
    let page = "<html><body style=\"margin:0;background:#fff\"><div style=\"font:20px Ahem;color:#000;width:40px\"><a href=\"/x\" style=\"color:#000\">ab</a></div><div style=\"height:10px;background:#00f\"></div></body></html>"
    let no_sheets: []const str = zero
    // The view owns its own arena: it rewinds it for every paint.
    let (backing, backing_error) = mem.alloc[u8](a, 33554432usize)
    if backing_error != ok { os.exit(4i32) }
    var view_arena = mem.arena_from(backing)
    let (v, open_error) = view.open(&view_arena, page, no_sheets, &fonts_value, view.no_images(), 128.0, 128.0)
    if open_error != ok { os.exit(4i32) }
    if view.document_height(v) < 29.0 || view.document_height(v) > 129.0 { os.exit(5i32) }
    // Links.
    let (href, has) = view.link_at(v, 10.0, 10.0)
    if !has || !str.eq(href, "/x") { os.exit(6i32) }
    let (nothing, has_far) = view.link_at(v, 100.0, 100.0)
    if has_far { os.exit(7i32) }
    // Rendering.
    let (device, open_device_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_device_error != ok { os.exit(8i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(8i32) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok { os.exit(9i32) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { os.exit(9i32) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 2u32, 1u32)
    if renderer_error != ok { os.exit(10i32) }
    var renderer = renderer_value
    if scene.register_font(&renderer, fonts_value.faces.items[0usize].font) != ok { os.exit(11i32) }
    let (bv, be) = scene.builder(a, 4096usize)
    if be != ok { os.exit(12i32) }
    var b = bv
    let custom = view.custom(v)
    let paint_error = custom.paint(custom.ctx, &b, geo.rect(0.0, 0.0, 128.0, 128.0))
    if paint_error != ok { os.exit(13i32) }
    let (id, compile_error) = scene.compile(&renderer, scene.finish(&b))
    if compile_error != ok { os.exit(14i32) }
    if scene.render(&renderer, id, canvas, geo.Size { width: 128.0, height: 128.0 }) != ok { os.exit(15i32) }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { os.exit(16i32) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { os.exit(17i32) }
    if gpu.read_image(q, image, pixels) != ok { os.exit(18i32) }
    // Two glyph squares in the first 40 x 20 pixels, white after them, the blue block below.
    if pixels[10usize * SIDE + 10usize] != BLACK { os.exit(20i32) }
    if pixels[10usize * SIDE + 30usize] != BLACK { os.exit(21i32) }
    if pixels[10usize * SIDE + 50usize] != WHITE { os.exit(22i32) }
    if pixels[25usize * SIDE + 10usize] != BLUE { os.exit(23i32) }
    if pixels[25usize * SIDE + 100usize] != BLUE { os.exit(24i32) }
    if pixels[60usize * SIDE + 10usize] != WHITE { os.exit(25i32) }
    // A gradient background renders from red on the left to blue on the right.
    let (backing2, backing2_error) = mem.alloc[u8](a, 33554432usize)
    if backing2_error != ok { os.exit(30i32) }
    var view_arena2 = mem.arena_from(backing2)
    let page2 = "<html><body style=\"margin:0\"><div style=\"height:20px;background:linear-gradient(to right,#f00,#00f)\"></div></body></html>"
    let (v2, open2_error) = view.open(&view_arena2, page2, no_sheets, &fonts_value, view.no_images(), 128.0, 128.0)
    if open2_error != ok { os.exit(31i32) }
    let (bv2, be2) = scene.builder(a, 4096usize)
    if be2 != ok { os.exit(32i32) }
    var b2 = bv2
    let custom2 = view.custom(v2)
    if custom2.paint(custom2.ctx, &b2, geo.rect(0.0, 0.0, 128.0, 128.0)) != ok { os.exit(33i32) }
    let (id2, compile2_error) = scene.compile(&renderer, scene.finish(&b2))
    if compile2_error != ok { os.exit(34i32) }
    if scene.render(&renderer, id2, canvas, geo.Size { width: 128.0, height: 128.0 }) != ok { os.exit(35i32) }
    let (image2, presented2_error) = gpu.presented(frames)
    if presented2_error != ok { os.exit(36i32) }
    let (pixels2, pixels2_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels2_error != ok { os.exit(37i32) }
    if gpu.read_image(q, image2, pixels2) != ok { os.exit(38i32) }
    let left = pixels2[10usize * SIDE + 2usize]
    let right = pixels2[10usize * SIDE + 125usize]
    if ((left >> 16u32) & 255u32) < 200u32 || (left & 255u32) > 60u32 { os.exit(40i32) }
    if (right & 255u32) < 200u32 || ((right >> 16u32) & 255u32) > 60u32 { os.exit(41i32) }
    ret ok
}
