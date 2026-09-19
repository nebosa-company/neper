@noescape("left", "right")
fn observe(left: []const u8, right: []const u8) -> usize {
    ret left.len + right.len
}

// Every forwarded input lands in a callee position with the same guarantee.
@noescape("left", "right")
fn forward(left: []const u8, right: []const u8) -> usize {
    ret observe(left, right)
}

fn main() {}
