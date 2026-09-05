fn bad[T: type](value: T) -> i32 {
    switch value {
    case .First:
        let wrong: i32 = true
        ret 1i32
    default:
        ret 0i32
    }
}
