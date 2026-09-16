// A constant the root folds on (D492, H14): its value is baked into `main`'s body,
// so a change to it is a value edge that rebuilds `main`, not a body change behind a
// signature that keeps it.
const LIMIT: usize = 3usize

fn answer() -> i32 {
    ret 4i32
}
