fn bad[T: type](left: *T, right: *T) -> *T {
    ret left + right
}
