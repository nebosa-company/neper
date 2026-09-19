@noescape("left", "right")
fn observe[T: type](left: []const u8, right: []const u8, value: T) -> usize {
    ret left.len + right.len
}

// Specialization preserves both checked positions from the template.
@noescape("left", "right")
fn forward(left: []const u8, right: []const u8) -> usize {
    ret observe[usize](left, right, left.len)
}

fn main() {}
