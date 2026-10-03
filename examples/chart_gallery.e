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
use e.gfx.paint
use e.gfx.scene
use e.text.shape

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
    try render_labeled_chart(a, queue, output_target, canvas, &renderer, 0u8)
    try render_labeled_chart(a, queue, output_target, canvas, &renderer, 1u8)
    try render_labeled_chart(a, queue, output_target, canvas, &renderer, 2u8)
    try scene.close(&renderer)
    try gpu.close_target(output_target)
    try gpu.close(device)
    try io.print("chart previews ok\n")
    ret ok
}
