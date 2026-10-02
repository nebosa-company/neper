// Render the currently delivered chart kinds through Neper's CPU scene and PNG encoder.
// From the repository root, run this executable to refresh docs/chart-previews/*.png.
use e.fs
use e.gpu
use e.io
use e.mem
use e.str
use e.fmt.png
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene

const WIDTH: u32 = 360u32
const HEIGHT: u32 = 240u32

fn fill(builder: *scene.Builder, rect: geometry.Rect, brush: paint.Brush) -> err {
    ret scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: rect, brush: brush } })
}

fn render_builder(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, builder: *scene.Builder, path: str) -> err {
    let (compiled, compile_error) = scene.compile(renderer, scene.finish(builder))
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
    var i = 0usize
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

fn vector_path(a: *mem.Arena, png_path: str) -> (str, err) {
    if !str.ends_with(png_path, ".png") { ret (zero, chart.Invalid) }
    let (made, builder_error) = str.builder(a, png_path.len)
    if builder_error != ok { ret (zero, builder_error) }
    var built = made
    try str.push(&built, png_path[..png_path.len - 4usize])
    try str.push(&built, ".svg")
    ret (str.done(&built), ok)
}

fn svg_start(a: *mem.Arena, png_path: str) -> (io.MemoryWriter, err) {
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret (zero, writer_error) }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    let (slash, found) = str.rfind(png_path, "/")
    var start = 0usize
    if found { start = slash + 1usize }
    try chart_svg.begin(&writer, f32(WIDTH), f32(HEIGHT), png_path[start..png_path.len - 4usize], "Neper chart rendered from caller-owned geometry")
    try chart_svg.rect(&writer, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.rgba(1.0, 1.0, 1.0, 1.0), false)
    ret (held, ok)
}

fn export_svg_chart(a: *mem.Arena, marks: *const chart.Layout, x_scale: chart.Scale, y_scale: chart.Scale, png_path: str) -> err {
    let (held, start_error) = svg_start(a, png_path)
    if start_error != ok { ret start_error }
    var state = held
    var writer = io.writer(mem.cast[*void](&state), io.memory_write)
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [4]chart.Tick = zero
    let (_, x_error) = chart.ticks(x_scale, marks.x_min, marks.x_max, x_ticks[..])
    if x_error != ok { ret x_error }
    let (_, y_error) = chart.ticks(y_scale, marks.y_min, marks.y_max, y_ticks[..])
    if y_error != ok { ret y_error }
    try chart_svg.append_guides(&writer, geometry.rect(44.0, 30.0, 286.0, 174.0), x_ticks[..], y_ticks[..], paint.rgba(0.88, 0.91, 0.95, 1.0), paint.rgba(0.32, 0.38, 0.48, 1.0))
    var ink = paint.rgba(0.07, 0.35, 0.76, 1.0)
    if marks.kind == .Area { ink = paint.rgba(0.25, 0.55, 0.88, 0.82) }
    try chart_svg.append(&writer, marks, ink)
    try chart_svg.finish(&writer)
    let (path, path_error) = vector_path(a, png_path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, path, io.memory_bytes(&state))
}

fn export_svg_matrix(a: *mem.Arena, marks: *const chart.MatrixLayout, png_path: str) -> err {
    let (held, start_error) = svg_start(a, png_path)
    if start_error != ok { ret start_error }
    var state = held
    var writer = io.writer(mem.cast[*void](&state), io.memory_write)
    try chart_svg.append_matrix(&writer, marks, paint.rgba(0.11, 0.30, 0.72, 1.0), paint.rgba(0.97, 0.97, 0.94, 1.0), paint.rgba(0.93, 0.28, 0.12, 1.0))
    try chart_svg.finish(&writer)
    let (path, path_error) = vector_path(a, png_path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, path, io.memory_bytes(&state))
}

