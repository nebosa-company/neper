use e.gfx.chart
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.io
use e.mem
use e.str

// References: scripts/chart_network_reference.py runs the same steps in Python.
fn near(a: f32, b: f32, tolerance: f32) -> bool { ret a - b <= tolerance && b - a <= tolerance }

fn distance(a: chart.Coord, b: chart.Coord) -> f32 {
    let dx = a.x - b.x
    let dy = a.y - b.y
    ret dx * dx + dy * dy
}

fn main(a: *mem.Arena, args: []str) -> err {
    // A chain into a triangle, 50 steps into 200x100: matches the Python replica.
    let small_from = [6]u32{ 0u32, 1u32, 2u32, 3u32, 4u32, 5u32 }
    let small_to = [6]u32{ 1u32, 2u32, 3u32, 4u32, 5u32, 3u32 }
    var work: [136]f64 = zero
    var nodes: [34]chart.Coord = zero
    var segments: [78]chart.Segment = zero
    let bounds = geometry.rect(0.0, 0.0, 200.0, 100.0)
    let (small, small_error) = chart.network_layout(6usize, small_from[..], small_to[..], bounds, 50usize, work[..], nodes[..], segments[..])
    if small_error != ok || small.nodes.len != 6usize || small.links.segments.len != 6usize { ret chart.Invalid }
    let want_x = [6]f32{ 97.0709, 97.7389, 98.5267, 99.375, 91.7457, 108.2543 }
    let want_y = [6]f32{ 100.0, 76.8719, 49.7517, 21.066, 0.0, 0.5046 }
    var i = 0usize
    while i < 6usize {
        if !near(small.nodes[i].x, want_x[i], 0.05) || !near(small.nodes[i].y, want_y[i], 0.05) { ret chart.Invalid }
        i += 1usize
    }
    if !near(small.links.segments[5usize].from.x, small.nodes[5usize].x, 0.0001) || !near(small.links.segments[5usize].to.y, small.nodes[3usize].y, 0.0001) { ret chart.Invalid }
    // Zachary's karate club (NetworkX's edge list): every node inside the frame,
    // linked nodes closer on average than unlinked ones, no two nodes stacked.
    let from = [78]u32{ 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 1u32, 1u32, 1u32, 1u32, 1u32, 1u32, 1u32, 1u32, 2u32, 2u32, 2u32, 2u32, 2u32, 2u32, 2u32, 2u32, 3u32, 3u32, 3u32, 4u32, 4u32, 5u32, 5u32, 5u32, 6u32, 8u32, 8u32, 8u32, 9u32, 13u32, 14u32, 14u32, 15u32, 15u32, 18u32, 18u32, 19u32, 20u32, 20u32, 22u32, 22u32, 23u32, 23u32, 23u32, 23u32, 23u32, 24u32, 24u32, 24u32, 25u32, 26u32, 26u32, 27u32, 28u32, 28u32, 29u32, 29u32, 30u32, 30u32, 31u32, 31u32, 32u32 }
    let to = [78]u32{ 1u32, 2u32, 3u32, 4u32, 5u32, 6u32, 7u32, 8u32, 10u32, 11u32, 12u32, 13u32, 17u32, 19u32, 21u32, 31u32, 2u32, 3u32, 7u32, 13u32, 17u32, 19u32, 21u32, 30u32, 3u32, 7u32, 8u32, 9u32, 13u32, 27u32, 28u32, 32u32, 7u32, 12u32, 13u32, 6u32, 10u32, 6u32, 10u32, 16u32, 16u32, 30u32, 32u32, 33u32, 33u32, 33u32, 32u32, 33u32, 32u32, 33u32, 32u32, 33u32, 33u32, 32u32, 33u32, 32u32, 33u32, 25u32, 27u32, 29u32, 32u32, 33u32, 25u32, 27u32, 31u32, 31u32, 29u32, 33u32, 33u32, 31u32, 33u32, 32u32, 33u32, 32u32, 33u32, 32u32, 33u32, 33u32 }
    let frame = geometry.rect(10.0, 20.0, 400.0, 300.0)
    let (club, club_error) = chart.network_layout(34usize, from[..], to[..], frame, 300usize, work[..], nodes[..], segments[..])
    if club_error != ok || club.nodes.len != 34usize || club.links.segments.len != 78usize { ret chart.Invalid }
    var linked = 0.0f32
    var all = 0.0f32
    var pairs = 0.0f32
    var closest = 1000000.0f32
    i = 0usize
    while i < 34usize {
        let p = club.nodes[i]
        if p.x < 9.99 || p.x > 410.01 || p.y < 19.99 || p.y > 320.01 { ret chart.Invalid }
        var j = i + 1usize
        while j < 34usize {
            let d = distance(p, club.nodes[j])
            all += d
            pairs += 1.0
            if d < closest { closest = d }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 78usize {
        linked += distance(club.nodes[usize(from[i])], club.nodes[usize(to[i])])
        i += 1usize
    }
    if linked / 78.0 >= all / pairs / 2.0 || closest < 4.0 { ret chart.Invalid }
    // Deterministic: the same call gives the same picture.
    var again_nodes: [34]chart.Coord = zero
    var again_segments: [78]chart.Segment = zero
    var again_work: [136]f64 = zero
    let (again, again_error) = chart.network_layout(34usize, from[..], to[..], frame, 300usize, again_work[..], again_nodes[..], again_segments[..])
    if again_error != ok || again.nodes[33usize].x != club.nodes[33usize].x || again.nodes[0usize].y != club.nodes[0usize].y { ret chart.Invalid }
    // Self-loops get no segment; one node sits in the centre.
    let loop_from = [2]u32{ 0u32, 1u32 }
    let loop_to = [2]u32{ 0u32, 0u32 }
    let (looped, looped_error) = chart.network_layout(2usize, loop_from[..], loop_to[..], bounds, 10usize, work[..], nodes[..], segments[..])
    let (single, single_error) = chart.network_layout(1usize, loop_from[..0usize], loop_to[..0usize], bounds, 10usize, work[..], nodes[..], segments[..])
    if looped_error != ok || looped.links.segments.len != 1usize || single_error != ok || !near(single.nodes[0usize].x, 100.0, 0.001) || !near(single.nodes[0usize].y, 50.0, 0.001) { ret chart.Invalid }
    // The links stream through the existing adapters.
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.append(&writer, &club.links, paint.rgba(0.5, 0.5, 0.5, 1.0))
    if !str.contains(io.memory_bytes(&held), "<line") { ret chart.Invalid }
    let bad_to = [1]u32{ 9u32 }
    let (_, index_error) = chart.network_layout(2usize, loop_from[..1usize], bad_to[..], bounds, 10usize, work[..], nodes[..], segments[..])
    let (_, length_error) = chart.network_layout(2usize, loop_from[..], bad_to[..], bounds, 10usize, work[..], nodes[..], segments[..])
    let (_, work_error) = chart.network_layout(34usize, from[..], to[..], frame, 10usize, work[..135usize], nodes[..], segments[..])
    let (_, segment_error) = chart.network_layout(34usize, from[..], to[..], frame, 10usize, work[..], nodes[..], segments[..77usize])
    let (_, empty_error) = chart.network_layout(0usize, loop_from[..0usize], loop_to[..0usize], bounds, 10usize, work[..], nodes[..], segments[..])
    if index_error != chart.Invalid || length_error != chart.Invalid || work_error != chart.TooLarge || segment_error != chart.TooLarge || empty_error != chart.Empty { ret chart.Invalid }
    // A layered DAG (D2117): 0 -> 3 and 1 -> 2 cross in index order and one
    // downward sweep uncrosses them.
    let rows_frame = geometry.rect(0.0, 0.0, 100.0, 90.0)
    let cross_from = [2]u32{ 0u32, 1u32 }
    let cross_to = [2]u32{ 3u32, 2u32 }
    let (crossed, crossed_error) = chart.layered_layout(4usize, cross_from[..], cross_to[..], rows_frame, 0usize, work[..], nodes[..], segments[..])
    if crossed_error != ok || !near(crossed.nodes[2usize].x, 25.0, 0.001) || !near(crossed.nodes[3usize].x, 75.0, 0.001) || !near(crossed.nodes[0usize].y, 22.5, 0.001) || !near(crossed.nodes[2usize].y, 67.5, 0.001) { ret chart.Invalid }
    let (uncrossed, uncrossed_error) = chart.layered_layout(4usize, cross_from[..], cross_to[..], rows_frame, 1usize, work[..], nodes[..], segments[..])
    if uncrossed_error != ok || !near(uncrossed.nodes[3usize].x, 25.0, 0.001) || !near(uncrossed.nodes[2usize].x, 75.0, 0.001) || !near(uncrossed.nodes[0usize].x, 25.0, 0.001) || uncrossed.links.segments.len != 2usize { ret chart.Invalid }
    // A node's row is its longest path from a source, so every link points down.
    let path_from = [4]u32{ 0u32, 1u32, 0u32, 3u32 }
    let path_to = [4]u32{ 1u32, 2u32, 2u32, 2u32 }
    let (paths, paths_error) = chart.layered_layout(4usize, path_from[..], path_to[..], rows_frame, 4usize, work[..], nodes[..], segments[..])
    if paths_error != ok || !near(paths.nodes[1usize].y, 45.0, 0.001) || !near(paths.nodes[2usize].y, 75.0, 0.001) || !near(paths.nodes[3usize].y, 15.0, 0.001) { ret chart.Invalid }
    var down = 0usize
    while down < paths.links.segments.len {
        if !(paths.links.segments[down].to.y > paths.links.segments[down].from.y) { ret chart.Invalid }
        down += 1usize
    }
    let cycle_from = [2]u32{ 0u32, 1u32 }
    let cycle_to = [2]u32{ 1u32, 0u32 }
    let (_, cycle_error) = chart.layered_layout(2usize, cycle_from[..], cycle_to[..], rows_frame, 1usize, work[..], nodes[..], segments[..])
    let self_from = [2]u32{ 0u32, 0u32 }
    let self_to = [2]u32{ 0u32, 1u32 }
    let (layered_looped, layered_looped_error) = chart.layered_layout(2usize, self_from[..], self_to[..], rows_frame, 1usize, work[..], nodes[..], segments[..])
    let (_, layered_small_error) = chart.layered_layout(4usize, cross_from[..], cross_to[..], rows_frame, 1usize, work[..15usize], nodes[..], segments[..])
    if cycle_error != chart.Invalid || layered_looped_error != ok || layered_looped.links.segments.len != 1usize || layered_small_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart network ok\n")
    ret ok
}
