// Chart throughput: the same workload as mpl_bench.py, timed in-process.
// Each chart is a 1,000-point line, 200 scatter points, a y grid with tick
// labels and a title at 360x240, laid out, then written as SVG and as PNG.
// Prints one line per pass: name, charts, milliseconds, output bytes.
use e.fmt.png
use e.fs
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.io
use e.math
use e.mem
use e.text.shape
use e.time

const WIDTH: u32 = 360u32
const HEIGHT: u32 = 240u32
const POINTS: usize = 1000usize
const CHARTS: usize = 200usize

type Data = struct { x: [1000]f32, y: [1000]f32, sx: [200]f32, sy: [200]f32 }

// Deterministic data shared with the Python side: a sine whose frequency
// varies per chart, plus LCG noise in [-0.15, 0.15).
fn fill(d: *Data, chart_index: usize) {
    var state = 1u64 + u64(chart_index)
    let frequency = 1.0f64 + f64(chart_index % 5usize) * 0.2f64
    var i = 0usize
    while i < POINTS {
        state = (state * 1103515245u64 + 12345u64) % 2147483648u64
        let noise = (f64(state) / 2147483648.0f64 - 0.5f64) * 0.3f64
        let x = 10.0f64 * f64(i) / 999.0f64
        d.x[i] = f32(x)
        d.y[i] = f32(math.sin[f64](x * frequency) + noise)
        i += 1usize
    }
    var k = 0usize
    while k < 200usize {
        d.sx[k] = d.x[k * 5usize]
        d.sy[k] = d.y[k * 5usize] + 0.5
        k += 1usize
    }
}

type Marks = struct { line: chart.Layout, dots: chart.Layout, ticks: []chart.Tick, labels: []chart.Label }

type Storage = struct { coords: [1000]chart.Coord, segments: [999]chart.Segment, dots: [200]chart.Coord, ticks: [12]chart.Tick, tick_text: [12]str, text_bytes: [256]u8, labels: [13]chart.Label }

fn lay_out(d: *const Data, s: *Storage, plot: geometry.Rect) -> (Marks, err) {
    let x_limits = [2]f32{ 0.0, 10.0 }
    let y_limits = [2]f32{ -2.0, 2.5 }
    let line_spec = chart.spec(.Line, plot, d.x[..], d.y[..])
    let (line, line_error) = chart.layout_with_limits(&line_spec, s.coords[..], s.segments[..], zero, x_limits[..], y_limits[..])
    if line_error != ok { ret (zero, line_error) }
    let dot_spec = chart.spec(.Scatter, plot, d.sx[..], d.sy[..])
    let (dots, dots_error) = chart.layout_with_limits(&dot_spec, s.dots[..], zero, zero, x_limits[..], y_limits[..])
    if dots_error != ok { ret (zero, dots_error) }
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    let (ticks, tick_error) = chart.nice_ticks(linear, -2.0, 2.5, 5usize, s.ticks[..])
    if tick_error != ok { ret (zero, tick_error) }
    let (text, text_error) = chart.format_ticks(ticks, s.tick_text[..], s.text_bytes[..])
    if text_error != ok { ret (zero, text_error) }
    let (labels, label_error) = chart.guide_labels(plot, zero, zero, ticks, text, 8.0, s.labels[1usize..])
    if label_error != ok { ret (zero, label_error) }
    s.labels[0usize] = chart.Label { text: "Signal with samples", anchor: chart.Coord { x: 180.0, y: 18.0 }, align: .Center }
    ret (Marks { line: line, dots: dots, ticks: ticks, labels: s.labels[..labels.len + 1usize] }, ok)
}

