// Spec section 9 rule 4: the supplied `hash` is xxHash64 seed 0 over a value's
// canonical little-endian bytes, so it must agree with algo.hash.xxhash64 over
// those same bytes.

use e.algo.hash

error Failed

type Level = enum u32 {
    None = 0u32,
    High = 70000u32,
}

fn digest[T: type](v: T) -> u64 {
    ret T.hash(v)
}

fn main() -> err {
    // The supplied hash is xxHash64 seed 0 over the value's canonical bytes, so it
    // has to agree with the library implementation over those same bytes.
    if digest[str]("") != hash.xxhash64("", 0u64) { ret Failed }
    if digest[str]("abc") != hash.xxhash64("abc", 0u64) { ret Failed }
    if digest[str]("0123456789abcdef0123456789abcdef0") != hash.xxhash64("0123456789abcdef0123456789abcdef0", 0u64) { ret Failed }
    if digest[str]("abc") == digest[str]("abd") { ret Failed }

    // A scalar hashes its own little-endian bytes.
    var word: [8]u8 = zero
    word[0usize] = 1u8
    if digest[u64](1u64) != hash.xxhash64(word[0usize..8usize], 0u64) { ret Failed }
    var small: [4]u8 = zero
    small[0usize] = 2u8
    if digest[u32](2u32) != hash.xxhash64(small[0usize..4usize], 0u64) { ret Failed }
    var one: [1]u8 = zero
    one[0usize] = 5u8
    if digest[u8](5u8) != hash.xxhash64(one[0usize..1usize], 0u64) { ret Failed }
    if digest[u64](1u64) == digest[u64](2u64) { ret Failed }
    if digest[bool](true) == digest[bool](false) { ret Failed }

    // An enum hashes its backing value.
    var level_bytes: [4]u8 = zero
    level_bytes[0usize] = 112u8
    level_bytes[1usize] = 17u8
    level_bytes[2usize] = 1u8
    if digest[Level](Level.High) != hash.xxhash64(level_bytes[0usize..4usize], 0u64) { ret Failed }
    if digest[Level](Level.High) == digest[Level](Level.None) { ret Failed }

    // An array and a slice hash the same contiguous run.
    var values: [4]u32 = zero
    values[0usize] = 1u32
    values[1usize] = 2u32
    values[2usize] = 3u32
    values[3usize] = 4u32
    var raw: [16]u8 = zero
    raw[0usize] = 1u8
    raw[4usize] = 2u8
    raw[8usize] = 3u8
    raw[12usize] = 4u8
    let expected = hash.xxhash64(raw[0usize..16usize], 0u64)
    if digest[[4]u32](values) != expected { ret Failed }
    if digest[[]u32](values[0usize..4usize]) != expected { ret Failed }
    if digest[[]u32](values[0usize..3usize]) == expected { ret Failed }

    // Nested arrays are still one contiguous run.
    var grid: [2][2]u32 = zero
    grid[0usize][0usize] = 1u32
    grid[0usize][1usize] = 2u32
    grid[1usize][0usize] = 3u32
    grid[1usize][1usize] = 4u32
    if digest[[2][2]u32](grid) != expected { ret Failed }

    ret ok
}
