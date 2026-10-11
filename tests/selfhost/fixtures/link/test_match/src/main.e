// `e.test.match`: the truth tables of every matcher kind over integers, floats, text,
// bools and integer lists; composition (all_of, any_of, negate, has_item, every, len_is)
// agreeing with the plain boolean expression it stands for over a 12x12 grid; and the
// exact description and mismatch texts, hand-checked against the Hamcrest convention
// ("expected: ..." / "     but: was ..."), including the failing-part naming of a
// composite and the message `assert_that` leaves in `e.test.current`. Every check has
// its own exit code.
use e.os
use e.mem
use e.str
use e.test
use e.test.match as match

fn int_v(n: i64) -> match.Subject { ret match.Subject{ Int: n } }
fn text_v(t: str) -> match.Subject { ret match.Subject{ Text: t } }

fn desc_is(m: *const match.Matcher, want: str) -> bool {
    var buf: [256]u8 = zero
    ret str.eq(match.describe(m, buf[0..]), want)
}

fn why_is(m: *const match.Matcher, v: match.Subject, want: str) -> bool {
    var buf: [256]u8 = zero
    ret str.eq(match.explain(m, v, buf[0..]), want)
}

fn checks_scalar() -> i32 {
    let ge5 = match.ge(5i64)
    if !match.matches(&ge5, int_v(5i64)) || match.matches(&ge5, int_v(4i64)) { ret 10i32 }
    let b = match.between(2i64, 4i64)
    if !match.matches(&b, int_v(2i64)) || !match.matches(&b, int_v(4i64)) || match.matches(&b, int_v(5i64)) { ret 11i32 }
    var set: [3]i64 = zero
    set[0] = 1i64
    set[1] = 3i64
    set[2] = 5i64
    let o = match.one_of(set[0..])
    if !match.matches(&o, int_v(3i64)) || match.matches(&o, int_v(4i64)) { ret 12i32 }
    let near = match.near(1.0f64, 0.25f64)
    if !match.matches(&near, match.Subject{ Float: 1.2f64 }) || match.matches(&near, match.Subject{ Float: 1.3f64 }) { ret 13i32 }
    let eqf = match.eq_float(0.5f64)
    if !match.matches(&eqf, match.Subject{ Float: 0.5f64 }) || match.matches(&eqf, match.Subject{ Float: 0.25f64 }) { ret 14i32 }
    let c = match.contains("ell")
    if !match.matches(&c, text_v("hello")) || match.matches(&c, text_v("help")) { ret 15i32 }
    let sw = match.starts_with("he")
    let ew = match.ends_with("lo")
    if !match.matches(&sw, text_v("hello")) || match.matches(&sw, text_v("h")) { ret 16i32 }
    if !match.matches(&ew, text_v("hello")) || match.matches(&ew, text_v("o")) { ret 17i32 }
    let t = match.is_true()
    let f = match.is_false()
    if !match.matches(&t, match.Subject{ Bool: true }) || match.matches(&t, match.Subject{ Bool: false }) { ret 18i32 }
    if !match.matches(&f, match.Subject{ Bool: false }) { ret 19i32 }
    // A subject of a kind the matcher does not read never matches (and anything always does).
    if match.matches(&ge5, text_v("9")) || match.matches(&c, int_v(1i64)) { ret 20i32 }
    let any = match.anything()
    if !match.matches(&any, text_v("x")) { ret 21i32 }
    ret 0i32
}

// Composition equals the boolean expression over a grid of subjects and bounds.
fn checks_grid() -> i32 {
    var lo = 0i64
    while lo < 12i64 {
        var x = 0i64
        while x < 12i64 {
            var parts: [2]match.Matcher = zero
            parts[0] = match.ge(lo)
            parts[1] = match.lt(lo + 4i64)
            let both = match.all_of(parts[0..])
            let either = match.any_of(parts[0..])
            let inner = match.eq_int(lo)
            let none = match.negate(&inner)
            let want_both = x >= lo && x < lo + 4i64
            let want_either = x >= lo || x < lo + 4i64
            if match.matches(&both, int_v(x)) != want_both { ret 30i32 }
            if match.matches(&either, int_v(x)) != want_either { ret 31i32 }
            if match.matches(&none, int_v(x)) != (x != lo) { ret 32i32 }
            x += 1i64
        }
        lo += 1i64
    }
    ret 0i32
}

fn checks_lists() -> i32 {
    var items: [4]i64 = zero
    items[0] = 2i64
    items[1] = 4i64
    items[2] = 6i64
    items[3] = 9i64
    let list = match.Subject{ Ints: items[0..] }
    let big = match.gt(8i64)
    let small = match.lt(2i64)
    let even_ish = match.le(9i64)
    let has_big = match.has_item(&big)
    let has_small = match.has_item(&small)
    let all_le = match.every(&even_ish)
    let all_big = match.every(&big)
    if !match.matches(&has_big, list) || match.matches(&has_small, list) { ret 40i32 }
    if !match.matches(&all_le, list) || match.matches(&all_big, list) { ret 41i32 }
    let four = match.eq_int(4i64)
    let len4 = match.len_is(&four)
    if !match.matches(&len4, list) { ret 42i32 }
    var none: [1]i64 = zero
    let empty = match.Subject{ Ints: none[0..0usize] }
    if match.matches(&has_big, empty) || !match.matches(&all_big, empty) { ret 43i32 }
    let three = match.gt(3i64)
    let long_text = match.len_is(&three)
    if !match.matches(&long_text, text_v("abcd")) || match.matches(&long_text, text_v("abc")) { ret 44i32 }
    ret 0i32
}

