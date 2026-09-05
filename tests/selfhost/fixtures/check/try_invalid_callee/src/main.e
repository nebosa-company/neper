fn value() -> i32 {
    ret 1i32
}

fn run() -> err {
    let result = try value()
    ret ok
}
