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

// --- More bit operations, over an unsigned `T` like the ones above.

// The bytes of `v` in the other order: `u16`, `u32`, `u64` (a `u8` is its own swap).
fn byte_swap[T: type](v: T) -> T {
    let size = mem.size_of[T]()
    let bits = u64.trunc(v)
    var out = 0u64
    var pos = 0usize
    while pos < size {
        out = (out << 8u32) | ((bits >> u32(pos * 8usize)) & 255u64)
        pos += 1usize
    }
    ret T.trunc(out)
}

fn reverse_bits[T: type](v: T) -> T {
    let width = u32(mem.size_of[T]() * 8usize)
    let bits = u64.trunc(v)
    var out = 0u64
    var pos = 0u32
    while pos < width {
        out = (out << 1u32) | ((bits >> pos) & 1u64)
        pos += 1u32
    }
    ret T.trunc(out)
}

// `v` with the bits at positions `i` and `j` exchanged.
fn swap_bits[T: type](v: T, i: u32, j: u32) -> T {
    let one = T(1u64)
    if (((v >> i) ^ (v >> j)) & one) == T(0u64) { ret v }
    ret v ^ ((one << i) | (one << j))
}

// 1 when an odd number of bits is set, else 0.
fn parity[T: type](v: T) -> u32 {
    ret count_ones[T](v) & 1u32
}

// Whether any of the eight bytes of `x` is zero: a byte borrows from its high bit only when it
// was zero, and `~x` keeps the borrow apart from a high bit `x` already had.
fn has_zero_byte(x: u64) -> bool {
    ret ((x -% 72340172838076673u64) & ~x & 9259542123273814144u64) != 0u64
}

fn has_byte(x: u64, b: u8) -> bool {
    ret has_zero_byte(x ^ (u64(b) *% 72340172838076673u64))
}

// Floor of log2; zero has none and is `Invalid`.
fn ilog2[T: type](v: T) -> (u32, err) {
    if v == T(0u64) { ret (0u32, Invalid) }
    let width = u32(mem.size_of[T]() * 8usize)
    ret (width - 1u32 - leading_zeros[T](v), ok)
}

// The smallest power of two that is at least `v` (1 for 0), and false when `T` has none.
fn next_power_of_two[T: type](v: T) -> (T, bool) {
    let one = T(1u64)
    if v <= one { ret (one, true) }
    let shift = leading_zeros[T](v - one)
    if shift == 0u32 { ret (T(0u64), false) }
    let width = u32(mem.size_of[T]() * 8usize)
    ret (one << (width - shift), true)
}

// The low `bits` bits of `x` as a signed number of that width, widened to an `i64`.
fn sign_extend(x: u64, bits: u32) -> i64 {
    if bits == 0u32 { ret 0i64 }
    if bits >= 64u32 { ret i64.trunc(x) }
    let sign = 1u64 << (bits - 1u32)
    let low = x & ((sign << 1u32) - 1u64)
    ret i64.trunc((low ^ sign) -% sign)
}

fn gray_encode[T: type](v: T) -> T {
    ret v ^ (v >> 1u32)
}

fn gray_decode[T: type](g: T) -> T {
    var out = g
    var mask = g >> 1u32
    while mask != T(0u64) {
        out = out ^ mask
        mask = mask >> 1u32
    }
    ret out
}

// --- Hex: two digits per byte, either case out, either case in.

fn hex_alphabet(upper: bool) -> str {
    if upper { ret "0123456789ABCDEF" }
    ret "0123456789abcdef"
}

fn hex_encode(dst: []u8, src: []const u8, upper: bool) -> (str, err) {
    if src.len > dst.len / 2usize { ret ("", TooLarge) }
    let table = hex_alphabet(upper)
    var pos = 0usize
    while pos < src.len {
        dst[pos * 2usize] = table[usize(src[pos] >> 4u32)]
        dst[pos * 2usize + 1usize] = table[usize(src[pos] & 15u8)]
        pos += 1usize
    }
    ret (dst[0usize..src.len * 2usize], ok)
}

