use e.algo.stat
use e.io
use e.mem

fn near(a: f64, b: f64) -> bool {
    let delta = a - b
    ret delta > -0.000001f64 && delta < 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let counts = [10]usize{ 2usize, 3usize, 1usize, 4usize, 2usize, 8usize, 9usize, 7usize, 10usize, 8usize }
    let starts = [10]bool{ true, false, false, false, false, true, false, false, false, false }
    let p_sizes = [10]usize{ 50usize, 100usize, 50usize, 100usize, 50usize, 100usize, 100usize, 100usize, 100usize, 100usize }
    let np_sizes = [10]usize{ 100usize, 100usize, 100usize, 100usize, 100usize, 200usize, 200usize, 200usize, 200usize, 200usize }
    let c_sizes = [10]usize{ 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize }
    let u_sizes = [10]usize{ 5usize, 10usize, 5usize, 10usize, 5usize, 10usize, 20usize, 10usize, 20usize, 10usize }
    let kinds = [4]stat.AttributeControlKind{ .P, .Np, .C, .U }
    let sizes = [4][]const usize{ p_sizes[..], np_sizes[..], c_sizes[..], u_sizes[..] }
    let first_centers = [4]f64{ 12.0 / 350.0, 2.4, 2.4, 12.0 / 35.0 }
    let second_centers = [4]f64{ 42.0 / 500.0, 8.4, 8.4, 42.0 / 70.0 }
    var phased: [10]stat.AttributeControlPoint = zero
    var reference: [10]stat.AttributeControlPoint = zero
    var kind_index = 0usize
    while kind_index < 4usize {
        if stat.attribute_control_phased(kinds[kind_index], counts[..], sizes[kind_index], starts[..], phased[..]) != ok { ret stat.Invalid }
        if !near(phased[0usize].center, first_centers[kind_index]) || !near(phased[5usize].center, second_centers[kind_index]) { ret stat.Invalid }
        if stat.attribute_control(kinds[kind_index], counts[..5usize], sizes[kind_index][..5usize], reference[..5usize]) != ok { ret stat.Invalid }
        if stat.attribute_control(kinds[kind_index], counts[5usize..], sizes[kind_index][5usize..], reference[5usize..]) != ok { ret stat.Invalid }
        var i = 0usize
        while i < 10usize {
            if !near(phased[i].value, reference[i].value) || !near(phased[i].center, reference[i].center) || !near(phased[i].lower, reference[i].lower) || !near(phased[i].upper, reference[i].upper) { ret stat.Invalid }
            i += 1usize
        }
        kind_index += 1usize
    }
    let short_phase = [10]bool{ true, true, false, false, false, false, false, false, false, false }
    if stat.attribute_control_phased(.P, counts[..], p_sizes[..], short_phase[..], phased[..]) != stat.Invalid { ret stat.Invalid }
    let last_singleton = [10]bool{ true, false, false, false, false, false, false, false, false, true }
    if stat.attribute_control_phased(.P, counts[..], p_sizes[..], last_singleton[..], phased[..]) != stat.Invalid { ret stat.Invalid }
    let no_start = [10]bool{ false, false, false, false, false, true, false, false, false, false }
    if stat.attribute_control_phased(.P, counts[..], p_sizes[..], no_start[..], phased[..]) != stat.Invalid { ret stat.Invalid }
    if stat.attribute_control_phased(.P, counts[..], p_sizes[..], starts[..9usize], phased[..]) != stat.Invalid { ret stat.Invalid }
    if stat.attribute_control_phased(.P, counts[..], p_sizes[..], starts[..], phased[..9usize]) != stat.TooSmall { ret stat.Invalid }
    let bad_np = [10]usize{ 100usize, 90usize, 100usize, 100usize, 100usize, 200usize, 200usize, 200usize, 200usize, 200usize }
    if stat.attribute_control_phased(.Np, counts[..], bad_np[..], starts[..], phased[..]) != stat.Invalid { ret stat.Invalid }
    let zero_sizes = [10]usize{ 50usize, 100usize, 50usize, 100usize, 50usize, 100usize, 0usize, 100usize, 100usize, 100usize }
    if stat.attribute_control_phased(.P, counts[..], zero_sizes[..], starts[..], phased[..]) != stat.Invalid { ret stat.Invalid }
    try io.print("gfx chart attribute phases ok\n")
    ret ok
}
