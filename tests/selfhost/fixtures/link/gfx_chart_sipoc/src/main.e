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
    ret delta > -0.001 && delta < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let entries = [7]chart.SipocEntry{
        chart.SipocEntry { column: 2usize },
        chart.SipocEntry { column: 0usize },
        chart.SipocEntry { column: 4usize },
        chart.SipocEntry { column: 2usize },
        chart.SipocEntry { column: 1usize },
        chart.SipocEntry { column: 3usize },
        chart.SipocEntry { column: 2usize },
    }
    let bounds = geometry.rect(0.0, 0.0, 340.0, 180.0)
    var columns: [5]geometry.Rect = zero
    var headers: [5]geometry.Rect = zero
    var cards: [7]geometry.Rect = zero
    var arrows: [12]chart.Segment = zero
    var counts: [5]usize = zero
    var used: [5]usize = zero
    let (board, result) = chart.sipoc(entries[..], bounds, 10.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..], arrows[..], counts[..], used[..])
    if result != ok || board.max_rows != 3usize || board.bands.bars.len != 5usize || board.headers.bars.len != 5usize || board.cards.bars.len != 7usize || board.connectors.segments.len != 12usize { ret chart.Invalid }
    if counts[0usize] != 1usize || counts[1usize] != 1usize || counts[2usize] != 3usize || counts[3usize] != 1usize || counts[4usize] != 1usize || used[2usize] != 3usize { ret chart.Invalid }
    if !near(columns[0usize].width, 60.0) || !near(columns[1usize].x, 70.0) || !near(columns[4usize].x, 280.0) || !near(headers[2usize].height, 30.0) || !near(cards[0usize].x, 146.0) || !near(cards[0usize].y, 36.0) || !near(cards[3usize].y, 83.3333) || !near(cards[6usize].y, 130.6667) || !near(cards[1usize].x, 6.0) || !near(cards[0usize].width, 48.0) { ret chart.Invalid }
    if !near(arrows[0usize].from.x, 60.0) || !near(arrows[0usize].to.x, 70.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 40usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &board.bands, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &board.headers, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &board.cards, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &board.connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 29usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 340.0, 180.0, "SIPOC", "Process boundary")
    try chart_svg.append(&writer, &board.bands, ink)
    try chart_svg.append(&writer, &board.headers, ink)
    try chart_svg.append(&writer, &board.cards, ink)
    try chart_svg.append(&writer, &board.connectors, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_entry = [1]chart.SipocEntry{ chart.SipocEntry { column: 5usize } }
    let (_, empty_error) = chart.sipoc(entries[..0usize], bounds, 10.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..], arrows[..], counts[..], used[..])
    let (_, bad_entry_error) = chart.sipoc(bad_entry[..], bounds, 10.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..], arrows[..], counts[..], used[..])
    let (_, gutter_error) = chart.sipoc(entries[..], bounds, 0.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..], arrows[..], counts[..], used[..])
    let (_, width_error) = chart.sipoc(entries[..], geometry.rect(0.0, 0.0, 20.0, 180.0), 10.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..], arrows[..], counts[..], used[..])
    let (_, card_height_error) = chart.sipoc(entries[..], geometry.rect(0.0, 0.0, 340.0, 60.0), 10.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..], arrows[..], counts[..], used[..])
    let (_, columns_error) = chart.sipoc(entries[..], bounds, 10.0, 6.0, 30.0, 4.0, columns[..4usize], headers[..], cards[..], arrows[..], counts[..], used[..])
    let (_, arrows_error) = chart.sipoc(entries[..], bounds, 10.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..], arrows[..11usize], counts[..], used[..])
    if empty_error != chart.Empty || bad_entry_error != chart.Invalid || gutter_error != chart.Invalid || width_error != chart.Invalid || card_height_error != chart.TooLarge || columns_error != chart.TooLarge || arrows_error != chart.TooLarge { ret chart.Invalid }
    let one = [1]chart.SipocEntry{ chart.SipocEntry { column: 2usize } }
    let (sparse, sparse_error) = chart.sipoc(one[..], bounds, 10.0, 6.0, 30.0, 4.0, columns[..], headers[..], cards[..1usize], arrows[..], counts[..], used[..])
    if sparse_error != ok || sparse.max_rows != 1usize || counts[0usize] != 0usize || counts[2usize] != 1usize || counts[4usize] != 0usize { ret chart.Invalid }
    try io.print("gfx chart sipoc ok\n")
    ret ok
}
