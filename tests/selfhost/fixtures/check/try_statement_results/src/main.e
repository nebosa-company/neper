fn value() -> (i32, err) {
    ret (1i32, ok)
}

fn run() -> err {
    try value()
    ret ok
}
