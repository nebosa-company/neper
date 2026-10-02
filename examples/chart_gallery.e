// Render the currently delivered chart kinds through Neper's CPU scene and PNG encoder.
// From the repository root, run this executable to refresh docs/chart-previews/*.png.
use e.fs
use e.gpu
use e.io
use e.mem
use e.fmt.png
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene

const WIDTH: u32 = 360u32
const HEIGHT: u32 = 240u32

fn fill(builder: *scene.Builder, rect: geometry.Rect, brush: paint.Brush) -> err {
    ret scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: rect, brush: brush } })
}

fn render_chart(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, marks: *const chart.Layout, path: str) -> err {
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let white = paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) }
    let grid = paint.Brush { Solid: paint.rgba(0.88, 0.91, 0.95, 1.0) }
    let axis = paint.Brush { Solid: paint.rgba(0.32, 0.38, 0.48, 1.0) }
    let ink = paint.Brush { Solid: paint.rgba(0.07, 0.35, 0.76, 1.0) }
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), white)
    var i = 1usize
    while i < 4usize {
        try fill(&builder, geometry.rect(44.0, 30.0 + f32(i) * 43.5, 286.0, 1.0), grid)
        i += 1usize
    }
    try fill(&builder, geometry.rect(44.0, 30.0, 1.0, 175.0), axis)
    try fill(&builder, geometry.rect(44.0, 204.0, 287.0, 1.0), axis)
    try chart_scene.append(a, &builder, marks, ink)
    let (compiled, compile_error) = scene.compile(renderer, scene.finish(&builder))
    if compile_error != ok { ret compile_error }
    try scene.render(renderer, compiled, canvas, geometry.Size { width: f32(WIDTH), height: f32(HEIGHT) })
    let (shown, shown_error) = gpu.presented(output_target)
    if shown_error != ok { ret shown_error }
    let count = usize(WIDTH) * usize(HEIGHT)
    let (pixels, pixels_error) = mem.alloc[u32](a, count)
    if pixels_error != ok { ret pixels_error }
    try gpu.read_image(q, shown, pixels)
    let (rgba, rgba_error) = mem.alloc[u8](a, count * 4usize)
    if rgba_error != ok { ret rgba_error }
    i = 0usize
    while i < count {
        let pixel = pixels[i]
        rgba[4usize * i] = u8(pixel & 255u32)
        rgba[4usize * i + 1usize] = u8((pixel >> 8u32) & 255u32)
        rgba[4usize * i + 2usize] = u8((pixel >> 16u32) & 255u32)
        rgba[4usize * i + 3usize] = u8((pixel >> 24u32) & 255u32)
        i += 1usize
    }
    let (view, view_error) = image.make_const(rgba, WIDTH, HEIGHT, usize(WIDTH) * 4usize, .Rgba8, .Straight)
    if view_error != ok { ret view_error }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try png.encode(&writer, view, png.EncodeOptions { compression: .Fast, interlace: false })
    try fs.write_file(a, path, io.memory_bytes(&held))
    try scene.release_scene(renderer, compiled)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, device_error) = gpu.open(a, .Cpu, 0u32)
    if device_error != ok { ret device_error }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (output_target, target_error) = gpu.open_target(queue, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, WIDTH, HEIGHT, .Rgba8)
    if target_error != ok { ret target_error }
    let (canvas, canvas_error) = scene.target_of(a, output_target)
    if canvas_error != ok { ret canvas_error }
    let (made_renderer, renderer_error) = scene.renderer(a, device, queue, 5u32, 1u32)
    if renderer_error != ok { ret renderer_error }
    var renderer = made_renderer
    let x = [8]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 }
    let y = [8]f32{ 1.0, 4.0, 3.0, 6.0, 4.0, 5.0, 2.0, 7.0 }
    var points: [8]chart.Coord = zero
    var segments: [14]chart.Segment = zero
    var bars: [8]geometry.Rect = zero
    let bounds = geometry.rect(44.0, 30.0, 286.0, 174.0)
    let kinds = [4]chart.Kind{ .Scatter, .Line, .Bar, .Step }
    let paths = [4]str{ "docs/chart-previews/scatter.png", "docs/chart-previews/line.png", "docs/chart-previews/bar.png", "docs/chart-previews/step.png" }
    var i = 0usize
    while i < kinds.len {
        var spec = chart.spec(kinds[i], bounds, x[..], y[..])
        let (marks, layout_error) = chart.layout(&spec, points[..], segments[..], bars[..])
        if layout_error != ok { ret layout_error }
        try render_chart(a, queue, output_target, canvas, &renderer, &marks, paths[i])
        i += 1usize
    }
    let values = [16]f32{ 1.0, 2.0, 2.0, 2.5, 3.0, 3.5, 4.0, 4.0, 4.0, 5.0, 5.5, 6.0, 6.0, 7.0, 8.0, 8.5 }
    var counts: [8]u64 = zero
    var hist_bars: [8]geometry.Rect = zero
    let (hist, hist_error) = chart.histogram(values[..], bounds, counts[..], hist_bars[..])
    if hist_error != ok { ret hist_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &hist, "docs/chart-previews/histogram.png")
    var cdf_segments: [31]chart.Segment = zero
    let (cdf, cdf_error) = chart.ecdf(values[..], bounds, cdf_segments[..])
    if cdf_error != ok { ret cdf_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &cdf, "docs/chart-previews/ecdf.png")
    let box_values = [8]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 20.0 }
    var box_points: [2]chart.Coord = zero
    var box_lines: [5]chart.Segment = zero
    var box_rects: [1]geometry.Rect = zero
    let (box, box_error) = chart.box_plot(box_values[..], bounds, box_points[..], box_lines[..], box_rects[..])
    if box_error != ok { ret box_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &box, "docs/chart-previews/box.png")
    let density_values = [16]f64{ 1.0, 2.0, 2.0, 2.5, 3.0, 3.5, 4.0, 4.0, 4.0, 5.0, 5.5, 6.0, 6.0, 7.0, 8.0, 8.5 }
    var grid: [64]f64 = zero
    var estimates: [64]f64 = zero
    var density_segments: [63]chart.Segment = zero
    let (density_plot, density_error) = chart.density(density_values[..], bounds, 0.0f64, grid[..], estimates[..], density_segments[..])
    if density_error != ok { ret density_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &density_plot, "docs/chart-previews/density.png")
    var violin_outline: [128]chart.Coord = zero
    let (violin_plot, violin_error) = chart.violin(density_values[..], bounds, 0.0f64, grid[..], estimates[..], violin_outline[..])
    if violin_error != ok { ret violin_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &violin_plot, "docs/chart-previews/violin.png")
    let qq_values = [9]f64{ -2.4, -1.5, -1.1, -0.4, 0.1, 0.5, 1.2, 1.7, 3.0 }
    var qq_points: [9]chart.Coord = zero
    var qq_reference: [1]chart.Segment = zero
    let (qq_plot, qq_error) = chart.qq_normal(qq_values[..], bounds, qq_points[..], qq_reference[..])
    if qq_error != ok { ret qq_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &qq_plot, "docs/chart-previews/qq.png")
    try scene.close(&renderer)
    try gpu.close_target(output_target)
    try gpu.close(device)
    try io.print("chart previews ok\n")
    ret ok
}
