use e.algo.stat
use e.io
use e.mem

fn near(a: f64, b: f64) -> bool {
    let delta = a - b
    ret delta > -0.000001f64 && delta < 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [24]f64{
        9.0, 10.0, 11.0, 10.0, 12.0, 11.0, 8.0, 9.0, 10.0, 10.0, 10.0, 13.0,
        19.0, 20.0, 21.0, 20.0, 22.0, 23.0, 18.0, 19.0, 20.0, 21.0, 22.0, 24.0,
    }
    let starts = [8]bool{ true, false, false, false, true, false, false, false }
    let kinds = [2]stat.SubgroupSpreadKind{ .Range, .StdDev }
    var means: [8]f64 = zero
    var spreads: [8]f64 = zero
    var mean_points: [8]stat.AttributeControlPoint = zero
    var spread_points: [8]stat.AttributeControlPoint = zero
    var reference_means: [8]f64 = zero
    var reference_spreads: [8]f64 = zero
    var kind_index = 0usize
    while kind_index < 2usize {
        if stat.subgroup_control_phased(kinds[kind_index], values[..], 3usize, starts[..], means[..], spreads[..], mean_points[..], spread_points[..]) != ok { ret stat.Invalid }
        var first_mean: stat.ControlLimits = zero
        var first_spread: stat.ControlLimits = zero
        var second_mean: stat.ControlLimits = zero
        var second_spread: stat.ControlLimits = zero
        var first_error: err = ok
        var second_error: err = ok
        if kinds[kind_index] == .Range {
            let (m1, s1, e1) = stat.xbar_r_limits(values[..12usize], 3usize, reference_means[..4usize], reference_spreads[..4usize])
            let (m2, s2, e2) = stat.xbar_r_limits(values[12usize..], 3usize, reference_means[4usize..], reference_spreads[4usize..])
            first_mean = m1
            first_spread = s1
            second_mean = m2
            second_spread = s2
            first_error = e1
            second_error = e2
        } else {
            let (m1, s1, e1) = stat.xbar_s_limits(values[..12usize], 3usize, reference_means[..4usize], reference_spreads[..4usize])
            let (m2, s2, e2) = stat.xbar_s_limits(values[12usize..], 3usize, reference_means[4usize..], reference_spreads[4usize..])
            first_mean = m1
            first_spread = s1
            second_mean = m2
            second_spread = s2
            first_error = e1
            second_error = e2
        }
        if first_error != ok || second_error != ok || !near(first_mean.center, 10.25) || !near(second_mean.center, 20.75) { ret stat.Invalid }
        var i = 0usize
        while i < 8usize {
            var expected_mean = first_mean
            var expected_spread = first_spread
            if i >= 4usize {
                expected_mean = second_mean
                expected_spread = second_spread
            }
            if !near(means[i], reference_means[i]) || !near(spreads[i], reference_spreads[i]) || !near(mean_points[i].value, means[i]) || !near(spread_points[i].value, spreads[i]) || !near(mean_points[i].center, expected_mean.center) || !near(mean_points[i].lower, expected_mean.lower) || !near(mean_points[i].upper, expected_mean.upper) || !near(spread_points[i].center, expected_spread.center) || !near(spread_points[i].lower, expected_spread.lower) || !near(spread_points[i].upper, expected_spread.upper) { ret stat.Invalid }
            i += 1usize
        }
        kind_index += 1usize
    }
    let singleton = [8]bool{ true, true, false, false, true, false, false, false }
    if stat.subgroup_control_phased(.Range, values[..], 3usize, singleton[..], means[..], spreads[..], mean_points[..], spread_points[..]) != stat.Invalid { ret stat.Invalid }
    let last_singleton = [8]bool{ true, false, false, false, false, false, false, true }
    if stat.subgroup_control_phased(.StdDev, values[..], 3usize, last_singleton[..], means[..], spreads[..], mean_points[..], spread_points[..]) != stat.Invalid { ret stat.Invalid }
    let no_first = [8]bool{ false, false, false, false, true, false, false, false }
    if stat.subgroup_control_phased(.Range, values[..], 3usize, no_first[..], means[..], spreads[..], mean_points[..], spread_points[..]) != stat.Invalid { ret stat.Invalid }
    if stat.subgroup_control_phased(.Range, values[..], 3usize, starts[..7usize], means[..], spreads[..], mean_points[..], spread_points[..]) != stat.Invalid { ret stat.Invalid }
    if stat.subgroup_control_phased(.Range, values[..], 3usize, starts[..], means[..7usize], spreads[..], mean_points[..], spread_points[..]) != stat.TooSmall { ret stat.Invalid }
    if stat.subgroup_control_phased(.StdDev, values[..], 3usize, starts[..], means[..], spreads[..], mean_points[..7usize], spread_points[..]) != stat.TooSmall { ret stat.Invalid }
    if stat.subgroup_control_phased(.Range, values[..], 12usize, starts[..2usize], means[..], spreads[..], mean_points[..], spread_points[..]) != stat.Invalid { ret stat.Invalid }
    var malformed = values
    malformed[6usize] = 0.0 / 0.0
    if stat.subgroup_control_phased(.Range, malformed[..], 3usize, starts[..], means[..], spreads[..], mean_points[..], spread_points[..]) != stat.Invalid { ret stat.Invalid }
    try io.print("gfx chart subgroup phases ok\n")
    ret ok
}
