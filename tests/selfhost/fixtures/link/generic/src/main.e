fn ignore[T: type](value: T) -> err {
    ret ok
}

fn main() -> err {
    ret ignore[i32](0i32)
}
