fn bad[T: type](value: T) -> i32 {
    switch value {
    default:
        ret 1i32
    default:
        ret 0i32
    }
}
