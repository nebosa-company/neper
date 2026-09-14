// Three statements that do not parse (D275): every one is a diagnostic at its own
// token, and each is an ErrorNode in the tree.
fn a() -> i32 {
    let x = = 1i32
    let y = 2i32
    ret x +
}

fn b() {
    ret )
}
