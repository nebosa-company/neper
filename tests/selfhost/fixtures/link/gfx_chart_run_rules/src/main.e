use e.algo.stat
use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    var centers: [16]f64 = zero
    var sigmas: [16]f64 = zero
    var signals: [16]stat.ControlSignal = zero
    var i = 0usize
    while i < 16usize {
        sigmas[i] = 1.0
        i += 1usize
    }

    let boundary = [3]f64{ 3.0, 2.0, 1.0 }
    if stat.control_run_rules(boundary[..], centers[..3usize], sigmas[..3usize], signals[..3usize]) != ok || signals[0usize].beyond3 || signals[2usize].two_of_three2 { ret stat.Invalid }
    let beyond = [2]f64{ 0.0, 3.1 }
    if stat.control_run_rules(beyond[..], centers[..2usize], sigmas[..2usize], signals[..2usize]) != ok || !signals[1usize].beyond3 { ret stat.Invalid }
    let same = [9]f64{ 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 }
    if stat.control_run_rules(same[..], centers[..9usize], sigmas[..9usize], signals[..9usize]) != ok || signals[7usize].same_side9 || !signals[8usize].same_side9 || signals[8usize].trend6 { ret stat.Invalid }
    let trend = [6]f64{ -0.5, -0.3, -0.1, 0.1, 0.3, 0.5 }
    if stat.control_run_rules(trend[..], centers[..6usize], sigmas[..6usize], signals[..6usize]) != ok || !signals[5usize].trend6 { ret stat.Invalid }
    var alternate: [14]f64 = zero
    i = 0usize
    while i < 14usize {
        if i % 2usize == 0usize { alternate[i] = 0.5 } else { alternate[i] = -0.5 }
        i += 1usize
    }
    if stat.control_run_rules(alternate[..], centers[..14usize], sigmas[..14usize], signals[..14usize]) != ok || signals[12usize].alternating14 || !signals[13usize].alternating14 { ret stat.Invalid }
    let two = [3]f64{ 2.1, 0.0, 2.2 }
    if stat.control_run_rules(two[..], centers[..3usize], sigmas[..3usize], signals[..3usize]) != ok || !signals[2usize].two_of_three2 { ret stat.Invalid }
    let four = [5]f64{ 1.1, 1.2, 0.0, 1.3, 1.4 }
    if stat.control_run_rules(four[..], centers[..5usize], sigmas[..5usize], signals[..5usize]) != ok || !signals[4usize].four_of_five1 { ret stat.Invalid }
    var within: [15]f64 = zero
    i = 0usize
    while i < 15usize {
        if i % 2usize == 0usize { within[i] = 0.2 } else { within[i] = -0.2 }
        i += 1usize
    }
    if stat.control_run_rules(within[..], centers[..15usize], sigmas[..15usize], signals[..15usize]) != ok || !signals[14usize].within1_15 { ret stat.Invalid }
    let outside = [8]f64{ 1.5, -1.5, 1.5, -1.5, 1.5, -1.5, 1.5, -1.5 }
    if stat.control_run_rules(outside[..], centers[..8usize], sigmas[..8usize], signals[..8usize]) != ok || !signals[7usize].outside1_8 { ret stat.Invalid }
    let varying = [2]f64{ 1.0, 2.0 }
    let varying_sigma = [2]f64{ 1.0, 0.5 }
    if stat.control_run_rules(varying[..], centers[..2usize], varying_sigma[..], signals[..2usize]) != ok || !signals[1usize].beyond3 { ret stat.Invalid }
    if stat.control_run_rules(varying[..], centers[..2usize], varying_sigma[..], signals[..1usize]) != stat.TooSmall { ret stat.Invalid }
    let bad_sigma = [2]f64{ 1.0, 0.0 }
    if stat.control_run_rules(varying[..], centers[..2usize], bad_sigma[..], signals[..2usize]) != stat.Invalid { ret stat.Invalid }
    try io.print("gfx chart run rules ok\n")
    ret ok
}
