// The differential oracle's program (D449, H10): every line of the file named by
// the first argument is hashed and encoded by the library, one answer line per
// input -- `sha256:<hex> sha3:<hex> b64:<base64>` -- for `benchmarks/differential`
// to check against Python's hashlib and base64, an implementation that shares
// nothing with this one.
use e.mem
use e.os
use e.io
use e.fs
use e.bytes
use e.crypto.hash

error Failed

fn hex_digit(value: u8) -> u8 {
    if value < 10u8 { ret 48u8 + value }
    ret 87u8 + value
}

fn print_hex(digest: []const u8) -> err {
    var line: [128]u8 = zero
    var at = 0usize
    while at < digest.len && at * 2usize + 1usize < line.len {
        line[at * 2usize] = hex_digit(digest[at] >> 4u8)
        line[at * 2usize + 1usize] = hex_digit(digest[at] & 15u8)
        at += 1usize
    }
    ret io.print(line[0usize..at * 2usize])
}

fn answer(a: *mem.Arena, input: []const u8) -> err {
    let digest = hash.sha256(input)
    try io.print("sha256:")
    try print_hex(digest[..])
    let digest3 = hash.sha3_256(input)
    try io.print(" sha3:")
    try print_hex(digest3[..])
    try io.print(" b64:")
    let (encoded_len, len_error) = bytes.base64_encoded_len(input.len, true)
    if len_error != ok { ret len_error }
    let (storage, storage_error) = mem.alloc[u8](a, encoded_len + 1usize)
    if storage_error != ok { ret storage_error }
    let (encoded, encode_error) = bytes.base64_encode(storage, input, .Standard, true)
    if encode_error != ok { ret encode_error }
    try io.print(encoded)
    ret io.print("\n")
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret Failed }
    let (text, read_error) = fs.read_file(a, args[1usize], 16777216usize)
    if read_error != ok { ret read_error }
    var start = 0usize
    var at = 0usize
    while at <= text.len {
        if at == text.len || text[at] == 10u8 {
            if at > start { try answer(a, text[start..at]) }
            start = at + 1usize
        }
        at += 1usize
    }
    ret ok
}
