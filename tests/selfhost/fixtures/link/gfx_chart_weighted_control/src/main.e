use e.algo.stat
use e.io
use e.mem

fn near(actual: f64, expected: f64) -> bool {
    ret actual > expected - 0.00001f64 && actual < expected + 0.00001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let groups = [15]f64{ 10.0, 11.0, 9.0, 10.0, 10.0, 11.0, 13.0, 10.0, 11.0, 10.0, 9.0, 10.0, 8.0, 9.0, 9.0 }
    var means: [3]f64 = zero
    var deviations: [3]f64 = zero
    let (xbar, s, group_error) = stat.xbar_s_limits(groups[..], 5usize, means[..], deviations[..])
    if group_error != ok || !near(means[1usize], 11.0) || !near(deviations[1usize], 1.224744871) || !near(xbar.center, 10.0) || !near(xbar.lower, 8.744472164) || !near(xbar.upper, 11.255527836) || !near(s.center, 0.879652811) || !near(s.lower, 0.0) || !near(s.upper, 1.837592848) { ret stat.Invalid }
    let (unused_x, unused_s, short_error) = stat.xbar_s_limits(groups[..], 5usize, means[..2usize], deviations[..])
    if short_error != stat.TooSmall { ret stat.Invalid }
    let (unused_x2, unused_s2, invalid_group) = stat.xbar_s_limits(groups[..], 1usize, means[..], deviations[..])
    if invalid_group != stat.Invalid { ret stat.Invalid }

    let values = [5]f64{ 10.0, 11.0, 13.0, 8.0, 7.0 }
    var sums: [5]stat.CusumPoint = zero
    if stat.cusum_control(values[..], 10.0, 0.5, 2.0, sums[..]) != ok || !near(sums[2usize].high, 3.0) || !sums[2usize].high_signal || !near(sums[4usize].low, 4.0) || !sums[4usize].low_signal || sums[1usize].high_signal { ret stat.Invalid }
    if stat.cusum_control(values[..], 10.0, 0.5, 2.0, sums[..4usize]) != stat.TooSmall { ret stat.Invalid }
    if stat.cusum_control(values[..], 10.0, -0.5, 2.0, sums[..]) != stat.Invalid { ret stat.Invalid }

    let ewma_values = [3]f64{ 11.0, 9.0, 12.0 }
    var points: [3]stat.AttributeControlPoint = zero
    if stat.ewma_control(ewma_values[..], 10.0, 2.0, 0.5, 3.0, points[..]) != ok || !near(points[0usize].value, 10.5) || !near(points[0usize].upper, 13.0) || !near(points[1usize].value, 9.75) || !near(points[1usize].upper, 13.354101966) || !near(points[2usize].value, 10.875) || !near(points[2usize].upper, 13.436931771) { ret stat.Invalid }
    if stat.ewma_control(ewma_values[..], 10.0, 2.0, 0.5, 3.0, points[..2usize]) != stat.TooSmall { ret stat.Invalid }
    if stat.ewma_control(ewma_values[..], 10.0, 2.0, 0.0, 3.0, points[..]) != stat.Invalid { ret stat.Invalid }
    try io.print("gfx chart weighted control ok\n")
    ret ok
}
