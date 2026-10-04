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
    let parents = [7]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 2usize, 2usize }
    let weights = [7]f32{ 0.0, 0.0, 0.0, 4.0, 2.0, 3.0, 1.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var totals: [7]f64 = zero
    var circles: [7]geometry.Rect = zero
    var storage: [7]chart.Layout = zero
    let (layers, layout_error) = chart.circle_pack(parents[..], weights[..], bounds, 0.0, totals[..], circles[..], storage[..])
    if layout_error != ok || layers.len != 7usize || !near(f32(totals[0usize]), 10.0) || !near(circles[0usize].width, 100.0) || !near(circles[1usize].x, 50.0) || !near(circles[1usize].width, 50.0) || !near(circles[2usize].width, 40.82483) || !near(circles[3usize].width, 25.0) || !near(circles[4usize].width, 17.67767) { ret chart.Invalid }
    var i = 1usize
    while i < layers.len {
        let child = circles[i]
        let parent = circles[parents[i]]
        let dx = child.x + child.width * 0.5 - parent.x - parent.width * 0.5
        let dy = child.y + child.height * 0.5 - parent.y - parent.height * 0.5
        if dx * dx + dy * dy > (parent.width * 0.5 - child.width * 0.5 + 0.02) * (parent.width * 0.5 - child.width * 0.5 + 0.02) { ret chart.Invalid }
        var j = 1usize
        while j < i {
            if parents[j] == parents[i] {
                let other = circles[j]
                let sx = child.x + child.width * 0.5 - other.x - other.width * 0.5
                let sy = child.y + child.height * 0.5 - other.y - other.height * 0.5
                let sum = (child.width + other.width) * 0.5
                if sx * sx + sy * sy + 0.02 < sum * sum { ret chart.Invalid }
            }
            j += 1usize
        }
        i += 1usize
    }
    let bad_parents = [7]usize{ 0usize, 0usize, 4usize, 1usize, 1usize, 2usize, 2usize }
    let (_, parent_error) = chart.circle_pack(bad_parents[..], weights[..], bounds, 0.0, totals[..], circles[..], storage[..])
    if parent_error != chart.Invalid { ret chart.Invalid }
    let bad_weights = [7]f32{ 0.0, 1.0, 0.0, 4.0, 2.0, 3.0, 1.0 }
    let (_, weight_error) = chart.circle_pack(parents[..], bad_weights[..], bounds, 0.0, totals[..], circles[..], storage[..])
    if weight_error != chart.Invalid { ret chart.Invalid }
    let (_, padding_error) = chart.circle_pack(parents[..], weights[..], bounds, 1.0, totals[..], circles[..], storage[..])
    if padding_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.circle_pack(parents[..], weights[..], bounds, 0.0, totals[..], circles[..6usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let zero_leaf = [7]f32{ 0.0, 0.0, 0.0, 4.0, 2.0, 3.0, 0.0 }
    let (zero_layers, zero_error) = chart.circle_pack(parents[..], zero_leaf[..], bounds, 0.0, totals[..], circles[..], storage[..])
    if zero_error != ok || zero_layers[6usize].bars.len != 0usize { ret chart.Invalid }
    let root_parents = [1]usize{ 0usize }
    let root_weights = [1]f32{ 5.0 }
    let (root, root_error) = chart.circle_pack(root_parents[..], root_weights[..], bounds, 0.0, totals[..], circles[..], storage[..])
    if root_error != ok || root.len != 1usize || !near(circles[0usize].width, 100.0) { ret chart.Invalid }
    let triple_parents = [4]usize{ 0usize, 0usize, 0usize, 0usize }
    let triple_weights = [4]f32{ 0.0, 4.0, 2.0, 1.0 }
    let (triple, triple_error) = chart.circle_pack(triple_parents[..], triple_weights[..], bounds, 0.1, totals[..], circles[..], storage[..])
    if triple_error != ok || triple.len != 4usize || !near(circles[1usize].width / circles[2usize].width, 1.41421) || !near(circles[2usize].width / circles[3usize].width, 1.41421) { ret chart.Invalid }
    let (again, again_error) = chart.circle_pack(parents[..], weights[..], bounds, 0.0, totals[..], circles[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 10usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    i = 0usize
    while i < again.len {
        try chart_scene.append(a, &builder, &again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Circle packing", "Nested circles proportional to hierarchy weights")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<circle") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart circle pack ok\n")
    ret ok
}
