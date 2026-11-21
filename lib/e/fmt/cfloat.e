// The digits C's `%.Ne` prints for a positive finite double: the exact decimal expansion rounded at
// the N+1st significant digit, a tie going away from zero as the Windows C runtime does. R's yaml
// package and libxml2's XPath number-to-string both print through it. The expansion comes from
// push_f64_fixed down to 1e-80, and below that from mant * 5^k in base-1e9 limbs.
use e.mem
use e.str

error NotPositive

// The exact digits of a positive double below 2^52, as mant * 5^k with the value's point k places
// from the right: the digit count and the decimal exponent of the first digit.
fn small_digits(ax: f64, out: []u8) -> (usize, i64) {
    let bits = mem.bitcast[u64](ax)
    let field = (bits >> 52u64) & 2047u64
    var mant = bits & 4503599627370495u64
    var e2 = 0i64 - 1074i64
    if field != 0u64 {
        mant = mant | 4503599627370496u64
        e2 = i64(field) - 1075i64
    }
    var k = 0i64 - e2
    var limbs: [112]u64 = zero
    limbs[0] = mant % 1000000000u64
    limbs[1] = mant / 1000000000u64
    var used = 2usize
    while k > 0i64 {
        var carry = 0u64
        var j = 0usize
        while j < used {
            let v = limbs[j] * 5u64 + carry
            limbs[j] = v % 1000000000u64
            carry = v / 1000000000u64
            j += 1usize
        }
        if carry > 0u64 {
            limbs[used] = carry
            used += 1usize
        }
        k -= 1i64
    }
    while used > 1usize && limbs[used - 1usize] == 0u64 { used -= 1usize }
    var count = 0usize
    var top = limbs[used - 1usize]
    var lead: [10]u8 = zero
    var lead_len = 0usize
    while top > 0u64 {
        lead[lead_len] = u8(top % 10u64)
        top = top / 10u64
        lead_len += 1usize
    }
    while lead_len > 0usize {
        lead_len -= 1usize
        out[count] = lead[lead_len]
        count += 1usize
    }
    var j = used - 1usize
    while j > 0usize {
        j -= 1usize
        var piece = limbs[j]
        var d = 9usize
        while d > 0usize {
            d -= 1usize
            out[count + d] = u8(piece % 10u64)
            piece = piece / 10u64
        }
        count += 9usize
    }
    ret (count, i64(count) - (0i64 - e2) - 1i64)
}

// Fills `kept[0..frac+1]` with the rounded significant digits of `ax` (frac at most 30) and gives the
// decimal exponent of the first.
fn exp_digits(ax: f64, frac: usize, kept: []u8) -> (i64, err) {
    if !(ax > 0.0f64) { ret (0i64, NotPositive) }
    var digits: [1024]u8 = zero
    var count = 0usize
    var first = 0usize
    var exponent = 0i64
    if ax < 1.0e-80f64 {
        let (small_count, small_exponent) = small_digits(ax, digits[..])
        count = small_count
        exponent = small_exponent
    } else {
        var scratch: [1024]u8 = zero
        var arena = mem.arena_from(scratch[0..])
        let (b0, builder_error) = str.builder(&arena, 600usize)
        if builder_error != ok { ret (0i64, builder_error) }
        var b = b0
        var precision = 99u8
        if ax >= 1.0e15f64 { precision = 0u8 }
        let push_error = str.push_f64_fixed(&b, ax, precision)
        if push_error != ok { ret (0i64, push_error) }
        let t = str.done(&b)
        var point = 0usize
        var seen_point = false
        var i = 0usize
        while i < t.len {
            if t[i] == 46u8 {
                point = count
                seen_point = true
            } else {
                digits[count] = t[i] - 48u8
                count += 1usize
            }
            i += 1usize
        }
        if !seen_point { point = count }
        while first < count && digits[first] == 0u8 { first += 1usize }
        exponent = i64(point) - i64(first) - 1i64
    }
    let keep = frac + 1usize
    var k = 0usize
    while k < keep {
        kept[k] = 0u8
        if first + k < count { kept[k] = digits[first + k] }
        k += 1usize
    }
    var next = 0u8
    if first + keep < count { next = digits[first + keep] }
    if next >= 5u8 {
        var j = keep
        var carry = true
        while carry && j > 0usize {
            j -= 1usize
            kept[j] += 1u8
            if kept[j] == 10u8 {
                kept[j] = 0u8
            } else {
                carry = false
            }
        }
        if carry {
            kept[0] = 1u8
            exponent += 1i64
        }
    }
    ret (exponent, ok)
}
