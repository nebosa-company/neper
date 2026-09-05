fn bad[T: type](value: T) -> T {
    let wrong: i32 = true
    ret value
}