fn hex_digit_value(c: u8) -> (u32, bool) {
    if c >= 48u8 && c <= 57u8 { ret (u32(c - 48u8), true) }
    if c >= 97u8 && c <= 102u8 { ret (u32(c - 87u8), true) }
    if c >= 65u8 && c <= 70u8 { ret (u32(c - 55u8), true) }
    ret (0u32, false)
}

// An odd length or a character that is not a digit is `Invalid`.
fn hex_decode(dst: []u8, src: str) -> ([]u8, err) {
    if src.len % 2usize != 0usize { ret (zero, Invalid) }
    let count = src.len / 2usize
    if count > dst.len { ret (zero, TooLarge) }
    var pos = 0usize
    while pos < count {
        let (high, high_valid) = hex_digit_value(src[pos * 2usize])
        let (low, low_valid) = hex_digit_value(src[pos * 2usize + 1usize])
        if !high_valid || !low_valid { ret (zero, Invalid) }
        dst[pos] = u8((high << 4u32) | low)
        pos += 1usize
    }
    ret (dst[0usize..count], ok)
}

// --- Base58, the Bitcoin alphabet: the bytes as one big number in base 58, and each leading
// zero byte as a leading `1`. `dst` is the big number's scratch, so it needs room for the
// result and says `TooLarge` when the number outgrows it; `src.len * 138 / 100 + 1` always does.

fn base58_alphabet() -> str {
    ret "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
}

// The digits are built least significant first in `dst[..count]`, then reversed and moved up
// behind the `1`s.
fn base58_encode(dst: []u8, src: []const u8) -> (str, err) {
    var zeros = 0usize
    while zeros < src.len && src[zeros] == 0u8 { zeros += 1usize }
    var count = 0usize
    var pos = zeros
    while pos < src.len {
        var carry = u32(src[pos])
        var digit = 0usize
        while digit < count {
            carry += u32(dst[digit]) << 8u32
            dst[digit] = u8(carry % 58u32)
            carry = carry / 58u32
            digit += 1usize
        }
        while carry != 0u32 {
            if count == dst.len { ret ("", TooLarge) }
            dst[count] = u8(carry % 58u32)
            carry = carry / 58u32
            count += 1usize
        }
        pos += 1usize
    }
    if zeros > dst.len - count { ret ("", TooLarge) }
    let table = base58_alphabet()
    var spell = 0usize
    while spell < count {
        dst[spell] = table[usize(dst[spell])]
        spell += 1usize
    }
    reverse_in_place(dst[0usize..count])
    // Moved up from the top so a digit is never written over before it is read.
    var move = count
    while move > 0usize {
        move -= 1usize
        dst[zeros + move] = dst[move]
    }
    var lead = 0usize
    while lead < zeros {
        dst[lead] = 49u8
        lead += 1usize
    }
    ret (dst[0usize..zeros + count], ok)
}

fn base58_decode(dst: []u8, src: str) -> ([]u8, err) {
    let table = base58_alphabet()
    var zeros = 0usize
    while zeros < src.len && src[zeros] == 49u8 { zeros += 1usize }
    var count = 0usize
    var pos = zeros
    while pos < src.len {
        let (value, valid) = alphabet_index(table, src[pos])
        if !valid { ret (zero, Invalid) }
        var carry = value
        var byte = 0usize
        while byte < count {
            carry += u32(dst[byte]) * 58u32
            dst[byte] = u8(carry & 255u32)
            carry = carry >> 8u32
            byte += 1usize
        }
        while carry != 0u32 {
            if count == dst.len { ret (zero, TooLarge) }
            dst[count] = u8(carry & 255u32)
            carry = carry >> 8u32
            count += 1usize
        }
        pos += 1usize
    }
    if zeros > dst.len - count { ret (zero, TooLarge) }
    reverse_in_place(dst[0usize..count])
    var move = count
    while move > 0usize {
        move -= 1usize
        dst[zeros + move] = dst[move]
    }
    var lead = 0usize
    while lead < zeros {
        dst[lead] = 0u8
        lead += 1usize
    }
    ret (dst[0usize..zeros + count], ok)
}

