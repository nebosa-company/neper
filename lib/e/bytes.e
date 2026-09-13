// Bytes as numbers and numbers as bytes, and three text encodings of a byte run.
//
// The generic half reinterprets a `T` through the one question the checker can answer about it
// -- its size, which folds for a scalar (D144) -- so one `load` serves every integer width and
// both floats: the bytes are gathered into a `u64` in the order the endianness names, and the
// `u64` becomes a `T` by conversion for an integer and by a bit-for-bit pun for a float. The
// bit operations are written over `T` directly, with the width from the same question.
//
// The encodings are RFC 4648's base64 and base32, and base85 in its two common spellings.
// Each is a pair that round-trips exactly and a length function that says how much room the
// pair needs, so a caller allocates once and never guesses.
//
// ponytail: a decoder finds each character by scanning its alphabet, which is 64 comparisons
// per byte at worst. A 256-entry reverse table is the upgrade, and needs a module-scope array
// this file does not yet want.

use e.mem
use e.meta

type Endian = enum u8 { Little, Big }
type Base64Alphabet = enum u8 { Standard, Url }
type Base32Alphabet = enum u8 { Standard, Hex }
type Base85Alphabet = enum u8 { Ascii85, Z85 }

type Reader = struct { data: []const u8, off: usize }
type Writer = struct { data: []u8, off: usize }

error End
error Invalid
error TooLarge

const PAD: u8 = 61u8

fn reader(data: []const u8) -> Reader {
    ret Reader { data: data, off: 0usize }
}

fn writer(data: []u8) -> Writer {
    ret Writer { data: data, off: 0usize }
}

fn remaining_reader(r: *const Reader) -> usize {
    ret r.data.len - r.off
}

fn remaining_writer(w: *const Writer) -> usize {
    ret w.data.len - w.off
}

fn skip(r: *Reader, n: usize) -> err {
    if n > r.data.len - r.off { ret End }
    r.off += n
    ret ok
}

fn read_bytes(r: *Reader, n: usize) -> ([]const u8, err) {
    if n > r.data.len - r.off { ret (zero, End) }
    let taken = r.data[r.off..r.off + n]
    r.off += n
    ret (taken, ok)
}

fn write_bytes(w: *Writer, src: []const u8) -> err {
    if src.len > w.data.len - w.off { ret TooLarge }
    mem.copy[u8](w.data[w.off..w.off + src.len], src)
    w.off += src.len
    ret ok
}

// The bytes at `off` as the bits of a `T`, in the order `endian` names. `T` is an integer or a
// float: a struct or an array has no conversion from a `u64` and is refused where it is asked.
fn load[T: type](src: []const u8, off: usize, endian: Endian) -> (T, err) {
    let size = mem.size_of[T]()
    if off > src.len || size > src.len - off { ret (zero, End) }
    var bits = 0u64
    var at = 0usize
    while at < size {
        var index = at
        if endian == .Big { index = size - 1usize - at }
        bits = bits | (u64(src[off + index]) << u32(at * 8usize))
        at += 1usize
    }
    if meta.kind[T]() == .Float {
        if mem.size_of[T]() == 4usize {
            ret (mem.bitcast[T](u32(bits)), ok)
        }
        ret (mem.bitcast[T](bits), ok)
    } else {
        // The bytes are the two's complement bits of the value, so a signed `T` takes
        // them as they are: a meant truncation, not a checked cast (section 4).
        ret (T.trunc(bits), ok)
    }
}

fn store[T: type](dst: []u8, off: usize, v: T, endian: Endian) -> err {
    let size = mem.size_of[T]()
    if off > dst.len || size > dst.len - off { ret TooLarge }
    var bits = 0u64
    if meta.kind[T]() == .Float {
        if mem.size_of[T]() == 4usize {
            bits = u64(mem.bitcast[u32](v))
        } else {
            bits = mem.bitcast[u64](v)
        }
    } else {
        bits = u64.trunc(v)
    }
    var at = 0usize
    while at < size {
        var index = at
        if endian == .Big { index = size - 1usize - at }
        dst[off + index] = u8((bits >> u32(at * 8usize)) & 255u64)
        at += 1usize
    }
    ret ok
}

fn read[T: type](r: *Reader, endian: Endian) -> (T, err) {
    let (value, load_error) = load[T](r.data, r.off, endian)
    if load_error != ok { ret (zero, load_error) }
    r.off += mem.size_of[T]()
    ret (value, ok)
}

fn write[T: type](w: *Writer, v: T, endian: Endian) -> err {
    let store_error = store[T](w.data, w.off, v, endian)
    if store_error != ok { ret store_error }
    w.off += mem.size_of[T]()
    ret ok
}

