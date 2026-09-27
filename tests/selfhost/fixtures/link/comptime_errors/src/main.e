// Errors, several results and `try` in the comptime interpreter (D1571, C066): a
// function answering a value beside an `err`, one that passes a failure on with
// `try` (the zero value beside it), a pair of results, `_` discarding one, a `try`
// statement in a function answering only `err`; and the errors compared by name.
error Negative
error TooBig
error Wrong

fn checked(x: i32) -> (u32, err) {
    if x < 0i32 { ret (0u32, Negative) }
    if x > 100i32 { ret (0u32, TooBig) }
    ret (u32(x), ok)
}

fn doubled(x: i32) -> (u32, err) {
    let v = try checked(x)
    ret (v * 2u32, ok)
}

fn split(x: u32) -> (u32, u32) {
    ret (x / 10u32, x % 10u32)
}

fn tally() -> u32 {
    var score = 0u32
    let (a, e) = checked(7i32)
    if e == ok { score += a }
    let (b, bad) = doubled(-3i32)
    if bad == Negative && b == 0u32 { score += 100u32 }
    let (c, big) = doubled(500i32)
    if big == TooBig && c == 0u32 { score += 1000u32 }
    if big != Negative { score += 10000u32 }
    let (tens, ones) = split(42u32)
    score += tens * 100000u32 + ones
    let (_, only) = checked(1i32)
    if only == ok { score += 3u32 }
    ret score
}

fn positive(x: i32) -> err {
    if x < 0i32 { ret Negative }
    ret ok
}

fn both(x: i32, y: i32) -> err {
    try positive(x)
    try positive(y)
    ret ok
}

fn verdict() -> usize {
    var bits = 0usize
    if both(1i32, 2i32) == ok { bits += 1usize }
    if both(1i32, -2i32) == Negative { bits += 2usize }
    ret bits
}

const TALLY = tally()
const VERDICT = verdict()

fn main() -> err {
    if TALLY != 411112u32 { ret Wrong }
    if VERDICT != 3usize { ret Wrong }
    var sized: [VERDICT]u8 = zero
    if sized.len != 3usize { ret Wrong }
    ret ok
}
