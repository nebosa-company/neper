// A specimen of the lunar fonts through text.e (D2204): each face at its role from the theme spec,
// drawn on a host into a binary PPM on standard output:
//   text_sheet.exe <fonts dir> > specimen.ppm
use e.mem
use e.os
use e.fs
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use text

const WIDTH: usize = 412usize
const HEIGHT: usize = 360usize

fn color(r: f32, g: f32, b: f32) -> paint.Color {
    ret paint.Color { red: r, green: g, blue: b, alpha: 1.0 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret ok }
    let dir = args[1usize]
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { ret open_error }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(WIDTH), u32(HEIGHT), gpu.Format.Bgra8)
    if frames_error != ok { ret frames_error }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret canvas_error }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret renderer_error }
    var renderer = renderer_value
    let (jost_bold_bytes, e1) = fs.read_file(a, "fonts/jost-bold.ttf", 65536usize)
    if e1 != ok { ret e1 }
    let (jost_bytes, e2) = fs.read_file(a, "fonts/jost-regular.ttf", 65536usize)
    if e2 != ok { ret e2 }
    let (sora_bytes, e3) = fs.read_file(a, "fonts/sora-medium.ttf", 65536usize)
    if e3 != ok { ret e3 }
    let (grotesk_bytes, e4) = fs.read_file(a, "fonts/spacegrotesk-regular.ttf", 65536usize)
    if e4 != ok { ret e4 }
    let (exo_bytes, e5) = fs.read_file(a, "fonts/exo2-regular.ttf", 65536usize)
    if e5 != ok { ret e5 }
    let (jost_bold, r1) = text.register(&renderer, 1u32, jost_bold_bytes)
    if r1 != ok { ret r1 }
    let (jost, r2) = text.register(&renderer, 2u32, jost_bytes)
    if r2 != ok { ret r2 }
    let (sora, r3) = text.register(&renderer, 3u32, sora_bytes)
    if r3 != ok { ret r3 }
    let (grotesk, r4) = text.register(&renderer, 4u32, grotesk_bytes)
    if r4 != ok { ret r4 }
    let (exo, r5) = text.register(&renderer, 5u32, exo_bytes)
    if r5 != ok { ret r5 }
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), brush: paint.Brush { Solid: color(0.18, 0.18, 0.2) } } })
    let white = color(1.0, 1.0, 1.0)
    let clock_text = "10:35"
    let clock_w = text.measure(a, jost_bold, 96.0, clock_text)
    let (clock_box, c1) = text.draw(a, &builder, jost_bold, 96.0, clock_text, (f32(WIDTH) - clock_w) / 2.0, 8.0, 0.0, 0u32, layout.Align.Start, white)
    if c1 != ok { ret c1 }
    let (date_box, c2) = text.draw(a, &builder, jost, 30.0, "October 7", 110.0, 118.0, 0.0, 0u32, layout.Align.Start, white)
    if c2 != ok { ret c2 }
    let (t1, c3) = text.draw(a, &builder, sora, 17.0, "Moon Phase: Waning Gibbous", 16.0, 170.0, 380.0, 1u32, layout.Align.Start, white)
    if c3 != ok { ret c3 }
    let (t2, c4) = text.draw(a, &builder, grotesk, 14.0, "93% illuminated  -  SPACE GROTESK", 16.0, 196.0, 380.0, 1u32, layout.Align.Start, white)
    if c4 != ok { ret c4 }
    let (t3, c5) = text.draw(a, &builder, exo, 15.0, "Orion Crew Module successfully tests communication from the Moon\xE2\x80\x99s far side", 16.0, 230.0, 380.0, 3u32, layout.Align.Start, white)
    if c5 != ok { ret c5 }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret compile_error }
    try scene.render(&renderer, scene_id, canvas, geometry.Size { width: f32(WIDTH), height: f32(HEIGHT) })
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret presented_error }
    let (pixels, pixels_error) = mem.alloc[u32](a, WIDTH * HEIGHT)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok { ret gpu.OutOfMemory }
    let header = "P6\n412 360\n255\n"
    let (bytes, bytes_error) = mem.alloc[u8](a, header.len + WIDTH * HEIGHT * 3usize)
    if bytes_error != ok { ret bytes_error }
    var at = 0usize
    while at < header.len {
        bytes[at] = header[at]
        at += 1usize
    }
    var p = 0usize
    while p < pixels.len {
        let v = pixels[p]
        bytes[at] = u8((v >> 16u32) & 255u32)
        bytes[at + 1usize] = u8((v >> 8u32) & 255u32)
        bytes[at + 2usize] = u8(v & 255u32)
        at += 3usize
        p += 1usize
    }
    let (written, write_error) = os.write(os.stdout(), bytes)
    ret ok
}
