use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d > -0.01 && d < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let base = 1700000000000.0f64
    let spans = [5]chart.StateSpan{
        chart.StateSpan { row: 0usize, start: base, end: base + 2000.0f64, state: 0usize },
        chart.StateSpan { row: 0usize, start: base + 2000.0f64, end: base + 5000.0f64, state: 0usize },
        chart.StateSpan { row: 0usize, start: base + 7000.0f64, end: base + 9000.0f64, state: 1usize },
        chart.StateSpan { row: 1usize, start: base, end: base + 3000.0f64, state: 1usize },
        chart.StateSpan { row: 1usize, start: base + 3000.0f64, end: base + 12000.0f64, state: 0usize },
    }
    let bounds = geometry.rect(10.0, 20.0, 120.0, 60.0)
    var rects: [5]geometry.Rect = zero
    var states: [5]usize = zero
    var storage: [5]chart.Layout = zero
    let (layers, layout_error) = chart.state_timeline(spans[..], 2usize, 2usize, base, base + 12000.0f64, bounds, 4.0, rects[..], states[..], storage[..])
    if layout_error != ok || layers.len != 4usize || layers[0usize].kind != .Bar || !near(rects[0usize].x, 10.0) || !near(rects[0usize].width, 50.0) || !near(rects[0usize].height, 28.0) || !near(rects[1usize].x, 80.0) || !near(rects[1usize].width, 20.0) || !near(rects[2usize].y, 52.0) || !near(rects[3usize].x, 40.0) || states[0usize] != 0usize || states[1usize] != 1usize || states[2usize] != 1usize || states[3usize] != 0usize { ret chart.Invalid }
    let unordered = [2]chart.StateSpan{ spans[1usize], spans[0usize] }
    let (_, order_error) = chart.state_timeline(unordered[..], 2usize, 2usize, base, base + 12000.0f64, bounds, 4.0, rects[..], states[..], storage[..])
    if order_error != chart.Invalid { ret chart.Invalid }
    let overlap = [2]chart.StateSpan{ spans[0usize], chart.StateSpan { row: 0usize, start: base + 1000.0f64, end: base + 3000.0f64, state: 1usize } }
    let (_, overlap_error) = chart.state_timeline(overlap[..], 2usize, 2usize, base, base + 12000.0f64, bounds, 4.0, rects[..], states[..], storage[..])
    if overlap_error != chart.Invalid { ret chart.Invalid }
    let wrong_state = [1]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base, end: base + 1000.0f64, state: 2usize } }
    let (_, state_error) = chart.state_timeline(wrong_state[..], 2usize, 2usize, base, base + 12000.0f64, bounds, 4.0, rects[..], states[..], storage[..])
    if state_error != chart.Invalid { ret chart.Invalid }
    let (_, domain_error) = chart.state_timeline(spans[..], 2usize, 2usize, base, base + 11000.0f64, bounds, 4.0, rects[..], states[..], storage[..])
    if domain_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.state_timeline(spans[..], 2usize, 2usize, base, base + 12000.0f64, bounds, 4.0, rects[..4usize], states[..], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, gap_error) = chart.state_timeline(spans[..], 2usize, 2usize, base, base + 12000.0f64, bounds, 60.0, rects[..], states[..], storage[..])
    if gap_error != chart.Invalid { ret chart.Invalid }
    let (valid_layers, valid_error) = chart.state_timeline(spans[..], 2usize, 2usize, base, base + 12000.0f64, bounds, 4.0, rects[..], states[..], storage[..])
    if valid_error != ok { ret valid_error }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < valid_layers.len {
        try chart_scene.append(a, &builder, &valid_layers[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 140.0, 90.0, "State timeline", "Categorical states")
    i = 0usize
    while i < valid_layers.len {
        try chart_svg.append(&writer, &valid_layers[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart state timeline ok\n")
    ret ok
}
