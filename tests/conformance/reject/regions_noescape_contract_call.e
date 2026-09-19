fn retain(bytes: []const u8) {}

// An unannotated callee may retain the input after this call returns.
@noescape("bytes")
fn forward(bytes: []const u8) {
    retain(bytes)
}

fn main() {}
