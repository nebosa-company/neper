// `dis-file --json --release` (D542): the release image, and each function's
// `inlined` runs -- here two copies of `add`'s body in `main`, one of them through
// `twice`, named for the innermost callee.
use e.os
fn add(x: i32, y: i32) -> i32 {
    ret x + y
}
fn twice(x: i32) -> i32 {
    ret add(x, x)
}
fn main() {
    os.exit(twice(add(2i32, 3i32)))
}
