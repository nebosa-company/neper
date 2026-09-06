fn main() -> i64 {
    let narrowed: i8 = i8(255u16)
    ret i64(narrowed) + 1i64
}
