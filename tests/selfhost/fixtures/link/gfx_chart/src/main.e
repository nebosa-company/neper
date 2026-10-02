use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ 0.0, 1.0, 2.0 }
    let y = [3]f32{ 0.0, 1.0, 0.0 }
    let (points, point_error) = mem.alloc[chart.Coord](a, 3usize)
    if point_error != ok { ret point_error }
    let (lines, line_error) = mem.alloc[chart.Segment](a, 2usize)
    if line_error != ok { ret line_error }
    let (bars, bar_error) = mem.alloc[geometry.Rect](a, 3usize)
    if bar_error != ok { ret bar_error }
    var line = chart.spec(.Line, geometry.rect(10.0, 20.0, 100.0, 50.0), x[..], y[..])
    let (line_layout, layout_error) = chart.layout(&line, points[..], lines[..], bars[..])
    if layout_error != ok || line_layout.segments.len != 2usize { ret chart.Invalid }
    if !near(line_layout.segments[0].from.x, 10.0) || !near(line_layout.segments[0].from.y, 70.0) || !near(line_layout.segments[0].to.x, 60.0) || !near(line_layout.segments[0].to.y, 20.0) { ret chart.Invalid }

    var scatter = chart.spec(.Scatter, geometry.rect(0.0, 0.0, 20.0, 20.0), x[..], y[..])
    let (scatter_layout, scatter_error) = chart.layout(&scatter, points[..], lines[..], bars[..])
    if scatter_error != ok || scatter_layout.coords.len != 3usize { ret chart.Invalid }
    if !near(scatter_layout.coords[1].x, 10.0) || !near(scatter_layout.coords[1].y, 0.0) { ret chart.Invalid }

    var bar = chart.spec(.Bar, geometry.rect(0.0, 0.0, 30.0, 30.0), x[..], y[..])
    let (bar_layout, bar_layout_error) = chart.layout(&bar, points[..], lines[..], bars[..])
    if bar_layout_error != ok || bar_layout.bars.len != 3usize || bar_layout.bars[1].height <= 0.0 { ret chart.Invalid }
    let (_, small_error) = chart.layout(&line, points[..], lines[..0usize], bars[..])
    if small_error != chart.TooLarge { ret chart.Invalid }

    let samples = [6]f32{ 0.0, 1.0, 1.0, 2.0, 3.0, 4.0 }
    let (counts, counts_error) = mem.alloc[u64](a, 4usize)
    if counts_error != ok { ret counts_error }
    let (hist_bars, hist_bars_error) = mem.alloc[geometry.Rect](a, 4usize)
    if hist_bars_error != ok { ret hist_bars_error }
    let (hist, hist_error) = chart.histogram(samples[..], geometry.rect(5.0, 10.0, 40.0, 20.0), counts[..], hist_bars[..])
    if hist_error != ok || hist.kind != .Histogram || hist.bars.len != 4usize || hist.y_max != 2.0 { ret chart.Invalid }
    if counts[0] != 1u64 || counts[1] != 2u64 || counts[2] != 1u64 || counts[3] != 2u64 { ret chart.Invalid }
    if !near(hist.bars[0].x, 5.0) || !near(hist.bars[0].width, 10.0) || !near(hist.bars[0].height, 10.0) || !near(hist.bars[1].y, 10.0) { ret chart.Invalid }
    let same = [2]f32{ 7.0, 7.0 }
    let (_, same_error) = chart.histogram(same[..], geometry.rect(0.0, 0.0, 40.0, 20.0), counts[..], hist_bars[..])
    if same_error != ok || counts[2] != 2u64 || counts[0] != 0u64 || counts[1] != 0u64 || counts[3] != 0u64 { ret chart.Invalid }
    let large = [1]f32{ 1.0e30f32 }
    let (large_hist, large_error) = chart.histogram(large[..], geometry.rect(0.0, 0.0, 40.0, 20.0), counts[..], hist_bars[..])
    if large_error != ok || large_hist.x_min >= large_hist.x_max || counts[2] != 1u64 { ret chart.Invalid }
    let (_, empty_error) = chart.histogram(samples[..0usize], geometry.rect(0.0, 0.0, 40.0, 20.0), counts[..], hist_bars[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    let (_, bins_error) = chart.histogram(samples[..], geometry.rect(0.0, 0.0, 40.0, 20.0), counts[..0usize], hist_bars[..0usize])
    if bins_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart ok\n")
    ret ok
}
