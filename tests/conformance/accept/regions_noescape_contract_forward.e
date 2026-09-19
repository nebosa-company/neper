@noescape("bytes")
fn observe(bytes: []const u8) -> usize {
    ret bytes.len
}

// A caller may forward its no-escape input only to the matching checked contract.
@noescape("bytes")
fn forward(bytes: []const u8) -> usize {
    ret observe(bytes)
}

fn main() {}
