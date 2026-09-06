fn main() -> i64 {
    let wrapped: u8 = u8(250u16) +% u8(6u16)
    let bits: u8 = u8(3u16) ^ u8(3u16)
    ret i64(wrapped | bits)
}
