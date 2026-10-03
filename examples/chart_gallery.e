// Render the currently delivered chart kinds through Neper's CPU scene and PNG encoder.
// From the repository root, run this executable to refresh docs/chart-previews/*.png.
use e.algo.stat
use e.fs
use e.gpu
use e.io
use e.math
use e.mem
use e.str
use e.fmt.png
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.text.layout as text_layout

const WIDTH: u32 = 360u32
const HEIGHT: u32 = 240u32

fn fill(builder: *scene.Builder, rect: geometry.Rect, brush: paint.Brush) -> err {
    ret scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: rect, brush: brush } })
}

fn render_builder(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, builder: *scene.Builder, path: str) -> err {
    let (view, view_error) = chart_scene.rasterize(a, q, output_target, canvas, renderer, builder, WIDTH, HEIGHT)
    if view_error != ok { ret view_error }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try png.encode(&writer, view, png.EncodeOptions { compression: .Fast, interlace: false })
    ret fs.write_file(a, path, io.memory_bytes(&held))
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
    var y_guides = y_ticks[..]
    if marks.kind == .Rug || marks.kind == .Strip || marks.kind == .Beeswarm || marks.kind == .DotPlot { y_guides = y_ticks[..0usize] }
    try chart_svg.append_guides(&writer, geometry.rect(44.0, 30.0, 286.0, 174.0), x_ticks[..], y_guides, paint.rgba(0.88, 0.91, 0.95, 1.0), paint.rgba(0.32, 0.38, 0.48, 1.0))
    var ink = paint.rgba(0.07, 0.35, 0.76, 1.0)
    if marks.kind == .Area || marks.kind == .Band { ink = paint.rgba(0.25, 0.55, 0.88, 0.82) }
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
    if marks.kind == .Area || marks.kind == .Band { ink = paint.Brush { Solid: paint.rgba(0.25, 0.55, 0.88, 0.82) } }
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), white)
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [4]chart.Tick = zero
    let (_, x_error) = chart.ticks(x_scale, marks.x_min, marks.x_max, x_ticks[..])
    if x_error != ok { ret x_error }
    let (_, y_error) = chart.ticks(y_scale, marks.y_min, marks.y_max, y_ticks[..])
    if y_error != ok { ret y_error }
    var y_guides = y_ticks[..]
    if marks.kind == .Rug || marks.kind == .Strip || marks.kind == .Beeswarm || marks.kind == .DotPlot { y_guides = y_ticks[..0usize] }
    try chart_scene.append_guides(&builder, geometry.rect(44.0, 30.0, 286.0, 174.0), x_ticks[..], y_guides, grid, axis)
    try chart_scene.append(a, &builder, marks, ink)
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    ret export_svg_chart(a, marks, x_scale, y_scale, path)
}

fn render_chart(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, marks: *const chart.Layout, path: str) -> err {
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    ret render_chart_scaled(a, q, output_target, canvas, renderer, marks, linear, linear, path)
}

fn render_scatter_overlay(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, dots: *const chart.Layout, overlay: *const chart.Layout, underlays: []const chart.Layout, path: str) -> err {
    let plot = geometry.rect(44.0, 30.0, 286.0, 174.0)
    let grid = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let axis = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let blue = paint.rgba(0.07, 0.35, 0.76, 1.0)
    let orange = paint.rgba(0.94, 0.42, 0.12, 1.0)
    let pale = paint.rgba(0.75, 0.85, 0.96, 1.0)
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [4]chart.Tick = zero
    let (_, x_error) = chart.ticks(linear, overlay.x_min, overlay.x_max, x_ticks[..])
    if x_error != ok { ret x_error }
    let (_, y_error) = chart.ticks(linear, overlay.y_min, overlay.y_max, y_ticks[..])
    if y_error != ok { ret y_error }
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: axis })
    var i = 0usize
    while i < underlays.len {
        try chart_scene.append(a, &builder, &underlays[i], paint.Brush { Solid: pale })
        i += 1usize
    }
    try chart_scene.append(a, &builder, dots, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, overlay, paint.Brush { Solid: orange })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, axis)
    i = 0usize
    while i < underlays.len {
        try chart_svg.append(&writer, &underlays[i], pale)
        i += 1usize
    }
    try chart_svg.append(&writer, dots, blue)
    try chart_svg.append(&writer, overlay, orange)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_ridgelines(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, names: []const str, path: str) -> err {
    if layers.len != 3usize || names.len != layers.len { ret chart.Invalid }
    let plot = geometry.rect(44.0, 30.0, 286.0, 174.0)
    let grid_color = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let colors = [3]paint.Color{ paint.rgba(0.07, 0.35, 0.76, 0.86), paint.rgba(0.22, 0.65, 0.48, 0.86), paint.rgba(0.94, 0.42, 0.12, 0.86) }
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_ticks: [4]chart.Tick = zero
    let (ticks, tick_error) = chart.nice_ticks(linear, layers[0usize].x_min, layers[0usize].x_max, 4usize, x_ticks[..])
    if tick_error != ok { ret tick_error }
    var tick_words: [4]str = zero
    var tick_text: [128]u8 = zero
    let (words, words_error) = chart.format_ticks(ticks, tick_words[..], tick_text[..])
    if words_error != ok { ret words_error }
    var labels: [8]chart.Label = zero
    let (_, labels_error) = chart.guide_labels(plot, ticks, words, x_ticks[..0usize], words[..0usize], 9.0, labels[..ticks.len])
    if labels_error != ok { ret labels_error }
    var i = 0usize
    while i < layers.len {
        labels[ticks.len + i] = chart.Label { text: names[i], anchor: chart.Coord { x: plot.x - 6.0, y: layers[i].coords[0usize].y + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[ticks.len + layers.len] = chart.Label { text: "Shared-scale ridgeline density", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, ticks, x_ticks[..0usize], paint.Brush { Solid: grid_color }, paint.Brush { Solid: axis_color })
    i = layers.len
    while i > 0usize {
        i -= 1usize
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
    }
    try chart_scene.append_labels(a, &builder, labels[..ticks.len + layers.len], font, 9.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, labels[ticks.len + layers.len..ticks.len + layers.len + 1usize], font, 11.0, paint.Brush { Solid: axis_color })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, ticks, x_ticks[..0usize], grid_color, axis_color)
    i = layers.len
    while i > 0usize {
        i -= 1usize
        try chart_svg.append(&writer, &layers[i], colors[i])
    }
    try chart_svg.append_labels(&writer, labels[..ticks.len + layers.len], axis_color, 9.0)
    try chart_svg.append_labels(&writer, labels[ticks.len + layers.len..ticks.len + layers.len + 1usize], axis_color, 11.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_financial(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, title: str, path: str) -> err {
    if layers.len != 1usize && layers.len != 3usize { ret chart.Invalid }
    let plot = geometry.rect(44.0, 30.0, 286.0, 174.0)
    let grid_color = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let colors = [3]paint.Color{ paint.rgba(0.22, 0.27, 0.35, 1.0), paint.rgba(0.11, 0.63, 0.44, 1.0), paint.rgba(0.91, 0.28, 0.25, 1.0) }
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_storage: [5]chart.Tick = zero
    var y_storage: [5]chart.Tick = zero
    let (x_ticks, x_error) = chart.nice_ticks(linear, layers[0usize].x_min, layers[0usize].x_max, 5usize, x_storage[..])
    if x_error != ok { ret x_error }
    let (y_ticks, y_error) = chart.nice_ticks(linear, layers[0usize].y_min, layers[0usize].y_max, 5usize, y_storage[..])
    if y_error != ok { ret y_error }
    var x_words: [5]str = zero
    var y_words: [5]str = zero
    var x_text: [128]u8 = zero
    var y_text: [128]u8 = zero
    let (x_labels, x_label_error) = chart.format_ticks(x_ticks, x_words[..], x_text[..])
    if x_label_error != ok { ret x_label_error }
    let (y_labels, y_label_error) = chart.format_ticks(y_ticks, y_words[..], y_text[..])
    if y_label_error != ok { ret y_label_error }
    var label_storage: [11]chart.Label = zero
    let (labels, labels_error) = chart.guide_labels(plot, x_ticks, x_labels, y_ticks, y_labels, 9.0, label_storage[..10usize])
    if labels_error != ok { ret labels_error }
    label_storage[labels.len] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, x_ticks, y_ticks, paint.Brush { Solid: grid_color }, paint.Brush { Solid: axis_color })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels, font, 9.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, label_storage[labels.len..labels.len + 1usize], font, 11.0, paint.Brush { Solid: axis_color })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, x_ticks, y_ticks, grid_color, axis_color)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels, axis_color, 9.0)
    try chart_svg.append_labels(&writer, label_storage[labels.len..labels.len + 1usize], axis_color, 11.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_finance_panels(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, top: *const chart.Layout, bottom: *const chart.Layout, top_bounds: geometry.Rect, bottom_bounds: geometry.Rect, title: str, top_name: str, bottom_name: str, path: str) -> err {
    let blue = paint.rgba(0.08, 0.39, 0.76, 1.0)
    let green = paint.rgba(0.07, 0.55, 0.43, 1.0)
    let pale = paint.rgba(0.97, 0.98, 0.99, 1.0)
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let labels = [4]chart.Label{
        chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: top_name, anchor: chart.Coord { x: top_bounds.x, y: top_bounds.y - 3.0 }, align: .Left },
        chart.Label { text: bottom_name, anchor: chart.Coord { x: bottom_bounds.x, y: bottom_bounds.y - 3.0 }, align: .Left },
        chart.Label { text: "Observation", anchor: chart.Coord { x: 180.0, y: 237.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, top_bounds, paint.Brush { Solid: pale })
    try fill(&builder, bottom_bounds, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, top, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, bottom, paint.Brush { Solid: green })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: axis })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, top_bounds, pale, false)
    try chart_svg.rect(&writer, bottom_bounds, pale, false)
    try chart_svg.append(&writer, top, blue)
    try chart_svg.append(&writer, bottom, green)
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_finance_panel_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let plot = geometry.rect(53.0, 43.0, 270.0, 169.0)
    let x = [10]f32{ 1.0, 2.0, 3.0, 5.0, 6.0, 8.0, 9.0, 10.0, 12.0, 13.0 }
    let prices = [10]f32{ 100.0, 104.0, 101.0, 109.0, 108.0, 115.0, 111.0, 120.0, 118.0, 126.0 }
    let volumes = [10]f32{ 35.0, 50.0, 42.0, 70.0, 49.0, 95.0, 80.0, 120.0, 75.0, 135.0 }
    var price_segments: [9]chart.Segment = zero
    var volume_bars: [10]geometry.Rect = zero
    let (price, volume, price_error) = chart.price_volume(x[..], prices[..], volumes[..], plot, 10.0, price_segments[..], volume_bars[..])
    if price_error != ok { ret price_error }
    let volume_height = (plot.height - 10.0) * 0.34
    let price_height = plot.height - 10.0 - volume_height
    let price_bounds = geometry.rect(plot.x, plot.y, plot.width, price_height)
    let volume_bounds = geometry.rect(plot.x, plot.y + price_height + 10.0, plot.width, volume_height)
    try render_finance_panels(a, q, output_target, canvas, renderer, &price, &volume, price_bounds, volume_bounds, "Price and volume", "Close", "Volume", "docs/chart-previews/price_volume.png")

    let time = [12]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0 }
    let history = [12]f32{ 100.0, 108.0, 103.0, 112.0, 107.0, 117.0, 114.0, 123.0, 116.0, 128.0, 122.0, 135.0 }
    var returns: [11]f32 = zero
    var volatility: [9]f32 = zero
    var return_segments: [10]chart.Segment = zero
    var volatility_segments: [8]chart.Segment = zero
    let (return_marks, volatility_marks, returns_error) = chart.returns_volatility(time[..], history[..], 3usize, plot, 10.0, returns[..], volatility[..], return_segments[..], volatility_segments[..])
    if returns_error != ok { ret returns_error }
    var panels: [2]geometry.Rect = zero
    let (_, panel_error) = chart.facet_grid(plot, 1usize, 2usize, 10.0, panels[..])
    if panel_error != ok { ret panel_error }
    ret render_finance_panels(a, q, output_target, canvas, renderer, &return_marks, &volatility_marks, panels[0usize], panels[1usize], "Returns and rolling volatility", "Simple return", "Rolling SD (3)", "docs/chart-previews/returns_volatility.png")
}

