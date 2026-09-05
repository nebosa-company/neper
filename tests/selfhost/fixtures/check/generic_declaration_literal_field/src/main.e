type Buffer[T: type] = struct {
    value: T,
}

fn bad[T: type](value: T) -> Buffer[T] {
    ret Buffer[T]{ missing: value }
}
