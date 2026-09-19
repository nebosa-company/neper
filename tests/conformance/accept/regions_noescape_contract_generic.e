@noescape("bytes")
fn observe[T: type](bytes: []const u8, value: T) -> usize {
    ret bytes.len
}

// Specialization preserves the template's checked no-escape summary.
@noescape("bytes")
fn forward(bytes: []const u8) -> usize {
    ret observe[usize](bytes, bytes.len)
}

fn main() {}
