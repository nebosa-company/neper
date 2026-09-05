error Failed

fn fallible() -> err {
    ret Failed
}

fn run() -> err {
    defer {
        try fallible()
    }
    ret ok
}
