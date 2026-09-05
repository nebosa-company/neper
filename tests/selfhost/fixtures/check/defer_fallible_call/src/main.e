error Failed

fn fallible() -> err {
    ret Failed
}

fn run() {
    defer fallible()
}
