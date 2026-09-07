// Decimal float literals to IEEE-754 bits, in integer arithmetic only.
//
// The compiler cannot read a float literal with floats: it is built by a compiler
// that has none until this lands, and reading a decimal through the arithmetic being
// defined would be circular in any case. So a literal is held as an
// arbitrary-precision decimal -- `0.d0 d1 ... * 10^exponent` -- and halved and
// doubled one bit at a time until the binary exponent falls out and the mantissa can
// be read off the front. It is slow and exactly correctly rounded, which is the trade
// a conversion that happens once per literal at compile time wants.

error Malformed
error OutOfRange

// 768 digits is the longest decimal that can still change an `f64`'s rounding. Past
// it every further digit is covered by `truncated`, which is the sticky bit.
type Decimal = struct {
    digits: [768]u8,
    count: usize,
    exponent: i64,
    truncated: bool,
}

fn push_digit(d: *Decimal, value: u8) {
    if d.count < d.digits.len {
        d.digits[d.count] = value
        d.count += 1usize
    } else {
        if value != 0u8 { d.truncated = true }
    }
}

// Trailing zeros are not significant, and a decimal with no digits left is zero
// whatever its exponent says.
fn trim(d: *Decimal) {
    while d.count > 0usize && d.digits[d.count - 1usize] == 0u8 { d.count = d.count - 1usize }
    if d.count == 0usize {
        d.exponent = 0i64
        d.truncated = false
    }
}

// Multiply by two. A carry out of the leading digit adds one at the front, which
// raises the exponent; at capacity the digit pushed off the end becomes sticky.
fn double(d: *Decimal) {
    if d.count == 0usize { ret }
    var carry = 0u8
    var at = d.count
    while at > 0usize {
        at = at - 1usize
        let value = d.digits[at] * 2u8 + carry
        d.digits[at] = value % 10u8
        carry = value / 10u8
    }
    if carry != 0u8 {
        if d.count == d.digits.len {
            if d.digits[d.count - 1usize] != 0u8 { d.truncated = true }
        } else {
            d.count += 1usize
        }
        var back = d.count
        while back > 1usize {
            back = back - 1usize
            d.digits[back] = d.digits[back - 1usize]
        }
        d.digits[0usize] = carry
        d.exponent += 1i64
    }
    trim(d)
}

// Halve. The division can leave one leading zero, which belongs to the exponent
// rather than to the digits, and can produce one further digit at the end.
fn halve(d: *Decimal) {
    if d.count == 0usize { ret }
    var remainder = 0u8
    var at = 0usize
    while at < d.count {
        let value = remainder * 10u8 + d.digits[at]
        d.digits[at] = value / 2u8
        remainder = value % 2u8
        at += 1usize
    }
    if remainder != 0u8 { push_digit(d, 5u8) }
    if d.digits[0usize] == 0u8 {
        var back = 0usize
        while back + 1usize < d.count {
            d.digits[back] = d.digits[back + 1usize]
            back += 1usize
        }
        d.count = d.count - 1usize
        d.exponent = d.exponent - 1i64
    }
    trim(d)
}

// `0.digits * 10^exponent` with a leading digit of at least one is in `[0.1, 1)`, so
// the whole comparison is on the exponent alone.
fn at_least_one(d: *Decimal) -> bool {
    if d.count == 0usize { ret false }
    ret d.exponent >= 1i64
}

fn below_half(d: *Decimal) -> bool {
    if d.count == 0usize { ret true }
    if d.exponent < 0i64 { ret true }
    if d.exponent > 0i64 { ret false }
    ret d.digits[0usize] < 5u8
}

