fn identity[T: type](value: T) -> T {
    ret value
}

fn run() -> i32 {
    ret identity[i32, u8](1)
}
