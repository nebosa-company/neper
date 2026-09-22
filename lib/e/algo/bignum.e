// Arbitrary-precision integers and rationals over arena-owned limbs: a sign and a
// little-endian magnitude in base 2^32 with no leading zero limbs, so a zero is a
// `Zero` sign and no limbs at all. Every result is a fresh allocation from the arena it
// is given; inputs are never written.
//
// ponytail: multiplication is schoolbook and division is binary long division, one
// bit at a time -- quadratic in limbs times 32, which is fine for the sizes an arena
// program keeps around. Knuth's algorithm D is the upgrade when a profile says so.

use e.mem
use e.str

type Sign = enum u8 { Zero, Positive, Negative }
type Int = struct { sign: Sign, limbs: []u32, arena: *mem.Arena }
type Rat = struct { num: Int, den: Int }
error DivideByZero
error Invalid

fn int_zero(a: *mem.Arena) -> Int {
    var z: Int = zero
    z.sign = .Zero
    z.arena = a
    ret z
}

// A magnitude as its limbs, with leading zeros dropped and the sign settled.
fn make_int(a: *mem.Arena, sign: Sign, limbs: []u32) -> Int {
    var count = limbs.len
    while count > 0usize && limbs[count - 1usize] == 0u32 { count -= 1usize }
    var v: Int = zero
    v.arena = a
    v.limbs = limbs[..count]
    v.sign = sign
    if count == 0usize { v.sign = .Zero }
    ret v
}

fn int_from_i64(a: *mem.Arena, v: i64) -> (Int, err) {
    if v == 0i64 { ret (int_zero(a), ok) }
    let (limbs, limbs_error) = mem.alloc[u32](a, 2usize)
    if limbs_error != ok { ret (zero, limbs_error) }
    var magnitude = 0u64
    var sign: Sign = .Positive
    if v < 0i64 {
        sign = .Negative
        magnitude = 0u64 -% u64.trunc(v)
    } else {
        magnitude = u64(v)
    }
    limbs[0usize] = u32(magnitude & 4294967295u64)
    limbs[1usize] = u32(magnitude >> 32u32)
    ret (make_int(a, sign, limbs[0..]), ok)
}

fn magnitude_cmp(x: []const u32, y: []const u32) -> i32 {
    if x.len != y.len {
        if x.len < y.len { ret -1i32 }
        ret 1i32
    }
    var at = x.len
    while at > 0usize {
        at -= 1usize
        if x[at] != y[at] {
            if x[at] < y[at] { ret -1i32 }
            ret 1i32
        }
    }
    ret 0i32
}

fn int_cmp(a: Int, b: Int) -> i32 {
    if a.sign != b.sign {
        if a.sign == .Negative || (a.sign == .Zero && b.sign == .Positive) { ret -1i32 }
        ret 1i32
    }
    let order = magnitude_cmp(a.limbs, b.limbs)
    if a.sign == .Negative { ret 0i32 - order }
    ret order
}

