// The index is out of range: a bounds trap here, two frames deep.
fn pick(xs: []const u8, i: usize) -> u8 {
    ret xs[i]
}
