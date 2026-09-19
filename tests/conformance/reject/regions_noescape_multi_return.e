type View = struct {
    bytes: []const u8,
}

// Every named input is checked through pointer-bearing aggregate leaves.
@noescape("left", "right")
fn retain(left: []const u8, right: []const u8) -> View {
    ret View { bytes: right }
}

fn main() {}