fn magnitude_add(a: *mem.Arena, x: []const u32, y: []const u32) -> ([]u32, err) {
    var longer = x
    var shorter = y
    if y.len > x.len {
        longer = y
        shorter = x
    }
    let (out, out_error) = mem.alloc[u32](a, longer.len + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var carry = 0u64
    var at = 0usize
    while at < longer.len {
        var total = u64(longer[at]) + carry
        if at < shorter.len { total += u64(shorter[at]) }
        out[at] = u32(total & 4294967295u64)
        carry = total >> 32u32
        at += 1usize
    }
    out[longer.len] = u32(carry)
    ret (out, ok)
}

// `x - y` for `x >= y`.
fn magnitude_sub(a: *mem.Arena, x: []const u32, y: []const u32) -> ([]u32, err) {
    let (out, out_error) = mem.alloc[u32](a, x.len)
    if out_error != ok { ret (zero, out_error) }
    var borrow = 0u64
    var at = 0usize
    while at < x.len {
        var take = borrow
        if at < y.len { take += u64(y[at]) }
        let have = u64(x[at])
        if have >= take {
            out[at] = u32(have - take)
            borrow = 0u64
        } else {
            out[at] = u32(have + 4294967296u64 - take)
            borrow = 1u64
        }
        at += 1usize
    }
    ret (out, ok)
}

// Signed addition from the two magnitudes: same signs add, differing signs subtract
// the smaller from the larger and keep the larger's sign.
fn signed_add(a: *mem.Arena, x: Int, y_sign: Sign, y_limbs: []const u32) -> (Int, err) {
    if x.sign == .Zero {
        let (copied, copy_error) = copy_limbs(a, y_limbs)
        if copy_error != ok { ret (zero, copy_error) }
        ret (make_int(a, y_sign, copied), ok)
    }
    if y_sign == .Zero {
        let (copied, copy_error) = copy_limbs(a, x.limbs)
        if copy_error != ok { ret (zero, copy_error) }
        ret (make_int(a, x.sign, copied), ok)
    }
    if x.sign == y_sign {
        let (sum, sum_error) = magnitude_add(a, x.limbs, y_limbs)
        if sum_error != ok { ret (zero, sum_error) }
        ret (make_int(a, x.sign, sum), ok)
    }
    let order = magnitude_cmp(x.limbs, y_limbs)
    if order == 0i32 { ret (int_zero(a), ok) }
    if order > 0i32 {
        let (difference, difference_error) = magnitude_sub(a, x.limbs, y_limbs)
        if difference_error != ok { ret (zero, difference_error) }
        ret (make_int(a, x.sign, difference), ok)
    }
    let (difference, difference_error) = magnitude_sub(a, y_limbs, x.limbs)
    if difference_error != ok { ret (zero, difference_error) }
    ret (make_int(a, y_sign, difference), ok)
}

fn copy_limbs(a: *mem.Arena, limbs: []const u32) -> ([]u32, err) {
    let (out, out_error) = mem.alloc[u32](a, limbs.len)
    if out_error != ok { ret (zero, out_error) }
    var at = 0usize
    while at < limbs.len {
        out[at] = limbs[at]
        at += 1usize
    }
    ret (out, ok)
}

fn negate_sign(sign: Sign) -> Sign {
    if sign == .Positive { ret .Negative }
    if sign == .Negative { ret .Positive }
    ret .Zero
}

fn int_add(a: *mem.Arena, x: Int, y: Int) -> (Int, err) {
    let (sum, sum_error) = signed_add(a, x, y.sign, y.limbs)
    ret (sum, sum_error)
}

fn int_sub(a: *mem.Arena, x: Int, y: Int) -> (Int, err) {
    let (difference, difference_error) = signed_add(a, x, negate_sign(y.sign), y.limbs)
    ret (difference, difference_error)
}

fn int_mul(a: *mem.Arena, x: Int, y: Int) -> (Int, err) {
    if x.sign == .Zero || y.sign == .Zero { ret (int_zero(a), ok) }
    let (out, out_error) = mem.alloc[u32](a, x.limbs.len + y.limbs.len)
    if out_error != ok { ret (zero, out_error) }
    var at = 0usize
    while at < out.len {
        out[at] = 0u32
        at += 1usize
    }
    var i = 0usize
    while i < x.limbs.len {
        var carry = 0u64
        var j = 0usize
        while j < y.limbs.len {
            let total = u64(x.limbs[i]) * u64(y.limbs[j]) + u64(out[i + j]) + carry
            out[i + j] = u32(total & 4294967295u64)
            carry = total >> 32u32
            j += 1usize
        }
        out[i + y.limbs.len] = u32(carry)
        i += 1usize
    }
    var sign: Sign = .Positive
    if x.sign != y.sign { sign = .Negative }
    ret (make_int(a, sign, out), ok)
}

fn bit_of(limbs: []const u32, index: usize) -> bool {
    let bit = (limbs[index / 32usize] >> u32(index % 32usize)) & 1u32
    ret bit != 0u32
}

// Binary long division of the magnitudes: the remainder is built a bit at a time from
// the top of `x`, and whenever it reaches `y` it is reduced and the quotient gets a bit.
fn magnitude_divmod(a: *mem.Arena, x: []const u32, y: []const u32) -> ([]u32, []u32, err) {
    let (quotient, quotient_error) = mem.alloc[u32](a, x.len)
    if quotient_error != ok { ret (zero, zero, quotient_error) }
    let (remainder, remainder_error) = mem.alloc[u32](a, y.len + 1usize)
    if remainder_error != ok { ret (zero, zero, remainder_error) }
    var at = 0usize
    while at < quotient.len {
        quotient[at] = 0u32
        at += 1usize
    }
    at = 0usize
    while at < remainder.len {
        remainder[at] = 0u32
        at += 1usize
    }
    var bit = x.len * 32usize
    while bit > 0usize {
        bit -= 1usize
        // remainder = remainder << 1 | bit
        var carry = 0u32
        if bit_of(x, bit) { carry = 1u32 }
        at = 0usize
        while at < remainder.len {
            let next_carry = remainder[at] >> 31u32
            remainder[at] = (remainder[at] << 1u32) | carry
            carry = next_carry
            at += 1usize
        }
        if magnitude_cmp(trimmed(remainder), y) >= 0i32 {
            var borrow = 0u64
            at = 0usize
            while at < remainder.len {
                var take = borrow
                if at < y.len { take += u64(y[at]) }
                let have = u64(remainder[at])
                if have >= take {
                    remainder[at] = u32(have - take)
                    borrow = 0u64
                } else {
                    remainder[at] = u32(have + 4294967296u64 - take)
                    borrow = 1u64
                }
                at += 1usize
            }
            quotient[bit / 32usize] = quotient[bit / 32usize] | (1u32 << u32(bit % 32usize))
        }
    }
    ret (quotient, remainder, ok)
}

fn trimmed(limbs: []u32) -> []const u32 {
    var count = limbs.len
    while count > 0usize && limbs[count - 1usize] == 0u32 { count -= 1usize }
    ret limbs[..count]
}

// Truncating division: the quotient rounds toward zero and the remainder has the
// dividend's sign, as `/` and `%` do on the scalars.
fn int_divmod(a: *mem.Arena, x: Int, y: Int) -> (Int, Int, err) {
    if y.sign == .Zero { ret (zero, zero, DivideByZero) }
    if x.sign == .Zero { ret (int_zero(a), int_zero(a), ok) }
    let (quotient, remainder, divide_error) = magnitude_divmod(a, x.limbs, y.limbs)
    if divide_error != ok { ret (zero, zero, divide_error) }
    var quotient_sign: Sign = .Positive
    if x.sign != y.sign { quotient_sign = .Negative }
    ret (make_int(a, quotient_sign, quotient), make_int(a, x.sign, remainder), ok)
}

fn int_gcd(a: *mem.Arena, x: Int, y: Int) -> (Int, err) {
    let (p_limbs, p_error) = copy_limbs(a, x.limbs)
    if p_error != ok { ret (zero, p_error) }
    let (q_limbs, q_error) = copy_limbs(a, y.limbs)
    if q_error != ok { ret (zero, q_error) }
    var p = make_int(a, .Positive, p_limbs)
    var q = make_int(a, .Positive, q_limbs)
    while q.sign != .Zero {
        let (_, remainder, divide_error) = int_divmod(a, p, q)
        if divide_error != ok { ret (zero, divide_error) }
        p = q
        q = remainder
    }
    ret (p, ok)
}

// `v * small + add`, in place over a magnitude with room for one more limb.
fn scale_add(limbs: []u32, count: usize, small: u32, add: u32) -> usize {
    var carry = u64(add)
    var at = 0usize
    while at < count {
        let total = u64(limbs[at]) * u64(small) + carry
        limbs[at] = u32(total & 4294967295u64)
        carry = total >> 32u32
        at += 1usize
    }
    if carry != 0u64 {
        limbs[count] = u32(carry)
        ret count + 1usize
    }
    ret count
}

fn digit_value(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c - 48u8) }
    if c >= 97u8 && c <= 122u8 { ret u32(c - 97u8) + 10u32 }
    if c >= 65u8 && c <= 90u8 { ret u32(c - 65u8) + 10u32 }
    ret 99u32
}

