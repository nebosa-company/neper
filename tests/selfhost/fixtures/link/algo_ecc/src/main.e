// `e.algo.ecc`: Reed-Solomon parity agrees with a Python replica of the
// reedsolo conventions and four errors, three errors with two erasures, and
// two wiped chunks of a 4 + 2 erasure code are restored while five errors
// are refused; BCH(15,7) corrects every one- and two-bit pattern on every
// word; Viterbi restores 200 LCG messages under spaced bursts; min-sum LDPC
// over a 6 x 12 matrix corrects every single error of every codeword; and
// Hamming(7,4) and SECDED(8,4) are exhaustive. Each check exits with its
// own code.

use e.algo.ecc
use e.io
use e.mem
use e.os

fn lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn distinct(state: *u64, count: usize, bound: u64, out: []usize) {
    var n = 0usize
    while n < count {
        let p = usize(lcg(state) % bound)
        var seen = false
        var i = 0usize
        while i < n {
            if out[i] == p { seen = true }
            i += 1usize
        }
        if !seen {
            out[n] = p
            n += 1usize
        }
    }
}

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let f = ecc.field()
    var state = 7u64

    // 1: Reed-Solomon, 32 data bytes and 8 parity symbols.
    var data: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        data[i] = u8(lcg(&state) & 255u64)
        i += 1usize
    }
    var code: [40]u8 = zero
    let (n, encode_error) = ecc.reed_solomon_encode(&f, data[..], 8usize, code[..])
    if encode_error != ok || n != 40usize { os.exit(1i32) }
    var weighted = 0u64
    i = 0usize
    while i < 8usize {
        weighted += u64(i + 1usize) * u64(code[32usize + i])
        i += 1usize
    }
    if weighted != 4315u64 { os.exit(1i32) }
    var received: [40]u8 = zero
    var positions: [8]usize = zero
    // Four errors.
    received = code
    distinct(&state, 4usize, 40u64, positions[..])
    i = 0usize
    while i < 4usize {
        received[positions[i]] ^= u8(lcg(&state) % 255u64) + 1u8
        i += 1usize
    }
    var none: [0]usize = zero
    let (fixed4, error4) = ecc.reed_solomon_decode(&f, received[..], 8usize, none[..])
    if error4 != ok || fixed4 != 4usize || !same(received[..], code[..]) { os.exit(1i32) }
    // Three errors and two erasures.
    received = code
    distinct(&state, 5usize, 40u64, positions[..])
    i = 0usize
    while i < 3usize {
        received[positions[i]] ^= u8(lcg(&state) % 255u64) + 1u8
        i += 1usize
    }
    while i < 5usize {
        received[positions[i]] = u8(lcg(&state) & 255u64)
        i += 1usize
    }
    let (fixed5, error5) = ecc.reed_solomon_decode(&f, received[..], 8usize, positions[3usize..5usize])
    if error5 != ok || fixed5 != 5usize || !same(received[..], code[..]) { os.exit(1i32) }
    // Five errors are beyond eight parity symbols.
    received = code
    distinct(&state, 5usize, 40u64, positions[..])
    i = 0usize
    while i < 5usize {
        received[positions[i]] ^= u8(lcg(&state) % 255u64) + 1u8
        i += 1usize
    }
    let (_, error_five) = ecc.reed_solomon_decode(&f, received[..], 8usize, none[..])
    if error_five != ecc.Invalid { os.exit(1i32) }
    let (_, clean_error) = ecc.reed_solomon_decode(&f, code[..], 8usize, none[..])
    if clean_error != ok || state != 14016802753645532771u64 { os.exit(1i32) }
    var small: [39]u8 = zero
    let (_, small_error) = ecc.reed_solomon_encode(&f, data[..], 8usize, small[..])
    if small_error != ecc.TooSmall { os.exit(1i32) }

    // 2: 4 + 2 erasure coding over 5-byte chunks.
    var chunks: [30]u8 = zero
    i = 0usize
    while i < 20usize {
        chunks[i] = u8(lcg(&state) & 255u64)
        i += 1usize
    }
    if ecc.reed_solomon_erasure_encode(&f, chunks[..20usize], 4usize, chunks[20usize..], 2usize) != ok { os.exit(2i32) }
    weighted = 0u64
    i = 0usize
    while i < 2usize {
        var j = 0usize
        while j < 5usize {
            weighted += u64(i + 1usize) * u64(j + 1usize) * u64(chunks[20usize + i * 5usize + j])
            j += 1usize
        }
        i += 1usize
    }
    if weighted != 7584u64 { os.exit(2i32) }
    let whole = chunks
    var missing: [3]usize = zero
    missing[0usize] = 1usize
    missing[1usize] = 4usize
    i = 0usize
    while i < 5usize {
        chunks[5usize + i] = 0u8
        chunks[20usize + i] = 0u8
        i += 1usize
    }
    if ecc.reed_solomon_erasure_decode(&f, chunks[..], 4usize, 2usize, missing[..2usize]) != ok || !same(chunks[..], whole[..]) { os.exit(2i32) }
    missing[2usize] = 0usize
    if ecc.reed_solomon_erasure_decode(&f, chunks[..], 4usize, 2usize, missing[..]) != ecc.Invalid { os.exit(2i32) }

    // 3: BCH(15,7), t = 2: every one- and two-bit pattern on every word.
    if ecc.bch_encode(465u32, 85u32) != 0x55e5u32 || ecc.bch_encode(465u32, 127u32) != 0x7fffu32 { os.exit(3i32) }
    var word = 0u32
    while word < 128u32 {
        let c = ecc.bch_encode(465u32, word)
        let (unchanged, count0, clean) = ecc.bch_decode(c, 2usize)
        if clean != ok || unchanged != c || count0 != 0usize { os.exit(3i32) }
        var p = 0u32
        while p < 15u32 {
            var q = p + 1u32
            let (one, count1, e1) = ecc.bch_decode(c ^ (1u32 << p), 2usize)
            if e1 != ok || one != c || count1 != 1usize { os.exit(3i32) }
            while q < 15u32 {
                let (two, count2, e2) = ecc.bch_decode(c ^ (1u32 << p) ^ (1u32 << q), 2usize)
                if e2 != ok || two != c || count2 != 2usize { os.exit(3i32) }
                q += 1u32
            }
            p += 1u32
        }
        word += 1u32
    }
    let (_, _, three) = ecc.bch_decode(0x55e5u32 ^ 0x105u32, 2usize)
    if three != ecc.Invalid { os.exit(3i32) }
    // Hamming(15,11) as t = 1.
    let (h15, hcount, herror) = ecc.bch_decode(ecc.bch_encode(19u32, 1234u32) ^ 64u32, 1usize)
    if herror != ok || h15 != ecc.bch_encode(19u32, 1234u32) || hcount != 1usize { os.exit(3i32) }

    // 4: the (7, 5) convolutional code and Viterbi over 200 LCG messages.
    var message: [40]u8 = zero
    var encoded: [84]u8 = zero
    var decoded: [40]u8 = zero
    var survivors: [168]u8 = zero
    message[0usize] = 1u8
    message[2usize] = 1u8
    message[3usize] = 1u8
    message[6usize] = 1u8
    let (enc_len, enc_error) = ecc.convolutional_encode(message[..8usize], encoded[..])
    if enc_error != ok || enc_len != 20usize { os.exit(4i32) }
    var packed = 0u64
    i = 0usize
    while i < 20usize {
        packed = (packed << 1u32) | u64(encoded[i])
        i += 1usize
    }
    if packed != 923628u64 { os.exit(4i32) }
    var seed = 11u64
    var flips = 0usize
    var trial = 0usize
    while trial < 200usize {
        let length = 1usize + usize(lcg(&seed) % 40u64)
        i = 0usize
        while i < length {
            message[i] = u8(lcg(&seed) & 1u64)
            i += 1usize
        }
        let (total, e) = ecc.convolutional_encode(message[..length], encoded[..])
        if e != ok { os.exit(4i32) }
        var p = 0usize
        while p < total {
            if lcg(&seed) % 10u64 < 3u64 {
                let count = 1usize + usize(lcg(&seed) % 2u64)
                var q = 0usize
                while q < count {
                    if p + q < total {
                        encoded[p + q] ^= 1u8
                        flips += 1usize
                    }
                    q += 1usize
                }
                p += 20usize
            } else {
                p += 2usize
            }
        }
        let (bits, decode_error) = ecc.viterbi_decode(encoded[..total], decoded[..], survivors[..])
        if decode_error != ok || bits != length { os.exit(4i32) }
        i = 0usize
        while i < length {
            if decoded[i] != message[i] { os.exit(4i32) }
            i += 1usize
        }
        trial += 1usize
    }
    if flips != 602usize { os.exit(4i32) }
    let (_, odd_error) = ecc.viterbi_decode(encoded[..7usize], decoded[..], survivors[..])
    if odd_error != ecc.Invalid { os.exit(4i32) }

    // 5: min-sum LDPC over a 6 x 12 matrix: every single error of every codeword.
    var h: [72]u8 = zero
    i = 0usize
    while i < 12usize {
        h[(i / 4usize) * 12usize + i] = 1u8
        i += 1usize
    }
    i = 0usize
    while i < 9usize {
        h[(3usize + i % 3usize) * 12usize + (i / 3usize) * 4usize + i % 3usize] = 1u8
        i += 1usize
    }
    var codeword: [12]u8 = zero
    var noisy: [12]u8 = zero
    var beliefs: [84]f64 = zero
    var codewords = 0usize
    var corrected = 0usize
    var iterations = 0usize
    var w = 0u32
    while w < 4096u32 {
        i = 0usize
        while i < 12usize {
            codeword[i] = u8((w >> u32(i)) & 1u32)
            i += 1usize
        }
        if ecc.ldpc_check(h[..], 6usize, 12usize, codeword[..]) {
            codewords += 1usize
            i = 0usize
            while i < 12usize {
                noisy = codeword
                noisy[i] ^= 1u8
                let (its, e) = ecc.ldpc_decode(h[..], 6usize, 12usize, noisy[..], beliefs[..], 20usize)
                if e == ok && same(noisy[..], codeword[..]) {
                    corrected += 1usize
                    iterations += its
                }
                i += 1usize
            }
        }
        w += 1u32
    }
    if codewords != 64usize || corrected != 768usize || iterations != 1152usize { os.exit(5i32) }
    let (_, room) = ecc.ldpc_decode(h[..], 6usize, 12usize, noisy[..], beliefs[..70usize], 20usize)
    if room != ecc.TooSmall { os.exit(5i32) }

    // 6: Hamming(7,4) and SECDED(8,4), exhaustively.
    var sum7 = 0u32
    var sum8 = 0u32
    var nibble = 0u8
    while nibble < 16u8 {
        let c7 = ecc.hamming_encode(nibble)
        let c8 = ecc.secded_encode(nibble)
        sum7 += u32(c7)
        sum8 += u32(c8)
        let (d, fixed, bad) = ecc.hamming_decode(c7)
        if d != nibble || fixed || bad { os.exit(6i32) }
        let (d8, fixed8, bad8) = ecc.secded_decode(c8)
        if d8 != nibble || fixed8 || bad8 { os.exit(6i32) }
        var p = 0u32
        while p < 8u32 {
            if p < 7u32 {
                let (d1, fixed1, bad1) = ecc.hamming_decode(c7 ^ (1u8 << p))
                if d1 != nibble || !fixed1 || bad1 { os.exit(6i32) }
            }
            let (s1, sfixed1, sbad1) = ecc.secded_decode(c8 ^ (1u8 << p))
            if s1 != nibble || !sfixed1 || sbad1 { os.exit(6i32) }
            var q = p + 1u32
            while q < 8u32 {
                let (_, _, double) = ecc.secded_decode(c8 ^ (1u8 << p) ^ (1u8 << q))
                if !double { os.exit(6i32) }
                q += 1u32
            }
            p += 1u32
        }
        nibble += 1u8
    }
    if sum7 != 1016u32 || sum8 != 2040u32 { os.exit(6i32) }

    try io.print("algo ecc ok\n")
    ret ok
}
