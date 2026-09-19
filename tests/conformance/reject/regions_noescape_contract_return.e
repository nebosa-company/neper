type View = struct {
    bytes: []const u8,
}

// A returned aggregate cannot retain an input promised not to escape.
@noescape("bytes")
fn retain(bytes: []const u8) -> View {
    let view = View { bytes: bytes }
    ret view
}

fn main() {}