fn int_parse(a: *mem.Arena, s: str, radix: u8) -> (Int, err) {
    if radix < 2u8 || radix > 36u8 || s.len == 0usize { ret (zero, Invalid) }
    var at = 0usize
    var sign: Sign = .Positive
    if s[0] == 45u8 {
        sign = .Negative
        at = 1usize
    } else {
        if s[0] == 43u8 { at = 1usize }
    }
    if at >= s.len { ret (zero, Invalid) }
    // Each digit is at most 6 bits, so digits / 5 + 1 limbs always hold the value.
    let (limbs, limbs_error) = mem.alloc[u32](a, (s.len - at) / 5usize + 2usize)
    if limbs_error != ok { ret (zero, limbs_error) }
    var count = 0usize
    while at < s.len {
        let digit = digit_value(s[at])
        if digit >= u32(radix) { ret (zero, Invalid) }
        count = scale_add(limbs, count, u32(radix), digit)
        at += 1usize
    }
    ret (make_int(a, sign, limbs[..count]), ok)
}

// The formatter allocates nothing: a `str.Builder` holds the top of its arena, so a
// scratch taken from the same arena would sit on top of the builder and break it.
// ponytail: the scratch is on the stack and caps the value at 1024 limbs (32768 bits,
// ~9864 decimal digits); a larger value is `Invalid` here. A streaming formatter that
// divides in place is the upgrade.
const FORMAT_LIMBS: usize = 1024usize

