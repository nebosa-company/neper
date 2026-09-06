fn main() -> i64 {
    let quotient: i64 = -21i64 / 4i64
    let remainder: i64 = -21i64 % 4i64
    let unsigned_quotient: u64 = 21u64 / 4u64
    let unsigned_remainder: u64 = 21u64 % 4u64
    ret quotient + 5i64 + remainder + 1i64 + i64(unsigned_quotient - 5u64) + i64(unsigned_remainder - 1u64)
}