fn reverse_in_place(data: []u8) {
    if data.len < 2usize { ret }
    var low = 0usize
    var high = data.len - 1usize
    while low < high {
        let held = data[low]
        data[low] = data[high]
        data[high] = held
        low += 1usize
        high -= 1usize
    }
}

// The bit operations take an unsigned `T`; a signed one is refused by the shifts, which is the
// checker's refusal rather than this module's and comes at the instantiation.
fn rotate_left[T: type](v: T, n: u32) -> T {
    let bits = u32(mem.size_of[T]() * 8usize)
    let k = n % bits
    if k == 0u32 { ret v }
    let high = v << k
    let low = v >> (bits - k)
    ret high | low
}

fn rotate_right[T: type](v: T, n: u32) -> T {
    let bits = u32(mem.size_of[T]() * 8usize)
    let k = n % bits
    if k == 0u32 { ret v }
    let low = v >> k
    let high = v << (bits - k)
    ret high | low
}

fn count_ones[T: type](v: T) -> u32 {
    let one = T(1u64)
    var rest = v
    var count = 0u32
    while rest != T(0u64) {
        rest = rest & (rest - one)
        count += 1u32
    }
    ret count
}

fn leading_zeros[T: type](v: T) -> u32 {
    let bits = u32(mem.size_of[T]() * 8usize)
    let zero_value = T(0u64)
    if v == zero_value { ret bits }
    var probe = T(1u64) << (bits - 1u32)
    var count = 0u32
    while (v & probe) == zero_value {
        probe = probe >> 1u32
        count += 1u32
    }
    ret count
}

fn trailing_zeros[T: type](v: T) -> u32 {
    let bits = u32(mem.size_of[T]() * 8usize)
    let zero_value = T(0u64)
    if v == zero_value { ret bits }
    var probe = T(1u64)
    var count = 0u32
    while (v & probe) == zero_value {
        probe = probe << 1u32
        count += 1u32
    }
    ret count
}

// --- Base64, RFC 4648 sections 4 and 5.

// A module-scope `const` of type `str` does not type check (D134), so each alphabet is a call.
fn base64_alphabet(alphabet: Base64Alphabet) -> str {
    if alphabet == .Url { ret "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" }
    ret "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
}

fn base64_encoded_len(n: usize, padded: bool) -> (usize, err) {
    // Four characters per three bytes; the last group is padded or shortened.
    if n > 18446744073709551615usize / 4usize { ret (0usize, TooLarge) }
    let whole = n / 3usize
    let rest = n % 3usize
    var length = whole * 4usize
    if rest != 0usize {
        if padded {
            length += 4usize
        } else {
            length += rest + 1usize
        }
    }
    ret (length, ok)
}

fn base64_encode(dst: []u8, src: []const u8, alphabet: Base64Alphabet, padded: bool) -> (str, err) {
    let (needed, needed_error) = base64_encoded_len(src.len, padded)
    if needed_error != ok { ret ("", needed_error) }
    if needed > dst.len { ret ("", TooLarge) }
    let table = base64_alphabet(alphabet)
    var at = 0usize
    var out = 0usize
    while at + 3usize <= src.len {
        let group = (u32(src[at]) << 16u32) | (u32(src[at + 1usize]) << 8u32) | u32(src[at + 2usize])
        dst[out] = table[usize((group >> 18u32) & 63u32)]
        dst[out + 1usize] = table[usize((group >> 12u32) & 63u32)]
        dst[out + 2usize] = table[usize((group >> 6u32) & 63u32)]
        dst[out + 3usize] = table[usize(group & 63u32)]
        at += 3usize
        out += 4usize
    }
    let rest = src.len - at
    if rest == 1usize {
        let group = u32(src[at]) << 16u32
        dst[out] = table[usize((group >> 18u32) & 63u32)]
        dst[out + 1usize] = table[usize((group >> 12u32) & 63u32)]
        out += 2usize
        if padded {
            dst[out] = PAD
            dst[out + 1usize] = PAD
            out += 2usize
        }
    }
    if rest == 2usize {
        let group = (u32(src[at]) << 16u32) | (u32(src[at + 1usize]) << 8u32)
        dst[out] = table[usize((group >> 18u32) & 63u32)]
        dst[out + 1usize] = table[usize((group >> 12u32) & 63u32)]
        dst[out + 2usize] = table[usize((group >> 6u32) & 63u32)]
        out += 3usize
        if padded {
            dst[out] = PAD
            out += 1usize
        }
    }
    ret (dst[0usize..out], ok)
}

fn alphabet_index(table: str, byte: u8) -> (u32, bool) {
    var at = 0usize
    while at < table.len {
        if table[at] == byte { ret (u32(at), true) }
        at += 1usize
    }
    ret (0u32, false)
}

