use e.fmt.png
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, device_error) = gpu.open(a, .Cpu, 0u32)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (output_target, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, 4u32, 4u32, .Rgba8)
    if target_error != ok { ret target_error }
    defer let _ = gpu.close_target(output_target)
    let (canvas, canvas_error) = scene.target_of(a, output_target)
    if canvas_error != ok { ret canvas_error }
    let (made_renderer, renderer_error) = scene.renderer(a, device, q, 2u32, 1u32)
    if renderer_error != ok { ret renderer_error }
    var renderer = made_renderer
    defer let _ = scene.close(&renderer)
    let (made, builder_error) = scene.builder(a, 1usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect {
        rect: geometry.rect(0.0, 0.0, 4.0, 4.0),
        brush: paint.Brush { Solid: paint.rgba(1.0, 0.0, 0.0, 0.5) },
    } })
    let (_, invalid_size) = chart_scene.rasterize(a, q, output_target, canvas, &renderer, &builder, 0u32, 4u32)
    if invalid_size != chart.Invalid { ret chart.Invalid }
    let (view, view_error) = chart_scene.rasterize(a, q, output_target, canvas, &renderer, &builder, 4u32, 4u32)
    if view_error != ok { ret view_error }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try png.encode(&writer, view, png.EncodeOptions { compression: .Fast, interlace: false })
    let bytes = io.memory_bytes(&held)
    var source = io.SliceReader { data: bytes, off: 0usize }
    let (decoded, decode_error) = png.decode(a, io.slice_reader(&source), png.DecodeOptions { max_width: 4u32, max_height: 4u32, max_pixels: 16u64, verify_crc: true })
    if decode_error != ok { ret decode_error }
    if decoded.width != 4u32 || decoded.height != 4u32 || decoded.pixels[0usize] < 250u8 || decoded.pixels[1usize] != 0u8 || decoded.pixels[2usize] != 0u8 || decoded.pixels[3usize] < 126u8 || decoded.pixels[3usize] > 129u8 { ret chart.Invalid }
    try io.print("gfx chart png ok\n")
    ret ok
}
