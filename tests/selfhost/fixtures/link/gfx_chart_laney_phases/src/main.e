use e.algo.stat
use e.io
use e.mem

fn near(a: f64, b: f64) -> bool {
    let delta = a - b
    ret delta > -0.000001f64 && delta < 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let starts = [8]bool{ true, false, false, false, true, false, false, false }
    let p_counts = [8]usize{ 2usize, 10usize, 3usize, 9usize, 6usize, 18usize, 7usize, 17usize }
    let u_counts = [8]usize{ 1usize, 12usize, 0usize, 14usize, 4usize, 20usize, 3usize, 18usize }
    let p_sizes = [8]usize{ 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize }
    let u_sizes = [8]usize{ 10usize, 10usize, 10usize, 10usize, 12usize, 12usize, 12usize, 12usize }
    let kinds = [2]stat.AttributeControlKind{ .P, .U }
    let counts = [2][]const usize{ p_counts[..], u_counts[..] }
    let sizes = [2][]const usize{ p_sizes[..], u_sizes[..] }
    var points: [8]stat.AttributeControlPoint = zero
    var reference: [8]stat.AttributeControlPoint = zero
    var sigmas: [8]f64 = zero
    var kind_index = 0usize
    while kind_index < 2usize {
        if stat.laney_control_phased(kinds[kind_index], counts[kind_index], sizes[kind_index], starts[..], points[..], sigmas[..]) != ok { ret stat.Invalid }
        let (first, first_error) = stat.laney_control(kinds[kind_index], counts[kind_index][..4usize], sizes[kind_index][..4usize], reference[..4usize])
        let (second, second_error) = stat.laney_control(kinds[kind_index], counts[kind_index][4usize..], sizes[kind_index][4usize..], reference[4usize..])
        if first_error != ok || second_error != ok || near(first, second) || near(points[0usize].center, points[4usize].center) { ret stat.Invalid }
        var i = 0usize
        while i < 8usize {
            var expected_sigma = first
            if i >= 4usize { expected_sigma = second }
            if !near(sigmas[i], expected_sigma) || !near(points[i].value, reference[i].value) || !near(points[i].center, reference[i].center) || !near(points[i].lower, reference[i].lower) || !near(points[i].upper, reference[i].upper) { ret stat.Invalid }
            i += 1usize
        }
        kind_index += 1usize
    }
    if stat.laney_control_phased(.C, p_counts[..], p_sizes[..], starts[..], points[..], sigmas[..]) != stat.Invalid { ret stat.Invalid }
    if stat.laney_control_phased(.P, p_counts[..], p_sizes[..], starts[..], points[..], sigmas[..7usize]) != stat.TooSmall { ret stat.Invalid }
    let singleton = [8]bool{ true, true, false, false, true, false, false, false }
    if stat.laney_control_phased(.P, p_counts[..], p_sizes[..], singleton[..], points[..], sigmas[..]) != stat.Invalid { ret stat.Invalid }
    let no_first = [8]bool{ false, false, false, false, true, false, false, false }
    if stat.laney_control_phased(.P, p_counts[..], p_sizes[..], no_first[..], points[..], sigmas[..]) != stat.Invalid { ret stat.Invalid }
    let all_zero = [8]usize{ 0usize, 0usize, 0usize, 0usize, 6usize, 18usize, 7usize, 17usize }
    if stat.laney_control_phased(.P, all_zero[..], p_sizes[..], starts[..], points[..], sigmas[..]) != stat.Invalid { ret stat.Invalid }
    try io.print("gfx chart laney phases ok\n")
    ret ok
}