fn render_chart_scaled(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, marks: *const chart.Layout, x_scale: chart.Scale, y_scale: chart.Scale, path: str) -> err {
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let white = paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) }
    let grid = paint.Brush { Solid: paint.rgba(0.88, 0.91, 0.95, 1.0) }
    let axis = paint.Brush { Solid: paint.rgba(0.32, 0.38, 0.48, 1.0) }
    var ink = paint.Brush { Solid: paint.rgba(0.07, 0.35, 0.76, 1.0) }
    if marks.kind == .Area { ink = paint.Brush { Solid: paint.rgba(0.25, 0.55, 0.88, 0.82) } }
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), white)
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [4]chart.Tick = zero
    let (_, x_error) = chart.ticks(x_scale, marks.x_min, marks.x_max, x_ticks[..])
    if x_error != ok { ret x_error }
    let (_, y_error) = chart.ticks(y_scale, marks.y_min, marks.y_max, y_ticks[..])
    if y_error != ok { ret y_error }
    try chart_scene.append_guides(&builder, geometry.rect(44.0, 30.0, 286.0, 174.0), x_ticks[..], y_ticks[..], grid, axis)
    try chart_scene.append(a, &builder, marks, ink)
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    ret export_svg_chart(a, marks, x_scale, y_scale, path)
}

fn render_chart(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, marks: *const chart.Layout, path: str) -> err {
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    ret render_chart_scaled(a, q, output_target, canvas, renderer, marks, linear, linear, path)
}