// The literal's grammar is `digits [. digits] [(e|E) [+|-] digits] [suffix]`, with
// `_` allowed between digits. There is no sign: `-1.5` is unary minus applied to a
// literal, so every bit pattern this returns has a clear sign bit.
fn parse(spelling: str, d: *Decimal) -> err {
    var at = 0usize
    var in_fraction = false
    var integer_length = 0usize
    var leading_zeros = 0usize
    var started = false
    while at < spelling.len {
        let byte = spelling[at]
        if byte == 95u8 {
            at += 1usize
            continue
        }
        if byte == 46u8 && !in_fraction {
            in_fraction = true
            at += 1usize
            continue
        }
        if byte < 48u8 || byte > 57u8 { break }
        if !in_fraction { integer_length += 1usize }
        let digit = byte - 48u8
        if !started && digit == 0u8 {
            leading_zeros += 1usize
        } else {
            started = true
            push_digit(d, digit)
        }
        at += 1usize
    }
    if at == 0usize { ret Malformed }
    // `I.F` is `0.(I F) * 10^len(I)`, and every leading zero dropped from `I F` takes
    // one off that exponent.
    d.exponent = i64(integer_length) - i64(leading_zeros)
    if at < spelling.len && (spelling[at] == 101u8 || spelling[at] == 69u8) {
        at += 1usize
        var negative = false
        if at < spelling.len && (spelling[at] == 43u8 || spelling[at] == 45u8) {
            negative = spelling[at] == 45u8
            at += 1usize
        }
        var magnitude = 0i64
        var any = false
        while at < spelling.len {
            let byte = spelling[at]
            if byte == 95u8 {
                at += 1usize
                continue
            }
            if byte < 48u8 || byte > 57u8 { break }
            any = true
            // Anything past six digits is out of range in either direction, and the
            // clamp keeps the normalization loop below finite.
            if magnitude < 1000000i64 { magnitude = magnitude * 10i64 + i64(byte - 48u8) }
            at += 1usize
        }
        if !any { ret Malformed }
        if negative {
            d.exponent = d.exponent - magnitude
        } else {
            d.exponent += magnitude
        }
    }
    trim(d)
    ret ok
}

// Returns the bit pattern of the literal in `width`-bit IEEE-754 form. `width` is 32
// or 64; f16 and bf16 are in the type system but not here.
fn literal_bits(spelling: str, width: usize) -> (usize, err) {
    if width != 32usize && width != 64usize { ret (0usize, Malformed) }
    var mantissa_bits = 24i64
    var bias = 127i64
    var max_biased = 254i64
    if width == 64usize {
        mantissa_bits = 53i64
        bias = 1023i64
        max_biased = 2046i64
    }
    var d: Decimal = zero
    let parse_error = parse(spelling, &d)
    if parse_error != ok { ret (0usize, parse_error) }
    if d.count == 0usize { ret (0usize, ok) }
    // Bounds that only keep the loops below finite. Anything outside them is out of
    // range for both widths by a wide margin; anything inside is decided exactly.
    if d.exponent > 400i64 || d.exponent < -450i64 { ret (0usize, OutOfRange) }
    var binary_exponent = 0i64
    while at_least_one(&d) {
        halve(&d)
        binary_exponent += 1i64
    }
    while below_half(&d) {
        double(&d)
        binary_exponent = binary_exponent - 1i64
    }
    // The value is now `m * 2^binary_exponent` with `m` in `[0.5, 1)`, so a normal
    // number's biased exponent is fixed and only the mantissa is left to read.
    var biased = binary_exponent - 1i64 + bias
    var bits = mantissa_bits
    if biased < 1i64 {
        // Subnormal: the exponent field is pinned at zero and the mantissa loses one
        // bit for every step below the smallest normal.
        bits = mantissa_bits + biased - 1i64
        biased = 0i64
        // `bits` is the value's exponent in units of the smallest subnormal, so a
        // negative one means less than half of that: the result is a zero the
        // literal did not write.
        if bits < 0i64 { ret (0usize, OutOfRange) }
    }
    var shifted = 0i64
    while shifted < bits {
        double(&d)
        shifted += 1i64
    }
    var mantissa = 0u64
    var taken = 0i64
    while taken < d.exponent {
        var digit = 0u8
        if usize(taken) < d.count { digit = d.digits[usize(taken)] }
        mantissa = mantissa * 10u64 + u64(digit)
        taken += 1i64
    }
    // Round to nearest, ties to even, on the digits left after the integer part.
    var round_up = false
    // At `bits` of zero the whole value is the fraction, so the comparison starts at
    // an exponent of zero rather than one.
    if d.exponent >= 0i64 && usize(d.exponent) < d.count {
        let first = d.digits[usize(d.exponent)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = d.truncated
            var scan = usize(d.exponent) + 1usize
            while scan < d.count {
                if d.digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                round_up = mantissa % 2u64 == 1u64
            }
        }
    }
    if round_up { mantissa += 1u64 }
    let implicit = 1u64 << u64(mantissa_bits - 1i64)
    if biased == 0i64 {
        // The carry out of a subnormal's mantissa is exactly the smallest normal.
        if mantissa >= implicit { biased = 1i64 }
    } else {
        if mantissa >= implicit * 2u64 {
            mantissa = mantissa / 2u64
            biased += 1i64
        }
    }
    if biased > max_biased { ret (0usize, OutOfRange) }
    var fraction = mantissa
    if biased >= 1i64 { fraction = mantissa - implicit }
    if biased == 0i64 && fraction == 0u64 { ret (0usize, OutOfRange) }
    let pattern = (u64(biased) << u64(mantissa_bits - 1i64)) + fraction
    ret (usize(pattern), ok)
}

