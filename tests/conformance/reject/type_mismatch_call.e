// A scalar mismatch at a whole value (D491, H09): a call's result, like a name or
// a literal (D444), is wrapped in the expected type as a `maybe` fix over the whole
// call -- `i64(half())` -- since the conversion converts nothing but the result.
fn half() -> i32 {
    ret 21i32
}

fn main() -> i32 {
    let doubled: i64 = half()
    ret i32(doubled + doubled)
}
