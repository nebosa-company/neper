fn consume(value: i32) {}

fn bad[T: type](value: T) -> T {
    consume()
    ret value
}