// Padded or not, the same decoder: padding is stripped first, and then a length that no
// encoding produces -- one character over a whole group -- is refused.
fn base64_decode(dst: []u8, src: str, alphabet: Base64Alphabet) -> ([]u8, err) {
    let table = base64_alphabet(alphabet)
    var end = src.len
    while end > 0usize && src[end - 1usize] == PAD { end -= 1usize }
    if end % 4usize == 1usize { ret (zero, Invalid) }
    let whole = end / 4usize
    let rest = end % 4usize
    var needed = whole * 3usize
    if rest != 0usize { needed += rest - 1usize }
    if needed > dst.len { ret (zero, TooLarge) }
    var at = 0usize
    var out = 0usize
    while at < end {
        var group = 0u32
        var count = 0usize
        while count < 4usize {
            group = group << 6u32
            if at + count < end {
                let (value, valid) = alphabet_index(table, src[at + count])
                if !valid { ret (zero, Invalid) }
                group = group | value
            }
            count += 1usize
        }
        let have = end - at
        if have >= 2usize {
            dst[out] = u8(group >> 16u32)
            out += 1usize
        }
        if have >= 3usize {
            dst[out] = u8((group >> 8u32) & 255u32)
            out += 1usize
        }
        if have >= 4usize {
            dst[out] = u8(group & 255u32)
            out += 1usize
        }
        at += 4usize
    }
    ret (dst[0usize..out], ok)
}

// --- Base32, RFC 4648 sections 6 and 7.

fn base32_alphabet(alphabet: Base32Alphabet) -> str {
    if alphabet == .Hex { ret "0123456789ABCDEFGHIJKLMNOPQRSTUV" }
    ret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
}

fn base32_encoded_len(n: usize, padded: bool) -> (usize, err) {
    // Eight characters per five bytes.
    if n > 18446744073709551615usize / 8usize { ret (0usize, TooLarge) }
    let whole = n / 5usize
    let rest = n % 5usize
    var length = whole * 8usize
    if rest != 0usize {
        if padded {
            length += 8usize
        } else {
            // 1, 2, 3 and 4 bytes are 2, 4, 5 and 7 characters: the bits, rounded up to fives.
            length += (rest * 8usize + 4usize) / 5usize
        }
    }
    ret (length, ok)
}

fn base32_encode(dst: []u8, src: []const u8, alphabet: Base32Alphabet, padded: bool) -> (str, err) {
    let (needed, needed_error) = base32_encoded_len(src.len, padded)
    if needed_error != ok { ret ("", needed_error) }
    if needed > dst.len { ret ("", TooLarge) }
    let table = base32_alphabet(alphabet)
    var at = 0usize
    var out = 0usize
    while at < src.len {
        // Up to five bytes into forty bits, high byte first, the missing ones zero.
        var group = 0u64
        var count = 0usize
        while count < 5usize {
            group = group << 8u32
            if at + count < src.len { group = group | u64(src[at + count]) }
            count += 1usize
        }
        let have = src.len - at
        var characters = 8usize
        if have < 5usize { characters = (have * 8usize + 4usize) / 5usize }
        var index = 0usize
        while index < characters {
            dst[out] = table[usize((group >> u32(35usize - index * 5usize)) & 31u64)]
            out += 1usize
            index += 1usize
        }
        if padded {
            while index < 8usize {
                dst[out] = PAD
                out += 1usize
                index += 1usize
            }
        }
        at += 5usize
    }
    ret (dst[0usize..out], ok)
}

fn base32_decode(dst: []u8, src: str, alphabet: Base32Alphabet) -> ([]u8, err) {
    let table = base32_alphabet(alphabet)
    var end = src.len
    while end > 0usize && src[end - 1usize] == PAD { end -= 1usize }
    let rest = end % 8usize
    // The lengths an encoding produces for a partial group are 2, 4, 5 and 7.
    if rest == 1usize || rest == 3usize || rest == 6usize { ret (zero, Invalid) }
    let whole = end / 8usize
    var needed = whole * 5usize
    if rest != 0usize { needed += rest * 5usize / 8usize }
    if needed > dst.len { ret (zero, TooLarge) }
    var at = 0usize
    var out = 0usize
    while at < end {
        var group = 0u64
        var count = 0usize
        while count < 8usize {
            group = group << 5u32
            if at + count < end {
                let (value, valid) = alphabet_index(table, src[at + count])
                if !valid { ret (zero, Invalid) }
                group = group | u64(value)
            }
            count += 1usize
        }
        var have = end - at
        if have > 8usize { have = 8usize }
        let bytes = have * 5usize / 8usize
        var index = 0usize
        while index < bytes {
            dst[out] = u8((group >> u32(32usize - index * 8usize)) & 255u64)
            out += 1usize
            index += 1usize
        }
        at += 8usize
    }
    ret (dst[0usize..out], ok)
}

