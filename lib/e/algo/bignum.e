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
        magnitude = 0u64 -% u64(v)
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
