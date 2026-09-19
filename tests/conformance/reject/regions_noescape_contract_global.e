var retained: []const u8 = zero

// A global store cannot retain an input promised not to escape.
@noescape("bytes")
fn retain(bytes: []const u8) {
    retained = bytes
}

fn main() {}
