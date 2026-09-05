fn maybe[T: type](value: T) -> (T, err) {
    ret (value, ok)
}

fn fixed[N: usize]() -> usize {
    ret N
}

fn run() -> err {
    let explicit = try maybe[i32](1)
    let (inferred, status) = maybe(explicit)
    let count = fixed[4]()
    ret status
}
