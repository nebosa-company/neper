use e.gfx.chart
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001 && b - a < 0.001 }

fn box_is(p: chart.LabelPlacement, slot: u8, x: f32, y: f32) -> bool {
    ret p.placed && p.slot == slot && near(p.box.x, x) && near(p.box.y, y) && near(p.label.anchor.x, x) && near(p.label.anchor.y, y + 8.0)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 200.0, 100.0)
    let texts = [2]str{ "alpha", "beta" }
    let widths = [2]f32{ 20.0, 20.0 }
    var out: [40]chart.LabelPlacement = zero
    // Alone, a label takes the upper right; at the right edge it flips left.
    let alone = [1]chart.Coord{ chart.Coord { x: 50.0, y: 50.0 } }
    let (single, single_error) = chart.place_point_labels(alone[..], texts[..1usize], widths[..1usize], 10.0, 8.0, bounds, 2.0, 1.0, out[..])
    if single_error != ok || single.placed != 1usize || !box_is(single.labels[0usize], 0u8, 52.0, 38.0) { ret chart.Invalid }
    let edge = [1]chart.Coord{ chart.Coord { x: 195.0, y: 50.0 } }
    let (flipped, flipped_error) = chart.place_point_labels(edge[..], texts[..1usize], widths[..1usize], 10.0, 8.0, bounds, 2.0, 1.0, out[..])
    if flipped_error != ok || !box_is(flipped.labels[0usize], 1u8, 173.0, 38.0) { ret chart.Invalid }
    // A neighbouring point blocks the first label's upper right.
    let pair = [2]chart.Coord{ chart.Coord { x: 50.0, y: 50.0 }, chart.Coord { x: 60.0, y: 40.0 } }
    var pair_out: [2]chart.LabelPlacement = zero
    let (both, both_error) = chart.place_point_labels(pair[..], texts[..], widths[..], 10.0, 8.0, bounds, 2.0, 1.0, pair_out[..])
    if both_error != ok || both.placed != 2usize || !box_is(both.labels[0usize], 1u8, 28.0, 38.0) || !box_is(both.labels[1usize], 0u8, 62.0, 28.0) { ret chart.Invalid }
    // Forty clustered points: 27 labels fit (a Python replica of the rule
    // agrees on every slot); the rest are reported, never overlapped.
    var points: [40]chart.Coord = zero
    var names: [40]str = zero
    var cluster_widths: [40]f32 = zero
    var state = 1u64
    var i = 0usize
    while i < 40usize {
        state = (state * 1103515245u64 + 12345u64) % 2147483648u64
        let x = 20.0 + f32(state % 160u64)
        state = (state * 1103515245u64 + 12345u64) % 2147483648u64
        points[i] = chart.Coord { x: x, y: 20.0 + f32(state % 60u64) }
        names[i] = "pt"
        cluster_widths[i] = 18.0
        i += 1usize
    }
    let (cluster, cluster_error) = chart.place_point_labels(points[..], names[..], cluster_widths[..], 10.0, 8.0, bounds, 2.0, 1.0, out[..])
    if cluster_error != ok || cluster.placed != 27usize || cluster.labels.len != 40usize { ret chart.Invalid }
    let slots = [10]u8{ 0u8, 0u8, 0u8, 0u8, 0u8, 2u8, 7u8, 1u8, 9u8, 9u8 }
    i = 0usize
    while i < slots.len {
        let p = cluster.labels[i]
        if (slots[i] == 9u8 && p.placed) || (slots[i] != 9u8 && (!p.placed || p.slot != slots[i])) { ret chart.Invalid }
        i += 1usize
    }
    i = 0usize
    while i < 40usize {
        let p = cluster.labels[i]
        if p.placed {
            if p.box.x < 0.0 || p.box.y < 0.0 || p.box.x + p.box.width > 200.0 || p.box.y + p.box.height > 100.0 { ret chart.Invalid }
            var j = 0usize
            while j < 40usize {
                let q = cluster.labels[j]
                if j != i && q.placed && chart.boxes_overlap(p.box, q.box) { ret chart.Invalid }
                if j != i && points[j].x > p.box.x - 1.0 && points[j].x < p.box.x + p.box.width + 1.0 && points[j].y > p.box.y - 1.0 && points[j].y < p.box.y + p.box.height + 1.0 { ret chart.Invalid }
                j += 1usize
            }
        }
        i += 1usize
    }
    // Placed labels feed the existing label adapters.
    let (state_writer, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state_writer
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    var labels: [2]chart.Label = zero
    labels[0usize] = both.labels[0usize].label
    labels[1usize] = both.labels[1usize].label
    try chart_svg.append_labels(&writer, labels[..], paint.rgba(0.0, 0.0, 0.0, 1.0), 8.0)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "<text x=\"28\" y=\"46\"") || !str.contains(output, ">beta</text>") { ret chart.Invalid }
    let (_, empty_error) = chart.place_point_labels(points[..0usize], names[..0usize], cluster_widths[..0usize], 10.0, 8.0, bounds, 2.0, 1.0, out[..])
    let (_, mismatch_error) = chart.place_point_labels(points[..2usize], names[..1usize], cluster_widths[..2usize], 10.0, 8.0, bounds, 2.0, 1.0, out[..])
    let (_, short_error) = chart.place_point_labels(points[..], names[..], cluster_widths[..], 10.0, 8.0, bounds, 2.0, 1.0, out[..39usize])
    let (_, width_error) = chart.place_point_labels(pair[..], texts[..], cluster_widths[..2usize], 10.0, 12.0, bounds, 2.0, 1.0, out[..])
    let zero_widths = [2]f32{ 20.0, 0.0 }
    let (_, zero_error) = chart.place_point_labels(pair[..], texts[..], zero_widths[..], 10.0, 8.0, bounds, 2.0, 1.0, out[..])
    let (_, bounds_error) = chart.place_point_labels(pair[..], texts[..], widths[..], 10.0, 8.0, geometry.rect(0.0, 0.0, 0.0, 10.0), 2.0, 1.0, out[..])
    if empty_error != chart.Empty || mismatch_error != chart.Invalid || short_error != chart.TooLarge || width_error != chart.Invalid || zero_error != chart.Invalid || bounds_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart label placement ok\n")
    ret ok
}
