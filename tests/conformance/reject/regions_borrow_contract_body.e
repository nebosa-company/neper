// The body must return a value derived from the parameter named by the summary.
@borrows("first")
fn choose(first: []const u8, second: []const u8) -> []const u8 {
    ret second
}

fn main() {}
