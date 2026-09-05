fn bad[T: type](value: T) -> T {
    let wrong: bool = true + false
    ret value
}
