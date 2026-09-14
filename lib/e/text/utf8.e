// UTF-8 as the encoding of `str`: strict decoding, encoding, counting and a lossy
// iterator.
//
// `str` is bytes, and nothing about the type says they are well-formed. This module is
// where that question is asked once. `decode` is strict and answers `Invalid` for every
// malformed shape Unicode names -- a bad lead byte, a missing or wrong continuation, an
// overlong encoding, a surrogate, or a scalar past U+10FFFF -- and never guesses.
// `iterator_next` is the lossy reading a display path wants: a malformed byte becomes
// U+FFFD and consumes one byte, so a corrupt run degrades to replacement characters
// rather than swallowing the text after it. The validity rules are the same ones
// `e.text.unicode` reads by, so the two never disagree about what a string contains.

type Decode = struct {
    scalar: u32,
    width: u8,
}

type Iterator = struct {
    data: str,
    off: usize,
}

error Invalid
error TooSmall

// The scalar at `off` and how many bytes it took. A lead byte of 0xC0/0xC1 or 0xF5 and
// above never starts a valid sequence, so those fail before any continuation is read.
fn decode(s: str, off: usize) -> (Decode, err) {
    if off >= s.len { ret (Decode { scalar: 0u32, width: 0u8 }, Invalid) }
    let b0 = u32(s[off])
    if b0 < 128u32 { ret (Decode { scalar: b0, width: 1u8 }, ok) }
    var need = 0usize
    var scalar = 0u32
    if b0 >= 194u32 && b0 < 224u32 {
        need = 1usize
        scalar = b0 & 31u32
    } else {
        if b0 >= 224u32 && b0 < 240u32 {
            need = 2usize
            scalar = b0 & 15u32
        } else {
            if b0 >= 240u32 && b0 < 245u32 {
                need = 3usize
                scalar = b0 & 7u32
            } else {
                ret (Decode { scalar: 0u32, width: 0u8 }, Invalid)
            }
        }
    }
    if off + need >= s.len { ret (Decode { scalar: 0u32, width: 0u8 }, Invalid) }
    var i = 1usize
    while i <= need {
        let b = u32(s[off + i])
        if b & 192u32 != 128u32 { ret (Decode { scalar: 0u32, width: 0u8 }, Invalid) }
        scalar = (scalar << 6u32) | (b & 63u32)
        i += 1usize
    }
    // Overlong three- and four-byte forms, surrogates, and anything past the last plane.
    if need == 2usize && (scalar < 2048u32 || (scalar >= 55296u32 && scalar <= 57343u32)) {
        ret (Decode { scalar: 0u32, width: 0u8 }, Invalid)
    }
    if need == 3usize && (scalar < 65536u32 || scalar > 1114111u32) {
        ret (Decode { scalar: 0u32, width: 0u8 }, Invalid)
    }
    ret (Decode { scalar: scalar, width: u8(need + 1usize) }, ok)
}

// Writes the scalar at the start of `dst` and answers the width. A surrogate or a value
// past U+10FFFF is not a scalar and is refused rather than encoded into something no
// decoder accepts.
fn encode(scalar: u32, dst: []u8) -> (u8, err) {
    if scalar > 1114111u32 || (scalar >= 55296u32 && scalar <= 57343u32) { ret (0u8, Invalid) }
    if scalar < 128u32 {
        if dst.len < 1usize { ret (0u8, TooSmall) }
        dst[0usize] = u8(scalar)
        ret (1u8, ok)
    }
    if scalar < 2048u32 {
        if dst.len < 2usize { ret (0u8, TooSmall) }
        dst[0usize] = u8(192u32 | (scalar >> 6u32))
        dst[1usize] = u8(128u32 | (scalar & 63u32))
        ret (2u8, ok)
    }
    if scalar < 65536u32 {
        if dst.len < 3usize { ret (0u8, TooSmall) }
        dst[0usize] = u8(224u32 | (scalar >> 12u32))
        dst[1usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
        dst[2usize] = u8(128u32 | (scalar & 63u32))
        ret (3u8, ok)
    }
    if dst.len < 4usize { ret (0u8, TooSmall) }
    dst[0usize] = u8(240u32 | (scalar >> 18u32))
    dst[1usize] = u8(128u32 | ((scalar >> 12u32) & 63u32))
    dst[2usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
    dst[3usize] = u8(128u32 | (scalar & 63u32))
    ret (4u8, ok)
}

fn validate(s: str) -> bool {
    var off = 0usize
    while off < s.len {
        let (d, d_error) = decode(s, off)
        if d_error != ok { ret false }
        off = off + usize(d.width)
    }
    ret true
}

// How many scalars the string holds; `Invalid` at the first malformed sequence.
fn count(s: str) -> (usize, err) {
    var off = 0usize
    var n = 0usize
    while off < s.len {
        let (d, d_error) = decode(s, off)
        if d_error != ok { ret (n, Invalid) }
        off = off + usize(d.width)
        n += 1usize
    }
    ret (n, ok)
}

// The byte offset where the scalar_index-th scalar starts. An index equal to the count
// answers `s.len`, so a slice `s[byte_offset(a)..byte_offset(b)]` works up to the end.
fn byte_offset(s: str, scalar_index: usize) -> (usize, err) {
    var off = 0usize
    var n = 0usize
    while n < scalar_index {
        if off >= s.len { ret (off, Invalid) }
        let (d, d_error) = decode(s, off)
        if d_error != ok { ret (off, Invalid) }
        off = off + usize(d.width)
        n += 1usize
    }
    ret (off, ok)
}

fn iterator(s: str) -> Iterator {
    ret Iterator { data: s, off: 0usize }
}

// The next scalar and whether there was one. A malformed byte reads as U+FFFD and
// advances by one, so the iteration always reaches the end.
fn iterator_next(it: *Iterator) -> (u32, bool) {
    if it.off >= it.data.len { ret (0u32, false) }
    let (d, d_error) = decode(it.data, it.off)
    if d_error != ok {
        it.off = it.off + 1usize
        ret (65533u32, true)
    }
    it.off = it.off + usize(d.width)
    ret (d.scalar, true)
}

// The strict reading: a malformed sequence answers `Invalid` and leaves the offset on
// it, so a caller can report where.
fn iterator_next_err(it: *Iterator) -> (u32, bool, err) {
    if it.off >= it.data.len { ret (0u32, false, ok) }
    let (d, d_error) = decode(it.data, it.off)
    if d_error != ok { ret (0u32, false, Invalid) }
    it.off = it.off + usize(d.width)
    ret (d.scalar, true, ok)
}
