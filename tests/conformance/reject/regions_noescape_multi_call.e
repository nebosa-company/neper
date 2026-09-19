fn retain(bytes: []const u8) {}

// The second named input cannot bypass forwarding checks.
@noescape("left", "right")
fn forward(left: []const u8, right: []const u8) {
    retain(right)
}

fn main() {}
