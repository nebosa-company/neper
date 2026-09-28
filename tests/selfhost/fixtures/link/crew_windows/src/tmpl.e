// The templates every module of `crew_windows` instantiates (D1670). `wrap` calls
// `pick`, so each instance of `wrap` makes an instance of `pick` in the same owner.

fn pick[T: type](a: T, b: T, first: bool) -> T {
    if first { ret a }
    ret b
}

fn wrap[T: type](a: T, b: T) -> T {
    ret pick[T](a, b, false)
}
