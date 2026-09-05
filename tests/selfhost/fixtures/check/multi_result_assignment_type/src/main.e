fn pair() -> (i32, bool) {
    ret (1i32, true)
}

fn run() {
    var first = 0i32
    var second = 0i32
    (first, second) = pair()
}
