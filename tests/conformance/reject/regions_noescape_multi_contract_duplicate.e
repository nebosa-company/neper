// Each input appears at most once in a no-escape summary.
@noescape("bytes", "bytes")
fn count(bytes: []const u8) -> usize {
    ret bytes.len
}

fn main() {}
