// A contact sheet of the NeperOS icon set (D2200): every app icon at 2x on a dark ground, and the
// top-bar glyphs on a bar strip in the theme ink. It draws the embedded SVG (icons.e) through
// e.gfx.svg into an e.gpu CPU-backend target and writes a binary PPM to standard output, so the set
// can be looked at on any host:  icon_sheet.exe > sheet.ppm
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use icons

const WIDTH: usize = 848usize
const HEIGHT: usize = 1150usize

fn color(r: usize, g: usize, b: usize) -> paint.Color {
    ret paint.Color { red: f32(r) / 255.0, green: f32(g) / 255.0, blue: f32(b) / 255.0, alpha: 1.0 }
}

fn block(builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, c: paint.Color) -> err {
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, y, w, h), brush: paint.Brush { Solid: c } } })
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
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
    let (builder_value, builder_error) = scene.builder(a, 8192usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    let ink = color(232usize, 235usize, 240usize)
    try block(&builder, 0.0, 0.0, f32(WIDTH), f32(HEIGHT), color(11usize, 13usize, 16usize))
    var i = 0usize
    while i < icons.APP_COUNT {
        let col = i % 4usize
        let row = i / 4usize
        let x = 16.0 + f32(col) * 208.0
        let y = 16.0 + f32(row) * 208.0
        try svg.draw(a, &builder, icons.app(i), geometry.rect(x, y, 192.0, 192.0), ink)
        i += 1usize
    }
    try block(&builder, 0.0, 1064.0, f32(WIDTH), 86.0, color(20usize, 23usize, 28usize))
    var j = 0usize
    while j < icons.BAR_COUNT {
        try svg.draw(a, &builder, icons.bar(j), geometry.rect(32.0 + f32(j) * 72.0, 1078.0, 56.0, 56.0), ink)
        j += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret compile_error }
    try scene.render(&renderer, scene_id, canvas, geometry.Size { width: f32(WIDTH), height: f32(HEIGHT) })
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret presented_error }
    let (pixels, pixels_error) = mem.alloc[u32](a, WIDTH * HEIGHT)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok { ret gpu.OutOfMemory }
    let header = "P6\n848 1150\n255\n"
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
