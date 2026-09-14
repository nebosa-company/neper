// A `(` still open when a column-0 `fn` arrives (D275): E-SYNTAX-0012 at the opener,
// naming the keyword that ended it, and the parse goes on past it.
fn a() -> i32 {
    let x = pick(1i32,

fn b() -> i32 {
    ret 2i32
}