fn checks_text() -> i32 {
    let ge5 = match.ge(5i64)
    if !desc_is(&ge5, "at least 5") { ret 50i32 }
    if !why_is(&ge5, int_v(3i64), "was 3") { ret 51i32 }
    let b = match.between(2i64, 4i64)
    if !desc_is(&b, "between 2 and 4") { ret 52i32 }
    let eq = match.eq_text("ab")
    if !desc_is(&eq, "equal to \"ab\"") { ret 53i32 }
    if !why_is(&eq, text_v("xy"), "was \"xy\"") { ret 54i32 }
    let c = match.contains("z")
    if !desc_is(&c, "containing \"z\"") { ret 55i32 }
    var set: [2]i64 = zero
    set[0] = 7i64
    set[1] = 8i64
    let o = match.one_of(set[0..])
    if !desc_is(&o, "one of [7, 8]") { ret 56i32 }
    let gt1 = match.gt(1i64)
    let not_gt1 = match.negate(&gt1)
    if !desc_is(&not_gt1, "not (greater than 1)") { ret 57i32 }
    if !why_is(&not_gt1, int_v(3i64), "was 3") { ret 58i32 }
    // A composite names the part that failed.
    var parts: [2]match.Matcher = zero
    parts[0] = match.ge(0i64)
    parts[1] = match.lt(10i64)
    let range = match.all_of(parts[0..])
    if !desc_is(&range, "all of (at least 0 and less than 10)") { ret 59i32 }
    if !why_is(&range, int_v(12i64), "was 12") { ret 60i32 }
    let either = match.any_of(parts[0..])
    if !desc_is(&either, "any of (at least 0 or less than 10)") { ret 61i32 }
    var edges: [2]match.Matcher = zero
    edges[0] = match.eq_int(1i64)
    edges[1] = match.eq_int(2i64)
    let one_or_two = match.any_of(edges[0..])
    if !why_is(&one_or_two, int_v(5i64), "none matched: was 5; was 5") { ret 62i32 }
    var items: [3]i64 = zero
    items[0] = 1i64
    items[1] = 9i64
    items[2] = 3i64
    let lt5 = match.lt(5i64)
    let all_lt5 = match.every(&lt5)
    let list = match.Subject{ Ints: items[0..] }
    if !desc_is(&all_lt5, "every item less than 5") { ret 63i32 }
    if !why_is(&all_lt5, list, "item at index 1 was 9") { ret 64i32 }
    let big = match.gt(100i64)
    let has_big = match.has_item(&big)
    if !desc_is(&has_big, "an item greater than 100") { ret 65i32 }
    if !why_is(&has_big, list, "no item matched in [1, 9, 3]") { ret 66i32 }
    let two = match.eq_int(2i64)
    let len2 = match.len_is(&two)
    if !why_is(&len2, list, "length was 3") { ret 67i32 }
    if !desc_is(&len2, "length equal to 2") { ret 68i32 }
    // Booleans and floats render.
    let t = match.is_true()
    if !why_is(&t, match.Subject{ Bool: false }, "was false") { ret 69i32 }
    let near = match.near(0.5f64, 0.25f64)
    if !desc_is(&near, "within 0.25 of 0.5") { ret 70i32 }
    // A subject of the wrong kind is shown as it is.
    if !why_is(&ge5, text_v("q"), "was \"q\"") { ret 71i32 }
    ret 0i32
}

fn checks_message() -> i32 {
    var buf: [128]u8 = zero
    let ge5 = match.ge(5i64)
    let want = "expected: at least 5\n     but: was 3"
    if !str.eq(match.message(&ge5, int_v(3i64), buf[0..]), want) { ret 80i32 }
    if match.assert_that(int_v(9i64), &ge5, buf[0..]) != ok { ret 81i32 }
    if match.assert_that(int_v(3i64), &ge5, buf[0..]) != test.Failed { ret 82i32 }
    if !str.eq(test.current.message, want) { ret 83i32 }
    // A buffer too small cuts the text and still fails the test.
    var tiny: [12]u8 = zero
    if match.assert_that(int_v(3i64), &ge5, tiny[0..]) != test.Failed { ret 84i32 }
    if test.current.message.len > 12usize { ret 85i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = checks_scalar()
    if code == 0i32 { code = checks_grid() }
    if code == 0i32 { code = checks_lists() }
    if code == 0i32 { code = checks_text() }
    if code == 0i32 { code = checks_message() }
    if code != 0i32 { os.exit(code) }
    ret ok
}
