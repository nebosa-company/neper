// SHA-256 from e.crypto.hash, printed as hex by e.bytes.

use e.bytes
use e.crypto.hash
use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let digest = hash.sha256("neper")
    var buf: [64]u8 = undef
    let (hex, hex_error) = bytes.hex_encode(buf[0..], digest[0..], false)
    if hex_error != ok { ret hex_error }
    try io.printf["sha256(\"neper\") = {}\n"](hex)
    ret ok
}
