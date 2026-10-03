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
    if !near(f32(chart.circle_overlap_area(1.0f64, 1.0f64, 1.0f64)), 1.22837) { ret chart.Invalid }
    let bounds = geometry.rect(0.0, 0.0, 140.0, 100.0)
    var circles: [3]geometry.Rect = zero
    var layers: [3]chart.Layout = zero
    let (euler, euler_error) = chart.euler2(10.0, 10.0, 5.0, bounds, circles[..], layers[..])
    if euler_error != ok || euler.len != 2usize || euler[0usize].kind != .Bubble || euler[0usize].bars.len != 1usize || !near(circles[0usize].width, circles[1usize].width) { ret chart.Invalid }
    let r1 = circles[0usize].width * 0.5
    let r2 = circles[1usize].width * 0.5
    let c1 = circles[0usize].x + r1
    let c2 = circles[1usize].x + r2
    let actual = chart.circle_overlap_area(f64(r1), f64(r2), f64(c2 - c1))
    let circle_area = 3.141592653589793f64 * f64(r1) * f64(r1)
    if !near(f32(actual / circle_area), 0.5) { ret chart.Invalid }
    let (disjoint, disjoint_error) = chart.euler2(10.0, 25.0, 0.0, bounds, circles[..], layers[..])
    if disjoint_error != ok || disjoint.len != 2usize || circles[1usize].x + circles[1usize].width * 0.5 - (circles[0usize].x + circles[0usize].width * 0.5) < (circles[0usize].width + circles[1usize].width) * 0.5 { ret chart.Invalid }
    let (contained, contained_error) = chart.euler2(10.0, 40.0, 10.0, bounds, circles[..], layers[..])
    if contained_error != ok || contained.len != 2usize || !near(circles[0usize].x + circles[0usize].width * 0.5, circles[1usize].x + circles[1usize].width * 0.5) || !near(circles[0usize].width / circles[1usize].width, 0.5) { ret chart.Invalid }
    let (zero_layers, zero_error) = chart.euler2(0.0, 10.0, 0.0, bounds, circles[..], layers[..])
    if zero_error != ok || zero_layers[0usize].bars.len != 0usize || zero_layers[1usize].bars.len != 1usize { ret chart.Invalid }
    let (_, negative_error) = chart.euler2(-1.0, 10.0, 0.0, bounds, circles[..], layers[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let (_, overlap_error) = chart.euler2(5.0, 10.0, 6.0, bounds, circles[..], layers[..])
    if overlap_error != chart.Invalid { ret chart.Invalid }
    let (_, empty_error) = chart.euler2(0.0, 0.0, 0.0, bounds, circles[..], layers[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    let (_, capacity_error) = chart.euler2(10.0, 10.0, 5.0, bounds, circles[..1usize], layers[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (again, again_error) = chart.euler2(10.0, 10.0, 5.0, bounds, circles[..], layers[..])
    if again_error != ok { ret again_error }
    let blue = paint.rgba(0.1, 0.3, 0.8, 0.6)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    var i = 0usize
    while i < again.len {
        try chart_scene.append(a, &builder, &again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 140.0, 100.0, "Euler", "Measured two-set overlap")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<circle") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    var anchors: [7]chart.Coord = zero
    let venn_bounds = geometry.rect(0.0, 0.0, 200.0, 180.0)
    let (venn, venn_error) = chart.venn3(venn_bounds, circles[..], anchors[..], layers[..])
    if venn_error != ok || venn.len != 3usize || !near(circles[0usize].width, circles[1usize].width) || !near(circles[1usize].width, circles[2usize].width) { ret chart.Invalid }
    let masks = [7]usize{ 1usize, 2usize, 4usize, 3usize, 5usize, 6usize, 7usize }
    let bits = [3]usize{ 1usize, 2usize, 4usize }
    i = 0usize
    while i < 7usize {
        var mask = 0usize
        var j = 0usize
        while j < 3usize {
            let dx = anchors[i].x - (circles[j].x + circles[j].width * 0.5)
            let dy = anchors[i].y - (circles[j].y + circles[j].height * 0.5)
            let radius = circles[j].width * 0.5
            if dx * dx + dy * dy < radius * radius { mask += bits[j] }
            j += 1usize
        }
        if mask != masks[i] { ret chart.Invalid }
        i += 1usize
    }
    let (_, venn_capacity_error) = chart.venn3(venn_bounds, circles[..], anchors[..6usize], layers[..])
    if venn_capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, venn_bounds_error) = chart.venn3(geometry.rect(0.0, 0.0, -1.0, 100.0), circles[..], anchors[..], layers[..])
    if venn_bounds_error != chart.Invalid { ret chart.Invalid }
    let (venn_again, venn_again_error) = chart.venn3(venn_bounds, circles[..], anchors[..], layers[..])
    if venn_again_error != ok { ret venn_again_error }
    let (venn_made, venn_builder_error) = scene.builder(a, 8usize)
    if venn_builder_error != ok { ret venn_builder_error }
    var venn_builder = venn_made
    i = 0usize
    while i < venn_again.len {
        try chart_scene.append(a, &venn_builder, &venn_again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&venn_builder) != 3usize { ret chart.Invalid }
    let (venn_state, venn_unused, venn_writer_error) = io.memory_writer(a, 0usize)
    if venn_writer_error != ok { ret venn_writer_error }
    var venn_held = venn_state
    var venn_writer = io.writer(mem.cast[*void](&venn_held), io.memory_write)
    try chart_svg.begin(&venn_writer, 200.0, 180.0, "Venn", "Seven membership regions")
    i = 0usize
    while i < venn_again.len {
        try chart_svg.append(&venn_writer, &venn_again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&venn_writer)
    if !str.contains(io.memory_bytes(&venn_held), "<circle") || !str.contains(io.memory_bytes(&venn_held), "</svg>") { ret chart.Invalid }
    try io.print("gfx chart venn euler ok\n")
    ret ok
}
