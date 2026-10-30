// Structured control flow and operand folding on wasm32-wasi (C183): nested loops with break and
// continue, if/else ladders with early returns, loops with several exits that meet afterwards,
// short-circuit conditions, calls whose results are read once, twice or by one of two extracts,
// and expression trees whose temporaries are read once. Each group prints a checksum and the
// program exits 0 only if every one is the value the same code gives on x64.
use e.mem
use e.os

const NESTED: i64 = 88160i64
const LADDER: i64 = 13880i64
const MATCH: i64 = 30i64
const COLLATZ: i64 = 1438i64
const SHORT: i64 = 836520502i64
const PAIRS: i64 = 3982i64
const EXPR: i64 = -1046785i64
const NARROW: i64 = 6578i64
const MANY: i64 = 1460947i64
const RANGE: i64 = 30637i64

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn say_number(label: str, value: i64) {
    var digits: [24]u8 = zero
    var at = 24usize
    var rest = value
    var negative = false
    if rest < 0i64 {
        negative = true
        rest = 0i64 - rest
    }
    if rest == 0i64 {
        at = at - 1usize
        digits[at] = 48u8
    }
    while rest != 0i64 {
        at = at - 1usize
        digits[at] = u8(48i64 + rest % 10i64)
        rest = rest / 10i64
    }
    if negative {
        at = at - 1usize
        digits[at] = 45u8
    }
    say(label)
    say(" ")
    let (shown, shown_error) = os.write(os.stdout(), digits[at..24usize])
    say("\n")
}

fn nested(limit: i64) -> i64 {
    var total = 0i64
    var i = 0i64
    while i < limit {
        var j = 0i64
        while j < limit {
            if j > i + 3i64 { break }
            j += 1i64
            if (i + j) % 3i64 == 0i64 { continue }
            total += i * j
        }
        i += 1i64
    }
    ret total
}

fn ladder(n: i64) -> i64 {
    if n < 0i64 { ret 0i64 - 1i64 }
    if n == 0i64 { ret 100i64 }
    if n < 10i64 { ret n * 2i64 }
    if n < 100i64 {
        if n % 2i64 == 0i64 { ret n / 2i64 }
        ret n * 3i64 + 1i64
    }
    if n < 1000i64 { ret n - 7i64 }
    ret 5i64
}

fn first_match(values: []i64, wanted: i64) -> i64 {
    var found = 0i64 - 1i64
    var at = 0usize
    while at < values.len {
        if values[at] == wanted {
            found = i64(at)
            break
        }
        if values[at] > 1000i64 { break }
        at += 1usize
    }
    if found < 0i64 { ret 0i64 - 2i64 }
    ret found * 10i64 + wanted
}

fn collatz(start: i64) -> i64 {
    var n = start
    var steps = 0i64
    while n != 1i64 {
        if n % 2i64 == 0i64 { n = n / 2i64 } else { n = n * 3i64 + 1i64 }
        steps += 1i64
    }
    ret steps
}

fn both(a: bool, b: bool, c: bool) -> i64 {
    var score = 0i64
    if a && b { score += 1i64 }
    if a || c { score += 10i64 }
    if (a && !b) || (b && c) { score += 100i64 }
    if !(a || b || c) { score += 1000i64 }
    ret score
}

fn divmod(a: i64, b: i64) -> (i64, i64) { ret (a / b, a % b) }

fn pairs(n: i64) -> i64 {
    var sum = 0i64
    var k = 1i64
    while k <= n {
        let (q, r) = divmod(n * 7i64, k)
        let (q2, r2) = divmod(q + 1i64, k)
        sum = sum + q * 3i64 + r - r2 + q2
        k += 1i64
    }
    ret sum
}

fn expression(a: i64, b: i64, c: i64) -> i64 {
    let t = (a * b + c) * (a - b) + (b * c - a) * (c + 1i64)
    let u = ((t >> 2u64) ^ (a << 3u64)) & 1048575i64
    ret t - u + (a + b) * (b + c) * (c + a)
}

fn narrow(seed: u8) -> u32 {
    var x = seed
    var total = 0u32
    var i = 0u32
    while i < 40u32 {
        x = x *% 5u8 +% 3u8
        if x > 128u8 { total += u32(x) } else { total += 1u32 }
        i += 1u32
    }
    ret total
}

fn many(n: i64) -> i64 {
    var r = 0i64
    if n == 1i64 { r = 11i64 }
    if n == 2i64 { r = 22i64 }
    if n == 3i64 { r = 33i64 }
    if n == 4i64 { r = 44i64 }
    if n == 5i64 { r = 55i64 }
    if n == 6i64 { r = 66i64 }
    if n == 7i64 { r = 77i64 }
    if n == 8i64 { r = 88i64 }
    if n == 9i64 { r = 99i64 }
    if n > 9i64 { r = 1i64 }
    ret r
}

fn range_sum(n: usize) -> usize {
    var total = 0usize
    for i in 0usize..n {
        if i % 4usize == 3usize { continue }
        total += i * i
    }
    ret total
}

fn main(a: *mem.Arena, args: []str) -> err {
    var data: [8]i64 = zero
    data[0] = 5i64
    data[1] = 9i64
    data[2] = 14i64
    data[3] = 2000i64
    data[4] = 7i64
    var failures = 0i64
    let got_nested = nested(30i64)
    say_number("nested", got_nested)
    if got_nested != NESTED { failures += 1i64 }
    var sum_ladder = 0i64
    var n = 0i64 - 3i64
    while n < 1200i64 {
        sum_ladder = sum_ladder + ladder(n)
        n += 37i64
    }
    say_number("ladder", sum_ladder)
    if sum_ladder != LADDER { failures += 1i64 }
    let got_match = first_match(data[0usize..5usize], 14i64) + first_match(data[0usize..5usize], 7i64) + first_match(data[0usize..5usize], 3i64)
    say_number("match", got_match)
    if got_match != MATCH { failures += 1i64 }
    var steps = 0i64
    var s = 1i64
    while s < 60i64 {
        steps += collatz(s)
        s += 1i64
    }
    say_number("collatz", steps)
    if steps != COLLATZ { failures += 1i64 }
    var shorts = 0i64
    var mask = 0i64
    while mask < 8i64 {
        shorts = shorts * 7i64 + both(mask % 2i64 == 1i64, (mask / 2i64) % 2i64 == 1i64, (mask / 4i64) % 2i64 == 1i64)
        mask += 1i64
    }
    say_number("short", shorts)
    if shorts != SHORT { failures += 1i64 }
    let got_pairs = pairs(40i64)
    say_number("pairs", got_pairs)
    if got_pairs != PAIRS { failures += 1i64 }
    let got_expr = expression(3i64, 5i64, 7i64) + expression(0i64 - 9i64, 4i64, 0i64 - 2i64)
    say_number("expr", got_expr)
    if got_expr != EXPR { failures += 1i64 }
    let got_narrow = narrow(1u8) + narrow(200u8)
    say_number("narrow", i64(got_narrow))
    if i64(got_narrow) != NARROW { failures += 1i64 }
    var many_sum = 0i64
    var m = 0i64
    while m < 12i64 {
        many_sum = many_sum * 3i64 + many(m)
        m += 1i64
    }
    say_number("many", many_sum)
    if many_sum != MANY { failures += 1i64 }
    let got_range = range_sum(50usize)
    say_number("range", i64(got_range))
    if i64(got_range) != RANGE { failures += 1i64 }
    if failures != 0i64 { ret mem.Exhausted }
    ret ok
}
