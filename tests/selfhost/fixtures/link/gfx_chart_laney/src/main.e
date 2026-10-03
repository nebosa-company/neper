use e.algo.stat
use e.io
use e.mem

fn near(actual: f64, expected: f64) -> bool {
    ret actual > expected - 0.00001f64 && actual < expected + 0.00001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let p_counts = [8]usize{ 2usize, 10usize, 3usize, 9usize, 1usize, 11usize, 4usize, 8usize }
    let u_counts = [8]usize{ 1usize, 12usize, 0usize, 14usize, 2usize, 11usize, 1usize, 13usize }
    let p_sizes = [8]usize{ 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize, 100usize }
    let u_sizes = [8]usize{ 10usize, 10usize, 10usize, 10usize, 10usize, 10usize, 10usize, 10usize }
    var points: [8]stat.AttributeControlPoint = zero
    let (p_sigma, p_error) = stat.laney_control(.P, p_counts[..], p_sizes[..], points[..])
    if p_error != ok || !near(p_sigma, 2.666387795) || !near(points[0usize].center, 0.06) || !near(points[0usize].upper, 0.249969605) || !near(points[0usize].lower, 0.0) { ret stat.Invalid }
    let (u_sigma, u_error) = stat.laney_control(.U, u_counts[..], u_sizes[..], points[..])
    if u_error != ok || !near(u_sigma, 3.899697867) || !near(points[0usize].center, 0.675) || !near(points[0usize].upper, 3.714513678) || !near(points[0usize].lower, 0.0) { ret stat.Invalid }
    let variable_counts = [4]usize{ 1usize, 4usize, 2usize, 8usize }
    let variable_sizes = [4]usize{ 20usize, 40usize, 25usize, 50usize }
    let (variable_sigma, variable_error) = stat.laney_control(.P, variable_counts[..], variable_sizes[..], points[..])
    if variable_error != ok || !near(variable_sigma, 0.742423834) || !near(points[0usize].upper, 0.267627798) || !near(points[1usize].upper, 0.221785122) { ret stat.Invalid }
    let (unused_short, short_error) = stat.laney_control(.P, p_counts[..], p_sizes[..], points[..7usize])
    if short_error != stat.TooSmall { ret stat.Invalid }
    let (unused_kind, kind_error) = stat.laney_control(.C, p_counts[..], p_sizes[..], points[..])
    if kind_error != stat.Invalid { ret stat.Invalid }
    let empty_counts = [2]usize{ 0usize, 0usize }
    let empty_sizes = [2]usize{ 10usize, 10usize }
    let (unused_empty, empty_error) = stat.laney_control(.P, empty_counts[..], empty_sizes[..], points[..])
    if empty_error != stat.Invalid { ret stat.Invalid }
    try io.print("gfx chart laney ok\n")
    ret ok
}
