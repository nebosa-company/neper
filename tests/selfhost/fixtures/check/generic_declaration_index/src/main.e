fn bad[T: type, N: usize](values: [N]T) -> T {
    ret values[true]
}
