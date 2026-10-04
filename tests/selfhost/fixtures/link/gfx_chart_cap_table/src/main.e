use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool { ret a - b < 0.00001f64 && b - a < 0.00001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let shares = [3]u64{ 6000000u64, 2000000u64, 2000000u64 }
    var before_bars: [3]geometry.Rect = zero
    var after_bars: [5]geometry.Rect = zero
    var before_layers: [3]chart.Layout = zero
    var after_layers: [5]chart.Layout = zero
    var before_fractions: [3]f64 = zero
    var after_fractions: [3]f64 = zero
    var bridge_bars: [4]geometry.Rect = zero
    var bridge_links: [3]chart.Segment = zero
    var work = chart.CapTableWork {
        before_bars: before_bars[..], after_bars: after_bars[..], before_layers: before_layers[..], after_layers: after_layers[..],
        before_fractions: before_fractions[..], after_fractions: after_fractions[..], bridge_bars: bridge_bars[..], bridge_links: bridge_links[..],
    }
    let before_bounds = geometry.rect(20.0, 44.0, 320.0, 24.0)
    let after_bounds = geometry.rect(20.0, 84.0, 320.0, 24.0)
    let bridge_bounds = geometry.rect(24.0, 134.0, 312.0, 68.0)
    let (cap, cap_error) = chart.cap_table_waterfall(shares[..], 2000000u64, 3000000u64, before_bounds, after_bounds, bridge_bounds, &work)
    if cap_error != ok || cap.before.len != 3usize || cap.after.len != 5usize || cap.bridge.bars.len != 4usize || cap.bridge.segments.len != 3usize || !cap.pool_present || !cap.investor_present { ret chart.Invalid }
    if cap.summary.before_shares != 10000000u64 || cap.summary.after_shares != 15000000u64 || !near(cap.summary.incumbent_fraction, 2.0f64 / 3.0f64) || !near(cap.summary.pool_fraction, 2.0f64 / 15.0f64) || !near(cap.summary.investor_fraction, 0.2f64) || !near(before_fractions[0usize], 0.6f64) || !near(after_fractions[0usize], 0.4f64) { ret chart.Invalid }
    if !near(f64(before_bars[0usize].width), 192.0f64) || !near(f64(after_bars[0usize].width), 128.0f64) || !near(f64(after_bars[4usize].x + after_bars[4usize].width), 340.0f64) || bridge_bars[1usize].height <= 0.0f32 || bridge_bars[2usize].height <= 0.0f32 { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &cap.before[0usize], paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &cap.after[0usize], paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &cap.bridge, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Cap table waterfall", "Before and after issuance")
    try chart_svg.append(&writer, &cap.before[0usize], ink)
    try chart_svg.append(&writer, &cap.after[0usize], ink)
    try chart_svg.append(&writer, &cap.bridge, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "<line") { ret chart.Invalid }
    let (_, empty_error) = chart.cap_table_waterfall(shares[..0usize], 2000000u64, 3000000u64, before_bounds, after_bounds, bridge_bounds, &work)
    let (_, issuance_error) = chart.cap_table_waterfall(shares[..], 0u64, 0u64, before_bounds, after_bounds, bridge_bounds, &work)
    let invalid_shares = [2]u64{ 100u64, 0u64 }
    let (_, shares_error) = chart.cap_table_waterfall(invalid_shares[..], 1u64, 1u64, before_bounds, after_bounds, bridge_bounds, &work)
    let overflow_shares = [2]u64{ 18446744073709551615u64, 1u64 }
    let (_, overflow_error) = chart.cap_table_waterfall(overflow_shares[..], 1u64, 1u64, before_bounds, after_bounds, bridge_bounds, &work)
    let (_, pool_overflow) = chart.cap_table_waterfall(shares[..], 18446744073709551615u64, 0u64, before_bounds, after_bounds, bridge_bounds, &work)
    let (_, investor_overflow) = chart.cap_table_waterfall(shares[..], 1u64, 18446744073709551615u64, before_bounds, after_bounds, bridge_bounds, &work)
    let (_, bounds_error) = chart.cap_table_waterfall(shares[..], 1u64, 1u64, geometry.rect(0.0, 0.0, -1.0, 20.0), after_bounds, bridge_bounds, &work)
    var short = work
    short.after_bars = after_bars[..4usize]
    let (_, short_error) = chart.cap_table_waterfall(shares[..], 2000000u64, 3000000u64, before_bounds, after_bounds, bridge_bounds, &short)
    let (no_pool, no_pool_error) = chart.cap_table_waterfall(shares[..], 0u64, 3000000u64, before_bounds, after_bounds, bridge_bounds, &work)
    let (no_investor, no_investor_error) = chart.cap_table_waterfall(shares[..], 2000000u64, 0u64, before_bounds, after_bounds, bridge_bounds, &work)
    if empty_error != chart.Empty || issuance_error != chart.Invalid || shares_error != chart.Invalid || overflow_error != chart.Invalid || pool_overflow != chart.Invalid || investor_overflow != chart.Invalid || bounds_error != chart.Invalid || short_error != chart.TooLarge || no_pool_error != ok || no_pool.pool_present || no_pool.after.len != 4usize || no_investor_error != ok || no_investor.investor_present || no_investor.after.len != 4usize { ret chart.Invalid }
    try io.print("gfx chart cap table ok\n")
    ret ok
}
