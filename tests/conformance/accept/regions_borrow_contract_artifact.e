// The public interface carries the one-based parameter position (`right` is 2).
@borrows("right")
fn choose(left: []const u8, right: []const u8) -> []const u8 {
    ret right
}

fn main() {}
