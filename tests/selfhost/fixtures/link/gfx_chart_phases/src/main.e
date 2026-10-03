use e.algo.stat
use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [10]f64{ 10.0, 11.0, 9.0, 10.0, 10.0, 20.0, 21.0, 19.0, 20.0, 20.0 }
    let starts = [10]bool{ true, false, false, false, false, true, false, false, false, false }
    var moving: [9]f64 = zero
    var points: [10]stat.AttributeControlPoint = zero
    if stat.imr_phase_control(values[..], starts[..], moving[..], points[..]) != ok { ret stat.Invalid }
    if moving[4usize] != 0.0 || moving[0usize] != 1.0 || moving[1usize] != 2.0 || moving[5usize] != 1.0 { ret stat.Invalid }
    if points[0usize].center != 10.0 || points[4usize].center != 10.0 || points[5usize].center != 20.0 || points[9usize].center != 20.0 { ret stat.Invalid }
    if points[0usize].upper < 12.65 || points[0usize].upper > 12.67 || points[5usize].lower < 17.33 || points[5usize].lower > 17.35 { ret stat.Invalid }
    if stat.imr_phase_control(values[..], starts[..9usize], moving[..], points[..]) != stat.Invalid { ret stat.Invalid }
    if stat.imr_phase_control(values[..], starts[..], moving[..8usize], points[..]) != stat.TooSmall { ret stat.Invalid }
    let short_phase = [10]bool{ true, true, false, false, false, false, false, false, false, false }
    if stat.imr_phase_control(values[..], short_phase[..], moving[..], points[..]) != stat.Invalid { ret stat.Invalid }

    var centers: [16]f64 = zero
    var sigmas: [16]f64 = zero
    var signals: [16]stat.ControlSignal = zero
    var i = 0usize
    while i < 16usize {
        sigmas[i] = 1.0
        i += 1usize
    }
    let same = [9]f64{ 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 }
    if stat.control_run_rules(same[..], centers[..9usize], sigmas[..9usize], signals[..9usize]) != ok || !signals[8usize].same_side9 { ret stat.Invalid }
    if stat.control_run_rules_phased(same[..], centers[..9usize], sigmas[..9usize], starts[..9usize], signals[..9usize]) != ok || signals[8usize].same_side9 { ret stat.Invalid }
    let trend = [6]f64{ -0.5, -0.3, -0.1, 0.1, 0.3, 0.5 }
    let split = [6]bool{ true, false, false, true, false, false }
    if stat.control_run_rules_phased(trend[..], centers[..6usize], sigmas[..6usize], split[..], signals[..6usize]) != ok || signals[5usize].trend6 { ret stat.Invalid }
    let two = [3]f64{ 2.1, 0.0, 2.2 }
    let two_split = [3]bool{ true, false, true }
    if stat.control_run_rules_phased(two[..], centers[..3usize], sigmas[..3usize], two_split[..], signals[..3usize]) != ok || signals[2usize].two_of_three2 { ret stat.Invalid }
    let no_start = [3]bool{ false, false, false }
    if stat.control_run_rules_phased(two[..], centers[..3usize], sigmas[..3usize], no_start[..], signals[..3usize]) != stat.Invalid { ret stat.Invalid }
    let four = [5]f64{ 1.1, 1.2, 0.0, 1.3, 1.4 }
    let four_split = [5]bool{ true, false, false, true, false }
    if stat.control_run_rules_phased(four[..], centers[..5usize], sigmas[..5usize], four_split[..], signals[..5usize]) != ok || signals[4usize].four_of_five1 { ret stat.Invalid }
    var alternate: [14]f64 = zero
    var alternate_starts: [14]bool = zero
    alternate_starts[0usize] = true
    alternate_starts[7usize] = true
    i = 0usize
    while i < 14usize {
        if i % 2usize == 0usize { alternate[i] = 0.5 } else { alternate[i] = -0.5 }
        i += 1usize
    }
    if stat.control_run_rules_phased(alternate[..], centers[..14usize], sigmas[..14usize], alternate_starts[..], signals[..14usize]) != ok || signals[13usize].alternating14 { ret stat.Invalid }
    var within: [15]f64 = zero
    var within_starts: [15]bool = zero
    within_starts[0usize] = true
    within_starts[8usize] = true
    if stat.control_run_rules_phased(within[..], centers[..15usize], sigmas[..15usize], within_starts[..], signals[..15usize]) != ok || signals[14usize].within1_15 { ret stat.Invalid }
    let outside = [8]f64{ 1.5, -1.5, 1.5, -1.5, 1.5, -1.5, 1.5, -1.5 }
    let outside_starts = [8]bool{ true, false, false, false, true, false, false, false }
    if stat.control_run_rules_phased(outside[..], centers[..8usize], sigmas[..8usize], outside_starts[..], signals[..8usize]) != ok || signals[7usize].outside1_8 { ret stat.Invalid }
    let beyond = [2]f64{ 0.0, 3.1 }
    let both_starts = [2]bool{ true, true }
    if stat.control_run_rules_phased(beyond[..], centers[..2usize], sigmas[..2usize], both_starts[..], signals[..2usize]) != ok || !signals[1usize].beyond3 { ret stat.Invalid }
    try io.print("gfx chart phases ok\n")
    ret ok
}
