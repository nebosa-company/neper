type Buffer[T: type] = struct {
    value: T,
}

fn bad[T: type](buffer: Buffer[T]) -> usize {
    ret buffer.len
}
