// The public interface carries the one-based parameter position (`right` is 2).
@noescape("right")
fn observe(left: []const u8, right: []const u8) -> usize {
    ret left.len + right.len
}

fn main() {}
