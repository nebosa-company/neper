// RFC 6455's client nonce is exactly sixteen caller-supplied bytes and encodes to a
// padded twenty-four-byte standard Base64 key without allocation.

use e.net.ws
use e.str

error Failed

fn main() -> err {
    var entropy: [16]u8 = zero
    let source = "the sample nonce"
    var at = 0usize
    while at < entropy.len {
        entropy[at] = source[at]
        at += 1usize
    }
    var output: [24]u8 = zero
    let (key, key_error) = ws.client_key(entropy, output[0..])
    if key_error != ok || !str.eq(key, "dGhlIHNhbXBsZSBub25jZQ==") { ret Failed }
    let (short_key, short_error) = ws.client_key(entropy, output[0..23usize])
    if short_error != ws.TooLarge || short_key.len != 0usize { ret Failed }
    ret ok
}