// --- Base85: ASCII85 without its `<~ ~>` frame, and Z85.

fn z85_alphabet() -> str {
    ret "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#"
}

// ASCII85 is the digits offset from `!`; Z85 is a table. Both go through this one pair, which
// is what keeps the two codecs one codec with two spellings.
fn base85_digit(alphabet: Base85Alphabet, value: u32) -> u8 {
    if alphabet == .Z85 { ret z85_alphabet()[usize(value)] }
    ret u8(value) + 33u8
}

fn base85_value(alphabet: Base85Alphabet, byte: u8) -> (u32, bool) {
    if alphabet == .Z85 {
        let (value, valid) = alphabet_index(z85_alphabet(), byte)
        ret (value, valid)
    }
    if byte < 33u8 || byte > 117u8 { ret (0u32, false) }
    ret (u32(byte - 33u8), true)
}

fn base85_encoded_len(n: usize, alphabet: Base85Alphabet) -> (usize, err) {
    if n > 18446744073709551615usize / 5usize { ret (0usize, TooLarge) }
    let whole = n / 4usize
    let rest = n % 4usize
    // Z85 is defined only on whole groups, and says so rather than padding.
    if alphabet == .Z85 && rest != 0usize { ret (0usize, Invalid) }
    var length = whole * 5usize
    if rest != 0usize { length += rest + 1usize }
    ret (length, ok)
}

fn base85_encode(dst: []u8, src: []const u8, alphabet: Base85Alphabet) -> (str, err) {
    let (needed, needed_error) = base85_encoded_len(src.len, alphabet)
    if needed_error != ok { ret ("", needed_error) }
    if needed > dst.len { ret ("", TooLarge) }
    var at = 0usize
    var out = 0usize
    while at < src.len {
        var group = 0u32
        var count = 0usize
        while count < 4usize {
            group = group << 8u32
            if at + count < src.len { group = group | u32(src[at + count]) }
            count += 1usize
        }
        var have = src.len - at
        if have > 4usize { have = 4usize }
        // Five digits, most significant first, of which a partial group keeps one more than
        // it has bytes.
        var digits: [5]u8 = zero
        var index = 5usize
        while index > 0usize {
            index -= 1usize
            digits[index] = base85_digit(alphabet, group % 85u32)
            group = group / 85u32
        }
        var emit = 0usize
        while emit < have + 1usize {
            dst[out] = digits[emit]
            out += 1usize
            emit += 1usize
        }
        at += 4usize
    }
    ret (dst[0usize..out], ok)
}

fn base85_decode(dst: []u8, src: str, alphabet: Base85Alphabet) -> ([]u8, err) {
    // ASCII85's `z` is a whole group in one character, so it is counted apart from the rest
    // before the rest is measured in fives.
    var shorthand = 0usize
    if alphabet == .Ascii85 {
        var scan = 0usize
        while scan < src.len {
            if src[scan] == 122u8 { shorthand += 1usize }
            scan += 1usize
        }
    }
    let spelled = src.len - shorthand
    let rest = spelled % 5usize
    // A partial group of ASCII85 has two to five characters; one is nothing. Z85 has none.
    if rest == 1usize { ret (zero, Invalid) }
    if alphabet == .Z85 && rest != 0usize { ret (zero, Invalid) }
    let whole = spelled / 5usize
    var needed = whole * 4usize + shorthand * 4usize
    if rest != 0usize { needed += rest - 1usize }
    if needed > dst.len { ret (zero, TooLarge) }
    var at = 0usize
    var out = 0usize
    while at < src.len {
        // ASCII85's `z` is a whole group of zeros in one character.
        if alphabet == .Ascii85 && src[at] == 122u8 {
            var fill = 0usize
            while fill < 4usize {
                dst[out] = 0u8
                out += 1usize
                fill += 1usize
            }
            at += 1usize
            continue
        }
        var have = src.len - at
        if have > 5usize { have = 5usize }
        // A partial group is completed with the highest digit, which is what makes the bytes it
        // does carry come out unchanged.
        var group = 0u64
        var count = 0usize
        while count < 5usize {
            var digit = 84u32
            if count < have {
                let (value, valid) = base85_value(alphabet, src[at + count])
                if !valid { ret (zero, Invalid) }
                digit = value
            }
            group = group * 85u64 + u64(digit)
            count += 1usize
        }
        if group > 4294967295u64 { ret (zero, Invalid) }
        var index = 0usize
        while index < have - 1usize {
            dst[out] = u8((group >> u32(24usize - index * 8usize)) & 255u64)
            out += 1usize
            index += 1usize
        }
        at += 5usize
    }
    ret (dst[0usize..out], ok)
}
