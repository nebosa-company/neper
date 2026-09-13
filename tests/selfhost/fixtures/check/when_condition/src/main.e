// A `when` condition that is not a question about `target` is refused (D216).
fn main() {
    let x = 1usize
    when x == 1usize {
    }
}
