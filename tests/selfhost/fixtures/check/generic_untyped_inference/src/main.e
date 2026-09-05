fn identity[T: type](value: T) -> T {
    ret value
}

fn run() -> i32 {
    ret identity(1)
}
