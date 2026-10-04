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
    ret d > -0.02 && d < 0.02
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 100.0, 50.0)
    var points: [196]chart.Coord = zero
    var marker: [1]chart.Segment = zero
    var storage: [3]chart.Layout = zero
    let (layers, layout_error) = chart.gauge(50.0, 75.0, 100.0, bounds, 0.5, points[..], marker[..], storage[..])
    if layout_error != ok || layers.len != 3usize || layers[0usize].kind != .Area || layers[1usize].kind != .Area || layers[2usize].kind != .Rug || layers[0usize].coords.len != 98usize || !near(points[0usize].x, 0.0) || !near(points[0usize].y, 50.0) || !near(points[48usize].x, 100.0) || !near(points[48usize].y, 50.0) || !near(points[49usize].x, 75.0) || !near(points[98usize + 48usize].x, 50.0) || !near(points[98usize + 48usize].y, 0.0) || !near(marker[0usize].to.x, 85.355) || !near(marker[0usize].to.y, 14.645) { ret chart.Invalid }
    let (_, zero_error) = chart.gauge(0.0, 0.0, 100.0, bounds, 0.5, points[..], marker[..], storage[..])
    if zero_error != ok || !near(points[98usize].x, 0.0) || !near(marker[0usize].to.x, 0.0) { ret chart.Invalid }
    let (_, limit_error) = chart.gauge(100.0, 100.0, 100.0, bounds, 0.5, points[..], marker[..], storage[..])
    if limit_error != ok || !near(points[98usize + 48usize].x, 100.0) { ret chart.Invalid }
    let (_, maximum_error) = chart.gauge(50.0, 75.0, 0.0, bounds, 0.5, points[..], marker[..], storage[..])
    if maximum_error != chart.Invalid { ret chart.Invalid }
    let (_, range_error) = chart.gauge(101.0, 75.0, 100.0, bounds, 0.5, points[..], marker[..], storage[..])
    if range_error != chart.Invalid { ret chart.Invalid }
    let (_, hole_error) = chart.gauge(50.0, 75.0, 100.0, bounds, 1.0, points[..], marker[..], storage[..])
    if hole_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.gauge(50.0, 75.0, 100.0, bounds, 0.5, points[..195usize], marker[..], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (above, above_error) = chart.target_status(96.0, 80.0, true)
    let (below, below_error) = chart.target_status(72.0, 80.0, true)
    let (lower_better, lower_error) = chart.target_status(72.0, 80.0, false)
    let (equal, equal_error) = chart.target_status(80.0, 80.0, false)
    if above_error != ok || !near(above.delta, 16.0) || !above.achieved || below_error != ok || !near(below.delta, -8.0) || below.achieved || lower_error != ok || !lower_better.achieved || equal_error != ok || !equal.achieved { ret chart.Invalid }
    let (valid_layers, valid_error) = chart.gauge(50.0, 75.0, 100.0, bounds, 0.5, points[..], marker[..], storage[..])
    if valid_error != ok { ret valid_error }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < valid_layers.len {
        try chart_scene.append(a, &builder, &valid_layers[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 3usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 50.0, "Gauge", "Measured value and target")
    i = 0usize
    while i < valid_layers.len {
        try chart_svg.append(&writer, &valid_layers[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart gauge ok\n")
    ret ok
}
