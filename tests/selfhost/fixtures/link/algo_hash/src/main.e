use algo.hash as hash
use e.io
use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    if hash.fnv1a32("") != 2166136261u32 { ret Failed }
    if hash.fnv1a32("hello") != 1335831723u32 { ret Failed }
    if hash.fnv1a64("") != 14695981039346656037u64 { ret Failed }
    if hash.fnv1a64("hello") != 11831194018420276491u64 { ret Failed }
    if hash.xxhash64("", 0u64) != 17241709254077376921u64 { ret Failed }
    if hash.xxhash64("hello", 0u64) != 2794345569481354659u64 { ret Failed }
    if hash.crc32("") != 0u32 { ret Failed }
    if hash.crc32("123456789") != 3421780262u32 { ret Failed }
    if hash.adler32("Wikipedia") != 300286872u32 { ret Failed }

    let input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    var xx = hash.xxhash64_init(7u64)
    hash.xxhash64_update(&xx, input[..3usize])
    hash.xxhash64_update(&xx, input[3usize..35usize])
    hash.xxhash64_update(&xx, input[35usize..])
    if hash.xxhash64(input, 7u64) != 17280636183555563867u64 { ret Failed }
    if hash.xxhash64_done(&xx) != hash.xxhash64(input, 7u64) { ret Failed }

    var crc = hash.crc32_init()
    hash.crc32_update(&crc, "1234")
    hash.crc32_update(&crc, "56789")
    if hash.crc32_done(&crc) != 3421780262u32 { ret Failed }
    try io.print("algo hash ok\n")
    ret ok
}