fn int_format(v: Int, b: *str.Builder, radix: u8) -> err {
    if radix < 2u8 || radix > 36u8 { ret Invalid }
    if v.sign == .Zero { ret str.push_byte(b, 48u8) }
    if v.limbs.len > FORMAT_LIMBS { ret Invalid }
    if v.sign == .Negative { try str.push_byte(b, 45u8) }
    var scratch: [1024]u32 = zero
    var digits: [32769]u8 = zero
    var at = 0usize
    while at < v.limbs.len {
        scratch[at] = v.limbs[at]
        at += 1usize
    }
    var count = v.limbs.len
    var produced = 0usize
    while count > 0usize {
        var remainder = 0u64
        at = count
        while at > 0usize {
            at -= 1usize
            let current = (remainder << 32u32) | u64(scratch[at])
            scratch[at] = u32(current / u64(radix))
            remainder = current % u64(radix)
        }
        var digit = u8(remainder)
        if digit < 10u8 { digit += 48u8 } else { digit += 87u8 }
        digits[produced] = digit
        produced += 1usize
        while count > 0usize && scratch[count - 1usize] == 0u32 { count -= 1usize }
    }
    while produced > 0usize {
        produced -= 1usize
        try str.push_byte(b, digits[produced])
    }
    ret ok
}

// A rational in lowest terms with a positive denominator; `0` is `0/1`.
fn rat_make(a: *mem.Arena, num: Int, den: Int) -> (Rat, err) {
    if den.sign == .Zero { ret (zero, DivideByZero) }
    var r: Rat = zero
    if num.sign == .Zero {
        let (one, one_error) = int_from_i64(a, 1i64)
        if one_error != ok { ret (zero, one_error) }
        r.num = int_zero(a)
        r.den = one
        ret (r, ok)
    }
    let (common, gcd_error) = int_gcd(a, num, den)
    if gcd_error != ok { ret (zero, gcd_error) }
    let (reduced_num, _, num_error) = int_divmod(a, num, common)
    if num_error != ok { ret (zero, num_error) }
    let (reduced_den, _, den_error) = int_divmod(a, den, common)
    if den_error != ok { ret (zero, den_error) }
    r.num = reduced_num
    r.den = reduced_den
    if r.den.sign == .Negative {
        r.den.sign = .Positive
        r.num.sign = negate_sign(r.num.sign)
    }
    ret (r, ok)
}

fn rat_add(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err) {
    let (left, left_error) = int_mul(a, x.num, y.den)
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = int_mul(a, y.num, x.den)
    if right_error != ok { ret (zero, right_error) }
    let (num, num_error) = int_add(a, left, right)
    if num_error != ok { ret (zero, num_error) }
    let (den, den_error) = int_mul(a, x.den, y.den)
    if den_error != ok { ret (zero, den_error) }
    let (result, make_error) = rat_make(a, num, den)
    ret (result, make_error)
}

fn rat_sub(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err) {
    var negated = y
    negated.num.sign = negate_sign(y.num.sign)
    let (result, add_error) = rat_add(a, x, negated)
    ret (result, add_error)
}

fn rat_mul(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err) {
    let (num, num_error) = int_mul(a, x.num, y.num)
    if num_error != ok { ret (zero, num_error) }
    let (den, den_error) = int_mul(a, x.den, y.den)
    if den_error != ok { ret (zero, den_error) }
    let (result, make_error) = rat_make(a, num, den)
    ret (result, make_error)
}

fn rat_div(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err) {
    if y.num.sign == .Zero { ret (zero, DivideByZero) }
    let (num, num_error) = int_mul(a, x.num, y.den)
    if num_error != ok { ret (zero, num_error) }
    let (den, den_error) = int_mul(a, x.den, y.num)
    if den_error != ok { ret (zero, den_error) }
    let (result, make_error) = rat_make(a, num, den)
    ret (result, make_error)
}

// Cross-multiplied comparison; both denominators are positive, so the order holds.
fn rat_cmp(a: Rat, b: Rat) -> i32 {
    let (left, left_error) = int_mul(a.num.arena, a.num, b.den)
    let (right, right_error) = int_mul(a.num.arena, b.num, a.den)
    if left_error != ok || right_error != ok { ret 0i32 }
    ret int_cmp(left, right)
}

fn rat_format(v: Rat, b: *str.Builder) -> err {
    try int_format(v.num, b, 10u8)
    if v.den.limbs.len == 1usize && v.den.limbs[0] == 1u32 { ret ok }
    try str.push_byte(b, 47u8)
    ret int_format(v.den, b, 10u8)
}

// --- Bytes and modular exponentiation (for e.crypto.sign and e.crypto.kx).

// The number of significant bits: zero for zero.
fn int_bits(v: Int) -> usize {
    if v.sign == .Zero { ret 0usize }
    var top = v.limbs[v.limbs.len - 1usize]
    var bits = 0usize
    while top != 0u32 {
        top = top >> 1u32
        bits += 1usize
    }
    ret (v.limbs.len - 1usize) * 32usize + bits
}