fn expect(spelling: str, width: usize, want: usize) -> err {
    let (pattern, pattern_error) = literal_bits(spelling, width)
    if pattern_error != ok { ret pattern_error }
    if pattern != want { ret Malformed }
    ret ok
}

fn reject(spelling: str, width: usize) -> err {
    let (_, pattern_error) = literal_bits(spelling, width)
    if pattern_error != OutOfRange { ret Malformed }
    ret ok
}

// The expected patterns are the ones IEEE-754 round-to-nearest-even gives, taken
// from an independent implementation rather than from this one.
fn self_test() -> err {
    try expect("0.0", 64usize, 0usize)
    try expect("1.0", 64usize, 4607182418800017408usize)
    try expect("0.5", 64usize, 4602678819172646912usize)
    try expect("2.0", 64usize, 4611686018427387904usize)
    try expect("1.5", 64usize, 4609434218613702656usize)
    try expect("3.75", 64usize, 4615626668101337088usize)
    try expect("2.5", 64usize, 4612811918334230528usize)
    try expect("3.5", 64usize, 4615063718147915776usize)
    try expect("123.456", 64usize, 4638387860618067575usize)
    try expect("0.1", 64usize, 4591870180066957722usize)
    try expect("0.000001", 64usize, 4517329193108106637usize)
    try expect("1e-7", 64usize, 4502148214488346440usize)
    try expect("1e22", 64usize, 4936209963552724370usize)
    try expect("1e23", 64usize, 4950912855330343670usize)
    try expect("9007199254740993.0", 64usize, 4845873199050653696usize)
    try expect("1.7976931348623157e308", 64usize, 9218868437227405311usize)
    try expect("2.2250738585072014e-308", 64usize, 4503599627370496usize)
    try expect("5e-324", 64usize, 1usize)
    try expect("4.9e-324", 64usize, 1usize)
    try expect("1e-323", 64usize, 2usize)
    try expect("1_000.5", 64usize, 4652011706887700480usize)
    try expect("0_.1", 64usize, 4591870180066957722usize)

    try expect("1.0", 32usize, 1065353216usize)
    try expect("0.5", 32usize, 1056964608usize)
    try expect("1.5", 32usize, 1069547520usize)
    try expect("2.5", 32usize, 1075838976usize)
    try expect("3.5", 32usize, 1080033280usize)
    try expect("0.1", 32usize, 1036831949usize)
    try expect("3.4028235e38", 32usize, 2139095039usize)
    try expect("1.1754944e-38", 32usize, 8388608usize)
    try expect("1e-45", 32usize, 1usize)
    try expect("16777217.0", 32usize, 1266679808usize)

    // The longest exact tie an f64 has is 768 significant digits, which is exactly
    // what the digit array holds: a tie always fits, so a decimal that does not fit
    // is never one. The pair below is that worst case and the same value with one
    // more digit, which only the sticky bit tells apart.
    try expect("0.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000222507385850720163012305563795567615250361241457301801308322872404958664760675944619203679411688695321398552054903200090343478188441232557218436756334761702051817599892294139362996674259828589999483014897143355557856769327930601597818316214242506796246078529588519927249357768832073249247992481686923224716596493432925878395010225097395757951057160073834364573849432419299709217920738991976169431413149717326525502008499797367678374315520581880443916381057236779117517775622749741380425338708447819365553307386742083452616251302946202273010905482006765402020154711200202813970014157525912344017736224427371246815175018974555997865323425588621961151633592416795802960447706494647018477736093430045142168360701364747951396213837722826145437693412532098591327667236328125", 64usize, 4503599627370496usize)
    try expect("0.00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002225073858507201630123055637955676152503612414573018013083228724049586647606759446192036794116886953213985520549032000903434781884412325572184367563347617020518175998922941393629966742598285899994830148971433555578567693279306015978183162142425067962460785295885199272493577688320732492479924816869232247165964934329258783950102250973957579510571600738343645738494324192997092179207389919761694314131497173265255020084997973676783743155205818804439163810572367791175177756227497413804253387084478193655533073867420834526162513029462022730109054820067654020201547112002028139700141575259123440177362244273712468151750189745559978653234255886219611516335924167958029604477064946470184777360934300451421683607013647479513962138377228261454376934125320985913276672363281251", 64usize, 4503599627370497usize)

    // Past either end of the range, in both widths.
    try reject("1e309", 64usize)
    try reject("1.8e308", 64usize)
    try reject("1e-324", 64usize)
    try reject("1e400", 64usize)
    try reject("1e-500", 64usize)
    try reject("1e39", 32usize)
    try reject("1e-46", 32usize)
    ret ok
}
