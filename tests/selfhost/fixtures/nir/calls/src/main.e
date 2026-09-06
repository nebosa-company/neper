fn increment(value: i64) -> i64 {
    ret value + 1i64
}

fn invoke() -> i64 {
    ret increment(4i64)
}
