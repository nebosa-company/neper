fn pair() -> (i32, bool, err) {
    ret (1i32, true, ok)
}

fn run() -> err {
    let result = try pair()
    ret ok
}
