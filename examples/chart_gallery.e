// Render the currently delivered chart kinds through Neper's CPU scene and PNG encoder.
// From the repository root, run this executable to refresh docs/chart-previews/*.png.
use e.algo.stat
use e.algo.geo
use e.algo.rand
use e.dsp
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
use e.gfx.chart.locale as chart_locale
use e.gfx.chart.widget as chart_widget
use e.gfx.chart.pdf as chart_pdf
use e.gfx.chart.geojson
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.text.layout as text_layout
use e.text.locale as text_locale
use e.time as calendar_time
use e.algo.graph.community as community
use e.data.graph as data_graph
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style as ui_style
use e.ui.testing
use e.ui.widget

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

fn render_future_state_vsm_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/future_state_vsm.png"
    let current_steps = [3]chart.ValueStreamStep{
        chart.ValueStreamStep { process_time: 2.0f64, value_added_time: 1.0f64, wait_before: 0.0f64, good_fraction: 0.98f64 },
        chart.ValueStreamStep { process_time: 5.0f64, value_added_time: 4.0f64, wait_before: 4.0f64, good_fraction: 0.95f64 },
        chart.ValueStreamStep { process_time: 3.0f64, value_added_time: 2.0f64, wait_before: 2.0f64, good_fraction: 0.99f64 },
    }
    let future_steps = [3]chart.ValueStreamStep{
        chart.ValueStreamStep { process_time: 2.0f64, value_added_time: 1.5f64, wait_before: 0.0f64, good_fraction: 0.99f64 },
        chart.ValueStreamStep { process_time: 4.2f64, value_added_time: 3.5f64, wait_before: 1.0f64, good_fraction: 0.98f64 },
        chart.ValueStreamStep { process_time: 2.5f64, value_added_time: 2.0f64, wait_before: 0.5f64, good_fraction: 0.995f64 },
    }
    let links = [2]chart.ValueStreamFlow{ .Pull, .Fifo }
    var current_boxes: [3]geometry.Rect = zero
    var current_arrows: [6]chart.Segment = zero
    var current_process: [3]geometry.Rect = zero
    var current_wait: [3]geometry.Rect = zero
    var future_boxes: [3]geometry.Rect = zero
    var future_arrows: [6]chart.Segment = zero
    var future_process: [3]geometry.Rect = zero
    var future_wait: [3]geometry.Rect = zero
    var fifo: [2]geometry.Rect = zero
    var pull: [2]geometry.Rect = zero
    var over: [3]geometry.Rect = zero
    var pace: [1]geometry.Rect = zero
    var work = chart.FutureValueStreamWork {
        current: chart.ValueStreamWork { boxes: current_boxes[..], arrows: current_arrows[..], process_bars: current_process[..], wait_bars: current_wait[..] },
        future: chart.ValueStreamWork { boxes: future_boxes[..], arrows: future_arrows[..], process_bars: future_process[..], wait_bars: future_wait[..] },
        fifo_cues: fifo[..], pull_cues: pull[..], over_takt: over[..], pacemaker: pace[..],
    }
    let (map, map_error) = chart.future_value_stream_map(current_steps[..], future_steps[..], links[..], 8.0f64, 2.0f64, 1usize, geometry.rect(18.0, 38.0, 324.0, 80.0), geometry.rect(18.0, 130.0, 324.0, 80.0), &work)
    if map_error != ok || map.fifo.bars.len != 1usize || map.pull.bars.len != 1usize || map.over_takt.bars.len != 1usize { ret chart.Invalid }
    let blue = paint.rgba(0.12, 0.42, 0.76, 1.0)
    let current_blue = paint.rgba(0.38, 0.52, 0.68, 1.0)
    let orange = paint.rgba(0.94, 0.54, 0.13, 1.0)
    let gray = paint.rgba(0.56, 0.64, 0.73, 1.0)
    let green = paint.rgba(0.12, 0.58, 0.42, 1.0)
    let red = paint.rgba(0.82, 0.25, 0.26, 1.0)
    let purple = paint.rgba(0.49, 0.36, 0.72, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    var labels: [12]chart.Label = zero
    labels[0usize] = chart.Label { text: "Future-state value stream", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "CURRENT", anchor: chart.Coord { x: 18.0, y: 36.0 }, align: .Left }
    labels[2usize] = chart.Label { text: "TARGET", anchor: chart.Coord { x: 18.0, y: 128.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "16h lead / 44% PCE", anchor: chart.Coord { x: 310.0, y: 36.0 }, align: .Right }
    labels[4usize] = chart.Label { text: "10.2h lead / 69% PCE", anchor: chart.Coord { x: 342.0, y: 128.0 }, align: .Right }
    let current_names = [3]str{ "Intake 2h", "Build 5h", "Review 3h" }
    let future_names = [3]str{ "Intake 2h", "Build 4.2h", "Review 2.5h" }
    var i = 0usize
    while i < 3usize {
        labels[5usize + i] = chart.Label { text: current_names[i], anchor: chart.Coord { x: current_boxes[i].x + current_boxes[i].width * 0.5f32, y: current_boxes[i].y + current_boxes[i].height * 0.5f32 + 3.0f32 }, align: .Center }
        labels[8usize + i] = chart.Label { text: future_names[i], anchor: chart.Coord { x: future_boxes[i].x + future_boxes[i].width * 0.5f32, y: future_boxes[i].y + future_boxes[i].height * 0.5f32 + 3.0f32 }, align: .Center }
        i += 1usize
    }
    labels[11usize] = chart.Label { text: "Takt 4h/unit    Green pull / amber FIFO    Red = over takt", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &map.current.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.current.nodes, paint.Brush { Solid: current_blue })
    try chart_scene.append(a, &builder, &map.current.waiting, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.current.process, paint.Brush { Solid: current_blue })
    try chart_scene.append(a, &builder, &map.future.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.future.nodes, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.future.waiting, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.future.process, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.pull, paint.Brush { Solid: green })
    try chart_scene.append(a, &builder, &map.fifo, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.over_takt, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.pacemaker, paint.Brush { Solid: purple })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..5usize], font, 8.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[5usize..11usize], font, 8.0f32, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[11usize..], font, 8.0f32, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &map.current.connectors, gray)
    try chart_svg.append(&writer, &map.current.nodes, current_blue)
    try chart_svg.append(&writer, &map.current.waiting, orange)
    try chart_svg.append(&writer, &map.current.process, current_blue)
    try chart_svg.append(&writer, &map.future.connectors, gray)
    try chart_svg.append(&writer, &map.future.nodes, blue)
    try chart_svg.append(&writer, &map.future.waiting, orange)
    try chart_svg.append(&writer, &map.future.process, blue)
    try chart_svg.append(&writer, &map.pull, green)
    try chart_svg.append(&writer, &map.fifo, orange)
    try chart_svg.append(&writer, &map.over_takt, red)
    try chart_svg.append(&writer, &map.pacemaker, purple)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0f32)
    try chart_svg.append_labels(&writer, labels[1usize..5usize], dark, 8.0f32)
    try chart_svg.append_labels(&writer, labels[5usize..11usize], white, 8.0f32)
    try chart_svg.append_labels(&writer, labels[11usize..], dark, 8.0f32)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_cap_table_waterfall_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/cap_table_waterfall.png"
    let shares = [3]u64{ 6000000u64, 2000000u64, 2000000u64 }
    var before_bars: [3]geometry.Rect = zero
    var after_bars: [5]geometry.Rect = zero
    var before_layers: [3]chart.Layout = zero
    var after_layers: [5]chart.Layout = zero
    var before_fractions: [3]f64 = zero
    var after_fractions: [3]f64 = zero
    var bridge_bars: [4]geometry.Rect = zero
    var bridge_links: [3]chart.Segment = zero
    var work = chart.CapTableWork {
        before_bars: before_bars[..], after_bars: after_bars[..], before_layers: before_layers[..], after_layers: after_layers[..],
        before_fractions: before_fractions[..], after_fractions: after_fractions[..], bridge_bars: bridge_bars[..], bridge_links: bridge_links[..],
    }
    let (cap, cap_error) = chart.cap_table_waterfall(shares[..], 2000000u64, 3000000u64, geometry.rect(22.0, 49.0, 316.0, 20.0), geometry.rect(22.0, 89.0, 316.0, 20.0), geometry.rect(26.0, 134.0, 308.0, 63.0), &work)
    if cap_error != ok || cap.summary.before_shares != 10000000u64 || cap.summary.after_shares != 15000000u64 || cap.after.len != 5usize { ret chart.Invalid }
    let colors = [5]paint.Color{
        paint.rgba(0.10, 0.39, 0.75, 1.0), paint.rgba(0.10, 0.57, 0.50, 1.0), paint.rgba(0.43, 0.36, 0.69, 1.0),
        paint.rgba(0.91, 0.53, 0.15, 1.0), paint.rgba(0.83, 0.27, 0.25, 1.0),
    }
    let gray = paint.rgba(0.56, 0.64, 0.73, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    var labels: [19]chart.Label = zero
    labels[0usize] = chart.Label { text: "Cap table / issuance waterfall", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Before / 10m shares", anchor: chart.Coord { x: 22.0, y: 44.0 }, align: .Left }
    labels[2usize] = chart.Label { text: "After / 15m shares", anchor: chart.Coord { x: 22.0, y: 84.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "Existing holders: 100% to 67%", anchor: chart.Coord { x: 180.0, y: 127.0 }, align: .Center }
    let before_text = [3]str{ "60%", "20%", "20%" }
    let after_text = [5]str{ "40%", "13%", "13%", "13%", "20%" }
    var i = 0usize
    while i < 3usize {
        let bar = cap.before[i].bars[0usize]
        labels[4usize + i] = chart.Label { text: before_text[i], anchor: chart.Coord { x: bar.x + bar.width * 0.5f32, y: bar.y + bar.height * 0.5f32 + 3.0f32 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        let bar = cap.after[i].bars[0usize]
        labels[7usize + i] = chart.Label { text: after_text[i], anchor: chart.Coord { x: bar.x + bar.width * 0.5f32, y: bar.y + bar.height * 0.5f32 + 3.0f32 }, align: .Center }
        i += 1usize
    }
    let bridge_text = [4]str{ "Start", "Pool", "Round", "Retained" }
    i = 0usize
    while i < 4usize {
        let bar = cap.bridge.bars[i]
        labels[12usize + i] = chart.Label { text: bridge_text[i], anchor: chart.Coord { x: bar.x + bar.width * 0.5f32, y: 209.0f32 }, align: .Center }
        i += 1usize
    }
    labels[16usize] = chart.Label { text: "Founders 40%", anchor: chart.Coord { x: 76.0, y: 226.0 }, align: .Center }
    labels[17usize] = chart.Label { text: "Seed 13% / team 13% / pool 13%", anchor: chart.Coord { x: 204.0, y: 226.0 }, align: .Center }
    labels[18usize] = chart.Label { text: "New 20%", anchor: chart.Coord { x: 316.0, y: 226.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < cap.before.len {
        try chart_scene.append(a, &builder, &cap.before[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    i = 0usize
    while i < cap.after.len {
        try chart_scene.append(a, &builder, &cap.after[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    var bridge_links_only = cap.bridge
    bridge_links_only.bars = cap.bridge.bars[..0usize]
    try chart_scene.append(a, &builder, &bridge_links_only, paint.Brush { Solid: gray })
    i = 0usize
    while i < cap.bridge.bars.len {
        var bridge_part = cap.bridge
        bridge_part.bars = cap.bridge.bars[i..i + 1usize]
        bridge_part.segments = cap.bridge.segments[..0usize]
        var ink = colors[0usize]
        if i == 1usize { ink = colors[3usize] }
        if i == 2usize { ink = colors[4usize] }
        try chart_scene.append(a, &builder, &bridge_part, paint.Brush { Solid: ink })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..4usize], font, 8.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..12usize], font, 8.0f32, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[12usize..], font, 8.0f32, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < cap.before.len {
        try chart_svg.append(&writer, &cap.before[i], colors[i])
        i += 1usize
    }
    i = 0usize
    while i < cap.after.len {
        try chart_svg.append(&writer, &cap.after[i], colors[i])
        i += 1usize
    }
    try chart_svg.append(&writer, &bridge_links_only, gray)
    i = 0usize
    while i < cap.bridge.bars.len {
        var bridge_part = cap.bridge
        bridge_part.bars = cap.bridge.bars[i..i + 1usize]
        bridge_part.segments = cap.bridge.segments[..0usize]
        var ink = colors[0usize]
        if i == 1usize { ink = colors[3usize] }
        if i == 2usize { ink = colors[4usize] }
        try chart_svg.append(&writer, &bridge_part, ink)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0f32)
    try chart_svg.append_labels(&writer, labels[1usize..4usize], dark, 8.0f32)
    try chart_svg.append_labels(&writer, labels[4usize..12usize], white, 8.0f32)
    try chart_svg.append_labels(&writer, labels[12usize..], dark, 8.0f32)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_tornado_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/tornado.png"
    let cases = [5]chart.TornadoCase{
        chart.TornadoCase { low_result: 88.0f64, high_result: 120.0f64 },
        chart.TornadoCase { low_result: 55.0f64, high_result: 145.0f64 },
        chart.TornadoCase { low_result: 80.0f64, high_result: 130.0f64 },
        chart.TornadoCase { low_result: 110.0f64, high_result: 90.0f64 },
        chart.TornadoCase { low_result: 90.0f64, high_result: 110.0f64 },
    }
    let names = [5]str{ "Demand", "Unit price", "Input cost", "Tax rate", "Retention" }
    var order: [5]usize = zero
    var low_bars: [5]geometry.Rect = zero
    var high_bars: [5]geometry.Rect = zero
    var baseline_line: [1]chart.Segment = zero
    let (tornado, tornado_error) = chart.tornado_sensitivity(cases[..], 100.0f64, geometry.rect(113.0, 49.0, 222.0, 135.0), order[..], low_bars[..], high_bars[..], baseline_line[..])
    if tornado_error != ok || tornado.order[0usize] != 1usize { ret chart.Invalid }
    let blue = paint.rgba(0.09, 0.40, 0.75, 1.0)
    let orange = paint.rgba(0.92, 0.50, 0.19, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let gray = paint.rgba(0.52, 0.59, 0.69, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    var labels: [13]chart.Label = zero
    labels[0usize] = chart.Label { text: "Tornado / one-at-a-time sensitivity", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Model output by input assumption", anchor: chart.Coord { x: 180.0, y: 39.0 }, align: .Center }
    var i = 0usize
    while i < 5usize {
        labels[2usize + i] = chart.Label { text: names[tornado.order[i]], anchor: chart.Coord { x: 106.0, y: 66.0f32 + f32(i) * 27.0f32 }, align: .Right }
        i += 1usize
    }
    labels[7usize] = chart.Label { text: "55", anchor: chart.Coord { x: 113.0, y: 199.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "100 baseline", anchor: chart.Coord { x: 224.0, y: 199.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "145", anchor: chart.Coord { x: 335.0, y: 199.0 }, align: .Center }
    labels[10usize] = chart.Label { text: "Blue: low input", anchor: chart.Coord { x: 93.0, y: 218.0 }, align: .Center }
    labels[11usize] = chart.Label { text: "Orange: high input", anchor: chart.Coord { x: 259.0, y: 218.0 }, align: .Center }
    labels[12usize] = chart.Label { text: "Sorted by absolute output swing; scenarios stay distinct", anchor: chart.Coord { x: 180.0, y: 233.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, geometry.rect(112.0, 48.0, 224.0, 137.0), paint.Brush { Solid: panel })
    try chart_scene.append(a, &builder, &tornado.low, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &tornado.high, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &tornado.baseline, paint.Brush { Solid: gray })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0f32, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, geometry.rect(112.0, 48.0, 224.0, 137.0), panel, false)
    try chart_svg.append(&writer, &tornado.low, blue)
    try chart_svg.append(&writer, &tornado.high, orange)
    try chart_svg.append(&writer, &tornado.baseline, gray)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0f32)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0f32)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_football_field_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/football_field.png"
    let methods = [4]chart.RangeInterval{
        chart.RangeInterval { row: 0usize, lower: 70.0f64, upper: 115.0f64 },
        chart.RangeInterval { row: 1usize, lower: 100.0f64, upper: 150.0f64 },
        chart.RangeInterval { row: 2usize, lower: 85.0f64, upper: 145.0f64 },
        chart.RangeInterval { row: 3usize, lower: 60.0f64, upper: 95.0f64 },
    }
    let names = [4]str{ "Trading comps", "Deal precedents", "DCF", "52-week range" }
    var bars: [4]geometry.Rect = zero
    var caps: [8]chart.Segment = zero
    var benchmark_line: [1]chart.Segment = zero
    let plot = geometry.rect(114.0, 48.0, 220.0, 136.0)
    let (field, field_error) = chart.football_field(methods[..], 50.0f64, 160.0f64, 100.0f64, plot, bars[..], caps[..], benchmark_line[..])
    if field_error != ok || field.ranges.bars.len != 4usize { ret chart.Invalid }
    let colors = [4]paint.Color{
        paint.rgba(0.10, 0.40, 0.76, 1.0), paint.rgba(0.91, 0.51, 0.19, 1.0),
        paint.rgba(0.12, 0.59, 0.49, 1.0), paint.rgba(0.48, 0.39, 0.70, 1.0),
    }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let red = paint.rgba(0.81, 0.24, 0.25, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    var labels: [10]chart.Label = zero
    labels[0usize] = chart.Label { text: "Valuation football field", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Illustrative implied price / share", anchor: chart.Coord { x: 180.0, y: 39.0 }, align: .Center }
    var i = 0usize
    while i < 4usize {
        labels[2usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: 108.0, y: 69.0f32 + f32(i) * 34.0f32 }, align: .Right }
        i += 1usize
    }
    labels[6usize] = chart.Label { text: "$50", anchor: chart.Coord { x: 114.0, y: 200.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "$100 ref", anchor: chart.Coord { x: 214.0, y: 200.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "$160", anchor: chart.Coord { x: 334.0, y: 200.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "Ranges share one equity / per-share basis", anchor: chart.Coord { x: 180.0, y: 225.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    i = 0usize
    while i < field.ranges.bars.len {
        var row = field.ranges
        row.bars = field.ranges.bars[i..i + 1usize]
        try chart_scene.append(a, &builder, &row, paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &field.caps, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &field.benchmark, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0f32, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    i = 0usize
    while i < field.ranges.bars.len {
        var row = field.ranges
        row.bars = field.ranges.bars[i..i + 1usize]
        try chart_svg.append(&writer, &row, colors[i])
        i += 1usize
    }
    try chart_svg.append(&writer, &field.caps, dark)
    try chart_svg.append(&writer, &field.benchmark, red)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0f32)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0f32)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_yield_curve_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/yield_curve.png"
    let tenors = [5]f64{ 0.25f64, 1.0f64, 2.0f64, 5.0f64, 10.0f64 }
    let current = [5]f64{ 4.8f64, 4.1f64, 3.9f64, 4.0f64, 4.3f64 }
    let prior = [5]f64{ 4.4f64, 4.25f64, 4.2f64, 4.25f64, 4.5f64 }
    var current_points: [5]chart.Coord = zero
    var current_links: [4]chart.Segment = zero
    var prior_points: [5]chart.Coord = zero
    var prior_links: [4]chart.Segment = zero
    let plot = geometry.rect(50.0, 50.0, 280.0, 140.0)
    let (current_curve, current_error) = chart.yield_curve(tenors[..], current[..], 10.0f64, 3.5f64, 5.0f64, plot, current_points[..], current_links[..])
    let (prior_curve, prior_error) = chart.yield_curve(tenors[..], prior[..], 10.0f64, 3.5f64, 5.0f64, plot, prior_points[..], prior_links[..])
    if current_error != ok || prior_error != ok || current_curve.coords.len != 5usize || prior_curve.coords.len != 5usize { ret chart.Invalid }
    let blue = paint.rgba(0.09, 0.40, 0.76, 1.0)
    let orange = paint.rgba(0.91, 0.50, 0.18, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let grid = paint.rgba(0.84, 0.88, 0.93, 1.0)
    let panel = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    var guides: [3]chart.Segment = zero
    var i = 0usize
    while i < 3usize {
        let y = plot.y + f32(i) * plot.height * 0.5f32
        guides[i] = chart.Segment { from: chart.Coord { x: plot.x, y: y }, to: chart.Coord { x: plot.x + plot.width, y: y } }
        i += 1usize
    }
    let guide = chart.Layout { kind: .Rug, coords: zero, segments: guides[..], bars: zero, x_min: 0.0f32, x_max: 10.0f32, y_min: 3.5f32, y_max: 5.0f32 }
    var labels: [11]chart.Label = zero
    labels[0usize] = chart.Label { text: "Yield curve / maturity vs yield", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Illustrative observations, not live Treasury data", anchor: chart.Coord { x: 180.0, y: 39.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "5.0%", anchor: chart.Coord { x: 45.0, y: 53.0 }, align: .Right }
    labels[3usize] = chart.Label { text: "4.25%", anchor: chart.Coord { x: 45.0, y: 123.0 }, align: .Right }
    labels[4usize] = chart.Label { text: "3.5%", anchor: chart.Coord { x: 45.0, y: 193.0 }, align: .Right }
    labels[5usize] = chart.Label { text: "0", anchor: chart.Coord { x: 50.0, y: 206.0 }, align: .Center }
    labels[6usize] = chart.Label { text: "2y", anchor: chart.Coord { x: 106.0, y: 206.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "5y", anchor: chart.Coord { x: 190.0, y: 206.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "10y", anchor: chart.Coord { x: 330.0, y: 206.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "Blue: current scenario", anchor: chart.Coord { x: 103.0, y: 226.0 }, align: .Center }
    labels[10usize] = chart.Label { text: "Orange: prior scenario", anchor: chart.Coord { x: 261.0, y: 226.0 }, align: .Center }
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.append(a, &builder, &guide, paint.Brush { Solid: grid })
    try chart_scene.append(a, &builder, &prior_curve, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &current_curve, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0f32, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.append(&writer, &guide, grid)
    try chart_svg.append(&writer, &prior_curve, orange)
    try chart_svg.append(&writer, &current_curve, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0f32)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0f32)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_monte_carlo_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, cumulative: bool) -> err {
    var path = "docs/chart-previews/monte_carlo_histogram.png"
    if cumulative { path = "docs/chart-previews/monte_carlo_cdf.png" }
    var generator = rand.pcg64(712u64, 3u64)
    var outcomes: [256]f64 = zero
    var i = 0usize
    while i < outcomes.len {
        let first = rand.pcg64_f64(&generator)
        let second = rand.pcg64_f64(&generator)
        let third = rand.pcg64_f64(&generator)
        outcomes[i] = 40.0f64 + 60.0f64 * (first + second + third) / 3.0f64
        i += 1usize
    }
    var sorted: [256]f64 = zero
    var counts: [16]u64 = zero
    var bars: [16]geometry.Rect = zero
    var cdf_segments: [511]chart.Segment = zero
    var threshold_rules: [2]chart.Segment = zero
    let plot = geometry.rect(49.0, 49.0, 282.0, 140.0)
    let (distribution, distribution_error) = chart.monte_carlo_distribution(outcomes[..], 40.0f64, 100.0f64, 70.0f64, plot, plot, sorted[..], counts[..], bars[..], cdf_segments[..], threshold_rules[..])
    if distribution_error != ok || distribution.cdf.segments.len != 511usize { ret chart.Invalid }
    var marks = distribution.histogram
    var rule = distribution.histogram_threshold
    var ink = paint.rgba(0.10, 0.40, 0.76, 1.0)
    if cumulative {
        marks = distribution.cdf
        rule = distribution.cdf_threshold
        ink = paint.rgba(0.11, 0.57, 0.49, 1.0)
    }
    let red = paint.rgba(0.83, 0.27, 0.25, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made_text, text_error) = str.builder(a, 0usize)
    if text_error != ok { ret text_error }
    var probability_text = made_text
    try str.push(&probability_text, "P(outcome <= 70) = ")
    try str.push_f64_fixed(&probability_text, distribution.probability, 2u8)
    let probability_label = str.done(&probability_text)
    var labels: [9]chart.Label = zero
    var title = "Monte Carlo / outcome histogram"
    if cumulative { title = "Monte Carlo / empirical CDF" }
    labels[0usize] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "256 seeded trials / three-uniform toy model", anchor: chart.Coord { x: 180.0, y: 39.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "40", anchor: chart.Coord { x: 49.0, y: 204.0 }, align: .Center }
    labels[3usize] = chart.Label { text: "70", anchor: chart.Coord { x: 190.0, y: 204.0 }, align: .Center }
    labels[4usize] = chart.Label { text: "100", anchor: chart.Coord { x: 331.0, y: 204.0 }, align: .Center }
    labels[5usize] = chart.Label { text: probability_label, anchor: chart.Coord { x: 180.0, y: 225.0 }, align: .Center }
    labels[6usize] = chart.Label { text: "1.0", anchor: chart.Coord { x: 44.0, y: 54.0 }, align: .Right }
    labels[7usize] = chart.Label { text: "0.5", anchor: chart.Coord { x: 44.0, y: 124.0 }, align: .Right }
    labels[8usize] = chart.Label { text: "0", anchor: chart.Coord { x: 44.0, y: 193.0 }, align: .Right }
    let (made, builder_error) = scene.builder(a, 1024usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &rule, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0f32, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..6usize], font, 8.0f32, paint.Brush { Solid: dark })
    if cumulative { try chart_scene.append_labels(a, &builder, labels[6usize..], font, 8.0f32, paint.Brush { Solid: dark }) }
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.append(&writer, &rule, red)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0f32)
    try chart_svg.append_labels(&writer, labels[1usize..6usize], dark, 8.0f32)
    if cumulative { try chart_svg.append_labels(&writer, labels[6usize..], dark, 8.0f32) }
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_missing_data_scatter_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/missing_data_scatter.png"
    let x = [10]f32{ 1.0, 2.0, 999.0, 4.0, 5.0, 6.0, 7.0, 8.0, 999.0, 10.0 }
    let y = [10]f32{ 2.0, 3.0, 4.0, 5.0, 6.0, 999.0, 6.5, 8.0, 9.0, 9.2 }
    let x_present = [10]bool{ true, true, false, true, true, true, true, true, false, true }
    let y_present = [10]bool{ true, true, true, true, true, false, true, true, true, true }
    let plot = geometry.rect(47.0, 56.0, 282.0, 133.0)
    var points: [7]chart.Coord = zero
    var row_ids: [7]usize = zero
    let (scatter, scatter_error) = chart.masked_scatter(x[..], y[..], x_present[..], y_present[..], plot, 0.0, 11.0, 0.0, 10.0, points[..], row_ids[..])
    if scatter_error != ok || scatter.omitted != 3usize || scatter.marks.coords.len != 7usize || row_ids[6usize] != 9usize { ret chart.Invalid }
    var grid_segments: [6]chart.Segment = zero
    let x_fractions = [3]f32{ 0.0, 5.0 / 11.0, 10.0 / 11.0 }
    var i = 0usize
    while i < 3usize {
        let xx = plot.x + plot.width * x_fractions[i]
        grid_segments[i] = chart.Segment { from: chart.Coord { x: xx, y: plot.y }, to: chart.Coord { x: xx, y: plot.y + plot.height } }
        let yy = plot.y + f32(i) * plot.height * 0.5
        grid_segments[3usize + i] = chart.Segment { from: chart.Coord { x: plot.x, y: yy }, to: chart.Coord { x: plot.x + plot.width, y: yy } }
        i += 1usize
    }
    let guide = chart.Layout { kind: .Rug, coords: zero, segments: grid_segments[..], bars: zero, x_min: 0.0, x_max: 11.0, y_min: 0.0, y_max: 10.0 }
    let labels = [9]chart.Label{
        chart.Label { text: "Scatter with explicit missing data", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "7 complete pairs / 3 rows omitted", anchor: chart.Coord { x: 180.0, y: 40.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: plot.x, y: 206.0 }, align: .Center },
        chart.Label { text: "5", anchor: chart.Coord { x: plot.x + plot.width * 5.0 / 11.0, y: 206.0 }, align: .Center },
        chart.Label { text: "10", anchor: chart.Coord { x: plot.x + plot.width * 10.0 / 11.0, y: 206.0 }, align: .Center },
        chart.Label { text: "10", anchor: chart.Coord { x: 40.0, y: plot.y + 3.0 }, align: .Right },
        chart.Label { text: "5", anchor: chart.Coord { x: 40.0, y: plot.y + plot.height * 0.5 + 3.0 }, align: .Right },
        chart.Label { text: "0", anchor: chart.Coord { x: 40.0, y: plot.y + plot.height + 3.0 }, align: .Right },
        chart.Label { text: "Source rows 3, 6, 9 omitted; IDs retained for selection", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center },
    }
    let blue = paint.rgba(0.13, 0.43, 0.78, 1.0)
    let grid = paint.rgba(0.83, 0.87, 0.92, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let orange = paint.rgba(0.80, 0.39, 0.20, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 90usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.append(a, &builder, &guide, paint.Brush { Solid: grid })
    try chart_scene.append(a, &builder, &scatter.marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..8usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 7.0, paint.Brush { Solid: orange })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.append(&writer, &guide, grid)
    try chart_svg.append(&writer, &scatter.marks, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[2usize..8usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[8usize..], orange, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_clipped_annotation_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/clipped_annotation.png"
    let plot = geometry.rect(45.0, 58.0, 270.0, 130.0)
    let x = [6]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0 }
    let y = [6]f32{ 2.0, 3.0, 2.5, 4.0, 3.3, 6.0 }
    var points: [6]chart.Coord = zero
    var segments: [5]chart.Segment = zero
    var bars: [1]geometry.Rect = zero
    var spec = chart.spec(.PointLine, plot, x[..], y[..])
    let (marks, marks_error) = chart.layout(&spec, points[..], segments[..], bars[..0usize])
    if marks_error != ok { ret marks_error }
    var marker = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: 294.0, y: 93.0 }, to: chart.Coord { x: 294.0, y: 124.0 } } }
    let marker_marks = chart.Layout { kind: .Rug, coords: zero, segments: marker[..], bars: zero, x_min: 0.0, x_max: 5.0, y_min: 0.0, y_max: 6.0 }
    let heading = [2]chart.Label{
        chart.Label { text: "Annotations clipped to the plot", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "Panel bounds crop marks and annotation text", anchor: chart.Coord { x: 180.0, y: 41.0 }, align: .Center },
    }
    let note = [1]chart.Label{ chart.Label { text: "Peak exceeds upper limit", anchor: chart.Coord { x: 267.0, y: 91.0 }, align: .Left } }
    let footer = [1]chart.Label{ chart.Label { text: "The title and axis labels remain outside the clip", anchor: chart.Coord { x: 180.0, y: 224.0 }, align: .Center } }
    let blue = paint.rgba(0.13, 0.43, 0.78, 1.0)
    let red = paint.rgba(0.83, 0.25, 0.22, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.begin_clip(&builder, plot)
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &marker_marks, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, note[..], font, 9.0, paint.Brush { Solid: red })
    try chart_scene.end_clip(&builder)
    try chart_scene.append_labels(a, &builder, heading[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, footer[..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.begin_clip(&writer, plot, "plot-window")
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append(&writer, &marker_marks, red)
    try chart_svg.append_labels(&writer, note[..], red, 9.0)
    try chart_svg.end_clip(&writer)
    try chart_svg.append_labels(&writer, heading[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, heading[1usize..], dark, 8.0)
    try chart_svg.append_labels(&writer, footer[..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_plot_grid_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/plot_grid.png"
    let columns = [2]f32{ 1.25, 1.0 }
    let rows = [2]f32{ 1.0, 1.0 }
    var panels: [4]geometry.Rect = zero
    let (placed, placement_error) = chart.plot_grid(geometry.rect(18.0, 40.0, 324.0, 184.0), columns[..], rows[..], 10.0, 10.0, panels[..])
    if placement_error != ok { ret placement_error }
    let kinds = [4]chart.Kind{ .Line, .Bar, .Scatter, .Area }
    let names = [4]str{ "A  Line", "B  Bars", "C  Points", "D  Area" }
    let colors = [4]paint.Color{
        paint.rgba(0.12, 0.42, 0.76, 1.0), paint.rgba(0.15, 0.63, 0.50, 1.0),
        paint.rgba(0.80, 0.36, 0.24, 1.0), paint.rgba(0.50, 0.38, 0.78, 1.0),
    }
    let line_x = [4]f32{ 0.0, 1.0, 2.0, 3.0 }
    let line_y = [4]f32{ 2.0, 5.0, 3.0, 6.0 }
    let bar_x = [4]f32{ 1.0, 2.0, 3.0, 4.0 }
    let bar_y = [4]f32{ 2.0, 3.0, 5.0, 4.0 }
    let scatter_x = [4]f32{ 10.0, 20.0, 30.0, 40.0 }
    let scatter_y = [4]f32{ 2.0, 5.0, 3.0, 7.0 }
    let area_x = [4]f32{ 0.0, 1.0, 2.0, 3.0 }
    let area_y = [4]f32{ 0.0, 2.0, 4.0, 3.0 }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let panel_fill = paint.rgba(0.94, 0.96, 0.98, 1.0)
    let axis = paint.rgba(0.56, 0.62, 0.70, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    let heading = [1]chart.Label{ chart.Label { text: "Weighted plot grid / independent scales", anchor: chart.Coord { x: 180.0, y: 25.0 }, align: .Center } }
    try chart_scene.append_labels(a, &builder, heading[..], font, 11.0, paint.Brush { Solid: dark })
    var i = 0usize
    while i < placed.len {
        let cell = placed[i]
        let plot = geometry.rect(cell.x + 13.0, cell.y + 25.0, cell.width - 26.0, cell.height - 34.0)
        try fill(&builder, cell, paint.Brush { Solid: panel_fill })
        try fill(&builder, plot, paint.Brush { Solid: white })
        try fill(&builder, geometry.rect(plot.x, plot.y + plot.height, plot.width, 1.0), paint.Brush { Solid: axis })
        var xx: []const f32 = line_x[..]
        var yy: []const f32 = line_y[..]
        if i == 1usize {
            xx = bar_x[..]
            yy = bar_y[..]
        }
        if i == 2usize {
            xx = scatter_x[..]
            yy = scatter_y[..]
        }
        if i == 3usize {
            xx = area_x[..]
            yy = area_y[..]
        }
        var point_storage: [8]chart.Coord = zero
        var line_storage: [4]chart.Segment = zero
        var bar_storage: [4]geometry.Rect = zero
        let spec = chart.spec(kinds[i], plot, xx, yy)
        let (marks, marks_error) = chart.layout(&spec, point_storage[..], line_storage[..], bar_storage[..])
        if marks_error != ok { ret marks_error }
        try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: colors[i] })
        let title = [1]chart.Label{ chart.Label { text: names[i], anchor: chart.Coord { x: cell.x + cell.width / 2.0, y: cell.y + 17.0 }, align: .Center } }
        try chart_scene.append_labels(a, &builder, title[..], font, 9.0, paint.Brush { Solid: dark })
        i += 1usize
    }
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_labels(&writer, heading[..], dark, 11.0)
    i = 0usize
    while i < placed.len {
        let cell = placed[i]
        let plot = geometry.rect(cell.x + 13.0, cell.y + 25.0, cell.width - 26.0, cell.height - 34.0)
        try chart_svg.rect(&writer, cell, panel_fill, false)
        try chart_svg.rect(&writer, plot, white, false)
        try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + plot.height, plot.width, 1.0), axis, false)
        var xx: []const f32 = line_x[..]
        var yy: []const f32 = line_y[..]
        if i == 1usize {
            xx = bar_x[..]
            yy = bar_y[..]
        }
        if i == 2usize {
            xx = scatter_x[..]
            yy = scatter_y[..]
        }
        if i == 3usize {
            xx = area_x[..]
            yy = area_y[..]
        }
        var point_storage: [8]chart.Coord = zero
        var line_storage: [4]chart.Segment = zero
        var bar_storage: [4]geometry.Rect = zero
        let spec = chart.spec(kinds[i], plot, xx, yy)
        let (marks, marks_error) = chart.layout(&spec, point_storage[..], line_storage[..], bar_storage[..])
        if marks_error != ok { ret marks_error }
        try chart_svg.append(&writer, &marks, colors[i])
        let title = [1]chart.Label{ chart.Label { text: names[i], anchor: chart.Coord { x: cell.x + cell.width / 2.0, y: cell.y + 17.0 }, align: .Center } }
        try chart_svg.append_labels(&writer, title[..], dark, 9.0)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_shared_guide_facets_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/shared_guide_facets.png"
    var panels: [4]geometry.Rect = zero
    let (placed, panel_error) = chart.facet_grid(geometry.rect(40.0, 50.0, 278.0, 134.0), 2usize, 4usize, 22.0, panels[..])
    if panel_error != ok { ret panel_error }
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_ticks: [3]chart.Tick = zero
    var y_ticks: [3]chart.Tick = zero
    let (_, x_error) = chart.ticks(linear, 0.0, 10.0, x_ticks[..])
    let (_, y_error) = chart.ticks(linear, 0.0, 10.0, y_ticks[..])
    if x_error != ok || y_error != ok { ret chart.Invalid }
    let tick_text = [3]str{ "0", "5", "10" }
    var labels: [12]chart.Label = zero
    let (outer, label_error) = chart.shared_facet_guide_labels(placed, 2usize, x_ticks[..], tick_text[..], y_ticks[..], tick_text[..], 8.0, labels[..])
    if label_error != ok { ret label_error }
    let strip_names = [4]str{ "North", "South", "East", "West" }
    var strips: [4]chart.Label = zero
    var i = 0usize
    while i < placed.len {
        strips[i] = chart.Label { text: strip_names[i], anchor: chart.Coord { x: placed[i].x + placed[i].width * 0.5, y: placed[i].y - 7.0 }, align: .Center }
        i += 1usize
    }
    let heading = [1]chart.Label{ chart.Label { text: "Shared guides / four facets", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center } }
    let footer = [1]chart.Label{ chart.Label { text: "x labels on bottom / y labels on left", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center } }
    let x = [3]f32{ 1.0, 5.0, 9.0 }
    let north = [3]f32{ 2.0, 6.0, 8.0 }
    let south = [3]f32{ 7.0, 4.0, 6.0 }
    let east = [3]f32{ 3.0, 8.0, 5.0 }
    let west = [3]f32{ 5.0, 2.0, 9.0 }
    let limits = [2]f32{ 0.0, 10.0 }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let grid = paint.rgba(0.86, 0.89, 0.93, 1.0)
    let axis = paint.rgba(0.42, 0.48, 0.57, 1.0)
    let ink = paint.rgba(0.12, 0.44, 0.78, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 160usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < placed.len {
        try fill(&builder, placed[i], paint.Brush { Solid: panel })
        try chart_scene.append_guides(&builder, placed[i], x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: axis })
        var yy: []const f32 = north[..]
        if i == 1usize { yy = south[..] }
        if i == 2usize { yy = east[..] }
        if i == 3usize { yy = west[..] }
        var points: [3]chart.Coord = zero
        var lines: [2]chart.Segment = zero
        var bars: [1]geometry.Rect = zero
        let spec = chart.spec(.PointLine, placed[i], x[..], yy)
        let (marks, marks_error) = chart.layout_with_limits(&spec, points[..], lines[..], bars[..0usize], limits[..], limits[..])
        if marks_error != ok { ret marks_error }
        try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, outer, font, 8.0, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, strips[..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[..], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, footer[..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < placed.len {
        try chart_svg.rect(&writer, placed[i], panel, false)
        try chart_svg.append_guides(&writer, placed[i], x_ticks[..], y_ticks[..], grid, axis)
        var yy: []const f32 = north[..]
        if i == 1usize { yy = south[..] }
        if i == 2usize { yy = east[..] }
        if i == 3usize { yy = west[..] }
        var points: [3]chart.Coord = zero
        var lines: [2]chart.Segment = zero
        var bars: [1]geometry.Rect = zero
        let spec = chart.spec(.PointLine, placed[i], x[..], yy)
        let (marks, marks_error) = chart.layout_with_limits(&spec, points[..], lines[..], bars[..0usize], limits[..], limits[..])
        if marks_error != ok { ret marks_error }
        try chart_svg.append(&writer, &marks, ink)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, outer, axis, 8.0)
    try chart_svg.append_labels(&writer, strips[..], dark, 8.0)
    try chart_svg.append_labels(&writer, heading[..], dark, 12.0)
    try chart_svg.append_labels(&writer, footer[..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_interactive_selection_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/interactive_selection.png"
    let plot = geometry.rect(43.0, 55.0, 284.0, 133.0)
    let x = [9]f32{ 0.8, 2.0, 999.0, 3.5, 5.0, 6.2, 7.4, 8.5, 9.3 }
    let y = [9]f32{ 1.5, 3.2, 4.0, 5.3, 5.0, 999.0, 7.8, 6.7, 9.2 }
    let x_present = [9]bool{ true, true, false, true, true, true, true, true, true }
    let y_present = [9]bool{ true, true, true, true, true, false, true, true, true }
    var points: [7]chart.Coord = zero
    var row_ids: [7]usize = zero
    let (scatter, scatter_error) = chart.masked_scatter(x[..], y[..], x_present[..], y_present[..], plot, 0.0, 10.0, 0.0, 10.0, points[..], row_ids[..])
    if scatter_error != ok || scatter.marks.coords.len != 7usize || scatter.omitted != 2usize { ret chart.Invalid }
    let picked_point = scatter.marks.coords[5usize]
    let (hit, found, hit_error) = chart.hit_scatter(&scatter.marks, scatter.row_ids, chart.Coord { x: picked_point.x + 3.0, y: picked_point.y - 2.0 }, 8.0)
    if hit_error != ok || !found || hit.mark_index != 5usize || hit.source_row != 7usize { ret chart.Invalid }
    var outline_storage: [1]geometry.Rect = zero
    let (outline, outline_error) = chart.selected_point_outline(&scatter.marks, hit.mark_index, 5.0, outline_storage[..])
    if outline_error != ok { ret outline_error }
    let (made_status, status_error) = str.builder(a, 0usize)
    if status_error != ok { ret status_error }
    var status = made_status
    try str.push(&status, "Selected source row ")
    try str.push_usize(&status, hit.source_row + 1usize)
    try str.push(&status, " / 7 complete, 2 omitted")
    let selected_text = str.done(&status)
    let heading = [2]chart.Label{
        chart.Label { text: "Interactive selection / stable row IDs", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "Click or focus a point in the SVG companion", anchor: chart.Coord { x: 180.0, y: 40.0 }, align: .Center },
    }
    let footer = [2]chart.Label{
        chart.Label { text: selected_text, anchor: chart.Coord { x: 180.0, y: 209.0 }, align: .Center },
        chart.Label { text: "PNG captures one pointer pick; SVG points remain selectable", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center },
    }
    let svg_footer = [2]chart.Label{
        chart.Label { text: "Select any source row via its point link", anchor: chart.Coord { x: 180.0, y: 209.0 }, align: .Center },
        chart.Label { text: "Click or keyboard focus reveals the orange outline", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center },
    }
    let descriptions = [7]str{
        "Source row 1, x 0.8, y 1.5", "Source row 2, x 2.0, y 3.2",
        "Source row 4, x 3.5, y 5.3", "Source row 5, x 5.0, y 5.0",
        "Source row 7, x 7.4, y 7.8", "Source row 8, x 8.5, y 6.7",
        "Source row 9, x 9.3, y 9.2",
    }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let grid = paint.rgba(0.85, 0.89, 0.93, 1.0)
    let axis = paint.rgba(0.43, 0.49, 0.58, 1.0)
    let blue = paint.rgba(0.12, 0.44, 0.78, 1.0)
    let orange = paint.rgba(0.89, 0.30, 0.13, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_ticks: [3]chart.Tick = zero
    var y_ticks: [3]chart.Tick = zero
    let (_, x_error) = chart.ticks(linear, 0.0, 10.0, x_ticks[..])
    let (_, y_error) = chart.ticks(linear, 0.0, 10.0, y_ticks[..])
    if x_error != ok || y_error != ok { ret chart.Invalid }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 100usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: axis })
    try chart_scene.append(a, &builder, &scatter.marks, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &outline, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, heading[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, footer[..1usize], font, 8.0, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, footer[1usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, axis)
    try chart_svg.append_selectable_scatter(&writer, &scatter.marks, scatter.row_ids, descriptions[..], blue, orange, "point")
    try chart_svg.append_labels(&writer, heading[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, heading[1usize..], dark, 8.0)
    try chart_svg.append_labels(&writer, svg_footer[..1usize], orange, 8.0)
    try chart_svg.append_labels(&writer, svg_footer[1usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_accessible_palette_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/accessible_palette.png"
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let night = paint.rgba(0.11, 0.13, 0.17, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let pale = paint.rgba(0.86, 0.89, 0.93, 1.0)
    let border = paint.rgba(0.80, 0.84, 0.89, 1.0)
    var light_store: [6]paint.Color = zero
    var night_store: [6]paint.Color = zero
    let (light, light_error) = chart.accessible_palette(white, light_store[..])
    if light_error != ok { ret light_error }
    let (night_colors, night_error) = chart.accessible_palette(night, night_store[..])
    if night_error != ok { ret night_error }
    let x = [5]f32{ 0.0, 1.0, 2.0, 3.0, 4.0 }
    let y = [30]f32{
        10.6, 11.2, 10.9, 11.6, 11.3,
        8.4, 8.9, 9.3, 8.8, 9.4,
        6.3, 6.0, 6.8, 7.1, 6.7,
        4.6, 4.2, 4.0, 4.7, 5.0,
        2.4, 2.9, 2.6, 2.2, 2.8,
        0.5, 0.9, 1.3, 0.8, 0.4,
    }
    let names = [6]str{ "S1", "S2", "S3", "S4", "S5", "S6" }
    let x_limits = [2]f32{ 0.0, 4.0 }
    let y_limits = [2]f32{ 0.0, 12.0 }
    let panels = [2]geometry.Rect{ geometry.rect(12.0, 42.0, 164.0, 186.0), geometry.rect(184.0, 42.0, 164.0, 186.0) }
    var points: [60]chart.Coord = zero
    var lines: [48]chart.Segment = zero
    var marks: [12]chart.Layout = zero
    var labels: [12]chart.Label = zero
    var p = 0usize
    while p < 2usize {
        let plot = geometry.rect(panels[p].x + 12.0, panels[p].y + 12.0, panels[p].width - 44.0, panels[p].height - 40.0)
        var s = 0usize
        while s < 6usize {
            let k = p * 6usize + s
            let spec = chart.spec(.PointLine, plot, x[..], y[s * 5usize..s * 5usize + 5usize])
            let (laid, marks_error) = chart.layout_with_limits(&spec, points[k * 5usize..k * 5usize + 5usize], lines[k * 4usize..k * 4usize + 4usize], zero, x_limits[..], y_limits[..])
            if marks_error != ok { ret marks_error }
            marks[k] = laid
            let last = laid.coords[4usize]
            labels[k] = chart.Label { text: names[s], anchor: chart.Coord { x: last.x + 7.0, y: last.y + 3.0 }, align: .Left }
            s += 1usize
        }
        p += 1usize
    }
    let heading = [2]chart.Label{
        chart.Label { text: "Accessible series palette", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center },
        chart.Label { text: "Every color clears 4.5:1 on its background; labels carry identity", anchor: chart.Coord { x: 180.0, y: 32.0 }, align: .Center },
    }
    let captions = [2]chart.Label{
        chart.Label { text: "White background", anchor: chart.Coord { x: 94.0, y: 219.0 }, align: .Center },
        chart.Label { text: "Dark background", anchor: chart.Coord { x: 266.0, y: 219.0 }, align: .Center },
    }
    let inner = geometry.rect(panels[0usize].x + 1.0, panels[0usize].y + 1.0, panels[0usize].width - 2.0, panels[0usize].height - 2.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, panels[0usize], paint.Brush { Solid: border })
    try fill(&builder, inner, paint.Brush { Solid: white })
    try fill(&builder, panels[1usize], paint.Brush { Solid: night })
    var k = 0usize
    while k < 12usize {
        var ink = night
        if k < 6usize { ink = light[k] } else { ink = night_colors[k - 6usize] }
        try chart_scene.append(a, &builder, &marks[k], paint.Brush { Solid: ink })
        try chart_scene.append_labels(a, &builder, labels[k..k + 1usize], font, 8.0, paint.Brush { Solid: ink })
        k += 1usize
    }
    try chart_scene.append_labels(a, &builder, heading[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[1usize..], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, captions[..1usize], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, captions[1usize..], font, 7.0, paint.Brush { Solid: pale })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, panels[0usize], border, false)
    try chart_svg.rect(&writer, inner, white, false)
    try chart_svg.rect(&writer, panels[1usize], night, false)
    k = 0usize
    while k < 12usize {
        var ink = night
        if k < 6usize { ink = light[k] } else { ink = night_colors[k - 6usize] }
        try chart_svg.append(&writer, &marks[k], ink)
        try chart_svg.append_labels(&writer, labels[k..k + 1usize], ink, 8.0)
        k += 1usize
    }
    try chart_svg.append_labels(&writer, heading[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, heading[1usize..], dark, 7.0)
    try chart_svg.append_labels(&writer, captions[..1usize], dark, 7.0)
    try chart_svg.append_labels(&writer, captions[1usize..], pale, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_gradient_font_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/gradient_font.png"
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let axis = paint.rgba(0.56, 0.62, 0.70, 1.0)
    let plot = geometry.rect(36.0, 44.0, 296.0, 150.0)
    let x = [6]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0 }
    let revenue = [6]f32{ 4.2, 5.1, 6.4, 5.8, 7.6, 8.9 }
    let margin = [6]f32{ 2.0, 2.6, 3.9, 3.1, 4.8, 6.2 }
    let limits = [2]f32{ 0.0, 10.0 }
    var bar_storage: [6]geometry.Rect = zero
    var line_storage: [5]chart.Segment = zero
    var point_storage: [6]chart.Coord = zero
    let bar_spec = chart.spec(.Bar, plot, x[..], revenue[..])
    let (bars, bars_error) = chart.layout_with_limits(&bar_spec, zero, zero, bar_storage[..], zero, limits[..])
    if bars_error != ok { ret bars_error }
    let line_spec = chart.spec(.PointLine, plot, x[..], margin[..])
    let x_limits = [2]f32{ bars.x_min, bars.x_max }
    let (trend, trend_error) = chart.layout_with_limits(&line_spec, point_storage[..], line_storage[..], zero, x_limits[..], limits[..])
    if trend_error != ok { ret trend_error }
    let column_stops = [2]paint.Stop{ paint.Stop { offset: 0.0, color: paint.rgba(0.05, 0.27, 0.55, 1.0) }, paint.Stop { offset: 1.0, color: paint.rgba(0.45, 0.72, 0.95, 1.0) } }
    let trend_stops = [3]paint.Stop{ paint.Stop { offset: 0.0, color: paint.rgba(0.95, 0.60, 0.10, 1.0) }, paint.Stop { offset: 0.5, color: paint.rgba(0.90, 0.35, 0.15, 1.0) }, paint.Stop { offset: 1.0, color: paint.rgba(0.70, 0.10, 0.25, 1.0) } }
    let columns = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 0.0, y: plot.y + plot.height }, end: geometry.Point { x: 0.0, y: plot.y }, stops: column_stops[..] } }
    let trend_brush = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: plot.x, y: 0.0 }, end: geometry.Point { x: plot.x + plot.width, y: 0.0 }, stops: trend_stops[..] } }
    let names = [6]str{ "Q1", "Q2", "Q3", "Q4", "Q5", "Q6" }
    var categories: [6]chart.Label = zero
    var i = 0usize
    while i < bars.bars.len {
        let bar = bars.bars[i]
        categories[i] = chart.Label { text: names[i], anchor: chart.Coord { x: bar.x + bar.width / 2.0, y: plot.y + plot.height + 14.0 }, align: .Center }
        i += 1usize
    }
    let heading = [2]chart.Label{
        chart.Label { text: "Gradient fills, embedded face", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "Columns fade upward; the margin line runs amber to crimson", anchor: chart.Coord { x: 180.0, y: 35.0 }, align: .Center },
    }
    let axis_rect = geometry.rect(plot.x, plot.y + plot.height, plot.width, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &bars, columns)
    try chart_scene.append(a, &builder, &trend, trend_brush)
    try fill(&builder, axis_rect, paint.Brush { Solid: axis })
    try chart_scene.append_labels(a, &builder, categories[..], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[1usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.embed_font(&writer, "Montserrat", font_bytes)
    try chart_svg.append_brush(&writer, &bars, columns, "columns")
    try chart_svg.append_brush(&writer, &trend, trend_brush, "trend")
    try chart_svg.rect(&writer, axis_rect, axis, false)
    try chart_svg.append_labels_in(&writer, categories[..], dark, 9.0, "Montserrat")
    try chart_svg.append_labels_in(&writer, heading[..1usize], dark, 12.0, "Montserrat")
    try chart_svg.append_labels_in(&writer, heading[1usize..], dark, 7.0, "Montserrat")
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn one_decimal(a: *mem.Arena, prefix: str, value: f64, suffix: str) -> (str, err) {
    let tenths = u64(value * 10.0f64 + 0.5f64)
    let (made, builder_error) = str.builder(a, prefix.len + suffix.len + 24usize)
    if builder_error != ok { ret (zero, builder_error) }
    var built = made
    try str.push(&built, prefix)
    try str.push_usize(&built, usize(tenths / 10u64))
    try str.push(&built, ".")
    try str.push_usize(&built, usize(tenths % 10u64))
    try str.push(&built, suffix)
    ret (str.done(&built), ok)
}

fn render_color_vision_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/color_vision.png"
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    var palette_store: [6]paint.Color = zero
    let (palette, palette_error) = chart.accessible_palette(white, palette_store[..])
    if palette_error != ok { ret palette_error }
    let visions = [4]chart.ColorVision{ .Typical, .Protan, .Deutan, .Tritan }
    let names = [4]str{ "Typical", "Protanopia", "Deuteranopia", "Tritanopia" }
    let series = [6]str{ "S1", "S2", "S3", "S4", "S5", "S6" }
    var swatches: [24]geometry.Rect = zero
    var inks: [24]paint.Color = zero
    var outlines: [8]geometry.Rect = zero
    var labels: [12]chart.Label = zero
    var row = 0usize
    while row < 4usize {
        let y = 52.0 + f32(row) * 44.0
        let (gap, gap_error) = chart.palette_separation(palette, visions[row], 1.0)
        if gap_error != ok { ret gap_error }
        var i = 0usize
        while i < 6usize {
            let (seen, seen_error) = chart.simulate_color_vision(palette[i], visions[row], 1.0)
            if seen_error != ok { ret seen_error }
            swatches[row * 6usize + i] = geometry.rect(96.0 + f32(i) * 30.0, y, 26.0, 26.0)
            inks[row * 6usize + i] = seen
            i += 1usize
        }
        let first = swatches[row * 6usize + gap.first]
        let second = swatches[row * 6usize + gap.second]
        outlines[row * 2usize] = geometry.rect(first.x - 3.0, first.y - 3.0, first.width + 6.0, first.height + 6.0)
        outlines[row * 2usize + 1usize] = geometry.rect(second.x - 3.0, second.y - 3.0, second.width + 6.0, second.height + 6.0)
        let (gap_text, text_error) = one_decimal(a, "min ", gap.difference, "")
        if text_error != ok { ret text_error }
        let (made_pair, pair_error) = str.builder(a, 16usize)
        if pair_error != ok { ret pair_error }
        var pair_text = made_pair
        try str.push(&pair_text, series[gap.first])
        try str.push(&pair_text, " vs ")
        try str.push(&pair_text, series[gap.second])
        labels[row * 3usize] = chart.Label { text: names[row], anchor: chart.Coord { x: 14.0, y: y + 17.0 }, align: .Left }
        labels[row * 3usize + 1usize] = chart.Label { text: gap_text, anchor: chart.Coord { x: 282.0, y: y + 11.0 }, align: .Left }
        labels[row * 3usize + 2usize] = chart.Label { text: str.done(&pair_text), anchor: chart.Coord { x: 282.0, y: y + 22.0 }, align: .Left }
        row += 1usize
    }
    let heading = [2]chart.Label{
        chart.Label { text: "Palette under simulated colour vision", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "Outlined: the closest pair; min is its CIEDE2000 difference", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    var k = 0usize
    while k < 8usize {
        try fill(&builder, outlines[k], paint.Brush { Solid: dark })
        try fill(&builder, geometry.rect(outlines[k].x + 2.0, outlines[k].y + 2.0, outlines[k].width - 4.0, outlines[k].height - 4.0), paint.Brush { Solid: white })
        k += 1usize
    }
    k = 0usize
    while k < 24usize {
        try fill(&builder, swatches[k], paint.Brush { Solid: inks[k] })
        k += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[1usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    k = 0usize
    while k < 8usize {
        try chart_svg.rect(&writer, outlines[k], dark, false)
        try chart_svg.rect(&writer, geometry.rect(outlines[k].x + 2.0, outlines[k].y + 2.0, outlines[k].width - 4.0, outlines[k].height - 4.0), white, false)
        k += 1usize
    }
    k = 0usize
    while k < 24usize {
        try chart_svg.rect(&writer, swatches[k], inks[k], false)
        k += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..], dark, 8.0)
    try chart_svg.append_labels(&writer, heading[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, heading[1usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_label_placement_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/label_placement.png"
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let blue = paint.rgba(0.0, 0.45, 0.70, 1.0)
    let muted = paint.rgba(0.62, 0.67, 0.74, 1.0)
    let panel = paint.rgba(0.95, 0.96, 0.98, 1.0)
    // Ordered by population, so the larger city keeps its label in a cluster.
    let names = [25]str{ "London", "Berlin", "Madrid", "Rome", "Paris", "Vienna", "Hamburg", "Warsaw", "Barcelona", "Milan", "Prague", "Stockholm", "Cologne", "Amsterdam", "Oslo", "Copenhagen", "Dublin", "Frankfurt", "Rotterdam", "Lisbon", "Antwerp", "Zurich", "Brussels", "Geneva", "Luxembourg" }
    let lon = [25]f32{ -0.13, 13.40, -3.70, 12.50, 2.35, 16.37, 9.99, 21.01, 2.17, 9.19, 14.42, 18.07, 6.96, 4.90, 10.75, 12.57, -6.26, 8.68, 4.48, -9.14, 4.40, 8.54, 4.35, 6.14, 6.13 }
    let lat = [25]f32{ 51.51, 52.52, 40.42, 41.90, 48.86, 48.21, 53.55, 52.23, 41.39, 45.46, 50.08, 59.33, 50.94, 52.37, 59.91, 55.68, 53.35, 50.11, 51.92, 38.72, 51.22, 47.37, 50.85, 46.20, 49.61 }
    let plot = geometry.rect(24.0, 44.0, 312.0, 166.0)
    let x_limits = [2]f32{ -11.0, 24.0 }
    let y_limits = [2]f32{ 37.0, 61.0 }
    var coord_storage: [25]chart.Coord = zero
    let spec = chart.spec(.Scatter, plot, lon[..], lat[..])
    let (cities, cities_error) = chart.layout_with_limits(&spec, coord_storage[..], zero, zero, x_limits[..], y_limits[..])
    if cities_error != ok { ret cities_error }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let fonts = [1]text_layout.FontChoice{ text_layout.FontChoice { font: font, size: 7.0 } }
    let style = text_layout.Style { fonts: fonts[..], language: "", line_height: 0.0 }
    let options = text_layout.Options { width: 0.0, max_lines: 1u32, align: .Start, wrap: .None, ellipsis: "", notdef: true }
    var widths: [25]f32 = zero
    var i = 0usize
    while i < names.len {
        let (measured, measure_error) = text_layout.layout(a, names[i], style, options)
        if measure_error != ok { ret measure_error }
        widths[i] = measured.bounds.width
        i += 1usize
    }
    var placements: [25]chart.LabelPlacement = zero
    let (placed, placed_error) = chart.place_point_labels(cities.coords, names[..], widths[..], 8.0, 6.5, plot, 2.5, 2.0, placements[..])
    if placed_error != ok { ret placed_error }
    var shown: [25]chart.Label = zero
    var hidden_points: [25]chart.Coord = zero
    var shown_count = 0usize
    var hidden_count = 0usize
    i = 0usize
    while i < placed.labels.len {
        if placed.labels[i].placed {
            shown[shown_count] = placed.labels[i].label
            shown_count += 1usize
        } else {
            hidden_points[hidden_count] = cities.coords[i]
            hidden_count += 1usize
        }
        i += 1usize
    }
    var hidden = cities
    hidden.coords = hidden_points[..hidden_count]
    let (made_note, note_error) = str.builder(a, 96usize)
    if note_error != ok { ret note_error }
    var note = made_note
    try str.push_usize(&note, shown_count)
    try str.push(&note, " of 25 labels placed; grey cities would collide, so they stay unlabelled")
    let heading = [2]chart.Label{
        chart.Label { text: "Label placement without collisions", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "Largest cities claim the eight slots around their point first", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center },
    }
    let footer = [1]chart.Label{ chart.Label { text: str.done(&note), anchor: chart.Coord { x: 180.0, y: 226.0 }, align: .Center } }
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.append(a, &builder, &cities, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &hidden, paint.Brush { Solid: muted })
    try chart_scene.append_labels(a, &builder, shown[..shown_count], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[1usize..], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, footer[..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.append(&writer, &cities, blue)
    try chart_svg.append(&writer, &hidden, muted)
    try chart_svg.append_labels(&writer, shown[..shown_count], dark, 7.0)
    try chart_svg.append_labels(&writer, heading[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, heading[1usize..], dark, 7.0)
    try chart_svg.append_labels(&writer, footer[..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_locale_axes_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/locale_axes.png"
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let blue = paint.rgba(0.11, 0.42, 0.77, 1.0)
    let grid = paint.rgba(0.84, 0.87, 0.92, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let (db, db_error) = text_locale.builtin(a)
    if db_error != ok { ret db_error }
    let tags = [4]str{ "en-US", "de", "es", "it" }
    let titles = [4]str{ "English (US)", "Deutsch", "Español", "Italiano" }
    var dates: [12]calendar_time.Date = zero
    let values = [12]f64{ 4200.0f64, 5100.0f64, 6400.0f64, 5800.0f64, 7600.0f64, 8900.0f64, 9400.0f64, 8700.0f64, 10200.0f64, 11400.0f64, 12100.0f64, 11800.0f64 }
    var m = 0usize
    while m < 12usize {
        dates[m] = calendar_time.Date { year: 2024i32, month: u8(m + 1usize), day: 1u8 }
        m += 1usize
    }
    var date_storage: [4]chart.DateTick = zero
    let (months, months_error) = chart.date_ticks(dates[0usize], dates[11usize], 3usize, date_storage[..])
    if months_error != ok { ret months_error }
    let y_ticks = [6]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 2500.0, fraction: 0.2 }, chart.Tick { value: 5000.0, fraction: 0.4 }, chart.Tick { value: 7500.0, fraction: 0.6 }, chart.Tick { value: 10000.0, fraction: 0.8 }, chart.Tick { value: 12500.0, fraction: 1.0 } }
    let columns = [2]f32{ 1.0, 1.0 }
    let rows = [2]f32{ 1.0, 1.0 }
    var cells: [4]geometry.Rect = zero
    let (placed, grid_error) = chart.plot_grid(geometry.rect(8.0, 40.0, 344.0, 194.0), columns[..], rows[..], 10.0, 8.0, cells[..])
    if grid_error != ok { ret grid_error }
    var series: [4]chart.Layout = zero
    var point_storage: [48]chart.Coord = zero
    var segment_storage: [44]chart.Segment = zero
    var plots: [4]geometry.Rect = zero
    var labels: [44]chart.Label = zero
    var label_count = 0usize
    var p = 0usize
    while p < 4usize {
        let (place, place_error) = text_locale.locale(&db, tags[p])
        if place_error != ok { ret place_error }
        let cell = placed[p]
        let plot = geometry.rect(cell.x + 40.0, cell.y + 16.0, cell.width - 50.0, cell.height - 30.0)
        plots[p] = plot
        let (line, line_error) = chart.date_axis_line(dates[..], values[..], dates[0usize], dates[11usize], 0.0f64, 12500.0f64, plot, point_storage[p * 12usize..p * 12usize + 12usize], segment_storage[p * 11usize..p * 11usize + 11usize])
        if line_error != ok { ret line_error }
        series[p] = line
        var y_text: [6]str = zero
        let (numbers, numbers_error) = chart_locale.format_ticks_in(a, place, y_ticks[..], y_text[..])
        if numbers_error != ok { ret numbers_error }
        var x_text: [4]str = zero
        let (month_names, names_error) = chart_locale.format_date_ticks_in(a, place, months, "MMM", x_text[..])
        if names_error != ok { ret names_error }
        labels[label_count] = chart.Label { text: titles[p], anchor: chart.Coord { x: cell.x + 4.0, y: cell.y + 9.0 }, align: .Left }
        label_count += 1usize
        var i = 0usize
        while i < numbers.len {
            labels[label_count] = chart.Label { text: numbers[i], anchor: chart.Coord { x: plot.x - 4.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 2.5 }, align: .Right }
            label_count += 1usize
            i += 1usize
        }
        i = 0usize
        while i < month_names.len {
            labels[label_count] = chart.Label { text: month_names[i], anchor: chart.Coord { x: plot.x + plot.width * months[i].fraction, y: plot.y + plot.height + 9.0 }, align: .Center }
            label_count += 1usize
            i += 1usize
        }
        p += 1usize
    }
    let heading = [2]chart.Label{
        chart.Label { text: "One series, four locales", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center },
        chart.Label { text: "Separators, grouping (Spanish leaves 2500 alone) and month names", anchor: chart.Coord { x: 180.0, y: 31.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 160usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    p = 0usize
    while p < 4usize {
        try fill(&builder, plots[p], paint.Brush { Solid: panel })
        try chart_scene.append_guides(&builder, plots[p], zero, y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: grid })
        try chart_scene.append(a, &builder, &series[p], paint.Brush { Solid: blue })
        p += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..label_count], font, 6.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[1usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    p = 0usize
    while p < 4usize {
        try chart_svg.rect(&writer, plots[p], panel, false)
        try chart_svg.append_guides(&writer, plots[p], zero, y_ticks[..], grid, grid)
        try chart_svg.append(&writer, &series[p], blue)
        p += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..label_count], dark, 6.0)
    try chart_svg.append_labels(&writer, heading[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, heading[1usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

// The PNG is the e.ui runtime's own frame: a themed framed canvas whose chart
// view is laid out at paint time, read back through the headless harness.
fn render_ui_canvas_preview(a: *mem.Arena) -> err {
    let path = "docs/chart-previews/ui_canvas.png"
    let quarters = [8]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 }
    let revenue = [8]f32{ 3.1, 3.6, 4.4, 4.0, 5.2, 5.9, 6.3, 7.1 }
    var bars: [8]geometry.Rect = zero
    let spec = chart.spec(.Bar, geometry.rect(0.0, 0.0, 1.0, 1.0), quarters[..], revenue[..])
    let accent = paint.rgba(0.40, 0.31, 0.64, 1.0)
    var v = chart_widget.view(a, spec, paint.Brush { Solid: accent }, zero, zero, bars[..])
    var tick_storage: [8]chart.Tick = zero
    let (y_ticks, tick_error) = chart.nice_ticks(chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }, 0.0, 7.1, 4usize, tick_storage[..])
    if tick_error != ok { ret tick_error }
    v.y_ticks = y_ticks
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { ret open_error }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (made_renderer, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { ret renderer_error }
    var renderer = made_renderer
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 512usize })
    if runtime_error != ok { ret runtime_error }
    var runtime = rt
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let fonts = [1]shape.Font{ shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 } }
    try scene.register_font(&renderer, fonts[0usize])
    var tokens = ui_style.reference(.Light)
    let theme = control.Theme { tokens: &tokens, fonts: fonts[..], language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, WIDTH, HEIGHT, 1.0)
    if harness_error != ok { ret harness_error }
    var harness = h
    var title_options = control.text_options()
    title_options.role = .TitleSmall
    let (title, title_error) = control.text(a, 1u64, "Revenue by quarter, in an e.ui canvas", &theme, title_options)
    if title_error != ok { ret title_error }
    var note_options = control.text_options()
    note_options.role = .LabelSmall
    note_options.color = .OnSurfaceVariant
    let (note, note_error) = control.text(a, 2u64, "Bars laid out when the canvas paints, at its size", &theme, note_options)
    if note_error != ok { ret note_error }
    var options = control.canvas_options()
    options.width = 336.0
    options.height = 168.0
    options.label = "Revenue by quarter"
    let (frame, frame_error) = control.framed_canvas(a, 3u64, &theme, chart_widget.custom(&v), options)
    if frame_error != ok { ret frame_error }
    let (children, children_error) = mem.alloc[widget.Node](a, 3usize)
    if children_error != ok { ret children_error }
    children[0usize] = title
    children[1usize] = note
    children[2usize] = frame
    var page = ui_style.defaults()
    page.width = ui_style.Length { Px: f32(WIDTH) }
    page.height = ui_style.Length { Px: f32(HEIGHT) }
    page.background = paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) }
    let pad = ui_style.Length { Px: 12.0 }
    page.padding = ui_style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let root = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, page, children[..3usize])
    try testing.pump(&harness, root, calendar_time.Instant { nanos: 1000000000i64 })
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { ret shot_error }
    let (frame_bounds, has_frame) = widget.bounds_of(&runtime, testing.by_key(&harness, 3u64).element)
    if !has_frame || v.marks.bars.len != 8usize { ret chart.Invalid }
    let (view, view_error) = image.make_const(shot.pixels, shot.width, shot.height, shot.stride, shot.format, shot.alpha)
    if view_error != ok { ret view_error }
    let (png_state, unused, png_writer_error) = io.memory_writer(a, 0usize)
    if png_writer_error != ok { ret png_writer_error }
    var png_held = png_state
    var png_writer = io.writer(mem.cast[*void](&png_held), io.memory_write)
    try png.encode(&png_writer, view, png.EncodeOptions { compression: .Fast, interlace: false })
    try fs.write_file(a, path, io.memory_bytes(&png_held))
    // The vector companion draws what the canvas painted, where it painted it.
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, frame_bounds, ui_style.color(&tokens, .SurfaceContainerLowest), false)
    try chart_svg.append_guides(&writer, v.plot, zero, y_ticks, paint.rgba(0.80, 0.84, 0.89, 1.0), paint.rgba(0.80, 0.84, 0.89, 1.0))
    try chart_svg.append(&writer, &v.marks, accent)
    let captions = [2]chart.Label{
        chart.Label { text: "Revenue by quarter, in an e.ui canvas", anchor: chart.Coord { x: 12.0, y: 26.0 }, align: .Left },
        chart.Label { text: "Bars laid out when the canvas paints, at its size", anchor: chart.Coord { x: 12.0, y: 42.0 }, align: .Left },
    }
    try chart_svg.append_labels(&writer, captions[..1usize], ui_style.color(&tokens, .Text), 12.0)
    try chart_svg.append_labels(&writer, captions[1usize..], ui_style.color(&tokens, .OnSurfaceVariant), 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    try fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
    try testing.close(&harness)
    try widget.close(&runtime)
    try scene.close(&renderer)
    ret gpu.close(device)
}

// One layout, three files: the PNG and SVG every preview has, and a PDF page
// whose marks sit exactly where the PNG's do (text is Helvetica in the PDF).
fn render_pdf_export_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/pdf_export.png"
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let grid = paint.rgba(0.84, 0.87, 0.92, 1.0)
    let axis = paint.rgba(0.56, 0.62, 0.70, 1.0)
    let blue = paint.rgba(0.0, 114.0 / 255.0, 178.0 / 255.0, 1.0)
    let orange = paint.rgba(195.0 / 255.0, 86.0 / 255.0, 0.0, 1.0)
    let plot = geometry.rect(48.0, 50.0, 286.0, 150.0)
    let x = [6]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 }
    let revenue = [6]f32{ 31.0, 36.0, 44.0, 40.0, 52.0, 59.0 }
    let margin = [6]f32{ 12.0, 15.0, 21.0, 17.0, 26.0, 31.0 }
    let limits = [2]f32{ 0.0, 60.0 }
    var bar_storage: [6]geometry.Rect = zero
    var point_storage: [6]chart.Coord = zero
    var line_storage: [5]chart.Segment = zero
    let bar_spec = chart.spec(.Bar, plot, x[..], revenue[..])
    let (bars, bars_error) = chart.layout_with_limits(&bar_spec, zero, zero, bar_storage[..], zero, limits[..])
    if bars_error != ok { ret bars_error }
    let x_limits = [2]f32{ bars.x_min, bars.x_max }
    let line_spec = chart.spec(.PointLine, plot, x[..], margin[..])
    let (trend, trend_error) = chart.layout_with_limits(&line_spec, point_storage[..], line_storage[..], zero, x_limits[..], limits[..])
    if trend_error != ok { ret trend_error }
    let y_ticks = [4]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 20.0, fraction: 1.0 / 3.0 }, chart.Tick { value: 40.0, fraction: 2.0 / 3.0 }, chart.Tick { value: 60.0, fraction: 1.0 } }
    let y_text = [4]str{ "0", "20", "40", "60" }
    let quarters = [6]str{ "Q1", "Q2", "Q3", "Q4", "Q5", "Q6" }
    var labels: [14]chart.Label = zero
    labels[0usize] = chart.Label { text: "Revenue and margin, \xe2\x82\xacm", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Bars: revenue \xc2\xb7 line: margin \xe2\x80\x93 one layout, PNG/SVG/PDF", anchor: chart.Coord { x: 180.0, y: 36.0 }, align: .Center }
    var i = 0usize
    while i < 6usize {
        let bar = bars.bars[i]
        labels[2usize + i] = chart.Label { text: quarters[i], anchor: chart.Coord { x: bar.x + bar.width / 2.0, y: plot.y + plot.height + 14.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        labels[8usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: plot.x - 8.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[12usize] = chart.Label { text: "Revenue", anchor: chart.Coord { x: 300.0, y: 228.0 }, align: .Right }
    labels[13usize] = chart.Label { text: "Margin", anchor: chart.Coord { x: 340.0, y: 228.0 }, align: .Right }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append_guides(&builder, plot, zero, y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: axis })
    try chart_scene.append(a, &builder, &bars, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &trend, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..12usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[12usize..13usize], font, 8.0, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 8.0, paint.Brush { Solid: orange })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, zero, y_ticks[..], grid, axis)
    try chart_svg.append(&writer, &bars, blue)
    try chart_svg.append(&writer, &trend, orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 7.0)
    try chart_svg.append_labels(&writer, labels[2usize..12usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[12usize..13usize], blue, 8.0)
    try chart_svg.append_labels(&writer, labels[13usize..], orange, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    try fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
    let (content, content_error) = mem.alloc[u8](a, 65536usize)
    if content_error != ok { ret content_error }
    let (started, begin_error) = chart_pdf.begin(content, f32(WIDTH), f32(HEIGHT), "Revenue and margin, \xe2\x82\xacm")
    if begin_error != ok { ret begin_error }
    var doc = started
    try chart_pdf.rect(&doc, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), white, false)
    try chart_pdf.append_guides(&doc, plot, zero, y_ticks[..], grid, axis)
    try chart_pdf.append(&doc, &bars, blue)
    try chart_pdf.append(&doc, &trend, orange)
    try chart_pdf.append_labels(&doc, labels[..1usize], dark, 11.0)
    try chart_pdf.append_labels(&doc, labels[1usize..2usize], dark, 7.0)
    try chart_pdf.append_labels(&doc, labels[2usize..12usize], dark, 8.0)
    try chart_pdf.append_labels(&doc, labels[12usize..13usize], blue, 8.0)
    try chart_pdf.append_labels(&doc, labels[13usize..], orange, 8.0)
    let (pdf_state, unused, pdf_writer_error) = io.memory_writer(a, 0usize)
    if pdf_writer_error != ok { ret pdf_writer_error }
    var pdf_held = pdf_state
    var pdf_writer = io.writer(mem.cast[*void](&pdf_held), io.memory_write)
    try chart_pdf.finish(&doc, &pdf_writer)
    ret fs.write_file(a, "docs/chart-previews/pdf_export.pdf", io.memory_bytes(&pdf_held))
}

// benchmarks/charts/results/windows.json, 2026-10-04: nine-run medians of 200
// charts per pass (i5-12500H, matplotlib 3.9.4). Re-running the benchmark
// does not change this picture; update the numbers here by hand.
fn render_benchmark_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/benchmark_matplotlib.png"
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let axis = paint.rgba(0.56, 0.62, 0.70, 1.0)
    let colors = [2]paint.Color{ paint.rgba(0.0, 114.0 / 255.0, 178.0 / 255.0, 1.0), paint.rgba(195.0 / 255.0, 86.0 / 255.0, 0.0, 1.0) }
    let values = [4]f32{ 2.50, 15.63, 20.02, 16.51 }
    let shown = [4]str{ "2.50", "15.63", "20.02", "16.51" }
    let plot = geometry.rect(30.0, 52.0, 300.0, 136.0)
    var bar_storage: [4]geometry.Rect = zero
    var layer_storage: [2]chart.Layout = zero
    let (layers, layers_error) = chart.grouped_bars(values[..], 2usize, 2usize, plot, bar_storage[..], layer_storage[..])
    if layers_error != ok { ret layers_error }
    var labels: [11]chart.Label = zero
    labels[0usize] = chart.Label { text: "Milliseconds per chart (lower is better)", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Neper vs matplotlib: 1,000-point line, 200 markers, grid, 360x240", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    var i = 0usize
    while i < 4usize {
        let bar = layers[i % 2usize].bars[i / 2usize]
        labels[2usize + i] = chart.Label { text: shown[i], anchor: chart.Coord { x: bar.x + bar.width / 2.0, y: bar.y - 4.0 }, align: .Center }
        i += 1usize
    }
    labels[6usize] = chart.Label { text: "SVG", anchor: chart.Coord { x: plot.x + plot.width * 0.25, y: plot.y + plot.height + 14.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "PNG", anchor: chart.Coord { x: plot.x + plot.width * 0.75, y: plot.y + plot.height + 14.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "Neper", anchor: chart.Coord { x: 52.0, y: 64.0 }, align: .Left }
    labels[9usize] = chart.Label { text: "matplotlib", anchor: chart.Coord { x: 52.0, y: 78.0 }, align: .Left }
    labels[10usize] = chart.Label { text: "Windows, 9-run medians; Neper PNG = 2.0 ms raster + 18.0 ms PNG encode", anchor: chart.Coord { x: 180.0, y: 226.0 }, align: .Center }
    let swatches = [2]geometry.Rect{ geometry.rect(38.0, 59.0, 10.0, 4.0), geometry.rect(38.0, 73.0, 10.0, 4.0) }
    let baseline = geometry.rect(plot.x, plot.y + plot.height, plot.width, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, baseline, paint.Brush { Solid: axis })
    try chart_scene.append(a, &builder, &layers[0usize], paint.Brush { Solid: colors[0usize] })
    try chart_scene.append(a, &builder, &layers[1usize], paint.Brush { Solid: colors[1usize] })
    try fill(&builder, swatches[0usize], paint.Brush { Solid: colors[0usize] })
    try fill(&builder, swatches[1usize], paint.Brush { Solid: colors[1usize] })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..8usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[8usize..10usize], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[10usize..], font, 6.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, baseline, axis, false)
    try chart_svg.append(&writer, &layers[0usize], colors[0usize])
    try chart_svg.append(&writer, &layers[1usize], colors[1usize])
    try chart_svg.rect(&writer, swatches[0usize], colors[0usize], false)
    try chart_svg.rect(&writer, swatches[1usize], colors[1usize], false)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 7.0)
    try chart_svg.append_labels(&writer, labels[2usize..8usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[8usize..10usize], dark, 7.0)
    try chart_svg.append_labels(&writer, labels[10usize..], dark, 6.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

// Zachary's karate club (NetworkX's 78 edges): force-directed layout, Louvain
// communities from e.algo.graph.community, node area by degree.
fn render_network_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/network.png"
    let from = [78]u32{ 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 1u32, 1u32, 1u32, 1u32, 1u32, 1u32, 1u32, 1u32, 2u32, 2u32, 2u32, 2u32, 2u32, 2u32, 2u32, 2u32, 3u32, 3u32, 3u32, 4u32, 4u32, 5u32, 5u32, 5u32, 6u32, 8u32, 8u32, 8u32, 9u32, 13u32, 14u32, 14u32, 15u32, 15u32, 18u32, 18u32, 19u32, 20u32, 20u32, 22u32, 22u32, 23u32, 23u32, 23u32, 23u32, 23u32, 24u32, 24u32, 24u32, 25u32, 26u32, 26u32, 27u32, 28u32, 28u32, 29u32, 29u32, 30u32, 30u32, 31u32, 31u32, 32u32 }
    let to = [78]u32{ 1u32, 2u32, 3u32, 4u32, 5u32, 6u32, 7u32, 8u32, 10u32, 11u32, 12u32, 13u32, 17u32, 19u32, 21u32, 31u32, 2u32, 3u32, 7u32, 13u32, 17u32, 19u32, 21u32, 30u32, 3u32, 7u32, 8u32, 9u32, 13u32, 27u32, 28u32, 32u32, 7u32, 12u32, 13u32, 6u32, 10u32, 6u32, 10u32, 16u32, 16u32, 30u32, 32u32, 33u32, 33u32, 33u32, 32u32, 33u32, 32u32, 33u32, 32u32, 33u32, 33u32, 32u32, 33u32, 32u32, 33u32, 25u32, 27u32, 29u32, 32u32, 33u32, 25u32, 27u32, 31u32, 31u32, 29u32, 33u32, 33u32, 31u32, 33u32, 32u32, 33u32, 32u32, 33u32, 32u32, 33u32, 33u32 }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let link_ink = paint.rgba(0.72, 0.76, 0.82, 1.0)
    // Communities, computed rather than drawn from a reference.
    let (made_graph, builder_error) = data_graph.builder[u8](a, 34usize, 156usize)
    if builder_error != ok { ret builder_error }
    var graph_builder = made_graph
    var e = 0usize
    while e < 78usize {
        try data_graph.add_undirected[u8](&graph_builder, from[e], to[e], 0u8)
        e += 1usize
    }
    let club = try data_graph.finish[u8](a, &graph_builder)
    var groups: [34]u32 = zero
    let quality = try community.louvain[u8](a, &club, groups[..])
    var degree: [34]usize = zero
    e = 0usize
    while e < 78usize {
        degree[usize(from[e])] += 1usize
        degree[usize(to[e])] += 1usize
        e += 1usize
    }
    var work: [136]f64 = zero
    var node_storage: [34]chart.Coord = zero
    var segment_storage: [78]chart.Segment = zero
    let frame = geometry.rect(24.0, 46.0, 312.0, 160.0)
    let net = try chart.network_layout(34usize, from[..], to[..], frame, 300usize, work[..], node_storage[..], segment_storage[..])
    var palette_store: [6]paint.Color = zero
    let palette = try chart.accessible_palette(white, palette_store[..])
    // One bubble layer per community; area grows with degree.
    var bubbles: [34]geometry.Rect = zero
    var layers: [6]chart.Layout = zero
    var used = 0usize
    var group = 0u32
    var group_count = 0usize
    while group < 6u32 {
        let first = used
        var i = 0usize
        while i < 34usize {
            if groups[i] == group {
                let d = 5.0 + 2.2 * math.sqrt[f32](f32(degree[i]))
                bubbles[used] = geometry.rect(net.nodes[i].x - d / 2.0, net.nodes[i].y - d / 2.0, d, d)
                used += 1usize
            }
            i += 1usize
        }
        if used > first {
            layers[group_count] = chart.Layout { kind: .Bubble, coords: zero, segments: zero, bars: bubbles[first..used], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            group_count += 1usize
        }
        group += 1u32
    }
    let hundredths = u64(quality * 100.0f64 + 0.5f64)
    let (made_note, note_error) = str.builder(a, 80usize)
    if note_error != ok { ret note_error }
    var note = made_note
    try str.push_usize(&note, group_count)
    try str.push(&note, " Louvain communities, modularity 0.")
    if hundredths % 100u64 < 10u64 { try str.push(&note, "0") }
    try str.push_usize(&note, usize(hundredths % 100u64))
    try str.push(&note, "; node area by degree")
    let labels = [4]chart.Label{
        chart.Label { text: "Karate club network", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: str.done(&note), anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center },
        chart.Label { text: "Instructor", anchor: chart.Coord { x: net.nodes[0usize].x, y: net.nodes[0usize].y + 18.0 }, align: .Center },
        chart.Label { text: "Administrator", anchor: chart.Coord { x: net.nodes[33usize].x, y: net.nodes[33usize].y + 18.0 }, align: .Center },
    }
    let footer = [1]chart.Label{ chart.Label { text: "Fruchterman-Reingold, 300 steps from a golden-angle spiral", anchor: chart.Coord { x: 180.0, y: 228.0 }, align: .Center } }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, scene_error) = scene.builder(a, 256usize)
    if scene_error != ok { ret scene_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &net.links, paint.Brush { Solid: link_ink })
    var k = 0usize
    while k < group_count {
        try chart_scene.append(a, &builder, &layers[k], paint.Brush { Solid: palette[k] })
        k += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, footer[..], font, 6.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &net.links, link_ink)
    k = 0usize
    while k < group_count {
        try chart_svg.append(&writer, &layers[k], palette[k])
        k += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 7.0)
    try chart_svg.append_labels(&writer, labels[2usize..], dark, 7.0)
    try chart_svg.append_labels(&writer, footer[..], dark, 6.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

// The chart modules and what they build on, in rows (D2117): the links are
// docs/modules.json's direct dependencies among these twelve.
fn render_layered_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/layered.png"
    let names = [12]str{ "e.mem", "e.str", "e.math", "e.io", "e.fmt.json", "e.gfx.geometry", "e.gfx.paint", "e.gfx.scene", "e.gfx.chart", "e.gfx.chart.scene", "e.gfx.chart.svg", "e.gfx.chart.geojson" }
    let from = [34]u32{ 0u32, 0u32, 0u32, 1u32, 3u32, 0u32, 1u32, 2u32, 0u32, 5u32, 2u32, 5u32, 6u32, 2u32, 0u32, 2u32, 5u32, 6u32, 0u32, 8u32, 5u32, 6u32, 7u32, 8u32, 5u32, 6u32, 3u32, 2u32, 0u32, 1u32, 4u32, 8u32, 0u32, 1u32 }
    let to = [34]u32{ 1u32, 2u32, 3u32, 3u32, 4u32, 4u32, 4u32, 5u32, 5u32, 6u32, 6u32, 7u32, 7u32, 7u32, 7u32, 8u32, 8u32, 8u32, 9u32, 9u32, 9u32, 9u32, 9u32, 10u32, 10u32, 10u32, 10u32, 10u32, 10u32, 10u32, 11u32, 11u32, 11u32, 11u32 }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let link_ink = paint.rgba(0.72, 0.76, 0.82, 1.0)
    let box_ink = paint.rgba(0.87, 0.92, 0.98, 1.0)
    var work: [48]f64 = zero
    var node_storage: [12]chart.Coord = zero
    var segment_storage: [34]chart.Segment = zero
    let frame = geometry.rect(24.0, 50.0, 312.0, 162.0)
    let graph = try chart.layered_layout(12usize, from[..], to[..], frame, 4usize, work[..], node_storage[..], segment_storage[..])
    var boxes: [12]geometry.Rect = zero
    var names_placed: [12]chart.Label = zero
    var i = 0usize
    while i < 12usize {
        boxes[i] = geometry.rect(graph.nodes[i].x - 44.0, graph.nodes[i].y - 7.0, 88.0, 14.0)
        names_placed[i] = chart.Label { text: names[i], anchor: chart.Coord { x: graph.nodes[i].x, y: graph.nodes[i].y + 2.5 }, align: .Center }
        i += 1usize
    }
    let labels = [3]chart.Label{
        chart.Label { text: "Layered dependency graph", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "Chart modules and what they build on; every link points down", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center },
        chart.Label { text: "Longest-path rows, 4 barycentre sweeps; edges from docs/modules.json", anchor: chart.Coord { x: 180.0, y: 228.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    // The renderer holds sixteen fonts (scene's MAX_FONTS), and the gallery's sixteen
    // ids are taken: this face is already registered as 32.
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, scene_error) = scene.builder(a, 256usize)
    if scene_error != ok { ret scene_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &graph.links, paint.Brush { Solid: link_ink })
    i = 0usize
    while i < 12usize {
        try fill(&builder, boxes[i], paint.Brush { Solid: box_ink })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, names_placed[..], font, 6.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &graph.links, link_ink)
    i = 0usize
    while i < 12usize {
        try chart_svg.rect(&writer, boxes[i], box_ink, false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, names_placed[..], dark, 6.0)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_legend_collision_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/legend_collision.png"
    let names = [4]str{ "Control baseline", "Treatment alpha extended", "Treatment beta extended", "Follow-up cohort" }
    let colors = [4]paint.Color{
        paint.rgba(0.13, 0.42, 0.76, 1.0),
        paint.rgba(0.12, 0.57, 0.48, 1.0),
        paint.rgba(0.85, 0.43, 0.19, 1.0),
        paint.rgba(0.55, 0.38, 0.73, 1.0),
    }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let pale = paint.rgba(0.95, 0.97, 0.99, 1.0)
    let grid = paint.rgba(0.84, 0.88, 0.92, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let fonts = [1]text_layout.FontChoice{ text_layout.FontChoice { font: font, size: 8.0 } }
    let style = text_layout.Style { fonts: fonts[..], language: "", line_height: 0.0 }
    let options = text_layout.Options { width: 0.0, max_lines: 1u32, align: .Start, wrap: .None, ellipsis: "", notdef: true }
    var widths: [4]f32 = zero
    var i = 0usize
    while i < names.len {
        let (measured, measure_error) = text_layout.layout(a, names[i], style, options)
        if measure_error != ok { ret measure_error }
        widths[i] = measured.bounds.width
        i += 1usize
    }
    let legend_bounds = geometry.rect(19.0, 163.0, 322.0, 52.0)
    var items: [4]chart.LegendItem = zero
    let (legend, legend_error) = chart.wrapped_legend_items(names[..], widths[..], legend_bounds, 10.0, 10.0, 22.0, items[..])
    if legend_error != ok || legend.rows != 2usize { ret chart.Invalid }
    var legend_labels: [4]chart.Label = zero
    i = 0usize
    while i < items.len {
        legend_labels[i] = items[i].label
        i += 1usize
    }
    let plot = geometry.rect(37.0, 56.0, 286.0, 96.0)
    let x = [4]f32{ 48.0, 136.0, 224.0, 312.0 }
    let ys = [16]f32{
        123.0, 116.0, 106.0, 96.0,
        139.0, 125.0, 99.0, 74.0,
        144.0, 132.0, 114.0, 87.0,
        128.0, 119.0, 105.0, 101.0,
    }
    var lines: [12]chart.Segment = zero
    var layers: [4]chart.Layout = zero
    i = 0usize
    while i < 4usize {
        var j = 0usize
        while j < 3usize {
            lines[i * 3usize + j] = chart.Segment { from: chart.Coord { x: x[j], y: ys[i * 4usize + j] }, to: chart.Coord { x: x[j + 1usize], y: ys[i * 4usize + j + 1usize] } }
            j += 1usize
        }
        layers[i] = chart.Layout { kind: .Line, coords: zero, segments: lines[i * 3usize..i * 3usize + 3usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    var grid_segments: [3]chart.Segment = zero
    i = 0usize
    while i < 3usize {
        let y = plot.y + 20.0 + f32(i) * 30.0
        grid_segments[i] = chart.Segment { from: chart.Coord { x: plot.x, y: y }, to: chart.Coord { x: plot.x + plot.width, y: y } }
        i += 1usize
    }
    let guide = chart.Layout { kind: .Rug, coords: zero, segments: grid_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let labels = [3]chart.Label{
        chart.Label { text: "Wrapped legend / no collisions", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "Measured labels wrap within a fixed legend band", anchor: chart.Coord { x: 180.0, y: 40.0 }, align: .Center },
        chart.Label { text: "Swatch and label stay together on each row", anchor: chart.Coord { x: 180.0, y: 234.0 }, align: .Center },
    }
    let (made, builder_error) = scene.builder(a, 100usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try fill(&builder, legend_bounds, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &guide, paint.Brush { Solid: grid })
    i = 0usize
    while i < 4usize {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: colors[i] })
        try fill(&builder, legend.items[i].swatch, paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, legend_labels[..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.rect(&writer, legend_bounds, pale, false)
    try chart_svg.append(&writer, &guide, grid)
    i = 0usize
    while i < 4usize {
        try chart_svg.append(&writer, &layers[i], colors[i])
        try chart_svg.rect(&writer, legend.items[i].swatch, colors[i], false)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, legend_labels[..], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_category_facet_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/category_facet.png"
    let keys = [12]str{ "North", "South", "East", "North", "South", "East", "North", "South", "East", "North", "South", "East" }
    let x = [12]f32{ 1.0, 1.0, 1.0, 3.5, 3.5, 3.5, 6.5, 6.5, 6.5, 9.0, 9.0, 9.0 }
    let y = [12]f32{ 3.0, 8.0, 2.0, 4.0, 6.5, 4.0, 7.0, 4.5, 6.0, 8.5, 2.5, 9.0 }
    let levels = [4]str{ "North", "South", "East", "West" }
    var panels: [4]geometry.Rect = zero
    var points: [12]chart.Coord = zero
    var marks: [4]chart.Layout = zero
    var strips: [4]chart.Label = zero
    var counts: [4]usize = zero
    let (facets, facet_error) = chart.category_facet_scatter(keys[..], x[..], y[..], levels[..], geometry.rect(14.0, 49.0, 332.0, 161.0), 2usize, 9.0, 18.0, 0.0, 10.0, 0.0, 10.0, panels[..], points[..], marks[..], strips[..], counts[..])
    if facet_error != ok || counts[0usize] != 4usize || counts[3usize] != 0usize { ret chart.Invalid }
    let blue = paint.rgba(0.15, 0.40, 0.70, 1.0)
    let teal = paint.rgba(0.10, 0.55, 0.50, 1.0)
    let panel = paint.rgba(0.95, 0.97, 0.99, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let gray = paint.rgba(0.48, 0.54, 0.61, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [4]chart.Label = zero
    labels[0usize] = chart.Label { text: "Category facets / shared scales", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Explicit panel order; West has no observations", anchor: chart.Coord { x: 180.0, y: 39.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "No observations", anchor: chart.Coord { x: panels[3usize].x + panels[3usize].width * 0.5, y: panels[3usize].y + 52.0 }, align: .Center }
    labels[3usize] = chart.Label { text: "Every panel uses x = 0..10 and y = 0..10", anchor: chart.Coord { x: 180.0, y: 234.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 100usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    var i = 0usize
    while i < facets.panels.len {
        try fill(&builder, facets.panels[i], paint.Brush { Solid: panel })
        try fill(&builder, geometry.rect(facets.panels[i].x, facets.panels[i].y, facets.panels[i].width, 18.0), paint.Brush { Solid: blue })
        try chart_scene.append(a, &builder, &facets.marks[i], paint.Brush { Solid: teal })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, facets.strips, font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..3usize], font, 8.0, paint.Brush { Solid: gray })
    try chart_scene.append_labels(a, &builder, labels[3usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < facets.panels.len {
        try chart_svg.rect(&writer, facets.panels[i], panel, false)
        try chart_svg.rect(&writer, geometry.rect(facets.panels[i].x, facets.panels[i].y, facets.panels[i].width, 18.0), blue, false)
        try chart_svg.append(&writer, &facets.marks[i], teal)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, facets.strips, white, 9.0)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[2usize..3usize], gray, 8.0)
    try chart_svg.append_labels(&writer, labels[3usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_discrete_axis_bar_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/discrete_axis_bar.png"
    let keys = [5]str{ "North", "East", "North", "West", "South" }
    let values = [5]f64{ 7.0f64, 8.0f64, 5.0f64, 4.0f64, 6.0f64 }
    let levels = [5]str{ "North", "South", "East", "West", "Online (0)" }
    let plot = geometry.rect(47.0, 58.0, 286.0, 132.0)
    var sums: [5]f64 = zero
    var bars: [5]geometry.Rect = zero
    var ticks: [5]chart.Tick = zero
    let (series, series_error) = chart.discrete_axis_bars(keys[..], values[..], levels[..], 15.0f64, plot, sums[..], bars[..], ticks[..])
    if series_error != ok || sums[0usize] != 12.0f64 || sums[4usize] != 0.0f64 { ret chart.Invalid }
    var grid_segments: [5]chart.Segment = zero
    var labels: [12]chart.Label = zero
    labels[0usize] = chart.Label { text: "Discrete axis / ordered categories", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Repeated keys aggregate; absent levels keep a slot", anchor: chart.Coord { x: 180.0, y: 40.0 }, align: .Center }
    var i = 0usize
    while i < levels.len {
        let x = plot.x + plot.width * ticks[i].fraction
        labels[2usize + i] = chart.Label { text: levels[i], anchor: chart.Coord { x: x, y: 207.0 }, align: .Center }
        i += 1usize
    }
    let y_text = [4]str{ "15", "10", "5", "0" }
    i = 0usize
    while i < 4usize {
        let y = plot.y + f32(i) * plot.height / 3.0
        grid_segments[i] = chart.Segment { from: chart.Coord { x: plot.x, y: y }, to: chart.Coord { x: plot.x + plot.width, y: y } }
        labels[7usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 42.0, y: y + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[11usize] = chart.Label { text: "Explicit order: North, South, East, West, Online", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let zero_x = plot.x + plot.width * ticks[4usize].fraction
    grid_segments[4usize] = chart.Segment { from: chart.Coord { x: zero_x, y: plot.y + plot.height - 5.0 }, to: chart.Coord { x: zero_x, y: plot.y + plot.height } }
    let guide = chart.Layout { kind: .Rug, coords: zero, segments: grid_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let blue = paint.rgba(0.15, 0.44, 0.76, 1.0)
    let grid = paint.rgba(0.82, 0.86, 0.91, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 80usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.append(a, &builder, &guide, paint.Brush { Solid: grid })
    try chart_scene.append(a, &builder, &series, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..11usize], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[11usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.append(&writer, &guide, grid)
    try chart_svg.append(&writer, &series, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[2usize..11usize], dark, 7.0)
    try chart_svg.append_labels(&writer, labels[11usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_date_axis_line_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/date_axis_line.png"
    let dates = [7]calendar_time.Date{
        calendar_time.Date { year: 2024i32, month: 1u8, day: 1u8 },
        calendar_time.Date { year: 2024i32, month: 2u8, day: 1u8 },
        calendar_time.Date { year: 2024i32, month: 3u8, day: 1u8 },
        calendar_time.Date { year: 2024i32, month: 4u8, day: 1u8 },
        calendar_time.Date { year: 2024i32, month: 5u8, day: 1u8 },
        calendar_time.Date { year: 2024i32, month: 6u8, day: 1u8 },
        calendar_time.Date { year: 2024i32, month: 7u8, day: 1u8 },
    }
    let values = [7]f64{ 12.0f64, 20.0f64, 17.0f64, 27.0f64, 24.0f64, 35.0f64, 32.0f64 }
    let plot = geometry.rect(51.0, 61.0, 278.0, 129.0)
    var points: [7]chart.Coord = zero
    var segments: [6]chart.Segment = zero
    let (series, series_error) = chart.date_axis_line(dates[..], values[..], dates[0usize], dates[6usize], 0.0f64, 40.0f64, plot, points[..], segments[..])
    if series_error != ok { ret series_error }
    var ticks: [7]chart.DateTick = zero
    let (months, tick_error) = chart.date_ticks(dates[0usize], dates[6usize], 1usize, ticks[..])
    if tick_error != ok || months.len != 7usize { ret chart.Invalid }
    var tick_text: [7]str = zero
    var tick_storage: [49]u8 = zero
    let (_, label_error) = chart.format_date_ticks(months, tick_text[..], tick_storage[..])
    if label_error != ok { ret label_error }
    var grid_segments: [12]chart.Segment = zero
    var labels: [15]chart.Label = zero
    labels[0usize] = chart.Label { text: "Date-aware line chart", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Elapsed calendar days / leap-year February", anchor: chart.Coord { x: 180.0, y: 40.0 }, align: .Center }
    var i = 0usize
    while i < months.len {
        let x = plot.x + plot.width * months[i].fraction
        grid_segments[i] = chart.Segment { from: chart.Coord { x: x, y: plot.y }, to: chart.Coord { x: x, y: plot.y + plot.height } }
        labels[2usize + i] = chart.Label { text: tick_text[i], anchor: chart.Coord { x: x, y: 207.0 }, align: .Center }
        i += 1usize
    }
    let y_text = [5]str{ "40", "30", "20", "10", "0" }
    i = 0usize
    while i < 5usize {
        let y = plot.y + f32(i) * plot.height / 4.0
        grid_segments[7usize + i] = chart.Segment { from: chart.Coord { x: plot.x, y: y }, to: chart.Coord { x: plot.x + plot.width, y: y } }
        labels[9usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 45.0, y: y + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[14usize] = chart.Label { text: "Month starts use 31, 29, 31, 30, 31 and 30-day gaps", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let guide = chart.Layout { kind: .Rug, coords: zero, segments: grid_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let blue = paint.rgba(0.11, 0.42, 0.77, 1.0)
    let grid = paint.rgba(0.82, 0.86, 0.91, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let panel = paint.rgba(0.96, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 100usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: panel })
    try chart_scene.append(a, &builder, &guide, paint.Brush { Solid: grid })
    try chart_scene.append(a, &builder, &series, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..14usize], font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[14usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, panel, false)
    try chart_svg.append(&writer, &guide, grid)
    try chart_svg.append(&writer, &series, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[2usize..14usize], dark, 7.0)
    try chart_svg.append_labels(&writer, labels[14usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_aggregate_decomposition_tree_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/aggregate_decomposition_tree.png"
    let parents = [9]usize{ 0usize, 0usize, 1usize, 1usize, 1usize, 0usize, 5usize, 5usize, 5usize }
    let weights = [9]f32{ 0.0, 0.0, 36.0, 22.0, 17.0, 0.0, 20.0, 15.0, 10.0 }
    let names = [9]str{ "All 120", "Digital 75", "Cloud 36", "Apps 22", "Data 17", "Operations 45", "Supply 20", "Field 15", "Support 10" }
    var totals: [9]f64 = zero
    var depths: [9]usize = zero
    var spans: [9]geometry.Rect = zero
    var cards: [9]geometry.Rect = zero
    var bars: [9]geometry.Rect = zero
    var links: [24]chart.Segment = zero
    let (tree, tree_error) = chart.aggregate_decomposition_tree(parents[..], weights[..], geometry.rect(8.0, 45.0, 344.0, 165.0), totals[..], depths[..], spans[..], cards[..], bars[..], links[..])
    if tree_error != ok || tree.levels != 3usize || tree.leaves != 6usize || totals[0usize] != 120.0f64 { ret chart.Invalid }
    let navy = paint.rgba(0.15, 0.30, 0.53, 1.0)
    let blue = paint.rgba(0.18, 0.44, 0.75, 1.0)
    let teal = paint.rgba(0.13, 0.54, 0.49, 1.0)
    let gold = paint.rgba(0.96, 0.79, 0.32, 1.0)
    let gray = paint.rgba(0.54, 0.61, 0.70, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [11]chart.Label = zero
    labels[0usize] = chart.Label { text: "Aggregate decomposition tree", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Leaf values roll up; bars show share of parent", anchor: chart.Coord { x: 180.0, y: 233.0 }, align: .Center }
    var i = 0usize
    while i < cards.len {
        labels[2usize + i] = chart.Label { text: names[i], anchor: chart.Coord { x: cards[i].x + cards[i].width * 0.5, y: cards[i].y + cards[i].height * 0.5 + 1.0 }, align: .Center }
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
    try chart_scene.append(a, &builder, &tree.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &tree.nodes, paint.Brush { Solid: teal })
    try fill(&builder, cards[0usize], paint.Brush { Solid: navy })
    try fill(&builder, cards[1usize], paint.Brush { Solid: blue })
    try fill(&builder, cards[5usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &tree.value_bars, paint.Brush { Solid: gold })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..], font, 7.0, paint.Brush { Solid: white })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &tree.connectors, gray)
    try chart_svg.append(&writer, &tree.nodes, teal)
    try chart_svg.rect(&writer, cards[0usize], navy, false)
    try chart_svg.rect(&writer, cards[1usize], blue, false)
    try chart_svg.rect(&writer, cards[5usize], blue, false)
    try chart_svg.append(&writer, &tree.value_bars, gold)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[2usize..], white, 7.0)
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

fn render_state_machine_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/state_machine.png"
    let plot = geometry.rect(18.0, 45.0, 324.0, 176.0)
    let states = [4]chart.MachineState{
        chart.MachineState { center: chart.Coord { x: 65.0, y: 137.0 }, initial: true, final: false },
        chart.MachineState { center: chart.Coord { x: 155.0, y: 90.0 }, initial: false, final: false },
        chart.MachineState { center: chart.Coord { x: 265.0, y: 90.0 }, initial: false, final: true },
        chart.MachineState { center: chart.Coord { x: 155.0, y: 180.0 }, initial: false, final: true },
    }
    let names = [4]str{ "Idle", "Load", "Ready", "Error" }
    let events = [6]str{ "open", "ok", "fail", "close", "reset", "refresh" }
    let transitions = [6]chart.MachineTransition{
        chart.MachineTransition { from: 0usize, to: 1usize, event: 0usize },
        chart.MachineTransition { from: 1usize, to: 2usize, event: 1usize },
        chart.MachineTransition { from: 1usize, to: 3usize, event: 2usize },
        chart.MachineTransition { from: 2usize, to: 3usize, event: 3usize },
        chart.MachineTransition { from: 3usize, to: 0usize, event: 4usize },
        chart.MachineTransition { from: 2usize, to: 2usize, event: 5usize },
    }
    var outlines: [96]chart.Coord = zero
    var shapes: [4]chart.Layout = zero
    var arrows: [30]chart.Segment = zero
    var final_rings: [48]chart.Segment = zero
    var start_segments: [3]chart.Segment = zero
    var event_labels: [6]chart.Label = zero
    let (machine, layout_error) = chart.state_machine(states[..], transitions[..], events[..], plot, 21.0, outlines[..], shapes[..], arrows[..], final_rings[..], start_segments[..], event_labels[..])
    if layout_error != ok || machine.states.len != 4usize || machine.final_rings.segments.len != 48usize { ret chart.Invalid }
    let (next, fired, step_error) = chart.state_machine_step(4usize, 0usize, 0usize, transitions[..])
    if step_error != ok || !fired || next != 1usize { ret chart.Invalid }
    let blue = paint.rgba(0.16, 0.43, 0.76, 1.0)
    let teal = paint.rgba(0.13, 0.53, 0.46, 1.0)
    let amber = paint.rgba(0.79, 0.43, 0.13, 1.0)
    let navy = paint.rgba(0.16, 0.30, 0.54, 1.0)
    let gray = paint.rgba(0.56, 0.63, 0.72, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [6]chart.Label = zero
    labels[0usize] = chart.Label { text: "State machine / events", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Initial arrow, final rings, self-loop", anchor: chart.Coord { x: 180.0, y: 238.0 }, align: .Center }
    var i = 0usize
    while i < states.len {
        labels[i + 2usize] = chart.Label { text: names[i], anchor: chart.Coord { x: states[i].center.x, y: states[i].center.y + 3.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &machine.transitions, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &machine.initial_marker, paint.Brush { Solid: gray })
    i = 0usize
    while i < machine.states.len {
        var color = blue
        if i == 0usize { color = navy }
        if i == 2usize { color = teal }
        if i == 3usize { color = amber }
        try chart_scene.append(a, &builder, &machine.states[i], paint.Brush { Solid: color })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &machine.final_rings, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..], font, 8.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, machine.event_labels, font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &machine.transitions, gray)
    try chart_svg.append(&writer, &machine.initial_marker, gray)
    i = 0usize
    while i < machine.states.len {
        var color = blue
        if i == 0usize { color = navy }
        if i == 2usize { color = teal }
        if i == 3usize { color = amber }
        try chart_svg.append(&writer, &machine.states[i], color)
        i += 1usize
    }
    try chart_svg.append(&writer, &machine.final_rings, white)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[2usize..], white, 8.0)
    try chart_svg.append_labels(&writer, machine.event_labels, dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_sequence_diagram_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/sequence_diagram.png"
    let plot = geometry.rect(16.0, 48.0, 328.0, 171.0)
    let participants = [3]str{ "Client", "API", "DB" }
    let messages = [6]chart.SequenceMessage{
        chart.SequenceMessage { from: 0usize, to: 1usize, kind: .Call, text: "request" },
        chart.SequenceMessage { from: 1usize, to: 1usize, kind: .Call, text: "auth" },
        chart.SequenceMessage { from: 1usize, to: 2usize, kind: .Call, text: "lookup" },
        chart.SequenceMessage { from: 2usize, to: 1usize, kind: .Return, text: "row" },
        chart.SequenceMessage { from: 1usize, to: 0usize, kind: .Return, text: "200 OK" },
        chart.SequenceMessage { from: 0usize, to: 1usize, kind: .Async, text: "refresh" },
    }
    let activations = [2]chart.SequenceActivation{
        chart.SequenceActivation { participant: 1usize, first: 0usize, last: 4usize },
        chart.SequenceActivation { participant: 2usize, first: 2usize, last: 3usize },
    }
    var headers: [3]geometry.Rect = zero
    var lifelines: [30]chart.Segment = zero
    var active: [2]geometry.Rect = zero
    var strokes: [48]chart.Segment = zero
    var layers: [6]chart.Layout = zero
    var labels: [6]chart.Label = zero
    let (sequence, layout_error) = chart.sequence_diagram(participants[..], messages[..], activations[..], plot, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    if layout_error != ok || sequence.messages.len != 6usize || sequence.lifelines.segments.len != 30usize { ret chart.Invalid }
    let blue = paint.rgba(0.16, 0.43, 0.76, 1.0)
    let teal = paint.rgba(0.13, 0.53, 0.46, 1.0)
    let navy = paint.rgba(0.16, 0.30, 0.54, 1.0)
    let pale = paint.rgba(0.77, 0.87, 0.97, 1.0)
    let gray = paint.rgba(0.70, 0.75, 0.82, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var titles: [5]chart.Label = zero
    titles[0usize] = chart.Label { text: "Sequence diagram / messages", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    titles[1usize] = chart.Label { text: "Calls, return dashes, async follow-up", anchor: chart.Coord { x: 180.0, y: 238.0 }, align: .Center }
    var i = 0usize
    while i < participants.len {
        titles[i + 2usize] = chart.Label { text: participants[i], anchor: chart.Coord { x: headers[i].x + headers[i].width * 0.5, y: headers[i].y + 15.0 }, align: .Center }
        i += 1usize
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &sequence.lifelines, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &sequence.activations, paint.Brush { Solid: pale })
    i = 0usize
    while i < sequence.messages.len {
        var color = blue
        if messages[i].kind == .Return { color = gray }
        if messages[i].kind == .Async { color = teal }
        try chart_scene.append(a, &builder, &sequence.messages[i], paint.Brush { Solid: color })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &sequence.headers, paint.Brush { Solid: blue })
    try fill(&builder, headers[0usize], paint.Brush { Solid: navy })
    try fill(&builder, headers[2usize], paint.Brush { Solid: teal })
    try chart_scene.append_labels(a, &builder, titles[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, titles[1usize..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, titles[2usize..], font, 9.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, sequence.labels, font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &sequence.lifelines, gray)
    try chart_svg.append(&writer, &sequence.activations, pale)
    i = 0usize
    while i < sequence.messages.len {
        var color = blue
        if messages[i].kind == .Return { color = gray }
        if messages[i].kind == .Async { color = teal }
        try chart_svg.append(&writer, &sequence.messages[i], color)
        i += 1usize
    }
    try chart_svg.append(&writer, &sequence.headers, blue)
    try chart_svg.rect(&writer, headers[0usize], navy, false)
    try chart_svg.rect(&writer, headers[2usize], teal, false)
    try chart_svg.append_labels(&writer, titles[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, titles[1usize..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, titles[2usize..], white, 9.0)
    try chart_svg.append_labels(&writer, sequence.labels, dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_entity_relationship_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/entity_relationship.png"
    let plot = geometry.rect(12.0, 52.0, 336.0, 166.0)
    let tables = [3]chart.EntityTable{
        chart.EntityTable { name: "Customer", center: chart.Coord { x: 60.0, y: 136.0 } },
        chart.EntityTable { name: "Order", center: chart.Coord { x: 180.0, y: 136.0 } },
        chart.EntityTable { name: "LineItem", center: chart.Coord { x: 300.0, y: 136.0 } },
    }
    let fields = [9]chart.EntityField{
        chart.EntityField { table: 0usize, name: "id", key: .Primary },
        chart.EntityField { table: 0usize, name: "name", key: .None },
        chart.EntityField { table: 0usize, name: "email", key: .None },
        chart.EntityField { table: 1usize, name: "id", key: .Primary },
        chart.EntityField { table: 1usize, name: "cust_id", key: .Foreign },
        chart.EntityField { table: 1usize, name: "total", key: .None },
        chart.EntityField { table: 2usize, name: "id", key: .Primary },
        chart.EntityField { table: 2usize, name: "order_id", key: .Foreign },
        chart.EntityField { table: 2usize, name: "qty", key: .None },
    }
    let relations = [2]chart.EntityRelation{
        chart.EntityRelation { from: 0usize, to: 1usize, from_card: .One, to_card: .ZeroMany, name: "places" },
        chart.EntityRelation { from: 1usize, to: 2usize, from_card: .One, to_card: .Many, name: "contains" },
    }
    var boxes: [3]geometry.Rect = zero
    var headers: [3]geometry.Rect = zero
    var field_counts: [3]usize = zero
    var field_used: [3]usize = zero
    var table_labels: [3]chart.Label = zero
    var field_labels: [9]chart.Label = zero
    var key_labels: [9]chart.Label = zero
    var relation_labels: [2]chart.Label = zero
    var segments: [48]chart.Segment = zero
    let (diagram, layout_error) = chart.entity_relationship(tables[..], fields[..], relations[..], plot, 72.0, boxes[..], headers[..], field_counts[..], field_used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    if layout_error != ok || diagram.tables.bars.len != 3usize || diagram.key_labels.len != 5usize { ret chart.Invalid }
    let blue = paint.rgba(0.16, 0.43, 0.76, 1.0)
    let teal = paint.rgba(0.13, 0.53, 0.46, 1.0)
    let navy = paint.rgba(0.16, 0.30, 0.54, 1.0)
    let pale = paint.rgba(0.91, 0.95, 0.98, 1.0)
    let gray = paint.rgba(0.48, 0.57, 0.68, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var titles: [2]chart.Label = zero
    titles[0usize] = chart.Label { text: "Entity relationship / schema", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    titles[1usize] = chart.Label { text: "Keys and one-to-many cardinalities", anchor: chart.Coord { x: 180.0, y: 238.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &diagram.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &diagram.tables, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &diagram.headers, paint.Brush { Solid: blue })
    try fill(&builder, headers[0usize], paint.Brush { Solid: navy })
    try fill(&builder, headers[2usize], paint.Brush { Solid: teal })
    try chart_scene.append_labels(a, &builder, titles[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, titles[1usize..], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, diagram.table_labels, font, 8.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, diagram.field_labels, font, 7.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, diagram.key_labels, font, 7.0, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, diagram.relation_labels, font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &diagram.connectors, gray)
    try chart_svg.append(&writer, &diagram.tables, pale)
    try chart_svg.append(&writer, &diagram.headers, blue)
    try chart_svg.rect(&writer, headers[0usize], navy, false)
    try chart_svg.rect(&writer, headers[2usize], teal, false)
    try chart_svg.append_labels(&writer, titles[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, titles[1usize..], dark, 9.0)
    try chart_svg.append_labels(&writer, diagram.table_labels, white, 8.0)
    try chart_svg.append_labels(&writer, diagram.field_labels, dark, 7.0)
    try chart_svg.append_labels(&writer, diagram.key_labels, blue, 7.0)
    try chart_svg.append_labels(&writer, diagram.relation_labels, dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_branching_process_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/branching_process_map.png"
    let plot = geometry.rect(12.0, 48.0, 336.0, 165.0)
    let steps = [6]chart.BranchStep{
        chart.BranchStep { process_time: 1.0f64, good_fraction: 0.99f64 },
        chart.BranchStep { process_time: 2.0f64, good_fraction: 0.98f64 },
        chart.BranchStep { process_time: 1.0f64, good_fraction: 0.99f64 },
        chart.BranchStep { process_time: 3.0f64, good_fraction: 0.90f64 },
        chart.BranchStep { process_time: 2.0f64, good_fraction: 0.97f64 },
        chart.BranchStep { process_time: 0.5f64, good_fraction: 1.0f64 },
    }
    let routes = [6]chart.BranchRoute{
        chart.BranchRoute { from: 0usize, to: 1usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 1usize, to: 2usize, fraction: 0.7f64 },
        chart.BranchRoute { from: 1usize, to: 3usize, fraction: 0.3f64 },
        chart.BranchRoute { from: 2usize, to: 4usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 3usize, to: 4usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 4usize, to: 5usize, fraction: 1.0f64 },
    }
    var indegree: [6]usize = zero
    var head: [6]usize = zero
    var next: [6]usize = zero
    var order: [6]usize = zero
    var stage: [6]usize = zero
    var stage_counts: [6]usize = zero
    var stage_used: [6]usize = zero
    var flow: [6]f64 = zero
    var branch_sum: [6]f64 = zero
    let work = chart.BranchWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..], stage: stage[..], stage_counts: stage_counts[..], stage_used: stage_used[..], flow: flow[..], branch_sum: branch_sum[..] }
    var boxes: [6]geometry.Rect = zero
    var arrows: [30]chart.Segment = zero
    let (map, layout_error) = chart.branching_process_map(steps[..], routes[..], plot, work, boxes[..], arrows[..])
    if layout_error != ok || map.summary.stages != 5usize || map.summary.sinks != 1usize || map.summary.output_fraction < 0.906f64 || map.summary.output_fraction > 0.907f64 { ret chart.Invalid }
    let names = [6]str{ "Start", "Triage", "Fast", "Manual", "Merge", "Done" }
    let blue = paint.rgba(0.16, 0.43, 0.76, 1.0)
    let teal = paint.rgba(0.13, 0.53, 0.46, 1.0)
    let amber = paint.rgba(0.79, 0.43, 0.13, 1.0)
    let navy = paint.rgba(0.16, 0.30, 0.54, 1.0)
    let gray = paint.rgba(0.55, 0.63, 0.72, 1.0)
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var labels: [10]chart.Label = zero
    labels[0usize] = chart.Label { text: "Branching process / yield", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "90.6% output / 6.85h expected work", anchor: chart.Coord { x: 180.0, y: 238.0 }, align: .Center }
    var i = 0usize
    while i < boxes.len {
        labels[i + 2usize] = chart.Label { text: names[i], anchor: chart.Coord { x: boxes[i].x + boxes[i].width * 0.5, y: boxes[i].y + boxes[i].height * 0.5 + 3.0 }, align: .Center }
        i += 1usize
    }
    labels[8usize] = chart.Label { text: "70%", anchor: chart.Coord { x: 143.0, y: 89.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "30%", anchor: chart.Coord { x: 143.0, y: 170.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &map.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.nodes, paint.Brush { Solid: blue })
    try fill(&builder, boxes[0usize], paint.Brush { Solid: navy })
    try fill(&builder, boxes[2usize], paint.Brush { Solid: teal })
    try fill(&builder, boxes[3usize], paint.Brush { Solid: amber })
    try fill(&builder, boxes[5usize], paint.Brush { Solid: navy })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..8usize], font, 8.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, labels[8usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &map.connectors, gray)
    try chart_svg.append(&writer, &map.nodes, blue)
    try chart_svg.rect(&writer, boxes[0usize], navy, false)
    try chart_svg.rect(&writer, boxes[2usize], teal, false)
    try chart_svg.rect(&writer, boxes[3usize], amber, false)
    try chart_svg.rect(&writer, boxes[5usize], navy, false)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[2usize..8usize], white, 8.0)
    try chart_svg.append_labels(&writer, labels[8usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_stem_and_leaf_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/stem_and_leaf.png"
    let values = [26]f64{ 12.0f64, 15.0f64, 18.0f64, 18.0f64, 21.0f64, 22.0f64, 24.0f64, 27.0f64, 30.0f64, 33.0f64, 35.0f64, 36.0f64, 38.0f64, 41.0f64, 43.0f64, 45.0f64, 48.0f64, 52.0f64, 54.0f64, 56.0f64, 59.0f64, 61.0f64, 65.0f64, 67.0f64, 72.0f64, 75.0f64 }
    let plot = geometry.rect(44.0, 64.0, 272.0, 140.0)
    var rows: [7]chart.StemLeafRow = zero
    var leaves: [26]u8 = zero
    let (tree, tree_error) = chart.stem_and_leaf(values[..], 1.0f64, plot, rows[..], leaves[..])
    if tree_error != ok { ret tree_error }
    if tree.rows.len != 7usize || tree.leaves.len != values.len || tree.rows[2usize].count != 5usize { ret chart.Invalid }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let pale = paint.rgba(0.92, 0.96, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var divider: [1]chart.Segment = zero
    divider[0usize] = tree.divider
    let rule = chart.Layout { kind: .Rug, coords: zero, segments: divider[..], bars: zero, x_min: plot.x, x_max: plot.x + plot.width, y_min: plot.y, y_max: plot.y + plot.height }
    var labels: [48]chart.Label = zero
    labels[0usize] = chart.Label { text: "Stem-and-leaf distribution", anchor: chart.Coord { x: 180.0, y: 25.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "STEM", anchor: chart.Coord { x: 88.0, y: 52.0 }, align: .Right }
    labels[2usize] = chart.Label { text: "LEAVES", anchor: chart.Coord { x: 121.0, y: 52.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "N", anchor: chart.Coord { x: 306.0, y: 52.0 }, align: .Right }
    var label_used = 4usize
    let digits = "0123456789"
    var row = 0usize
    while row < tree.rows.len {
        let (stem_made, stem_error) = str.builder(a, 24usize)
        if stem_error != ok { ret stem_error }
        var stem_text = stem_made
        try str.push_i64(&stem_text, tree.rows[row].stem)
        labels[label_used] = chart.Label { text: str.done(&stem_text), anchor: chart.Coord { x: tree.divider.from.x - 11.0, y: tree.rows[row].baseline }, align: .Right }
        label_used += 1usize
        let (count_made, count_error) = str.builder(a, 16usize)
        if count_error != ok { ret count_error }
        var count_text = count_made
        try str.push_usize(&count_text, tree.rows[row].count)
        labels[label_used] = chart.Label { text: str.done(&count_text), anchor: chart.Coord { x: 306.0, y: tree.rows[row].baseline }, align: .Right }
        label_used += 1usize
        var leaf = 0usize
        while leaf < tree.rows[row].count {
            let digit = usize(tree.leaves[tree.rows[row].first + leaf])
            labels[label_used] = chart.Label { text: digits[digit..digit + 1usize], anchor: chart.Coord { x: tree.leaf_start + tree.leaf_step * f32(leaf), y: tree.rows[row].baseline }, align: .Left }
            label_used += 1usize
            leaf += 1usize
        }
        row += 1usize
    }
    labels[label_used] = chart.Label { text: "Key: 2 | 4 = 24 units", anchor: chart.Coord { x: 180.0, y: 225.0 }, align: .Center }
    label_used += 1usize
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 192usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    row = 0usize
    while row < tree.rows.len {
        if row % 2usize == 0usize { try fill(&builder, geometry.rect(plot.x, plot.y + 20.0 * f32(row), plot.width, 20.0), paint.Brush { Solid: pale }) }
        row += 1usize
    }
    try chart_scene.append(a, &builder, &rule, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..4usize], font, 9.0, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[4usize..label_used - 1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[label_used - 1usize..label_used], font, 9.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    row = 0usize
    while row < tree.rows.len {
        if row % 2usize == 0usize { try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + 20.0 * f32(row), plot.width, 20.0), pale, false) }
        row += 1usize
    }
    try chart_svg.append(&writer, &rule, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..4usize], blue, 9.0)
    try chart_svg.append_labels(&writer, labels[4usize..label_used - 1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, labels[label_used - 1usize..label_used], dark, 9.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_range_interval_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/range_interval.png"
    let plot = geometry.rect(79.0, 54.0, 246.0, 144.0)
    let ranges = [6]chart.RangeInterval{
        chart.RangeInterval { row: 0usize, lower: -6.0f64, upper: 8.0f64 },
        chart.RangeInterval { row: 1usize, lower: -3.0f64, upper: 12.0f64 },
        chart.RangeInterval { row: 2usize, lower: 0.0f64, upper: 18.0f64 },
        chart.RangeInterval { row: 3usize, lower: 6.0f64, upper: 25.0f64 },
        chart.RangeInterval { row: 4usize, lower: 2.0f64, upper: 20.0f64 },
        chart.RangeInterval { row: 5usize, lower: -4.0f64, upper: 10.0f64 },
    }
    var bands: [6]geometry.Rect = zero
    var caps: [12]chart.Segment = zero
    let (map, map_error) = chart.range_intervals(ranges[..], 6usize, -10.0f64, 30.0f64, plot, 0.34, bands[..], caps[..])
    if map_error != ok || map.ranges.bars.len != 6usize || map.caps.segments.len != 12usize { ret chart.Invalid }
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let grid = paint.rgba(0.81, 0.86, 0.92, 1.0)
    let pale = paint.rgba(0.94, 0.97, 0.99, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let days = [6]str{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
    let tick_text = [5]str{ "-10", "0", "10", "20", "30" }
    let ticks = [5]chart.Tick{
        chart.Tick { value: -10.0, fraction: 0.0 },
        chart.Tick { value: 0.0, fraction: 0.25 },
        chart.Tick { value: 10.0, fraction: 0.5 },
        chart.Tick { value: 20.0, fraction: 0.75 },
        chart.Tick { value: 30.0, fraction: 1.0 },
    }
    var no_y: [1]chart.Tick = zero
    var labels: [13]chart.Label = zero
    labels[0usize] = chart.Label { text: "Daily temperature ranges", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    var i = 0usize
    while i < days.len {
        labels[1usize + i] = chart.Label { text: days[i], anchor: chart.Coord { x: 69.0, y: plot.y + (f32(i) + 0.5) * 24.0 + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < ticks.len {
        labels[7usize + i] = chart.Label { text: tick_text[i], anchor: chart.Coord { x: plot.x + plot.width * ticks[i].fraction, y: 216.0 }, align: .Center }
        i += 1usize
    }
    labels[12usize] = chart.Label { text: "Daily low to high (C)", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < days.len {
        if i % 2usize == 0usize { try fill(&builder, geometry.rect(plot.x, plot.y + 24.0 * f32(i), plot.width, 24.0), paint.Brush { Solid: pale }) }
        i += 1usize
    }
    try chart_scene.append_guides(&builder, plot, ticks[..], no_y[..0usize], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.ranges, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.caps, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..12usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[12usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < days.len {
        if i % 2usize == 0usize { try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + 24.0 * f32(i), plot.width, 24.0), pale, false) }
        i += 1usize
    }
    try chart_svg.append_guides(&writer, plot, ticks[..], no_y[..0usize], grid, dark)
    try chart_svg.append(&writer, &map.ranges, blue)
    try chart_svg.append(&writer, &map.caps, dark)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..12usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[12usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_probability_plot_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/probability_plot.png"
    let plot = geometry.rect(68.0, 43.0, 248.0, 156.0)
    let sample = [12]f64{ -1.8f64, -1.3f64, -1.0f64, -0.7f64, -0.4f64, -0.2f64, 0.0f64, 0.3f64, 0.6f64, 0.9f64, 1.4f64, 1.9f64 }
    var points: [12]chart.Coord = zero
    var line: [1]chart.Segment = zero
    var probability_ticks: [7]chart.Tick = zero
    let (map, map_error) = chart.probability_plot(sample[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, plot, points[..], line[..], probability_ticks[..])
    if map_error != ok || map.observations.coords.len != sample.len || map.reference.segments.len != 1usize || map.probability_ticks.len != 7usize { ret chart.Invalid }
    let x_ticks = [5]chart.Tick{
        chart.Tick { value: -2.0, fraction: 0.1 },
        chart.Tick { value: -1.0, fraction: 0.3 },
        chart.Tick { value: 0.0, fraction: 0.5 },
        chart.Tick { value: 1.0, fraction: 0.7 },
        chart.Tick { value: 2.0, fraction: 0.9 },
    }
    let x_text = [5]str{ "-2", "-1", "0", "1", "2" }
    let y_text = [7]str{ "1%", "5%", "25%", "50%", "75%", "95%", "99%" }
    var labels: [14]chart.Label = zero
    labels[0usize] = chart.Label { text: "Normal probability plot", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center }
    var i = 0usize
    while i < y_text.len {
        labels[1usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 58.0, y: plot.y + plot.height * (1.0 - map.probability_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < x_text.len {
        labels[8usize + i] = chart.Label { text: x_text[i], anchor: chart.Coord { x: plot.x + plot.width * x_ticks[i].fraction, y: 215.0 }, align: .Center }
        i += 1usize
    }
    labels[13usize] = chart.Label { text: "Observed value / cumulative probability", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], map.probability_ticks, paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.reference, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.observations, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..13usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], map.probability_ticks, grid, dark)
    try chart_svg.append(&writer, &map.reference, orange)
    try chart_svg.append(&writer, &map.observations, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..13usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[13usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_weibull_probability_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/weibull_probability.png"
    let plot = geometry.rect(68.0, 48.0, 248.0, 151.0)
    let failures = [10]f64{ 54.0f64, 187.0f64, 216.0f64, 240.0f64, 244.0f64, 335.0f64, 361.0f64, 373.0f64, 375.0f64, 386.0f64 }
    var points: [10]chart.Coord = zero
    var line: [1]chart.Segment = zero
    var probability_ticks: [7]chart.Tick = zero
    let (map, map_error) = chart.weibull_probability_plot(failures[..], 20usize, 1.5f64, 500.0f64, 50.0f64, 800.0f64, plot, points[..], line[..], probability_ticks[..])
    if map_error != ok || map.observations.coords.len != failures.len { ret chart.Invalid }
    let x_ticks = [5]chart.Tick{
        chart.Tick { value: 50.0, fraction: 0.0 },
        chart.Tick { value: 100.0, fraction: 0.25 },
        chart.Tick { value: 200.0, fraction: 0.5 },
        chart.Tick { value: 500.0, fraction: 0.830482 },
        chart.Tick { value: 800.0, fraction: 1.0 },
    }
    let x_text = [5]str{ "50", "100", "200", "500", "800" }
    let y_text = [7]str{ "1%", "5%", "25%", "50%", "75%", "95%", "99%" }
    var labels: [15]chart.Label = zero
    labels[0usize] = chart.Label { text: "Weibull probability plot", anchor: chart.Coord { x: 180.0, y: 19.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "10 failures / 20 units; 10 censored at 500h", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center }
    var i = 0usize
    while i < y_text.len {
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 58.0, y: plot.y + plot.height * (1.0 - map.probability_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < x_text.len {
        labels[9usize + i] = chart.Label { text: x_text[i], anchor: chart.Coord { x: plot.x + plot.width * x_ticks[i].fraction, y: 215.0 }, align: .Center }
        i += 1usize
    }
    labels[14usize] = chart.Label { text: "Time (hours) / cumulative failure probability", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], map.probability_ticks, paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.reference, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.observations, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..14usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[14usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], map.probability_ticks, grid, dark)
    try chart_svg.append(&writer, &map.reference, orange)
    try chart_svg.append(&writer, &map.observations, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..14usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[14usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_oc_curve_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/oc_curve.png"
    let plot = geometry.rect(68.0, 48.0, 248.0, 151.0)
    var points: [13]chart.Coord = zero
    var segments: [12]chart.Segment = zero
    let (curve, curve_error) = chart.oc_curve(52usize, 3usize, 0.12f64, plot, points[..], segments[..])
    if curve_error != ok || curve.coords.len != 13usize { ret chart.Invalid }
    let x_ticks = [7]chart.Tick{
        chart.Tick { value: 0.0, fraction: 0.0 },
        chart.Tick { value: 0.02, fraction: 0.16666667 },
        chart.Tick { value: 0.04, fraction: 0.33333334 },
        chart.Tick { value: 0.06, fraction: 0.5 },
        chart.Tick { value: 0.08, fraction: 0.6666667 },
        chart.Tick { value: 0.10, fraction: 0.8333333 },
        chart.Tick { value: 0.12, fraction: 1.0 },
    }
    let y_ticks = [6]chart.Tick{
        chart.Tick { value: 0.0, fraction: 0.0 },
        chart.Tick { value: 0.2, fraction: 0.2 },
        chart.Tick { value: 0.4, fraction: 0.4 },
        chart.Tick { value: 0.6, fraction: 0.6 },
        chart.Tick { value: 0.8, fraction: 0.8 },
        chart.Tick { value: 1.0, fraction: 1.0 },
    }
    let x_text = [7]str{ "0", "2", "4", "6", "8", "10", "12%" }
    let y_text = [6]str{ "0%", "20%", "40%", "60%", "80%", "100%" }
    var labels: [16]chart.Label = zero
    labels[0usize] = chart.Label { text: "Operating-characteristic curve", anchor: chart.Coord { x: 180.0, y: 19.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Single sample / n=52, accept up to 3 defects", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center }
    var i = 0usize
    while i < y_text.len {
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 58.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < x_text.len {
        labels[8usize + i] = chart.Label { text: x_text[i], anchor: chart.Coord { x: plot.x + plot.width * x_ticks[i].fraction, y: 215.0 }, align: .Center }
        i += 1usize
    }
    labels[15usize] = chart.Label { text: "Lot defective % / probability of acceptance", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &curve, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..15usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[15usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &curve, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..15usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[15usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_gage_rr_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/gage_rr.png"
    let plot = geometry.rect(52.0, 48.0, 276.0, 128.0)
    let means = stat.GageRrMeanSquares { part: 9.81799f64, operator: 1.58363f64, interaction: 0.01994f64, repeatability: 0.03997f64 }
    let (components, component_error) = stat.gage_rr_variance_components(10usize, 3usize, 3usize, &means, false)
    if component_error != ok { ret component_error }
    var bars: [8]geometry.Rect = zero
    var percentages: [8]f32 = zero
    let (map, map_error) = chart.gage_rr_components(&components, plot, bars[..], percentages[..])
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 4.0, fraction: 1.0 } }
    let y_ticks = [5]chart.Tick{
        chart.Tick { value: 0.0, fraction: 0.0 },
        chart.Tick { value: 25.0, fraction: 0.25 },
        chart.Tick { value: 50.0, fraction: 0.5 },
        chart.Tick { value: 75.0, fraction: 0.75 },
        chart.Tick { value: 100.0, fraction: 1.0 },
    }
    let y_text = [5]str{ "0%", "25%", "50%", "75%", "100%" }
    let category_text = [4]str{ "Gage", "Repeat", "Reprod", "Part" }
    var labels: [14]chart.Label = zero
    labels[0usize] = chart.Label { text: "Gage R&R components", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Crossed ANOVA / 10 parts, 3 operators, 3 trials", anchor: chart.Coord { x: 180.0, y: 32.0 }, align: .Center }
    var i = 0usize
    while i < y_text.len {
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 43.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < category_text.len {
        labels[7usize + i] = chart.Label { text: category_text[i], anchor: chart.Coord { x: plot.x + plot.width * (f32(i) + 0.5) / 4.0, y: 190.0 }, align: .Center }
        i += 1usize
    }
    labels[11usize] = chart.Label { text: "Variance %", anchor: chart.Coord { x: 135.0, y: 210.0 }, align: .Left }
    labels[12usize] = chart.Label { text: "Study variation %", anchor: chart.Coord { x: 243.0, y: 210.0 }, align: .Left }
    labels[13usize] = chart.Label { text: "Source of variation / percent of total", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let blue_key = geometry.rect(112.0, 202.0, 10.0, 8.0)
    let orange_key = geometry.rect(220.0, 202.0, 10.0, 8.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.contribution, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.study_variation, paint.Brush { Solid: orange })
    try fill(&builder, blue_key, paint.Brush { Solid: blue })
    try fill(&builder, orange_key, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..13usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &map.contribution, blue)
    try chart_svg.append(&writer, &map.study_variation, orange)
    try chart_svg.rect(&writer, blue_key, blue, false)
    try chart_svg.rect(&writer, orange_key, orange, false)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..13usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[13usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_multi_vari_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/multi_vari.png"
    let plot = geometry.rect(45.0, 49.0, 270.0, 137.0)
    let readings = [12]f64{ 8.0f64, 10.0f64, 10.0f64, 12.0f64, 12.0f64, 14.0f64, 9.0f64, 11.0f64, 14.0f64, 16.0f64, 15.0f64, 17.0f64 }
    var raw_points: [12]chart.Coord = zero
    var cell_points: [6]chart.Coord = zero
    var cell_lines: [4]chart.Segment = zero
    var group_points: [2]chart.Coord = zero
    var group_lines: [1]chart.Segment = zero
    var cell_means: [6]f64 = zero
    var group_means: [2]f64 = zero
    var storage = chart.MultiVariStorage { raw_points: raw_points[..], cell_points: cell_points[..], cell_lines: cell_lines[..], group_points: group_points[..], group_lines: group_lines[..], cell_means: cell_means[..], group_means: group_means[..] }
    let (map, map_error) = chart.multi_vari(readings[..], 2usize, 3usize, 2usize, plot, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 6.0, fraction: 1.0 } }
    let y_ticks = [5]chart.Tick{
        chart.Tick { value: 8.0, fraction: 0.0 },
        chart.Tick { value: 10.0, fraction: 0.22222222 },
        chart.Tick { value: 12.0, fraction: 0.44444445 },
        chart.Tick { value: 14.0, fraction: 0.6666667 },
        chart.Tick { value: 16.0, fraction: 0.8888889 },
    }
    let y_text = [5]str{ "8", "10", "12", "14", "16" }
    let setting_text = [6]str{ "1", "2", "3", "1", "2", "3" }
    var labels: [16]chart.Label = zero
    labels[0usize] = chart.Label { text: "Multi-vari / machine and setting", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "2 machines / 3 settings / 2 readings each", anchor: chart.Coord { x: 180.0, y: 32.0 }, align: .Center }
    var i = 0usize
    while i < y_text.len {
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 36.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < setting_text.len {
        labels[7usize + i] = chart.Label { text: setting_text[i], anchor: chart.Coord { x: cell_points[i].x, y: 199.0 }, align: .Center }
        i += 1usize
    }
    labels[13usize] = chart.Label { text: "Machine A", anchor: chart.Coord { x: 112.5, y: 214.0 }, align: .Center }
    labels[14usize] = chart.Label { text: "Machine B", anchor: chart.Coord { x: 247.5, y: 214.0 }, align: .Center }
    labels[15usize] = chart.Label { text: "Gray: readings    Blue: setting means    Orange: machine means", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let gray = paint.rgba(0.63, 0.69, 0.76, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var divider_segment = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: 180.0, y: plot.y }, to: chart.Coord { x: 180.0, y: plot.y + plot.height } } }
    let divider = chart.Layout { kind: .Rug, coords: zero, segments: divider_segment[..], bars: zero, x_min: 0.0, x_max: 6.0, y_min: 8.0, y_max: 17.0 }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &divider, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.observations, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.within, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.cells, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.groups, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..15usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[15usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &divider, gray)
    try chart_svg.append(&writer, &map.observations, gray)
    try chart_svg.append(&writer, &map.within, blue)
    try chart_svg.append(&writer, &map.cells, blue)
    try chart_svg.append(&writer, &map.groups, orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..15usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[15usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_main_effects_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/main_effects.png"
    let plot = geometry.rect(45.0, 59.0, 270.0, 128.0)
    let readings = [5]f64{ 2.0f64, 4.0f64, 6.0f64, 8.0f64, 10.0f64 }
    let factor_ids = [10]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 0usize, 1usize, 1usize, 1usize, 1usize }
    let factor_levels = [2]usize{ 2usize, 2usize }
    var points: [4]chart.Coord = zero
    var lines: [2]chart.Segment = zero
    var references: [2]chart.Segment = zero
    var means: [4]f64 = zero
    var counts: [4]usize = zero
    var storage = chart.MainEffectsStorage { points: points[..], lines: lines[..], references: references[..], means: means[..], counts: counts[..] }
    let (map, map_error) = chart.main_effects(readings[..], factor_ids[..], factor_levels[..], plot, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 4.0, fraction: 1.0 } }
    let y_ticks = [5]chart.Tick{
        chart.Tick { value: 2.0, fraction: 0.0 },
        chart.Tick { value: 4.0, fraction: 0.25 },
        chart.Tick { value: 6.0, fraction: 0.5 },
        chart.Tick { value: 8.0, fraction: 0.75 },
        chart.Tick { value: 10.0, fraction: 1.0 },
    }
    let y_text = [5]str{ "2", "4", "6", "8", "10" }
    let level_text = [4]str{ "Low", "High", "Cool", "Hot" }
    var labels: [14]chart.Label = zero
    labels[0usize] = chart.Label { text: "Main effects / process and temperature", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Raw response means / unequal sample sizes", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    var i = 0usize
    while i < y_text.len {
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 36.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < level_text.len {
        labels[7usize + i] = chart.Label { text: level_text[i], anchor: chart.Coord { x: points[i].x, y: 201.0 }, align: .Center }
        i += 1usize
    }
    labels[11usize] = chart.Label { text: "Process", anchor: chart.Coord { x: 112.5, y: 216.0 }, align: .Center }
    labels[12usize] = chart.Label { text: "Temperature", anchor: chart.Coord { x: 247.5, y: 216.0 }, align: .Center }
    labels[13usize] = chart.Label { text: "Blue: level mean    Gray: overall mean (6)", anchor: chart.Coord { x: 180.0, y: 233.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let gray = paint.rgba(0.58, 0.65, 0.73, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var divider_segment = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: 180.0, y: plot.y }, to: chart.Coord { x: 180.0, y: plot.y + plot.height } } }
    let divider = chart.Layout { kind: .Rug, coords: zero, segments: divider_segment[..], bars: zero, x_min: 0.0, x_max: 4.0, y_min: 2.0, y_max: 10.0 }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &divider, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.reference, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.connections, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.levels, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..13usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &divider, gray)
    try chart_svg.append(&writer, &map.reference, gray)
    try chart_svg.append(&writer, &map.connections, blue)
    try chart_svg.append(&writer, &map.levels, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..13usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[13usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_anom_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/anom.png"
    let plot = geometry.rect(46.0, 53.0, 268.0, 133.0)
    let values = [15]f64{ 9.0f64, 10.0f64, 11.0f64, 10.0f64, 11.0f64, 12.0f64, 11.0f64, 12.0f64, 13.0f64, 10.0f64, 11.0f64, 12.0f64, 15.0f64, 16.0f64, 17.0f64 }
    let ids = [15]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 3usize, 3usize, 3usize, 4usize, 4usize, 4usize }
    var points: [5]chart.Coord = zero
    var signals: [5]chart.Coord = zero
    var upper: [5]chart.Segment = zero
    var lower: [5]chart.Segment = zero
    var center: [1]chart.Segment = zero
    var means: [5]f64 = zero
    var counts: [5]usize = zero
    var upper_limits: [5]f64 = zero
    var lower_limits: [5]f64 = zero
    var storage = chart.AnomStorage { points: points[..], signals: signals[..], upper: upper[..], lower: lower[..], center: center[..], means: means[..], counts: counts[..], upper_limits: upper_limits[..], lower_limits: lower_limits[..] }
    let (map, map_error) = chart.anom(values[..], ids[..], 5usize, 3.0f64, plot, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 5.0, fraction: 1.0 } }
    var y_ticks: [5]chart.Tick = zero
    let y_values = [5]f64{ 9.0f64, 11.0f64, 13.0f64, 15.0f64, 17.0f64 }
    let y_text = [5]str{ "9", "11", "13", "15", "17" }
    var labels: [16]chart.Label = zero
    labels[0usize] = chart.Label { text: "ANOM / group means vs decision limits", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "One-way normal data / pooled within-group SD", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    var i = 0usize
    while i < y_ticks.len {
        let fraction = f32((y_values[i] - f64(map.groups.y_min)) / f64(map.groups.y_max - map.groups.y_min))
        y_ticks[i] = chart.Tick { value: f32(y_values[i]), fraction: fraction }
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 37.0, y: plot.y + plot.height * (1.0 - fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    let group_text = [5]str{ "A", "B", "C", "D", "E" }
    i = 0usize
    while i < group_text.len {
        labels[7usize + i] = chart.Label { text: group_text[i], anchor: chart.Coord { x: points[i].x, y: 202.0 }, align: .Center }
        i += 1usize
    }
    labels[12usize] = chart.Label { text: "UDL", anchor: chart.Coord { x: 321.0, y: upper[4usize].from.y + 3.0 }, align: .Left }
    labels[13usize] = chart.Label { text: "CL", anchor: chart.Coord { x: 321.0, y: center[0usize].from.y + 3.0 }, align: .Left }
    labels[14usize] = chart.Label { text: "LDL", anchor: chart.Coord { x: 321.0, y: lower[4usize].from.y + 3.0 }, align: .Left }
    labels[15usize] = chart.Label { text: "Blue: mean   Red: outside decision limits   h = 3", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let red = paint.rgba(0.82, 0.19, 0.22, 1.0)
    let gray = paint.rgba(0.46, 0.54, 0.62, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.center, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.lower, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.groups, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.signals, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..15usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[15usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &map.center, gray)
    try chart_svg.append(&writer, &map.upper, red)
    try chart_svg.append(&writer, &map.lower, red)
    try chart_svg.append(&writer, &map.groups, blue)
    try chart_svg.append(&writer, &map.signals, red)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..15usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[15usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_hotelling_t2_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/hotelling_t2.png"
    let plot = geometry.rect(46.0, 53.0, 268.0, 133.0)
    let historical = [16]f64{ 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64, 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64 }
    let monitored = [16]f64{ 0.0f64, 0.0f64, 1.0f64, 1.0f64, 0.0f64, 2.0f64, 1.0f64, 1.0f64, 0.0f64, -1.0f64, 0.0f64, 0.0f64, 4.0f64, 4.0f64, 1.0f64, 0.0f64 }
    var means: [2]f64 = zero
    var covariance: [4]f64 = zero
    var factor: [4]f64 = zero
    var residual: [2]f64 = zero
    var scores: [8]f64 = zero
    var points: [8]chart.Coord = zero
    var segments: [7]chart.Segment = zero
    var signals: [8]chart.Coord = zero
    var upper: [1]chart.Segment = zero
    var storage = chart.HotellingStorage { means: means[..], covariance: covariance[..], factor: factor[..], residual: residual[..], scores: scores[..], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..] }
    let (map, map_error) = chart.hotelling_t2_individuals(monitored[..], 2usize, historical[..], 0.05f64, plot, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 8.0, fraction: 1.0 } }
    let tick_values = [4]f32{ 0.0, 10.0, 20.0, 30.0 }
    let tick_text = [4]str{ "0", "10", "20", "30" }
    var y_ticks: [4]chart.Tick = zero
    var labels: [11]chart.Label = zero
    labels[0usize] = chart.Label { text: "Hotelling T2 / correlated process", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Phase II individuals / 8 historical references", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    var i = 0usize
    while i < tick_values.len {
        let fraction = tick_values[i] / map.trace.y_max
        y_ticks[i] = chart.Tick { value: tick_values[i], fraction: fraction }
        labels[2usize + i] = chart.Label { text: tick_text[i], anchor: chart.Coord { x: 37.0, y: plot.y + plot.height * (1.0 - fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[6usize] = chart.Label { text: "1", anchor: chart.Coord { x: points[0usize].x, y: 202.0 }, align: .Center }
    labels[7usize] = chart.Label { text: "4", anchor: chart.Coord { x: points[3usize].x, y: 202.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "8", anchor: chart.Coord { x: points[7usize].x, y: 202.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "UCL", anchor: chart.Coord { x: 321.0, y: upper[0usize].from.y + 3.0 }, align: .Left }
    labels[10usize] = chart.Label { text: "Red: T2 beyond Phase II limit / alpha = 0.05", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let red = paint.rgba(0.82, 0.19, 0.22, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.trace, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.signals, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..10usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[10usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &map.upper, red)
    try chart_svg.append(&writer, &map.trace, blue)
    try chart_svg.append(&writer, &map.signals, red)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..10usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[10usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_generalized_variance_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/generalized_variance.png"
    let plot = geometry.rect(46.0, 53.0, 268.0, 133.0)
    let scales = [8]f64{ 1.0f64, 1.1f64, 0.9f64, 1.05f64, 1.05f64, 0.95f64, 1.1f64, 2.0f64 }
    let base_x = [5]f64{ 1.0f64, -1.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let base_y = [5]f64{ 0.0f64, 0.0f64, 1.0f64, -1.0f64, 0.0f64 }
    var phase_one: [40]f64 = zero
    var phase_two: [40]f64 = zero
    var group = 0usize
    while group < scales.len {
        var row = 0usize
        while row < base_x.len {
            var source = phase_one[..]
            var local_group = group
            if group >= 4usize {
                source = phase_two[..]
                local_group = group - 4usize
            }
            source[local_group * 10usize + row * 2usize] = scales[group] * base_x[row]
            source[local_group * 10usize + row * 2usize + 1usize] = scales[group] * base_y[row]
            row += 1usize
        }
        group += 1usize
    }
    var covariance: [4]f64 = zero
    var pooled: [4]f64 = zero
    var factor: [4]f64 = zero
    var determinants: [8]f64 = zero
    var points: [8]chart.Coord = zero
    var segments: [7]chart.Segment = zero
    var signals: [8]chart.Coord = zero
    var upper: [1]chart.Segment = zero
    var lower: [1]chart.Segment = zero
    var center: [1]chart.Segment = zero
    var storage = chart.GeneralizedVarianceStorage { covariance: covariance[..], pooled: pooled[..], factor: factor[..], determinants: determinants[..], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..], lower: lower[..], center: center[..] }
    let (map, map_error) = chart.generalized_variance(phase_one[..], phase_two[..], 5usize, 2usize, 0.0027f64, false, plot, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 8.0, fraction: 1.0 } }
    let tick_values = [5]f32{ 0.0, 1.0, 2.0, 3.0, 4.0 }
    let tick_text = [5]str{ "0", "1", "2", "3", "4" }
    var y_ticks: [5]chart.Tick = zero
    var labels: [14]chart.Label = zero
    labels[0usize] = chart.Label { text: "Generalized variance / covariance spread", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Four baseline and four monitored subgroups", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    var i = 0usize
    while i < tick_values.len {
        let fraction = tick_values[i] / map.trace.y_max
        y_ticks[i] = chart.Tick { value: tick_values[i], fraction: fraction }
        labels[2usize + i] = chart.Label { text: tick_text[i], anchor: chart.Coord { x: 37.0, y: plot.y + plot.height * (1.0 - fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[7usize] = chart.Label { text: "1", anchor: chart.Coord { x: points[0usize].x, y: 202.0 }, align: .Center }
    labels[8usize] = chart.Label { text: "4", anchor: chart.Coord { x: points[3usize].x, y: 202.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "5", anchor: chart.Coord { x: points[4usize].x, y: 202.0 }, align: .Center }
    labels[10usize] = chart.Label { text: "8", anchor: chart.Coord { x: points[7usize].x, y: 202.0 }, align: .Center }
    labels[11usize] = chart.Label { text: "UCL", anchor: chart.Coord { x: 321.0, y: upper[0usize].from.y + 3.0 }, align: .Left }
    labels[12usize] = chart.Label { text: "CL", anchor: chart.Coord { x: 321.0, y: center[0usize].from.y + 3.0 }, align: .Left }
    labels[13usize] = chart.Label { text: "Moment-normal limit / alpha = 0.0027", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let red = paint.rgba(0.82, 0.19, 0.22, 1.0)
    let gray = paint.rgba(0.46, 0.54, 0.62, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    var divider_segment = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: plot.x + plot.width * 0.5, y: plot.y }, to: chart.Coord { x: plot.x + plot.width * 0.5, y: plot.y + plot.height } } }
    let divider = chart.Layout { kind: .Rug, coords: zero, segments: divider_segment[..], bars: zero, x_min: 0.0, x_max: 8.0, y_min: 0.0, y_max: map.trace.y_max }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &divider, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.center, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.trace, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.signals, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..13usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &divider, gray)
    try chart_svg.append(&writer, &map.upper, red)
    try chart_svg.append(&writer, &map.center, gray)
    try chart_svg.append(&writer, &map.trace, blue)
    try chart_svg.append(&writer, &map.signals, red)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..13usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[13usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_mewma_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/mewma.png"
    let plot = geometry.rect(46.0, 53.0, 268.0, 133.0)
    let historical = [16]f64{ 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64, 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64 }
    var monitored: [24]f64 = zero
    var i = 0usize
    while i < 12usize {
        let value = 0.2f64 * f64(i)
        monitored[i * 2usize] = value
        monitored[i * 2usize + 1usize] = value
        i += 1usize
    }
    var means: [2]f64 = zero
    var covariance: [4]f64 = zero
    var factor: [4]f64 = zero
    var state: [2]f64 = zero
    var residual: [2]f64 = zero
    var smoothed: [24]f64 = zero
    var scores: [12]f64 = zero
    var points: [12]chart.Coord = zero
    var segments: [11]chart.Segment = zero
    var signals: [12]chart.Coord = zero
    var upper: [1]chart.Segment = zero
    var storage = chart.MewmaStorage { means: means[..], covariance: covariance[..], factor: factor[..], state: state[..], residual: residual[..], smoothed: smoothed[..], scores: scores[..], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..] }
    let (map, map_error) = chart.mewma(monitored[..], 2usize, historical[..], 0.25f64, 10.0f64, plot, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 12.0, fraction: 1.0 } }
    let tick_values = [6]f32{ 0.0, 5.0, 10.0, 15.0, 20.0, 25.0 }
    let tick_text = [6]str{ "0", "5", "10", "15", "20", "25" }
    var y_ticks: [6]chart.Tick = zero
    var labels: [14]chart.Label = zero
    labels[0usize] = chart.Label { text: "MEWMA / gradual correlated drift", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Phase II / lambda = 0.25 / finite-time covariance", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    i = 0usize
    while i < tick_values.len {
        let fraction = tick_values[i] / map.trace.y_max
        y_ticks[i] = chart.Tick { value: tick_values[i], fraction: fraction }
        labels[2usize + i] = chart.Label { text: tick_text[i], anchor: chart.Coord { x: 37.0, y: plot.y + plot.height * (1.0 - fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[8usize] = chart.Label { text: "1", anchor: chart.Coord { x: points[0usize].x, y: 202.0 }, align: .Center }
    labels[9usize] = chart.Label { text: "4", anchor: chart.Coord { x: points[3usize].x, y: 202.0 }, align: .Center }
    labels[10usize] = chart.Label { text: "8", anchor: chart.Coord { x: points[7usize].x, y: 202.0 }, align: .Center }
    labels[11usize] = chart.Label { text: "12", anchor: chart.Coord { x: points[11usize].x, y: 202.0 }, align: .Center }
    labels[12usize] = chart.Label { text: "UCL", anchor: chart.Coord { x: 321.0, y: upper[0usize].from.y + 3.0 }, align: .Left }
    labels[13usize] = chart.Label { text: "Caller-selected UCL = 10 / ARL calibration external", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let red = paint.rgba(0.82, 0.19, 0.22, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.trace, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.signals, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..13usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[13usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &map.upper, red)
    try chart_svg.append(&writer, &map.trace, blue)
    try chart_svg.append(&writer, &map.signals, red)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..13usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[13usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_interaction_plot_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/interaction_plot.png"
    let plot = geometry.rect(45.0, 54.0, 270.0, 136.0)
    let readings = [8]f64{ 2.0f64, 4.0f64, 5.0f64, 9.0f64, 10.0f64, 8.0f64, 3.0f64, 5.0f64 }
    let x_ids = [8]usize{ 0usize, 0usize, 1usize, 2usize, 0usize, 1usize, 2usize, 2usize }
    let series_ids = [8]usize{ 0usize, 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 1usize }
    var points: [6]chart.Coord = zero
    var lines: [4]chart.Segment = zero
    var means: [6]f64 = zero
    var counts: [6]usize = zero
    var series: [2]chart.Layout = zero
    var storage = chart.InteractionStorage { points: points[..], lines: lines[..], means: means[..], counts: counts[..], series: series[..] }
    let (map, map_error) = chart.interaction_plot(readings[..], x_ids[..], series_ids[..], 3usize, 2usize, plot, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [2]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 3.0, fraction: 1.0 } }
    let y_ticks = [5]chart.Tick{
        chart.Tick { value: 2.0, fraction: 0.0 },
        chart.Tick { value: 4.0, fraction: 0.25 },
        chart.Tick { value: 6.0, fraction: 0.5 },
        chart.Tick { value: 8.0, fraction: 0.75 },
        chart.Tick { value: 10.0, fraction: 1.0 },
    }
    let y_text = [5]str{ "2", "4", "6", "8", "10" }
    let level_text = [3]str{ "Low", "Medium", "High" }
    var labels: [11]chart.Label = zero
    labels[0usize] = chart.Label { text: "Interaction / setting by method", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Nonparallel lines indicate differing level responses", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    var i = 0usize
    while i < y_text.len {
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 36.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < level_text.len {
        labels[7usize + i] = chart.Label { text: level_text[i], anchor: chart.Coord { x: points[i].x, y: 204.0 }, align: .Center }
        i += 1usize
    }
    labels[10usize] = chart.Label { text: "Blue: Method A    Orange: Method B", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.series[0usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.series[1usize], paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..10usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[10usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &map.series[0usize], blue)
    try chart_svg.append(&writer, &map.series[1usize], orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_cube_plot_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/cube_plot.png"
    let bounds = geometry.rect(55.0, 47.0, 250.0, 150.0)
    let readings = [9]f64{ 1.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64, 7.0f64, 8.0f64, 9.0f64, 10.0f64 }
    let ids = [27]usize{
        0usize, 0usize, 0usize, 0usize, 0usize, 0usize,
        1usize, 0usize, 0usize, 0usize, 1usize, 0usize,
        1usize, 1usize, 0usize, 0usize, 0usize, 1usize,
        1usize, 0usize, 1usize, 0usize, 1usize, 1usize,
        1usize, 1usize, 1usize,
    }
    var vertices: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var means: [8]f64 = zero
    var counts: [8]usize = zero
    var storage = chart.CubePlotStorage { vertices: vertices[..], edges: edges[..], means: means[..], counts: counts[..] }
    let (map, map_error) = chart.cube_plot(readings[..], ids[..], bounds, &storage)
    if map_error != ok { ret map_error }
    let value_text = [8]str{ "2", "4", "5", "6", "7", "8", "9", "10" }
    let offset_x = [8]f32{ -12.0, 12.0, -12.0, 12.0, -12.0, 12.0, -12.0, 12.0 }
    let offset_y = [8]f32{ 12.0, 12.0, -8.0, -8.0, 12.0, 12.0, -8.0, -8.0 }
    var labels: [11]chart.Label = zero
    labels[0usize] = chart.Label { text: "Cube plot / three two-level factors", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Raw response mean at each corner", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    var i = 0usize
    while i < value_text.len {
        labels[2usize + i] = chart.Label { text: value_text[i], anchor: chart.Coord { x: vertices[i].x + offset_x[i], y: vertices[i].y + offset_y[i] }, align: .Center }
        i += 1usize
    }
    labels[10usize] = chart.Label { text: "A: horizontal   B: vertical   C: depth", anchor: chart.Coord { x: 180.0, y: 228.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let gray = paint.rgba(0.58, 0.65, 0.73, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &map.frame, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.vertices, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..10usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[10usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &map.frame, gray)
    try chart_svg.append(&writer, &map.vertices, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..10usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[10usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_spectrogram_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/spectrogram.png"
    let plot = geometry.rect(45.0, 51.0, 270.0, 138.0)
    var samples: [512]f64 = zero
    var phase = 0.0f64
    var i = 0usize
    while i < samples.len {
        let time = f64(i) / 256.0f64
        let frequency = 24.0f64 + 38.0f64 * time
        phase += 6.283185307179586f64 * frequency / 256.0f64
        samples[i] = math.sin[f64](phase) + 0.35f64 * math.sin[f64](6.283185307179586f64 * 12.0f64 * time)
        i += 1usize
    }
    var win: [64]f64 = zero
    try dsp.window(.Hann, 64usize, win[..])
    var re: [1856]f64 = zero
    var im: [1856]f64 = zero
    let (frames, transform_error) = dsp.stft(samples[..], 64usize, 16usize, win[..], re[..], im[..])
    if transform_error != ok { ret transform_error }
    var cells: [957]chart.Cell = zero
    let (map, map_error) = chart.spectrogram(re[..], im[..], frames, 64usize, 16usize, 256.0f64, 0.000001f64, plot, cells[..])
    if map_error != ok { ret map_error }
    let x_ticks = [3]chart.Tick{ chart.Tick { value: 0.125, fraction: 0.0 }, chart.Tick { value: 1.0, fraction: 0.5 }, chart.Tick { value: 1.875, fraction: 1.0 } }
    let y_ticks = [5]chart.Tick{
        chart.Tick { value: 0.0, fraction: 0.0 },
        chart.Tick { value: 32.0, fraction: 0.25 },
        chart.Tick { value: 64.0, fraction: 0.5 },
        chart.Tick { value: 96.0, fraction: 0.75 },
        chart.Tick { value: 128.0, fraction: 1.0 },
    }
    let y_text = [5]str{ "0", "32", "64", "96", "128" }
    let x_text = [3]str{ "0.125", "1.0", "1.875" }
    var labels: [11]chart.Label = zero
    labels[0usize] = chart.Label { text: "Spectrogram / rising tone", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "One-sided STFT power (dB) / 256 Hz samples", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    i = 0usize
    while i < y_text.len {
        labels[2usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 36.0, y: plot.y + plot.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < x_text.len {
        labels[7usize + i] = chart.Label { text: x_text[i], anchor: chart.Coord { x: plot.x + plot.width * x_ticks[i].fraction, y: 204.0 }, align: .Center }
        i += 1usize
    }
    labels[10usize] = chart.Label { text: "Time (s)    /    Frequency (Hz)    /    Yellow = stronger", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let low = paint.rgba(0.02, 0.08, 0.22, 1.0)
    let high = paint.rgba(1.0, 0.78, 0.18, 1.0)
    let middle = paint.rgba(0.0, 0.5, 0.75, 1.0)
    let grid = paint.rgba(0.35, 0.46, 0.56, 0.65)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 1200usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append_matrix(&builder, &map.matrix, low, middle, high)
    try chart_scene.append_guides(&builder, plot, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..10usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[10usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_matrix(&writer, &map.matrix, low, middle, high)
    try chart_svg.append_guides(&writer, plot, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..10usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[10usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_waterfall_spectrum_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/waterfall_spectrum.png"
    let plot = geometry.rect(30.0, 47.0, 300.0, 154.0)
    var samples: [512]f64 = zero
    var phase = 0.0f64
    var i = 0usize
    while i < samples.len {
        let time = f64(i) / 256.0f64
        let frequency = 24.0f64 + 38.0f64 * time
        phase += 6.283185307179586f64 * frequency / 256.0f64
        samples[i] = math.sin[f64](phase) + 0.35f64 * math.sin[f64](6.283185307179586f64 * 12.0f64 * time)
        i += 1usize
    }
    var win: [64]f64 = zero
    try dsp.window(.Hann, 64usize, win[..])
    var re: [1856]f64 = zero
    var im: [1856]f64 = zero
    let (frames, transform_error) = dsp.stft(samples[..], 64usize, 16usize, win[..], re[..], im[..])
    if transform_error != ok { ret transform_error }
    var cells: [957]chart.Cell = zero
    let (spectrum, spectrum_error) = chart.spectrogram(re[..], im[..], frames, 64usize, 16usize, 256.0f64, 0.000001f64, plot, cells[..])
    if spectrum_error != ok { ret spectrum_error }
    var points: [264]chart.Coord = zero
    var segments: [256]chart.Segment = zero
    var traces: [8]chart.Layout = zero
    var frame_indices: [8]usize = zero
    var storage = chart.WaterfallSpectrumStorage { points: points[..], segments: segments[..], traces: traces[..], frame_indices: frame_indices[..] }
    let (map, map_error) = chart.waterfall_spectrum(&spectrum, 4usize, plot, &storage)
    if map_error != ok { ret map_error }
    var axes = [2]chart.Segment{
        chart.Segment { from: chart.Coord { x: 57.0, y: 182.52 }, to: chart.Coord { x: 261.0, y: 182.52 } },
        chart.Segment { from: chart.Coord { x: 57.0, y: 182.52 }, to: chart.Coord { x: 111.0, y: 124.0 } },
    }
    let guides = chart.Layout { kind: .Rug, coords: zero, segments: axes[..], bars: zero, x_min: 0.0, x_max: 128.0, y_min: map.value_min, y_max: map.value_max }
    var labels: [6]chart.Label = zero
    labels[0usize] = chart.Label { text: "Waterfall spectrum / rising tone", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Frequency traces sampled across time", anchor: chart.Coord { x: 180.0, y: 34.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "0", anchor: chart.Coord { x: 57.0, y: 205.0 }, align: .Center }
    labels[3usize] = chart.Label { text: "64", anchor: chart.Coord { x: 159.0, y: 205.0 }, align: .Center }
    labels[4usize] = chart.Label { text: "128 Hz", anchor: chart.Coord { x: 261.0, y: 205.0 }, align: .Center }
    labels[5usize] = chart.Label { text: "Blue: early    Orange: later    Height: power dB", anchor: chart.Coord { x: 180.0, y: 229.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let gray = paint.rgba(0.58, 0.65, 0.73, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &guides, paint.Brush { Solid: gray })
    i = 0usize
    while i < map.traces.len {
        let color = paint.mix(blue, orange, f32(i) / f32(map.traces.len - 1usize))
        try chart_scene.append(a, &builder, &map.traces[i], paint.Brush { Solid: color })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..5usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[5usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &guides, gray)
    i = 0usize
    while i < map.traces.len {
        let color = paint.mix(blue, orange, f32(i) / f32(map.traces.len - 1usize))
        try chart_svg.append(&writer, &map.traces[i], color)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..5usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[5usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_bode_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/bode.png"
    let bounds = geometry.rect(45.0, 48.0, 270.0, 142.0)
    var frequency: [61]f64 = zero
    var real: [61]f64 = zero
    var imag: [61]f64 = zero
    var i = 0usize
    while i < frequency.len {
        let exponent = -1.0f64 + 3.0f64 * f64(i) / 60.0f64
        let omega = math.pow[f64](10.0f64, exponent)
        let ratio = omega / 10.0f64
        let denominator = 1.0f64 + ratio * ratio
        frequency[i] = omega
        real[i] = 1.0f64 / denominator
        imag[i] = -ratio / denominator
        i += 1usize
    }
    var magnitude_points: [61]chart.Coord = zero
    var magnitude_segments: [60]chart.Segment = zero
    var phase_points: [61]chart.Coord = zero
    var phase_segments: [60]chart.Segment = zero
    var magnitude_db: [61]f64 = zero
    var phase_degrees: [61]f64 = zero
    var storage = chart.BodeStorage { magnitude_points: magnitude_points[..], magnitude_segments: magnitude_segments[..], phase_points: phase_points[..], phase_segments: phase_segments[..], magnitude_db: magnitude_db[..], phase_degrees: phase_degrees[..] }
    let (map, map_error) = chart.bode(frequency[..], real[..], imag[..], 0.000001f64, bounds, &storage)
    if map_error != ok { ret map_error }
    let x_ticks = [4]chart.Tick{
        chart.Tick { value: 0.1, fraction: 0.0 }, chart.Tick { value: 1.0, fraction: 0.33333334 },
        chart.Tick { value: 10.0, fraction: 0.6666667 }, chart.Tick { value: 100.0, fraction: 1.0 },
    }
    let y_ticks = [3]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 0.5, fraction: 0.5 }, chart.Tick { value: 1.0, fraction: 1.0 } }
    let magnitude_text = [3]str{ "-20", "-10", "0" }
    let phase_text = [3]str{ "-84", "-42", "0" }
    let frequency_text = [4]str{ "0.1", "1", "10", "100" }
    var labels: [13]chart.Label = zero
    labels[0usize] = chart.Label { text: "Bode / first-order low-pass", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Corner 10 rad/s / sampled complex response", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center }
    i = 0usize
    while i < magnitude_text.len {
        labels[2usize + i] = chart.Label { text: magnitude_text[i], anchor: chart.Coord { x: 36.0, y: map.magnitude_bounds.y + map.magnitude_bounds.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        labels[5usize + i] = chart.Label { text: phase_text[i], anchor: chart.Coord { x: 36.0, y: map.phase_bounds.y + map.phase_bounds.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    i = 0usize
    while i < frequency_text.len {
        labels[8usize + i] = chart.Label { text: frequency_text[i], anchor: chart.Coord { x: bounds.x + bounds.width * x_ticks[i].fraction, y: 202.0 }, align: .Center }
        i += 1usize
    }
    labels[12usize] = chart.Label { text: "Blue: magnitude dB    Orange: unwrapped phase deg", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, map.magnitude_bounds, paint.Brush { Solid: pale })
    try fill(&builder, map.phase_bounds, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, map.magnitude_bounds, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append_guides(&builder, map.phase_bounds, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.magnitude, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.phase, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..12usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[12usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, map.magnitude_bounds, pale, false)
    try chart_svg.rect(&writer, map.phase_bounds, pale, false)
    try chart_svg.append_guides(&writer, map.magnitude_bounds, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append_guides(&writer, map.phase_bounds, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &map.magnitude, blue)
    try chart_svg.append(&writer, &map.phase, orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..12usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[12usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_nyquist_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/nyquist.png"
    let bounds = geometry.rect(45.0, 48.0, 270.0, 148.0)
    var frequency: [61]f64 = zero
    var real: [61]f64 = zero
    var imag: [61]f64 = zero
    var i = 0usize
    while i < frequency.len {
        let omega = math.pow[f64](10.0f64, -2.0f64 + 4.0f64 * f64(i) / 60.0f64)
        let square = omega * omega
        let denominator = (1.0f64 + square) * (1.0f64 + square)
        frequency[i] = omega
        real[i] = 4.0f64 * (1.0f64 - square) / denominator
        imag[i] = -8.0f64 * omega / denominator
        i += 1usize
    }
    var positive_points: [61]chart.Coord = zero
    var positive_segments: [60]chart.Segment = zero
    var negative_points: [61]chart.Coord = zero
    var negative_segments: [60]chart.Segment = zero
    var critical_point: [1]chart.Coord = zero
    var storage = chart.NyquistStorage { positive_points: positive_points[..], positive_segments: positive_segments[..], negative_points: negative_points[..], negative_segments: negative_segments[..], critical_point: critical_point[..] }
    let (map, map_error) = chart.nyquist(frequency[..], real[..], imag[..], bounds, &storage)
    if map_error != ok { ret map_error }
    let x_values = [4]f32{ -1.0, 0.0, 2.0, 4.0 }
    let x_text = [4]str{ "-1", "0", "2", "4" }
    let y_values = [3]f32{ -2.0, 0.0, 2.0 }
    let y_text = [3]str{ "-2", "0", "2" }
    var x_ticks: [4]chart.Tick = zero
    var y_ticks: [3]chart.Tick = zero
    var labels: [10]chart.Label = zero
    labels[0usize] = chart.Label { text: "Nyquist / second-order response", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "G(jw) = 4 / (1 + jw)^2", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center }
    i = 0usize
    while i < x_ticks.len {
        x_ticks[i] = chart.Tick { value: x_values[i], fraction: (x_values[i] - map.positive.x_min) / (map.positive.x_max - map.positive.x_min) }
        labels[2usize + i] = chart.Label { text: x_text[i], anchor: chart.Coord { x: bounds.x + bounds.width * x_ticks[i].fraction, y: 208.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < y_ticks.len {
        y_ticks[i] = chart.Tick { value: y_values[i], fraction: (y_values[i] - map.positive.y_min) / (map.positive.y_max - map.positive.y_min) }
        labels[6usize + i] = chart.Label { text: y_text[i], anchor: chart.Coord { x: 36.0, y: bounds.y + bounds.height * (1.0 - y_ticks[i].fraction) + 3.0 }, align: .Right }
        i += 1usize
    }
    labels[9usize] = chart.Label { text: "Blue: +w    Orange: -w    Red: critical (-1, 0)", anchor: chart.Coord { x: 180.0, y: 229.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let orange = paint.rgba(0.91, 0.34, 0.16, 1.0)
    let red = paint.rgba(0.75, 0.1, 0.18, 1.0)
    let grid = paint.rgba(0.87, 0.91, 0.95, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, bounds, paint.Brush { Solid: pale })
    try chart_scene.append_guides(&builder, bounds, x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.positive, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.negative, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.critical, paint.Brush { Solid: red })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..9usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[9usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, bounds, pale, false)
    try chart_svg.append_guides(&writer, bounds, x_ticks[..], y_ticks[..], grid, dark)
    try chart_svg.append(&writer, &map.positive, blue)
    try chart_svg.append(&writer, &map.negative, orange)
    try chart_svg.append(&writer, &map.critical, red)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..9usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[9usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_scatter3d_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/scatter3d.png"
    let bounds = geometry.rect(45.0, 48.0, 270.0, 150.0)
    var x: [73]f64 = zero
    var y: [73]f64 = zero
    var z: [73]f64 = zero
    var i = 0usize
    while i < x.len {
        let t = 12.566370614359172f64 * f64(i) / 72.0f64
        x[i] = math.cos[f64](t)
        y[i] = math.sin[f64](t)
        z[i] = -1.0f64 + 2.0f64 * f64(i) / 72.0f64
        i += 1usize
    }
    var points: [73]chart.Coord = zero
    var depths: [73]f64 = zero
    var order: [73]usize = zero
    var bubbles: [73]geometry.Rect = zero
    var corners: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var storage = chart.Scatter3dStorage { points: points[..], depths: depths[..], order: order[..], bubbles: bubbles[..], corners: corners[..], edges: edges[..] }
    let camera = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 27.0f64, distance: 4.5f64 }
    let (map, map_error) = chart.scatter3d(x[..], y[..], z[..], camera, bounds, &storage)
    if map_error != ok { ret map_error }
    var labels: [6]chart.Label = zero
    labels[0usize] = chart.Label { text: "3-D scatter / projected helix", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Camera: azimuth 42 deg / elevation 27 deg", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "x", anchor: chart.Coord { x: map.corners[1usize].x + 6.0, y: map.corners[1usize].y + 5.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "y", anchor: chart.Coord { x: map.corners[2usize].x - 6.0, y: map.corners[2usize].y + 5.0 }, align: .Right }
    labels[4usize] = chart.Label { text: "z", anchor: chart.Coord { x: map.corners[4usize].x - 6.0, y: map.corners[4usize].y - 5.0 }, align: .Right }
    labels[5usize] = chart.Label { text: "Perspective size + far-to-near marker order", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let gray = paint.rgba(0.68, 0.75, 0.82, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, bounds, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &map.frame, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..5usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[5usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, bounds, pale, false)
    try chart_svg.append(&writer, &map.frame, gray)
    try chart_svg.append(&writer, &map.marks, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..5usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[5usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_histogram3d_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/histogram3d.png"
    let bounds = geometry.rect(45.0, 48.0, 270.0, 150.0)
    var x: [120]f32 = zero
    var y: [120]f32 = zero
    var i = 0usize
    while i < x.len {
        let radius = 0.04f64 + 0.55f64 * f64((i * 29usize) % 101usize) / 101.0f64
        let angle = 6.283185307179586f64 * f64((i * 37usize) % 101usize) / 101.0f64
        var cx = -0.28f64
        var cy = -0.2f64
        if i >= 60usize {
            cx = 0.34f64
            cy = 0.28f64
        }
        x[i] = f32(cx + radius * math.cos[f64](angle))
        y[i] = f32(cy + radius * math.sin[f64](angle))
        i += 1usize
    }
    var counts: [25]u64 = zero
    var cells: [25]chart.Cell = zero
    var vertices: [300]chart.Coord = zero
    var faces: [75]chart.Layout = zero
    var depths: [75]f64 = zero
    var order: [75]usize = zero
    var kinds: [75]chart.Histogram3dFace = zero
    var corners: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var storage = chart.Histogram3dStorage { counts: counts[..], cells: cells[..], vertices: vertices[..], faces: faces[..], depths: depths[..], order: order[..], face_kinds: kinds[..], corners: corners[..], edges: edges[..] }
    let camera = chart.Camera3d { azimuth_degrees: 46.0f64, elevation_degrees: 32.0f64, distance: 5.0f64 }
    let (map, map_error) = chart.histogram3d(x[..], y[..], -1.0, 1.0, -1.0, 1.0, 5usize, 5usize, camera, bounds, &storage)
    if map_error != ok { ret map_error }
    var labels: [6]chart.Label = zero
    labels[0usize] = chart.Label { text: "3-D histogram / joint x-y counts", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "5 x 5 bins / 120 observations", anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "x", anchor: chart.Coord { x: map.corners[1usize].x + 6.0, y: map.corners[1usize].y + 5.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "y", anchor: chart.Coord { x: map.corners[2usize].x - 6.0, y: map.corners[2usize].y + 5.0 }, align: .Right }
    labels[4usize] = chart.Label { text: "count", anchor: chart.Coord { x: map.corners[4usize].x - 6.0, y: map.corners[4usize].y - 5.0 }, align: .Right }
    labels[5usize] = chart.Label { text: "Prism height = observations per x-y bin", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let top = paint.rgba(0.43, 0.68, 0.88, 1.0)
    let x_side = paint.rgba(0.10, 0.36, 0.66, 1.0)
    let y_side = paint.rgba(0.18, 0.48, 0.75, 1.0)
    let gray = paint.rgba(0.70, 0.77, 0.83, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, bounds, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &map.frame, paint.Brush { Solid: gray })
    i = 0usize
    while i < map.order.len {
        let face = map.order[i]
        var ink = top
        if map.face_kinds[face] == .XSide { ink = x_side }
        if map.face_kinds[face] == .YSide { ink = y_side }
        try chart_scene.append(a, &builder, &map.faces[face], paint.Brush { Solid: ink })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..5usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[5usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, bounds, pale, false)
    try chart_svg.append(&writer, &map.frame, gray)
    i = 0usize
    while i < map.order.len {
        let face = map.order[i]
        var ink = top
        if map.face_kinds[face] == .XSide { ink = x_side }
        if map.face_kinds[face] == .YSide { ink = y_side }
        try chart_svg.append(&writer, &map.faces[face], ink)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..5usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[5usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_surface3d_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, density: bool) -> err {
    var path = "docs/chart-previews/density_surface3d.png"
    if !density { path = "docs/chart-previews/wireframe3d.png" }
    let bounds = geometry.rect(45.0, 48.0, 270.0, 150.0)
    var values: [81]f64 = zero
    var points: [81]chart.Coord = zero
    var depths: [81]f64 = zero
    var face_vertices: [256]chart.Coord = zero
    var faces: [64]chart.Layout = zero
    var face_depths: [64]f64 = zero
    var face_values: [64]f64 = zero
    var order: [64]usize = zero
    var wires: [144]chart.Segment = zero
    var corners: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var storage = chart.Surface3dStorage { points: points[..], depths: depths[..], face_vertices: face_vertices[..], faces: faces[..], face_depths: face_depths[..], face_values: face_values[..], order: order[..], wires: wires[..], corners: corners[..], edges: edges[..] }
    let camera = chart.Camera3d { azimuth_degrees: 46.0f64, elevation_degrees: 31.0f64, distance: 5.0f64 }
    var map: chart.Surface3dLayout = zero
    if density {
        var sample_x: [64]f64 = zero
        var sample_y: [64]f64 = zero
        var i = 0usize
        while i < sample_x.len {
            let angle = 6.283185307179586f64 * f64((i * 19usize) % 31usize) / 31.0f64
            let radius = 0.03f64 + 0.28f64 * f64((i * 17usize) % 31usize) / 31.0f64
            var cx = -0.35f64
            var cy = -0.22f64
            if i >= 32usize {
                cx = 0.38f64
                cy = 0.31f64
            }
            sample_x[i] = cx + radius * math.cos[f64](angle)
            sample_y[i] = cy + radius * math.sin[f64](angle)
            i += 1usize
        }
        var grid_x: [9]f64 = zero
        var grid_y: [9]f64 = zero
        let (made, map_error) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.24f64, 0.24f64, camera, bounds, grid_x[..], grid_y[..], values[..], &storage)
        if map_error != ok { ret map_error }
        map = made
    } else {
        var row = 0usize
        while row < 9usize {
            var column = 0usize
            while column < 9usize {
                let xx = -1.0f64 + 2.0f64 * f64(column) / 8.0f64
                let yy = 1.0f64 - 2.0f64 * f64(row) / 8.0f64
                let dx1 = xx + 0.35f64
                let dy1 = yy + 0.25f64
                let dx2 = xx - 0.4f64
                let dy2 = yy - 0.35f64
                values[row * 9usize + column] = math.exp[f64](-4.0f64 * (dx1 * dx1 + dy1 * dy1)) + 0.75f64 * math.exp[f64](-5.0f64 * (dx2 * dx2 + dy2 * dy2))
                column += 1usize
            }
            row += 1usize
        }
        let (made, map_error) = chart.wireframe3d(values[..], 9usize, camera, bounds, &storage)
        if map_error != ok { ret map_error }
        map = made
    }
    var labels: [6]chart.Label = zero
    var subtitle = "Product-Gaussian KDE / 64 observations"
    var footer = "Height = estimated joint density"
    labels[0usize] = chart.Label { text: "3-D density surface / twin peaks", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    if !density {
        labels[0usize] = chart.Label { text: "3-D wireframe / twin peaks", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
        subtitle = "9 x 9 sampled scalar grid"
        footer = "Row and column traces share a perspective camera"
    }
    labels[1usize] = chart.Label { text: subtitle, anchor: chart.Coord { x: 180.0, y: 33.0 }, align: .Center }
    labels[2usize] = chart.Label { text: "x", anchor: chart.Coord { x: map.corners[1usize].x + 6.0, y: map.corners[1usize].y + 5.0 }, align: .Left }
    labels[3usize] = chart.Label { text: "y", anchor: chart.Coord { x: map.corners[2usize].x - 6.0, y: map.corners[2usize].y + 5.0 }, align: .Right }
    labels[4usize] = chart.Label { text: "z", anchor: chart.Coord { x: map.corners[4usize].x - 6.0, y: map.corners[4usize].y - 5.0 }, align: .Right }
    labels[5usize] = chart.Label { text: footer, anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center }
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let gray = paint.rgba(0.70, 0.77, 0.83, 1.0)
    let pale = paint.rgba(0.98, 0.99, 1.0, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 32u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, bounds, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &map.frame, paint.Brush { Solid: gray })
    if density {
        var i = 0usize
        while i < map.order.len {
            let face = map.order[i]
            let share = map.face_values[face] / map.value_max
            var ink = paint.rgba(0.12, 0.37, 0.67, 1.0)
            if share > 0.2f64 { ink = paint.rgba(0.16, 0.53, 0.73, 1.0) }
            if share > 0.4f64 { ink = paint.rgba(0.34, 0.69, 0.69, 1.0) }
            if share > 0.6f64 { ink = paint.rgba(0.70, 0.78, 0.43, 1.0) }
            if share > 0.8f64 { ink = paint.rgba(0.94, 0.68, 0.27, 1.0) }
            try chart_scene.append(a, &builder, &map.faces[face], paint.Brush { Solid: ink })
            i += 1usize
        }
    } else {
        try chart_scene.append(a, &builder, &map.wireframe, paint.Brush { Solid: blue })
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 13.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..5usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[5usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, bounds, pale, false)
    try chart_svg.append(&writer, &map.frame, gray)
    if density {
        var i = 0usize
        while i < map.order.len {
            let face = map.order[i]
            let share = map.face_values[face] / map.value_max
            var ink = paint.rgba(0.12, 0.37, 0.67, 1.0)
            if share > 0.2f64 { ink = paint.rgba(0.16, 0.53, 0.73, 1.0) }
            if share > 0.4f64 { ink = paint.rgba(0.34, 0.69, 0.69, 1.0) }
            if share > 0.6f64 { ink = paint.rgba(0.70, 0.78, 0.43, 1.0) }
            if share > 0.8f64 { ink = paint.rgba(0.94, 0.68, 0.27, 1.0) }
            try chart_svg.append(&writer, &map.faces[face], ink)
            i += 1usize
        }
    } else {
        try chart_svg.append(&writer, &map.wireframe, blue)
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 13.0)
    try chart_svg.append_labels(&writer, labels[1usize..5usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[5usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn two_cluster_sample(x: []f32, y: []f32) -> err {
    if x.len != 72usize || y.len != 72usize { ret chart.Invalid }
    var i = 0usize
    while i < x.len {
        var cx = 3.1f64
        var cy = 6.2f64
        var radius = 0.35f64 + 1.8f64 * f64(i % 13usize) / 13.0f64
        if i >= 40usize {
            cx = 7.0f64
            cy = 3.7f64
            radius = 0.3f64 + 1.7f64 * f64(i % 11usize) / 11.0f64
        }
        let angle = f64(i) * 2.399963229728653f64
        x[i] = f32(cx + radius * math.cos[f64](angle))
        y[i] = f32(cy + radius * math.sin[f64](angle))
        i += 1usize
    }
    ret ok
}

fn render_hexbin_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/hexbin.png"
    let plot = geometry.rect(54.0, 46.0, 252.0, 160.0)
    var x: [72]f32 = zero
    var y: [72]f32 = zero
    try two_cluster_sample(x[..], y[..])
    var i = 0usize
    var cells: [54]chart.HexCell = zero
    var vertices: [324]chart.Coord = zero
    var layers: [54]chart.Layout = zero
    let (map, map_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, plot, 9usize, 6usize, cells[..], vertices[..], layers[..])
    if map_error != ok || map.cells.len != 54usize || map.hexes.len != 54usize || map.total_count != 72u64 || map.max_count == 0u64 { ret chart.Invalid }
    let pale = paint.rgba(0.93, 0.96, 0.99, 1.0)
    let blue = paint.rgba(0.04, 0.33, 0.72, 1.0)
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let labels = [8]chart.Label{
        chart.Label { text: "Hexbin / two clusters", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: 54.0, y: 220.0 }, align: .Center },
        chart.Label { text: "5", anchor: chart.Coord { x: 180.0, y: 220.0 }, align: .Center },
        chart.Label { text: "10", anchor: chart.Coord { x: 306.0, y: 220.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: 42.0, y: 207.0 }, align: .Right },
        chart.Label { text: "5", anchor: chart.Coord { x: 42.0, y: 129.0 }, align: .Right },
        chart.Label { text: "10", anchor: chart.Coord { x: 42.0, y: 52.0 }, align: .Right },
        chart.Label { text: "Colour = observations per hexagon", anchor: chart.Coord { x: 180.0, y: 235.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 18u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < map.hexes.len {
        let shade = paint.mix(pale, blue, f32(map.cells[i].count) / f32(map.max_count))
        try chart_scene.append(a, &builder, &map.hexes[i], paint.Brush { Solid: shade })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..7usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[7usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < map.hexes.len {
        let shade = paint.mix(pale, blue, f32(map.cells[i].count) / f32(map.max_count))
        try chart_svg.append(&writer, &map.hexes[i], shade)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..7usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[7usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_bin2d_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/bin2d.png"
    let plot = geometry.rect(54.0, 46.0, 252.0, 160.0)
    var x: [72]f32 = zero
    var y: [72]f32 = zero
    try two_cluster_sample(x[..], y[..])
    var counts: [96]u64 = zero
    var cells: [96]chart.Cell = zero
    let (map, map_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, plot, 12usize, 8usize, counts[..], cells[..])
    if map_error != ok || map.counts.len != 96usize || map.matrix.cells.len != 96usize || map.total_count != 72u64 || map.max_count == 0u64 { ret chart.Invalid }
    let pale = paint.rgba(0.93, 0.96, 0.99, 1.0)
    let blue = paint.rgba(0.04, 0.33, 0.72, 1.0)
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let labels = [8]chart.Label{
        chart.Label { text: "2D bins / two clusters", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: 54.0, y: 220.0 }, align: .Center },
        chart.Label { text: "5", anchor: chart.Coord { x: 180.0, y: 220.0 }, align: .Center },
        chart.Label { text: "10", anchor: chart.Coord { x: 306.0, y: 220.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: 42.0, y: 207.0 }, align: .Right },
        chart.Label { text: "5", anchor: chart.Coord { x: 42.0, y: 129.0 }, align: .Right },
        chart.Label { text: "10", anchor: chart.Coord { x: 42.0, y: 52.0 }, align: .Right },
        chart.Label { text: "Colour = observations per rectangle", anchor: chart.Coord { x: 180.0, y: 235.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 19u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append_matrix(&builder, &map.matrix, pale, pale, blue)
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..7usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[7usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_matrix(&writer, &map.matrix, pale, pale, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..7usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[7usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_density2d_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/density2d.png"
    let plot = geometry.rect(54.0, 46.0, 252.0, 160.0)
    var x32: [72]f32 = zero
    var y32: [72]f32 = zero
    try two_cluster_sample(x32[..], y32[..])
    var x: [72]f64 = zero
    var y: [72]f64 = zero
    var i = 0usize
    while i < x.len {
        x[i] = f64(x32[i])
        y[i] = f64(y32[i])
        i += 1usize
    }
    let fractions = [4]f64{ 0.14f64, 0.30f64, 0.50f64, 0.72f64 }
    var grid_x: [25]f64 = zero
    var grid_y: [17]f64 = zero
    var values: [425]f64 = zero
    var cutoffs: [4]f64 = zero
    var segments: [4096]chart.Segment = zero
    var layers: [4]chart.Layout = zero
    let (map, map_error) = chart.density2d(x[..], y[..], 0.0f64, 10.0f64, 0.0f64, 10.0f64, plot, 0.7f64, 0.7f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    if map_error != ok || map.contours.len != 4usize || map.grid.len != 425usize || map.peak <= 0.0f64 { ret chart.Invalid }
    let colors = [4]paint.Color{
        paint.rgba(0.62, 0.76, 0.91, 1.0), paint.rgba(0.34, 0.61, 0.84, 1.0),
        paint.rgba(0.12, 0.45, 0.76, 1.0), paint.rgba(0.03, 0.25, 0.58, 1.0),
    }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let labels = [8]chart.Label{
        chart.Label { text: "2D density / two clusters", anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: 54.0, y: 220.0 }, align: .Center },
        chart.Label { text: "5", anchor: chart.Coord { x: 180.0, y: 220.0 }, align: .Center },
        chart.Label { text: "10", anchor: chart.Coord { x: 306.0, y: 220.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: 42.0, y: 207.0 }, align: .Right },
        chart.Label { text: "5", anchor: chart.Coord { x: 42.0, y: 129.0 }, align: .Right },
        chart.Label { text: "10", anchor: chart.Coord { x: 42.0, y: 52.0 }, align: .Right },
        chart.Label { text: "Gaussian KDE / contours at 14–72% of peak", anchor: chart.Coord { x: 180.0, y: 235.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 20u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    i = 0usize
    while i < map.contours.len {
        try chart_scene.append(a, &builder, &map.contours[i], paint.Brush { Solid: colors[i] })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 14.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..7usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[7usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    i = 0usize
    while i < map.contours.len {
        try chart_svg.append(&writer, &map.contours[i], colors[i])
        i += 1usize
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 14.0)
    try chart_svg.append_labels(&writer, labels[1usize..7usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[7usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_one_sided_distribution_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, rain: bool) -> err {
    var path: str = "docs/chart-previews/half_violin.png"
    var title: str = "Half violin / single-sided KDE"
    var footer: str = "Density on one side of the value axis"
    var font_id = 21u32
    if rain {
        path = "docs/chart-previews/raincloud.png"
        title = "Raincloud / density + box + observations"
        footer = "KDE, Tukey quartiles and every observation"
        font_id = 22u32
    }
    let plot = geometry.rect(54.0, 46.0, 252.0, 160.0)
    let sample = [24]f64{ 1.2f64, 1.8f64, 2.2f64, 2.4f64, 2.7f64, 2.9f64, 3.0f64, 3.2f64, 3.4f64, 3.6f64, 3.9f64, 4.0f64, 4.1f64, 4.2f64, 4.4f64, 4.6f64, 5.0f64, 5.4f64, 5.8f64, 6.2f64, 6.8f64, 7.2f64, 8.0f64, 9.0f64 }
    var grid: [64]f64 = zero
    var estimates: [64]f64 = zero
    var outline: [66]chart.Coord = zero
    var drops_storage: [24]chart.Coord = zero
    var whiskers: [5]chart.Segment = zero
    var boxes: [1]geometry.Rect = zero
    var cloud: chart.Layout = zero
    var drops: chart.Layout = zero
    var summary: chart.Layout = zero
    if rain {
        let (map, map_error) = chart.raincloud(sample[..], plot, 0.65f64, grid[..], estimates[..], outline[..], drops_storage[..], whiskers[..], boxes[..])
        if map_error != ok || map.drops.coords.len != sample.len || map.summary.segments.len != 5usize { ret chart.Invalid }
        cloud = map.cloud
        drops = map.drops
        summary = map.summary
    } else {
        let (half, half_error) = chart.half_violin(sample[..], plot, 0.65f64, false, grid[..], estimates[..], outline[..])
        if half_error != ok || half.coords.len != 66usize { ret chart.Invalid }
        cloud = half
    }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.39, 0.68, 0.90, 0.90)
    let deep = paint.rgba(0.08, 0.33, 0.67, 1.0)
    let orange = paint.rgba(0.90, 0.36, 0.18, 1.0)
    let dark = paint.rgba(0.17, 0.23, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let axis = geometry.rect(plot.x + plot.width * 0.5 - 0.5, plot.y, 1.0, plot.height)
    let lo = grid[0usize]
    let hi = grid[grid.len - 1usize]
    let labels = [5]chart.Label{
        chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 24.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: 45.0, y: plot.y + plot.height * f32(1.0f64 - (0.0f64 - lo) / (hi - lo)) + 3.0 }, align: .Right },
        chart.Label { text: "5", anchor: chart.Coord { x: 45.0, y: plot.y + plot.height * f32(1.0f64 - (5.0f64 - lo) / (hi - lo)) + 3.0 }, align: .Right },
        chart.Label { text: "10", anchor: chart.Coord { x: 45.0, y: plot.y + plot.height * f32(1.0f64 - (10.0f64 - lo) / (hi - lo)) + 3.0 }, align: .Right },
        chart.Label { text: footer, anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: font_id, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &cloud, paint.Brush { Solid: blue })
    try fill(&builder, axis, paint.Brush { Solid: deep })
    if rain {
        try chart_scene.append(a, &builder, &summary, paint.Brush { Solid: deep })
        try chart_scene.append(a, &builder, &drops, paint.Brush { Solid: orange })
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..4usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &cloud, blue)
    try chart_svg.rect(&writer, axis, deep, false)
    if rain {
        try chart_svg.append(&writer, &summary, deep)
        try chart_svg.append(&writer, &drops, orange)
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..4usize], dark, 8.0)
    try chart_svg.append_labels(&writer, labels[4usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_slopegraph_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/slopegraph.png"
    let plot = geometry.rect(72.0, 54.0, 216.0, 138.0)
    let before = [5]f32{ 23.0, 42.0, 57.0, 74.0, 88.0 }
    let after = [5]f32{ 82.0, 54.0, 67.0, 31.0, 18.0 }
    var points: [10]chart.Coord = zero
    var lines: [5]chart.Segment = zero
    let (marks, marks_error) = chart.slopegraph(before[..], after[..], plot, points[..], lines[..])
    if marks_error != ok || marks.segments.len != 5usize { ret chart.Invalid }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.43, 0.78, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let labels = [14]chart.Label{
        chart.Label { text: "Slopegraph / paired changes", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center },
        chart.Label { text: "Before", anchor: chart.Coord { x: plot.x, y: 213.0 }, align: .Center },
        chart.Label { text: "After", anchor: chart.Coord { x: plot.x + plot.width, y: 213.0 }, align: .Center },
        chart.Label { text: "Five series / shared value axis", anchor: chart.Coord { x: 180.0, y: 233.0 }, align: .Center },
        chart.Label { text: "A 23", anchor: chart.Coord { x: 67.0, y: points[0usize].y + 3.0 }, align: .Right },
        chart.Label { text: "A 82", anchor: chart.Coord { x: 293.0, y: points[1usize].y + 3.0 }, align: .Left },
        chart.Label { text: "B 42", anchor: chart.Coord { x: 67.0, y: points[2usize].y + 3.0 }, align: .Right },
        chart.Label { text: "B 54", anchor: chart.Coord { x: 293.0, y: points[3usize].y + 3.0 }, align: .Left },
        chart.Label { text: "C 57", anchor: chart.Coord { x: 67.0, y: points[4usize].y + 3.0 }, align: .Right },
        chart.Label { text: "C 67", anchor: chart.Coord { x: 293.0, y: points[5usize].y + 3.0 }, align: .Left },
        chart.Label { text: "D 74", anchor: chart.Coord { x: 67.0, y: points[6usize].y + 3.0 }, align: .Right },
        chart.Label { text: "D 31", anchor: chart.Coord { x: 293.0, y: points[7usize].y + 3.0 }, align: .Left },
        chart.Label { text: "E 88", anchor: chart.Coord { x: 67.0, y: points[8usize].y + 3.0 }, align: .Right },
        chart.Label { text: "E 18", anchor: chart.Coord { x: 293.0, y: points[9usize].y + 3.0 }, align: .Left },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 23u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, geometry.rect(48.0, 46.0, 264.0, 154.0), paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..4usize], font, 9.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[4usize..], font, 7.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, geometry.rect(48.0, 46.0, 264.0, 154.0), pale, false)
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..4usize], dark, 9.0)
    try chart_svg.append_labels(&writer, labels[4usize..], dark, 7.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_connected_scatter_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/connected_scatter.png"
    let plot = geometry.rect(55.0, 48.0, 250.0, 152.0)
    let x = [8]f32{ 0.0, 1.0, 2.0, 2.8, 2.2, 1.3, 0.7, 1.7 }
    let y = [8]f32{ 0.0, 0.8, 0.4, 1.8, 2.7, 2.4, 1.5, 1.1 }
    let steps = [8]str{ "1", "2", "3", "4", "5", "6", "7", "8" }
    var points: [8]chart.Coord = zero
    var lines: [7]chart.Segment = zero
    let (marks, marks_error) = chart.connected_scatter(x[..], y[..], plot, points[..], lines[..])
    if marks_error != ok || marks.segments.len != 7usize { ret chart.Invalid }
    var labels: [10]chart.Label = zero
    labels[0usize] = chart.Label { text: "Connected scatter / ordered path", anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
    labels[1usize] = chart.Label { text: "Numbers show observation order", anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center }
    var i = 0usize
    while i < steps.len {
        labels[i + 2usize] = chart.Label { text: steps[i], anchor: chart.Coord { x: points[i].x + 6.0, y: points[i].y - 6.0 }, align: .Left }
        i += 1usize
    }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.43, 0.78, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 24u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[2usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_marginal_histogram_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/marginal_histogram.png"
    let plot = geometry.rect(66.0, 83.0, 188.0, 113.0)
    let x = [12]f32{ 0.3, 0.8, 1.1, 1.3, 1.7, 2.0, 2.2, 2.6, 2.8, 3.1, 3.3, 3.8 }
    let y = [12]f32{ 1.2, 1.8, 1.4, 2.2, 2.4, 1.7, 3.1, 2.6, 3.4, 2.9, 3.7, 3.2 }
    var points: [12]chart.Coord = zero
    var x_counts: [7]u64 = zero
    var y_counts: [6]u64 = zero
    var x_bars: [7]geometry.Rect = zero
    var y_bars: [6]geometry.Rect = zero
    let (map, map_error) = chart.marginal_histogram(x[..], y[..], plot, 32.0, 48.0, 5.0, points[..], x_counts[..], x_bars[..], y_counts[..], y_bars[..])
    if map_error != ok || map.top.bars.len != 7usize || map.right.bars.len != 6usize { ret chart.Invalid }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.43, 0.78, 1.0)
    let orange = paint.rgba(0.87, 0.38, 0.17, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let labels = [4]chart.Label{
        chart.Label { text: "Marginal histograms / joint + each axis", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "X frequency", anchor: chart.Coord { x: 160.0, y: 43.0 }, align: .Center },
        chart.Label { text: "Y frequency", anchor: chart.Coord { x: 278.0, y: 216.0 }, align: .Center },
        chart.Label { text: "Shared x/y domains; exact bin counts", anchor: chart.Coord { x: 180.0, y: 234.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 25u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &map.top, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.right, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.scatter, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 11.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &map.top, blue)
    try chart_svg.append(&writer, &map.right, orange)
    try chart_svg.append(&writer, &map.scatter, dark)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 11.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_dose_response_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/dose_response.png"
    let plot = geometry.rect(60.0, 48.0, 244.0, 150.0)
    let doses = [10]f64{ 0.1f64, 0.2f64, 0.5f64, 1.0f64, 2.0f64, 5.0f64, 10.0f64, 20.0f64, 50.0f64, 100.0f64 }
    let responses = [10]f64{ 2.0f64, 4.0f64, 6.0f64, 10.0f64, 15.0f64, 33.0f64, 52.0f64, 69.0f64, 88.0f64, 97.0f64 }
    var grid: [65]f64 = zero
    var estimates: [65]f64 = zero
    var points: [10]chart.Coord = zero
    var lines: [64]chart.Segment = zero
    let (map, map_error) = chart.dose_response(doses[..], responses[..], 0.0f64, 100.0f64, 10.0f64, -1.8f64, plot, grid[..], estimates[..], points[..], lines[..])
    if map_error != ok || map.curve.segments.len != 64usize { ret chart.Invalid }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.43, 0.78, 1.0)
    let orange = paint.rgba(0.87, 0.38, 0.17, 1.0)
    let gray = paint.rgba(0.76, 0.81, 0.87, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let midpoint = geometry.rect(plot.x + plot.width * 0.6666667 - 0.5, plot.y, 1.0, plot.height)
    let labels = [9]chart.Label{
        chart.Label { text: "Dose response / LL.4 mean", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "0.1", anchor: chart.Coord { x: plot.x, y: 214.0 }, align: .Center },
        chart.Label { text: "1", anchor: chart.Coord { x: plot.x + plot.width * 0.3333333, y: 214.0 }, align: .Center },
        chart.Label { text: "10 / EC50", anchor: chart.Coord { x: plot.x + plot.width * 0.6666667, y: 214.0 }, align: .Center },
        chart.Label { text: "100", anchor: chart.Coord { x: plot.x + plot.width, y: 214.0 }, align: .Center },
        chart.Label { text: "Log dose; parameters supplied, not fitted", anchor: chart.Coord { x: 180.0, y: 234.0 }, align: .Center },
        chart.Label { text: "100", anchor: chart.Coord { x: 54.0, y: plot.y + 3.0 }, align: .Right },
        chart.Label { text: "50", anchor: chart.Coord { x: 54.0, y: plot.y + plot.height * 0.5 + 3.0 }, align: .Right },
        chart.Label { text: "0", anchor: chart.Coord { x: 54.0, y: plot.y + plot.height + 3.0 }, align: .Right },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 26u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try fill(&builder, midpoint, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.curve, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.observations, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.rect(&writer, midpoint, gray, false)
    try chart_svg.append(&writer, &map.curve, blue)
    try chart_svg.append(&writer, &map.observations, orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_hazard_rate_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/hazard_rate.png"
    let plot = geometry.rect(55.0, 48.0, 250.0, 150.0)
    let times = [14]f64{ 0.8f64, 1.7f64, 2.3f64, 3.1f64, 3.8f64, 4.2f64, 5.4f64, 6.1f64, 6.7f64, 7.3f64, 8.5f64, 9.2f64, 10.6f64, 12.0f64 }
    let events = [14]bool{ true, false, true, false, true, false, true, false, true, false, true, false, true, false }
    let edges = [7]f64{ 0.0f64, 2.0f64, 4.0f64, 6.0f64, 8.0f64, 10.0f64, 12.0f64 }
    var counts: [6]u64 = zero
    var exposure: [6]f64 = zero
    var rates: [6]f64 = zero
    try stat.interval_hazard(times[..], events[..], edges[..], counts[..], exposure[..], rates[..])
    var segments: [11]chart.Segment = zero
    let (marks, marks_error) = chart.hazard_rate(edges[..], rates[..], plot, segments[..])
    if marks_error != ok || marks.segments.len != 11usize { ret chart.Invalid }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.43, 0.78, 1.0)
    let gray = paint.rgba(0.78, 0.82, 0.87, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let labels = [9]chart.Label{
        chart.Label { text: "Interval hazard / event exposure", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "0", anchor: chart.Coord { x: plot.x, y: 213.0 }, align: .Center },
        chart.Label { text: "4", anchor: chart.Coord { x: plot.x + plot.width * 0.3333333, y: 213.0 }, align: .Center },
        chart.Label { text: "8", anchor: chart.Coord { x: plot.x + plot.width * 0.6666667, y: 213.0 }, align: .Center },
        chart.Label { text: "12", anchor: chart.Coord { x: plot.x + plot.width, y: 213.0 }, align: .Center },
        chart.Label { text: "Events / person-time in each interval", anchor: chart.Coord { x: 180.0, y: 233.0 }, align: .Center },
        chart.Label { text: "0.385", anchor: chart.Coord { x: 49.0, y: plot.y + 3.0 }, align: .Right },
        chart.Label { text: "0.2", anchor: chart.Coord { x: 49.0, y: plot.y + plot.height * 0.48 + 3.0 }, align: .Right },
        chart.Label { text: "0", anchor: chart.Coord { x: 49.0, y: plot.y + plot.height + 3.0 }, align: .Right },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 27u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try fill(&builder, geometry.rect(plot.x, plot.y + plot.height - 1.0, plot.width, 1.0), paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.rect(&writer, geometry.rect(plot.x, plot.y + plot.height - 1.0, plot.width, 1.0), gray, false)
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_influence_plot_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/influence_plot.png"
    let plot = geometry.rect(59.0, 48.0, 247.0, 148.0)
    let x = [8]f64{ 0.0f64, 1.0f64, 2.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64, 9.0f64 }
    let y = [8]f64{ 1.2f64, 2.1f64, 2.8f64, 4.2f64, 4.7f64, 6.0f64, 7.2f64, 14.1f64 }
    var diagnostics: [8]stat.RegressionDiagnostic = zero
    try stat.regression_diagnostics(x[..], y[..], diagnostics[..])
    var points: [8]chart.Coord = zero
    var circles: [8]geometry.Rect = zero
    var reference_lines: [5]chart.Segment = zero
    let (map, map_error) = chart.influence_plot(diagnostics[..], plot, 10.0, points[..], circles[..], reference_lines[..])
    if map_error != ok || map.guides.segments.len != 5usize { ret chart.Invalid }
    var max_index = 0usize
    var i = 1usize
    while i < diagnostics.len {
        if diagnostics[i].cook > diagnostics[max_index].cook { max_index = i }
        i += 1usize
    }
    let highlighted = chart.Layout { kind: .Bubble, coords: points[max_index..max_index + 1usize], segments: zero, bars: circles[max_index..max_index + 1usize], x_min: map.bubbles.x_min, x_max: map.bubbles.x_max, y_min: map.bubbles.y_min, y_max: map.bubbles.y_max }
    let pale = paint.rgba(0.97, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.43, 0.78, 0.72)
    let orange = paint.rgba(0.88, 0.34, 0.17, 1.0)
    let gray = paint.rgba(0.75, 0.80, 0.86, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let yabs = map.bubbles.y_max
    let labels = [8]chart.Label{
        chart.Label { text: "Regression influence / Cook area", anchor: chart.Coord { x: 180.0, y: 22.0 }, align: .Center },
        chart.Label { text: "+2", anchor: chart.Coord { x: 53.0, y: plot.y + plot.height * (yabs - 2.0) / (2.0 * yabs) + 3.0 }, align: .Right },
        chart.Label { text: "0", anchor: chart.Coord { x: 53.0, y: plot.y + plot.height * 0.5 + 3.0 }, align: .Right },
        chart.Label { text: "-2", anchor: chart.Coord { x: 53.0, y: plot.y + plot.height * (yabs + 2.0) / (2.0 * yabs) + 3.0 }, align: .Right },
        chart.Label { text: "Leverage (hat value)", anchor: chart.Coord { x: 180.0, y: 219.0 }, align: .Center },
        chart.Label { text: "Internally standardized residual", anchor: chart.Coord { x: 180.0, y: 239.0 }, align: .Center },
        chart.Label { text: "2x", anchor: chart.Coord { x: reference_lines[3usize].from.x, y: 204.0 }, align: .Center },
        chart.Label { text: "3x", anchor: chart.Coord { x: reference_lines[4usize].from.x, y: 204.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 28u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &map.guides, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.points, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &map.bubbles, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &highlighted, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &map.guides, gray)
    try chart_svg.append(&writer, &map.points, dark)
    try chart_svg.append(&writer, &map.bubbles, blue)
    try chart_svg.append(&writer, &highlighted, orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_capability_nonnormal_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/capability_nonnormal.png"
    let values = [30]f64{
        0.9f64, 1.1f64, 1.2f64, 1.4f64, 1.5f64, 1.7f64, 1.8f64, 2.0f64, 2.1f64, 2.2f64,
        2.4f64, 2.5f64, 2.6f64, 2.8f64, 3.0f64, 3.1f64, 3.3f64, 3.5f64, 3.7f64, 3.9f64,
        4.2f64, 4.4f64, 4.7f64, 5.0f64, 5.4f64, 5.9f64, 6.5f64, 7.2f64, 8.1f64, 9.5f64,
    }
    var counts: [12]u64 = zero
    var bars: [12]geometry.Rect = zero
    var fit_curve: [63]chart.Segment = zero
    var guides: [3]chart.Segment = zero
    var work = chart.LognormalCapabilityStorage { counts: counts[..], bars: bars[..], fit_curve: fit_curve[..], guides: guides[..] }
    let plot = geometry.rect(30.0, 50.0, 300.0, 118.0)
    let (report, report_error) = chart.lognormal_capability(values[..], 1.5f64, 7.5f64, plot, &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.19, 0.49, 0.77, 1.0)
    let orange = paint.rgba(0.93, 0.44, 0.17, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let gray = paint.rgba(0.58, 0.64, 0.71, 1.0)
    let (metrics_made, metrics_error) = str.builder(a, 96usize)
    if metrics_error != ok { ret metrics_error }
    var metrics = metrics_made
    try str.push(&metrics, "Pp ")
    try str.push_f64_fixed(&metrics, report.summary.pp, 2u8)
    try str.push(&metrics, "   Ppk ")
    try str.push_f64_fixed(&metrics, report.summary.ppk, 2u8)
    try str.push(&metrics, "   fitted median ")
    try str.push_f64_fixed(&metrics, report.summary.median, 2u8)
    let (ppm_made, ppm_error) = str.builder(a, 100usize)
    if ppm_error != ok { ret ppm_error }
    var ppm = ppm_made
    try str.push(&ppm, "Out-of-spec PPM: observed ")
    try str.push_f64_fixed(&ppm, report.summary.observed_below_ppm + report.summary.observed_above_ppm, 0u8)
    try str.push(&ppm, "   fitted ")
    try str.push_f64_fixed(&ppm, report.summary.expected_below_ppm + report.summary.expected_above_ppm, 0u8)
    let labels = [6]chart.Label{
        chart.Label { text: "Nonnormal capability / lognormal MLE", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "LSL", anchor: chart.Coord { x: guides[0usize].from.x, y: 44.0 }, align: .Center },
        chart.Label { text: "Median", anchor: chart.Coord { x: guides[1usize].from.x, y: 44.0 }, align: .Center },
        chart.Label { text: "USL", anchor: chart.Coord { x: guides[2usize].from.x, y: 44.0 }, align: .Center },
        chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 194.0 }, align: .Center },
        chart.Label { text: str.done(&ppm), anchor: chart.Coord { x: 180.0, y: 214.0 }, align: .Center },
    }
    let legend = [1]chart.Label{ chart.Label { text: "Fitted lognormal", anchor: chart.Coord { x: 180.0, y: 230.0 }, align: .Center } }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &report.histogram, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.fit_curve, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: gray })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, legend[..], font, 8.0, paint.Brush { Solid: orange })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &report.histogram, blue)
    try chart_svg.append(&writer, &report.fit_curve, orange)
    try chart_svg.append(&writer, &report.guides, gray)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.append_labels(&writer, legend[..], orange, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_capability_attribute_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/capability_attribute.png"
    let defectives = [16]usize{ 4usize, 6usize, 5usize, 7usize, 4usize, 5usize, 8usize, 3usize, 6usize, 7usize, 5usize, 4usize, 19usize, 6usize, 4usize, 5usize }
    let inspected = [16]usize{ 100usize, 105usize, 95usize, 110usize, 90usize, 100usize, 120usize, 80usize, 100usize, 105usize, 95usize, 100usize, 100usize, 110usize, 90usize, 100usize }
    var controls: [16]stat.AttributeControlPoint = zero
    var cumulative_rates: [16]f64 = zero
    var p_points: [16]chart.Coord = zero
    var p_lines: [15]chart.Segment = zero
    var cumulative_points: [16]chart.Coord = zero
    var cumulative_lines: [15]chart.Segment = zero
    var upper_limit: [15]chart.Segment = zero
    var lower_limit: [15]chart.Segment = zero
    var guides: [5]chart.Segment = zero
    var signal_points: [16]chart.Coord = zero
    var work = chart.BinomialCapabilityStorage {
        controls: controls[..], cumulative_rates: cumulative_rates[..], p_points: p_points[..], p_lines: p_lines[..],
        cumulative_points: cumulative_points[..], cumulative_lines: cumulative_lines[..],
        upper_limit: upper_limit[..], lower_limit: lower_limit[..], guides: guides[..], signal_points: signal_points[..],
    }
    let panels = [2]geometry.Rect{ geometry.rect(32.0, 50.0, 296.0, 65.0), geometry.rect(32.0, 140.0, 296.0, 53.0) }
    let (report, report_error) = chart.binomial_capability(defectives[..], inspected[..], 0.08f64, 0.95f64, panels[..], &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.19, 0.49, 0.77, 1.0)
    let orange = paint.rgba(0.93, 0.35, 0.22, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let gray = paint.rgba(0.61, 0.68, 0.75, 1.0)
    let (metrics_made, metrics_error) = str.builder(a, 128usize)
    if metrics_error != ok { ret metrics_error }
    var metrics = metrics_made
    try str.push(&metrics, "Pooled defective ")
    try str.push_f64_fixed(&metrics, report.summary.fraction * 100.0f64, 1u8)
    try str.push(&metrics, "%   PPM ")
    try str.push_f64_fixed(&metrics, report.summary.ppm, 0u8)
    let (interval_made, interval_error) = str.builder(a, 128usize)
    if interval_error != ok { ret interval_error }
    var interval = interval_made
    try str.push(&interval, "Wilson 95% ")
    try str.push_f64_fixed(&interval, report.summary.confidence.low * 100.0f64, 1u8)
    try str.push(&interval, "-")
    try str.push_f64_fixed(&interval, report.summary.confidence.high * 100.0f64, 1u8)
    try str.push(&interval, "%   target 8%")
    let labels = [5]chart.Label{
        chart.Label { text: "Binomial capability / defective units", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "P chart | variable subgroup limits", anchor: chart.Coord { x: 180.0, y: 42.0 }, align: .Center },
        chart.Label { text: "Cumulative defective rate", anchor: chart.Coord { x: 180.0, y: 132.0 }, align: .Center },
        chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 210.0 }, align: .Center },
        chart.Label { text: str.done(&interval), anchor: chart.Coord { x: 180.0, y: 228.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, panels[0usize], paint.Brush { Solid: pale })
    try fill(&builder, panels[1usize], paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &report.upper_limit, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.lower_limit, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.p_chart, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.cumulative, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.signals, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, panels[0usize], pale, false)
    try chart_svg.rect(&writer, panels[1usize], pale, false)
    try chart_svg.append(&writer, &report.upper_limit, gray)
    try chart_svg.append(&writer, &report.lower_limit, gray)
    try chart_svg.append(&writer, &report.guides, gray)
    try chart_svg.append(&writer, &report.p_chart, blue)
    try chart_svg.append(&writer, &report.cumulative, blue)
    try chart_svg.append(&writer, &report.signals, orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_capability_batch_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/capability_batch.png"
    let values = [32]f64{
        9.78f64, 9.83f64, 9.85f64, 9.94f64, 10.02f64, 10.10f64, 10.20f64, 10.28f64,
        9.91f64, 9.98f64, 10.04f64, 10.07f64, 10.15f64, 10.28f64, 10.40f64, 10.48f64,
        9.75f64, 9.82f64, 9.95f64, 10.00f64, 10.08f64, 10.16f64, 10.20f64, 10.25f64,
        9.60f64, 9.68f64, 9.75f64, 9.82f64, 10.01f64, 10.07f64, 10.18f64, 10.22f64,
    }
    var batch_means: [8]f64 = zero
    var batch_spreads: [8]f64 = zero
    var mean_points: [8]chart.Coord = zero
    var mean_lines: [7]chart.Segment = zero
    var spread_bars: [8]geometry.Rect = zero
    var guides: [3]chart.Segment = zero
    var work = chart.BatchCapabilityStorage { batch_means: batch_means[..], batch_spreads: batch_spreads[..], mean_points: mean_points[..], mean_lines: mean_lines[..], spread_bars: spread_bars[..], guides: guides[..] }
    let panels = [2]geometry.Rect{ geometry.rect(30.0, 50.0, 300.0, 65.0), geometry.rect(30.0, 140.0, 300.0, 53.0) }
    let (report, report_error) = chart.batch_capability(values[..], 4usize, 9.70f64, 10.40f64, panels[..], &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.19, 0.49, 0.77, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let gray = paint.rgba(0.61, 0.68, 0.75, 1.0)
    let (metrics_made, metrics_error) = str.builder(a, 128usize)
    if metrics_error != ok { ret metrics_error }
    var metrics = metrics_made
    try str.push(&metrics, "B/W Cp ")
    try str.push_f64_fixed(&metrics, report.summary.cp, 2u8)
    try str.push(&metrics, "   Cpk ")
    try str.push_f64_fixed(&metrics, report.summary.cpk, 2u8)
    try str.push(&metrics, "   Overall Ppk ")
    try str.push_f64_fixed(&metrics, report.summary.ppk, 2u8)
    let (sigma_made, sigma_error) = str.builder(a, 128usize)
    if sigma_error != ok { ret sigma_error }
    var sigmas = sigma_made
    try str.push(&sigmas, "SD within ")
    try str.push_f64_fixed(&sigmas, report.summary.within_sigma, 3u8)
    try str.push(&sigmas, "   between ")
    try str.push_f64_fixed(&sigmas, report.summary.between_sigma, 3u8)
    let labels = [5]chart.Label{
        chart.Label { text: "Batch capability / balanced ANOVA", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "Batch means | specification guides", anchor: chart.Coord { x: 180.0, y: 42.0 }, align: .Center },
        chart.Label { text: "Within-batch SD | pooled guide", anchor: chart.Coord { x: 180.0, y: 132.0 }, align: .Center },
        chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 210.0 }, align: .Center },
        chart.Label { text: str.done(&sigmas), anchor: chart.Coord { x: 180.0, y: 228.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, panels[0usize], paint.Brush { Solid: pale })
    try fill(&builder, panels[1usize], paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.means, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.spreads, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, panels[0usize], pale, false)
    try chart_svg.rect(&writer, panels[1usize], pale, false)
    try chart_svg.append(&writer, &report.guides, gray)
    try chart_svg.append(&writer, &report.means, blue)
    try chart_svg.append(&writer, &report.spreads, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_gage_bias_linearity_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/gage_bias_linearity.png"
    let references = [6]f64{ 2.0f64, 4.0f64, 6.0f64, 8.0f64, 10.0f64, 12.0f64 }
    let measurements = [18]f64{
        1.905f64, 1.930f64, 1.955f64, 3.955f64, 3.980f64, 4.005f64,
        6.005f64, 6.030f64, 6.055f64, 8.055f64, 8.080f64, 8.105f64,
        10.105f64, 10.130f64, 10.155f64, 12.155f64, 12.180f64, 12.205f64,
    }
    var biases: [18]f64 = zero
    var mean_biases: [6]f64 = zero
    var fitted_biases: [6]f64 = zero
    var ci_lower: [6]f64 = zero
    var ci_upper: [6]f64 = zero
    var raw_points: [18]chart.Coord = zero
    var mean_points: [6]chart.Coord = zero
    var fit_segments: [5]chart.Segment = zero
    var ci_segments: [6]chart.Segment = zero
    var zero_guide: [1]chart.Segment = zero
    var work = chart.GageLinearityStorage {
        biases: biases[..], mean_biases: mean_biases[..], fitted_biases: fitted_biases[..], ci_lower: ci_lower[..], ci_upper: ci_upper[..],
        raw_points: raw_points[..], mean_points: mean_points[..], fit_segments: fit_segments[..], ci_segments: ci_segments[..], zero_guide: zero_guide[..],
    }
    let plot = geometry.rect(32.0, 51.0, 296.0, 129.0)
    let (report, report_error) = chart.gage_linearity(references[..], measurements[..], 3usize, 2.12f64, plot, &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.19, 0.49, 0.77, 1.0)
    let orange = paint.rgba(0.93, 0.44, 0.17, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let gray = paint.rgba(0.61, 0.68, 0.75, 1.0)
    let (metrics_made, metrics_error) = str.builder(a, 120usize)
    if metrics_error != ok { ret metrics_error }
    var metrics = metrics_made
    try str.push(&metrics, "Mean bias ")
    try str.push_f64_fixed(&metrics, report.summary.average_bias, 3u8)
    try str.push(&metrics, "   Slope ")
    try str.push_f64_fixed(&metrics, report.summary.slope, 3u8)
    try str.push(&metrics, "   Span drift ")
    try str.push_f64_fixed(&metrics, report.summary.linearity, 3u8)
    let labels = [4]chart.Label{
        chart.Label { text: "Gage bias and linearity", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "Measurement minus reference", anchor: chart.Coord { x: 180.0, y: 40.0 }, align: .Center },
        chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 207.0 }, align: .Center },
        chart.Label { text: "Replicates / mean / fit / 95% mean CI", anchor: chart.Coord { x: 180.0, y: 226.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &report.zero_line, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.confidence, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.observations, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.fit, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &report.means, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &report.zero_line, gray)
    try chart_svg.append(&writer, &report.confidence, gray)
    try chart_svg.append(&writer, &report.observations, blue)
    try chart_svg.append(&writer, &report.fit, orange)
    try chart_svg.append(&writer, &report.means, dark)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_attribute_agreement_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/attribute_agreement.png"
    let standard = [10]usize{ 0usize, 1usize, 0usize, 1usize, 1usize, 0usize, 1usize, 0usize, 0usize, 1usize }
    var ratings: [80]usize = zero
    var appraiser = 0usize
    while appraiser < 4usize {
        var item = 0usize
        while item < standard.len {
            var trial = 0usize
            while trial < 2usize {
                var response = standard[item]
                var flip = false
                if appraiser == 0usize && item == 2usize && trial == 1usize { flip = true }
                if appraiser == 1usize && (item == 3usize || item == 7usize) { flip = true }
                if appraiser == 2usize && (item == 1usize || item == 4usize || (item == 8usize && trial == 1usize)) { flip = true }
                if appraiser == 3usize && (item == 0usize || item == 5usize || (item == 9usize && trial == 1usize)) { flip = true }
                if flip { response = 1usize - response }
                ratings[(appraiser * standard.len + item) * 2usize + trial] = response
                trial += 1usize
            }
            item += 1usize
        }
        appraiser += 1usize
    }
    var within_rates: [4]stat.AttributeAgreementRate = zero
    var standard_rates: [4]stat.AttributeAgreementRate = zero
    var within_points: [4]chart.Coord = zero
    var standard_points: [4]chart.Coord = zero
    var within_intervals: [4]chart.Segment = zero
    var standard_intervals: [4]chart.Segment = zero
    var work = chart.AttributeAgreementStorage {
        within_rates: within_rates[..], standard_rates: standard_rates[..],
        within_points: within_points[..], standard_points: standard_points[..],
        within_intervals: within_intervals[..], standard_intervals: standard_intervals[..],
    }
    let panels = [2]geometry.Rect{ geometry.rect(35.0, 50.0, 290.0, 58.0), geometry.rect(35.0, 145.0, 290.0, 58.0) }
    let (report, report_error) = chart.attribute_agreement(standard[..], ratings[..], 4usize, 2usize, 2usize, 0.95f64, panels[..], &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.19, 0.49, 0.77, 1.0)
    let orange = paint.rgba(0.93, 0.44, 0.17, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let gray = paint.rgba(0.61, 0.68, 0.75, 1.0)
    let (metrics_made, metrics_error) = str.builder(a, 100usize)
    if metrics_error != ok { ret metrics_error }
    var metrics = metrics_made
    try str.push(&metrics, "Pooled rating kappa ")
    try str.push_f64_fixed(&metrics, report.summary.pooled_rating_kappa, 2u8)
    try str.push(&metrics, "   all appraisers agree ")
    try str.push_usize(&metrics, report.summary.between_matched)
    try str.push(&metrics, "/10")
    let labels = [12]chart.Label{
        chart.Label { text: "Attribute agreement", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "Within appraiser / exact 95% CI", anchor: chart.Coord { x: 180.0, y: 42.0 }, align: .Center },
        chart.Label { text: "Consistent and correct versus standard", anchor: chart.Coord { x: 180.0, y: 137.0 }, align: .Center },
        chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 232.0 }, align: .Center },
        chart.Label { text: "A", anchor: chart.Coord { x: 71.0, y: 120.0 }, align: .Center },
        chart.Label { text: "B", anchor: chart.Coord { x: 143.0, y: 120.0 }, align: .Center },
        chart.Label { text: "C", anchor: chart.Coord { x: 216.0, y: 120.0 }, align: .Center },
        chart.Label { text: "D", anchor: chart.Coord { x: 289.0, y: 120.0 }, align: .Center },
        chart.Label { text: "A", anchor: chart.Coord { x: 71.0, y: 215.0 }, align: .Center },
        chart.Label { text: "B", anchor: chart.Coord { x: 143.0, y: 215.0 }, align: .Center },
        chart.Label { text: "C", anchor: chart.Coord { x: 216.0, y: 215.0 }, align: .Center },
        chart.Label { text: "D", anchor: chart.Coord { x: 289.0, y: 215.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, panels[0usize], paint.Brush { Solid: pale })
    try fill(&builder, panels[1usize], paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &report.within_intervals, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.standard_intervals, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.within, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.versus_standard, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, panels[0usize], pale, false)
    try chart_svg.rect(&writer, panels[1usize], pale, false)
    try chart_svg.append(&writer, &report.within_intervals, gray)
    try chart_svg.append(&writer, &report.standard_intervals, gray)
    try chart_svg.append(&writer, &report.within, blue)
    try chart_svg.append(&writer, &report.versus_standard, orange)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_gage_run_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/gage_run.png"
    let baseline = [5]f64{ 10.0f64, 13.0f64, 9.0f64, 15.0f64, 11.0f64 }
    let bias = [3]f64{ -0.35f64, 0.20f64, 0.65f64 }
    let trial_offset = [3]f64{ -0.20f64, 0.0f64, 0.18f64 }
    var values: [45]f64 = zero
    var part = 0usize
    while part < 5usize {
        var operator = 0usize
        while operator < 3usize {
            var trial = 0usize
            while trial < 3usize {
                values[(part * 3usize + operator) * 3usize + trial] = baseline[part] + bias[operator] + trial_offset[trial]
                trial += 1usize
            }
            operator += 1usize
        }
        part += 1usize
    }
    var operator_points: [45]chart.Coord = zero
    var operator_layouts: [3]chart.Layout = zero
    var part_centers: [5]chart.Coord = zero
    var part_dividers: [4]chart.Segment = zero
    var mean_guide: [1]chart.Segment = zero
    var work = chart.GageRunStorage {
        operator_points: operator_points[..], operator_layouts: operator_layouts[..],
        part_centers: part_centers[..], part_dividers: part_dividers[..], mean_guide: mean_guide[..],
    }
    let plot = geometry.rect(30.0, 50.0, 300.0, 132.0)
    let (report, report_error) = chart.gage_run(values[..], 5usize, 3usize, 3usize, plot, &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.12, 0.40, 0.76, 1.0)
    let orange = paint.rgba(0.93, 0.42, 0.17, 1.0)
    let green = paint.rgba(0.11, 0.60, 0.48, 1.0)
    let gray = paint.rgba(0.68, 0.73, 0.80, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let (metrics_made, metrics_error) = str.builder(a, 96usize)
    if metrics_error != ok { ret metrics_error }
    var metrics = metrics_made
    try str.push(&metrics, "Overall mean ")
    try str.push_f64_fixed(&metrics, report.summary.grand_mean, 2u8)
    try str.push(&metrics, "   max repeat range ")
    try str.push_f64_fixed(&metrics, report.summary.max_repeat_range, 2u8)
    let labels = [11]chart.Label{
        chart.Label { text: "Gage run / crossed study", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 39.0 }, align: .Center },
        chart.Label { text: "Part 1", anchor: chart.Coord { x: report.part_centers[0usize].x, y: 198.0 }, align: .Center },
        chart.Label { text: "Part 2", anchor: chart.Coord { x: report.part_centers[1usize].x, y: 198.0 }, align: .Center },
        chart.Label { text: "Part 3", anchor: chart.Coord { x: report.part_centers[2usize].x, y: 198.0 }, align: .Center },
        chart.Label { text: "Part 4", anchor: chart.Coord { x: report.part_centers[3usize].x, y: 198.0 }, align: .Center },
        chart.Label { text: "Part 5", anchor: chart.Coord { x: report.part_centers[4usize].x, y: 198.0 }, align: .Center },
        chart.Label { text: "Operator A", anchor: chart.Coord { x: 73.0, y: 227.0 }, align: .Center },
        chart.Label { text: "Operator B", anchor: chart.Coord { x: 180.0, y: 227.0 }, align: .Center },
        chart.Label { text: "Operator C", anchor: chart.Coord { x: 287.0, y: 227.0 }, align: .Center },
        chart.Label { text: "Measurements by part and operator", anchor: chart.Coord { x: 180.0, y: 213.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 30u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &report.dividers, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.reference, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &report.operators[0usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.operators[1usize], paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &report.operators[2usize], paint.Brush { Solid: green })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &report.dividers, gray)
    try chart_svg.append(&writer, &report.reference, dark)
    try chart_svg.append(&writer, &report.operators[0usize], blue)
    try chart_svg.append(&writer, &report.operators[1usize], orange)
    try chart_svg.append(&writer, &report.operators[2usize], green)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_map_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, symbols: bool) -> err {
    var path: str = "docs/chart-previews/choropleth.png"
    var title: str = "Choropleth / district rate"
    var subtitle: str = "Rate per 1,000 / gray district has no data"
    if symbols {
        path = "docs/chart-previews/proportional_symbol_map.png"
        title = "Proportional symbol map"
        subtitle = "Circle area tracks site volume / missing site unmarked"
    }
    // The districts arrive as GeoJSON keyed by their `name` (D2115); A has a lake.
    let districts = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"name\":\"A\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-9,5],[-3.5,4.5],[-2.5,9],[-7.5,8.5],[-9,5]],[[-7.3,5.8],[-6.3,5.8],[-6.3,6.7],[-7.3,6.7],[-7.3,5.8]]]}},{\"type\":\"Feature\",\"properties\":{\"name\":\"B\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-3.5,4.5],[2.5,5.2],[2,8.7],[-2.5,9],[-3.5,4.5]]]}},{\"type\":\"Feature\",\"properties\":{\"name\":\"C\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[2.5,5.2],[9,5.5],[7.5,8],[2,8.7],[2.5,5.2]]]}},{\"type\":\"Feature\",\"properties\":{\"name\":\"D\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-8,2],[-3,1],[-3.5,4.5],[-9,5],[-8,2]]]}},{\"type\":\"Feature\",\"properties\":{\"name\":\"E\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-3,1],[2,1.5],[2.5,5.2],[-3.5,4.5],[-3,1]]]}},{\"type\":\"Feature\",\"properties\":{\"name\":\"F\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[2,1.5],[8,2.5],[9,5.5],[2.5,5.2],[2,1.5]]]}}]}"
    let (parsed, parsed_error) = geojson.read(a, districts, "name")
    if parsed_error != ok { ret parsed_error }
    let regions = parsed.regions
    let rings = parsed.rings
    let vertices = parsed.vertices
    let metrics = [5]chart.MapMetric{
        chart.MapMetric { key: "A", value: 12.0f64 }, chart.MapMetric { key: "B", value: 26.0f64 },
        chart.MapMetric { key: "C", value: 38.0f64 }, chart.MapMetric { key: "D", value: 18.0f64 },
        chart.MapMetric { key: "E", value: 32.0f64 },
    }
    let sites = [6]chart.MapSite{
        chart.MapSite { key: "A", lon: -5.5f64, lat: 6.7f64, value: 100.0f64, present: true },
        chart.MapSite { key: "B", lon: -0.3f64, lat: 6.8f64, value: 60.0f64, present: true },
        chart.MapSite { key: "C", lon: 5.2f64, lat: 6.7f64, value: 180.0f64, present: true },
        chart.MapSite { key: "D", lon: -5.7f64, lat: 3.2f64, value: 30.0f64, present: true },
        chart.MapSite { key: "E", lon: -0.2f64, lat: 3.0f64, value: 75.0f64, present: true },
        chart.MapSite { key: "F", lon: 5.5f64, lat: 3.7f64, value: 0.0f64, present: false },
    }
    let window = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 10.0f64, south_lat: 0.0f64, north_lat: 10.0f64 }
    let plot = geometry.rect(30.0, 49.0, 300.0, 142.0)
    var projected: [28]chart.Coord = zero
    var projected_rings: [7]chart.MapProjectedRing = zero
    var region_layouts: [6]chart.MapRegionLayout = zero
    var work = chart.ChoroplethStorage { points: projected[..], rings: projected_rings[..], regions: region_layouts[..] }
    let (map, map_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], window, plot, &work)
    if map_error != ok { ret map_error }
    var circle_boxes: [6]geometry.Rect = zero
    let (circles, circle_error) = chart.proportional_symbol_map(sites[..], window, plot, 16.0f32, circle_boxes[..])
    if circle_error != ok { ret circle_error }
    var border_segments: [28]chart.Segment = zero
    var region_index = 0usize
    while region_index < rings.len {
        var edge = 0usize
        while edge < 4usize {
            let first = rings[region_index].first
            border_segments[first + edge] = chart.Segment {
                from: projected[first + edge], to: projected[first + (edge + 1usize) % 4usize],
            }
            edge += 1usize
        }
        region_index += 1usize
    }
    let borders = chart.Layout { kind: .Rug, coords: zero, segments: border_segments[..], bars: zero, x_min: 0.0f32, x_max: 1.0f32, y_min: 0.0f32, y_max: 1.0f32 }
    let small_radius = 9.0f32 * math.sqrt[f32](30.0f32 / 180.0f32)
    let mid_radius = 9.0f32 * math.sqrt[f32](100.0f32 / 180.0f32)
    var legend_boxes = [3]geometry.Rect{
        geometry.rect(122.0f32 - small_radius, 210.0f32 - small_radius, 2.0f32 * small_radius, 2.0f32 * small_radius),
        geometry.rect(191.0f32 - mid_radius, 210.0f32 - mid_radius, 2.0f32 * mid_radius, 2.0f32 * mid_radius),
        geometry.rect(263.0, 201.0, 18.0, 18.0),
    }
    let legend_circles = chart.Layout { kind: .Bubble, coords: zero, segments: zero, bars: legend_boxes[..], x_min: 0.0f32, x_max: 1.0f32, y_min: 0.0f32, y_max: 1.0f32 }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let missing = paint.rgba(0.72, 0.76, 0.80, 1.0)
    let bubble = paint.rgba(0.07, 0.37, 0.72, 0.82)
    let palette = [5]paint.Color{
        paint.rgba(0.79, 0.88, 0.96, 1.0), paint.rgba(0.59, 0.77, 0.91, 1.0),
        paint.rgba(0.37, 0.64, 0.85, 1.0), paint.rgba(0.20, 0.50, 0.75, 1.0),
        paint.rgba(0.08, 0.34, 0.63, 1.0),
    }
    let labels = [2]chart.Label{
        chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 19.0 }, align: .Center },
        chart.Label { text: subtitle, anchor: chart.Coord { x: 180.0, y: 38.0 }, align: .Center },
    }
    // Equal-interval classes: a swatch per palette colour, the breaks written under it.
    let strip = geometry.rect(78.0, 209.0, 200.0, 9.0)
    var swatch_storage: [5]geometry.Rect = zero
    var break_storage: [6]chart.Tick = zero
    let (classes, classes_error) = chart.class_legend(map.minimum, map.maximum, palette.len, strip, swatch_storage[..], break_storage[..])
    if classes_error != ok { ret classes_error }
    var break_words: [6]str = zero
    var word_storage: [64]u8 = zero
    let (words, words_error) = chart.format_ticks(classes.breaks, break_words[..], word_storage[..])
    if words_error != ok { ret words_error }
    var break_labels: [6]chart.Label = zero
    let (placed, placed_error) = chart.guide_labels(strip, classes.breaks, words, zero, zero, 8.0, break_labels[..])
    if placed_error != ok { ret placed_error }
    let region_labels = [6]chart.Label{
        chart.Label { text: "A", anchor: chart.Coord { x: 95.0, y: 91.0 }, align: .Center },
        chart.Label { text: "B", anchor: chart.Coord { x: 175.0, y: 88.0 }, align: .Center },
        chart.Label { text: "C", anchor: chart.Coord { x: 258.0, y: 92.0 }, align: .Center },
        chart.Label { text: "D", anchor: chart.Coord { x: 92.0, y: 153.0 }, align: .Center },
        chart.Label { text: "E", anchor: chart.Coord { x: 175.0, y: 152.0 }, align: .Center },
        chart.Label { text: "F", anchor: chart.Coord { x: 260.0, y: 152.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    var font_id = 31u32
    if symbols { font_id = 32u32 }
    let font = shape.Font { id: font_id, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    region_index = 0usize
    while region_index < map.regions.len {
        var ink = missing
        if !symbols && map.regions[region_index].has_value { ink = palette[chart.class_of(map.regions[region_index].fraction, palette.len)] }
        try chart_scene.append_map_region(a, &builder, &map.regions[region_index], paint.Brush { Solid: ink })
        region_index += 1usize
    }
    try chart_scene.append(a, &builder, &borders, paint.Brush { Solid: white })
    if symbols {
        try chart_scene.append(a, &builder, &circles.marks, paint.Brush { Solid: bubble })
        try chart_scene.append(a, &builder, &legend_circles, paint.Brush { Solid: bubble })
    }
    if !symbols { try chart_scene.append_labels(a, &builder, region_labels[..], font, 10.0, paint.Brush { Solid: dark }) }
    if !symbols {
        region_index = 0usize
        while region_index < palette.len {
            try fill(&builder, classes.swatches[region_index], paint.Brush { Solid: palette[region_index] })
            region_index += 1usize
        }
    }
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..2usize], font, 8.0, paint.Brush { Solid: dark })
    if !symbols { try chart_scene.append_labels(a, &builder, placed, font, 8.0, paint.Brush { Solid: dark }) }
    if symbols {
        let symbol_legend = [3]chart.Label{
            chart.Label { text: "30", anchor: chart.Coord { x: 122.0, y: 229.0 }, align: .Center },
            chart.Label { text: "100", anchor: chart.Coord { x: 191.0, y: 229.0 }, align: .Center },
            chart.Label { text: "180", anchor: chart.Coord { x: 272.0, y: 229.0 }, align: .Center },
        }
        try chart_scene.append_labels(a, &builder, symbol_legend[..], font, 8.0, paint.Brush { Solid: dark })
    }
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    region_index = 0usize
    while region_index < map.regions.len {
        var ink = missing
        if !symbols && map.regions[region_index].has_value { ink = palette[chart.class_of(map.regions[region_index].fraction, palette.len)] }
        try chart_svg.append_map_region(&writer, &map.regions[region_index], ink)
        region_index += 1usize
    }
    try chart_svg.append(&writer, &borders, white)
    if symbols {
        try chart_svg.append(&writer, &circles.marks, bubble)
        try chart_svg.append(&writer, &legend_circles, bubble)
    }
    if !symbols { try chart_svg.append_labels(&writer, region_labels[..], dark, 10.0) }
    if !symbols {
        region_index = 0usize
        while region_index < palette.len {
            try chart_svg.rect(&writer, classes.swatches[region_index], palette[region_index], false)
            region_index += 1usize
        }
    }
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..2usize], dark, 8.0)
    if !symbols { try chart_svg.append_labels(&writer, placed, dark, 8.0) }
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_report_page(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, path: str, title: str, subtitle: str, footer: str, cells: []const chart.ReportCell, cell_labels: []const chart.Label, font_id: u32) -> err {
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let pale = paint.rgba(0.94, 0.97, 1.0, 1.0)
    let light = paint.rgba(0.88, 0.93, 0.98, 1.0)
    let alternate = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let total = paint.rgba(0.82, 0.89, 0.96, 1.0)
    let missing = paint.rgba(0.91, 0.93, 0.95, 1.0)
    let bar = paint.rgba(0.38, 0.68, 0.91, 0.75)
    let fills = [10]paint.Color{ light, light, pale, white, total, total, total, total, alternate, missing }
    let headings = [3]chart.Label{
        chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 19.0 }, align: .Center },
        chart.Label { text: subtitle, anchor: chart.Coord { x: 180.0, y: 38.0 }, align: .Center },
        chart.Label { text: footer, anchor: chart.Coord { x: 180.0, y: 229.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: font_id, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 2048usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append_report_cells(&builder, cells, fills[..], bar)
    try chart_scene.append_labels(a, &builder, headings[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, headings[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, cell_labels, font, 7.5, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_report_cells(&writer, cells, fills[..], bar)
    try chart_svg.append_labels(&writer, headings[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, headings[1usize..], dark, 8.0)
    try chart_svg.append_labels(&writer, cell_labels, dark, 7.5)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_cross_tab_report_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let observed = [12]usize{ 6usize, 2usize, 4usize, 3usize, 3usize, 7usize, 2usize, 4usize, 5usize, 3usize, 6usize, 1usize }
    var row_ids: [46]usize = zero
    var column_ids: [46]usize = zero
    var used = 0usize
    var row = 0usize
    while row < 3usize {
        var column = 0usize
        while column < 4usize {
            var repeat = 0usize
            while repeat < observed[row * 4usize + column] {
                row_ids[used] = row
                column_ids[used] = column
                used += 1usize
                repeat += 1usize
            }
            column += 1usize
        }
        row += 1usize
    }
    if used != row_ids.len { ret chart.Invalid }
    var counts: [12]u64 = zero
    var row_totals: [3]u64 = zero
    var column_totals: [4]u64 = zero
    var cells: [30]chart.ReportCell = zero
    var work = chart.CrossTabStorage { counts: counts[..], row_totals: row_totals[..], column_totals: column_totals[..], cells: cells[..] }
    let (report, report_error) = chart.cross_tab_report(row_ids[..], column_ids[..], 3usize, 4usize, geometry.rect(24.0, 51.0, 312.0, 153.0), 78.0f32, &work)
    if report_error != ok { ret report_error }
    let row_names = [3]str{ "North", "South", "East" }
    let column_names = [4]str{ "Web", "Store", "Partner", "Direct" }
    var labels: [30]chart.Label = zero
    var i = 0usize
    while i < report.cells.len {
        let grid_row = i / report.display_columns
        let grid_column = i % report.display_columns
        var cell_text: str = ""
        if grid_row == 0usize && grid_column == 0usize {
            cell_text = "Region"
        } else if grid_row == 0usize {
            if grid_column == report.display_columns - 1usize { cell_text = "Total" } else { cell_text = column_names[grid_column - 1usize] }
        } else if grid_column == 0usize {
            if grid_row == report.display_rows - 1usize { cell_text = "Total" } else { cell_text = row_names[grid_row - 1usize] }
        } else {
            let (made, text_error) = str.builder(a, 20usize)
            if text_error != ok { ret text_error }
            var built = made
            try str.push_usize(&built, usize(report.cells[i].value))
            cell_text = str.done(&built)
        }
        let rect = report.cells[i].rect
        labels[i] = chart.Label { text: cell_text, anchor: chart.Coord { x: rect.x + rect.width * 0.5f32, y: rect.y + rect.height * 0.61f32 }, align: .Center }
        i += 1usize
    }
    ret render_report_page(a, q, output_target, canvas, renderer, "docs/chart-previews/cross_tab_report.png", "Cross-tab report / channel mix", "Exact event counts with row and column totals", "46 events / three regions / four channels", report.cells, labels[..], 31u32)
}

fn render_matrix_report_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let row_ids = [12]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 3usize, 3usize, 3usize }
    let column_ids = [12]usize{ 0usize, 1usize, 2usize, 0usize, 1usize, 2usize, 0usize, 1usize, 2usize, 0usize, 1usize, 2usize }
    let values = [12]f64{ 18.0f64, 27.5f64, 0.0f64, 12.0f64, 24.0f64, 30.0f64, 9.0f64, 0.0f64, 18.0f64, 20.0f64, 25.0f64, 28.5f64 }
    let present = [12]bool{ true, true, false, true, true, true, true, true, true, true, true, true }
    let groups = [4]usize{ 0usize, 0usize, 1usize, 1usize }
    var aggregates: [12]stat.ReportAggregate = zero
    var row_totals: [4]stat.ReportAggregate = zero
    var column_totals: [3]stat.ReportAggregate = zero
    var group_aggregates: [6]stat.ReportAggregate = zero
    var group_totals: [2]stat.ReportAggregate = zero
    var cells: [40]chart.ReportCell = zero
    var work = chart.MatrixReportStorage {
        aggregates: aggregates[..], row_totals: row_totals[..], column_totals: column_totals[..],
        group_aggregates: group_aggregates[..], group_totals: group_totals[..], cells: cells[..],
    }
    let (report, report_error) = chart.matrix_report(row_ids[..], column_ids[..], values[..], present[..], groups[..], 4usize, 3usize, geometry.rect(20.0, 51.0, 320.0, 154.0), 93.0f32, .Row, &work)
    if report_error != ok { ret report_error }
    let row_names = [8]str{ "Product", "Servers", "Devices", "Hardware sum", "Licenses", "Support", "Software sum", "Grand total" }
    let column_names = [4]str{ "Q1", "Q2", "Q3", "Total" }
    var labels: [40]chart.Label = zero
    var i = 0usize
    while i < report.cells.len {
        let grid_row = i / report.display_columns
        let grid_column = i % report.display_columns
        var cell_text: str = ""
        if grid_column == 0usize {
            cell_text = row_names[grid_row]
        } else if grid_row == 0usize {
            cell_text = column_names[grid_column - 1usize]
        } else if !report.cells[i].present {
            cell_text = "n/a"
        } else {
            let (made, text_error) = str.builder(a, 24usize)
            if text_error != ok { ret text_error }
            var built = made
            try str.push_f64_fixed(&built, report.cells[i].value, 1u8)
            cell_text = str.done(&built)
        }
        let rect = report.cells[i].rect
        labels[i] = chart.Label { text: cell_text, anchor: chart.Coord { x: rect.x + rect.width * 0.5f32, y: rect.y + rect.height * 0.52f32 }, align: .Center }
        i += 1usize
    }
    ret render_report_page(a, q, output_target, canvas, renderer, "docs/chart-previews/matrix_report.png", "Matrix report / quarterly sales", "Grouped subtotals, missing cells and row-scaled bars", "Blue bar length is normalized within each product row", report.cells, labels[..], 32u32)
}

fn render_capability_normal_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/capability_normal.png"
    let values = [30]f64{
        9.5f64, 10.2f64, 9.8f64, 10.3f64, 9.9f64, 10.1f64, 9.7f64, 10.4f64, 10.0f64, 9.6f64,
        10.2f64, 9.9f64, 10.5f64, 10.1f64, 9.8f64, 10.3f64, 9.7f64, 10.0f64, 10.4f64, 9.9f64,
        10.1f64, 9.6f64, 10.2f64, 10.0f64, 9.8f64, 10.3f64, 9.7f64, 10.1f64, 9.9f64, 10.5f64,
    }
    var moving: [29]f64 = zero
    var counts: [12]u64 = zero
    var bars: [12]geometry.Rect = zero
    var within: [63]chart.Segment = zero
    var overall: [63]chart.Segment = zero
    var guides: [3]chart.Segment = zero
    var work = chart.NormalCapabilityStorage { moving: moving[..], counts: counts[..], bars: bars[..], within_curve: within[..], overall_curve: overall[..], guides: guides[..] }
    let plot = geometry.rect(30.0, 48.0, 300.0, 120.0)
    let (report, report_error) = chart.normal_capability(values[..], 9.6f64, 10.4f64, plot, &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.19, 0.49, 0.77, 1.0)
    let orange = paint.rgba(0.93, 0.44, 0.17, 1.0)
    let dark = paint.rgba(0.16, 0.22, 0.31, 1.0)
    let gray = paint.rgba(0.58, 0.64, 0.71, 1.0)
    let (metrics_made, metrics_error) = str.builder(a, 128usize)
    if metrics_error != ok { ret metrics_error }
    var metrics = metrics_made
    try str.push(&metrics, "Cp ")
    try str.push_f64_fixed(&metrics, report.summary.cp, 2u8)
    try str.push(&metrics, "  Cpk ")
    try str.push_f64_fixed(&metrics, report.summary.cpk, 2u8)
    try str.push(&metrics, "  Pp ")
    try str.push_f64_fixed(&metrics, report.summary.pp, 2u8)
    try str.push(&metrics, "  Ppk ")
    try str.push_f64_fixed(&metrics, report.summary.ppk, 2u8)
    let (ppm_made, ppm_error) = str.builder(a, 128usize)
    if ppm_error != ok { ret ppm_error }
    var ppm = ppm_made
    try str.push(&ppm, "Out-of-spec PPM: observed ")
    try str.push_f64_fixed(&ppm, report.performance.observed_below_ppm + report.performance.observed_above_ppm, 0u8)
    try str.push(&ppm, "   within ")
    try str.push_f64_fixed(&ppm, report.performance.within_below_ppm + report.performance.within_above_ppm, 0u8)
    try str.push(&ppm, "   overall ")
    try str.push_f64_fixed(&ppm, report.performance.overall_below_ppm + report.performance.overall_above_ppm, 0u8)
    let labels = [5]chart.Label{
        chart.Label { text: "Normal capability / individuals", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "LSL", anchor: chart.Coord { x: guides[0usize].from.x, y: 43.0 }, align: .Center },
        chart.Label { text: "USL", anchor: chart.Coord { x: guides[2usize].from.x, y: 43.0 }, align: .Center },
        chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 193.0 }, align: .Center },
        chart.Label { text: str.done(&ppm), anchor: chart.Coord { x: 180.0, y: 213.0 }, align: .Center },
    }
    let legend = [2]chart.Label{
        chart.Label { text: "Within", anchor: chart.Coord { x: 115.0, y: 230.0 }, align: .Center },
        chart.Label { text: "Overall", anchor: chart.Coord { x: 245.0, y: 230.0 }, align: .Center },
    }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try fill(&builder, plot, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &report.histogram, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.within_curve, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &report.overall_curve, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: gray })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, legend[..1usize], font, 8.0, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, legend[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.rect(&writer, plot, pale, false)
    try chart_svg.append(&writer, &report.histogram, blue)
    try chart_svg.append(&writer, &report.within_curve, orange)
    try chart_svg.append(&writer, &report.overall_curve, dark)
    try chart_svg.append(&writer, &report.guides, gray)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.append_labels(&writer, legend[..1usize], orange, 8.0)
    try chart_svg.append_labels(&writer, legend[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_capability_sixpack_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/capability_sixpack.png"
    let values = [30]f64{
        9.5f64, 10.2f64, 9.8f64, 10.3f64, 9.9f64, 10.1f64, 9.7f64, 10.4f64, 10.0f64, 9.6f64,
        10.2f64, 9.9f64, 10.5f64, 10.1f64, 9.8f64, 10.3f64, 9.7f64, 10.0f64, 10.4f64, 9.9f64,
        10.1f64, 9.6f64, 10.2f64, 10.0f64, 9.8f64, 10.3f64, 9.7f64, 10.1f64, 9.9f64, 10.5f64,
    }
    var sorted = values
    var i = 1usize
    while i < sorted.len {
        let held = sorted[i]
        var j = i
        while j > 0usize && sorted[j - 1usize] > held {
            sorted[j] = sorted[j - 1usize]
            j -= 1usize
        }
        sorted[j] = held
        i += 1usize
    }
    let panels = [6]geometry.Rect{
        geometry.rect(20.0, 44.0, 145.0, 42.0), geometry.rect(196.0, 44.0, 145.0, 42.0),
        geometry.rect(20.0, 111.0, 145.0, 42.0), geometry.rect(196.0, 111.0, 145.0, 42.0),
        geometry.rect(20.0, 178.0, 145.0, 42.0), geometry.rect(244.0, 174.0, 96.0, 51.0),
    }
    var moving: [29]f64 = zero
    var individual_points: [30]chart.Coord = zero
    var individual_lines: [29]chart.Segment = zero
    var range_points: [29]chart.Coord = zero
    var range_lines: [28]chart.Segment = zero
    var recent_points: [25]chart.Coord = zero
    var counts: [8]u64 = zero
    var bars: [8]geometry.Rect = zero
    var within_curve: [31]chart.Segment = zero
    var overall_curve: [31]chart.Segment = zero
    var probability_points: [30]chart.Coord = zero
    var probability_reference: [1]chart.Segment = zero
    var interval_bars: [3]geometry.Rect = zero
    var guides: [11]chart.Segment = zero
    var work = chart.CapabilitySixpackStorage {
        moving: moving[..], individual_points: individual_points[..], individual_lines: individual_lines[..],
        range_points: range_points[..], range_lines: range_lines[..], recent_points: recent_points[..],
        histogram_counts: counts[..], histogram_bars: bars[..], within_curve: within_curve[..], overall_curve: overall_curve[..],
        probability_points: probability_points[..], probability_reference: probability_reference[..],
        interval_bars: interval_bars[..], guides: guides[..],
    }
    let (report, report_error) = chart.capability_sixpack(values[..], sorted[..], 9.0f64, 11.0f64, panels[..], &work)
    if report_error != ok { ret report_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let pale = paint.rgba(0.96, 0.98, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.44, 0.77, 1.0)
    let orange = paint.rgba(0.91, 0.42, 0.19, 1.0)
    let gray = paint.rgba(0.74, 0.79, 0.83, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let names = [6]str{ "Individuals", "Moving range", "Last 25 observations", "Capability histogram", "Normal Q-Q", "Capability intervals" }
    var labels: [10]chart.Label = zero
    labels[0usize] = chart.Label { text: "Normal capability sixpack / individuals", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center }
    i = 0usize
    while i < 6usize {
        var x = panels[i].x + panels[i].width * 0.5
        if i == 5usize { x = 268.0 }
        labels[i + 1usize] = chart.Label { text: names[i], anchor: chart.Coord { x: x, y: panels[i].y - 7.0 }, align: .Center }
        i += 1usize
    }
    labels[7usize] = chart.Label { text: "Within", anchor: chart.Coord { x: 239.0, y: 187.0 }, align: .Right }
    labels[8usize] = chart.Label { text: "Overall", anchor: chart.Coord { x: 239.0, y: 204.0 }, align: .Right }
    labels[9usize] = chart.Label { text: "Specs", anchor: chart.Coord { x: 239.0, y: 221.0 }, align: .Right }
    let (made_text, text_error) = str.builder(a, 96usize)
    if text_error != ok { ret text_error }
    var metrics = made_text
    try str.push(&metrics, "Cp ")
    try str.push_f64_fixed(&metrics, report.summary.cp, 2u8)
    try str.push(&metrics, "   Cpk ")
    try str.push_f64_fixed(&metrics, report.summary.cpk, 2u8)
    try str.push(&metrics, "   Pp ")
    try str.push_f64_fixed(&metrics, report.summary.pp, 2u8)
    try str.push(&metrics, "   Ppk ")
    try str.push_f64_fixed(&metrics, report.summary.ppk, 2u8)
    let footer = [1]chart.Label{ chart.Label { text: str.done(&metrics), anchor: chart.Coord { x: 180.0, y: 237.0 }, align: .Center } }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 29u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 384usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    i = 0usize
    while i < 6usize {
        try fill(&builder, panels[i], paint.Brush { Solid: pale })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &report.individuals, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.moving_range, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.recent, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.histogram, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.within_curve, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &report.overall_curve, paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &report.probability, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.intervals, paint.Brush { Solid: blue })
    try chart_scene.append_labels(a, &builder, labels[..1usize], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, footer[..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    i = 0usize
    while i < 6usize {
        try chart_svg.rect(&writer, panels[i], pale, false)
        i += 1usize
    }
    try chart_svg.append(&writer, &report.guides, gray)
    try chart_svg.append(&writer, &report.individuals, blue)
    try chart_svg.append(&writer, &report.moving_range, blue)
    try chart_svg.append(&writer, &report.recent, blue)
    try chart_svg.append(&writer, &report.histogram, blue)
    try chart_svg.append(&writer, &report.within_curve, orange)
    try chart_svg.append(&writer, &report.overall_curve, dark)
    try chart_svg.append(&writer, &report.probability, blue)
    try chart_svg.append(&writer, &report.intervals, blue)
    try chart_svg.append_labels(&writer, labels[..1usize], dark, 12.0)
    try chart_svg.append_labels(&writer, labels[1usize..], dark, 8.0)
    try chart_svg.append_labels(&writer, footer[..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_fishbone_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/fishbone.png"
    let categories = [6]str{ "People", "Process", "Equipment", "Materials", "Measurement", "Environment" }
    let causes = [9]chart.FishboneCause{
        chart.FishboneCause { category: 0usize, parent: -1i32, text: "Training" },
        chart.FishboneCause { category: 0usize, parent: -1i32, text: "Staffing" },
        chart.FishboneCause { category: 1usize, parent: -1i32, text: "Handoffs" },
        chart.FishboneCause { category: 1usize, parent: -1i32, text: "Queue" },
        chart.FishboneCause { category: 2usize, parent: -1i32, text: "Wear" },
        chart.FishboneCause { category: 3usize, parent: -1i32, text: "Supplier" },
        chart.FishboneCause { category: 3usize, parent: -1i32, text: "Mix" },
        chart.FishboneCause { category: 4usize, parent: -1i32, text: "Sampling" },
        chart.FishboneCause { category: 5usize, parent: -1i32, text: "Humidity" },
    }
    var spine: [3]chart.Segment = zero
    var ribs: [6]chart.Segment = zero
    var branches: [9]chart.Segment = zero
    var head_box: [1]geometry.Rect = zero
    var labels: [16]chart.Label = zero
    let (map, map_error) = chart.fishbone("Defects", categories[..], causes[..], geometry.rect(12.0, 32.0, 336.0, 190.0), spine[..], ribs[..], branches[..], head_box[..], labels[..])
    if map_error != ok { ret map_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let blue = paint.rgba(0.10, 0.43, 0.77, 1.0)
    let orange = paint.rgba(0.89, 0.38, 0.19, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let title = [1]chart.Label{ chart.Label { text: "Fishbone / cause & effect", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center } }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 30u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &map.spine, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.ribs, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.causes, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.head, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, title[..], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, map.labels[..1usize], font, 8.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, map.labels[1usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &map.spine, blue)
    try chart_svg.append(&writer, &map.ribs, blue)
    try chart_svg.append(&writer, &map.causes, orange)
    try chart_svg.append(&writer, &map.head, orange)
    try chart_svg.append_labels(&writer, title[..], dark, 12.0)
    try chart_svg.append_labels(&writer, map.labels[..1usize], white, 8.0)
    try chart_svg.append_labels(&writer, map.labels[1usize..], dark, 8.0)
    try chart_svg.finish(&writer)
    let (svg_path, path_error) = vector_path(a, path)
    if path_error != ok { ret path_error }
    ret fs.write_file(a, svg_path, io.memory_bytes(&svg_state))
}

fn render_cause_effect_tree_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let path = "docs/chart-previews/cause_effect_tree.png"
    let nodes = [10]chart.CauseTreeNode{
        chart.CauseTreeNode { parent: -1i32, text: "Delays" },
        chart.CauseTreeNode { parent: 0i32, text: "Supply" },
        chart.CauseTreeNode { parent: 0i32, text: "Process" },
        chart.CauseTreeNode { parent: 0i32, text: "Planning" },
        chart.CauseTreeNode { parent: 1i32, text: "Stockout" },
        chart.CauseTreeNode { parent: 1i32, text: "Transit" },
        chart.CauseTreeNode { parent: 2i32, text: "Rework" },
        chart.CauseTreeNode { parent: 2i32, text: "Breakdown" },
        chart.CauseTreeNode { parent: 3i32, text: "Forecast" },
        chart.CauseTreeNode { parent: 4i32, text: "Vendor" },
    }
    var placements: [10]chart.CauseTreePlacement = zero
    var cursor: [10]usize = zero
    var work = chart.CauseTreeWork { placements: placements[..], cursor: cursor[..] }
    var boxes: [10]geometry.Rect = zero
    var links: [27]chart.Segment = zero
    var labels: [10]chart.Label = zero
    let (map, map_error) = chart.cause_effect_tree(nodes[..], geometry.rect(10.0, 41.0, 340.0, 176.0), &work, boxes[..], links[..], labels[..])
    if map_error != ok { ret map_error }
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let gray = paint.rgba(0.68, 0.75, 0.82, 1.0)
    let orange = paint.rgba(0.88, 0.37, 0.18, 1.0)
    let blue = paint.rgba(0.11, 0.43, 0.78, 1.0)
    let pale = paint.rgba(0.83, 0.90, 0.97, 1.0)
    let dark = paint.rgba(0.18, 0.24, 0.32, 1.0)
    let root_marks = chart.Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let primary_marks = chart.Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[1usize..4usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let detail_marks = chart.Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[4usize..], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let title = [1]chart.Label{ chart.Label { text: "Cause-effect tree / late delivery", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center } }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 31u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: white })
    try chart_scene.append(a, &builder, &map.connectors, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &detail_marks, paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &primary_marks, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &root_marks, paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, title[..], font, 12.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, map.labels[..4usize], font, 8.0, paint.Brush { Solid: white })
    try chart_scene.append_labels(a, &builder, map.labels[4usize..], font, 8.0, paint.Brush { Solid: dark })
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append(&writer, &map.connectors, gray)
    try chart_svg.append(&writer, &detail_marks, pale)
    try chart_svg.append(&writer, &primary_marks, blue)
    try chart_svg.append(&writer, &root_marks, orange)
    try chart_svg.append_labels(&writer, title[..], dark, 12.0)
    try chart_svg.append_labels(&writer, map.labels[..4usize], white, 8.0)
    try chart_svg.append_labels(&writer, map.labels[4usize..], dark, 8.0)
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

fn render_mekko(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, layers: []chart.Layout, categories: []const str, names: []const str, title: str, path: str) -> err {
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
    labels[7usize] = chart.Label { text: title, anchor: chart.Coord { x: 180.0, y: 23.0 }, align: .Center }
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

// Three independent vertical domains over one month axis: orders as bars on the
// left axis, an index with a missing March on the right, a defect rate on a
// third axis 44 px further out, and an axis table of months and counts.
fn render_combo_axes_preview(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer) -> err {
    let plot = geometry.rect(52.0, 36.0, 196.0, 122.0)
    let months = [6]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 }
    let orders = [6]f32{ 120.0, 135.0, 128.0, 150.0, 162.0, 171.0 }
    let index_values = [6]f32{ 100.0, 104.0, f32(math.nan64()), 118.0, 125.0, 131.0 }
    let rates = [6]f32{ 2.4, 2.1, 2.6, 1.9, 1.7, 1.5 }
    let series = [3]chart.ComboSeries{
        chart.ComboSeries { mark: .Bar, axis: 0usize, x: months[..], y: orders[..] },
        chart.ComboSeries { mark: .PointLine, axis: 1usize, x: months[..], y: index_values[..] },
        chart.ComboSeries { mark: .Line, axis: 2usize, x: months[..], y: rates[..] },
    }
    var coords: [6]chart.Coord = zero
    var segments: [10]chart.Segment = zero
    var bars: [6]geometry.Rect = zero
    var layers: [3]chart.Layout = zero
    var axes: [3]chart.ComboAxis = zero
    let storage = chart.ComboStorage { coords: coords[..], segments: segments[..], bars: bars[..], layers: layers[..], axes: axes[..] }
    let (combo, combo_error) = chart.combo(series[..], 3usize, plot, 0.0, storage)
    if combo_error != ok { ret combo_error }
    let colors = [3]paint.Color{ paint.rgba(0.07, 0.35, 0.76, 1.0), paint.rgba(0.94, 0.42, 0.12, 1.0), paint.rgba(0.10, 0.55, 0.32, 1.0) }
    let dark = paint.rgba(0.20, 0.25, 0.33, 1.0)
    let grid = paint.rgba(0.88, 0.91, 0.95, 1.0)
    let offsets = [3]f32{ 0.0, 0.0, 44.0 }
    let rights = [3]bool{ false, true, true }
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var tick_storage: [15]chart.Tick = zero
    var words: [15]str = zero
    var word_bytes: [192]u8 = zero
    var rules: [18]chart.Segment = zero
    var axis_text: [15]chart.Label = zero
    var axis_layers: [3]chart.Layout = zero
    var axis_counts: [3]usize = zero
    var left_ticks = tick_storage[..0usize]
    var k = 0usize
    while k < 3usize {
        let (made_ticks, tick_error) = chart.nice_ticks(linear, combo.axes[k].y_min, combo.axes[k].y_max, 5usize, tick_storage[5usize * k..5usize * k + 5usize])
        if tick_error != ok { ret tick_error }
        if k == 0usize { left_ticks = made_ticks }
        let (made_words, word_error) = chart.format_ticks(made_ticks, words[5usize * k..5usize * k + 5usize], word_bytes[64usize * k..64usize * k + 64usize])
        if word_error != ok { ret word_error }
        let (rule_layer, made_labels, axis_error) = chart.side_axis(plot, made_ticks, made_words, rights[k], offsets[k], 8.0, rules[6usize * k..6usize * k + 6usize], axis_text[5usize * k..5usize * k + 5usize])
        if axis_error != ok { ret axis_error }
        axis_layers[k] = rule_layer
        axis_counts[k] = made_labels.len
        k += 1usize
    }
    let titles = [3]chart.Label{
        chart.Label { text: "Orders", anchor: chart.Coord { x: plot.x, y: plot.y - 8.0 }, align: .Center },
        chart.Label { text: "Index", anchor: chart.Coord { x: plot.x + plot.width, y: plot.y - 8.0 }, align: .Center },
        chart.Label { text: "Defect %", anchor: chart.Coord { x: plot.x + plot.width + offsets[2usize], y: plot.y - 8.0 }, align: .Center },
    }
    let row_titles = [2]str{ "Month", "Orders" }
    let cells = [12]str{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "120", "135", "128", "150", "162", "171" }
    var table_storage: [14]chart.Label = zero
    let (table, table_error) = chart.axis_table(months[..], &combo.layers[0usize], plot, row_titles[..], cells[..], plot.y + plot.height + 1.0, 12.0, table_storage[..])
    if table_error != ok { ret table_error }
    let heading = [1]chart.Label{ chart.Label { text: "Orders, index and defect rate on three axes", anchor: chart.Coord { x: 180.0, y: 16.0 }, align: .Center } }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(renderer, font)
    let (made, builder_error) = scene.builder(a, 160usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try fill(&builder, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) })
    try chart_scene.append_guides(&builder, plot, tick_storage[..0usize], left_ticks, paint.Brush { Solid: grid }, paint.Brush { Solid: dark })
    k = 0usize
    while k < 3usize {
        try chart_scene.append(a, &builder, &combo.layers[k], paint.Brush { Solid: colors[k] })
        try chart_scene.append(a, &builder, &axis_layers[k], paint.Brush { Solid: colors[k] })
        try chart_scene.append_labels(a, &builder, axis_text[5usize * k..5usize * k + axis_counts[k]], font, 8.0, paint.Brush { Solid: colors[k] })
        try chart_scene.append_labels(a, &builder, titles[k..k + 1usize], font, 9.0, paint.Brush { Solid: colors[k] })
        k += 1usize
    }
    try chart_scene.append_labels(a, &builder, table, font, 8.0, paint.Brush { Solid: dark })
    try chart_scene.append_labels(a, &builder, heading[..], font, 11.0, paint.Brush { Solid: dark })
    let path = "docs/chart-previews/combo_axes.png"
    try render_builder(a, q, output_target, canvas, renderer, &builder, path)
    let (svg_held, svg_error) = svg_start(a, path)
    if svg_error != ok { ret svg_error }
    var svg_state = svg_held
    var writer = io.writer(mem.cast[*void](&svg_state), io.memory_write)
    try chart_svg.append_guides(&writer, plot, tick_storage[..0usize], left_ticks, grid, dark)
    k = 0usize
    while k < 3usize {
        try chart_svg.append(&writer, &combo.layers[k], colors[k])
        try chart_svg.append(&writer, &axis_layers[k], colors[k])
        try chart_svg.append_labels(&writer, axis_text[5usize * k..5usize * k + axis_counts[k]], colors[k], 8.0)
        try chart_svg.append_labels(&writer, titles[k..k + 1usize], colors[k], 9.0)
        k += 1usize
    }
    try chart_svg.append_labels(&writer, table, dark, 8.0)
    try chart_svg.append_labels(&writer, heading[..], dark, 11.0)
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
    let loess_x = [24]f32{ 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0, 11.5 }
    let loess_y = [24]f32{ 4.88, 5.92, 6.22, 6.71, 6.82, 7.36, 7.99, 7.52, 7.45, 6.61, 6.07, 5.3, 3.77, 4.25, 3.53, 3.09, 1.83, 1.72, 2.2, 2.68, 3.47, 3.89, 4.81, 4.97 }
    var loess_distances: [24]f64 = zero
    var loess_outline: [98]chart.Coord = zero
    var loess_fit: [48]chart.Segment = zero
    let (loess_ribbon, loess_curve, loess_error) = chart.loess_interval(loess_x[..], loess_y[..], 0.4, 2.0, false, bounds, loess_distances[..], loess_outline[..], loess_fit[..])
    if loess_error != ok { ret loess_error }
    let loess_x_limits = [2]f32{ loess_curve.x_min, loess_curve.x_max }
    let loess_y_limits = [2]f32{ loess_curve.y_min, loess_curve.y_max }
    var loess_spec = chart.spec(.Scatter, bounds, loess_x[..], loess_y[..])
    var loess_points: [24]chart.Coord = zero
    let (loess_dots, loess_dots_error) = chart.layout_with_limits(&loess_spec, loess_points[..], segments[..0usize], bars[..0usize], loess_x_limits[..], loess_y_limits[..])
    if loess_dots_error != ok { ret loess_dots_error }
    let loess_underlay = [1]chart.Layout{ loess_ribbon }
    try render_scatter_overlay(a, queue, output_target, canvas, &renderer, &loess_dots, &loess_curve, loess_underlay[..], "docs/chart-previews/loess_band.png")
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
    try render_mekko(a, queue, output_target, canvas, &renderer, mekko_layers, category_names[..], mekko_series[..], "Marimekko shares", "docs/chart-previews/mekko.png")
    let spine_counts = [12]f64{ 24.0f64, 12.0f64, 4.0f64, 6.0f64, 16.0f64, 8.0f64, 9.0f64, 6.0f64, 15.0f64, 4.0f64, 8.0f64, 8.0f64 }
    let spine_names = [3]str{ "Pass", "Hold", "Fail" }
    let spine_groups = [4]str{ "A", "B", "C", "D" }
    var spine_totals: [4]f64 = zero
    var spine_bars: [12]geometry.Rect = zero
    var spine_layers: [3]chart.Layout = zero
    let (spine, spine_error) = chart.spine_plot(spine_counts[..], 4usize, geometry.rect(44.0, 45.0, 210.0, 148.0), 2.0, spine_totals[..], spine_bars[..], spine_layers[..])
    if spine_error != ok || spine.grand_total != 120.0f64 || spine.column_totals[0usize] != 40.0f64 { ret chart.Invalid }
    try render_mekko(a, queue, output_target, canvas, &renderer, spine.categories, spine_groups[..], spine_names[..], "Spine / outcome mix", "docs/chart-previews/spine_plot.png")
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
    try render_combo_axes_preview(a, queue, output_target, canvas, &renderer)
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
    try render_future_state_vsm_preview(a, queue, output_target, canvas, &renderer)
    try render_cap_table_waterfall_preview(a, queue, output_target, canvas, &renderer)
    try render_tornado_preview(a, queue, output_target, canvas, &renderer)
    try render_football_field_preview(a, queue, output_target, canvas, &renderer)
    try render_yield_curve_preview(a, queue, output_target, canvas, &renderer)
    try render_monte_carlo_preview(a, queue, output_target, canvas, &renderer, false)
    try render_monte_carlo_preview(a, queue, output_target, canvas, &renderer, true)
    try render_date_axis_line_preview(a, queue, output_target, canvas, &renderer)
    try render_discrete_axis_bar_preview(a, queue, output_target, canvas, &renderer)
    try render_category_facet_preview(a, queue, output_target, canvas, &renderer)
    try render_legend_collision_preview(a, queue, output_target, canvas, &renderer)
    try render_missing_data_scatter_preview(a, queue, output_target, canvas, &renderer)
    try render_clipped_annotation_preview(a, queue, output_target, canvas, &renderer)
    try render_plot_grid_preview(a, queue, output_target, canvas, &renderer)
    try render_shared_guide_facets_preview(a, queue, output_target, canvas, &renderer)
    try render_interactive_selection_preview(a, queue, output_target, canvas, &renderer)
    try render_accessible_palette_preview(a, queue, output_target, canvas, &renderer)
    try render_gradient_font_preview(a, queue, output_target, canvas, &renderer)
    try render_color_vision_preview(a, queue, output_target, canvas, &renderer)
    try render_label_placement_preview(a, queue, output_target, canvas, &renderer)
    try render_locale_axes_preview(a, queue, output_target, canvas, &renderer)
    try render_pdf_export_preview(a, queue, output_target, canvas, &renderer)
    try render_benchmark_preview(a, queue, output_target, canvas, &renderer)
    try render_network_preview(a, queue, output_target, canvas, &renderer)
    try render_layered_preview(a, queue, output_target, canvas, &renderer)
    try render_aggregate_decomposition_tree_preview(a, queue, output_target, canvas, &renderer)
    try render_sipoc_preview(a, queue, output_target, canvas, &renderer)
    try render_decision_tree_preview(a, queue, output_target, canvas, &renderer)
    try render_org_chart_preview(a, queue, output_target, canvas, &renderer)
    try render_dependency_graph_preview(a, queue, output_target, canvas, &renderer)
    try render_flowchart_preview(a, queue, output_target, canvas, &renderer)
    try render_state_machine_preview(a, queue, output_target, canvas, &renderer)
    try render_sequence_diagram_preview(a, queue, output_target, canvas, &renderer)
    try render_entity_relationship_preview(a, queue, output_target, canvas, &renderer)
    try render_branching_process_preview(a, queue, output_target, canvas, &renderer)
    try render_stem_and_leaf_preview(a, queue, output_target, canvas, &renderer)
    try render_range_interval_preview(a, queue, output_target, canvas, &renderer)
    try render_probability_plot_preview(a, queue, output_target, canvas, &renderer)
    try render_weibull_probability_preview(a, queue, output_target, canvas, &renderer)
    try render_oc_curve_preview(a, queue, output_target, canvas, &renderer)
    try render_gage_rr_preview(a, queue, output_target, canvas, &renderer)
    try render_multi_vari_preview(a, queue, output_target, canvas, &renderer)
    try render_main_effects_preview(a, queue, output_target, canvas, &renderer)
    try render_anom_preview(a, queue, output_target, canvas, &renderer)
    try render_hotelling_t2_preview(a, queue, output_target, canvas, &renderer)
    try render_generalized_variance_preview(a, queue, output_target, canvas, &renderer)
    try render_mewma_preview(a, queue, output_target, canvas, &renderer)
    try render_interaction_plot_preview(a, queue, output_target, canvas, &renderer)
    try render_cube_plot_preview(a, queue, output_target, canvas, &renderer)
    try render_spectrogram_preview(a, queue, output_target, canvas, &renderer)
    try render_waterfall_spectrum_preview(a, queue, output_target, canvas, &renderer)
    try render_bode_preview(a, queue, output_target, canvas, &renderer)
    try render_nyquist_preview(a, queue, output_target, canvas, &renderer)
    try render_scatter3d_preview(a, queue, output_target, canvas, &renderer)
    try render_histogram3d_preview(a, queue, output_target, canvas, &renderer)
    try render_surface3d_preview(a, queue, output_target, canvas, &renderer, true)
    try render_surface3d_preview(a, queue, output_target, canvas, &renderer, false)
    try render_hexbin_preview(a, queue, output_target, canvas, &renderer)
    try render_bin2d_preview(a, queue, output_target, canvas, &renderer)
    try render_density2d_preview(a, queue, output_target, canvas, &renderer)
    try render_one_sided_distribution_preview(a, queue, output_target, canvas, &renderer, false)
    try render_one_sided_distribution_preview(a, queue, output_target, canvas, &renderer, true)
    try render_slopegraph_preview(a, queue, output_target, canvas, &renderer)
    try render_connected_scatter_preview(a, queue, output_target, canvas, &renderer)
    try render_marginal_histogram_preview(a, queue, output_target, canvas, &renderer)
    try render_dose_response_preview(a, queue, output_target, canvas, &renderer)
    try render_hazard_rate_preview(a, queue, output_target, canvas, &renderer)
    try render_influence_plot_preview(a, queue, output_target, canvas, &renderer)
    try render_capability_nonnormal_preview(a, queue, output_target, canvas, &renderer)
    try render_capability_attribute_preview(a, queue, output_target, canvas, &renderer)
    try render_capability_batch_preview(a, queue, output_target, canvas, &renderer)
    try render_gage_bias_linearity_preview(a, queue, output_target, canvas, &renderer)
    try render_attribute_agreement_preview(a, queue, output_target, canvas, &renderer)
    try render_gage_run_preview(a, queue, output_target, canvas, &renderer)
    try render_map_preview(a, queue, output_target, canvas, &renderer, false)
    try render_map_preview(a, queue, output_target, canvas, &renderer, true)
    try render_cross_tab_report_preview(a, queue, output_target, canvas, &renderer)
    try render_matrix_report_preview(a, queue, output_target, canvas, &renderer)
    try render_capability_normal_preview(a, queue, output_target, canvas, &renderer)
    try render_capability_sixpack_preview(a, queue, output_target, canvas, &renderer)
    try render_fishbone_preview(a, queue, output_target, canvas, &renderer)
    try render_cause_effect_tree_preview(a, queue, output_target, canvas, &renderer)
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
    try render_ui_canvas_preview(a)
    try scene.close(&renderer)
    try gpu.close_target(output_target)
    try gpu.close(device)
    try io.print("chart previews ok\n")
    ret ok
}
