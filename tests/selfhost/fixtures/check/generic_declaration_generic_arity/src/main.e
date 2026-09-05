fn identity[T: type](value: T) -> T {
    ret value
}

fn bad[T: type](value: T) -> T {
    ret identity[T, T](value)
}