// A non-negative value from big-endian bytes; leading zero bytes are fine.
fn int_from_bytes_be(a: *mem.Arena, bytes: []const u8) -> (Int, err) {
    let (limbs, limbs_error) = mem.alloc[u32](a, bytes.len / 4usize + 1usize)
    if limbs_error != ok { ret (zero, limbs_error) }
    var at = 0usize
    while at < limbs.len {
        limbs[at] = 0u32
        at += 1usize
    }
    at = 0usize
    while at < bytes.len {
        let from_end = bytes.len - 1usize - at
        limbs[from_end / 4usize] = limbs[from_end / 4usize] | (u32(bytes[at]) << u32((from_end % 4usize) * 8usize))
        at += 1usize
    }
    ret (make_int(a, .Positive, limbs), ok)
}

// The magnitude big-endian into all of `out`, zero-padded on the left; `Invalid` when
// the value is negative or does not fit.
fn int_to_bytes_be(v: Int, out: []u8) -> err {
    if v.sign == .Negative { ret Invalid }
    if int_bits(v) > out.len * 8usize { ret Invalid }
    var at = 0usize
    while at < out.len {
        let from_end = out.len - 1usize - at
        var byte = 0u8
        if from_end / 4usize < v.limbs.len {
            byte = u8((v.limbs[from_end / 4usize] >> u32((from_end % 4usize) * 8usize)) & 255u32)
        }
        out[at] = byte
        at += 1usize
    }
    ret ok
}

// -m^-1 mod 2^32 for an odd m, by Newton's iteration from the trivial inverse mod 2.
fn mont_inverse32(m0: u32) -> u32 {
    var inverse = 1u32
    var round = 0usize
    while round < 5usize {
        inverse = inverse *% (2u32 -% m0 *% inverse)
        round += 1usize
    }
    ret 0u32 -% inverse
}

// CIOS Montgomery product: out = x * y * R^-1 mod m with R = 2^(32 k), for x, y < m
// and k = m.len. `t` is scratch of k + 2 limbs; `out` may alias x or y.
fn mont_mul(t: []u32, out: []u32, x: []const u32, y: []const u32, m: []const u32, m_prime: u32) {
    let k = m.len
    var at = 0usize
    while at < k + 2usize {
        t[at] = 0u32
        at += 1usize
    }
    var i = 0usize
    while i < k {
        let xi = u64(x[i])
        var carry = 0u64
        var j = 0usize
        while j < k {
            let sum = u64(t[j]) + xi * u64(y[j]) + carry
            t[j] = u32(sum & 4294967295u64)
            carry = sum >> 32u32
            j += 1usize
        }
        var sum = u64(t[k]) + carry
        t[k] = u32(sum & 4294967295u64)
        t[k + 1usize] = u32(sum >> 32u32)
        let u = u64(t[0] *% m_prime)
        carry = 0u64
        j = 0usize
        while j < k {
            let sum2 = u64(t[j]) + u * u64(m[j]) + carry
            t[j] = u32(sum2 & 4294967295u64)
            carry = sum2 >> 32u32
            j += 1usize
        }
        sum = u64(t[k]) + carry
        t[k] = u32(sum & 4294967295u64)
        t[k + 1usize] = t[k + 1usize] +% u32(sum >> 32u32)
        j = 0usize
        while j < k + 1usize {
            t[j] = t[j + 1usize]
            j += 1usize
        }
        t[k + 1usize] = 0u32
        i += 1usize
    }
    // t < 2m here: one conditional subtraction settles it.
    if t[k] != 0u32 || magnitude_cmp(trimmed(t[..k]), m) >= 0i32 {
        var borrow = 0u64
        at = 0usize
        while at < k {
            let have = u64(t[at])
            let take = u64(m[at]) + borrow
            if have >= take {
                t[at] = u32(have - take)
                borrow = 0u64
            } else {
                t[at] = u32(have + 4294967296u64 - take)
                borrow = 1u64
            }
            at += 1usize
        }
    }
    at = 0usize
    while at < k {
        out[at] = t[at]
        at += 1usize
    }
}

// (value * 2^(32 k)) mod m as exactly k limbs, by the module's division.
fn mont_enter(a: *mem.Arena, value: []const u32, m: []const u32) -> ([]u32, err) {
    let k = m.len
    let (shifted, shifted_error) = mem.alloc[u32](a, value.len + k)
    if shifted_error != ok { ret (zero, shifted_error) }
    var at = 0usize
    while at < shifted.len {
        shifted[at] = 0u32
        if at >= k { shifted[at] = value[at - k] }
        at += 1usize
    }
    let (_, remainder, divide_error) = magnitude_divmod(a, shifted, m)
    if divide_error != ok { ret (zero, divide_error) }
    ret (remainder[..k], ok)
}

