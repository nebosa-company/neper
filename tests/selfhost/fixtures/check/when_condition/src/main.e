// A `when` condition that is neither a question about `target` nor a bool the
// interpreter can evaluate -- a local is runtime state -- is refused (D216, D220).
fn main() {
    let x = 1usize
    when x == 1usize {
    }
}
