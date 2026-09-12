// HKDF by RFC 5869 over `e.crypto.mac`: extract is HMAC(salt, ikm) with an absent salt
// standing for a block of zeros, and expand is the chain T(i) = HMAC(prk, T(i-1) ||
// info || i) for as many blocks as `dst` needs, at most 255 -- refused before a byte
// is written. Nothing here is a password-hashing function.

use e.crypto.mac as mac

error TooLarge

fn hkdf_sha256_extract(salt: []const u8, input_key: []const u8) -> [32]u8 {
    if salt.len == 0usize {
        let zeros: [32]u8 = zero
        ret mac.hmac_sha256(zeros[0..], input_key)
    }
    ret mac.hmac_sha256(salt, input_key)
}

fn hkdf_sha256_expand(dst: []u8, prk: [32]u8, info: []const u8) -> err {
    if dst.len > 255usize * 32usize { ret TooLarge }
    var previous: [32]u8 = zero
    var previous_len = 0usize
    var written = 0usize
    var counter = 1u8
    while written < dst.len {
        var s = mac.sha256_init(prk[0..])
        mac.sha256_update(&s, previous[..previous_len])
        mac.sha256_update(&s, info)
        var index: [1]u8 = zero
        index[0] = counter
        mac.sha256_update(&s, index[0..])
        previous = mac.sha256_done(&s)
        previous_len = 32usize
        var at = 0usize
        while at < 32usize && written < dst.len {
            dst[written] = previous[at]
            written += 1usize
            at += 1usize
        }
        counter += 1u8
    }
    ret ok
}

fn hkdf_sha512_extract(salt: []const u8, input_key: []const u8) -> [64]u8 {
    if salt.len == 0usize {
        let zeros: [64]u8 = zero
        ret mac.hmac_sha512(zeros[0..], input_key)
    }
    ret mac.hmac_sha512(salt, input_key)
}

fn hkdf_sha512_expand(dst: []u8, prk: [64]u8, info: []const u8) -> err {
    if dst.len > 255usize * 64usize { ret TooLarge }
    var previous: [64]u8 = zero
    var previous_len = 0usize
    var written = 0usize
    var counter = 1u8
    while written < dst.len {
        var s = mac.sha512_init(prk[0..])
        mac.sha512_update(&s, previous[..previous_len])
        mac.sha512_update(&s, info)
        var index: [1]u8 = zero
        index[0] = counter
        mac.sha512_update(&s, index[0..])
        previous = mac.sha512_done(&s)
        previous_len = 64usize
        var at = 0usize
        while at < 64usize && written < dst.len {
            dst[written] = previous[at]
            written += 1usize
            at += 1usize
        }
        counter += 1u8
    }
    ret ok
}
