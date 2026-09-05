fn invalid[T: type](value: T) -> T {
    ret true
}

fn run() -> i32 {
    ret invalid[i32](1)
}
