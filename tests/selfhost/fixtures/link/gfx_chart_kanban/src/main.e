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
    ret d > -0.001 && d < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 300.0, 180.0)
    let limits = [3]usize{ 2usize, 1usize, 0usize }
    let cards = [6]chart.KanbanCard{
        chart.KanbanCard { column: 1usize, height: 36.0 },
        chart.KanbanCard { column: 0usize, height: 28.0 },
        chart.KanbanCard { column: 1usize, height: 40.0 },
        chart.KanbanCard { column: 2usize, height: 30.0 },
        chart.KanbanCard { column: 0usize, height: 32.0 },
        chart.KanbanCard { column: 2usize, height: 35.0 },
    }
    var columns: [3]geometry.Rect = zero
    var card_boxes: [6]geometry.Rect = zero
    var status: [3]chart.KanbanStatus = zero
    var next_y: [3]f32 = zero
    let (board, items, result) = chart.kanban(cards[..], limits[..], bounds, 12.0, 8.0, 26.0, 6.0, columns[..], card_boxes[..], status[..], next_y[..])
    if result != ok || board.kind != .Bar || items.kind != .Bar || board.bars.len != 3usize || items.bars.len != 6usize { ret chart.Invalid }
    if !near(columns[0usize].width, 92.0) || !near(columns[1usize].x, 104.0) || !near(columns[2usize].x, 208.0) || !near(card_boxes[0usize].x, 112.0) || !near(card_boxes[0usize].y, 34.0) || !near(card_boxes[0usize].width, 76.0) || !near(card_boxes[2usize].y, 76.0) || !near(card_boxes[4usize].y, 68.0) { ret chart.Invalid }
    if status[0usize].count != 2usize || status[0usize].exceeded || status[1usize].count != 2usize || !status[1usize].exceeded || status[2usize].count != 2usize || status[2usize].exceeded || status[2usize].limit != 0usize { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &board, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &items, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 9usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 300.0, 180.0, "Kanban", "Workflow and WIP")
    try chart_svg.append(&writer, &board, ink)
    try chart_svg.append(&writer, &items, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let outside = [1]chart.KanbanCard{ chart.KanbanCard { column: 3usize, height: 20.0 } }
    let negative = [1]chart.KanbanCard{ chart.KanbanCard { column: 0usize, height: -2.0 } }
    let tall = [1]chart.KanbanCard{ chart.KanbanCard { column: 0usize, height: 200.0 } }
    let (_, _, empty_error) = chart.kanban(cards[..0usize], limits[..0usize], bounds, 12.0, 8.0, 26.0, 6.0, columns[..], card_boxes[..], status[..], next_y[..])
    let (_, _, outside_error) = chart.kanban(outside[..], limits[..], bounds, 12.0, 8.0, 26.0, 6.0, columns[..], card_boxes[..], status[..], next_y[..])
    let (_, _, negative_error) = chart.kanban(negative[..], limits[..], bounds, 12.0, 8.0, 26.0, 6.0, columns[..], card_boxes[..], status[..], next_y[..])
    let (_, _, tall_error) = chart.kanban(tall[..], limits[..], bounds, 12.0, 8.0, 26.0, 6.0, columns[..], card_boxes[..], status[..], next_y[..])
    let (_, _, geometry_error) = chart.kanban(cards[..], limits[..], bounds, 12.0, 48.0, 26.0, 6.0, columns[..], card_boxes[..], status[..], next_y[..])
    let (_, _, storage_error) = chart.kanban(cards[..], limits[..], bounds, 12.0, 8.0, 26.0, 6.0, columns[..], card_boxes[..5usize], status[..], next_y[..])
    if empty_error != chart.Empty || outside_error != chart.Invalid || negative_error != chart.Invalid || tall_error != chart.TooLarge || geometry_error != chart.Invalid || storage_error != chart.TooLarge { ret chart.Invalid }
    let (empty_board, empty_items, no_card_error) = chart.kanban(cards[..0usize], limits[..], bounds, 12.0, 8.0, 26.0, 6.0, columns[..], card_boxes[..0usize], status[..], next_y[..])
    if no_card_error != ok || empty_board.bars.len != 3usize || empty_items.bars.len != 0usize || status[1usize].count != 0usize || status[1usize].exceeded { ret chart.Invalid }
    try io.print("gfx chart kanban ok\n")
    ret ok
}