// --- Base64 in chunks: the same codec fed a piece at a time, holding back a partial group
// between calls so a chunk boundary may fall anywhere. Each `update` and `finish` answers how
// many bytes it put in `dst`, and the whole run is byte for byte what the one-shot pair makes.

type Base64Encoder = struct { alphabet: Base64Alphabet, padded: bool, held: [3]u8, count: usize }
type Base64Decoder = struct { alphabet: Base64Alphabet, held: [4]u8, count: usize }

fn base64_encoder(alphabet: Base64Alphabet, padded: bool) -> Base64Encoder {
    ret Base64Encoder { alphabet: alphabet, padded: padded, held: zero, count: 0usize }
}

fn base64_encoder_update(enc: *Base64Encoder, dst: []u8, src: []const u8) -> (usize, err) {
    var pos = 0usize
    var out = 0usize
    // Complete the group held from last time first.
    while enc.count != 0usize && enc.count < 3usize && pos < src.len {
        enc.held[enc.count] = src[pos]
        enc.count += 1usize
        pos += 1usize
    }
    if enc.count == 3usize {
        let (text, text_error) = base64_encode(dst, enc.held[..], enc.alphabet, true)
        if text_error != ok { ret (0usize, text_error) }
        out = text.len
        enc.count = 0usize
    }
    // Then every whole group of the rest in one call, and hold what is left.
    let whole = (src.len - pos) / 3usize * 3usize
    if whole != 0usize {
        let (text, text_error) = base64_encode(dst[out..], src[pos..pos + whole], enc.alphabet, true)
        if text_error != ok { ret (0usize, text_error) }
        out += text.len
        pos += whole
    }
    while pos < src.len {
        enc.held[enc.count] = src[pos]
        enc.count += 1usize
        pos += 1usize
    }
    ret (out, ok)
}

fn base64_encoder_finish(enc: *Base64Encoder, dst: []u8) -> (usize, err) {
    if enc.count == 0usize { ret (0usize, ok) }
    let (text, text_error) = base64_encode(dst, enc.held[..enc.count], enc.alphabet, enc.padded)
    if text_error != ok { ret (0usize, text_error) }
    enc.count = 0usize
    ret (text.len, ok)
}

fn base64_decoder(alphabet: Base64Alphabet) -> Base64Decoder {
    ret Base64Decoder { alphabet: alphabet, held: zero, count: 0usize }
}

fn base64_decoder_update(dec: *Base64Decoder, dst: []u8, src: str) -> (usize, err) {
    var pos = 0usize
    var out = 0usize
    while dec.count != 0usize && dec.count < 4usize && pos < src.len {
        dec.held[dec.count] = src[pos]
        dec.count += 1usize
        pos += 1usize
    }
    if dec.count == 4usize {
        let (data, data_error) = base64_decode(dst, dec.held[..], dec.alphabet)
        if data_error != ok { ret (0usize, data_error) }
        out = data.len
        dec.count = 0usize
    }
    let whole = (src.len - pos) / 4usize * 4usize
    if whole != 0usize {
        let (data, data_error) = base64_decode(dst[out..], src[pos..pos + whole], dec.alphabet)
        if data_error != ok { ret (0usize, data_error) }
        out += data.len
        pos += whole
    }
    while pos < src.len {
        dec.held[dec.count] = src[pos]
        dec.count += 1usize
        pos += 1usize
    }
    ret (out, ok)
}

// What is still held is an unpadded tail, which the one-shot decoder already accepts; a single
// character is `Invalid` there too.
fn base64_decoder_finish(dec: *Base64Decoder, dst: []u8) -> (usize, err) {
    if dec.count == 0usize { ret (0usize, ok) }
    let (data, data_error) = base64_decode(dst, dec.held[..dec.count], dec.alphabet)
    if data_error != ok { ret (0usize, data_error) }
    dec.count = 0usize
    ret (data.len, ok)
}