fn render_bar_layers(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, categories: []const str, names: []const str, title: str, path: str) -> err {
    if layers.len != 2usize || names.len != layers.len { ret chart.Invalid }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let colors = [2]paint.Color{ paint.rgba(0.07, 0.35, 0.76, 1.0), paint.rgba(0.94, 0.42, 0.12, 1.0) }
    let grid_color = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let plot = geometry.rect(48.0, 42.0, 228.0, 140.0)
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [5]chart.Tick = zero
    let (x_breaks, x_error) = chart.category_ticks(categories.len, x_ticks[..])
    if x_error != ok { ret x_error }
    let (y_breaks, y_error) = chart.nice_ticks(linear, layers[0].y_min, layers[0].y_max, 5usize, y_ticks[..])
    if y_error != ok { ret y_error }
    var y_text: [5]str = zero
    var y_storage: [128]u8 = zero
    let (y_words, text_error) = chart.format_ticks(y_breaks, y_text[..], y_storage[..])
    if text_error != ok { ret text_error }
    var labels: [10]chart.Label = zero
    let (guides, label_error) = chart.guide_labels(plot, x_breaks, categories, y_breaks, y_words, 9.0, labels[..9usize])
    if label_error != ok { ret label_error }
    labels[guides.len] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    var legend: [2]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(names, chart.Coord { x: 284.0, y: 64.0 }, 10.0, 23.0, legend[..])
    if legend_error != ok { ret legend_error }
    var legend_labels: [2]chart.Label = zero
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, x_breaks, y_breaks, paint.Brush { Solid: grid_color }, paint.Brush { Solid: axis_color })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: colors[i] })
        legend_labels[i] = entries[i].label
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, guides, font, 9.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, labels[guides.len..guides.len + 1usize], font, 13.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, legend_labels[..], font, 9.0, paint.Brush { Solid: axis_color })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, x_breaks, y_breaks, grid_color, axis_color)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        try chart_svg.rect(&writer, entries[i].swatch, colors[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, guides, axis_color, 9.0)
    try chart_svg.append_labels(&writer, labels[guides.len..guides.len + 1usize], axis_color, 13.0)
    try chart_svg.append_labels(&writer, legend_labels[..], axis_color, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_state_timeline(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, state_ids: []usize, row_names: []const str, state_names: []const str, colors: []const paint.Color, title: str, path: str) -> err {
    if row_names.len != 4usize || state_names.len != 3usize || colors.len != state_names.len || state_ids.len < layers.len { ret chart.Invalid }
    let plot = geometry.rect(68.0, 54.0, 188.0, 148.0)
    let lane_height = (plot.height - 3.0 * 4.0) / 4.0
    let pale = paint.rgba(0.93, 0.95, 0.97, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var legend: [3]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(state_names, chart.Coord { x: 268.0, y: 69.0 }, 10.0, 34.0, legend[..])
    if legend_error != ok { ret legend_error }
    var labels: [12]chart.Label = zero
    var i = 0usize
    while i < 4usize {
        labels[i] = chart.Label { text: row_names[i], anchor: chart.Coord { x: 60.0, y: plot.y + f32(i) * (lane_height + 4.0) + lane_height * 0.5 + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        labels[4usize + i] = entries[i].label
        i += 1usize
    }
    let ticks = [4]str{ "0", "4", "8", "12" }
    i = 0usize
    while i < 4usize {
        labels[7usize + i] = chart.Label { text: ticks[i], anchor: chart.Coord { x: plot.x + plot.width * f32(i) / 3.0, y: 220.0 }, align: .Center }
        i += 1usize
    }
    labels[11usize] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < 4usize {
        try fill(&builder, geometry.rect(plot.x, plot.y + f32(i) * (lane_height + 4.0), plot.width, lane_height), paint.Brush { Solid: pale })
        i += 1usize
    }
    i = 0usize
    while i < layers.len {
        if state_ids[i] >= colors.len { ret chart.Invalid }
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[state_ids[i]] })
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..11usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[11usize..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 4usize {
        try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + f32(i) * (lane_height + 4.0), plot.width, lane_height), pale, false)
        i += 1usize
    }
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[state_ids[i]])
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try chart_svg.rect(&writer, entries[i].swatch, colors[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..11usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[11usize..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_sparklines(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/sparkline.png"
    let samples = [32]f32{ 2.0, 3.0, 4.0, 4.0, 5.0, 7.0, 6.0, 9.0, 7.0, 6.0, 7.0, 5.0, 4.0, 5.0, 3.0, 3.0, 3.0, 4.0, 3.0, 6.0, 5.0, 7.0, 8.0, 8.0, 7.0, 7.0, 6.0, 6.0, 5.0, 5.0, 4.0, 3.0 }
    let names = [4]str{ "Sales", "Costs", "Visits", "Churn" }
    let colors = [4]paint.Color{ paint.rgba(0.07, 0.38, 0.76, 1.0), paint.rgba(0.86, 0.39, 0.17, 1.0), paint.rgba(0.15, 0.60, 0.46, 1.0), paint.rgba(0.48, 0.35, 0.72, 1.0) }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let pale = paint.rgba(0.95, 0.96, 0.98, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var labels: [5]chart.Label = zero
    var x: [8]f32 = zero
    var segments: [7]chart.Segment = zero
    var i = 0usize
    while i < 4usize {
        let box = geometry.rect(120.0, 48.0 + f32(i) * 43.0, 192.0, 29.0)
        let row = geometry.rect(110.0, box.y - 5.0, 212.0, 39.0)
        try fill(&builder, row, paint.Brush { Solid: pale })
        let (marks, marks_error) = chart.sparkline(samples[i * 8usize..i * 8usize + 8usize], box, x[..], segments[..])
        if marks_error != ok { ret marks_error }
        try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: colors[i] })
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: 99.0, y: box.y + 19.0 }, align: .Right }
        i += 1usize
    }
    labels[4usize] = chart.Label { text: "In-cell sparklines", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    try chart_scene.append_labels(a, &builder, labels[..4usize], font, 10.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 4usize {
        let box = geometry.rect(120.0, 48.0 + f32(i) * 43.0, 192.0, 29.0)
        try chart_svg.rect(&writer, geometry.rect(110.0, box.y - 5.0, 212.0, 39.0), pale, false)
        let (marks, marks_error) = chart.sparkline(samples[i * 8usize..i * 8usize + 8usize], box, x[..], segments[..])
        if marks_error != ok { ret marks_error }
        try chart_svg.append(&writer, &marks, colors[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..4usize], dark, 10.0)
    try chart_svg.append_labels(&writer, labels[4usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_calendar_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/calendar_heatmap.png"
    let plot = geometry.rect(62.0, 55.0, 252.0, 147.0)
    let first_weekday = 5usize
    let pale = paint.rgba(0.92, 0.94, 0.97, 1.0)
    let low = paint.rgba(0.75, 0.86, 0.97, 1.0)
    let high = paint.rgba(0.06, 0.38, 0.72, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var days: [31]chart.CalendarDay = zero
    var count = 0usize
    var day = 0usize
    while day < 31usize {
        if day != 5usize && day != 14usize && day != 22usize {
            days[count] = chart.CalendarDay { offset: day, value: f64((day * 7usize + 3usize) % 13usize) }
            count += 1usize
        }
        day += 1usize
    }
    var cells: [31]chart.Cell = zero
    let (marks, marks_error) = chart.calendar_heatmap(days[..count], 31usize, first_weekday, plot, 3.0, cells[..])
    if marks_error != ok { ret marks_error }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    day = 0usize
    while day < 31usize {
        let slot = first_weekday + day
        let tile = geometry.rect(plot.x + f32(slot / 7usize) * 42.0 + 1.5, plot.y + f32(slot % 7usize) * 21.0 + 1.5, 39.0, 18.0)
        try fill(&builder, tile, paint.Brush { Solid: pale })
        day += 1usize
    }
    try chart_scene.append_matrix(&builder, &marks, low, low, high)
    let weekdays = [7]str{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
    let weeks = [6]str{ "W1", "W2", "W3", "W4", "W5", "W6" }
    var labels: [14]chart.Label = zero
    var i = 0usize
    while i < 7usize {
        labels[i] = chart.Label { text: weekdays[i], anchor: chart.Coord { x: 53.0, y: plot.y + f32(i) * 21.0 + 14.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < 6usize {
        labels[7usize + i] = chart.Label { text: weeks[i], anchor: chart.Coord { x: plot.x + f32(i) * 42.0 + 21.0, y: 221.0 }, align: .Center }
        i += 1usize
    }
    labels[13usize] = chart.Label { text: "Calendar heatmap", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    try chart_scene.append_labels(a, &builder, labels[..13usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    day = 0usize
    while day < 31usize {
        let slot = first_weekday + day
        let tile = geometry.rect(plot.x + f32(slot / 7usize) * 42.0 + 1.5, plot.y + f32(slot % 7usize) * 21.0 + 1.5, 39.0, 18.0)
        try chart_svg.rect(&writer, tile, pale, false)
        day += 1usize
    }
    try chart_svg.append_matrix(&writer, &marks, low, low, high)
    try chart_svg.append_labels(&writer, labels[..13usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[13usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_risk_matrix_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/risk_matrix.png"
    let plot = geometry.rect(78.0, 47.0, 215.0, 160.0)
    var ratings: [25]f64 = zero
    var row = 0usize
    while row < 5usize {
        var col = 0usize
        while col < 5usize {
            ratings[row * 5usize + col] = f64((5usize - row) * (col + 1usize))
            col += 1usize
        }
        row += 1usize
    }
    let risks = [11]chart.RiskPoint{
        chart.RiskPoint { likelihood: 1usize, impact: 5usize },
        chart.RiskPoint { likelihood: 2usize, impact: 4usize },
        chart.RiskPoint { likelihood: 2usize, impact: 4usize },
        chart.RiskPoint { likelihood: 4usize, impact: 4usize },
        chart.RiskPoint { likelihood: 4usize, impact: 4usize },
        chart.RiskPoint { likelihood: 4usize, impact: 4usize },
        chart.RiskPoint { likelihood: 5usize, impact: 3usize },
        chart.RiskPoint { likelihood: 3usize, impact: 2usize },
        chart.RiskPoint { likelihood: 2usize, impact: 1usize },
        chart.RiskPoint { likelihood: 5usize, impact: 1usize },
        chart.RiskPoint { likelihood: 5usize, impact: 1usize },
    }
    var counts: [25]u64 = zero
    var cells: [25]chart.Cell = zero
    let (marks, marks_error) = chart.risk_matrix(risks[..], ratings[..], 5usize, plot, counts[..], cells[..])
    if marks_error != ok { ret marks_error }
    let low = paint.rgba(0.82, 0.93, 0.75, 1.0)
    let high = paint.rgba(0.96, 0.52, 0.39, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let digits = [5]str{ "1", "2", "3", "4", "5" }
    let count_words = [4]str{ "", "1", "2", "3" }
    var labels: [25]chart.Label = zero
    var used = 0usize
    var i = 0usize
    while i < counts.len {
        if counts[i] > 0u64 {
            if counts[i] >= 4u64 { ret chart.Invalid }
            let tile = cells[i].rect
            labels[used] = chart.Label { text: count_words[usize(counts[i])], anchor: chart.Coord { x: tile.x + tile.width * 0.5, y: tile.y + tile.height * 0.61 }, align: .Center }
            used += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        labels[used + i] = chart.Label { text: digits[4usize - i], anchor: chart.Coord { x: 71.0, y: plot.y + (f32(i) + 0.61) * 32.0 }, align: .Right }
        labels[used + 5usize + i] = chart.Label { text: digits[i], anchor: chart.Coord { x: plot.x + (f32(i) + 0.5) * 43.0, y: 222.0 }, align: .Center }
        i += 1usize
    }
    used += 10usize
    labels[used] = chart.Label { text: "Risk matrix", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_matrix(&builder, &marks, low, low, high)
    try chart_scene.append_labels(a, &builder, labels[..used], font, 10.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[used..used + 1usize], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_matrix(&writer, &marks, low, low, high)
    try chart_svg.append_labels(&writer, labels[..used], dark, 10.0)
    try chart_svg.append_labels(&writer, labels[used..used + 1usize], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_resource_histogram_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/resource_histogram.png"
    let plot = geometry.rect(53.0, 46.0, 263.0, 147.0)
    let spans = [5]chart.ResourceSpan{
        chart.ResourceSpan { start: 0.0f64, end: 4.0f64, units: 2.0f64 },
        chart.ResourceSpan { start: 2.0f64, end: 7.0f64, units: 3.0f64 },
        chart.ResourceSpan { start: 5.0f64, end: 9.0f64, units: 1.5f64 },
        chart.ResourceSpan { start: 8.0f64, end: 12.0f64, units: 2.0f64 },
        chart.ResourceSpan { start: 10.0f64, end: 12.0f64, units: 2.5f64 },
    }
    var edges: [12]f64 = zero
    var loads: [11]f64 = zero
    var normal_bars: [11]geometry.Rect = zero
    var excess_bars: [11]geometry.Rect = zero
    var capacity_rule: [1]chart.Segment = zero
    let (normal, excess, limit, layout_error) = chart.resource_histogram(spans[..], 0.0f64, 12.0f64, 3.0f64, plot, edges[..], loads[..], normal_bars[..], excess_bars[..], capacity_rule[..])
    if layout_error != ok { ret layout_error }
    let blue = paint.rgba(0.11, 0.42, 0.78, 1.0)
    let red = paint.rgba(0.85, 0.22, 0.18, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let ticks_x = [7]str{ "0", "2", "4", "6", "8", "10", "12" }
    let ticks_y = [6]str{ "0", "1", "2", "3", "4", "5" }
    var labels: [18]chart.Label = zero
    var i = 0usize
    while i < 7usize {
        labels[i] = chart.Label { text: ticks_x[i], anchor: chart.Coord { x: plot.x + plot.width * f32(i) / 6.0, y: 209.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < 6usize {
        labels[7usize + i] = chart.Label { text: ticks_y[i], anchor: chart.Coord { x: 45.0, y: plot.y + plot.height - plot.height * f32(i) / 5.0 + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[13usize] = chart.Label { text: "Resource histogram", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[14usize] = chart.Label { text: "Cap 3", anchor: chart.Coord { x: 312.0, y: limit.segments[0usize].from.y + 13.0 }, align: .Right }
    labels[15usize] = chart.Label { text: "Assigned", anchor: chart.Coord { x: 91.0, y: 233.0 }, align: .Left }
    labels[16usize] = chart.Label { text: "Excess", anchor: chart.Coord { x: 211.0, y: 233.0 }, align: .Left }
    let normal_swatch = geometry.rect(74.0, 225.0, 11.0, 10.0)
    let excess_swatch = geometry.rect(194.0, 225.0, 11.0, 10.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append(a, &builder, &normal, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &excess, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &limit, paint.Brush { Solid: red })
    try fill(&builder, normal_swatch, paint.Brush { Solid: blue })
    try fill(&builder, excess_swatch, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..13usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[14usize..15usize], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[15usize..17usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..14usize], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &normal, blue)
    try chart_svg.append(&writer, &excess, red)
    try chart_svg.append(&writer, &limit, red)
    try chart_svg.rect(&writer, normal_swatch, blue, false)
    try chart_svg.rect(&writer, excess_swatch, red, false)
    try chart_svg.append_labels(&writer, labels[..13usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[14usize..15usize], white, 9.0)
    try chart_svg.append_labels(&writer, labels[15usize..17usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[13usize..14usize], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_swimlane_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/swimlane.png"
    let plot = geometry.rect(82.0, 49.0, 248.0, 150.0)
    let steps = [4]chart.SwimlaneStep{
        chart.SwimlaneStep { lane: 0usize, stage: 0usize },
        chart.SwimlaneStep { lane: 1usize, stage: 1usize },
        chart.SwimlaneStep { lane: 1usize, stage: 2usize },
        chart.SwimlaneStep { lane: 2usize, stage: 3usize },
    }
    let links = [3]chart.SwimlaneLink{
        chart.SwimlaneLink { from: 0usize, to: 1usize },
        chart.SwimlaneLink { from: 1usize, to: 2usize },
        chart.SwimlaneLink { from: 2usize, to: 3usize },
    }
    let names = [4]str{ "Intake", "Review", "Approve", "Ship" }
    let lane_names = [3]str{ "Sales", "Risk", "Ops" }
    let band_colors = [3]paint.Color{
        paint.rgba(0.92, 0.96, 1.0, 1.0),
        paint.rgba(0.96, 0.98, 1.0, 1.0),
        paint.rgba(0.92, 0.96, 1.0, 1.0),
    }
    let blue = paint.rgba(0.10, 0.39, 0.73, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var lanes: [3]geometry.Rect = zero
    var boxes: [4]geometry.Rect = zero
    var arrows: [15]chart.Segment = zero
    let (nodes, connectors, layout_error) = chart.swimlane(steps[..], links[..], 3usize, 4usize, plot, lanes[..], boxes[..], arrows[..])
    if layout_error != ok { ret layout_error }
    var labels: [8]chart.Label = zero
    var i = 0usize
    while i < lanes.len {
        labels[i] = chart.Label { text: lane_names[i], anchor: chart.Coord { x: 73.0, y: lanes[i].y + lanes[i].height * 0.5 + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < boxes.len {
        let box = boxes[i]
        labels[3usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: box.x + box.width * 0.5, y: box.y + box.height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[7usize] = chart.Label { text: "Swimlane handoffs", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < lanes.len {
        try fill(&builder, lanes[i], paint.Brush { Solid: band_colors[i] })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &connectors, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &nodes, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..3usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[3usize..7usize], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[7usize..], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < lanes.len {
        try chart_svg.rect(&writer, lanes[i], band_colors[i], false)
        i += 1usize
    }
    try chart_svg.append(&writer, &connectors, dark)
    try chart_svg.append(&writer, &nodes, blue)
    try chart_svg.append_labels(&writer, labels[..3usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[3usize..7usize], white, 9.0)
    try chart_svg.append_labels(&writer, labels[7usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_pert_cpm_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/pert-cpm-network.png"
    let plot = geometry.rect(17.0, 58.0, 326.0, 142.0)
    let activities = [4]chart.CpmActivity{
        chart.CpmActivity { optimistic: 2.0f64, likely: 2.0f64, pessimistic: 2.0f64 },
        chart.CpmActivity { optimistic: 3.0f64, likely: 3.0f64, pessimistic: 3.0f64 },
        chart.CpmActivity { optimistic: 0.0f64, likely: 1.0f64, pessimistic: 2.0f64 },
        chart.CpmActivity { optimistic: 4.0f64, likely: 4.0f64, pessimistic: 4.0f64 },
    }
    let links = [4]chart.CpmDependency{
        chart.CpmDependency { from: 0usize, to: 1usize },
        chart.CpmDependency { from: 0usize, to: 2usize },
        chart.CpmDependency { from: 1usize, to: 3usize },
        chart.CpmDependency { from: 2usize, to: 3usize },
    }
    var timings: [4]chart.CpmTiming = zero
    var indegree: [4]usize = zero
    var head: [4]usize = zero
    var next: [4]usize = zero
    var order: [4]usize = zero
    let work = chart.CpmWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..] }
    let (summary, schedule_error) = chart.pert_cpm_schedule(activities[..], links[..], timings[..], work)
    if schedule_error != ok || summary.duration != 9.0f64 || summary.critical_count != 3usize { ret chart.Invalid }
    var stage_counts: [4]usize = zero
    var stage_used: [4]usize = zero
    var boxes: [4]geometry.Rect = zero
    var arrows: [20]chart.Segment = zero
    var critical_links: [4]bool = zero
    let (nodes, connectors, layout_error) = chart.pert_cpm_network(links[..], timings[..], summary, plot, stage_counts[..], stage_used[..], boxes[..], arrows[..], critical_links[..])
    if layout_error != ok { ret layout_error }
    let red = paint.rgba(0.80, 0.18, 0.19, 1.0)
    let blue = paint.rgba(0.15, 0.42, 0.73, 1.0)
    let gray = paint.rgba(0.59, 0.66, 0.74, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let names = [4]str{ "A / 2d", "B / 3d", "C / 1d", "D / 4d" }
    var labels: [6]chart.Label = zero
    labels[0usize] = chart.Label { text: "PERT / CPM network", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Critical A-B-D: 9d    C slack: 2d", anchor: chart.Coord { x: 180.0, y: 222.0 }, align: .Center }
    var i = 0usize
    while i < boxes.len {
        labels[i + 2usize] = chart.Label { text: names[i], anchor: chart.Coord { x: boxes[i].x + boxes[i].width * 0.5, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &connectors, paint.Brush { Solid: gray })
    i = 0usize
    while i < links.len {
        if critical_links[i] {
            let edge = chart.Layout { kind: .Rug, coords: zero, segments: arrows[i * 5usize..i * 5usize + 5usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            try chart_scene.append(a, &builder, &edge, paint.Brush { Solid: red })
        }
        i += 1usize
    }
    try chart_scene.append(a, &builder, &nodes, paint.Brush { Solid: blue })
    i = 0usize
    while i < boxes.len {
        if timings[i].critical { try fill(&builder, boxes[i], paint.Brush { Solid: red }) }
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..], font, 10.0, paint.Brush { Solid: white })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &connectors, gray)
    i = 0usize
    while i < links.len {
        if critical_links[i] {
            let edge = chart.Layout { kind: .Rug, coords: zero, segments: arrows[i * 5usize..i * 5usize + 5usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            try chart_svg.append(&writer, &edge, red)
        }
        i += 1usize
    }
    try chart_svg.append(&writer, &nodes, blue)
    i = 0usize
    while i < boxes.len {
        if timings[i].critical { try chart_svg.rect(&writer, boxes[i], red, false) }
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[2usize..], white, 10.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_value_stream_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/value-stream-map.png"
    let plot = geometry.rect(18.0, 48.0, 324.0, 162.0)
    let steps = [3]chart.ValueStreamStep{
        chart.ValueStreamStep { process_time: 2.0f64, value_added_time: 1.0f64, wait_before: 0.0f64, good_fraction: 0.98f64 },
        chart.ValueStreamStep { process_time: 5.0f64, value_added_time: 4.0f64, wait_before: 4.0f64, good_fraction: 0.95f64 },
        chart.ValueStreamStep { process_time: 3.0f64, value_added_time: 2.0f64, wait_before: 2.0f64, good_fraction: 0.99f64 },
    }
    var boxes: [3]geometry.Rect = zero
    var arrows: [6]chart.Segment = zero
    var process_bars: [3]geometry.Rect = zero
    var wait_bars: [3]geometry.Rect = zero
    let (map, map_error) = chart.value_stream_map(steps[..], plot, boxes[..], arrows[..], process_bars[..], wait_bars[..])
    if map_error != ok || map.summary.lead_time != 16.0f64 || map.summary.value_added_time != 7.0f64 || map.waiting.bars.len != 2usize { ret chart.Invalid }
    let blue = paint.rgba(0.12, 0.42, 0.76, 1.0)
    let orange = paint.rgba(0.94, 0.54, 0.13, 1.0)
    let gray = paint.rgba(0.54, 0.61, 0.69, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let names = [3]str{ "Intake / 2h", "Build / 5h", "Review / 3h" }
    var labels: [6]chart.Label = zero
    labels[0usize] = chart.Label { text: "Value-stream map", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Queue (amber) / processing (blue)", anchor: chart.Coord { x: 180.0, y: 148.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "Lead 16h   VA 7h   PCE 44%   yield 92%", anchor: chart.Coord { x: 180.0, y: 226.0 }, align: .Center }
    var i = 0usize
    while i < boxes.len {
        labels[3usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: boxes[i].x + boxes[i].width * 0.5, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &map.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.nodes, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.waiting, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.process, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..3usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[3usize..], font, 9.0, paint.Brush { Solid: white })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &map.connectors, gray)
    try chart_svg.append(&writer, &map.nodes, blue)
    try chart_svg.append(&writer, &map.waiting, orange)
    try chart_svg.append(&writer, &map.process, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..3usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[3usize..], white, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_sipoc_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/sipoc.png"
    let plot = geometry.rect(13.0, 49.0, 334.0, 171.0)
    let entries = [11]chart.SipocEntry{
        chart.SipocEntry { column: 0usize }, chart.SipocEntry { column: 0usize },
        chart.SipocEntry { column: 1usize }, chart.SipocEntry { column: 1usize },
        chart.SipocEntry { column: 2usize }, chart.SipocEntry { column: 2usize }, chart.SipocEntry { column: 2usize },
        chart.SipocEntry { column: 3usize }, chart.SipocEntry { column: 3usize },
        chart.SipocEntry { column: 4usize }, chart.SipocEntry { column: 4usize },
    }
    let headers = [5]str{ "Suppliers", "Inputs", "Process", "Outputs", "Customers" }
    let names = [11]str{ "Design", "Vendor", "Brief", "Assets", "Plan", "Build", "Check", "Release", "Report", "Client", "Support" }
    let colors = [5]paint.Color{
        paint.rgba(0.19, 0.47, 0.77, 1.0),
        paint.rgba(0.24, 0.55, 0.72, 1.0),
        paint.rgba(0.15, 0.52, 0.46, 1.0),
        paint.rgba(0.65, 0.38, 0.70, 1.0),
        paint.rgba(0.78, 0.43, 0.22, 1.0),
    }
    let pale = paint.rgba(0.93, 0.95, 0.98, 1.0)
    let gray = paint.rgba(0.56, 0.62, 0.70, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var columns: [5]geometry.Rect = zero
    var header_boxes: [5]geometry.Rect = zero
    var cards: [11]geometry.Rect = zero
    var arrows: [12]chart.Segment = zero
    var counts: [5]usize = zero
    var used: [5]usize = zero
    let (board, layout_error) = chart.sipoc(entries[..], plot, 6.0, 4.0, 26.0, 4.0, columns[..], header_boxes[..], cards[..], arrows[..], counts[..], used[..])
    if layout_error != ok || board.max_rows != 3usize || counts[2usize] != 3usize { ret chart.Invalid }
    var labels: [18]chart.Label = zero
    var i = 0usize
    while i < 5usize {
        labels[i] = chart.Label { text: headers[i], anchor: chart.Coord { x: header_boxes[i].x + header_boxes[i].width * 0.5, y: header_boxes[i].y + 16.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        labels[5usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: cards[i].x + cards[i].width * 0.5, y: cards[i].y + cards[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[16usize] = chart.Label { text: "SIPOC process overview", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    labels[17usize] = chart.Label { text: "Suppliers to customers / one process boundary", anchor: chart.Coord { x: 180.0, y: 234.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &board.bands, paint.Brush { Solid: pale })
    i = 0usize
    while i < 5usize {
        try fill(&builder, header_boxes[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &board.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &board.cards, paint.Brush { Solid: white })
    i = 0usize
    while i < entries.len {
        try fill(&builder, geometry.rect(cards[i].x, cards[i].y, 3.0, cards[i].height), paint.Brush { Solid: colors[entries[i].column] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..5usize], font, 8.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[5usize..16usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[16usize..17usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[17usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &board.bands, pale)
    i = 0usize
    while i < 5usize {
        try chart_svg.rect(&writer, header_boxes[i], colors[i], false)
        i += 1usize
    }
    try chart_svg.append(&writer, &board.connectors, gray)
    try chart_svg.append(&writer, &board.cards, white)
    i = 0usize
    while i < entries.len {
        try chart_svg.rect(&writer, geometry.rect(cards[i].x, cards[i].y, 3.0, cards[i].height), colors[entries[i].column], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..5usize], white, 8.0)
    try chart_svg.append_labels(&writer, labels[5usize..16usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[16usize..17usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[17usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_decision_tree_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/decision_tree.png"
    let plot = geometry.rect(10.0, 42.0, 340.0, 160.0)
    let nodes = [7]chart.DecisionNode{
        chart.DecisionNode { kind: .Choice, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Chance, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Chance, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 12.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 8.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 6.0f64 },
    }
    let edges = [6]chart.DecisionEdge{
        chart.DecisionEdge { from: 0usize, to: 1usize, probability: 0.0f64 },
        chart.DecisionEdge { from: 0usize, to: 2usize, probability: 0.0f64 },
        chart.DecisionEdge { from: 1usize, to: 3usize, probability: 0.7f64 },
        chart.DecisionEdge { from: 1usize, to: 4usize, probability: 0.3f64 },
        chart.DecisionEdge { from: 2usize, to: 5usize, probability: 0.5f64 },
        chart.DecisionEdge { from: 2usize, to: 6usize, probability: 0.5f64 },
    }
    var values: [7]chart.DecisionValue = zero
    var indegree: [7]usize = zero
    var head: [7]usize = zero
    var next: [6]usize = zero
    var order: [7]usize = zero
    let work = chart.DecisionTreeWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..] }
    let (summary, value_error) = chart.decision_tree_values(nodes[..], edges[..], values[..], work)
    if value_error != ok || summary.expected < 8.399f64 || summary.expected > 8.401f64 || summary.depth != 3usize || summary.leaves != 4usize || values[0usize].selected_edge != 0usize { ret chart.Invalid }
    var boxes: [7]geometry.Rect = zero
    var arrows: [30]chart.Segment = zero
    var chosen: [6]bool = zero
    let (node_layout, connectors, layout_error) = chart.decision_tree_layout(nodes[..], edges[..], values[..], summary, plot, boxes[..], arrows[..], chosen[..])
    if layout_error != ok { ret layout_error }
    let blue = paint.rgba(0.12, 0.41, 0.73, 1.0)
    let amber = paint.rgba(0.84, 0.52, 0.13, 1.0)
    let green = paint.rgba(0.12, 0.56, 0.39, 1.0)
    let red = paint.rgba(0.81, 0.20, 0.20, 1.0)
    let gray = paint.rgba(0.56, 0.63, 0.71, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let names = [7]str{ "Choose", "A / 8.4", "B / 7.0", "+12", "0", "+8", "+6" }
    var labels: [10]chart.Label = zero
    labels[0usize] = chart.Label { text: "Decision tree / expected value", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    var i = 0usize
    while i < boxes.len {
        labels[i + 1usize] = chart.Label { text: names[i], anchor: chart.Coord { x: boxes[i].x + boxes[i].width * 0.5, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[8usize] = chart.Label { text: "A: 70% of 12, 30% of 0 = 8.4", anchor: chart.Coord { x: 180.0, y: 217.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "B: 50% of 8, 50% of 6 = 7.0", anchor: chart.Coord { x: 180.0, y: 231.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &connectors, paint.Brush { Solid: gray })
    i = 0usize
    while i < edges.len {
        if chosen[i] {
            let selected = chart.Layout { kind: .Rug, coords: zero, segments: arrows[i * 5usize..i * 5usize + 5usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            try chart_scene.append(a, &builder, &selected, paint.Brush { Solid: red })
        }
        i += 1usize
    }
    try chart_scene.append(a, &builder, &node_layout, paint.Brush { Solid: blue })
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Chance { try fill(&builder, boxes[i], paint.Brush { Solid: amber }) }
        if nodes[i].kind == .Outcome { try fill(&builder, boxes[i], paint.Brush { Solid: green }) }
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..8usize], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &connectors, gray)
    i = 0usize
    while i < edges.len {
        if chosen[i] {
            let selected = chart.Layout { kind: .Rug, coords: zero, segments: arrows[i * 5usize..i * 5usize + 5usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            try chart_svg.append(&writer, &selected, red)
        }
        i += 1usize
    }
    try chart_svg.append(&writer, &node_layout, blue)
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Chance { try chart_svg.rect(&writer, boxes[i], amber, false) }
        if nodes[i].kind == .Outcome { try chart_svg.rect(&writer, boxes[i], green, false) }
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..8usize], white, 9.0)
    try chart_svg.append_labels(&writer, labels[8usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_org_chart_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/org_chart.png"
    let plot = geometry.rect(13.0, 46.0, 334.0, 166.0)
    let links = [6]chart.OrgLink{
        chart.OrgLink { manager: 0usize, report: 1usize },
        chart.OrgLink { manager: 0usize, report: 2usize },
        chart.OrgLink { manager: 1usize, report: 3usize },
        chart.OrgLink { manager: 1usize, report: 4usize },
        chart.OrgLink { manager: 2usize, report: 5usize },
        chart.OrgLink { manager: 2usize, report: 6usize },
    }
    let names = [7]str{ "Director", "Engineering", "Sales", "Platform", "Apps", "Accounts", "Field" }
    var places: [7]chart.OrgPlacement = zero
    var indegree: [7]usize = zero
    var head: [7]usize = zero
    var next: [6]usize = zero
    var order: [7]usize = zero
    let work = chart.OrgWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..] }
    var boxes: [7]geometry.Rect = zero
    var connectors: [18]chart.Segment = zero
    let (chart_layout, layout_error) = chart.org_chart(7usize, links[..], plot, places[..], work, boxes[..], connectors[..])
    if layout_error != ok || chart_layout.levels != 3usize || chart_layout.leaves != 4usize || places[0usize].direct_reports != 2usize { ret chart.Invalid }
    let navy = paint.rgba(0.16, 0.30, 0.54, 1.0)
    let blue = paint.rgba(0.16, 0.43, 0.76, 1.0)
    let teal = paint.rgba(0.15, 0.55, 0.48, 1.0)
    let gray = paint.rgba(0.58, 0.64, 0.72, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [9]chart.Label = zero
    labels[0usize] = chart.Label { text: "Org chart / reporting lines", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Solid-line manager hierarchy", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    var i = 0usize
    while i < boxes.len {
        labels[2usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: boxes[i].x + boxes[i].width * 0.5, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &chart_layout.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &chart_layout.nodes, paint.Brush { Solid: teal })
    try fill(&builder, boxes[0usize], paint.Brush { Solid: navy })
    try fill(&builder, boxes[1usize], paint.Brush { Solid: blue })
    try fill(&builder, boxes[2usize], paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..], font, 8.0, paint.Brush { Solid: white })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &chart_layout.connectors, gray)
    try chart_svg.append(&writer, &chart_layout.nodes, teal)
    try chart_svg.rect(&writer, boxes[0usize], navy, false)
    try chart_svg.rect(&writer, boxes[1usize], blue, false)
    try chart_svg.rect(&writer, boxes[2usize], blue, false)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[2usize..], white, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_dependency_graph_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/dependency_graph.png"
    let plot = geometry.rect(10.0, 47.0, 340.0, 163.0)
    let links = [6]chart.DependencyLink{
        chart.DependencyLink { from: 0usize, to: 2usize },
        chart.DependencyLink { from: 1usize, to: 2usize },
        chart.DependencyLink { from: 2usize, to: 3usize },
        chart.DependencyLink { from: 2usize, to: 4usize },
        chart.DependencyLink { from: 3usize, to: 5usize },
        chart.DependencyLink { from: 4usize, to: 5usize },
    }
    let names = [6]str{ "Plan", "Data", "Build", "Test", "Docs", "Ship" }
    var indegree: [6]usize = zero
    var head: [6]usize = zero
    var next: [6]usize = zero
    var order: [6]usize = zero
    var stage: [6]usize = zero
    var stage_counts: [6]usize = zero
    var stage_used: [6]usize = zero
    let work = chart.DependencyWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..], stage: stage[..], stage_counts: stage_counts[..], stage_used: stage_used[..] }
    var boxes: [6]geometry.Rect = zero
    var arrows: [30]chart.Segment = zero
    let (graph, layout_error) = chart.dependency_graph(6usize, links[..], plot, work, boxes[..], arrows[..])
    if layout_error != ok || graph.stages != 4usize || graph.sources != 2usize { ret chart.Invalid }
    let blue = paint.rgba(0.16, 0.43, 0.76, 1.0)
    let teal = paint.rgba(0.13, 0.53, 0.46, 1.0)
    let navy = paint.rgba(0.16, 0.30, 0.54, 1.0)
    let gray = paint.rgba(0.55, 0.62, 0.71, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [8]chart.Label = zero
    labels[0usize] = chart.Label { text: "Dependency graph / DAG", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Two starts, a merge and a split", anchor: chart.Coord { x: 180.0, y: 231.0 }, align: .Center }
    var i = 0usize
    while i < boxes.len {
        labels[i + 2usize] = chart.Label { text: names[i], anchor: chart.Coord { x: boxes[i].x + boxes[i].width * 0.5, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 72usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &graph.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &graph.nodes, paint.Brush { Solid: blue })
    try fill(&builder, boxes[2usize], paint.Brush { Solid: teal })
    try fill(&builder, boxes[5usize], paint.Brush { Solid: navy })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..], font, 9.0, paint.Brush { Solid: white })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &graph.connectors, gray)
    try chart_svg.append(&writer, &graph.nodes, blue)
    try chart_svg.rect(&writer, boxes[2usize], teal, false)
    try chart_svg.rect(&writer, boxes[5usize], navy, false)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[2usize..], white, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_flowchart_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/flowchart.png"
    let plot = geometry.rect(12.0, 42.0, 336.0, 185.0)
    let nodes = [6]chart.FlowNode{
        chart.FlowNode { kind: .Terminal, center: chart.Coord { x: 180.0, y: 58.0 } },
        chart.FlowNode { kind: .Process, center: chart.Coord { x: 180.0, y: 105.0 } },
        chart.FlowNode { kind: .Decision, center: chart.Coord { x: 180.0, y: 160.0 } },
        chart.FlowNode { kind: .Process, center: chart.Coord { x: 292.0, y: 160.0 } },
        chart.FlowNode { kind: .Process, center: chart.Coord { x: 62.0, y: 105.0 } },
        chart.FlowNode { kind: .Terminal, center: chart.Coord { x: 292.0, y: 207.0 } },
    }
    let links = [6]chart.FlowLink{
        chart.FlowLink { from: 0usize, to: 1usize, exit: .Bottom, entry: .Top },
        chart.FlowLink { from: 1usize, to: 2usize, exit: .Bottom, entry: .Top },
        chart.FlowLink { from: 2usize, to: 3usize, exit: .Right, entry: .Left },
        chart.FlowLink { from: 3usize, to: 5usize, exit: .Bottom, entry: .Top },
        chart.FlowLink { from: 2usize, to: 4usize, exit: .Left, entry: .Right },
        chart.FlowLink { from: 4usize, to: 1usize, exit: .Right, entry: .Left },
    }
    let names = [6]str{ "Start", "Review", "OK?", "Approve", "Revise", "End" }
    var boxes: [6]geometry.Rect = zero
    var outlines: [48]chart.Coord = zero
    var shapes: [6]chart.Layout = zero
    var arrows: [30]chart.Segment = zero
    let (flow, layout_error) = chart.flowchart(nodes[..], links[..], plot, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    if layout_error != ok || flow.nodes.len != 6usize || flow.connectors.segments.len != 30usize { ret chart.Invalid }
    let blue = paint.rgba(0.16, 0.43, 0.76, 1.0)
    let teal = paint.rgba(0.14, 0.52, 0.45, 1.0)
    let amber = paint.rgba(0.78, 0.43, 0.10, 1.0)
    let navy = paint.rgba(0.16, 0.30, 0.54, 1.0)
    let gray = paint.rgba(0.54, 0.62, 0.71, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [10]chart.Label = zero
    labels[0usize] = chart.Label { text: "Flowchart / decision loop", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Explicit ports allow feedback", anchor: chart.Coord { x: 180.0, y: 239.0 }, align: .Center }
    var i = 0usize
    while i < boxes.len {
        labels[i + 2usize] = chart.Label { text: names[i], anchor: chart.Coord { x: boxes[i].x + boxes[i].width * 0.5, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[8usize] = chart.Label { text: "Yes", anchor: chart.Coord { x: 238.0, y: 150.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "No", anchor: chart.Coord { x: 121.0, y: 150.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 90usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &flow.connectors, paint.Brush { Solid: gray })
    i = 0usize
    while i < flow.nodes.len {
        var color = blue
        if i == 0usize || i == 5usize { color = navy }
        if i == 2usize { color = amber }
        if i == 4usize { color = teal }
        try chart_scene.append(a, &builder, &flow.nodes[i], paint.Brush { Solid: color })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..8usize], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &flow.connectors, gray)
    i = 0usize
    while i < flow.nodes.len {
        var color = blue
        if i == 0usize || i == 5usize { color = navy }
        if i == 2usize { color = amber }
        if i == 4usize { color = teal }
        try chart_svg.append(&writer, &flow.nodes[i], color)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[2usize..8usize], white, 9.0)
    try chart_svg.append_labels(&writer, labels[8usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_kanban_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/kanban.png"
    let plot = geometry.rect(18.0, 46.0, 324.0, 176.0)
    let limits = [3]usize{ 3usize, 2usize, 0usize }
    let cards = [7]chart.KanbanCard{
        chart.KanbanCard { column: 1usize, height: 31.0 },
        chart.KanbanCard { column: 0usize, height: 30.0 },
        chart.KanbanCard { column: 2usize, height: 32.0 },
        chart.KanbanCard { column: 1usize, height: 32.0 },
        chart.KanbanCard { column: 0usize, height: 33.0 },
        chart.KanbanCard { column: 1usize, height: 30.0 },
        chart.KanbanCard { column: 2usize, height: 30.0 },
    }
    let card_names = [7]str{ "Design", "Brief", "Released", "Build", "Estimate", "Review", "Archive" }
    let headers = [3]str{ "Ready 2/3", "Doing 3/2", "Done 2" }
    let colors = [3]paint.Color{
        paint.rgba(0.11, 0.42, 0.78, 1.0),
        paint.rgba(0.85, 0.22, 0.18, 1.0),
        paint.rgba(0.12, 0.55, 0.39, 1.0),
    }
    let background = paint.rgba(0.93, 0.95, 0.98, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var columns: [3]geometry.Rect = zero
    var boxes: [7]geometry.Rect = zero
    var status: [3]chart.KanbanStatus = zero
    var next_y: [3]f32 = zero
    let (board, items, layout_error) = chart.kanban(cards[..], limits[..], plot, 8.0, 7.0, 27.0, 6.0, columns[..], boxes[..], status[..], next_y[..])
    if layout_error != ok { ret layout_error }
    if status[0usize].count != 2usize || status[1usize].count != 3usize || !status[1usize].exceeded || status[2usize].count != 2usize { ret chart.Invalid }
    var labels: [11]chart.Label = zero
    var i = 0usize
    while i < columns.len {
        labels[i] = chart.Label { text: headers[i], anchor: chart.Coord { x: columns[i].x + columns[i].width * 0.5, y: columns[i].y + 18.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < boxes.len {
        labels[3usize + i] = chart.Label { text: card_names[i], anchor: chart.Coord { x: boxes[i].x + 10.0, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Left }
        i += 1usize
    }
    labels[10usize] = chart.Label { text: "Kanban / WIP board", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &board, paint.Brush { Solid: background })
    i = 0usize
    while i < columns.len {
        try fill(&builder, geometry.rect(columns[i].x, columns[i].y, columns[i].width, 27.0), paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &items, paint.Brush { Solid: white })
    i = 0usize
    while i < boxes.len {
        try fill(&builder, geometry.rect(boxes[i].x, boxes[i].y, 3.0, boxes[i].height), paint.Brush { Solid: colors[cards[i].column] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..3usize], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[3usize..10usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[10usize..], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &board, background)
    i = 0usize
    while i < columns.len {
        try chart_svg.rect(&writer, geometry.rect(columns[i].x, columns[i].y, columns[i].width, 27.0), colors[i], false)
        i += 1usize
    }
    try chart_svg.append(&writer, &items, white)
    i = 0usize
    while i < boxes.len {
        try chart_svg.rect(&writer, geometry.rect(boxes[i].x, boxes[i].y, 3.0, boxes[i].height), colors[cards[i].column], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..3usize], white, 9.0)
    try chart_svg.append_labels(&writer, labels[3usize..10usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[10usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_gantt_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/gantt.png"
    let plot = geometry.rect(89.0, 52.0, 225.0, 143.0)
    let tasks = [4]chart.GanttTask{
        chart.GanttTask { row: 0usize, start: 0.0f64, end: 3.0f64, complete: 1.0 },
        chart.GanttTask { row: 1usize, start: 2.0f64, end: 5.0f64, complete: 1.0 },
        chart.GanttTask { row: 2usize, start: 4.0f64, end: 10.0f64, complete: 0.55 },
        chart.GanttTask { row: 3usize, start: 9.0f64, end: 12.0f64, complete: 0.1 },
    }
    let names = [4]str{ "Plan", "Design", "Build", "Launch" }
    let ticks = [4]str{ "0", "4", "8", "12" }
    let pale = paint.rgba(0.95, 0.96, 0.98, 1.0)
    let remaining = paint.rgba(0.69, 0.82, 0.95, 1.0)
    let complete = paint.rgba(0.07, 0.38, 0.76, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let grid = paint.rgba(0.84, 0.88, 0.93, 1.0)
    var spans: [4]geometry.Rect = zero
    var progress: [4]geometry.Rect = zero
    let (whole, done, layout_error) = chart.gantt(tasks[..], 4usize, 0.0f64, 12.0f64, plot, 7.0, spans[..], progress[..])
    if layout_error != ok { ret layout_error }
    var x_ticks: [4]chart.Tick = zero
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    let (_, tick_error) = chart.ticks(linear, 0.0, 12.0, x_ticks[..])
    if tick_error != ok { ret tick_error }
    var labels: [9]chart.Label = zero
    var i = 0usize
    while i < 4usize {
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: 79.0, y: spans[i].y + spans[i].height * 0.5 + 3.0 }, align: .Right }
        labels[4usize + i] = chart.Label { text: ticks[i], anchor: chart.Coord { x: plot.x + plot.width * f32(i) / 3.0, y: 217.0 }, align: .Center }
        i += 1usize
    }
    labels[8usize] = chart.Label { text: "Gantt schedule / completion", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < 4usize {
        try fill(&builder, geometry.rect(plot.x, plot.y + f32(i) * 37.5, plot.width, 30.5), paint.Brush { Solid: pale })
        i += 1usize
    }
    try chart_scene.append_guides(&builder, plot, x_ticks[..], x_ticks[..0usize], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &whole, paint.Brush { Solid: remaining })
    try chart_scene.append(a, &builder, &done, paint.Brush { Solid: complete })
    try chart_scene.append_labels(a, &builder, labels[..8usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 4usize {
        try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + f32(i) * 37.5, plot.width, 30.5), pale, false)
        i += 1usize
    }
    try chart_svg.append_guides(&writer, plot, x_ticks[..], x_ticks[..0usize], grid, dark)
    try chart_svg.append(&writer, &whole, remaining)
    try chart_svg.append(&writer, &done, complete)
    try chart_svg.append_labels(&writer, labels[..8usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[8usize..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_milestone_roadmap_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/milestone_roadmap.png"
    let plot = geometry.rect(63.0, 52.0, 245.0, 144.0)
    let events = [6]chart.TimelineEvent{
        chart.TimelineEvent { time: 1.0f64, row: 0usize },
        chart.TimelineEvent { time: 3.0f64, row: 1usize },
        chart.TimelineEvent { time: 4.8f64, row: 0usize },
        chart.TimelineEvent { time: 6.8f64, row: 1usize },
        chart.TimelineEvent { time: 8.5f64, row: 2usize },
        chart.TimelineEvent { time: 11.0f64, row: 2usize },
    }
    let lane_names = [3]str{ "Product", "Platform", "Release" }
    let names = [6]str{ "Scope", "API", "Design", "Beta", "QA", "Launch" }
    let ticks = [4]str{ "0", "4", "8", "12" }
    let colors = [3]paint.Color{ paint.rgba(0.07, 0.38, 0.76, 1.0), paint.rgba(0.15, 0.60, 0.46, 1.0), paint.rgba(0.82, 0.38, 0.20, 1.0) }
    let pale = paint.rgba(0.95, 0.96, 0.98, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let grid = paint.rgba(0.84, 0.88, 0.93, 1.0)
    var centers: [6]chart.Coord = zero
    var stems: [6]chart.Segment = zero
    var diamonds: [24]chart.Coord = zero
    var storage: [6]chart.Layout = zero
    let (marks, layout_error) = chart.milestone_roadmap(events[..], 3usize, 0.0f64, 12.0f64, plot, 6.0, centers[..], stems[..], diamonds[..], storage[..])
    if layout_error != ok { ret layout_error }
    var x_ticks: [4]chart.Tick = zero
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    let (_, tick_error) = chart.ticks(linear, 0.0, 12.0, x_ticks[..])
    if tick_error != ok { ret tick_error }
    var labels: [14]chart.Label = zero
    var i = 0usize
    while i < 3usize {
        labels[i] = chart.Label { text: lane_names[i], anchor: chart.Coord { x: 54.0, y: plot.y + f32(i) * 48.0 + 27.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < events.len {
        labels[3usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: centers[i].x, y: centers[i].y - 11.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        labels[9usize + i] = chart.Label { text: ticks[i], anchor: chart.Coord { x: plot.x + plot.width * f32(i) / 3.0, y: 217.0 }, align: .Center }
        i += 1usize
    }
    labels[13usize] = chart.Label { text: "Milestone roadmap", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < 3usize {
        try fill(&builder, geometry.rect(plot.x, plot.y + f32(i) * 48.0, plot.width, 43.0), paint.Brush { Solid: pale })
        i += 1usize
    }
    try chart_scene.append_guides(&builder, plot, x_ticks[..], x_ticks[..0usize], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    i = 0usize
    while i < marks.len {
        try chart_scene.append(a, &builder, &marks[i], paint.Brush { Solid: colors[events[i].row] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..13usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 3usize {
        try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + f32(i) * 48.0, plot.width, 43.0), pale, false)
        i += 1usize
    }
    try chart_svg.append_guides(&writer, plot, x_ticks[..], x_ticks[..0usize], grid, dark)
    i = 0usize
    while i < marks.len {
        try chart_svg.append(&writer, &marks[i], colors[events[i].row])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..13usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[13usize..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_event_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/event_timeline.png"
    let plot = geometry.rect(62.0, 52.0, 246.0, 144.0)
    let events = [5]chart.TimelineEvent{
        chart.TimelineEvent { time: 1.0f64, row: 0usize },
        chart.TimelineEvent { time: 3.2f64, row: 1usize },
        chart.TimelineEvent { time: 5.1f64, row: 2usize },
        chart.TimelineEvent { time: 8.2f64, row: 0usize },
        chart.TimelineEvent { time: 11.0f64, row: 2usize },
    }
    let row_names = [3]str{ "Plan", "Build", "Ship" }
    let event_names = [5]str{ "Kickoff", "Prototype", "QA", "Release", "Review" }
    let ticks = [4]str{ "0", "4", "8", "12" }
    let blue = paint.rgba(0.07, 0.38, 0.76, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let pale = paint.rgba(0.95, 0.96, 0.98, 1.0)
    var points: [5]chart.Coord = zero
    var stems: [5]chart.Segment = zero
    let (marks, marks_error) = chart.event_timeline(events[..], 3usize, 0.0f64, 12.0f64, plot, points[..], stems[..])
    if marks_error != ok { ret marks_error }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var labels: [13]chart.Label = zero
    var i = 0usize
    while i < 3usize {
        try fill(&builder, geometry.rect(plot.x, plot.y + f32(i) * 48.0, plot.width, 43.0), paint.Brush { Solid: pale })
        labels[i] = chart.Label { text: row_names[i], anchor: chart.Coord { x: 53.0, y: plot.y + f32(i) * 48.0 + 27.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        labels[3usize + i] = chart.Label { text: event_names[i], anchor: chart.Coord { x: marks.coords[i].x, y: marks.coords[i].y - 12.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        labels[8usize + i] = chart.Label { text: ticks[i], anchor: chart.Coord { x: plot.x + plot.width * f32(i) / 3.0, y: 218.0 }, align: .Center }
        i += 1usize
    }
    labels[12usize] = chart.Label { text: "Event timeline", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..12usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[12usize..], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 3usize {
        try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + f32(i) * 48.0, plot.width, 43.0), pale, false)
        i += 1usize
    }
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append_labels(&writer, labels[..12usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[12usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_cell_bars_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/in_cell_data_bars.png"
    let values = [6]f32{ 78.0, 45.0, 95.0, 61.0, 25.0, 0.0 }
    let names = [6]str{ "North", "South", "East", "West", "Central", "Remote" }
    let counts = [6]str{ "78", "45", "95", "61", "25", "0" }
    let blue = paint.rgba(0.10, 0.45, 0.78, 1.0)
    let pale = paint.rgba(0.94, 0.96, 0.98, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var cells: [6]geometry.Rect = zero
    var i = 0usize
    while i < 6usize {
        cells[i] = geometry.rect(126.0, 48.0 + f32(i) * 29.0, 178.0, 22.0)
        i += 1usize
    }
    var bars: [6]geometry.Rect = zero
    let (marks, marks_error) = chart.in_cell_bars(values[..], 100.0, cells[..], 3.0, bars[..])
    if marks_error != ok { ret marks_error }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var labels: [13]chart.Label = zero
    i = 0usize
    while i < 6usize {
        try fill(&builder, cells[i], paint.Brush { Solid: pale })
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: 116.0, y: cells[i].y + 15.0 }, align: .Right }
        labels[6usize + i] = chart.Label { text: counts[i], anchor: chart.Coord { x: 314.0, y: cells[i].y + 15.0 }, align: .Left }
        i += 1usize
    }
    labels[12usize] = chart.Label { text: "In-cell data bars", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..12usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[12usize..], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 6usize {
        try chart_svg.rect(&writer, cells[i], pale, false)
        i += 1usize
    }
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append_labels(&writer, labels[..12usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[12usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_forest_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/forest_plot.png"
    let plot = geometry.rect(100.0, 48.0, 214.0, 144.0)
    let estimates = [5]f32{ 0.72, 0.95, 1.10, 1.35, 1.80 }
    let lows = [5]f32{ 0.45, 0.70, 0.85, 1.05, 1.30 }
    let highs = [5]f32{ 1.10, 1.25, 1.45, 1.80, 2.50 }
    let names = [5]str{ "Study A", "Study B", "Study C", "Study D", "Study E" }
    let tick_names = [3]str{ "0.5", "1.0", "2.0" }
    let tick_values = [3]f32{ 0.5, 1.0, 2.0 }
    let scale = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    let blue = paint.rgba(0.08, 0.40, 0.76, 1.0)
    let axis = paint.rgba(0.52, 0.58, 0.66, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let pale = paint.rgba(0.96, 0.97, 0.99, 1.0)
    var centers: [5]chart.Coord = zero
    var intervals: [5]chart.Segment = zero
    var reference: [1]chart.Segment = zero
    let (marks, rule, marks_error) = chart.forest_plot(estimates[..], lows[..], highs[..], 1.0, scale, plot, centers[..], intervals[..], reference[..])
    if marks_error != ok { ret marks_error }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var labels: [10]chart.Label = zero
    var i = 0usize
    while i < 5usize {
        if i % 2usize == 0usize { try fill(&builder, geometry.rect(plot.x, plot.y + f32(i) * plot.height / 5.0, plot.width, plot.height / 5.0), paint.Brush { Solid: pale }) }
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: 89.0, y: centers[i].y + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < 3usize {
        let x = plot.x + plot.width * chart.fraction(tick_values[i], marks.x_min, marks.x_max, scale)
        labels[5usize + i] = chart.Label { text: tick_names[i], anchor: chart.Coord { x: x, y: 210.0 }, align: .Center }
        i += 1usize
    }
    labels[8usize] = chart.Label { text: "Forest plot", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "Risk ratio (log)", anchor: chart.Coord { x: 208.0, y: 231.0 }, align: .Center }
    try chart_scene.append(a, &builder, &rule, paint.Brush { Solid: axis })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..8usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[8usize..9usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[9usize..], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 5usize {
        if i % 2usize == 0usize { try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + f32(i) * plot.height / 5.0, plot.width, plot.height / 5.0), pale, false) }
        i += 1usize
    }
    try chart_svg.append(&writer, &rule, axis)
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append_labels(&writer, labels[..8usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[8usize..9usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[9usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_agreement_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/bland_altman.png"
    let plot = geometry.rect(56.0, 43.0, 252.0, 151.0)
    let left = [8]f64{ 9.1f64, 10.8f64, 12.9f64, 15.2f64, 16.8f64, 18.9f64, 21.4f64, 22.2f64 }
    let right = [8]f64{ 9.3f64, 10.4f64, 12.2f64, 14.9f64, 17.1f64, 18.0f64, 20.9f64, 23.0f64 }
    let blue = paint.rgba(0.08, 0.40, 0.76, 1.0)
    let rule_color = paint.rgba(0.72, 0.32, 0.30, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let pale = paint.rgba(0.96, 0.97, 0.99, 1.0)
    var means: [8]f32 = zero
    var differences: [8]f32 = zero
    var points: [8]chart.Coord = zero
    var rule_segments: [3]chart.Segment = zero
    let (dots, rules, layout_error) = chart.bland_altman(left[..], right[..], 1.96f64, plot, means[..], differences[..], points[..], rule_segments[..])
    if layout_error != ok { ret layout_error }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &rules, paint.Brush { Solid: rule_color })
    try chart_scene.append(a, &builder, &dots, paint.Brush { Solid: blue })
    var labels: [8]chart.Label = zero
    let levels = [3]str{ "Lower LoA", "Bias", "Upper LoA" }
    var i = 0usize
    while i < 3usize {
        labels[i] = chart.Label { text: levels[i], anchor: chart.Coord { x: 301.0, y: rule_segments[i].from.y - 4.0 }, align: .Right }
        i += 1usize
    }
    let ticks = [3]str{ "10", "15", "20" }
    let tick_values = [3]f32{ 10.0, 15.0, 20.0 }
    let scale = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    i = 0usize
    while i < 3usize {
        labels[3usize + i] = chart.Label { text: ticks[i], anchor: chart.Coord { x: plot.x + plot.width * chart.fraction(tick_values[i], dots.x_min, dots.x_max, scale), y: 211.0 }, align: .Center }
        i += 1usize
    }
    labels[6usize] = chart.Label { text: "Bland-Altman agreement", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "Pair mean", anchor: chart.Coord { x: 180.0, y: 231.0 }, align: .Center }
    try chart_scene.append_labels(a, &builder, labels[..6usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[6usize..7usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[7usize..], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &rules, rule_color)
    try chart_svg.append(&writer, &dots, blue)
    try chart_svg.append_labels(&writer, labels[..6usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[6usize..7usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[7usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_diagnostic_preview_extra(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, marks: *const chart.Layout, baseline: *const chart.Layout, highlight: *const chart.Layout, title: str, x_label: str, y_label: str, path: str) -> err {
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    var blue = paint.rgba(0.08, 0.40, 0.76, 1.0)
    if marks.kind == .Area { blue = paint.rgba(0.08, 0.40, 0.76, 0.38) }
    let baseline_color = paint.rgba(0.64, 0.69, 0.76, 1.0)
    let pale = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, baseline, paint.Brush { Solid: baseline_color })
    try chart_scene.append(a, &builder, marks, paint.Brush { Solid: blue })
    let signal_color = paint.rgba(0.88, 0.24, 0.21, 1.0)
    if highlight.coords.len > 0usize { try chart_scene.append(a, &builder, highlight, paint.Brush { Solid: signal_color }) }
    let ticks = [3]str{ "0", "0.5", "1" }
    var labels: [6]chart.Label = zero
    var i = 0usize
    while i < 3usize {
        labels[i] = chart.Label { text: ticks[i], anchor: chart.Coord { x: plot.x + f32(i) * plot.width * 0.5, y: 210.0 }, align: .Center }
        i += 1usize
    }
    labels[3usize] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[4usize] = chart.Label { text: x_label, anchor: chart.Coord { x: 180.0, y: 231.0 }, align: .Center }
    labels[5usize] = chart.Label { text: y_label, anchor: chart.Coord { x: 56.0, y: 38.0 }, align: .Left }
    try chart_scene.append_labels(a, &builder, labels[..3usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[3usize..4usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, baseline, baseline_color)
    try chart_svg.append(&writer, marks, blue)
    if highlight.coords.len > 0usize { try chart_svg.append(&writer, highlight, signal_color) }
    try chart_svg.append_labels(&writer, labels[..3usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[3usize..4usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[4usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_diagnostic_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, marks: *const chart.Layout, baseline: *const chart.Layout, title: str, x_label: str, y_label: str, path: str) -> err {
    let empty = chart.Layout { kind: .Scatter, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret render_diagnostic_preview_extra(a, q, output_target, canvas, renderer, marks, baseline, &empty, title, x_label, y_label, path)
}

fn render_parallel_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [24]f64{
        0.0, 80.0, 10.0, 2.0, 2.0, 65.0, 30.0, 4.0,
        4.0, 90.0, 20.0, 3.0, 6.0, 55.0, 45.0, 7.0,
        8.0, 72.0, 35.0, 5.0, 10.0, 95.0, 50.0, 6.0,
    }
    let plot = geometry.rect(36.0, 56.0, 288.0, 120.0)
    var minimums: [4]f64 = zero
    var maximums: [4]f64 = zero
    var lines: [18]chart.Segment = zero
    var axes: [4]chart.Segment = zero
    let (marks, guides, layout_error) = chart.parallel_coordinates(values[..], 4usize, plot, minimums[..], maximums[..], lines[..], axes[..])
    if layout_error != ok { ret layout_error }
    let blue = paint.rgba(0.08, 0.40, 0.76, 0.62)
    let gray = paint.rgba(0.62, 0.67, 0.74, 1.0)
    let pale = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 18u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let top = [4]str{ "10", "95", "50", "7" }
    let bottom = [4]str{ "0", "55", "10", "2" }
    let names = [4]str{ "Speed", "Cost", "Quality", "Risk" }
    var labels: [13]chart.Label = zero
    var i = 0usize
    while i < 4usize {
        let x = plot.x + plot.width * f32(i) / 3.0
        labels[i] = chart.Label { text: top[i], anchor: chart.Coord { x: x, y: 49.0 }, align: .Center }
        labels[4usize + i] = chart.Label { text: bottom[i], anchor: chart.Coord { x: x, y: 191.0 }, align: .Center }
        labels[8usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: x, y: 210.0 }, align: .Center }
        i += 1usize
    }
    labels[12usize] = chart.Label { text: "Parallel coordinates", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &guides, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..12usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[12usize..], font, 14.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/parallel_coordinates.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &guides, gray)
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append_labels(&writer, labels[..12usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[12usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_pairs_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [24]f64{
        42.0, 8.2, 3.0, 55.0, 7.0, 5.0, 63.0, 6.4, 4.0, 70.0, 5.7, 8.0,
        76.0, 5.2, 6.0, 82.0, 4.9, 9.0, 89.0, 4.5, 11.0, 95.0, 4.2, 10.0,
    }
    var minimums: [3]f64 = zero
    var maximums: [3]f64 = zero
    var panels: [9]geometry.Rect = zero
    var points: [48]chart.Coord = zero
    var storage: [9]chart.Layout = zero
    let (layers, layout_error) = chart.scatterplot_matrix(values[..], 3usize, geometry.rect(36.0, 39.0, 288.0, 177.0), 8.0, minimums[..], maximums[..], panels[..], points[..], storage[..])
    if layout_error != ok { ret layout_error }
    let blue = paint.rgba(0.07, 0.35, 0.76, 1.0)
    let pale = paint.rgba(0.94, 0.96, 0.99, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 19u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let names = [3]str{ "Speed", "Fuel", "Risk" }
    var labels: [4]chart.Label = zero
    var i = 0usize
    while i < 3usize {
        let panel = panels[i * 3usize + i]
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: panel.x + panel.width / 2.0, y: panel.y + panel.height / 2.0 + 4.0 }, align: .Center }
        i += 1usize
    }
    labels[3usize] = chart.Label { text: "Scatterplot matrix", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < layers.len {
        try fill(&builder, geometry.rect(panels[i].x - 3.0, panels[i].y - 3.0, panels[i].width + 6.0, panels[i].height + 6.0), paint.Brush { Solid: pale })
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..3usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[3usize..], font, 14.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/scatterplot_matrix.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.rect(&writer, geometry.rect(panels[i].x - 3.0, panels[i].y - 3.0, panels[i].width + 6.0, panels[i].height + 6.0), pale, false)
        try chart_svg.append(&writer, &layers[i], blue)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..3usize], dark, 11.0)
    try chart_svg.append_labels(&writer, labels[3usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_binary_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, data: *const stat.BinaryCurve, metric: chart.BinaryMetric, title: str, x_label: str, y_label: str, path: str) -> err {
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    var x: [17]f32 = zero
    var y: [17]f32 = zero
    var segments: [16]chart.Segment = zero
    let (marks, marks_error) = chart.binary_metric_curve(data, metric, plot, x[..], y[..], segments[..])
    if marks_error != ok { ret marks_error }
    var baseline_segments: [1]chart.Segment = zero
    let bottom = plot.y + plot.height
    if metric == .Roc || metric == .CumulativeGain {
        baseline_segments[0usize] = chart.Segment { from: chart.Coord { x: plot.x, y: bottom }, to: chart.Coord { x: plot.x + plot.width, y: plot.y } }
    } else {
        var fraction = f32(data.positives) / f32(data.positives + data.negatives)
        if metric == .Lift { fraction = 1.0 / marks.y_max }
        let line_y = bottom - plot.height * fraction
        baseline_segments[0usize] = chart.Segment { from: chart.Coord { x: plot.x, y: line_y }, to: chart.Coord { x: plot.x + plot.width, y: line_y } }
    }
    let baseline = chart.Layout { kind: .Rug, coords: zero, segments: baseline_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: marks.y_min, y_max: marks.y_max }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &marks, &baseline, title, x_label, y_label, path)
}

fn render_survival_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let times = [12]f64{ 0.08, 0.14, 0.14, 0.24, 0.31, 0.38, 0.47, 0.53, 0.53, 0.67, 0.78, 0.92 }
    let event = [12]bool{ true, true, false, true, false, true, true, false, true, false, true, false }
    var storage: [13]stat.SurvivalPoint = zero
    let (curve, curve_error) = stat.survival_curve(times[..], event[..], storage[..])
    if curve_error != ok { ret curve_error }
    var x: [13]f32 = zero
    var survival: [13]f32 = zero
    var hazard: [13]f32 = zero
    var censor_x: [12]f32 = zero
    var censor_y: [12]f32 = zero
    var censored = 0usize
    var i = 0usize
    while i < curve.len {
        x[i] = f32(curve[i].time)
        survival[i] = f32(curve[i].survival)
        hazard[i] = f32(curve[i].cumulative_hazard)
        if curve[i].censored > 0usize {
            censor_x[censored] = x[i]
            censor_y[censored] = survival[i]
            censored += 1usize
        }
        i += 1usize
    }
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    let x_limits = [2]f32{ 0.0, 1.0 }
    let probability_limits = [2]f32{ 0.0, 1.0 }
    let hazard_limits = [2]f32{ 0.0, 1.5 }
    var survival_spec = chart.spec(.Step, plot, x[..curve.len], survival[..curve.len])
    var survival_segments: [24]chart.Segment = zero
    let (survival_marks, survival_error) = chart.layout_with_limits(&survival_spec, zero, survival_segments[..], zero, x_limits[..], probability_limits[..])
    if survival_error != ok { ret survival_error }
    var censor_spec = chart.spec(.Scatter, plot, censor_x[..censored], censor_y[..censored])
    var censor_coords: [12]chart.Coord = zero
    let (censor_marks, censor_error) = chart.layout_with_limits(&censor_spec, censor_coords[..], zero, zero, x_limits[..], probability_limits[..])
    if censor_error != ok { ret censor_error }
    try render_diagnostic_preview(a, q, output_target, canvas, renderer, &survival_marks, &censor_marks, "Kaplan-Meier survival", "Years", "Survival", "docs/chart-previews/kaplan_meier.png")
    var hazard_spec = chart.spec(.Step, plot, x[..curve.len], hazard[..curve.len])
    var hazard_segments: [24]chart.Segment = zero
    let (hazard_marks, hazard_error) = chart.layout_with_limits(&hazard_spec, zero, hazard_segments[..], zero, x_limits[..], hazard_limits[..])
    if hazard_error != ok { ret hazard_error }
    let bottom = plot.y + plot.height
    var rule_segments = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: plot.x, y: bottom }, to: chart.Coord { x: plot.x + plot.width, y: bottom } } }
    let rule = chart.Layout { kind: .Rug, coords: zero, segments: rule_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.5 }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &hazard_marks, &rule, "Cumulative hazard", "Years", "Hazard", "docs/chart-previews/cumulative_hazard.png")
}

fn render_control_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, values: []const f64, limits: stat.ControlLimits, title: str, y_label: str, path: str) -> err {
    if values.len < 2usize || values.len > 16usize { ret chart.Invalid }
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    var x: [16]f32 = zero
    var y: [16]f32 = zero
    var low = f32(limits.lower)
    var high = f32(limits.upper)
    var i = 0usize
    while i < values.len {
        x[i] = f32(i) / f32(values.len - 1usize)
        y[i] = f32(values[i])
        if y[i] < low { low = y[i] }
        if y[i] > high { high = y[i] }
        i += 1usize
    }
    var padding = (high - low) * 0.08
    if padding == 0.0 { padding = 1.0 }
    low -= padding
    high += padding
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ low, high }
    var spec = chart.spec(.PointLine, plot, x[..values.len], y[..values.len])
    var points: [16]chart.Coord = zero
    var segments: [15]chart.Segment = zero
    let (marks, marks_error) = chart.layout_with_limits(&spec, points[..], segments[..], zero, x_limits[..], y_limits[..])
    if marks_error != ok { ret marks_error }
    let levels = [3]f32{ f32(limits.lower), f32(limits.center), f32(limits.upper) }
    var rules: [3]chart.Segment = zero
    i = 0usize
    while i < 3usize {
        let pixel_y = plot.y + plot.height * (high - levels[i]) / (high - low)
        rules[i] = chart.Segment { from: chart.Coord { x: plot.x, y: pixel_y }, to: chart.Coord { x: plot.x + plot.width, y: pixel_y } }
        i += 1usize
    }
    let reference = chart.Layout { kind: .Rug, coords: zero, segments: rules[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: low, y_max: high }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &marks, &reference, title, "Run fraction", y_label, path)
}

fn render_run_rules_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [16]f64{ 0.4, 0.6, 0.7, 0.8, 1.0, 0.6, 0.9, 1.1, 1.2, 1.3, -0.2, 3.4, 0.2, -0.4, 0.3, 0.1 }
    var centers: [16]f64 = zero
    var sigmas: [16]f64 = zero
    var signals: [16]stat.ControlSignal = zero
    var x: [16]f32 = zero
    var y: [16]f32 = zero
    var i = 0usize
    while i < values.len {
        sigmas[i] = 1.0
        x[i] = f32(i) / 15.0
        y[i] = f32(values[i])
        i += 1usize
    }
    try stat.control_run_rules(values[..], centers[..], sigmas[..], signals[..])
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ -3.5, 3.8 }
    var spec = chart.spec(.PointLine, plot, x[..], y[..])
    var points: [16]chart.Coord = zero
    var segments: [15]chart.Segment = zero
    let (series, layout_error) = chart.layout_with_limits(&spec, points[..], segments[..], zero, x_limits[..], y_limits[..])
    if layout_error != ok { ret layout_error }
    var rules: [3]chart.Segment = zero
    let levels = [3]f32{ -3.0, 0.0, 3.0 }
    i = 0usize
    while i < 3usize {
        let pixel_y = plot.y + plot.height * (y_limits[1usize] - levels[i]) / (y_limits[1usize] - y_limits[0usize])
        rules[i] = chart.Segment { from: chart.Coord { x: plot.x, y: pixel_y }, to: chart.Coord { x: plot.x + plot.width, y: pixel_y } }
        i += 1usize
    }
    var flagged: [16]chart.Coord = zero
    var flagged_count = 0usize
    i = 0usize
    while i < 16usize {
        let s = signals[i]
        if s.beyond3 || s.same_side9 || s.trend6 || s.alternating14 || s.two_of_three2 || s.four_of_five1 || s.within1_15 || s.outside1_8 {
            flagged[flagged_count] = series.coords[i]
            flagged_count += 1usize
        }
        i += 1usize
    }
    let reference = chart.Layout { kind: .Rug, coords: zero, segments: rules[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: y_limits[0usize], y_max: y_limits[1usize] }
    let highlight = chart.Layout { kind: .Scatter, coords: flagged[..flagged_count], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: y_limits[0usize], y_max: y_limits[1usize] }
    ret render_diagnostic_preview_extra(a, q, output_target, canvas, renderer, &series, &reference, &highlight, "SPC run signals", "Run fraction", "Z score", "docs/chart-previews/run_rules_control.png")
}

fn render_phase_control_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [10]f64{ 10.0, 11.0, 9.0, 10.0, 10.0, 20.0, 21.0, 19.0, 20.0, 20.0 }
    let starts = [10]bool{ true, false, false, false, false, true, false, false, false, false }
    var moving: [9]f64 = zero
    var limits: [10]stat.AttributeControlPoint = zero
    try stat.imr_phase_control(values[..], starts[..], moving[..], limits[..])
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ 6.0, 24.0 }
    var x: [10]f32 = zero
    var y: [10]f32 = zero
    var i = 0usize
    while i < 10usize {
        x[i] = f32(i) / 9.0
        y[i] = f32(values[i])
        i += 1usize
    }
    var spec = chart.spec(.PointLine, plot, x[..], y[..])
    var coords: [10]chart.Coord = zero
    var segments: [9]chart.Segment = zero
    let (marks, marks_error) = chart.layout_with_limits(&spec, coords[..], segments[..], zero, x_limits[..], y_limits[..])
    if marks_error != ok { ret marks_error }
    var rules: [7]chart.Segment = zero
    let phase_indices = [2]usize{ 0usize, 5usize }
    var phase = 0usize
    while phase < 2usize {
        let point = limits[phase_indices[phase]]
        let levels = [3]f32{ f32(point.lower), f32(point.center), f32(point.upper) }
        i = 0usize
        while i < 3usize {
            let pixel_y = plot.y + plot.height * (y_limits[1usize] - levels[i]) / (y_limits[1usize] - y_limits[0usize])
            let left = plot.x + plot.width * f32(phase_indices[phase]) / 9.0
            let right = left + plot.width * 4.0 / 9.0
            rules[phase * 3usize + i] = chart.Segment { from: chart.Coord { x: left, y: pixel_y }, to: chart.Coord { x: right, y: pixel_y } }
            i += 1usize
        }
        phase += 1usize
    }
    let boundary_x = plot.x + plot.width * 4.5 / 9.0
    rules[6usize] = chart.Segment { from: chart.Coord { x: boundary_x, y: plot.y }, to: chart.Coord { x: boundary_x, y: plot.y + plot.height } }
    let reference = chart.Layout { kind: .Rug, coords: zero, segments: rules[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 6.0, y_max: 24.0 }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &marks, &reference, "Phased Individuals", "Run fraction", "Value", "docs/chart-previews/phase_control.png")
}

fn render_control_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let observations = [10]f64{ 49.6, 47.6, 49.9, 51.3, 47.8, 51.2, 52.6, 52.4, 53.6, 52.1 }
    var moving: [9]f64 = zero
    let (individuals, mr, imr_error) = stat.imr_limits(observations[..], moving[..])
    if imr_error != ok { ret imr_error }
    try render_control_preview(a, q, output_target, canvas, renderer, observations[..], individuals, "Individuals chart", "Value", "docs/chart-previews/individuals_control.png")
    try render_control_preview(a, q, output_target, canvas, renderer, moving[..], mr, "Moving range", "Range", "docs/chart-previews/moving_range_control.png")
    let subgroup_values = [25]f64{ 10.0, 11.0, 9.0, 10.0, 10.0, 11.0, 13.0, 10.0, 11.0, 10.0, 9.0, 10.0, 8.0, 9.0, 9.0, 10.0, 12.0, 9.0, 11.0, 10.0, 12.0, 11.0, 10.0, 11.0, 11.0 }
    var means: [5]f64 = zero
    var ranges: [5]f64 = zero
    let (xbar, range, subgroup_error) = stat.xbar_r_limits(subgroup_values[..], 5usize, means[..], ranges[..])
    if subgroup_error != ok { ret subgroup_error }
    try render_control_preview(a, q, output_target, canvas, renderer, means[..], xbar, "X-bar chart", "Mean", "docs/chart-previews/xbar_control.png")
    try render_control_preview(a, q, output_target, canvas, renderer, ranges[..], range, "Range chart", "Range", "docs/chart-previews/range_control.png")
    var deviations: [5]f64 = zero
    let (xbar_s, s_limits, s_error) = stat.xbar_s_limits(subgroup_values[..], 5usize, means[..], deviations[..])
    if s_error != ok { ret s_error }
    try render_control_preview(a, q, output_target, canvas, renderer, means[..], xbar_s, "X-bar / S chart", "Mean", "docs/chart-previews/xbar_s_control.png")
    ret render_control_preview(a, q, output_target, canvas, renderer, deviations[..], s_limits, "Standard deviation chart", "S", "docs/chart-previews/s_control.png")
}

fn render_subgroup_phase_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [24]f64{
        9.0, 10.0, 11.0, 10.0, 12.0, 11.0, 8.0, 9.0, 10.0, 10.0, 10.0, 13.0,
        19.0, 20.0, 21.0, 20.0, 22.0, 23.0, 18.0, 19.0, 20.0, 21.0, 22.0, 24.0,
    }
    let starts = [8]bool{ true, false, false, false, true, false, false, false }
    let kinds = [2]stat.SubgroupSpreadKind{ .Range, .StdDev }
    let mean_titles = [2]str{ "Phased X-bar / R", "Phased X-bar / S" }
    let spread_titles = [2]str{ "Phased Range", "Phased S chart" }
    let mean_paths = [2]str{ "docs/chart-previews/phased_xbar_r.png", "docs/chart-previews/phased_xbar_s.png" }
    let spread_paths = [2]str{ "docs/chart-previews/phased_range.png", "docs/chart-previews/phased_s.png" }
    var means: [8]f64 = zero
    var spreads: [8]f64 = zero
    var mean_points: [8]stat.AttributeControlPoint = zero
    var spread_points: [8]stat.AttributeControlPoint = zero
    var i = 0usize
    while i < 2usize {
        try stat.subgroup_control_phased(kinds[i], values[..], 3usize, starts[..], means[..], spreads[..], mean_points[..], spread_points[..])
        try render_attribute_preview_phased(a, q, output_target, canvas, renderer, mean_points[..], starts[..], mean_titles[i], "Mean", mean_paths[i])
        var spread_label = "Range"
        if kinds[i] == .StdDev { spread_label = "S" }
        try render_attribute_preview_phased(a, q, output_target, canvas, renderer, spread_points[..], starts[..], spread_titles[i], spread_label, spread_paths[i])
        i += 1usize
    }
    ret ok
}

fn render_weighted_control_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let observations = [10]f64{ 10.6, 11.1, 11.4, 12.0, 11.8, 9.2, 8.8, 8.5, 8.0, 8.5 }
    var sums: [10]stat.CusumPoint = zero
    try stat.cusum_control(observations[..], 10.0, 0.5, 4.0, sums[..])
    var high: [10]f64 = zero
    var low: [10]f64 = zero
    var i = 0usize
    while i < sums.len {
        high[i] = sums[i].high
        low[i] = sums[i].low
        i += 1usize
    }
    let limits = stat.ControlLimits { center: 0.0, lower: 0.0, upper: 4.0 }
    try render_control_preview(a, q, output_target, canvas, renderer, high[..], limits, "CUSUM / upper", "C+", "docs/chart-previews/cusum_high.png")
    try render_control_preview(a, q, output_target, canvas, renderer, low[..], limits, "CUSUM / lower", "C-", "docs/chart-previews/cusum_low.png")
    var ewma: [10]stat.AttributeControlPoint = zero
    try stat.ewma_control(observations[..], 10.0, 1.2, 0.3, 3.0, ewma[..])
    ret render_attribute_preview(a, q, output_target, canvas, renderer, ewma[..], "EWMA chart", "Weighted mean", "docs/chart-previews/ewma_control.png")
}

fn render_attribute_preview_phased(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, samples: []const stat.AttributeControlPoint, starts: []const bool, title: str, y_label: str, path: str) -> err {
    if samples.len < 2usize || samples.len > 10usize { ret chart.Invalid }
    if starts.len != 0usize && starts.len != samples.len { ret chart.Invalid }
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    var x: [10]f32 = zero
    var y: [10]f32 = zero
    var low = f32(samples[0usize].lower)
    var high = f32(samples[0usize].upper)
    var i = 0usize
    while i < samples.len {
        x[i] = f32(i) / f32(samples.len - 1usize)
        y[i] = f32(samples[i].value)
        if y[i] < low { low = y[i] }
        if f32(samples[i].lower) < low { low = f32(samples[i].lower) }
        if y[i] > high { high = y[i] }
        if f32(samples[i].upper) > high { high = f32(samples[i].upper) }
        i += 1usize
    }
    var padding = (high - low) * 0.08
    if padding == 0.0 { padding = 1.0 }
    low -= padding
    high += padding
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ low, high }
    var spec = chart.spec(.PointLine, plot, x[..samples.len], y[..samples.len])
    var points: [10]chart.Coord = zero
    var segments: [9]chart.Segment = zero
    let (marks, marks_error) = chart.layout_with_limits(&spec, points[..], segments[..], zero, x_limits[..], y_limits[..])
    if marks_error != ok { ret marks_error }
    var rules: [27]chart.Segment = zero
    var used = 0usize
    i = 0usize
    while i + 1usize < samples.len {
        if starts.len > 0usize && starts[i + 1usize] {
            let boundary_x = plot.x + (x[i] + x[i + 1usize]) * plot.width * 0.5
            rules[used] = chart.Segment { from: chart.Coord { x: boundary_x, y: plot.y }, to: chart.Coord { x: boundary_x, y: plot.y + plot.height } }
            used += 1usize
        } else {
            let from = [3]f32{ f32(samples[i].lower), f32(samples[i].center), f32(samples[i].upper) }
            let to = [3]f32{ f32(samples[i + 1usize].lower), f32(samples[i + 1usize].center), f32(samples[i + 1usize].upper) }
            var j = 0usize
            while j < 3usize {
                rules[used] = chart.Segment {
                    from: chart.Coord { x: plot.x + x[i] * plot.width, y: plot.y + plot.height * (high - from[j]) / (high - low) },
                    to: chart.Coord { x: plot.x + x[i + 1usize] * plot.width, y: plot.y + plot.height * (high - to[j]) / (high - low) },
                }
                used += 1usize
                j += 1usize
            }
        }
        i += 1usize
    }
    let reference = chart.Layout { kind: .Rug, coords: zero, segments: rules[..used], bars: zero, x_min: 0.0, x_max: 1.0, y_min: low, y_max: high }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &marks, &reference, title, "Run fraction", y_label, path)
}

fn render_attribute_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, samples: []const stat.AttributeControlPoint, title: str, y_label: str, path: str) -> err {
    ret render_attribute_preview_phased(a, q, output_target, canvas, renderer, samples, zero, title, y_label, path)
}

fn render_attribute_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let counts = [8]usize{ 2usize, 5usize, 3usize, 8usize, 4usize, 7usize, 1usize, 6usize }
    let counts_c = [8]usize{ 3usize, 1usize, 6usize, 4usize, 8usize, 2usize, 7usize, 5usize }
    let sizes_p = [8]usize{ 50usize, 100usize, 50usize, 100usize, 80usize, 100usize, 50usize, 70usize }
    let sizes_np = [8]usize{ 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize }
    let sizes_c = [8]usize{ 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize }
    let sizes_u = [8]usize{ 5usize, 9usize, 6usize, 8usize, 10usize, 7usize, 5usize, 12usize }
    let kinds = [4]stat.AttributeControlKind{ .P, .Np, .C, .U }
    let sizes = [4][]const usize{ sizes_p[..], sizes_np[..], sizes_c[..], sizes_u[..] }
    let titles = [4]str{ "P chart", "Np chart", "C chart", "U chart" }
    let labels = [4]str{ "Fraction", "Defectives", "Defects", "Rate" }
    let paths = [4]str{ "docs/chart-previews/p_control.png", "docs/chart-previews/np_control.png", "docs/chart-previews/c_control.png", "docs/chart-previews/u_control.png" }
    var samples: [8]stat.AttributeControlPoint = zero
    var i = 0usize
    while i < 4usize {
        var selected = counts[..]
        if kinds[i] == .C { selected = counts_c[..] }
        try stat.attribute_control(kinds[i], selected, sizes[i], samples[..])
        try render_attribute_preview(a, q, output_target, canvas, renderer, samples[..], titles[i], labels[i], paths[i])
        i += 1usize
    }
    let phase_counts = [8]usize{ 2usize, 3usize, 1usize, 4usize, 8usize, 9usize, 7usize, 10usize }
    let phase_starts = [8]bool{ true, false, false, false, true, false, false, false }
    let phase_titles = [4]str{ "Phased P chart", "Phased Np chart", "Phased C chart", "Phased U chart" }
    let phase_paths = [4]str{ "docs/chart-previews/phased_p_control.png", "docs/chart-previews/phased_np_control.png", "docs/chart-previews/phased_c_control.png", "docs/chart-previews/phased_u_control.png" }
    i = 0usize
    while i < 4usize {
        try stat.attribute_control_phased(kinds[i], phase_counts[..], sizes[i], phase_starts[..], samples[..])
        try render_attribute_preview_phased(a, q, output_target, canvas, renderer, samples[..], phase_starts[..], phase_titles[i], labels[i], phase_paths[i])
        i += 1usize
    }
    ret ok
}

fn render_laney_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let p_counts = [8]usize{ 2usize, 10usize, 3usize, 9usize, 1usize, 11usize, 4usize, 8usize }
    let u_counts = [8]usize{ 1usize, 12usize, 0usize, 14usize, 2usize, 11usize, 1usize, 13usize }
    let p_sizes = [8]usize{ 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize }
    let u_sizes = [8]usize{ 10usize, 10usize, 10usize, 10usize, 10usize, 10usize, 10usize, 10usize }
    var samples: [8]stat.AttributeControlPoint = zero
    let (p_sigma, p_error) = stat.laney_control(.P, p_counts[..], p_sizes[..], samples[..])
    if p_error != ok { ret p_error }
    try render_attribute_preview(a, q, output_target, canvas, renderer, samples[..], "Laney P-prime", "Fraction", "docs/chart-previews/laney_p.png")
    let (u_sigma, u_error) = stat.laney_control(.U, u_counts[..], u_sizes[..], samples[..])
    if u_error != ok { ret u_error }
    try render_attribute_preview(a, q, output_target, canvas, renderer, samples[..], "Laney U-prime", "Defect rate", "docs/chart-previews/laney_u.png")
    let phase_starts = [8]bool{ true, false, false, false, true, false, false, false }
    let phase_p_counts = [8]usize{ 2usize, 10usize, 3usize, 9usize, 6usize, 18usize, 7usize, 17usize }
    let phase_u_counts = [8]usize{ 1usize, 12usize, 0usize, 14usize, 4usize, 20usize, 3usize, 18usize }
    let phase_u_sizes = [8]usize{ 10usize, 10usize, 10usize, 10usize, 12usize, 12usize, 12usize, 12usize }
    var sigmas: [8]f64 = zero
    try stat.laney_control_phased(.P, phase_p_counts[..], p_sizes[..], phase_starts[..], samples[..], sigmas[..])
    try render_attribute_preview_phased(a, q, output_target, canvas, renderer, samples[..], phase_starts[..], "Phased Laney P-prime", "Fraction", "docs/chart-previews/phased_laney_p.png")
    try stat.laney_control_phased(.U, phase_u_counts[..], phase_u_sizes[..], phase_starts[..], samples[..], sigmas[..])
    ret render_attribute_preview_phased(a, q, output_target, canvas, renderer, samples[..], phase_starts[..], "Phased Laney U-prime", "Defect rate", "docs/chart-previews/phased_laney_u.png")
}

fn render_rare_event_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let gaps = [10]usize{ 12usize, 14usize, 9usize, 11usize, 16usize, 10usize, 13usize, 8usize, 15usize, 250usize }
    var gap_values: [10]f64 = zero
    var i = 0usize
    while i < gaps.len {
        gap_values[i] = f64(gaps[i])
        i += 1usize
    }
    let (g_limits, g_error) = stat.g_control_limits(gaps[..])
    if g_error != ok { ret g_error }
    try render_control_preview(a, q, output_target, canvas, renderer, gap_values[..], g_limits, "G chart", "Opportunities", "docs/chart-previews/g_control.png")
    let intervals = [10]f64{ 4.0, 3.2, 5.1, 4.8, 3.7, 4.2, 5.4, 3.9, 4.5, 80.0 }
    let (t_limits, t_error) = stat.t_exponential_control_limits(intervals[..])
    if t_error != ok { ret t_error }
    ret render_control_preview(a, q, output_target, canvas, renderer, intervals[..], t_limits, "T chart / exponential", "Days", "docs/chart-previews/t_control.png")
}

fn render_roc_extension_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, data: *const stat.BinaryCurve, partial: bool, path: str) -> err {
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    var x: [17]f32 = zero
    var y: [17]f32 = zero
    var segments: [16]chart.Segment = zero
    let (roc, roc_error) = chart.binary_metric_curve(data, .Roc, plot, x[..], y[..], segments[..])
    if roc_error != ok { ret roc_error }
    if partial {
        var region_points: [19]chart.Coord = zero
        let (region, region_error) = chart.roc_partial_region(data, 0.35, plot, region_points[..])
        if region_error != ok { ret region_error }
        ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &region, &roc, "Partial ROC area", "False-positive rate", "TPR", path)
    }
    let (selected, unused, valid) = stat.youden_index(data)
    if !valid { ret chart.Invalid }
    var marker = roc.segments[0usize].from
    if selected > 0usize { marker = roc.segments[selected - 1usize].to }
    var guides = [2]chart.Segment{
        chart.Segment { from: chart.Coord { x: marker.x, y: plot.y + plot.height }, to: marker },
        chart.Segment { from: chart.Coord { x: plot.x, y: marker.y }, to: marker },
    }
    let highlight = chart.Layout { kind: .Rug, coords: zero, segments: guides[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &highlight, &roc, "Youden index", "False-positive rate", "TPR", path)
}

fn render_decision_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, scores: []const f64, positive: []const bool, path: str) -> err {
    let thresholds = [13]f64{ 0.05f64, 0.10f64, 0.15f64, 0.20f64, 0.25f64, 0.30f64, 0.35f64, 0.40f64, 0.45f64, 0.50f64, 0.55f64, 0.60f64, 0.65f64 }
    var model_values: [13]f64 = zero
    var all_values: [13]f64 = zero
    try stat.decision_curve(scores, positive, thresholds[..], model_values[..], all_values[..])
    var x: [13]f32 = zero
    var model_y: [13]f32 = zero
    var all_y: [13]f32 = zero
    var i = 0usize
    while i < thresholds.len {
        x[i] = f32(thresholds[i])
        model_y[i] = f32(model_values[i])
        all_y[i] = f32(all_values[i])
        i += 1usize
    }
    let plot = geometry.rect(56.0, 45.0, 252.0, 148.0)
    let x_limits = [2]f32{ 0.0, 0.7 }
    let y_limits = [2]f32{ -0.5, 0.6 }
    let model_spec = chart.spec(.Line, plot, x[..], model_y[..])
    let all_spec = chart.spec(.Line, plot, x[..], all_y[..])
    var model_segments: [12]chart.Segment = zero
    var all_segments: [12]chart.Segment = zero
    var unused_coords: [1]chart.Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let (model, model_error) = chart.layout_with_limits(&model_spec, unused_coords[..0usize], model_segments[..], unused_bars[..0usize], x_limits[..], y_limits[..])
    if model_error != ok { ret model_error }
    let (all, all_error) = chart.layout_with_limits(&all_spec, unused_coords[..0usize], all_segments[..], unused_bars[..0usize], x_limits[..], y_limits[..])
    if all_error != ok { ret all_error }
    let zero_y = plot.y + plot.height * 0.6 / 1.1
    var none_segments = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: plot.x, y: zero_y }, to: chart.Coord { x: plot.x + plot.width, y: zero_y } } }
    let none = chart.Layout { kind: .Rug, coords: zero, segments: none_segments[..], bars: zero, x_min: 0.0, x_max: 0.7, y_min: -0.5, y_max: 0.6 }
    let blue = paint.rgba(0.07, 0.38, 0.76, 1.0)
    let orange = paint.rgba(0.88, 0.36, 0.14, 1.0)
    let gray = paint.rgba(0.58, 0.63, 0.70, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let pale = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    var labels: [12]chart.Label = zero
    labels[0usize] = chart.Label { text: "Decision curve", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Threshold probability", anchor: chart.Coord { x: 180.0, y: 231.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "Net benefit", anchor: chart.Coord { x: 56.0, y: 39.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "0", anchor: chart.Coord { x: 56.0, y: 210.0 }, align: .Center }
    labels[4usize] = chart.Label { text: "0.35", anchor: chart.Coord { x: 182.0, y: 210.0 }, align: .Center }
    labels[5usize] = chart.Label { text: "0.7", anchor: chart.Coord { x: 308.0, y: 210.0 }, align: .Center }
    labels[6usize] = chart.Label { text: "0.5", anchor: chart.Coord { x: 52.0, y: 59.0 }, align: .Right }
    labels[7usize] = chart.Label { text: "0", anchor: chart.Coord { x: 52.0, y: zero_y + 3.0 }, align: .Right }
    labels[8usize] = chart.Label { text: "-0.5", anchor: chart.Coord { x: 52.0, y: 193.0 }, align: .Right }
    labels[9usize] = chart.Label { text: "Model", anchor: chart.Coord { x: 157.0, y: 39.0 }, align: .Center }
    labels[10usize] = chart.Label { text: "Treat all", anchor: chart.Coord { x: 225.0, y: 39.0 }, align: .Center }
    labels[11usize] = chart.Label { text: "Treat none", anchor: chart.Coord { x: 294.0, y: 39.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &none, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &all, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &model, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..9usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[9usize..10usize], font, 8.0, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[10usize..11usize], font, 8.0, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[11usize..], font, 8.0, paint.Brush { Solid: gray })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &none, gray)
    try chart_svg.append(&writer, &all, orange)
    try chart_svg.append(&writer, &model, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..9usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[9usize..10usize], blue, 8.0)
    try chart_svg.append_labels(&writer, labels[10usize..11usize], orange, 8.0)
    try chart_svg.append_labels(&writer, labels[11usize..], gray, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_calibration_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, bins: []const stat.CalibrationBin, path: str) -> err {
    var x: [8]f32 = zero
    var y: [8]f32 = zero
    if bins.len > x.len { ret chart.TooLarge }
    var used = 0usize
    var i = 0usize
    while i < bins.len {
        if bins[i].count > 0usize {
            x[used] = f32(bins[i].score_sum / f64(bins[i].count))
            y[used] = f32(f64(bins[i].positives) / f64(bins[i].count))
            used += 1usize
        }
        i += 1usize
    }
    if used == 0usize { ret chart.Empty }
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    let limits = [2]f32{ 0.0, 1.0 }
    let spec = chart.spec(.PointLine, plot, x[..used], y[..used])
    var coords: [8]chart.Coord = zero
    var segments: [7]chart.Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let (marks, marks_error) = chart.layout_with_limits(&spec, coords[..], segments[..], unused_bars[..0usize], limits[..], limits[..])
    if marks_error != ok { ret marks_error }
    var baseline_segments = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: plot.x, y: plot.y + plot.height }, to: chart.Coord { x: plot.x + plot.width, y: plot.y } } }
    let baseline = chart.Layout { kind: .Rug, coords: zero, segments: baseline_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &marks, &baseline, "Calibration", "Mean predicted probability", "Observed", path)
}

fn render_confusion_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, counts: *const stat.BinaryConfusion, path: str) -> err {
    let plot = geometry.rect(70.0, 42.0, 220.0, 160.0)
    let values = [4]f64{ f64(counts.true_negative), f64(counts.false_positive), f64(counts.false_negative), f64(counts.true_positive) }
    var cells: [4]chart.Cell = zero
    let (marks, marks_error) = chart.heatmap(values[..], 2usize, plot, cells[..])
    if marks_error != ok { ret marks_error }
    let low = paint.rgba(0.89, 0.94, 0.98, 1.0)
    let middle = paint.rgba(0.58, 0.76, 0.91, 1.0)
    let high = paint.rgba(0.10, 0.39, 0.67, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    var count_ticks: [4]chart.Tick = zero
    var i = 0usize
    while i < 4usize {
        count_ticks[i] = chart.Tick { value: f32(values[i]), fraction: 0.0 }
        i += 1usize
    }
    var count_words: [4]str = zero
    var count_bytes: [64]u8 = zero
    let (words, words_error) = chart.format_ticks(count_ticks[..], count_words[..], count_bytes[..])
    if words_error != ok { ret words_error }
    var labels: [9]chart.Label = zero
    i = 0usize
    while i < 4usize {
        let cell = marks.cells[i].rect
        labels[i] = chart.Label { text: words[i], anchor: chart.Coord { x: cell.x + cell.width * 0.5, y: cell.y + cell.height * 0.56 }, align: .Center }
        i += 1usize
    }
    labels[4usize] = chart.Label { text: "Actual -", anchor: chart.Coord { x: 65.0, y: 88.0 }, align: .Right }
    labels[5usize] = chart.Label { text: "Actual +", anchor: chart.Coord { x: 65.0, y: 168.0 }, align: .Right }
    labels[6usize] = chart.Label { text: "Predicted -", anchor: chart.Coord { x: 125.0, y: 219.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "Predicted +", anchor: chart.Coord { x: 235.0, y: 219.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "Confusion matrix", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_matrix(&builder, &marks, low, middle, high)
    try chart_scene.append_labels(a, &builder, labels[..8usize], font, 10.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 14.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_matrix(&writer, &marks, low, middle, high)
    try chart_svg.append_labels(&writer, labels[..8usize], dark, 10.0)
    try chart_svg.append_labels(&writer, labels[8usize..], dark, 14.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_mekko(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, categories: []const str, names: []const str, path: str) -> err {
    if layers.len != 3usize || categories.len != 4usize || names.len != layers.len || layers[0usize].bars.len != categories.len { ret chart.Invalid }
    let colors = [3]paint.Color{
        paint.rgba(0.08, 0.37, 0.75, 1.0), paint.rgba(0.92, 0.42, 0.13, 1.0), paint.rgba(0.16, 0.58, 0.43, 1.0),
    }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var legend: [3]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(names, chart.Coord { x: 268.0, y: 63.0 }, 10.0, 31.0, legend[..])
    if legend_error != ok { ret legend_error }
    var labels: [8]chart.Label = zero
    var i = 0usize
    while i < categories.len {
        let bar = layers[0usize].bars[i]
        labels[i] = chart.Label { text: categories[i], anchor: chart.Coord { x: bar.x + bar.width * 0.5, y: 209.0 }, align: .Center }
        i += 1usize
    }
    labels[4usize] = chart.Label { text: "100%", anchor: chart.Coord { x: 31.0, y: 48.0 }, align: .Right }
    labels[5usize] = chart.Label { text: "50%", anchor: chart.Coord { x: 31.0, y: 122.0 }, align: .Right }
    labels[6usize] = chart.Label { text: "0%", anchor: chart.Coord { x: 31.0, y: 195.0 }, align: .Right }
    labels[7usize] = chart.Label { text: "Marimekko shares", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var legend_labels: [3]chart.Label = zero
    i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: colors[i] })
        legend_labels[i] = entries[i].label
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..7usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[7usize..], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, legend_labels[..], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        try chart_svg.rect(&writer, entries[i].swatch, colors[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..7usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[7usize..], dark, 13.0)
    try chart_svg.append_labels(&writer, legend_labels[..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_mosaic_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let counts = [12]f64{ 12.0, 2.0, 1.0, 2.0, 10.0, 3.0, 7.0, 5.0, 10.0, 3.0, 1.0, 8.0 }
    var columns: [4]f64 = zero
    var rows: [3]f64 = zero
    var cells: [12]chart.Cell = zero
    let (marks, marks_error) = chart.mosaic(counts[..], 4usize, geometry.rect(45.0, 43.0, 222.0, 149.0), 2.0, columns[..], rows[..], cells[..])
    if marks_error != ok { ret marks_error }
    let low = paint.rgba(0.80, 0.24, 0.29, 1.0)
    let neutral = paint.rgba(0.96, 0.96, 0.96, 1.0)
    let high = paint.rgba(0.08, 0.38, 0.75, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let names = [4]str{ "A", "B", "C", "D" }
    var labels: [7]chart.Label = zero
    var grand = 0.0f64
    var i = 0usize
    while i < columns.len {
        grand += columns[i]
        i += 1usize
    }
    var cumulative = 0.0f64
    i = 0usize
    while i < 4usize {
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: 45.0 + 222.0 * f32((cumulative + columns[i] / 2.0f64) / grand), y: 209.0 }, align: .Center }
        cumulative += columns[i]
        i += 1usize
    }
    labels[4usize] = chart.Label { text: "Mosaic • residuals", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[5usize] = chart.Label { text: "Deficit", anchor: chart.Coord { x: 301.0, y: 80.0 }, align: .Center }
    labels[6usize] = chart.Label { text: "Surplus", anchor: chart.Coord { x: 301.0, y: 126.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 20u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let deficit = geometry.rect(295.0, 57.0, 12.0, 12.0)
    let surplus = geometry.rect(295.0, 103.0, 12.0, 12.0)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_matrix(&builder, &marks, low, neutral, high)
    try fill(&builder, deficit, paint.Brush { Solid: low })
    try fill(&builder, surplus, paint.Brush { Solid: high })
    try chart_scene.append_labels(a, &builder, labels[..4usize], font, 10.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..5usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[5usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/mosaic.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_matrix(&writer, &marks, low, neutral, high)
    try chart_svg.rect(&writer, deficit, low, false)
    try chart_svg.rect(&writer, surplus, high, false)
    try chart_svg.append_labels(&writer, labels[..4usize], dark, 10.0)
    try chart_svg.append_labels(&writer, labels[4usize..5usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[5usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_association_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let counts = [12]f64{ 12.0, 2.0, 1.0, 2.0, 10.0, 3.0, 7.0, 5.0, 10.0, 3.0, 1.0, 8.0 }
    let bounds = geometry.rect(60.0, 47.0, 220.0, 145.0)
    var columns: [4]f64 = zero
    var rows: [3]f64 = zero
    var cells: [12]chart.Cell = zero
    var baselines: [3]chart.Segment = zero
    let (marks, marks_error) = chart.association(counts[..], 4usize, bounds, 0.08, columns[..], rows[..], cells[..], baselines[..])
    if marks_error != ok { ret marks_error }
    let guides = chart.Layout { kind: .Rug, coords: zero, segments: baselines[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let deficit = paint.rgba(0.80, 0.24, 0.29, 1.0)
    let neutral = paint.rgba(0.96, 0.96, 0.96, 1.0)
    let surplus = paint.rgba(0.08, 0.38, 0.75, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let rule = paint.rgba(0.69, 0.73, 0.80, 1.0)
    let row_names = [3]str{ "R1", "R2", "R3" }
    let column_names = [4]str{ "A", "B", "C", "D" }
    var labels: [10]chart.Label = zero
    var i = 0usize
    while i < rows.len {
        labels[i] = chart.Label { text: row_names[i], anchor: chart.Coord { x: 51.0, y: baselines[i].from.y + 3.0 }, align: .Right }
        i += 1usize
    }
    var root_total = 0.0f64
    i = 0usize
    while i < columns.len {
        root_total += math.sqrt[f64](columns[i])
        i += 1usize
    }
    var cumulative = 0.0f64
    i = 0usize
    while i < columns.len {
        let width = math.sqrt[f64](columns[i])
        labels[3usize + i] = chart.Label { text: column_names[i], anchor: chart.Coord { x: bounds.x + bounds.width * f32((cumulative + width * 0.5f64) / root_total), y: 211.0 }, align: .Center }
        cumulative += width
        i += 1usize
    }
    labels[7usize] = chart.Label { text: "Association • residuals", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "Deficit", anchor: chart.Coord { x: 301.0, y: 83.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "Surplus", anchor: chart.Coord { x: 301.0, y: 129.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 21u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let deficit_swatch = geometry.rect(295.0, 60.0, 12.0, 12.0)
    let surplus_swatch = geometry.rect(295.0, 106.0, 12.0, 12.0)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append(a, &builder, &guides, paint.Brush { Solid: rule })
    try chart_scene.append_matrix(&builder, &marks, deficit, neutral, surplus)
    try fill(&builder, deficit_swatch, paint.Brush { Solid: deficit })
    try fill(&builder, surplus_swatch, paint.Brush { Solid: surplus })
    try chart_scene.append_labels(a, &builder, labels[..7usize], font, 10.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[7usize..8usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/association.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &guides, rule)
    try chart_svg.append_matrix(&writer, &marks, deficit, neutral, surplus)
    try chart_svg.rect(&writer, deficit_swatch, deficit, false)
    try chart_svg.rect(&writer, surplus_swatch, surplus, false)
    try chart_svg.append_labels(&writer, labels[..7usize], dark, 10.0)
    try chart_svg.append_labels(&writer, labels[7usize..8usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[8usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_fourfold_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let counts = [4]f64{ 10.0, 2.0, 4.0, 8.0 }
    let bounds = geometry.rect(48.0, 45.0, 190.0, 175.0)
    var points: [72]chart.Coord = zero
    var ring_segments: [128]chart.Segment = zero
    var wedges: [4]chart.Layout = zero
    let (marks, marks_error) = chart.fourfold(counts[..], bounds, 0.95, points[..], ring_segments[..], wedges[..])
    if marks_error != ok { ret marks_error }
    var cross_segments: [2]chart.Segment = zero
    cross_segments[0usize] = chart.Segment { from: chart.Coord { x: 48.0, y: 132.5 }, to: chart.Coord { x: 238.0, y: 132.5 } }
    cross_segments[1usize] = chart.Segment { from: chart.Coord { x: 143.0, y: 45.0 }, to: chart.Coord { x: 143.0, y: 220.0 } }
    let cross = chart.Layout { kind: .Rug, coords: zero, segments: cross_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let same = paint.rgba(0.08, 0.38, 0.75, 1.0)
    let other = paint.rgba(0.80, 0.24, 0.29, 1.0)
    let ring = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let same_swatch = geometry.rect(271.0, 77.0, 14.0, 14.0)
    let other_swatch = geometry.rect(271.0, 128.0, 14.0, 14.0)
    var labels: [8]chart.Label = zero
    labels[0usize] = chart.Label { text: "Fourfold • 95% CI", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "OR = 10", anchor: chart.Coord { x: 302.0, y: 58.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "Same", anchor: chart.Coord { x: 303.0, y: 106.0 }, align: .Center }
    labels[3usize] = chart.Label { text: "Opposite", anchor: chart.Coord { x: 303.0, y: 157.0 }, align: .Center }
    labels[4usize] = chart.Label { text: "10", anchor: chart.Coord { x: 102.0, y: 99.0 }, align: .Center }
    labels[5usize] = chart.Label { text: "2", anchor: chart.Coord { x: 121.0, y: 153.0 }, align: .Center }
    labels[6usize] = chart.Label { text: "4", anchor: chart.Coord { x: 163.0, y: 114.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "8", anchor: chart.Coord { x: 184.0, y: 174.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 22u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 180usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    var i = 0usize
    while i < marks.wedges.len {
        var color = same
        if i == 1usize || i == 2usize { color = other }
        try chart_scene.append(a, &builder, &marks.wedges[i], paint.Brush { Solid: color })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &marks.rings, paint.Brush { Solid: ring })
    try chart_scene.append(a, &builder, &cross, paint.Brush { Solid: dark })
    try fill(&builder, same_swatch, paint.Brush { Solid: same })
    try fill(&builder, other_swatch, paint.Brush { Solid: other })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..4usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..], font, 10.0, paint.Brush { Solid: white })
    let path = "docs/chart-previews/fourfold.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < marks.wedges.len {
        var color = same
        if i == 1usize || i == 2usize { color = other }
        try chart_svg.append(&writer, &marks.wedges[i], color)
        i += 1usize
    }
    try chart_svg.append(&writer, &marks.rings, ring)
    try chart_svg.append(&writer, &cross, dark)
    try chart_svg.rect(&writer, same_swatch, same, false)
    try chart_svg.rect(&writer, other_swatch, other, false)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..4usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[4usize..], white, 10.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_horizon_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let x = [18]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0 }
    let y = [18]f32{ 0.0, 0.8, 1.7, 2.8, 2.2, 0.5, -1.2, -2.4, -1.6, 0.2, 1.3, 2.9, 2.1, -0.4, -1.8, -2.8, -1.0, 0.3 }
    let bounds = geometry.rect(43.0, 48.0, 232.0, 137.0)
    var points: [2048]chart.Coord = zero
    var storage: [512]chart.HorizonPatch = zero
    let (patches, layout_error) = chart.horizon(x[..], y[..], 0.0, 1.0, 3usize, bounds, points[..], storage[..])
    if layout_error != ok { ret layout_error }
    let positive = [3]paint.Color{ paint.rgba(0.72, 0.85, 0.96, 1.0), paint.rgba(0.30, 0.61, 0.83, 1.0), paint.rgba(0.04, 0.33, 0.69, 1.0) }
    let negative = [3]paint.Color{ paint.rgba(0.96, 0.73, 0.74, 1.0), paint.rgba(0.84, 0.36, 0.41, 1.0), paint.rgba(0.63, 0.13, 0.22, 1.0) }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let light_rule = paint.rgba(0.73, 0.77, 0.83, 1.0)
    var labels: [12]chart.Label = zero
    labels[0usize] = chart.Label { text: "Horizon • folded bands", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "0", anchor: chart.Coord { x: 43.0, y: 207.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "4", anchor: chart.Coord { x: 97.6, y: 207.0 }, align: .Center }
    labels[3usize] = chart.Label { text: "8", anchor: chart.Coord { x: 152.2, y: 207.0 }, align: .Center }
    labels[4usize] = chart.Label { text: "12", anchor: chart.Coord { x: 206.8, y: 207.0 }, align: .Center }
    labels[5usize] = chart.Label { text: "17", anchor: chart.Coord { x: 275.0, y: 207.0 }, align: .Center }
    let legend_names = [6]str{ "+1", "+2", "+3", "-1", "-2", "-3" }
    var swatches: [6]geometry.Rect = zero
    var i = 0usize
    while i < 6usize {
        let top = 60.0 + f32(i) * 25.0
        swatches[i] = geometry.rect(294.0, top, 13.0, 13.0)
        labels[i + 6usize] = chart.Label { text: legend_names[i], anchor: chart.Coord { x: 324.0, y: top + 11.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 23u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < patches.len {
        var color = positive[patches[i].band]
        if patches[i].negative { color = negative[patches[i].band] }
        try chart_scene.append(a, &builder, &patches[i].layout, paint.Brush { Solid: color })
        i += 1usize
    }
    try fill(&builder, geometry.rect(bounds.x, bounds.y + bounds.height, bounds.width, 1.0), paint.Brush { Solid: light_rule })
    i = 0usize
    while i < 6usize {
        var color = positive[0usize]
        if i < 3usize { color = positive[i] } else { color = negative[i - 3usize] }
        try fill(&builder, swatches[i], paint.Brush { Solid: color })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/horizon.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < patches.len {
        var color = positive[patches[i].band]
        if patches[i].negative { color = negative[patches[i].band] }
        try chart_svg.append(&writer, &patches[i].layout, color)
        i += 1usize
    }
    try chart_svg.rect(&writer, geometry.rect(bounds.x, bounds.y + bounds.height, bounds.width, 1.0), light_rule, false)
    i = 0usize
    while i < 6usize {
        var color = positive[0usize]
        if i < 3usize { color = positive[i] } else { color = negative[i - 3usize] }
        try chart_svg.rect(&writer, swatches[i], color, false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_seasonal_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [16]f32{ 8.0, 12.0, 18.0, 11.0, 9.0, 13.0, 20.0, 12.0, 10.0, 16.0, 21.0, 13.0, 11.0, 17.0, 23.0, 14.0 }
    let bounds = geometry.rect(44.0, 49.0, 272.0, 139.0)
    var segments: [12]chart.Segment = zero
    var means: [4]chart.Segment = zero
    var storage: [4]chart.Layout = zero
    let (series, mean_marks, layout_error) = chart.seasonal_subseries(values[..], 4usize, bounds, segments[..], means[..], storage[..])
    if layout_error != ok { ret layout_error }
    let blue = paint.rgba(0.06, 0.35, 0.72, 1.0)
    let orange = paint.rgba(0.88, 0.34, 0.13, 1.0)
    let pale = paint.rgba(0.95, 0.97, 0.99, 1.0)
    let rule = paint.rgba(0.79, 0.82, 0.87, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let labels = [6]chart.Label{
        chart.Label { text: "Seasonal subseries • quarters", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "Q1", anchor: chart.Coord { x: 78.0, y: 205.0 }, align: .Center },
        chart.Label { text: "Q2", anchor: chart.Coord { x: 146.0, y: 205.0 }, align: .Center },
        chart.Label { text: "Q3", anchor: chart.Coord { x: 214.0, y: 205.0 }, align: .Center },
        chart.Label { text: "Q4", anchor: chart.Coord { x: 282.0, y: 205.0 }, align: .Center },
        chart.Label { text: "Blue: year sequence     Orange: quarter mean", anchor: chart.Coord { x: 180.0, y: 228.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 24u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var i = 0usize
    while i < 4usize {
        if i % 2usize == 0usize { try fill(&builder, geometry.rect(bounds.x + f32(i) * 68.0, bounds.y, 68.0, bounds.height), paint.Brush { Solid: pale }) }
        if i > 0usize { try fill(&builder, geometry.rect(bounds.x + f32(i) * 68.0, bounds.y, 1.0, bounds.height), paint.Brush { Solid: rule }) }
        i += 1usize
    }
    try chart_scene.append(a, &builder, &mean_marks, paint.Brush { Solid: orange })
    i = 0usize
    while i < series.len {
        try chart_scene.append(a, &builder, &series[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/seasonal_subseries.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 4usize {
        if i % 2usize == 0usize { try chart_svg.rect(&writer, geometry.rect(bounds.x + f32(i) * 68.0, bounds.y, 68.0, bounds.height), pale, false) }
        if i > 0usize { try chart_svg.rect(&writer, geometry.rect(bounds.x + f32(i) * 68.0, bounds.y, 1.0, bounds.height), rule, false) }
        i += 1usize
    }
    try chart_svg.append(&writer, &mean_marks, orange)
    i = 0usize
    while i < series.len {
        try chart_svg.append(&writer, &series[i], blue)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_fan_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let x = [8]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 }
    let median = [8]f32{ 52.0, 54.0, 57.0, 59.0, 62.0, 65.0, 66.0, 68.0 }
    let lower = [24]f32{ 48.0, 47.0, 46.0, 44.0, 42.0, 40.0, 38.0, 36.0, 49.0, 50.0, 50.0, 51.0, 52.0, 53.0, 54.0, 55.0, 50.0, 52.0, 54.0, 56.0, 58.0, 60.0, 61.0, 63.0 }
    let upper = [24]f32{ 56.0, 61.0, 66.0, 72.0, 78.0, 83.0, 88.0, 93.0, 55.0, 58.0, 62.0, 66.0, 70.0, 74.0, 77.0, 81.0, 54.0, 56.0, 59.0, 62.0, 65.0, 68.0, 70.0, 73.0 }
    let bounds = geometry.rect(43.0, 47.0, 274.0, 141.0)
    var outlines: [48]chart.Coord = zero
    var median_segments: [7]chart.Segment = zero
    var storage: [3]chart.Layout = zero
    let (bands, middle, layout_error) = chart.fan(x[..], median[..], lower[..], upper[..], 3usize, bounds, outlines[..], median_segments[..], storage[..])
    if layout_error != ok { ret layout_error }
    let shades = [3]paint.Color{ paint.rgba(0.78, 0.87, 0.97, 1.0), paint.rgba(0.51, 0.72, 0.93, 1.0), paint.rgba(0.23, 0.53, 0.83, 1.0) }
    let navy = paint.rgba(0.05, 0.23, 0.54, 1.0)
    let rule = paint.rgba(0.90, 0.92, 0.95, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let legend_names = [4]str{ "95%", "80%", "50%", "Median" }
    var labels: [8]chart.Label = zero
    labels[0usize] = chart.Label { text: "Forecast fan • nested intervals", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Now", anchor: chart.Coord { x: 43.0, y: 205.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "+4", anchor: chart.Coord { x: 199.6, y: 205.0 }, align: .Center }
    labels[3usize] = chart.Label { text: "+7", anchor: chart.Coord { x: 317.0, y: 205.0 }, align: .Center }
    var swatches: [4]geometry.Rect = zero
    var i = 0usize
    while i < 4usize {
        swatches[i] = geometry.rect(44.0 + f32(i) * 73.0, 219.0, 13.0, 5.0)
        labels[i + 4usize] = chart.Label { text: legend_names[i], anchor: chart.Coord { x: 76.0 + f32(i) * 73.0, y: 226.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 25u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 1usize
    while i < 4usize {
        try fill(&builder, geometry.rect(bounds.x, bounds.y + f32(i) * bounds.height / 4.0, bounds.width, 1.0), paint.Brush { Solid: rule })
        i += 1usize
    }
    i = 0usize
    while i < bands.len {
        try chart_scene.append(a, &builder, &bands[i], paint.Brush { Solid: shades[i] })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &middle, paint.Brush { Solid: navy })
    i = 0usize
    while i < 4usize {
        var color = navy
        if i < 3usize { color = shades[i] }
        try fill(&builder, swatches[i], paint.Brush { Solid: color })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/fan_forecast.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 1usize
    while i < 4usize {
        try chart_svg.rect(&writer, geometry.rect(bounds.x, bounds.y + f32(i) * bounds.height / 4.0, bounds.width, 1.0), rule, false)
        i += 1usize
    }
    i = 0usize
    while i < bands.len {
        try chart_svg.append(&writer, &bands[i], shades[i])
        i += 1usize
    }
    try chart_svg.append(&writer, &middle, navy)
    i = 0usize
    while i < 4usize {
        var color = navy
        if i < 3usize { color = shades[i] }
        try chart_svg.rect(&writer, swatches[i], color, false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_decomposition_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [24]f32{ 16.0, 20.0, 24.0, 31.0, 24.0, 21.0, 20.0, 25.0, 27.0, 34.0, 29.0, 26.0, 25.0, 30.0, 37.0, 39.0, 34.0, 31.0, 30.0, 35.0, 37.0, 44.0, 39.0, 36.0 }
    let bounds = geometry.rect(72.0, 45.0, 256.0, 146.0)
    let gap = 4.0f32
    let panel_height = (bounds.height - 3.0 * gap) / 4.0
    var trend: [24]f32 = zero
    var seasonal: [24]f32 = zero
    var residual: [24]f32 = zero
    var segments: [92]chart.Segment = zero
    var storage: [4]chart.Layout = zero
    let (panels, _, _, chart_error) = chart.decomposition(values[..], 6usize, bounds, gap, trend[..], seasonal[..], residual[..], segments[..], storage[..])
    if chart_error != ok { ret chart_error }
    let inks = [4]paint.Color{ paint.rgba(0.06, 0.34, 0.71, 1.0), paint.rgba(0.12, 0.55, 0.45, 1.0), paint.rgba(0.88, 0.42, 0.14, 1.0), paint.rgba(0.67, 0.22, 0.37, 1.0) }
    let pale = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let names = [4]str{ "Observed", "Trend", "Seasonal", "Remainder" }
    var labels: [7]chart.Label = zero
    labels[0usize] = chart.Label { text: "Additive time-series decomposition", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    var i = 0usize
    while i < 4usize {
        labels[i + 1usize] = chart.Label { text: names[i], anchor: chart.Coord { x: 65.0, y: bounds.y + f32(i) * (panel_height + gap) + panel_height * 0.5 + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[5usize] = chart.Label { text: "1", anchor: chart.Coord { x: 72.0, y: 210.0 }, align: .Center }
    labels[6usize] = chart.Label { text: "24", anchor: chart.Coord { x: 328.0, y: 210.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 26u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < 4usize {
        let box = geometry.rect(bounds.x, bounds.y + f32(i) * (panel_height + gap), bounds.width, panel_height)
        try fill(&builder, box, paint.Brush { Solid: pale })
        try chart_scene.append(a, &builder, &panels[i], paint.Brush { Solid: inks[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/decomposition.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 4usize {
        let box = geometry.rect(bounds.x, bounds.y + f32(i) * (panel_height + gap), bounds.width, panel_height)
        try chart_svg.rect(&writer, box, pale, false)
        try chart_svg.append(&writer, &panels[i], inks[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_correlogram_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let values = [28]f32{ 0.4, 1.1, 1.4, 0.9, 0.2, -0.3, -0.7, -0.2, 0.5, 1.2, 1.0, 0.3, -0.4, -0.8, -0.4, 0.1, 0.8, 1.3, 0.7, 0.0, -0.6, -0.9, -0.3, 0.4, 1.0, 0.6, -0.1, -0.5 }
    let bounds = geometry.rect(49.0, 44.0, 278.0, 148.0)
    let gap = 10.0f32
    let panel_height = (bounds.height - gap) * 0.5
    var acf: [13]f64 = zero
    var pacf: [13]f64 = zero
    var coefficients: [13]f64 = zero
    var next: [13]f64 = zero
    var stems: [25]chart.Segment = zero
    var guides: [6]chart.Segment = zero
    var storage: [2]chart.Layout = zero
    let (panels, guide_marks, chart_error) = chart.correlogram(values[..], 12usize, bounds, gap, acf[..], pacf[..], coefficients[..], next[..], stems[..], guides[..], storage[..])
    if chart_error != ok { ret chart_error }
    let inks = [2]paint.Color{ paint.rgba(0.06, 0.35, 0.72, 1.0), paint.rgba(0.88, 0.40, 0.13, 1.0) }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let rule = paint.rgba(0.73, 0.78, 0.85, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var labels: [6]chart.Label = zero
    labels[0usize] = chart.Label { text: "ACF / PACF correlogram", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "ACF", anchor: chart.Coord { x: 43.0, y: bounds.y + panel_height * 0.5 + 3.0 }, align: .Right }
    labels[2usize] = chart.Label { text: "PACF", anchor: chart.Coord { x: 43.0, y: bounds.y + panel_height + gap + panel_height * 0.5 + 3.0 }, align: .Right }
    labels[3usize] = chart.Label { text: "0", anchor: chart.Coord { x: bounds.x, y: 207.0 }, align: .Center }
    labels[4usize] = chart.Label { text: "12 lags", anchor: chart.Coord { x: bounds.x + bounds.width, y: 207.0 }, align: .Center }
    labels[5usize] = chart.Label { text: "95% reference = ±1.96/√n", anchor: chart.Coord { x: 180.0, y: 226.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 27u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var i = 0usize
    while i < 2usize {
        let box = geometry.rect(bounds.x, bounds.y + f32(i) * (panel_height + gap), bounds.width, panel_height)
        try fill(&builder, box, paint.Brush { Solid: pale })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &guide_marks, paint.Brush { Solid: rule })
    i = 0usize
    while i < 2usize {
        try chart_scene.append(a, &builder, &panels[i], paint.Brush { Solid: inks[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/correlogram.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 2usize {
        let box = geometry.rect(bounds.x, bounds.y + f32(i) * (panel_height + gap), bounds.width, panel_height)
        try chart_svg.rect(&writer, box, pale, false)
        i += 1usize
    }
    try chart_svg.append(&writer, &guide_marks, rule)
    i = 0usize
    while i < 2usize {
        try chart_svg.append(&writer, &panels[i], inks[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_variogram_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    var x: [25]f32 = zero
    var y: [25]f32 = zero
    var values: [25]f32 = zero
    var i = 0usize
    while i < values.len {
        x[i] = f32(i % 5usize) * 0.25
        y[i] = f32(i / 5usize) * 0.25
        values[i] = 1.0 + 2.0 * x[i] + 0.8 * y[i] + f32((i * 7usize) % 5usize) * 0.11
        i += 1usize
    }
    var pair_counts: [6]u64 = zero
    var distances: [6]f64 = zero
    var semivariances: [6]f64 = zero
    var points: [6]chart.Coord = zero
    let (marks, chart_error) = chart.variogram(x[..], y[..], values[..], 1.0, geometry.rect(56.0, 43.0, 252.0, 150.0), pair_counts[..], distances[..], semivariances[..], points[..])
    if chart_error != ok { ret chart_error }
    let empty = chart.Layout { kind: .Rug, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &marks, &empty, "Empirical semivariogram", "Pair distance", "Semivariance", "docs/chart-previews/variogram.png")
}

fn render_population_pyramid(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, bars: []geometry.Rect, ages: []const str, path: str) -> err {
    if layers.len != 2usize || ages.len != 6usize || bars.len != ages.len * 2usize { ret chart.Invalid }
    let colors = [2]paint.Color{ paint.rgba(0.08, 0.37, 0.72, 1.0), paint.rgba(0.89, 0.39, 0.16, 1.0) }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [9]chart.Label = zero
    var i = 0usize
    while i < ages.len {
        labels[i] = chart.Label { text: ages[i], anchor: chart.Coord { x: 180.0, y: bars[i].y + bars[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[6usize] = chart.Label { text: "Population pyramid", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "Group A", anchor: chart.Coord { x: 88.0, y: 45.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "Group B", anchor: chart.Coord { x: 272.0, y: 45.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..6usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[7usize..], font, 10.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[6usize..7usize], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..6usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[7usize..], dark, 10.0)
    try chart_svg.append_labels(&writer, labels[6usize..7usize], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_bullet(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, path: str) -> err {
    if layers.len != 5usize { ret chart.Invalid }
    let plot = geometry.rect(44.0, 86.0, 286.0, 66.0)
    let colors = [5]paint.Color{
        paint.rgba(0.88, 0.91, 0.95, 1.0), paint.rgba(0.73, 0.78, 0.86, 1.0),
        paint.rgba(0.58, 0.65, 0.76, 1.0), paint.rgba(0.07, 0.35, 0.76, 1.0),
        paint.rgba(0.95, 0.35, 0.10, 1.0),
    }
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var tick_storage: [5]chart.Tick = zero
    let (ticks, tick_error) = chart.nice_ticks(linear, 0.0, layers[0].x_max, 5usize, tick_storage[..])
    if tick_error != ok { ret tick_error }
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, ticks, ticks[..0usize], paint.Brush { Solid: colors[0] }, paint.Brush { Solid: axis_color })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, ticks, ticks[..0usize], colors[0], axis_color)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_gauge(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, path: str) -> err {
    if layers.len != 3usize { ret chart.Invalid }
    let colors = [3]paint.Color{ paint.rgba(0.86, 0.90, 0.94, 1.0), paint.rgba(0.08, 0.40, 0.77, 1.0), paint.rgba(0.91, 0.37, 0.14, 1.0) }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let names = [2]str{ "Actual 72", "Target 80" }
    var legend: [2]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(names[..], chart.Coord { x: 238.0, y: 89.0 }, 11.0, 38.0, legend[..])
    if legend_error != ok { ret legend_error }
    let labels = [4]chart.Label{
        entries[0usize].label,
        entries[1usize].label,
        chart.Label { text: "72%", anchor: chart.Coord { x: 123.0, y: 162.0 }, align: .Center },
        chart.Label { text: "Target gauge", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: colors[i + 1usize] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..3usize], font, 23.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[3usize..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try chart_svg.rect(&writer, entries[i].swatch, colors[i + 1usize], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[2usize..3usize], dark, 23.0)
    try chart_svg.append_labels(&writer, labels[3usize..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_kpi(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, status: chart.TargetStatus, path: str) -> err {
    if layers.len != 5usize { ret chart.Invalid }
    var actual_color = paint.rgba(0.72, 0.22, 0.22, 1.0)
    if status.achieved { actual_color = paint.rgba(0.08, 0.55, 0.38, 1.0) }
    let colors = [5]paint.Color{
        paint.rgba(0.89, 0.92, 0.95, 1.0), paint.rgba(0.77, 0.83, 0.88, 1.0),
        paint.rgba(0.64, 0.72, 0.80, 1.0), actual_color, paint.rgba(0.91, 0.37, 0.14, 1.0),
    }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let labels = [6]chart.Label{
        chart.Label { text: "Service KPI", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "96%", anchor: chart.Coord { x: 36.0, y: 103.0 }, align: .Left },
        chart.Label { text: "16 above target", anchor: chart.Coord { x: 38.0, y: 130.0 }, align: .Left },
        chart.Label { text: "Target 80%", anchor: chart.Coord { x: 238.0, y: 130.0 }, align: .Left },
        chart.Label { text: "0", anchor: chart.Coord { x: 34.0, y: 213.0 }, align: .Left },
        chart.Label { text: "100", anchor: chart.Coord { x: 326.0, y: 213.0 }, align: .Right },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 32.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..3usize], font, 10.0, paint.Brush { Solid: actual_color })
    try chart_scene.append_labels(a, &builder, labels[3usize..4usize], font, 9.0, paint.Brush { Solid: colors[4usize] })
    try chart_scene.append_labels(a, &builder, labels[4usize..], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 32.0)
    try chart_svg.append_labels(&writer, labels[2usize..3usize], actual_color, 10.0)
    try chart_svg.append_labels(&writer, labels[3usize..4usize], colors[4usize], 9.0)
    try chart_svg.append_labels(&writer, labels[4usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_dual_axis(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, categories: []const str, title: str, percent: bool, path: str) -> err {
    if layers.len != 2usize || categories.len != 5usize || categories.len != layers[0].bars.len { ret chart.Invalid }
    let plot = geometry.rect(48.0, 36.0, 246.0, 158.0)
    let bar_color = paint.rgba(0.07, 0.35, 0.76, 1.0)
    let line_color = paint.rgba(0.94, 0.42, 0.12, 1.0)
    let grid_color = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_storage: [5]chart.Tick = zero
    var y_storage: [5]chart.Tick = zero
    var percent_storage: [5]chart.Tick = zero
    let (x_ticks, x_error) = chart.category_ticks(categories.len, x_storage[..])
    if x_error != ok { ret x_error }
    let (y_ticks, y_error) = chart.ticks(linear, layers[0].y_min, layers[0].y_max, y_storage[..])
    if y_error != ok { ret y_error }
    let (right_ticks, right_error) = chart.ticks(linear, layers[1].y_min, layers[1].y_max, percent_storage[..])
    if right_error != ok { ret right_error }
    var y_words: [5]str = zero
    var text_storage: [128]u8 = zero
    let (count_words, count_error) = chart.format_ticks(y_ticks, y_words[..], text_storage[..])
    if count_error != ok { ret count_error }
    var labels: [16]chart.Label = zero
    let (base_labels, label_error) = chart.guide_labels(plot, x_ticks, categories, y_ticks, count_words, 9.0, labels[..10usize])
    if label_error != ok { ret label_error }
    let percent_words = [5]str{ "0%", "25%", "50%", "75%", "100%" }
    var right_words: [5]str = zero
    var right_text: [128]u8 = zero
    if percent {
        var j = 0usize
        while j < percent_words.len {
            right_words[j] = percent_words[j]
            j += 1usize
        }
    } else {
        let (_, right_text_error) = chart.format_ticks(right_ticks, right_words[..], right_text[..])
        if right_text_error != ok { ret right_text_error }
    }
    var i = 0usize
    while i < right_ticks.len {
        labels[base_labels.len + i] = chart.Label { text: right_words[i], anchor: chart.Coord { x: plot.x + plot.width + 9.0, y: plot.y + plot.height * (1.0 - right_ticks[i].fraction) + 3.0 }, align: .Left }
        i += 1usize
    }
    labels[15usize] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, x_ticks, y_ticks, paint.Brush { Solid: grid_color }, paint.Brush { Solid: axis_color })
    try fill(&builder, geometry.rect(plot.x + plot.width, plot.y, 1.0, plot.height), paint.Brush { Solid: axis_color })
    i = 0usize
    while i < right_ticks.len {
        let y = plot.y + plot.height * (1.0 - right_ticks[i].fraction)
        try fill(&builder, geometry.rect(plot.x + plot.width, y, 5.0, 1.0), paint.Brush { Solid: axis_color })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &layers[0], paint.Brush { Solid: bar_color })
    try chart_scene.append(a, &builder, &layers[1], paint.Brush { Solid: line_color })
    try chart_scene.append_labels(a, &builder, labels[..15usize], font, 9.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, labels[15usize..], font, 11.0, paint.Brush { Solid: axis_color })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, x_ticks, y_ticks, grid_color, axis_color)
    try chart_svg.rect(&writer, geometry.rect(plot.x + plot.width, plot.y, 1.0, plot.height), axis_color, false)
    i = 0usize
    while i < right_ticks.len {
        let y = plot.y + plot.height * (1.0 - right_ticks[i].fraction)
        try chart_svg.rect(&writer, geometry.rect(plot.x + plot.width, y, 5.0, 1.0), axis_color, false)
        i += 1usize
    }
    try chart_svg.append(&writer, &layers[0], bar_color)
    try chart_svg.append(&writer, &layers[1], line_color)
    try chart_svg.append_labels(&writer, labels[..15usize], axis_color, 9.0)
    try chart_svg.append_labels(&writer, labels[15usize..], axis_color, 11.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_share(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, names: []const str, title: str, path: str) -> err {
    if layers.len != 5usize || names.len != layers.len { ret chart.Invalid }
    let colors = [5]paint.Color{
        paint.rgba(0.07, 0.35, 0.76, 1.0), paint.rgba(0.94, 0.42, 0.12, 1.0),
        paint.rgba(0.22, 0.65, 0.48, 1.0), paint.rgba(0.64, 0.40, 0.76, 1.0),
        paint.rgba(0.93, 0.70, 0.15, 1.0),
    }
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    var legend: [5]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(names, chart.Coord { x: 236.0, y: 59.0 }, 11.0, 27.0, legend[..])
    if legend_error != ok { ret legend_error }
    var labels: [6]chart.Label = zero
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 160usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: colors[i] })
        labels[i] = entries[i].label
        i += 1usize
    }
    labels[5usize] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    try chart_scene.append_labels(a, &builder, labels[..5usize], font, 9.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, labels[5usize..], font, 13.0, paint.Brush { Solid: axis_color })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        try chart_svg.rect(&writer, entries[i].swatch, colors[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..5usize], axis_color, 9.0)
    try chart_svg.append_labels(&writer, labels[5usize..], axis_color, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_radar_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let first = [6]f32{ 80.0, 72.0, 62.0, 88.0, 58.0, 77.0 }
    let second = [6]f32{ 63.0, 89.0, 76.0, 68.0, 83.0, 64.0 }
    let minimum = [6]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
    let maximum = [6]f32{ 100.0, 100.0, 100.0, 100.0, 100.0, 100.0 }
    let bounds = geometry.rect(80.0, 50.0, 200.0, 160.0)
    var first_points: [7]chart.Coord = zero
    var second_points: [7]chart.Coord = zero
    var guide_segments: [18]chart.Segment = zero
    let (first_area, _, first_error) = chart.radar(first[..], minimum[..], maximum[..], bounds, 2usize, first_points[..], guide_segments[..])
    if first_error != ok { ret first_error }
    let (second_area, guides, second_error) = chart.radar(second[..], minimum[..], maximum[..], bounds, 2usize, second_points[..], guide_segments[..])
    if second_error != ok { ret second_error }
    var first_lines: [6]chart.Segment = zero
    var second_lines: [6]chart.Segment = zero
    var i = 0usize
    while i < 6usize {
        first_lines[i] = chart.Segment { from: first_points[i], to: first_points[i + 1usize] }
        second_lines[i] = chart.Segment { from: second_points[i], to: second_points[i + 1usize] }
        i += 1usize
    }
    let first_outline = chart.Layout { kind: .Line, coords: zero, segments: first_lines[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let second_outline = chart.Layout { kind: .Line, coords: zero, segments: second_lines[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let blue = paint.rgba(0.08, 0.39, 0.77, 0.44)
    let orange = paint.rgba(0.93, 0.42, 0.13, 0.40)
    let solid_blue = paint.rgba(0.08, 0.39, 0.77, 1.0)
    let solid_orange = paint.rgba(0.93, 0.42, 0.13, 1.0)
    let grid = paint.rgba(0.74, 0.79, 0.85, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var labels: [9]chart.Label = zero
    labels[0usize] = chart.Label { text: "Radar comparison", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Speed", anchor: chart.Coord { x: 180.0, y: 45.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "Power", anchor: chart.Coord { x: 258.0, y: 93.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "Quality", anchor: chart.Coord { x: 258.0, y: 173.0 }, align: .Left }
    labels[4usize] = chart.Label { text: "Reach", anchor: chart.Coord { x: 180.0, y: 221.0 }, align: .Center }
    labels[5usize] = chart.Label { text: "Growth", anchor: chart.Coord { x: 102.0, y: 173.0 }, align: .Right }
    labels[6usize] = chart.Label { text: "Value", anchor: chart.Coord { x: 102.0, y: 93.0 }, align: .Right }
    labels[7usize] = chart.Label { text: "A", anchor: chart.Coord { x: 104.0, y: 235.0 }, align: .Left }
    labels[8usize] = chart.Label { text: "B", anchor: chart.Coord { x: 244.0, y: 235.0 }, align: .Left }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 28u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append(a, &builder, &guides, paint.Brush { Solid: grid })
    try chart_scene.append(a, &builder, &first_area, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &second_area, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &first_outline, paint.Brush { Solid: solid_blue })
    try chart_scene.append(a, &builder, &second_outline, paint.Brush { Solid: solid_orange })
    try fill(&builder, geometry.rect(87.0, 229.0, 12.0, 5.0), paint.Brush { Solid: solid_blue })
    try fill(&builder, geometry.rect(227.0, 229.0, 12.0, 5.0), paint.Brush { Solid: solid_orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/radar.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &guides, grid)
    try chart_svg.append(&writer, &first_area, blue)
    try chart_svg.append(&writer, &second_area, orange)
    try chart_svg.append(&writer, &first_outline, solid_blue)
    try chart_svg.append(&writer, &second_outline, solid_orange)
    try chart_svg.rect(&writer, geometry.rect(87.0, 229.0, 12.0, 5.0), solid_blue, false)
    try chart_svg.rect(&writer, geometry.rect(227.0, 229.0, 12.0, 5.0), solid_orange, false)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_ternary_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let top = [12]f32{ 65.0, 55.0, 72.0, 44.0, 80.0, 62.0, 24.0, 18.0, 36.0, 28.0, 14.0, 33.0 }
    let left = [12]f32{ 20.0, 31.0, 12.0, 36.0, 10.0, 23.0, 59.0, 68.0, 48.0, 62.0, 72.0, 53.0 }
    let right = [12]f32{ 15.0, 14.0, 16.0, 20.0, 10.0, 15.0, 17.0, 14.0, 16.0, 10.0, 14.0, 14.0 }
    var points: [12]chart.Coord = zero
    var guides: [15]chart.Segment = zero
    let (all, grid, chart_error) = chart.ternary(top[..], left[..], right[..], geometry.rect(74.0, 48.0, 212.0, 152.0), 5usize, points[..], guides[..])
    if chart_error != ok { ret chart_error }
    var first = all
    first.coords = all.coords[..6usize]
    var second = all
    second.coords = all.coords[6usize..]
    let blue = paint.rgba(0.07, 0.35, 0.76, 1.0)
    let orange = paint.rgba(0.94, 0.42, 0.12, 1.0)
    let grid_color = paint.rgba(0.76, 0.81, 0.87, 1.0)
    let ink = paint.rgba(0.24, 0.30, 0.40, 1.0)
    let labels = [6]chart.Label{
        chart.Label { text: "Three-part mixtures", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "A", anchor: chart.Coord { x: 180.0, y: 41.0 }, align: .Center },
        chart.Label { text: "B", anchor: chart.Coord { x: 82.0, y: 216.0 }, align: .Center },
        chart.Label { text: "C", anchor: chart.Coord { x: 278.0, y: 216.0 }, align: .Center },
        chart.Label { text: "Blend 1", anchor: chart.Coord { x: 105.0, y: 234.0 }, align: .Left },
        chart.Label { text: "Blend 2", anchor: chart.Coord { x: 229.0, y: 234.0 }, align: .Left },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 40usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append(a, &builder, &grid, paint.Brush { Solid: grid_color })
    try chart_scene.append(a, &builder, &first, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &second, paint.Brush { Solid: orange })
    try fill(&builder, geometry.rect(89.0, 228.0, 10.0, 5.0), paint.Brush { Solid: blue })
    try fill(&builder, geometry.rect(213.0, 228.0, 10.0, 5.0), paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: ink })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: ink })
    let path = "docs/chart-previews/ternary.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &grid, grid_color)
    try chart_svg.append(&writer, &first, blue)
    try chart_svg.append(&writer, &second, orange)
    try chart_svg.rect(&writer, geometry.rect(89.0, 228.0, 10.0, 5.0), blue, false)
    try chart_svg.rect(&writer, geometry.rect(213.0, 228.0, 10.0, 5.0), orange, false)
    try chart_svg.append_labels(&writer, labels[..1usize], ink, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], ink, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_quiver_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    var xs: [25]f32 = zero
    var ys: [25]f32 = zero
    var us: [25]f32 = zero
    var vs: [25]f32 = zero
    var i = 0usize
    while i < 25usize {
        xs[i] = f32(i % 5usize) - 2.0
        ys[i] = 2.0 - f32(i / 5usize)
        us[i] = 0.0 - ys[i]
        vs[i] = xs[i]
        i += 1usize
    }
    var tails: [25]chart.Coord = zero
    var strokes: [75]chart.Segment = zero
    let (arrows, chart_error) = chart.quiver(xs[..], ys[..], us[..], vs[..], geometry.rect(56.0, 46.0, 248.0, 156.0), 8.0, 5.0, tails[..], strokes[..])
    if chart_error != ok { ret chart_error }
    let ink = paint.rgba(0.08, 0.39, 0.77, 1.0)
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let guides = paint.rgba(0.83, 0.87, 0.92, 1.0)
    let labels = [2]chart.Label{
        chart.Label { text: "Rotational vector field", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "u = -y, v = x", anchor: chart.Coord { x: 180.0, y: 230.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 30u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 112usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, geometry.rect(56.0, 123.5, 248.0, 1.0), paint.Brush { Solid: guides })
    try fill(&builder, geometry.rect(179.5, 46.0, 1.0, 156.0), paint.Brush { Solid: guides })
    try chart_scene.append(a, &builder, &arrows, paint.Brush { Solid: ink })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 10.0, paint.Brush { Solid: axis })
    let path = "docs/chart-previews/quiver.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, geometry.rect(56.0, 123.5, 248.0, 1.0), guides, false)
    try chart_svg.rect(&writer, geometry.rect(179.5, 46.0, 1.0, 156.0), guides, false)
    try chart_svg.append(&writer, &arrows, ink)
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 10.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_streamlines_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    var u: [85]f32 = zero
    var v: [85]f32 = zero
    var i = 0usize
    while i < u.len {
        let x = f64(i % 17usize) / 16.0f64
        u[i] = 1.0
        v[i] = f32(math.cos[f64](6.283185307179586f64 * x))
        i += 1usize
    }
    var seeds: [5]chart.Coord = zero
    i = 0usize
    while i < seeds.len {
        seeds[i] = chart.Coord { x: 0.0, y: 0.2 + f32(i) * 0.15 }
        i += 1usize
    }
    var strokes: [450]chart.Segment = zero
    let (paths, chart_error) = chart.streamlines(u[..], v[..], 17usize, 5usize, 0.0, 1.0, 0.0, 1.0, seeds[..], 0.02, 90usize, geometry.rect(35.0, 48.0, 290.0, 156.0), strokes[..])
    if chart_error != ok { ret chart_error }
    let ink = paint.rgba(0.07, 0.35, 0.76, 1.0)
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let grid = paint.rgba(0.86, 0.89, 0.93, 1.0)
    let labels = [2]chart.Label{
        chart.Label { text: "Wave-field streamlines", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "u = 1, v = cos(2 pi x)", anchor: chart.Coord { x: 180.0, y: 230.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 480usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 1usize
    while i < 4usize {
        try fill(&builder, geometry.rect(35.0, 48.0 + f32(i) * 39.0, 290.0, 1.0), paint.Brush { Solid: grid })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &paths, paint.Brush { Solid: ink })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 10.0, paint.Brush { Solid: axis })
    let path = "docs/chart-previews/streamlines.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 1usize
    while i < 4usize {
        try chart_svg.rect(&writer, geometry.rect(35.0, 48.0 + f32(i) * 39.0, 290.0, 1.0), grid, false)
        i += 1usize
    }
    try chart_svg.append(&writer, &paths, ink)
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 10.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_phase_space_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    var values: [31]f32 = zero
    var i = 0usize
    while i < values.len {
        values[i] = f32(math.sin[f64](6.283185307179586f64 * f64(i) / 24.0f64))
        i += 1usize
    }
    var points: [25]chart.Coord = zero
    var segments: [24]chart.Segment = zero
    let (marks, chart_error) = chart.phase_space(values[..], 6usize, geometry.rect(80.0, 42.0, 180.0, 180.0), points[..], segments[..])
    if chart_error != ok { ret chart_error }
    let ink = paint.rgba(0.08, 0.39, 0.77, 1.0)
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let grid = paint.rgba(0.86, 0.89, 0.93, 1.0)
    let labels = [3]chart.Label{
        chart.Label { text: "Lagged phase portrait", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "x(t)", anchor: chart.Coord { x: 170.0, y: 237.0 }, align: .Center },
        chart.Label { text: "x(t+6)", anchor: chart.Coord { x: 74.0, y: 133.0 }, align: .Right },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, geometry.rect(80.0, 131.5, 180.0, 1.0), paint.Brush { Solid: grid })
    try fill(&builder, geometry.rect(169.5, 42.0, 1.0, 180.0), paint.Brush { Solid: grid })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: axis })
    let path = "docs/chart-previews/phase_space.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, geometry.rect(80.0, 131.5, 180.0, 1.0), grid, false)
    try chart_svg.rect(&writer, geometry.rect(169.5, 42.0, 1.0, 180.0), grid, false)
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_recurrence_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    var values: [49]f32 = zero
    var i = 0usize
    while i < values.len {
        values[i] = f32(math.sin[f64](6.283185307179586f64 * f64(i) / 24.0f64))
        i += 1usize
    }
    var cells: [1849]chart.Cell = zero
    let (marks, chart_error) = chart.recurrence(values[..], 6usize, 0.55, geometry.rect(87.0, 37.0, 186.0, 186.0), cells[..])
    if chart_error != ok { ret chart_error }
    let low = paint.rgba(0.93, 0.95, 0.98, 1.0)
    let high = paint.rgba(0.08, 0.34, 0.74, 1.0)
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let labels = [2]chart.Label{
        chart.Label { text: "Lagged recurrence", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "lag 6, radius 0.55", anchor: chart.Coord { x: 180.0, y: 238.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 1872usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_matrix(&builder, &marks, low, low, high)
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: axis })
    let path = "docs/chart-previews/recurrence.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_matrix(&writer, &marks, low, low, high)
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_earned_value_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/earned_value.png"
    let plot = geometry.rect(52.0, 47.0, 256.0, 136.0)
    let x = [7]f32{ 0.0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0 }
    let planned = [7]f32{ 0.0, 8.0, 17.0, 28.0, 39.0, 50.0, 60.0 }
    let earned = [5]f32{ 0.0, 6.0, 14.0, 20.0, 27.0 }
    let actual = [5]f32{ 0.0, 7.0, 17.0, 25.0, 34.0 }
    var planned_segments: [6]chart.Segment = zero
    var earned_segments: [4]chart.Segment = zero
    var actual_segments: [4]chart.Segment = zero
    let (pv, ev, ac, layout_error) = chart.earned_value(x[..], planned[..], earned[..], actual[..], plot, planned_segments[..], earned_segments[..], actual_segments[..])
    if layout_error != ok { ret layout_error }
    let colors = [3]paint.Color{ paint.rgba(0.08, 0.40, 0.76, 1.0), paint.rgba(0.15, 0.60, 0.46, 1.0), paint.rgba(0.86, 0.40, 0.17, 1.0) }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let grid = paint.rgba(0.87, 0.90, 0.94, 1.0)
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [4]chart.Tick = zero
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    let (_, x_error) = chart.ticks(linear, pv.x_min, pv.x_max, x_ticks[..])
    if x_error != ok { ret x_error }
    let (_, y_error) = chart.ticks(linear, pv.y_min, pv.y_max, y_ticks[..])
    if y_error != ok { ret y_error }
    let x_names = [4]str{ "0", "1/3", "2/3", "1" }
    let y_names = [4]str{ "0", "20", "40", "60" }
    let legend_names = [3]str{ "PV plan", "EV earned", "AC actual" }
    var labels: [12]chart.Label = zero
    var swatches: [3]geometry.Rect = zero
    var i = 0usize
    while i < 4usize {
        labels[i] = chart.Label { text: x_names[i], anchor: chart.Coord { x: plot.x + plot.width * x_ticks[i].fraction, y: 199.0 }, align: .Center }
        labels[4usize + i] = chart.Label { text: y_names[i], anchor: chart.Coord { x: 43.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[8usize] = chart.Label { text: "Earned value (PV / EV / AC)", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    i = 0usize
    while i < 3usize {
        swatches[i] = geometry.rect(47.0 + f32(i) * 100.0, 217.0, 10.0, 10.0)
        labels[9usize + i] = chart.Label { text: legend_names[i], anchor: chart.Coord { x: swatches[i].x + 16.0, y: 226.0 }, align: .Left }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &pv, paint.Brush { Solid: colors[0usize] })
    try chart_scene.append(a, &builder, &ev, paint.Brush { Solid: colors[1usize] })
    try chart_scene.append(a, &builder, &ac, paint.Brush { Solid: colors[2usize] })
    i = 0usize
    while i < 3usize {
        try fill(&builder, swatches[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..8usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[8usize..9usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[9usize..], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &pv, colors[0usize])
    try chart_svg.append(&writer, &ev, colors[1usize])
    try chart_svg.append(&writer, &ac, colors[2usize])
    i = 0usize
    while i < 3usize {
        try chart_svg.rect(&writer, swatches[i], colors[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..8usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[8usize..9usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[9usize..], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_burn_previews(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let plot = geometry.rect(56.0, 43.0, 252.0, 150.0)
    let x = [7]f32{ 0.0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0 }
    let remaining = [7]f32{ 30.0, 27.0, 25.0, 22.0, 17.0, 11.0, 5.0 }
    let completed = [7]f32{ 0.0, 4.0, 8.0, 11.0, 16.0, 21.0, 26.0 }
    let scope = [7]f32{ 30.0, 30.0, 30.0, 36.0, 36.0, 36.0, 36.0 }
    var ideal: [7]f32 = zero
    var actual_segments: [6]chart.Segment = zero
    var reference_segments: [6]chart.Segment = zero
    let (down, ideal_line, down_error) = chart.burndown(x[..], remaining[..], plot, ideal[..], actual_segments[..], reference_segments[..])
    if down_error != ok { ret down_error }
    try render_diagnostic_preview(a, q, output_target, canvas, renderer, &down, &ideal_line, "Burndown: actual vs ideal", "Sprint fraction", "Work left", "docs/chart-previews/burndown.png")
    let (up, scope_line, up_error) = chart.burnup(x[..], completed[..], scope[..], plot, actual_segments[..], reference_segments[..])
    if up_error != ok { ret up_error }
    ret render_diagnostic_preview(a, q, output_target, canvas, renderer, &up, &scope_line, "Burnup: done vs scope", "Sprint fraction", "Work done", "docs/chart-previews/burnup.png")
}

fn render_drawdown_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let x = [10]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0 }
    let prices = [10]f32{ 100.0, 120.0, 98.0, 110.0, 90.0, 140.0, 125.0, 150.0, 130.0, 160.0 }
    var losses: [10]f32 = zero
    var points: [20]chart.Coord = zero
    let plot = geometry.rect(49.0, 43.0, 272.0, 160.0)
    let (marks, chart_error) = chart.drawdown(x[..], prices[..], plot, losses[..], points[..])
    if chart_error != ok { ret chart_error }
    var segments: [9]chart.Segment = zero
    var unused_coords: [1]chart.Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let line = chart.spec(.Line, plot, x[..], losses[..])
    let (outline, line_error) = chart.layout(&line, unused_coords[..0usize], segments[..], unused_bars[..0usize])
    if line_error != ok { ret line_error }
    let fill_color = paint.rgba(0.88, 0.26, 0.31, 0.34)
    let line_color = paint.rgba(0.74, 0.16, 0.23, 1.0)
    let grid = paint.rgba(0.85, 0.88, 0.92, 1.0)
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let labels = [4]chart.Label{
        chart.Label { text: "Drawdown from running peak", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "0%", anchor: chart.Coord { x: 42.0, y: 46.0 }, align: .Right },
        chart.Label { text: "-25%", anchor: chart.Coord { x: 42.0, y: 201.0 }, align: .Right },
        chart.Label { text: "Observation", anchor: chart.Coord { x: 180.0, y: 234.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, plot, paint.Brush { Solid: paint.rgba(0.98, 0.97, 0.97, 1.0) })
    try fill(&builder, geometry.rect(plot.x, plot.y + plot.height - 1.0, plot.width, 1.0), paint.Brush { Solid: grid })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: fill_color })
    try chart_scene.append(a, &builder, &outline, paint.Brush { Solid: line_color })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: axis })
    let path = "docs/chart-previews/drawdown.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, paint.rgba(0.98, 0.97, 0.97, 1.0), false)
    try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + plot.height - 1.0, plot.width, 1.0), grid, false)
    try chart_svg.append(&writer, &marks, fill_color)
    try chart_svg.append(&writer, &outline, line_color)
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_cohort_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let counts = [10]f64{ 120.0f64, 94.0f64, 76.0f64, 62.0f64, 100.0f64, 73.0f64, 59.0f64, 90.0f64, 70.0f64, 110.0f64 }
    var cells: [10]chart.Cell = zero
    let (marks, chart_error) = chart.cohort_retention(counts[..], 4usize, geometry.rect(84.0, 43.0, 224.0, 168.0), 3.0, cells[..])
    if chart_error != ok { ret chart_error }
    let low = paint.rgba(0.93, 0.96, 0.98, 1.0)
    let mid = paint.rgba(0.42, 0.72, 0.79, 1.0)
    let high = paint.rgba(0.05, 0.39, 0.58, 1.0)
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let labels = [10]chart.Label{
        chart.Label { text: "Cohort retention", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "Jan", anchor: chart.Coord { x: 75.0, y: 67.0 }, align: .Right },
        chart.Label { text: "Feb", anchor: chart.Coord { x: 75.0, y: 109.0 }, align: .Right },
        chart.Label { text: "Mar", anchor: chart.Coord { x: 75.0, y: 151.0 }, align: .Right },
        chart.Label { text: "Apr", anchor: chart.Coord { x: 75.0, y: 193.0 }, align: .Right },
        chart.Label { text: "0", anchor: chart.Coord { x: 112.0, y: 227.0 }, align: .Center },
        chart.Label { text: "1", anchor: chart.Coord { x: 168.0, y: 227.0 }, align: .Center },
        chart.Label { text: "2", anchor: chart.Coord { x: 224.0, y: 227.0 }, align: .Center },
        chart.Label { text: "3", anchor: chart.Coord { x: 280.0, y: 227.0 }, align: .Center },
        chart.Label { text: "Months since start", anchor: chart.Coord { x: 180.0, y: 239.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_matrix(&builder, &marks, low, mid, high)
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: axis })
    let path = "docs/chart-previews/cohort_retention.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_matrix(&writer, &marks, low, mid, high)
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_contour_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    var values: [289]f64 = zero
    var row = 0usize
    while row < 17usize {
        var col = 0usize
        while col < 17usize {
            let dx = f64(col) - 8.0f64
            let dy = f64(row) - 8.0f64
            values[row * 17usize + col] = math.sqrt[f64](dx * dx + dy * dy)
            col += 1usize
        }
        row += 1usize
    }
    let levels = [3]f64{ 3.0f64, 5.0f64, 7.0f64 }
    var segments: [1536]chart.Segment = zero
    var storage: [3]chart.Layout = zero
    let plot = geometry.rect(92.0, 42.0, 176.0, 176.0)
    let (layers, contour_error) = chart.contour(values[..], 17usize, 17usize, levels[..], plot, segments[..], storage[..])
    if contour_error != ok { ret contour_error }
    let colors = [3]paint.Color{ paint.rgba(0.08, 0.37, 0.72, 1.0), paint.rgba(0.03, 0.57, 0.65, 1.0), paint.rgba(0.78, 0.24, 0.28, 1.0) }
    let axis = paint.rgba(0.30, 0.36, 0.45, 1.0)
    let grid = paint.rgba(0.87, 0.90, 0.94, 1.0)
    let labels = [2]chart.Label{
        chart.Label { text: "Interpolated contour lines", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "Levels 3, 5, 7", anchor: chart.Coord { x: 180.0, y: 238.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try fill(&builder, plot, paint.Brush { Solid: paint.rgba(0.97, 0.98, 0.99, 1.0) })
    try fill(&builder, geometry.rect(179.5, plot.y, 1.0, plot.height), paint.Brush { Solid: grid })
    try fill(&builder, geometry.rect(plot.x, 129.5, plot.width, 1.0), paint.Brush { Solid: grid })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 9.0, paint.Brush { Solid: axis })
    let path = "docs/chart-previews/contour.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, paint.rgba(0.97, 0.98, 0.99, 1.0), false)
    try chart_svg.rect(&writer, geometry.rect(179.5, plot.y, 1.0, plot.height), grid, false)
    try chart_svg.rect(&writer, geometry.rect(plot.x, 129.5, plot.width, 1.0), grid, false)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], axis, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    try fs.write_file(a, svg_path, io.memory_bytes(&svg_state))

    var fill_points: [16384]chart.Coord = zero
    var fill_storage: [2048]chart.Layout = zero
    var band_ids: [2048]usize = zero
    let (filled, fill_error) = chart.filled_contour(values[..], 17usize, 17usize, levels[..], plot, fill_points[..], fill_storage[..], band_ids[..])
    if fill_error != ok { ret fill_error }
    let fills = [4]paint.Color{
        paint.rgba(0.94, 0.97, 0.99, 1.0), paint.rgba(0.72, 0.88, 0.94, 1.0),
        paint.rgba(0.37, 0.67, 0.82, 1.0), paint.rgba(0.12, 0.39, 0.65, 1.0),
    }
    let outline = paint.rgba(0.18, 0.32, 0.45, 1.0)
    let fill_labels = [2]chart.Label{
        chart.Label { text: "Filled contour bands", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "Levels 3, 5, 7", anchor: chart.Coord { x: 180.0, y: 238.0 }, align: .Center },
    }
    let (fill_made, fill_builder_error) = scene.builder(a, 2200usize)
    if fill_builder_error != ok { ret fill_builder_error }
    var fill_builder = fill_made
    try fill(&fill_builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_filled_contour(a, &fill_builder, filled, band_ids[..filled.len], fills[..])
    i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &fill_builder, &layers[i], paint.Brush { Solid: outline })
        i += 1usize
    }
    try chart_scene.append_labels(a, &fill_builder, fill_labels[..1usize], font, 13.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &fill_builder, fill_labels[1usize..], font, 9.0, paint.Brush { Solid: axis })
    let fill_path = "docs/chart-previews/filled_contour.png"
    try render_builder(a, q, output_target, canvas, renderer, &fill_builder, fill_path)
    let (fill_svg_held, fill_svg_error) = svg_start(a, fill_path)
    if fill_svg_error != ok { ret fill_svg_error }
    var fill_svg_state = fill_svg_held
    var fill_writer = io.writer(mem.cast[*void](&fill_svg_state), io.memory_write)
    try chart_svg.append_filled_contour(&fill_writer, filled, band_ids[..filled.len], fills[..])
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&fill_writer, &layers[i], outline)
        i += 1usize
    }
    try chart_svg.append_labels(&fill_writer, fill_labels[..1usize], axis, 13.0)
    try chart_svg.append_labels(&fill_writer, fill_labels[1usize..], axis, 9.0)
    try chart_svg.finish(&fill_writer)
    let (fill_svg_path, fill_path_error) = vector_path(a, fill_path)
    if fill_path_error != ok { ret fill_path_error }
    ret fs.write_file(a, fill_svg_path, io.memory_bytes(&fill_svg_state))
}

fn render_treemap(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, rects: []geometry.Rect, names: []const str, path: str) -> err {
    if layers.len != 9usize || rects.len != layers.len || names.len != layers.len { ret chart.Invalid }
    let colors = [6]paint.Color{
        paint.rgba(0.08, 0.33, 0.70, 1.0), paint.rgba(0.27, 0.27, 0.65, 1.0), paint.rgba(0.08, 0.49, 0.63, 1.0),
        paint.rgba(0.10, 0.47, 0.33, 1.0), paint.rgba(0.66, 0.33, 0.08, 1.0), paint.rgba(0.69, 0.18, 0.27, 1.0),
    }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var labels: [9]chart.Label = zero
    var i = 3usize
    while i < layers.len {
        let r = rects[i]
        labels[i - 3usize] = chart.Label { text: names[i], anchor: chart.Coord { x: r.x + r.width * 0.5, y: r.y + r.height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[6usize] = chart.Label { text: names[1usize], anchor: chart.Coord { x: rects[1usize].x + 7.0, y: rects[1usize].y + 14.0 }, align: .Left }
    labels[7usize] = chart.Label { text: names[2usize], anchor: chart.Coord { x: rects[2usize].x + 7.0, y: rects[2usize].y + 14.0 }, align: .Left }
    labels[8usize] = chart.Label { text: "Hierarchical treemap", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    let border = chart.Layout { kind: .Rug, coords: zero, segments: zero, bars: rects, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 160usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 3usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i - 3usize] })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &border, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[..8usize], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 3usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i - 3usize])
        i += 1usize
    }
    try chart_svg.append(&writer, &border, white)
    try chart_svg.append_labels(&writer, labels[..8usize], white, 9.0)
    try chart_svg.append_labels(&writer, labels[8usize..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_icicle(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, rects: []geometry.Rect, names: []const str, path: str) -> err {
    if layers.len != 9usize || rects.len != layers.len || names.len != layers.len { ret chart.Invalid }
    let colors = [9]paint.Color{
        paint.rgba(0.20, 0.25, 0.35, 1.0), paint.rgba(0.09, 0.35, 0.67, 1.0), paint.rgba(0.11, 0.48, 0.43, 1.0),
        paint.rgba(0.07, 0.44, 0.75, 1.0), paint.rgba(0.31, 0.37, 0.70, 1.0), paint.rgba(0.08, 0.55, 0.67, 1.0),
        paint.rgba(0.10, 0.57, 0.39, 1.0), paint.rgba(0.40, 0.57, 0.17, 1.0), paint.rgba(0.68, 0.39, 0.12, 1.0),
    }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var labels: [10]chart.Label = zero
    var i = 0usize
    while i < layers.len {
        let r = rects[i]
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: r.x + r.width * 0.5, y: r.y + r.height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[9usize] = chart.Label { text: "Hierarchical icicle", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    let border = chart.Layout { kind: .Rug, coords: zero, segments: zero, bars: rects, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 160usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &border, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[..9usize], font, 10.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[9usize..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    try chart_svg.append(&writer, &border, white)
    try chart_svg.append_labels(&writer, labels[..9usize], white, 10.0)
    try chart_svg.append_labels(&writer, labels[9usize..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_radial_hierarchy(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, names: []const str, first_color: usize, center_label: bool, title: str, path: str) -> err {
    if layers.len != 8usize || names.len + first_color != layers.len { ret chart.Invalid }
    let colors = [8]paint.Color{
        paint.rgba(0.35, 0.41, 0.51, 1.0), paint.rgba(0.11, 0.35, 0.69, 1.0), paint.rgba(0.16, 0.53, 0.38, 1.0),
        paint.rgba(0.08, 0.39, 0.79, 1.0), paint.rgba(0.34, 0.35, 0.74, 1.0), paint.rgba(0.11, 0.56, 0.70, 1.0),
        paint.rgba(0.10, 0.62, 0.44, 1.0), paint.rgba(0.73, 0.40, 0.13, 1.0),
    }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var legend: [7]chart.LegendItem = zero
    var legend_step = 29.0f32
    if names.len > 5usize { legend_step = 24.0 }
    let (entries, legend_error) = chart.legend_items(names, chart.Coord { x: 232.0, y: 58.0 }, 10.0, legend_step, legend[..])
    if legend_error != ok { ret legend_error }
    var labels: [9]chart.Label = zero
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: colors[i + first_color] })
        labels[i] = entries[i].label
        i += 1usize
    }
    var title_index = entries.len
    if center_label {
        labels[title_index] = chart.Label { text: "All", anchor: chart.Coord { x: 120.0, y: 131.0 }, align: .Center }
        title_index += 1usize
    }
    labels[title_index] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    try chart_scene.append_labels(a, &builder, labels[..title_index], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[title_index..title_index + 1usize], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try chart_svg.rect(&writer, entries[i].swatch, colors[i + first_color], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..title_index], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[title_index..title_index + 1usize], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_circle_sets(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, names: []const str, regions: []const str, anchors: []const chart.Coord, title: str, path: str) -> err {
    if (layers.len != 2usize && layers.len != 3usize) || names.len != layers.len || regions.len != anchors.len || regions.len > 7usize { ret chart.Invalid }
    let colors = [3]paint.Color{ paint.rgba(0.10, 0.43, 0.78, 0.50), paint.rgba(0.91, 0.39, 0.25, 0.50), paint.rgba(0.16, 0.64, 0.45, 0.50) }
    let swatches = [3]paint.Color{ paint.rgba(0.10, 0.43, 0.78, 1.0), paint.rgba(0.91, 0.39, 0.25, 1.0), paint.rgba(0.16, 0.64, 0.45, 1.0) }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var legend: [3]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(names, chart.Coord { x: 237.0, y: 64.0 }, 11.0, 36.0, legend[..])
    if legend_error != ok { ret legend_error }
    var labels: [11]chart.Label = zero
    var i = 0usize
    while i < entries.len {
        labels[i] = entries[i].label
        i += 1usize
    }
    var j = 0usize
    while j < regions.len {
        labels[i + j] = chart.Label { text: regions[j], anchor: chart.Coord { x: anchors[j].x, y: anchors[j].y + 3.0 }, align: .Center }
        j += 1usize
    }
    let title_index = i + j
    labels[title_index] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: swatches[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..title_index], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[title_index..title_index + 1usize], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        try chart_svg.rect(&writer, entries[i].swatch, swatches[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..title_index], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[title_index..title_index + 1usize], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_word_cloud(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, font: shape.Font, marks: []chart.CloudWord, path: str) -> err {
    let colors = [5]paint.Color{
        paint.rgba(0.08, 0.39, 0.76, 1.0), paint.rgba(0.87, 0.36, 0.17, 1.0),
        paint.rgba(0.10, 0.56, 0.42, 1.0), paint.rgba(0.49, 0.36, 0.70, 1.0),
        paint.rgba(0.72, 0.47, 0.12, 1.0),
    }
    let title = [1]chart.Label{ chart.Label { text: "Weighted word cloud", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center } }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var i = 0usize
    while i < marks.len {
        let label = [1]chart.Label{ marks[i].label }
        try chart_scene.append_labels(a, &builder, label[..], font, marks[i].size, paint.Brush { Solid: colors[i % colors.len] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, title[..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < marks.len {
        let label = [1]chart.Label{ marks[i].label }
        try chart_svg.append_labels(&writer, label[..], colors[i % colors.len], marks[i].size)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, title[..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_chord(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, names: []const str, path: str) -> err {
    if layers.len != 14usize || names.len != 4usize { ret chart.Invalid }
    let ribbons = [4]paint.Color{
        paint.rgba(0.09, 0.36, 0.74, 0.50), paint.rgba(0.87, 0.39, 0.15, 0.50),
        paint.rgba(0.14, 0.58, 0.43, 0.50), paint.rgba(0.51, 0.36, 0.73, 0.50),
    }
    let rings = [4]paint.Color{
        paint.rgba(0.09, 0.36, 0.74, 1.0), paint.rgba(0.87, 0.39, 0.15, 1.0),
        paint.rgba(0.14, 0.58, 0.43, 1.0), paint.rgba(0.51, 0.36, 0.73, 1.0),
    }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    var legend: [4]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(names, chart.Coord { x: 236.0, y: 62.0 }, 11.0, 35.0, legend[..])
    if legend_error != ok { ret legend_error }
    var labels: [5]chart.Label = zero
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    var layer = 0usize
    var i = 0usize
    while i < 4usize {
        var j = i
        while j < 4usize {
            try chart_scene.append(a, &builder, &layers[layer], paint.Brush { Solid: ribbons[i] })
            layer += 1usize
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        try chart_scene.append(a, &builder, &layers[layer + i], paint.Brush { Solid: rings[i] })
        try fill(&builder, entries[i].swatch, paint.Brush { Solid: rings[i] })
        labels[i] = entries[i].label
        i += 1usize
    }
    labels[4usize] = chart.Label { text: "Connections", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    try chart_scene.append_labels(a, &builder, labels[..4usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    layer = 0usize
    i = 0usize
    while i < 4usize {
        var j = i
        while j < 4usize {
            try chart_svg.append(&writer, &layers[layer], ribbons[i])
            layer += 1usize
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        try chart_svg.append(&writer, &layers[layer + i], rings[i])
        try chart_svg.rect(&writer, entries[i].swatch, rings[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..4usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[4usize..], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_sankey(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, rects: []geometry.Rect, names: []const str, colors: []const paint.Color, title: str, path: str) -> err {
    if layers.len <= rects.len || rects.len > 8usize || names.len != rects.len || colors.len != layers.len { ret chart.Invalid }
    let link_count = layers.len - rects.len
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [9]chart.Label = zero
    var i = 0usize
    while i < rects.len {
        let r = rects[i]
        labels[i] = chart.Label { text: names[i], anchor: chart.Coord { x: r.x + r.width * 0.5, y: r.y + r.height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[rects.len] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < link_count {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    i = 0usize
    while i < rects.len {
        try chart_scene.append(a, &builder, &layers[link_count + i], paint.Brush { Solid: colors[link_count + i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..rects.len], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[rects.len..rects.len + 1usize], font, 13.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < link_count {
        try chart_svg.append(&writer, &layers[i], colors[i])
        i += 1usize
    }
    i = 0usize
    while i < rects.len {
        try chart_svg.append(&writer, &layers[link_count + i], colors[link_count + i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..rects.len], white, 9.0)
    try chart_svg.append_labels(&writer, labels[rects.len..rects.len + 1usize], dark, 13.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
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

fn render_labeled_chart(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, variant: u8) -> err {
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let bounds = geometry.rect(44.0, 40.0, 286.0, 150.0)
    let x = [4]f32{ 0.0, 1.0, 2.0, 3.0 }
    let y = [4]f32{ 0.0, 2.0, 1.0, 3.0 }
    let log_x = [4]f32{ 1.0, 10.0, 100.0, 1000.0 }
    let log_y = [4]f32{ 1.0, 5.0, 50.0, 1000.0 }
    let signed_y = [4]f32{ -99.0, -9.0, 9.0, 99.0 }
    var points: [4]chart.Coord = zero
    var segments: [3]chart.Segment = zero
    var bars: [4]geometry.Rect = zero
    var plot = chart.spec(.Line, bounds, x[..], y[..])
    var path = "docs/chart-previews/labeled_line.png"
    var title = "Response over time"
    var axis_name = "Time"
    if variant == 1u8 {
        plot = chart.spec(.Scatter, bounds, log_x[..], log_y[..])
        plot.x_scale.kind = .Log10
        plot.y_scale.kind = .Log10
        path = "docs/chart-previews/labeled_log_scatter.png"
        title = "Logarithmic response"
        axis_name = "Dose"
    } else if variant == 2u8 {
        plot = chart.spec(.Line, bounds, x[..], signed_y[..])
        plot.y_scale.kind = .Symlog
        path = "docs/chart-previews/labeled_symlog_line.png"
        title = "Symmetric-log response"
        axis_name = "Index"
    }
    let (marks, marks_error) = chart.layout(&plot, points[..], segments[..], bars[..])
    if marks_error != ok { ret marks_error }
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [5]chart.Tick = zero
    let (x_breaks, x_error) = chart.nice_ticks(plot.x_scale, marks.x_min, marks.x_max, 4usize, x_ticks[..])
    if x_error != ok { ret x_error }
    var wanted_y = 4usize
    if variant == 2u8 { wanted_y = 5usize }
    let (y_breaks, y_error) = chart.nice_ticks(plot.y_scale, marks.y_min, marks.y_max, wanted_y, y_ticks[..])
    if y_error != ok { ret y_error }
    var x_text: [4]str = zero
    var y_text: [5]str = zero
    var x_storage: [128]u8 = zero
    var y_storage: [128]u8 = zero
    let (x_words, x_text_error) = chart.format_ticks(x_breaks, x_text[..], x_storage[..])
    if x_text_error != ok { ret x_text_error }
    let (y_words, y_text_error) = chart.format_ticks(y_breaks, y_text[..], y_storage[..])
    if y_text_error != ok { ret y_text_error }
    var labels: [11]chart.Label = zero
    let tick_count = x_breaks.len + y_breaks.len
    let (_, labels_error) = chart.guide_labels(bounds, x_breaks, x_words, y_breaks, y_words, 10.0, labels[..tick_count])
    if labels_error != ok { ret labels_error }
    labels[tick_count] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[tick_count + 1usize] = chart.Label { text: axis_name, anchor: chart.Coord { x: 187.0, y: 232.0 }, align: .Center }
    let grid_color = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let axis_color = paint.rgba(0.32, 0.38, 0.48, 1.0)
    let ink_color = paint.rgba(0.07, 0.35, 0.76, 1.0)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, bounds, x_breaks, y_breaks, paint.Brush { Solid: grid_color }, paint.Brush { Solid: axis_color })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink_color })
    try chart_scene.append_labels(a, &builder, labels[..tick_count], font, 10.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, labels[tick_count..tick_count + 1usize], font, 14.0, paint.Brush { Solid: axis_color })
    try chart_scene.append_labels(a, &builder, labels[tick_count + 1usize..tick_count + 2usize], font, 11.0, paint.Brush { Solid: axis_color })
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, bounds, x_breaks, y_breaks, grid_color, axis_color)
    try chart_svg.append(&writer, &marks, ink_color)
    try chart_svg.append_labels(&writer, labels[..tick_count], axis_color, 10.0)
    try chart_svg.append_labels(&writer, labels[tick_count..tick_count + 1usize], axis_color, 14.0)
    try chart_svg.append_labels(&writer, labels[tick_count + 1usize..tick_count + 2usize], axis_color, 11.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    try fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
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
    let kinds = [7]chart.Kind{ .Scatter, .Line, .PointLine, .Bar, .Step, .Area, .Lollipop }
    let paths = [7]str{ "docs/chart-previews/scatter.png", "docs/chart-previews/line.png", "docs/chart-previews/point_line.png", "docs/chart-previews/bar.png", "docs/chart-previews/step.png", "docs/chart-previews/area.png", "docs/chart-previews/lollipop.png" }
    var i = 0usize
    while i < kinds.len {
        var spec = chart.spec(kinds[i], bounds, x[..], y[..])
        let (marks, layout_error) = chart.layout(&spec, points[..], segments[..], bars[..])
        if layout_error != ok { ret layout_error }
        try render_chart(a, queue, output_target, canvas, &renderer, &marks, paths[i])
        i += 1usize
    }
    let bubble_sizes = [8]f32{ 4.0, 9.0, 16.0, 25.0, 36.0, 49.0, 64.0, 100.0 }
    var bubble_spec = chart.spec(.Bubble, bounds, x[..], y[..])
    let (bubble_marks, bubble_error) = chart.bubble(&bubble_spec, bubble_sizes[..], 18.0, points[..], bars[..])
    if bubble_error != ok { ret bubble_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &bubble_marks, "docs/chart-previews/bubble.png")
    var fit_segments: [1]chart.Segment = zero
    let (fit, fit_error) = chart.regression_line(x[..], y[..], bounds, fit_segments[..])
    if fit_error != ok { ret fit_error }
    let fit_x_limits = [2]f32{ fit.x_min, fit.x_max }
    let fit_y_limits = [2]f32{ fit.y_min, fit.y_max }
    var overlay_spec = chart.spec(.Scatter, bounds, x[..], y[..])
    let (fit_dots, fit_dots_error) = chart.layout_with_limits(&overlay_spec, points[..], segments[..0usize], bars[..0usize], fit_x_limits[..], fit_y_limits[..])
    if fit_dots_error != ok { ret fit_dots_error }
    try render_scatter_overlay(a, queue, output_target, canvas, &renderer, &fit_dots, &fit, zero, "docs/chart-previews/regression_fit.png")
    let diagnostic_x = [8]f64{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 9.0 }
    let diagnostic_y = [8]f64{ 1.2, 2.1, 2.8, 4.2, 4.7, 6.0, 7.2, 14.1 }
    var diagnostics: [8]stat.RegressionDiagnostic = zero
    try stat.regression_diagnostics(diagnostic_x[..], diagnostic_y[..], diagnostics[..])
    var fitted_values: [8]f32 = zero
    var residual_values: [8]f32 = zero
    var leverage_values: [8]f32 = zero
    var standardized_values: [8]f32 = zero
    var indices: [8]f32 = zero
    var cook_values: [8]f32 = zero
    i = 0usize
    while i < diagnostics.len {
        fitted_values[i] = f32(diagnostics[i].fitted)
        residual_values[i] = f32(diagnostics[i].residual)
        leverage_values[i] = f32(diagnostics[i].leverage)
        standardized_values[i] = f32(diagnostics[i].standardized)
        indices[i] = f32(i + 1usize)
        cook_values[i] = f32(diagnostics[i].cook)
        i += 1usize
    }
    var residual_spec = chart.spec(.Scatter, bounds, fitted_values[..], residual_values[..])
    let (residual_marks, residual_error) = chart.layout(&residual_spec, points[..], segments[..], bars[..])
    if residual_error != ok { ret residual_error }
    let zero_x = [2]f32{ residual_marks.x_min, residual_marks.x_max }
    let zero_y = [2]f32{ 0.0, 0.0 }
    var zero_spec = chart.spec(.Line, bounds, zero_x[..], zero_y[..])
    var zero_segments: [1]chart.Segment = zero
    let residual_x_limits = [2]f32{ residual_marks.x_min, residual_marks.x_max }
    var residual_y_limits = [2]f32{ residual_marks.y_min, residual_marks.y_max }
    if residual_y_limits[0usize] > 0.0 { residual_y_limits[0usize] = 0.0 }
    if residual_y_limits[1usize] < 0.0 { residual_y_limits[1usize] = 0.0 }
    let (zero_line, zero_error) = chart.layout_with_limits(&zero_spec, points[..0usize], zero_segments[..], bars[..0usize], residual_x_limits[..], residual_y_limits[..])
    if zero_error != ok { ret zero_error }
    let (residual_dots, residual_dots_error) = chart.layout_with_limits(&residual_spec, points[..], segments[..0usize], bars[..0usize], residual_x_limits[..], residual_y_limits[..])
    if residual_dots_error != ok { ret residual_dots_error }
    try render_scatter_overlay(a, queue, output_target, canvas, &renderer, &residual_dots, &zero_line, zero, "docs/chart-previews/residual_fitted.png")
    var leverage_spec = chart.spec(.Scatter, bounds, leverage_values[..], standardized_values[..])
    let (leverage_marks, leverage_error) = chart.layout(&leverage_spec, points[..], segments[..], bars[..])
    if leverage_error != ok { ret leverage_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &leverage_marks, "docs/chart-previews/leverage_residual.png")
    var cook_spec = chart.spec(.Lollipop, bounds, indices[..], cook_values[..])
    let (cook_marks, cook_error) = chart.layout(&cook_spec, points[..], segments[..], bars[..])
    if cook_error != ok { ret cook_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &cook_marks, "docs/chart-previews/cooks_distance.png")
    var ellipse_segments: [64]chart.Segment = zero
    let (ellipse, ellipse_error) = chart.covariance_ellipse(x[..], y[..], bounds, 2.4477, ellipse_segments[..])
    if ellipse_error != ok { ret ellipse_error }
    let ellipse_x_limits = [2]f32{ ellipse.x_min, ellipse.x_max }
    let ellipse_y_limits = [2]f32{ ellipse.y_min, ellipse.y_max }
    let (ellipse_dots, ellipse_dots_error) = chart.layout_with_limits(&overlay_spec, points[..], segments[..0usize], bars[..0usize], ellipse_x_limits[..], ellipse_y_limits[..])
    if ellipse_dots_error != ok { ret ellipse_dots_error }
    try render_scatter_overlay(a, queue, output_target, canvas, &renderer, &ellipse_dots, &ellipse, zero, "docs/chart-previews/data_ellipse.png")
    var interval_outline: [64]chart.Coord = zero
    var interval_fit: [1]chart.Segment = zero
    let (confidence, mean_line, confidence_error) = chart.regression_interval(x[..], y[..], bounds, 2.446912, false, interval_outline[..], interval_fit[..])
    if confidence_error != ok { ret confidence_error }
    let confidence_y_limits = [2]f32{ confidence.y_min, confidence.y_max }
    let (confidence_dots, confidence_dots_error) = chart.layout_with_limits(&overlay_spec, points[..], segments[..0usize], bars[..0usize], fit_x_limits[..], confidence_y_limits[..])
    if confidence_dots_error != ok { ret confidence_dots_error }
    let confidence_underlay = [1]chart.Layout{ confidence }
    try render_scatter_overlay(a, queue, output_target, canvas, &renderer, &confidence_dots, &mean_line, confidence_underlay[..], "docs/chart-previews/confidence_band.png")
    let (prediction, prediction_line, prediction_error) = chart.regression_interval(x[..], y[..], bounds, 2.446912, true, interval_outline[..], interval_fit[..])
    if prediction_error != ok { ret prediction_error }
    let prediction_y_limits = [2]f32{ prediction.y_min, prediction.y_max }
    let (prediction_dots, prediction_dots_error) = chart.layout_with_limits(&overlay_spec, points[..], segments[..0usize], bars[..0usize], fit_x_limits[..], prediction_y_limits[..])
    if prediction_dots_error != ok { ret prediction_dots_error }
    let prediction_underlay = [1]chart.Layout{ prediction }
    try render_scatter_overlay(a, queue, output_target, canvas, &renderer, &prediction_dots, &prediction_line, prediction_underlay[..], "docs/chart-previews/prediction_band.png")
    let grouped_values = [8]f32{ 3.0, 2.0, 5.0, 4.0, 2.0, 6.0, 4.0, 3.0 }
    let category_names = [4]str{ "North", "South", "East", "West" }
    let series_names = [2]str{ "Alpha", "Beta" }
    let bar_bounds = geometry.rect(48.0, 42.0, 228.0, 140.0)
    var series_bars: [8]geometry.Rect = zero
    var series_layers: [2]chart.Layout = zero
    let (grouped, grouped_error) = chart.grouped_bars(grouped_values[..], 4usize, 2usize, bar_bounds, series_bars[..], series_layers[..])
    if grouped_error != ok { ret grouped_error }
    try render_bar_layers(a, queue, output_target, canvas, &renderer, grouped, category_names[..], series_names[..], "Grouped comparison", "docs/chart-previews/grouped_bar.png")
    let signed_values = [8]f32{ 3.0, 2.0, 5.0, -2.0, 2.0, 6.0, 4.0, -1.0 }
    let (stacked, stacked_error) = chart.stacked_bars(signed_values[..], 4usize, 2usize, bar_bounds, false, series_bars[..], series_layers[..])
    if stacked_error != ok { ret stacked_error }
    try render_bar_layers(a, queue, output_target, canvas, &renderer, stacked, category_names[..], series_names[..], "Signed totals", "docs/chart-previews/stacked_bar.png")
    let (normalized, normalized_error) = chart.stacked_bars(grouped_values[..], 4usize, 2usize, bar_bounds, true, series_bars[..], series_layers[..])
    if normalized_error != ok { ret normalized_error }
    try render_bar_layers(a, queue, output_target, canvas, &renderer, normalized, category_names[..], series_names[..], "Share by category", "docs/chart-previews/stacked_100.png")
    let mekko_values = [12]f32{ 20.0, 10.0, 20.0, 5.0, 15.0, 10.0, 25.0, 20.0, 25.0, 10.0, 15.0, 25.0 }
    let mekko_series = [3]str{ "Core", "Growth", "Services" }
    var mekko_totals: [4]f64 = zero
    var mekko_bars: [12]geometry.Rect = zero
    var mekko_storage: [3]chart.Layout = zero
    let (mekko_layers, mekko_error) = chart.mekko(mekko_values[..], 4usize, 3usize, geometry.rect(44.0, 45.0, 210.0, 148.0), mekko_totals[..], mekko_bars[..], mekko_storage[..])
    if mekko_error != ok { ret mekko_error }
    try render_mekko(a, queue, output_target, canvas, &renderer, mekko_layers, category_names[..], mekko_series[..], "docs/chart-previews/mekko.png")
    try render_mosaic_preview(a, queue, output_target, canvas, &renderer)
    try render_association_preview(a, queue, output_target, canvas, &renderer)
    try render_fourfold_preview(a, queue, output_target, canvas, &renderer)
    try render_horizon_preview(a, queue, output_target, canvas, &renderer)
    try render_seasonal_preview(a, queue, output_target, canvas, &renderer)
    try render_fan_preview(a, queue, output_target, canvas, &renderer)
    try render_decomposition_preview(a, queue, output_target, canvas, &renderer)
    try render_correlogram_preview(a, queue, output_target, canvas, &renderer)
    try render_variogram_preview(a, queue, output_target, canvas, &renderer)
    let pyramid_left = [6]f32{ 55.0, 70.0, 83.0, 72.0, 50.0, 31.0 }
    let pyramid_right = [6]f32{ 52.0, 68.0, 78.0, 75.0, 57.0, 40.0 }
    let pyramid_ages = [6]str{ "0-9", "10-19", "20-29", "30-39", "40-49", "50+" }
    var pyramid_bars: [12]geometry.Rect = zero
    var pyramid_storage: [2]chart.Layout = zero
    let (pyramid_layers, pyramid_error) = chart.population_pyramid(pyramid_left[..], pyramid_right[..], geometry.rect(20.0, 58.0, 320.0, 156.0), 50.0, 4.0, pyramid_bars[..], pyramid_storage[..])
    if pyramid_error != ok { ret pyramid_error }
    try render_population_pyramid(a, queue, output_target, canvas, &renderer, pyramid_layers, pyramid_bars[..], pyramid_ages[..], "docs/chart-previews/population_pyramid.png")
    let bullet_ranges = [3]f32{ 40.0, 70.0, 100.0 }
    var bullet_bars: [4]geometry.Rect = zero
    var bullet_target: [1]chart.Segment = zero
    var bullet_storage: [5]chart.Layout = zero
    let (bullet_layers, bullet_error) = chart.bullet(62.0, 80.0, bullet_ranges[..], geometry.rect(44.0, 86.0, 286.0, 66.0), bullet_bars[..], bullet_target[..], bullet_storage[..])
    if bullet_error != ok { ret bullet_error }
    try render_bullet(a, queue, output_target, canvas, &renderer, bullet_layers, "docs/chart-previews/bullet.png")
    var gauge_points: [196]chart.Coord = zero
    var gauge_target: [1]chart.Segment = zero
    var gauge_storage: [3]chart.Layout = zero
    let (gauge_layers, gauge_error) = chart.gauge(72.0, 80.0, 100.0, geometry.rect(28.0, 52.0, 190.0, 122.0), 0.62, gauge_points[..], gauge_target[..], gauge_storage[..])
    if gauge_error != ok { ret gauge_error }
    try render_gauge(a, queue, output_target, canvas, &renderer, gauge_layers, "docs/chart-previews/gauge.png")
    let (kpi_status, kpi_error) = chart.target_status(96.0, 80.0, true)
    if kpi_error != ok { ret kpi_error }
    let (kpi_layers, kpi_layout_error) = chart.bullet(96.0, 80.0, bullet_ranges[..], geometry.rect(34.0, 158.0, 292.0, 34.0), bullet_bars[..], bullet_target[..], bullet_storage[..])
    if kpi_layout_error != ok { ret kpi_layout_error }
    try render_kpi(a, queue, output_target, canvas, &renderer, kpi_layers, kpi_status, "docs/chart-previews/kpi_target.png")
    let pareto_values = [5]f32{ 3.0, 8.0, 5.0, 2.0, 6.0 }
    let pareto_names = [5]str{ "North", "South", "East", "West", "Central" }
    var pareto_order: [5]usize = zero
    var pareto_bars: [5]geometry.Rect = zero
    var pareto_points: [5]chart.Coord = zero
    var pareto_lines: [4]chart.Segment = zero
    var pareto_storage: [2]chart.Layout = zero
    let pareto_bounds = geometry.rect(48.0, 36.0, 246.0, 158.0)
    let (pareto_layers, pareto_error) = chart.pareto(pareto_values[..], pareto_bounds, pareto_order[..], pareto_bars[..], pareto_points[..], pareto_lines[..], pareto_storage[..])
    if pareto_error != ok { ret pareto_error }
    var ordered_names: [5]str = zero
    i = 0usize
    while i < pareto_order.len {
        ordered_names[i] = pareto_names[pareto_order[i]]
        i += 1usize
    }
    try render_dual_axis(a, queue, output_target, canvas, &renderer, pareto_layers, ordered_names[..], "Pareto frequency and cumulative share", true, "docs/chart-previews/pareto.png")
    let combo_columns = [5]f32{ 12.0, 15.0, 11.0, 18.0, 22.0 }
    let combo_trend = [5]f32{ 110.0, 130.0, 125.0, 170.0, 210.0 }
    var combo_x: [5]f32 = zero
    var combo_bars: [5]geometry.Rect = zero
    var combo_points: [5]chart.Coord = zero
    var combo_segments: [4]chart.Segment = zero
    var combo_storage: [2]chart.Layout = zero
    let (combo_layers, combo_error) = chart.combo_bar_line(combo_columns[..], combo_trend[..], pareto_bounds, combo_x[..], combo_bars[..], combo_points[..], combo_segments[..], combo_storage[..])
    if combo_error != ok { ret combo_error }
    try render_dual_axis(a, queue, output_target, canvas, &renderer, combo_layers, pareto_names[..], "Volume and index (secondary axis)", false, "docs/chart-previews/combo_bar_line.png")
    let pie_values = [5]f32{ 30.0, 24.0, 18.0, 16.0, 12.0 }
    let pie_names = [5]str{ "North 30%", "South 24%", "East 18%", "West 16%", "Other 12%" }
    var pie_points: [512]chart.Coord = zero
    var pie_storage: [5]chart.Layout = zero
    let pie_bounds = geometry.rect(28.0, 33.0, 190.0, 190.0)
    let (pie_layers, pie_error) = chart.pie(pie_values[..], pie_bounds, 0.0, pie_points[..], pie_storage[..])
    if pie_error != ok { ret pie_error }
    try render_share(a, queue, output_target, canvas, &renderer, pie_layers, pie_names[..], "Category share", "docs/chart-previews/pie.png")
    let (donut_layers, donut_error) = chart.pie(pie_values[..], pie_bounds, 0.54, pie_points[..], pie_storage[..])
    if donut_error != ok { ret donut_error }
    try render_share(a, queue, output_target, canvas, &renderer, donut_layers, pie_names[..], "Category share", "docs/chart-previews/donut.png")
    try render_radar_preview(a, queue, output_target, canvas, &renderer)
    try render_ternary_preview(a, queue, output_target, canvas, &renderer)
    try render_quiver_preview(a, queue, output_target, canvas, &renderer)
    try render_streamlines_preview(a, queue, output_target, canvas, &renderer)
    try render_phase_space_preview(a, queue, output_target, canvas, &renderer)
    try render_recurrence_preview(a, queue, output_target, canvas, &renderer)
    try render_earned_value_preview(a, queue, output_target, canvas, &renderer)
    try render_burn_previews(a, queue, output_target, canvas, &renderer)
    try render_drawdown_preview(a, queue, output_target, canvas, &renderer)
    try render_cohort_preview(a, queue, output_target, canvas, &renderer)
    try render_contour_preview(a, queue, output_target, canvas, &renderer)
    let rose_values = [5]f32{ 10.0, 18.0, 8.0, 5.0, 14.0 }
    let rose_names = [5]str{ "0 deg", "72 deg", "144 deg", "216 deg", "288 deg" }
    var rose_points: [115]chart.Coord = zero
    var rose_storage: [5]chart.Layout = zero
    let (rose_layers, rose_error) = chart.rose(rose_values[..], pie_bounds, rose_points[..], rose_storage[..])
    if rose_error != ok { ret rose_error }
    try render_share(a, queue, output_target, canvas, &renderer, rose_layers, rose_names[..], "Area-scaled wind rose", "docs/chart-previews/rose.png")
    var waffle_bars: [100]geometry.Rect = zero
    let (waffle_layers, waffle_error) = chart.waffle(pie_values[..], pie_bounds, 10usize, 10usize, 2.0, waffle_bars[..], pie_storage[..])
    if waffle_error != ok { ret waffle_error }
    try render_share(a, queue, output_target, canvas, &renderer, waffle_layers, pie_names[..], "100-cell composition", "docs/chart-previews/waffle.png")
    let tree_parents = [9]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize }
    let tree_weights = [9]f32{ 0.0, 0.0, 0.0, 36.0, 22.0, 17.0, 20.0, 15.0, 10.0 }
    let tree_names = [9]str{ "All", "Digital", "Operations", "Cloud", "Apps", "Data", "Supply", "Field", "Support" }
    var tree_totals: [9]f64 = zero
    var tree_rects: [9]geometry.Rect = zero
    var tree_storage: [9]chart.Layout = zero
    let (tree_layers, tree_error) = chart.treemap(tree_parents[..], tree_weights[..], geometry.rect(24.0, 38.0, 312.0, 176.0), tree_totals[..], tree_rects[..], tree_storage[..])
    if tree_error != ok { ret tree_error }
    try render_treemap(a, queue, output_target, canvas, &renderer, tree_layers, tree_rects[..], tree_names[..], "docs/chart-previews/treemap.png")
    var ice_depths: [9]usize = zero
    let (ice_layers, ice_error) = chart.icicle(tree_parents[..], tree_weights[..], geometry.rect(24.0, 38.0, 312.0, 176.0), tree_totals[..], ice_depths[..], tree_rects[..], tree_storage[..])
    if ice_error != ok { ret ice_error }
    let ice_names = [9]str{ "All", "Digital", "Operations", "Cloud", "Apps", "Data", "Supply", "Field", "IT" }
    try render_icicle(a, queue, output_target, canvas, &renderer, ice_layers, tree_rects[..], ice_names[..], "docs/chart-previews/icicle.png")
    let sun_parents = [8]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 2usize, 2usize }
    let sun_weights = [8]f32{ 0.0, 0.0, 0.0, 30.0, 20.0, 10.0, 25.0, 15.0 }
    let sun_names = [5]str{ "Cloud 30", "Apps 20", "Data 10", "Supply 25", "Field 15" }
    var sun_totals: [8]f64 = zero
    var sun_depths: [8]usize = zero
    var sun_arcs: [8]chart.SunburstArc = zero
    var sun_points: [1600]chart.Coord = zero
    var sun_storage: [8]chart.Layout = zero
    let (sun_layers, sun_error) = chart.sunburst(sun_parents[..], sun_weights[..], geometry.rect(25.0, 33.0, 190.0, 190.0), 0.23, sun_totals[..], sun_depths[..], sun_arcs[..], sun_points[..], sun_storage[..])
    if sun_error != ok { ret sun_error }
    try render_radial_hierarchy(a, queue, output_target, canvas, &renderer, sun_layers, sun_names[..], 3usize, true, "Hierarchical sunburst", "docs/chart-previews/sunburst.png")
    var circle_rects: [8]geometry.Rect = zero
    var circle_storage: [8]chart.Layout = zero
    let (circle_layers, circle_error) = chart.circle_pack(sun_parents[..], sun_weights[..], geometry.rect(25.0, 33.0, 190.0, 190.0), 0.04, sun_totals[..], circle_rects[..], circle_storage[..])
    if circle_error != ok { ret circle_error }
    let circle_names = [7]str{ "Digital", "Operations", "Cloud 30", "Apps 20", "Data 10", "Supply 25", "Field 15" }
    try render_radial_hierarchy(a, queue, output_target, canvas, &renderer, circle_layers, circle_names[..], 1usize, false, "Circle packing", "docs/chart-previews/circle_pack.png")
    var euler_circles: [2]geometry.Rect = zero
    var euler_storage: [2]chart.Layout = zero
    let (euler_layers, euler_error) = chart.euler2(30.0, 25.0, 10.0, geometry.rect(20.0, 40.0, 200.0, 175.0), euler_circles[..], euler_storage[..])
    if euler_error != ok { ret euler_error }
    let ex0 = euler_circles[0usize].x + euler_circles[0usize].width * 0.5
    let ex1 = euler_circles[1usize].x + euler_circles[1usize].width * 0.5
    let ey = euler_circles[0usize].y + euler_circles[0usize].height * 0.5
    let euler_anchors = [3]chart.Coord{
        chart.Coord { x: ex0 - euler_circles[0usize].width * 0.25, y: ey },
        chart.Coord { x: (ex0 + ex1) * 0.5, y: ey },
        chart.Coord { x: ex1 + euler_circles[1usize].width * 0.25, y: ey },
    }
    let euler_names = [2]str{ "A 30", "B 25" }
    let euler_regions = [3]str{ "20", "10", "15" }
    try render_circle_sets(a, queue, output_target, canvas, &renderer, euler_layers, euler_names[..], euler_regions[..], euler_anchors[..], "Measured overlap", "docs/chart-previews/euler2.png")
    var venn_circles: [3]geometry.Rect = zero
    var venn_anchors: [7]chart.Coord = zero
    var venn_storage: [3]chart.Layout = zero
    let (venn_layers, venn_error) = chart.venn3(geometry.rect(20.0, 40.0, 200.0, 175.0), venn_circles[..], venn_anchors[..], venn_storage[..])
    if venn_error != ok { ret venn_error }
    let venn_names = [3]str{ "A", "B", "C" }
    let venn_regions = [7]str{ "A", "B", "C", "AB", "AC", "BC", "ABC" }
    try render_circle_sets(a, queue, output_target, canvas, &renderer, venn_layers, venn_names[..], venn_regions[..], venn_anchors[..], "Three-set Venn", "docs/chart-previews/venn3.png")
    let cloud_words = [12]str{ "Neper", "Charts", "Graphics", "Data", "Layers", "Scales", "SVG", "Statistics", "Labels", "Facets", "the", "Export" }
    let cloud_weights = [12]f32{ 50.0, 36.0, 25.0, 20.0, 18.0, 15.0, 12.0, 11.0, 10.0, 9.0, 100.0, 8.0 }
    let cloud_excluded = [1]str{ "the" }
    let (cloud_bytes, cloud_font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if cloud_font_error != ok { ret cloud_font_error }
    let cloud_font = shape.Font { id: 17u32, data: cloud_bytes, face_index: 0u32 }
    let cloud_fonts = [1]text_layout.FontChoice{ text_layout.FontChoice { font: cloud_font, size: 16.0 } }
    let cloud_style = text_layout.Style { fonts: cloud_fonts[..], language: "", line_height: 0.0 }
    let cloud_options = text_layout.Options { width: 0.0, max_lines: 1u32, align: .Start, wrap: .None, ellipsis: "", notdef: true }
    var cloud_widths: [12]f32 = zero
    var cloud_heights: [12]f32 = zero
    var cloud_baseline = 0.0f32
    var cloud_index = 0usize
    while cloud_index < cloud_words.len {
        let (measured, measure_error) = text_layout.layout(a, cloud_words[cloud_index], cloud_style, cloud_options)
        if measure_error != ok { ret measure_error }
        if measured.lines.len != 1usize { ret chart.Invalid }
        cloud_widths[cloud_index] = measured.bounds.width / 16.0
        cloud_heights[cloud_index] = measured.bounds.height / 16.0
        cloud_baseline = measured.lines[0usize].baseline / 16.0
        cloud_index += 1usize
    }
    var cloud_order: [12]usize = zero
    var cloud_storage: [12]chart.CloudWord = zero
    let (cloud_marks, cloud_error) = chart.word_cloud(cloud_words[..], cloud_weights[..], cloud_widths[..], cloud_heights[..], cloud_baseline, cloud_excluded[..], geometry.rect(20.0, 42.0, 320.0, 180.0), 9.0, 32.0, 5.0, cloud_order[..], cloud_storage[..])
    if cloud_error != ok { ret cloud_error }
    try render_word_cloud(a, queue, output_target, canvas, &renderer, cloud_font, cloud_marks, "docs/chart-previews/word_cloud.png")
    let chord_values = [16]f32{ 0.0, 8.0, 5.0, 3.0, 4.0, 0.0, 6.0, 5.0, 7.0, 3.0, 0.0, 4.0, 2.0, 6.0, 5.0, 0.0 }
    let chord_names = [4]str{ "Design", "Build", "Sales", "Support" }
    var chord_totals: [4]f64 = zero
    var chord_arcs: [4]chart.SunburstArc = zero
    var chord_subarcs: [16]chart.SunburstArc = zero
    var chord_points: [450]chart.Coord = zero
    var chord_storage: [14]chart.Layout = zero
    let (chord_layers, chord_error) = chart.chord(chord_values[..], 4usize, geometry.rect(25.0, 33.0, 190.0, 190.0), 0.78, 0.06, 12usize, chord_totals[..], chord_arcs[..], chord_subarcs[..], chord_points[..], chord_storage[..])
    if chord_error != ok { ret chord_error }
    try render_chord(a, queue, output_target, canvas, &renderer, chord_layers, chord_names[..], "docs/chart-previews/chord.png")
    let flow_columns = [6]usize{ 0usize, 0usize, 1usize, 1usize, 2usize, 2usize }
    let flow_sources = [8]usize{ 0usize, 0usize, 1usize, 1usize, 2usize, 2usize, 3usize, 3usize }
    let flow_targets = [8]usize{ 2usize, 3usize, 2usize, 3usize, 4usize, 5usize, 4usize, 5usize }
    let flow_values = [8]f32{ 35.0, 25.0, 15.0, 25.0, 30.0, 20.0, 15.0, 35.0 }
    let flow_names = [6]str{ "Search", "Referral", "Trial", "Direct", "Won", "Lost" }
    let flow_colors = [14]paint.Color{
        paint.rgba(0.17, 0.44, 0.77, 0.50), paint.rgba(0.17, 0.44, 0.77, 0.50),
        paint.rgba(0.84, 0.40, 0.14, 0.50), paint.rgba(0.84, 0.40, 0.14, 0.50),
        paint.rgba(0.10, 0.54, 0.53, 0.50), paint.rgba(0.10, 0.54, 0.53, 0.50),
        paint.rgba(0.39, 0.36, 0.70, 0.50), paint.rgba(0.39, 0.36, 0.70, 0.50),
        paint.rgba(0.08, 0.31, 0.62, 1.0), paint.rgba(0.69, 0.31, 0.09, 1.0),
        paint.rgba(0.07, 0.45, 0.44, 1.0), paint.rgba(0.34, 0.30, 0.62, 1.0),
        paint.rgba(0.10, 0.50, 0.29, 1.0), paint.rgba(0.65, 0.21, 0.27, 1.0),
    }
    var flow_nodes: [6]chart.SankeyNode = zero
    var flow_rects: [6]geometry.Rect = zero
    var flow_points: [144]chart.Coord = zero
    var flow_storage: [14]chart.Layout = zero
    let (flow_layers, flow_error) = chart.sankey(flow_columns[..], 3usize, flow_sources[..], flow_targets[..], flow_values[..], geometry.rect(20.0, 42.0, 320.0, 176.0), 56.0, 14.0, 8usize, flow_nodes[..], flow_rects[..], flow_points[..], flow_storage[..])
    if flow_error != ok { ret flow_error }
    try render_sankey(a, queue, output_target, canvas, &renderer, flow_layers, flow_rects[..], flow_names[..], flow_colors[..], "Journey flows", "docs/chart-previews/sankey.png")
    let alluvial_columns = [8]usize{ 0usize, 0usize, 1usize, 1usize, 2usize, 2usize, 3usize, 3usize }
    let alluvial_sources = [12]usize{ 0usize, 0usize, 1usize, 1usize, 2usize, 2usize, 3usize, 3usize, 4usize, 4usize, 5usize, 5usize }
    let alluvial_targets = [12]usize{ 2usize, 3usize, 2usize, 3usize, 4usize, 5usize, 5usize, 4usize, 6usize, 7usize, 6usize, 7usize }
    let alluvial_values = [12]f32{ 35.0, 25.0, 15.0, 25.0, 35.0, 15.0, 25.0, 25.0, 35.0, 25.0, 15.0, 25.0 }
    let alluvial_names = [8]str{ "North", "South", "Web", "Store", "Trial", "Paid", "Stay", "Leave" }
    let alluvial_colors = [20]paint.Color{
        paint.rgba(0.12, 0.40, 0.76, 0.52), paint.rgba(0.86, 0.36, 0.16, 0.52), paint.rgba(0.13, 0.58, 0.48, 0.52), paint.rgba(0.52, 0.35, 0.72, 0.52),
        paint.rgba(0.12, 0.40, 0.76, 0.52), paint.rgba(0.13, 0.58, 0.48, 0.52), paint.rgba(0.86, 0.36, 0.16, 0.52), paint.rgba(0.52, 0.35, 0.72, 0.52),
        paint.rgba(0.12, 0.40, 0.76, 0.52), paint.rgba(0.52, 0.35, 0.72, 0.52), paint.rgba(0.13, 0.58, 0.48, 0.52), paint.rgba(0.86, 0.36, 0.16, 0.52),
        paint.rgba(0.08, 0.31, 0.62, 1.0), paint.rgba(0.69, 0.31, 0.09, 1.0), paint.rgba(0.07, 0.45, 0.44, 1.0), paint.rgba(0.34, 0.30, 0.62, 1.0),
        paint.rgba(0.10, 0.50, 0.29, 1.0), paint.rgba(0.65, 0.21, 0.27, 1.0), paint.rgba(0.08, 0.31, 0.62, 1.0), paint.rgba(0.69, 0.31, 0.09, 1.0),
    }
    var alluvial_nodes: [8]chart.SankeyNode = zero
    var alluvial_rects: [8]geometry.Rect = zero
    var alluvial_points: [216]chart.Coord = zero
    var alluvial_storage: [20]chart.Layout = zero
    let (alluvial_layers, alluvial_error) = chart.alluvial(alluvial_columns[..], 4usize, alluvial_sources[..], alluvial_targets[..], alluvial_values[..], geometry.rect(14.0, 42.0, 332.0, 176.0), 40.0, 14.0, 8usize, alluvial_nodes[..], alluvial_rects[..], alluvial_points[..], alluvial_storage[..])
    if alluvial_error != ok { ret alluvial_error }
    try render_sankey(a, queue, output_target, canvas, &renderer, alluvial_layers, alluvial_rects[..], alluvial_names[..], alluvial_colors[..], "Cohorts across stages", "docs/chart-previews/alluvial.png")
    let stream_x = [9]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 }
    let stream_values = [45]f32{
        8.0, 4.0, 2.0, 3.0, 1.0, 10.0, 6.0, 3.0, 4.0, 2.0,
        14.0, 8.0, 4.0, 3.0, 2.0, 12.0, 11.0, 7.0, 5.0, 3.0,
        8.0, 13.0, 10.0, 7.0, 4.0, 5.0, 11.0, 12.0, 10.0, 6.0,
        4.0, 8.0, 10.0, 12.0, 8.0, 3.0, 6.0, 8.0, 10.0, 10.0,
        2.0, 4.0, 6.0, 8.0, 12.0,
    }
    let stream_names = [5]str{ "Search", "Social", "Email", "Direct", "Partners" }
    var stream_totals: [9]f64 = zero
    var stream_cumulative: [9]f64 = zero
    var stream_points: [90]chart.Coord = zero
    var stream_storage: [5]chart.Layout = zero
    let (stream_layers, stream_error) = chart.streamgraph(stream_x[..], stream_values[..], 5usize, geometry.rect(18.0, 42.0, 192.0, 176.0), stream_totals[..], stream_cumulative[..], stream_points[..], stream_storage[..])
    if stream_error != ok { ret stream_error }
    try render_share(a, queue, output_target, canvas, &renderer, stream_layers, stream_names[..], "Centered streamgraph", "docs/chart-previews/streamgraph.png")
    let rank_x = [6]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0 }
    let rank_values = [30]f32{
        90.0, 75.0, 60.0, 45.0, 30.0,
        80.0, 95.0, 65.0, 50.0, 35.0,
        65.0, 82.0, 98.0, 55.0, 40.0,
        54.0, 72.0, 85.0, 110.0, 46.0,
        45.0, 62.0, 75.0, 93.0, 115.0,
        55.0, 70.0, 85.0, 100.0, 120.0,
    }
    let rank_names = [5]str{ "Atlas", "Beacon", "Comet", "Delta", "Ember" }
    var rank_points: [60]chart.Coord = zero
    var rank_storage: [5]chart.Layout = zero
    let (rank_layers, rank_error) = chart.ribbon_rank(rank_x[..], rank_values[..], 5usize, geometry.rect(18.0, 42.0, 192.0, 176.0), 5.0, rank_points[..], rank_storage[..])
    if rank_error != ok { ret rank_error }
    try render_share(a, queue, output_target, canvas, &renderer, rank_layers, rank_names[..], "Ranks over time", "docs/chart-previews/ribbon_rank.png")
    let timeline_rows = [4]str{ "API", "Queue", "DB", "Worker" }
    let timeline_states = [3]str{ "Idle", "Running", "Paused" }
    let timeline_colors = [3]paint.Color{ paint.rgba(0.48, 0.57, 0.67, 1.0), paint.rgba(0.08, 0.43, 0.78, 1.0), paint.rgba(0.91, 0.53, 0.15, 1.0) }
    let timeline_spans = [17]chart.StateSpan{
        chart.StateSpan { row: 0usize, start: 0.0, end: 2.0, state: 0usize },
        chart.StateSpan { row: 0usize, start: 2.0, end: 5.0, state: 1usize },
        chart.StateSpan { row: 0usize, start: 5.0, end: 8.0, state: 1usize },
        chart.StateSpan { row: 0usize, start: 8.0, end: 9.0, state: 2usize },
        chart.StateSpan { row: 0usize, start: 9.0, end: 12.0, state: 1usize },
        chart.StateSpan { row: 1usize, start: 0.0, end: 1.0, state: 0usize },
        chart.StateSpan { row: 1usize, start: 1.0, end: 4.0, state: 1usize },
        chart.StateSpan { row: 1usize, start: 4.0, end: 6.0, state: 2usize },
        chart.StateSpan { row: 1usize, start: 6.0, end: 12.0, state: 1usize },
        chart.StateSpan { row: 2usize, start: 0.0, end: 3.0, state: 1usize },
        chart.StateSpan { row: 2usize, start: 3.0, end: 4.0, state: 2usize },
        chart.StateSpan { row: 2usize, start: 4.0, end: 10.0, state: 1usize },
        chart.StateSpan { row: 2usize, start: 10.0, end: 12.0, state: 0usize },
        chart.StateSpan { row: 3usize, start: 0.0, end: 2.0, state: 0usize },
        chart.StateSpan { row: 3usize, start: 2.0, end: 7.0, state: 1usize },
        chart.StateSpan { row: 3usize, start: 7.0, end: 8.0, state: 2usize },
        chart.StateSpan { row: 3usize, start: 8.0, end: 12.0, state: 1usize },
    }
    var timeline_rects: [17]geometry.Rect = zero
    var timeline_state_ids: [17]usize = zero
    var timeline_storage: [17]chart.Layout = zero
    let timeline_bounds = geometry.rect(68.0, 54.0, 188.0, 148.0)
    let (timeline_layers, timeline_error) = chart.state_timeline(timeline_spans[..], 4usize, 3usize, 0.0f64, 12.0f64, timeline_bounds, 4.0, timeline_rects[..], timeline_state_ids[..], timeline_storage[..])
    if timeline_error != ok { ret timeline_error }
    try render_state_timeline(a, queue, output_target, canvas, &renderer, timeline_layers, timeline_state_ids[..], timeline_rows[..], timeline_states[..], timeline_colors[..], "State timeline", "docs/chart-previews/state_timeline.png")
    let history_states = [3]str{ "Healthy", "Warning", "Down" }
    let history_colors = [3]paint.Color{ paint.rgba(0.11, 0.61, 0.43, 1.0), paint.rgba(0.91, 0.59, 0.15, 1.0), paint.rgba(0.84, 0.25, 0.25, 1.0) }
    let history_spans = [15]chart.StateSpan{
        chart.StateSpan { row: 0usize, start: 0.0, end: 3.0, state: 0usize },
        chart.StateSpan { row: 0usize, start: 3.0, end: 4.0, state: 1usize },
        chart.StateSpan { row: 0usize, start: 4.0, end: 5.0, state: 2usize },
        chart.StateSpan { row: 0usize, start: 5.0, end: 12.0, state: 0usize },
        chart.StateSpan { row: 1usize, start: 0.0, end: 6.0, state: 0usize },
        chart.StateSpan { row: 1usize, start: 6.0, end: 7.0, state: 1usize },
        chart.StateSpan { row: 1usize, start: 8.0, end: 10.0, state: 1usize },
        chart.StateSpan { row: 1usize, start: 10.0, end: 12.0, state: 0usize },
        chart.StateSpan { row: 2usize, start: 0.0, end: 2.0, state: 0usize },
        chart.StateSpan { row: 2usize, start: 2.0, end: 3.0, state: 2usize },
        chart.StateSpan { row: 2usize, start: 3.0, end: 12.0, state: 0usize },
        chart.StateSpan { row: 3usize, start: 0.0, end: 4.0, state: 0usize },
        chart.StateSpan { row: 3usize, start: 4.0, end: 5.0, state: 1usize },
        chart.StateSpan { row: 3usize, start: 5.0, end: 6.0, state: 1usize },
        chart.StateSpan { row: 3usize, start: 6.0, end: 12.0, state: 0usize },
    }
    let (history_layers, history_error) = chart.state_timeline(history_spans[..], 4usize, 3usize, 0.0f64, 12.0f64, timeline_bounds, 4.0, timeline_rects[..], timeline_state_ids[..], timeline_storage[..])
    if history_error != ok { ret history_error }
    try render_state_timeline(a, queue, output_target, canvas, &renderer, history_layers, timeline_state_ids[..], timeline_rows[..], history_states[..], history_colors[..], "Status history", "docs/chart-previews/status_history.png")
    try render_sparklines(a, queue, output_target, canvas, &renderer)
    try render_calendar_preview(a, queue, output_target, canvas, &renderer)
    try render_risk_matrix_preview(a, queue, output_target, canvas, &renderer)
    try render_resource_histogram_preview(a, queue, output_target, canvas, &renderer)
    try render_swimlane_preview(a, queue, output_target, canvas, &renderer)
    try render_kanban_preview(a, queue, output_target, canvas, &renderer)
    try render_pert_cpm_preview(a, queue, output_target, canvas, &renderer)
    try render_value_stream_preview(a, queue, output_target, canvas, &renderer)
    try render_sipoc_preview(a, queue, output_target, canvas, &renderer)
    try render_decision_tree_preview(a, queue, output_target, canvas, &renderer)
    try render_org_chart_preview(a, queue, output_target, canvas, &renderer)
    try render_dependency_graph_preview(a, queue, output_target, canvas, &renderer)
    try render_flowchart_preview(a, queue, output_target, canvas, &renderer)
    try render_gantt_preview(a, queue, output_target, canvas, &renderer)
    try render_milestone_roadmap_preview(a, queue, output_target, canvas, &renderer)
    try render_event_preview(a, queue, output_target, canvas, &renderer)
    try render_cell_bars_preview(a, queue, output_target, canvas, &renderer)
    try render_forest_preview(a, queue, output_target, canvas, &renderer)
    try render_agreement_preview(a, queue, output_target, canvas, &renderer)
    try render_survival_previews(a, queue, output_target, canvas, &renderer)
    try render_control_previews(a, queue, output_target, canvas, &renderer)
    try render_subgroup_phase_previews(a, queue, output_target, canvas, &renderer)
    try render_run_rules_preview(a, queue, output_target, canvas, &renderer)
    try render_parallel_preview(a, queue, output_target, canvas, &renderer)
    try render_pairs_preview(a, queue, output_target, canvas, &renderer)
    try render_phase_control_preview(a, queue, output_target, canvas, &renderer)
    try render_weighted_control_previews(a, queue, output_target, canvas, &renderer)
    try render_attribute_previews(a, queue, output_target, canvas, &renderer)
    try render_laney_previews(a, queue, output_target, canvas, &renderer)
    try render_rare_event_previews(a, queue, output_target, canvas, &renderer)
    let diagnostic_scores = [16]f64{ 0.98f64, 0.93f64, 0.89f64, 0.84f64, 0.78f64, 0.72f64, 0.68f64, 0.62f64, 0.56f64, 0.50f64, 0.44f64, 0.38f64, 0.32f64, 0.26f64, 0.18f64, 0.08f64 }
    let diagnostic_positive = [16]bool{ true, true, false, true, true, false, true, false, true, false, true, false, false, true, false, false }
    var diagnostic_order: [16]usize = zero
    var diagnostic_points: [17]stat.BinaryPoint = zero
    let (diagnostic, diagnostic_error) = stat.binary_curve(diagnostic_scores[..], diagnostic_positive[..], diagnostic_order[..], diagnostic_points[..])
    if diagnostic_error != ok { ret diagnostic_error }
    try render_binary_preview(a, queue, output_target, canvas, &renderer, &diagnostic, .Roc, "ROC curve", "False-positive rate", "TPR", "docs/chart-previews/roc.png")
    try render_binary_preview(a, queue, output_target, canvas, &renderer, &diagnostic, .PrecisionRecall, "Precision-recall", "Recall", "Precision", "docs/chart-previews/precision_recall.png")
    try render_binary_preview(a, queue, output_target, canvas, &renderer, &diagnostic, .CumulativeGain, "Cumulative gain", "Population share", "Gain", "docs/chart-previews/cumulative_gain.png")
    try render_binary_preview(a, queue, output_target, canvas, &renderer, &diagnostic, .Lift, "Cumulative lift", "Population share", "Lift", "docs/chart-previews/cumulative_lift.png")
    try render_roc_extension_preview(a, queue, output_target, canvas, &renderer, &diagnostic, true, "docs/chart-previews/partial_auc.png")
    try render_roc_extension_preview(a, queue, output_target, canvas, &renderer, &diagnostic, false, "docs/chart-previews/youden_index.png")
    try render_decision_preview(a, queue, output_target, canvas, &renderer, diagnostic_scores[..], diagnostic_positive[..], "docs/chart-previews/decision_curve.png")
    var calibration_bins: [5]stat.CalibrationBin = zero
    try stat.binary_calibration(diagnostic_scores[..], diagnostic_positive[..], calibration_bins[..])
    try render_calibration_preview(a, queue, output_target, canvas, &renderer, calibration_bins[..], "docs/chart-previews/calibration.png")
    let (confusion, confusion_error) = stat.binary_confusion(diagnostic_scores[..], diagnostic_positive[..], 0.5f64)
    if confusion_error != ok { ret confusion_error }
    try render_confusion_preview(a, queue, output_target, canvas, &renderer, &confusion, "docs/chart-previews/confusion_matrix.png")
    let funnel_values = [5]f32{ 100.0, 74.0, 52.0, 31.0, 18.0 }
    let funnel_names = [5]str{ "Visits 100", "Leads 74", "Qualified 52", "Trials 31", "Won 18" }
    var funnel_points: [20]chart.Coord = zero
    let (funnel_layers, funnel_error) = chart.funnel(funnel_values[..], pie_bounds, 4.0, funnel_points[..], pie_storage[..])
    if funnel_error != ok { ret funnel_error }
    try render_share(a, queue, output_target, canvas, &renderer, funnel_layers, funnel_names[..], "Conversion funnel", "docs/chart-previews/funnel.png")
    let waterfall_values = [6]f32{ 12.0, 5.0, -3.0, 4.0, -6.0, 2.0 }
    var waterfall_bars: [7]geometry.Rect = zero
    var waterfall_links: [6]chart.Segment = zero
    let (waterfall_marks, waterfall_error) = chart.waterfall(waterfall_values[..], bounds, waterfall_bars[..], waterfall_links[..])
    if waterfall_error != ok { ret waterfall_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &waterfall_marks, "docs/chart-previews/waterfall.png")
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
    var band_outline: [16]chart.Coord = zero
    let (ribbon, ribbon_error) = chart.band(x[..], lower[..], upper[..], bounds, band_outline[..])
    if ribbon_error != ok { ret ribbon_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &ribbon, "docs/chart-previews/band.png")
    var dumbbell_points: [16]chart.Coord = zero
    var dumbbell_lines: [8]chart.Segment = zero
    let (dumbbells, dumbbell_error) = chart.dumbbell(x[..], lower[..], upper[..], bounds, dumbbell_points[..], dumbbell_lines[..])
    if dumbbell_error != ok { ret dumbbell_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &dumbbells, "docs/chart-previews/dumbbell.png")
    let values = [16]f32{ 1.0, 2.0, 2.0, 2.5, 3.0, 3.5, 4.0, 4.0, 4.0, 5.0, 5.5, 6.0, 6.0, 7.0, 8.0, 8.5 }
    var counts: [8]u64 = zero
    var hist_bars: [8]geometry.Rect = zero
    let (hist, hist_error) = chart.histogram(values[..], bounds, counts[..], hist_bars[..])
    if hist_error != ok { ret hist_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &hist, "docs/chart-previews/histogram.png")
    var frequency_segments: [9]chart.Segment = zero
    let (frequency, frequency_error) = chart.frequency_polygon(values[..], bounds, counts[..], hist_bars[..], frequency_segments[..])
    if frequency_error != ok { ret frequency_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &frequency, "docs/chart-previews/frequency_polygon.png")
    var rug_segments: [16]chart.Segment = zero
    let (rug_marks, rug_error) = chart.rug(values[..], bounds, 18.0, rug_segments[..])
    if rug_error != ok { ret rug_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &rug_marks, "docs/chart-previews/rug.png")
    var strip_points: [16]chart.Coord = zero
    let (strip_marks, strip_error) = chart.strip(values[..], bounds, 24.0, strip_points[..])
    if strip_error != ok { ret strip_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &strip_marks, "docs/chart-previews/strip.png")
    let dot_values = [20]f32{
        1.0, 1.0, 1.0,
        2.0, 2.0, 2.0, 2.0, 2.0, 2.0,
        3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0,
        4.0, 4.0, 4.0,
    }
    var swarm_points: [20]chart.Coord = zero
    let (swarm, swarm_error) = chart.beeswarm(dot_values[..], bounds, 12.0, swarm_points[..])
    if swarm_error != ok { ret swarm_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &swarm, "docs/chart-previews/beeswarm.png")
    var dot_counts: [4]u64 = zero
    var dot_bins: [4]geometry.Rect = zero
    var dot_points: [20]chart.Coord = zero
    let (dots, dots_error) = chart.dot_plot(dot_values[..], bounds, 16.0, dot_counts[..], dot_bins[..], dot_points[..])
    if dots_error != ok { ret dots_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &dots, "docs/chart-previews/dot_plot.png")
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
    let boxen_values = [32]f64{
        0.0, 1.0, 2.0, 3.0, 3.0, 4.0, 4.0, 5.0, 5.0, 6.0, 6.0, 7.0, 7.0, 8.0, 8.0, 9.0,
        9.0, 10.0, 10.0, 11.0, 11.0, 12.0, 13.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 20.0, 22.0, 30.0,
    }
    var boxen_tails: [32]chart.Coord = zero
    var boxen_median: [1]chart.Segment = zero
    var boxen_boxes: [3]geometry.Rect = zero
    let (boxen, boxen_error) = chart.boxen_plot(boxen_values[..], bounds, 3usize, boxen_tails[..], boxen_median[..], boxen_boxes[..])
    if boxen_error != ok { ret boxen_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &boxen, "docs/chart-previews/boxen.png")
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
    let ridge_values = [36]f64{
        1.0, 2.0, 2.0, 2.5, 3.0, 3.0, 3.5, 4.0, 4.0, 4.5, 5.0, 5.5,
        2.0, 2.5, 3.0, 3.0, 3.5, 4.0, 5.0, 5.0, 5.5, 6.0, 6.5, 7.0,
        4.0, 4.5, 5.0, 5.5, 6.0, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0,
    }
    let ridge_lengths = [3]usize{ 12usize, 12usize, 12usize }
    let ridge_names = [3]str{ "Early", "Middle", "Late" }
    var ridge_grid: [64]f64 = zero
    var ridge_estimates: [192]f64 = zero
    var ridge_bandwidths: [3]f64 = zero
    var ridge_outline: [198]chart.Coord = zero
    var ridge_storage: [3]chart.Layout = zero
    let (ridges, ridge_error) = chart.ridgeline(ridge_values[..], ridge_lengths[..], bounds, 0.0f64, 1.45, ridge_grid[..], ridge_estimates[..], ridge_bandwidths[..], ridge_outline[..], ridge_storage[..])
    if ridge_error != ok { ret ridge_error }
    try render_ridgelines(a, queue, output_target, canvas, &renderer, ridges, ridge_names[..], "docs/chart-previews/ridgeline.png")
    let finance_x = [12]f32{ 1.0, 2.0, 3.0, 4.0, 7.0, 8.0, 9.0, 10.0, 11.0, 14.0, 15.0, 16.0 }
    let finance_open = [12]f32{ 12.0, 14.0, 13.0, 15.0, 14.0, 16.0, 17.0, 16.0, 18.0, 17.0, 19.0, 18.0 }
    let finance_high = [12]f32{ 15.0, 15.0, 16.0, 16.0, 17.0, 18.0, 18.0, 19.0, 19.0, 20.0, 20.0, 21.0 }
    let finance_low = [12]f32{ 11.0, 12.0, 12.0, 13.0, 13.0, 15.0, 15.0, 15.0, 16.0, 16.0, 17.0, 17.0 }
    let finance_close = [12]f32{ 14.0, 13.0, 15.0, 14.0, 16.0, 17.0, 16.0, 18.0, 17.0, 19.0, 18.0, 20.0 }
    var finance_wicks: [24]chart.Segment = zero
    var finance_rising: [12]geometry.Rect = zero
    var finance_falling: [12]geometry.Rect = zero
    var finance_layers: [3]chart.Layout = zero
    let (candles, candle_error) = chart.candlestick(finance_x[..], finance_open[..], finance_high[..], finance_low[..], finance_close[..], bounds, 0.64, finance_wicks[..], finance_rising[..], finance_falling[..], finance_layers[..])
    if candle_error != ok { ret candle_error }
    try render_financial(a, queue, output_target, canvas, &renderer, candles, "Candlestick (OHLC)", "docs/chart-previews/candlestick.png")
    var finance_ticks: [36]chart.Segment = zero
    let (ohlc_marks, ohlc_error) = chart.ohlc(finance_x[..], finance_open[..], finance_high[..], finance_low[..], finance_close[..], bounds, 0.64, finance_ticks[..])
    if ohlc_error != ok { ret ohlc_error }
    var ohlc_layers = [1]chart.Layout{ ohlc_marks }
    try render_financial(a, queue, output_target, canvas, &renderer, ohlc_layers[..], "OHLC price bars", "docs/chart-previews/ohlc.png")
    try render_finance_panel_previews(a, queue, output_target, canvas, &renderer)
    let qq_values = [9]f64{ -2.4, -1.5, -1.1, -0.4, 0.1, 0.5, 1.2, 1.7, 3.0 }
    var qq_points: [9]chart.Coord = zero
    var qq_reference: [1]chart.Segment = zero
    let (qq_plot, qq_error) = chart.qq_normal(qq_values[..], bounds, qq_points[..], qq_reference[..])
    if qq_error != ok { ret qq_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &qq_plot, "docs/chart-previews/qq.png")
    var pp_points: [9]chart.Coord = zero
    var pp_reference: [1]chart.Segment = zero
    let (pp_plot, pp_error) = chart.pp_normal(qq_values[..], 0.0f64, 1.5f64, bounds, pp_points[..], pp_reference[..])
    if pp_error != ok { ret pp_error }
    try render_chart(a, queue, output_target, canvas, &renderer, &pp_plot, "docs/chart-previews/pp_normal.png")
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
    try render_labeled_chart(a, queue, output_target, canvas, &renderer, 0u8)
    try render_labeled_chart(a, queue, output_target, canvas, &renderer, 1u8)
    try render_labeled_chart(a, queue, output_target, canvas, &renderer, 2u8)
    try scene.close(&renderer)
    try gpu.close_target(output_target)
    try gpu.close(device)
    try io.print("chart previews ok\n")
    ret ok
}
