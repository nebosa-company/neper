use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [11]f64{ -23.0f64, -20.0f64, -19.0f64, -11.0f64, -10.0f64, -1.0f64, 0.0f64, 1.0f64, 12.0f64, 18.0f64, 18.0f64 }
    let bounds = geometry.rect(10.0, 10.0, 250.0, 120.0)
    var rows: [11]chart.StemLeafRow = zero
    var leaves: [11]u8 = zero
    let (tree, result) = chart.stem_and_leaf(values[..], 1.0f64, bounds, rows[..], leaves[..])
    if result != ok || tree.rows.len != 5usize || tree.leaves.len != values.len || tree.leaf_unit != 1.0f64 { ret chart.Invalid }
    if rows[0usize].stem != -3i64 || rows[0usize].count != 1usize || rows[1usize].stem != -2i64 || rows[1usize].first != 1usize || rows[1usize].count != 3usize || rows[2usize].stem != -1i64 || rows[3usize].stem != 0i64 || rows[4usize].stem != 1i64 || rows[4usize].first != 8usize || rows[4usize].count != 3usize { ret chart.Invalid }
    let expected = [11]u8{ 7u8, 0u8, 1u8, 9u8, 0u8, 9u8, 0u8, 1u8, 2u8, 8u8, 8u8 }
    var i = 0usize
    while i < leaves.len {
        if leaves[i] != expected[i] { ret chart.Invalid }
        i += 1usize
    }
    if rows[0usize].baseline >= rows[1usize].baseline || tree.divider.from.x != 67.0 || tree.divider.to.y != 130.0 || tree.leaf_start != 86.0 || tree.leaf_step != 18.0 { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    var divider: [1]chart.Segment = zero
    divider[0usize] = tree.divider
    let rule = chart.Layout { kind: .Rug, coords: zero, segments: divider[..], bars: zero, x_min: 10.0, x_max: 260.0, y_min: 10.0, y_max: 130.0 }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &rule, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 1usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 140.0, "Stem-and-leaf", "Leaf digits retain repeated values")
    try chart_svg.append(&writer, &rule, ink)
    let labels = [1]chart.Label{ chart.Label { text: "stem", anchor: chart.Coord { x: 20.0, y: 20.0 }, align: .Left } }
    try chart_svg.append_labels(&writer, labels[..], ink, 10.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "stem") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let decimals = [4]f64{ -1.24f64, -0.04f64, 0.04f64, 1.26f64 }
    let (decimal_tree, decimal_error) = chart.stem_and_leaf(decimals[..], 0.1f64, bounds, rows[..], leaves[..])
    if decimal_error != ok || decimal_tree.rows.len != 3usize || rows[0usize].stem != -2i64 || leaves[0usize] != 8u8 || rows[1usize].stem != 0i64 || rows[1usize].count != 2usize || leaves[1usize] != 0u8 || leaves[2usize] != 0u8 || rows[2usize].stem != 1i64 || leaves[3usize] != 3u8 { ret chart.Invalid }
    let unsorted = [2]f64{ 5.0f64, 4.0f64 }
    let huge = [1]f64{ 10000000000000.0f64 }
    let (_, empty_error) = chart.stem_and_leaf(values[..0usize], 1.0f64, bounds, rows[..], leaves[..])
    let (_, order_error) = chart.stem_and_leaf(unsorted[..], 1.0f64, bounds, rows[..], leaves[..])
    let (_, unit_error) = chart.stem_and_leaf(values[..], 0.0f64, bounds, rows[..], leaves[..])
    let (_, huge_error) = chart.stem_and_leaf(huge[..], 1.0f64, bounds, rows[..], leaves[..])
    let (_, bounds_error) = chart.stem_and_leaf(values[..], 1.0f64, geometry.rect(0.0, 0.0, -1.0, 120.0), rows[..], leaves[..])
    let (_, row_error) = chart.stem_and_leaf(values[..], 1.0f64, bounds, rows[..4usize], leaves[..])
    let (_, leaf_error) = chart.stem_and_leaf(values[..], 1.0f64, bounds, rows[..], leaves[..10usize])
    let (_, height_error) = chart.stem_and_leaf(values[..], 1.0f64, geometry.rect(10.0, 10.0, 250.0, 70.0), rows[..], leaves[..])
    let (_, width_error) = chart.stem_and_leaf(values[..], 1.0f64, geometry.rect(10.0, 10.0, 110.0, 120.0), rows[..], leaves[..])
    if empty_error != chart.Empty || order_error != chart.Invalid || unit_error != chart.Invalid || huge_error != chart.Invalid || bounds_error != chart.Invalid || row_error != chart.TooLarge || leaf_error != chart.TooLarge || height_error != chart.TooLarge || width_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart stem and leaf ok\n")
    ret ok
}
