fn produce() -> i32 {
    ret 1i32
}

fn run() {
    defer let saved = produce()
    let copy = saved
}
