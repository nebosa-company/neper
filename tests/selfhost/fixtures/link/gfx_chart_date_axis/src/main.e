use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str
use e.time

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001f32 && b - a < 0.001f32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let dates = [4]time.Date{
        time.Date { year: 2024i32, month: 1u8, day: 1u8 },
        time.Date { year: 2024i32, month: 2u8, day: 1u8 },
        time.Date { year: 2024i32, month: 3u8, day: 1u8 },
        time.Date { year: 2024i32, month: 4u8, day: 1u8 },
    }
    let values = [4]f64{ 10.0f64, 20.0f64, 15.0f64, 30.0f64 }
    let bounds = geometry.rect(40.0, 50.0, 270.0, 120.0)
    var points: [4]chart.Coord = zero
    var segments: [3]chart.Segment = zero
    let (line, line_error) = chart.date_axis_line(dates[..], values[..], dates[0usize], dates[3usize], 0.0f64, 40.0f64, bounds, points[..], segments[..])
    if line_error != ok || line.coords.len != 4usize || line.segments.len != 3usize {
        try io.print("line fail\n")
        ret chart.Invalid
    }
    if !near(points[0usize].x, 40.0) || !near(points[1usize].x, 40.0 + 270.0 * 31.0 / 91.0) || !near(points[2usize].x, 40.0 + 270.0 * 60.0 / 91.0) || !near(points[3usize].x, 310.0) || !near(points[2usize].y, 125.0) {
        try io.print("point fail\n")
        ret chart.Invalid
    }
    var ticks: [4]chart.DateTick = zero
    let (month_ticks, ticks_error) = chart.date_ticks(dates[0usize], dates[3usize], 1usize, ticks[..])
    if ticks_error != ok || month_ticks.len != 4usize || !near(month_ticks[2usize].fraction, 60.0 / 91.0) || month_ticks[2usize].date.month != 3u8 {
        try io.print("tick fail\n")
        ret chart.Invalid
    }
    var labels: [4]str = zero
    var storage: [28]u8 = zero
    let (month_labels, label_error) = chart.format_date_ticks(month_ticks, labels[..], storage[..])
    if label_error != ok || !str.eq(month_labels[0usize], "2024-01") || !str.eq(month_labels[1usize], "2024-02") || !str.eq(month_labels[3usize], "2024-04") {
        try io.print("label fail\n")
        ret chart.Invalid
    }
    let ancient_start = time.Date { year: 1i32, month: 1u8, day: 1u8 }
    let ancient_end = time.Date { year: 1i32, month: 1u8, day: 2u8 }
    var ancient_tick: [1]chart.DateTick = zero
    let (ancient, ancient_error) = chart.date_ticks(ancient_start, ancient_end, 1usize, ancient_tick[..])
    let (ancient_label, ancient_label_error) = chart.format_date_ticks(ancient, labels[..1usize], storage[..7usize])
    if ancient_error != ok || ancient_label_error != ok || ancient_label.len != 1usize || !str.eq(ancient_label[0usize], "0001-01") { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &line, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Date axis", "Leap-year month spacing")
    try chart_svg.append(&writer, &line, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "<rect") {
        try io.print("svg fail\n")
        ret chart.Invalid
    }
    let (_, short_error) = chart.date_axis_line(dates[..], values[..], dates[0usize], dates[3usize], 0.0f64, 40.0f64, bounds, points[..], segments[..2usize])
    let (_, tick_short_error) = chart.date_ticks(dates[0usize], dates[3usize], 1usize, ticks[..3usize])
    let (_, label_short_error) = chart.format_date_ticks(month_ticks, labels[..], storage[..27usize])
    let invalid = time.Date { year: 2023i32, month: 2u8, day: 29u8 }
    let (_, invalid_error) = chart.date_axis_line(dates[..], values[..], invalid, dates[3usize], 0.0f64, 40.0f64, bounds, points[..], segments[..])
    let (_, order_error) = chart.date_axis_line(dates[..], values[..], dates[3usize], dates[0usize], 0.0f64, 40.0f64, bounds, points[..], segments[..])
    if short_error != chart.TooLarge || tick_short_error != chart.TooLarge || label_short_error != chart.TooLarge || invalid_error != chart.Invalid || order_error != chart.Invalid {
        try io.print("refusal fail\n")
        ret chart.Invalid
    }
    try io.print("gfx chart date axis ok\n")
    ret ok
}
