// A result-borrow summary names one pointer-bearing input exactly.
@borrows("missing")
fn head(bytes: []const u8) -> []const u8 {
    ret bytes
}

fn main() {}
