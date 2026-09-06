fn main() -> i64 {
    let left: u8 = u8(1u16) << 3u32
    let right: i8 = i8(-128i16) >> 7u32
    ret i64(left - u8(8u16)) + i64(right) + 1i64
}