// base^exponent mod modulus for a non-negative exponent. An odd modulus runs
// Montgomery multiplication in place over scratch from the arena; an even one falls
// back to multiply-and-divide with the module's operations.
// ponytail: the exponent is scanned bit by bit and no window is used; enough for a
// 2048-bit RSA signature in well under a second.
fn int_mod_pow(a: *mem.Arena, base: Int, exponent: Int, modulus: Int) -> (Int, err) {
    if modulus.sign == .Zero { ret (zero, DivideByZero) }
    if exponent.sign == .Negative { ret (zero, Invalid) }
    let (_, reduced, reduce_error) = int_divmod(a, base, modulus)
    if reduce_error != ok { ret (zero, reduce_error) }
    var residue = reduced
    if residue.sign == .Negative {
        let (fixed, fix_error) = int_add(a, residue, modulus)
        if fix_error != ok { ret (zero, fix_error) }
        residue = fixed
    }
    let m = modulus.limbs
    let k = m.len
    let bits = int_bits(exponent)
    if (m[0] & 1u32) == 0u32 {
        let (one, one_error) = int_from_i64(a, 1i64)
        if one_error != ok { ret (zero, one_error) }
        var acc = one
        var bit = bits
        while bit > 0usize {
            bit -= 1usize
            let (square, square_error) = int_mul(a, acc, acc)
            if square_error != ok { ret (zero, square_error) }
            let (_, square_mod, square_mod_error) = int_divmod(a, square, modulus)
            if square_mod_error != ok { ret (zero, square_mod_error) }
            acc = square_mod
            if bit_of(exponent.limbs, bit) {
                let (product, product_error) = int_mul(a, acc, residue)
                if product_error != ok { ret (zero, product_error) }
                let (_, product_mod, product_mod_error) = int_divmod(a, product, modulus)
                if product_mod_error != ok { ret (zero, product_mod_error) }
                acc = product_mod
            }
        }
        let (_, final_mod, final_error) = int_divmod(a, acc, modulus)
        if final_error != ok { ret (zero, final_error) }
        ret (final_mod, ok)
    }
    let m_prime = mont_inverse32(m[0])
    let (t, t_error) = mem.alloc[u32](a, k + 2usize)
    if t_error != ok { ret (zero, t_error) }
    let (base_mont, base_error) = mont_enter(a, residue.limbs, m)
    if base_error != ok { ret (zero, base_error) }
    var one_limb: [1]u32 = zero
    one_limb[0] = 1u32
    let (acc, acc_error) = mont_enter(a, one_limb[0..], m)
    if acc_error != ok { ret (zero, acc_error) }
    var bit = bits
    while bit > 0usize {
        bit -= 1usize
        mont_mul(t, acc, acc, acc, m, m_prime)
        if bit_of(exponent.limbs, bit) { mont_mul(t, acc, acc, base_mont, m, m_prime) }
    }
    let (plain, plain_error) = mem.alloc[u32](a, k)
    if plain_error != ok { ret (zero, plain_error) }
    var at = 0usize
    while at < k {
        plain[at] = 0u32
        at += 1usize
    }
    plain[0] = 1u32
    mont_mul(t, acc, acc, plain, m, m_prime)
    ret (make_int(a, .Positive, acc), ok)
}

// --- Lenstra elliptic-curve factoring.

error NotFound

// ponytail: the point coordinates are copied to stack buffers of this many limbs
// after every prime power so the arena can be reset; a modulus above 2048 bits is
// `Invalid` here. Arena-resident buffers are the upgrade.
const ECM_LIMBS: usize = 64usize

fn ecm_reduce(a: *mem.Arena, x: Int, n: Int) -> (Int, err) {
    let (_, remainder, divide_error) = int_divmod(a, x, n)
    if divide_error != ok { ret (zero, divide_error) }
    if remainder.sign == .Negative {
        let (lifted, lift_error) = int_add(a, remainder, n)
        ret (lifted, lift_error)
    }
    ret (remainder, ok)
}

fn ecm_mul(a: *mem.Arena, x: Int, y: Int, n: Int) -> (Int, err) {
    let (product, product_error) = int_mul(a, x, y)
    if product_error != ok { ret (zero, product_error) }
    let (reduced, reduce_error) = ecm_reduce(a, product, n)
    ret (reduced, reduce_error)
}

