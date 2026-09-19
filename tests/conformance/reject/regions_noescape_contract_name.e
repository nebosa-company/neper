// A no-escape contract names one pointer-bearing input exactly.
@noescape("missing")
fn count(bytes: []const u8) -> usize {
    ret bytes.len
}

fn main() {}
