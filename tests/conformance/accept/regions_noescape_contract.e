// A checked no-escape contract may name one borrowed pointer-bearing input.
@noescape("bytes")
fn count(bytes: []const u8) -> usize {
    ret bytes.len
}

fn main() {}
