fn choose[T: type](left: T, right: T) -> T {
    ret left
}

fn run() {
    let value = choose(1i32, 2u16)
}
