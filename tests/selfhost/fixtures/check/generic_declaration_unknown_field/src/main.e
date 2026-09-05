type Buffer[T: type] = struct {
    value: T,
}

fn bad[T: type](buffer: Buffer[T]) -> T {
    ret buffer.missing
}
