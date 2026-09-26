fn inner(xs: []const u8, i: usize) -> u8 {
    ret xs[i]
}

fn outer(xs: []const u8, i: usize) -> u8 {
    ret inner(xs, i) +% 1u8
}