fn ecm_add_mod(a: *mem.Arena, x: Int, y: Int, n: Int) -> (Int, err) {
    let (sum, sum_error) = int_add(a, x, y)
    if sum_error != ok { ret (zero, sum_error) }
    if int_cmp(sum, n) >= 0i32 {
        let (wrapped, wrap_error) = int_sub(a, sum, n)
        ret (wrapped, wrap_error)
    }
    ret (sum, ok)
}

fn ecm_sub_mod(a: *mem.Arena, x: Int, y: Int, n: Int) -> (Int, err) {
    let (difference, difference_error) = int_sub(a, x, y)
    if difference_error != ok { ret (zero, difference_error) }
    if difference.sign == .Negative {
        let (lifted, lift_error) = int_add(a, difference, n)
        ret (lifted, lift_error)
    }
    ret (difference, ok)
}

// x-only doubling on the Montgomery curve with `a24 = (A + 2) / 4`.
fn ecm_double(a: *mem.Arena, x: Int, z: Int, a24: Int, n: Int) -> (Int, Int, err) {
    let (sum, sum_error) = ecm_add_mod(a, x, z, n)
    if sum_error != ok { ret (zero, zero, sum_error) }
    let (difference, difference_error) = ecm_sub_mod(a, x, z, n)
    if difference_error != ok { ret (zero, zero, difference_error) }
    let (s, s_error) = ecm_mul(a, sum, sum, n)
    if s_error != ok { ret (zero, zero, s_error) }
    let (d, d_error) = ecm_mul(a, difference, difference, n)
    if d_error != ok { ret (zero, zero, d_error) }
    let (t, t_error) = ecm_sub_mod(a, s, d, n)
    if t_error != ok { ret (zero, zero, t_error) }
    let (x2, x2_error) = ecm_mul(a, s, d, n)
    if x2_error != ok { ret (zero, zero, x2_error) }
    let (scaled, scaled_error) = ecm_mul(a, a24, t, n)
    if scaled_error != ok { ret (zero, zero, scaled_error) }
    let (inner, inner_error) = ecm_add_mod(a, d, scaled, n)
    if inner_error != ok { ret (zero, zero, inner_error) }
    let (z2, z2_error) = ecm_mul(a, t, inner, n)
    if z2_error != ok { ret (zero, zero, z2_error) }
    ret (x2, z2, ok)
}

// x-only differential addition of `p` and `q` whose difference is `(xd, zd)`.
fn ecm_add(a: *mem.Arena, xp: Int, zp: Int, xq: Int, zq: Int, xd: Int, zd: Int, n: Int) -> (Int, Int, err) {
    let (p_minus, p_minus_error) = ecm_sub_mod(a, xp, zp, n)
    if p_minus_error != ok { ret (zero, zero, p_minus_error) }
    let (q_plus, q_plus_error) = ecm_add_mod(a, xq, zq, n)
    if q_plus_error != ok { ret (zero, zero, q_plus_error) }
    let (u, u_error) = ecm_mul(a, p_minus, q_plus, n)
    if u_error != ok { ret (zero, zero, u_error) }
    let (p_plus, p_plus_error) = ecm_add_mod(a, xp, zp, n)
    if p_plus_error != ok { ret (zero, zero, p_plus_error) }
    let (q_minus, q_minus_error) = ecm_sub_mod(a, xq, zq, n)
    if q_minus_error != ok { ret (zero, zero, q_minus_error) }
    let (v, v_error) = ecm_mul(a, p_plus, q_minus, n)
    if v_error != ok { ret (zero, zero, v_error) }
    let (sum, sum_error) = ecm_add_mod(a, u, v, n)
    if sum_error != ok { ret (zero, zero, sum_error) }
    let (difference, difference_error) = ecm_sub_mod(a, u, v, n)
    if difference_error != ok { ret (zero, zero, difference_error) }
    let (sum_sq, sum_sq_error) = ecm_mul(a, sum, sum, n)
    if sum_sq_error != ok { ret (zero, zero, sum_sq_error) }
    let (difference_sq, difference_sq_error) = ecm_mul(a, difference, difference, n)
    if difference_sq_error != ok { ret (zero, zero, difference_sq_error) }
    let (x_out, x_out_error) = ecm_mul(a, zd, sum_sq, n)
    if x_out_error != ok { ret (zero, zero, x_out_error) }
    let (z_out, z_out_error) = ecm_mul(a, xd, difference_sq, n)
    if z_out_error != ok { ret (zero, zero, z_out_error) }
    ret (x_out, z_out, ok)
}

