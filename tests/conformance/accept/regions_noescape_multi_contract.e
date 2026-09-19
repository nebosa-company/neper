// One checked contract may cover every borrowed pointer-bearing input it names.
@noescape("left", "right")
fn count(left: []const u8, right: []const u8) -> usize {
    ret left.len + right.len
}

fn main() {}
