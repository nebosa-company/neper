fn choose[T: type, N: usize](value: T) -> T {
    ret value
}

fn run() {
    let value = choose[i32](1)
}