fn ms(d: time.Duration) -> f64 { ret f64(d.nanos) / 1000000.0f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let blue = paint.rgba(0.0, 114.0 / 255.0, 178.0 / 255.0, 1.0)
    let orange = paint.rgba(195.0 / 255.0, 86.0 / 255.0, 0.0, 1.0)
    let grid = paint.rgba(0.84, 0.87, 0.92, 1.0)
    let dark = paint.rgba(0.16, 0.20, 0.28, 1.0)
    let plot = geometry.rect(40.0, 28.0, 306.0, 190.0)
    let (data_storage, data_error) = mem.alloc[Data](a, 1usize)
    if data_error != ok { ret data_error }
    let d = &data_storage[0usize]
    let (mark_storage, storage_error) = mem.alloc[Storage](a, 1usize)
    if storage_error != ok { ret storage_error }
    let s = &mark_storage[0usize]

    // Layout only: geometry, ticks and labels, no output.
    var start = try time.monotonic()
    var j = 0usize
    while j < CHARTS {
        fill(d, j)
        let (marks, marks_error) = lay_out(d, s, plot)
        if marks_error != ok { ret marks_error }
        j += 1usize
    }
    try io.printf["layout {} {} 0\n"](CHARTS, ms(time.since(start)))

    // SVG: stream every chart into memory.
    var svg_bytes = 0usize
    start = try time.monotonic()
    j = 0usize
    while j < CHARTS {
        let mark = mem.mark(a)
        fill(d, j)
        let marks = try lay_out(d, s, plot)
        let (state, unused, writer_error) = io.memory_writer(a, 0usize)
        if writer_error != ok { ret writer_error }
        var held = state
        var writer = io.writer(mem.cast[*void](&held), io.memory_write)
        try chart_svg.begin(&writer, f32(WIDTH), f32(HEIGHT), "Signal with samples", "Benchmark chart")
        try chart_svg.rect(&writer, geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), white, false)
        try chart_svg.append_guides(&writer, plot, zero, marks.ticks, grid, grid)
        try chart_svg.append(&writer, &marks.line, blue)
        try chart_svg.append(&writer, &marks.dots, orange)
        try chart_svg.append_labels(&writer, marks.labels, dark, 8.0)
        try chart_svg.finish(&writer)
        svg_bytes += io.memory_bytes(&held).len
        mem.reset(a, mark)
        j += 1usize
    }
    try io.printf["svg {} {} {}\n"](CHARTS, ms(time.since(start)), svg_bytes)

    // PNG: CPU scene rasterization and PNG encoding, in memory.
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
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    try scene.register_font(&renderer, font)
    // Rasterization alone, to split the PNG time between scene and encoder.
    start = try time.monotonic()
    j = 0usize
    while j < CHARTS {
        let mark = mem.mark(a)
        fill(d, j)
        let marks = try lay_out(d, s, plot)
        let (made, builder_error) = scene.builder(a, 512usize)
        if builder_error != ok { ret builder_error }
        var builder = made
        try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), brush: paint.Brush { Solid: white } } })
        try chart_scene.append_guides(&builder, plot, zero, marks.ticks, paint.Brush { Solid: grid }, paint.Brush { Solid: grid })
        try chart_scene.append(a, &builder, &marks.line, paint.Brush { Solid: blue })
        try chart_scene.append(a, &builder, &marks.dots, paint.Brush { Solid: orange })
        try chart_scene.append_labels(a, &builder, marks.labels, font, 8.0, paint.Brush { Solid: dark })
        let view = try chart_scene.rasterize(a, queue, output_target, canvas, &renderer, &builder, WIDTH, HEIGHT)
        mem.reset(a, mark)
        j += 1usize
    }
    try io.printf["raster {} {} 0\n"](CHARTS, ms(time.since(start)))
    var png_bytes = 0usize
    start = try time.monotonic()
    j = 0usize
    while j < CHARTS {
        let mark = mem.mark(a)
        fill(d, j)
        let marks = try lay_out(d, s, plot)
        let (made, builder_error) = scene.builder(a, 512usize)
        if builder_error != ok { ret builder_error }
        var builder = made
        try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, f32(WIDTH), f32(HEIGHT)), brush: paint.Brush { Solid: white } } })
        try chart_scene.append_guides(&builder, plot, zero, marks.ticks, paint.Brush { Solid: grid }, paint.Brush { Solid: grid })
        try chart_scene.append(a, &builder, &marks.line, paint.Brush { Solid: blue })
        try chart_scene.append(a, &builder, &marks.dots, paint.Brush { Solid: orange })
        try chart_scene.append_labels(a, &builder, marks.labels, font, 8.0, paint.Brush { Solid: dark })
        let view = try chart_scene.rasterize(a, queue, output_target, canvas, &renderer, &builder, WIDTH, HEIGHT)
        let (state, unused, writer_error) = io.memory_writer(a, 0usize)
        if writer_error != ok { ret writer_error }
        var held = state
        var writer = io.writer(mem.cast[*void](&held), io.memory_write)
        try png.encode(&writer, view, png.EncodeOptions { compression: .Balanced, interlace: false })
        png_bytes += io.memory_bytes(&held).len
        if j == 0usize && args.len > 1usize { try fs.write_file(a, args[1usize], io.memory_bytes(&held)) }
        mem.reset(a, mark)
        j += 1usize
    }
    try io.printf["png {} {} {}\n"](CHARTS, ms(time.since(start)), png_bytes)
    try scene.close(&renderer)
    try gpu.close_target(output_target)
    ret gpu.close(device)
}
