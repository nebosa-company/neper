use e.algo.stat
use e.io
use e.mem

fn near(actual: f64, expected: f64) -> bool {
    ret actual > expected - 0.00001f64 && actual < expected + 0.00001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let gaps = [4]usize{ 1usize, 1usize, 1usize, 1usize }
    let (g, g_error) = stat.g_control_limits(gaps[..])
    if g_error != ok || !near(g.center, 0.0) || !near(g.lower, 0.0) || !near(g.upper, 8.6176) { ret stat.Invalid }
    let (unused_quantile, invalid_probability) = stat.geometric_gap_percentile(0.0, 0.5)
    if invalid_probability { ret stat.Invalid }
    let (unused_fraction, invalid_fraction) = stat.geometric_gap_percentile(0.5, 1.0)
    if invalid_fraction { ret stat.Invalid }
    let zero_gaps = [2]usize{ 0usize, 0usize }
    let (zero_g, zero_error) = stat.g_control_limits(zero_gaps[..])
    if zero_error != ok || !near(zero_g.upper, 0.0) { ret stat.Invalid }
    let long_gaps = [2]usize{ 1000000000000000000usize, 1000000000000000000usize }
    let (long_g, long_error) = stat.g_control_limits(long_gaps[..])
    if long_error != ok || !(long_g.upper > long_g.center) { ret stat.Invalid }
    let (unused_g, short_g) = stat.g_control_limits(gaps[..1usize])
    if short_g != stat.Invalid { ret stat.Invalid }

    let intervals = [3]f64{ 1.0, 2.0, 3.0 }
    let (t, t_error) = stat.t_exponential_control_limits(intervals[..])
    if t_error != ok || !near(t.center, 1.386294361) || !near(t.lower, 0.002701824) || !near(t.upper, 13.215301373) { ret stat.Invalid }
    let zero_intervals = [2]f64{ 1.0, 0.0 }
    let (unused_t, zero_t) = stat.t_exponential_control_limits(zero_intervals[..])
    if zero_t != stat.Invalid { ret stat.Invalid }
    let (unused_short_t, short_t) = stat.t_exponential_control_limits(intervals[..1usize])
    if short_t != stat.Invalid { ret stat.Invalid }
    try io.print("gfx chart rare event ok\n")
    ret ok
}
