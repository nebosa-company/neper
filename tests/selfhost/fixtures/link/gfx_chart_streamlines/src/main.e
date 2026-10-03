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
    let delta = a - b
    ret delta > -0.02 && delta < 0.02
}

fn main(a: *mem.Arena, args: []str) -> err {
    let uniform = [9]f32{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 }
    let zeroes = [9]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
    let shear = [9]f32{ 0.0, 1.0, 2.0, 0.0, 1.0, 2.0, 0.0, 1.0, 2.0 }
    let seeds = [1]chart.Coord{ chart.Coord { x: 0.0, y: 0.5 } }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var storage: [8]chart.Segment = zero
    let (marks, stream_error) = chart.streamlines(uniform[..], zeroes[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, seeds[..], 0.25, 8usize, bounds, storage[..])
    if stream_error != ok || marks.kind != .Rug || marks.segments.len != 4usize || !near(marks.x_min, 0.0) || !near(marks.x_max, 1.0) { ret chart.Invalid }
    if !near(storage[0usize].from.x, 0.0) || !near(storage[0usize].from.y, 50.0) || !near(storage[0usize].to.x, 25.0) || !near(storage[3usize].to.x, 100.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Streamlines", "Midpoint-integrated vector field")
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (curved, curved_error) = chart.streamlines(uniform[..], shear[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, seeds[..], 0.5, 1usize, bounds, storage[..])
    if curved_error != ok || curved.segments.len != 1usize || !near(storage[0usize].to.x, 44.72) || !near(storage[0usize].to.y, 27.64) { ret chart.Invalid }
    let edge = [1]chart.Coord{ chart.Coord { x: 0.9, y: 0.5 } }
    let (clipped, clipped_error) = chart.streamlines(uniform[..], zeroes[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, edge[..], 0.5, 4usize, bounds, storage[..])
    if clipped_error != ok || clipped.segments.len != 1usize || !near(storage[0usize].to.x, 100.0) { ret chart.Invalid }
    let (stopped, stopped_error) = chart.streamlines(zeroes[..], zeroes[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, seeds[..], 0.25, 8usize, bounds, storage[..])
    if stopped_error != ok || stopped.segments.len != 0usize { ret chart.Invalid }
    let (_, shape_error) = chart.streamlines(uniform[..8usize], zeroes[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, seeds[..], 0.25, 8usize, bounds, storage[..])
    let (_, step_error) = chart.streamlines(uniform[..], zeroes[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, seeds[..], 0.0, 8usize, bounds, storage[..])
    let (_, capacity_error) = chart.streamlines(uniform[..], zeroes[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, seeds[..], 0.25, 8usize, bounds, storage[..3usize])
    let outside = [1]chart.Coord{ chart.Coord { x: -0.1, y: 0.5 } }
    let (_, seed_error) = chart.streamlines(uniform[..], zeroes[..], 3usize, 3usize, 0.0, 1.0, 0.0, 1.0, outside[..], 0.25, 8usize, bounds, storage[..])
    if shape_error != chart.Invalid || step_error != chart.Invalid || capacity_error != chart.TooLarge || seed_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart streamlines ok\n")
    ret ok
}