// `[k]P` by the Montgomery ladder, the difference of the two rungs always `P`.
fn ecm_ladder(a: *mem.Arena, x: Int, z: Int, k: u64, a24: Int, n: Int) -> (Int, Int, err) {
    var bits = 0u32
    var rest = k
    while rest > 0u64 {
        bits += 1u32
        rest = rest >> 1u32
    }
    var x0 = x
    var z0 = z
    let (dx, dz, double_error) = ecm_double(a, x, z, a24, n)
    if double_error != ok { ret (zero, zero, double_error) }
    var x1 = dx
    var z1 = dz
    var i = bits - 1u32
    while i > 0u32 {
        i -= 1u32
        let (sx, sz, add_error) = ecm_add(a, x0, z0, x1, z1, x, z, n)
        if add_error != ok { ret (zero, zero, add_error) }
        if ((k >> i) & 1u64) == 1u64 {
            let (tx, tz, step_error) = ecm_double(a, x1, z1, a24, n)
            if step_error != ok { ret (zero, zero, step_error) }
            x0 = sx
            z0 = sz
            x1 = tx
            z1 = tz
        } else {
            let (tx, tz, step_error) = ecm_double(a, x0, z0, a24, n)
            if step_error != ok { ret (zero, zero, step_error) }
            x1 = sx
            z1 = sz
            x0 = tx
            z0 = tz
        }
    }
    ret (x0, z0, ok)
}

fn ecm_is_prime(p: u64) -> bool {
    if p < 2u64 { ret false }
    var q = 2u64
    while q * q <= p {
        if p % q == 0u64 { ret false }
        q += 1u64
    }
    ret true
}

// A `u64` below 2^31 from the generator, reduced modulo `n`.
fn ecm_random(a: *mem.Arena, state: *u64, n: Int) -> (Int, err) {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    let (value, value_error) = int_from_i64(a, i64(*state >> 33u32))
    if value_error != ok { ret (zero, value_error) }
    let (reduced, reduce_error) = ecm_reduce(a, value, n)
    ret (reduced, reduce_error)
}

// Stage-1 ECM: for each of `curves` Montgomery curves `By^2 = x^3 + Ax^2 + x`
// drawn from `seed` (a random `a24` and starting `x`), the point is multiplied
// by every prime power up to `b1`; a `gcd` of its `Z` with `n` strictly between
// 1 and `n` is a factor. Answers `NotFound` when no curve splits `n`. An even
// `n` answers 2.
fn factor_ecm(a: *mem.Arena, n: Int, b1: u64, curves: usize, seed: u64) -> (Int, err) {
    if n.sign != .Positive || n.limbs.len > ECM_LIMBS || int_bits(n) < 3usize { ret (zero, Invalid) }
    if (n.limbs[0] & 1u32) == 0u32 {
        let (two, two_error) = int_from_i64(a, 2i64)
        ret (two, two_error)
    }
    var bx: [64]u32 = zero
    var bz: [64]u32 = zero
    var state = seed
    var curve = 0usize
    while curve < curves {
        curve += 1usize
        let (a24, a24_error) = ecm_random(a, &state, n)
        if a24_error != ok { ret (zero, a24_error) }
        let (start, start_error) = ecm_random(a, &state, n)
        if start_error != ok { ret (zero, start_error) }
        if int_bits(a24) >= 2usize {
            let (one, one_error) = int_from_i64(a, 1i64)
            if one_error != ok { ret (zero, one_error) }
            var x = start
            var z = one
            var p = 2u64
            while p <= b1 {
                if ecm_is_prime(p) {
                    var k = p
                    while k * p <= b1 { k = k * p }
                    let marker = mem.mark(a)
                    let (nx, nz, ladder_error) = ecm_ladder(a, x, z, k, a24, n)
                    if ladder_error != ok { ret (zero, ladder_error) }
                    let x_len = nx.limbs.len
                    let z_len = nz.limbs.len
                    var i = 0usize
                    while i < x_len {
                        bx[i] = nx.limbs[i]
                        i += 1usize
                    }
                    i = 0usize
                    while i < z_len {
                        bz[i] = nz.limbs[i]
                        i += 1usize
                    }
                    mem.reset(a, marker)
                    x = make_int(a, .Positive, bx[..x_len])
                    z = make_int(a, .Positive, bz[..z_len])
                }
                p += 1u64
            }
            let (g, gcd_error) = int_gcd(a, z, n)
            if gcd_error != ok { ret (zero, gcd_error) }
            if int_bits(g) > 1usize && int_cmp(g, n) < 0i32 {
                let (copied, copy_error) = copy_limbs(a, g.limbs)
                if copy_error != ok { ret (zero, copy_error) }
                ret (make_int(a, .Positive, copied), ok)
            }
        }
    }
    ret (zero, NotFound)
}