fn render_matrix(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, marks: *const chart.MatrixLayout, path: str) -> err {
    let (made, builder_error) = scene.builder(a, marks.cells.len + 1usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_matrix(&builder, marks, paint.rgba(0.11, 0.30, 0.72, 1.0), paint.rgba(0.97, 0.97, 0.94, 1.0), paint.rgba(0.93, 0.28, 0.12, 1.0))
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    ret export_svg_matrix(a, marks, path)
}

// Top row shares both data domains; bottom row lets each facet use its own.
fn render_facet_scales(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/facet_scales.png"
    var panels: [4]geometry.Rect = zero
    let (placed, panel_error) = chart.facet_grid(geometry.rect(32.0, 20.0, 296.0, 202.0), 2usize, 4usize, 14.0, panels[..])
    if panel_error != ok { ret panel_error }
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    let white = paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) }
    let grid_color = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let ink_color = paint.rgba(0.07, 0.35, 0.76, 1.0)
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), white)
    let low = [3]f32{ 0.0, 0.5, 1.0 }
    let high = [3]f32{ 10.0, 10.5, 11.0 }
    let common = [2]f32{ 0.0, 11.0 }
    var points: [3]chart.Coord = zero
    var lines: [2]chart.Segment = zero
    var bars: [3]geometry.Rect = zero
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var i = 0usize
    while i < placed.len {
        var values: []const f32 = low[..]
        if i % 2usize == 1usize { values = high[..] }
        var limits: []const f32 = low[..0usize]
        if i < 2usize { limits = common[..] }
        let plot = chart.spec(.Scatter, placed[i], values, values)
        let (marks, marks_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], limits, limits)
        if marks_error != ok { ret marks_error }
        var x_ticks: [2]chart.Tick = zero
        var y_ticks: [2]chart.Tick = zero
        let (_, x_error) = chart.ticks(linear, marks.x_min, marks.x_max, x_ticks[..])
        if x_error != ok { ret x_error }
        let (_, y_error) = chart.ticks(linear, marks.y_min, marks.y_max, y_ticks[..])
        if y_error != ok { ret y_error }
        try chart_scene.append_guides(&builder, placed[i], x_ticks[..], y_ticks[..], paint.Brush { Solid: grid_color }, paint.Brush { Solid: axis_color })
        try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink_color })
        try chart_svg.append_guides(&writer, placed[i], x_ticks[..], y_ticks[..], grid_color, axis_color)
        try chart_svg.append(&writer, &marks, ink_color)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    try fs.write_file(a, "docs/chart-previews/facet_scales.svg", io.memory_bytes(&svg_state))
    ret render_builder(a, q, output_target, canvas, renderer, &builder, path)
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
    var points: [16]chart.Coord = zero
    var segments: [14]chart.Segment = zero
    var bars: [8]geometry.Rect = zero
    let bounds = geometry.rect(44.0, 30.0, 286.0, 174.0)
    let kinds = [6]chart.Kind{ .Scatter, .Line, .Bar, .Step, .Area, .Lollipop }
    let paths = [6]str{ "docs/chart-previews/scatter.png", "docs/chart-previews/line.png", "docs/chart-previews/bar.png", "docs/chart-previews/step.png", "docs/chart-previews/area.png", "docs/chart-previews/lollipop.png" }
    var i = 0usize
    while i < kinds.len {
        var spec = chart.spec(kinds[i], bounds, x[..], y[..])
        let (marks, layout_error) = chart.layout(&spec, points[..], segments[..], bars[..])
        if layout_error != ok { ret layout_error }
        try render_chart(a, queue, output_target, canvas, &renderer, &marks, paths[i])
        i += 1usize
    }
    let log_x = [8]f32{ 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 1000.0 }
    let log_y = [8]f32{ 1.0, 3.0, 5.0, 10.0, 25.0, 40.0, 80.0, 100.0 }
    var log_plot = chart.spec(.Scatter, bounds, log_x[..], log_y[..])
    log_plot.x_scale = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    log_plot.y_scale = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    let (log_marks, log_error) = chart.layout(&log_plot, points[..], segments[..], bars[..])
    if log_error != ok { ret log_error }
    try render_chart_scaled(a, queue, output_target, canvas, &renderer, &log_marks, log_plot.x_scale, log_plot.y_scale, "docs/chart-previews/log_scatter.png")
    let symmetric_y = [8]f32{ -100.0, -30.0, -10.0, -1.0, 1.0, 10.0, 30.0, 100.0 }
    var symmetric_plot = chart.spec(.Line, bounds, x[..], symmetric_y[..])
    symmetric_plot.y_scale = chart.Scale { kind: .Symlog, reverse: false, linthresh: 5.0 }
    let (symmetric_marks, symmetric_error) = chart.layout(&symmetric_plot, points[..], segments[..], bars[..])
    if symmetric_error != ok { ret symmetric_error }
    try render_chart_scaled(a, queue, output_target, canvas, &renderer, &symmetric_marks, symmetric_plot.x_scale, symmetric_plot.y_scale, "docs/chart-previews/symlog_line.png")
    let lower = [8]f32{ 0.0, 2.0, 1.5, 4.0, 2.0, 3.0, 0.5, 5.0 }
    let upper = [8]f32{ 2.0, 6.0, 5.0, 7.0, 6.0, 7.0, 4.0, 8.0 }
    var interval_points: [8]chart.Coord = zero
    var interval_lines: [24]chart.Segment = zero
    let (intervals, interval_error) = chart.error_bars(x[..], y[..], lower[..], upper[..], bounds, interval_points[..], interval_lines[..])
    if interval_error != ok { ret interval_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &intervals, "docs/chart-previews/errorbar.png")
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
    let tile_values = [36]f64{
        0.0, 1.0, 2.0, 3.0, 2.0, 1.0,
        1.0, 2.0, 4.0, 6.0, 4.0, 2.0,
        2.0, 4.0, 7.0, 9.0, 7.0, 3.0,
        2.0, 5.0, 8.0, 10.0, 6.0, 2.0,
        1.0, 3.0, 5.0, 6.0, 4.0, 1.0,
        0.0, 1.0, 2.0, 3.0, 1.0, 0.0,
    }
    var tile_cells: [36]chart.Cell = zero
    let (tiles, tile_error) = chart.heatmap(tile_values[..], 6usize, bounds, tile_cells[..])
    if tile_error != ok { ret tile_error }
    try render_matrix(a, queue, output_target, canvas, &renderer, &tiles, "docs/chart-previews/heatmap.png")
    let observations = [24]f64{
        1.0, 1.5, 9.0, 4.0,
        2.0, 2.1, 8.0, 7.0,
        3.0, 3.7, 7.0, 3.0,
        4.0, 3.8, 6.0, 8.0,
        5.0, 5.1, 5.0, 2.0,
        6.0, 6.4, 4.0, 5.0,
    }
    var corr_x: [6]f64 = zero
    var corr_y: [6]f64 = zero
    var corr_cells: [16]chart.Cell = zero
    let (corr, corr_error) = chart.correlation_matrix(observations[..], 4usize, bounds, corr_x[..], corr_y[..], corr_cells[..])
    if corr_error != ok { ret corr_error }
    try render_matrix(a, queue, output_target, canvas, &renderer, &corr, "docs/chart-previews/correlation.png")
    var panels: [4]geometry.Rect = zero
    let (facet_bounds, facet_error) = chart.facet_grid(bounds, 2usize, 4usize, 12.0, panels[..])
    if facet_error != ok { ret facet_error }
    let facet_values = [36]f64{
        0.0, 1.0, 2.0, 1.0, 3.0, 4.0, 2.0, 4.0, 6.0,
        4.0, 3.0, 2.0, 3.0, 5.0, 3.0, 2.0, 3.0, 4.0,
        6.0, 4.0, 2.0, 4.0, 3.0, 1.0, 2.0, 1.0, 0.0,
        1.0, 4.0, 1.0, 4.0, 8.0, 4.0, 1.0, 4.0, 1.0,
    }
    var facet_cells: [36]chart.Cell = zero
    let (made_facet, made_facet_error) = scene.builder(a, 40usize)
    if made_facet_error != ok { ret made_facet_error }
    var facet_builder = made_facet
    try fill(&facet_builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < 4usize {
        let start = i * 9usize
        let (panel, panel_error) = chart.heatmap(facet_values[start..start + 9usize], 3usize, facet_bounds[i], facet_cells[start..start + 9usize])
        if panel_error != ok { ret panel_error }
        try chart_scene.append_matrix(&facet_builder, &panel, paint.rgba(0.11, 0.30, 0.72, 1.0), paint.rgba(0.97, 0.97, 0.94, 1.0), paint.rgba(0.93, 0.28, 0.12, 1.0))
        i += 1usize
    }
    try render_builder(a, queue, output_target, canvas, &renderer, &facet_builder, "docs/chart-previews/facet_heatmap.png")
    let (facet_svg_state, facet_svg_error) = svg_start(a, "docs/chart-previews/facet_heatmap.png")
    if facet_svg_error != ok { ret facet_svg_error }
    var facet_svg_held = facet_svg_state
    var facet_svg_writer = io.writer(mem.cast[*void](&facet_svg_held), io.memory_write)
    i = 0usize
    while i < 4usize {
        let start = i * 9usize
        let (panel, panel_error) = chart.heatmap(facet_values[start..start + 9usize], 3usize, facet_bounds[i], facet_cells[start..start + 9usize])
        if panel_error != ok { ret panel_error }
        try chart_svg.append_matrix(&facet_svg_writer, &panel, paint.rgba(0.11, 0.30, 0.72, 1.0), paint.rgba(0.97, 0.97, 0.94, 1.0), paint.rgba(0.93, 0.28, 0.12, 1.0))
        i += 1usize
    }
    try chart_svg.finish(&facet_svg_writer)
    try fs.write_file(a, "docs/chart-previews/facet_heatmap.svg", io.memory_bytes(&facet_svg_held))
    try render_facet_scales(a, queue, output_target, canvas, &renderer)
    try scene.close(&renderer)
    try gpu.close_target(output_target)
    try gpu.close(device)
    try io.print("chart previews ok\n")
    ret ok
}
