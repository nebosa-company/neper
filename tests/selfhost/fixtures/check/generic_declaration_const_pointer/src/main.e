fn bad[T: type](pointer: *const T, value: T) {
    *pointer = value
}
