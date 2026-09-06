// The builder owns the top of an arena, so appending is a bump of the arena offset.
// This fixture pins the three things that are not visible from the signatures: that
// the builder grows past its initial reservation in place, that it refuses to write
// once something else has taken the top, and that a builder carrying a sink drains
// through it instead of reporting `mem.Exhausted`.
use e.mem
use e.str

error Failed

fn same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

// A sink that keeps no state, because a `Sink` context cannot be made without a
// pointer cast. It checks the bytes it is handed instead of recording them.
fn only_x(ctx: *void, bytes: []const u8) -> err {
    if bytes.len == 0usize { ret Failed }
    var at = 0usize
    while at < bytes.len {
        if bytes[at] != 120u8 { ret Failed }
        at += 1usize
    }
    ret ok
}

// Section 9 spells a declared `format` as `fn <t>_format(v: T, b: *str.Builder)`, so
// the builder has to be nameable as a type through the module's own qualifier even
// though `str` is also a builtin type name.
fn point_format(v: i64, b: *str.Builder) -> err {
    try str.push_byte(b, 40u8)
    try str.push_i64(b, v)
    try str.push_byte(b, 41u8)
    ret ok
}

// Each of these builds one number in a builder of its own, so a wrong digit shows
// up as a mismatch against the expected text rather than as a wrong offset later.
fn check_i64(a: *mem.Arena, v: i64, want: str) -> err {
    var (b, builder_error) = str.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    try str.push_i64(&b, v)
    if !same(str.done(&b), want) { ret Failed }
    ret ok
}

fn check_u64(a: *mem.Arena, v: u64, want: str) -> err {
    var (b, builder_error) = str.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    try str.push_u64(&b, v)
    if !same(str.done(&b), want) { ret Failed }
    ret ok
}

fn check_hex(a: *mem.Arena, v: u64, want: str) -> err {
    var (b, builder_error) = str.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    try str.push_hex_u64(&b, v)
    if !same(str.done(&b), want) { ret Failed }
    ret ok
}

fn check_bin(a: *mem.Arena, v: u64, want: str) -> err {
    var (b, builder_error) = str.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    try str.push_bin_u64(&b, v)
    if !same(str.done(&b), want) { ret Failed }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    // A run of mixed pushes, and the byte and bool forms that have no verb of
    // their own.
    var (b, builder_error) = str.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    try str.push(&b, "n=")
    try str.push_u32(&b, 42u32)
    try str.push_byte(&b, 32u8)
    try str.push_bool(&b, true)
    try str.push_byte(&b, 32u8)
    try str.push_i16(&b, 0i16 - 7i16)
    if !same(str.done(&b), "n=42 true -7") { ret Failed }

    var (formatted, formatted_error) = str.builder(a, 8usize)
    if formatted_error != ok { ret formatted_error }
    try point_format(0i64 - 3i64, &formatted)
    if !same(str.done(&formatted), "(-3)") { ret Failed }

    // `cap` is an initial reservation, not a limit: 4 bytes reserved, 300 written,
    // and the buffer grows in place rather than moving.
    var (grown, grown_error) = str.builder(a, 4usize)
    if grown_error != ok { ret grown_error }
    var at = 0usize
    while at < 300usize {
        try str.push(&grown, "ab")
        at += 1usize
    }
    let long = str.done(&grown)
    if long.len != 600usize { ret Failed }
    if long[0usize] != 97u8 || long[599usize] != 98u8 { ret Failed }
    if long[299usize] != 98u8 || long[300usize] != 97u8 { ret Failed }

    // `done` gives the arena top back, so the next allocation starts where the
    // written bytes end rather than where the reservation did.
    var (trimmed, trimmed_error) = str.builder(a, 64usize)
    if trimmed_error != ok { ret trimmed_error }
    try str.push(&trimmed, "abc")
    let short = str.done(&trimmed)
    let after = mem.mark(a)
    let (next, next_error) = mem.alloc[u8](a, 1usize)
    if next_error != ok { ret next_error }
    if after != mem.mark(a) - 1usize { ret Failed }
    if !same(short, "abc") { ret Failed }

    // The claim has to still be on top. One allocation from underneath the builder
    // turns the next push into an error instead of an overwrite.
    var (stale, stale_error) = str.builder(a, 8usize)
    if stale_error != ok { ret stale_error }
    try str.push(&stale, "x")
    let (interloper, interloper_error) = mem.alloc[u8](a, 8usize)
    if interloper_error != ok { ret interloper_error }
    if str.push(&stale, "y") != str.NotOnTop { ret Failed }

    // Decimal edges: zero, both signs, and the two ends of `i64` — the most negative
    // of which has no positive counterpart to negate.
    let i64_max = 9223372036854775807i64
    try check_i64(a, 0i64, "0")
    try check_i64(a, i64_max, "9223372036854775807")
    try check_i64(a, 0i64 - i64_max - 1i64, "-9223372036854775808")
    try check_i64(a, 0i64 - 100i64, "-100")
    try check_i64(a, 0i64 - 5i64, "-5")
    try check_u64(a, 0u64, "0")
    try check_u64(a, 18446744073709551615u64, "18446744073709551615")

    // `{x}` and `{b}` write the digits alone: no prefix and no leading zeros, so the
    // narrow and wide forms of one value agree.
    try check_hex(a, 0u64, "0")
    try check_hex(a, 3735928559u64, "deadbeef")
    try check_hex(a, 18446744073709551615u64, "ffffffffffffffff")
    try check_bin(a, 0u64, "0")
    try check_bin(a, 10u64, "1010")

    var (narrow, narrow_error) = str.builder(a, 8usize)
    if narrow_error != ok { ret narrow_error }
    try str.push_hex_u32(&narrow, 255u32)
    try str.push_byte(&narrow, 47u8)
    try str.push_bin_u32(&narrow, 5u32)
    try str.push_byte(&narrow, 47u8)
    try str.push_u8(&narrow, 7u8)
    try str.push_byte(&narrow, 47u8)
    try str.push_isize(&narrow, 0isize - 1isize)
    try str.push_byte(&narrow, 47u8)
    try str.push_usize(&narrow, 9usize)
    try str.push_bool(&narrow, false)
    if !same(str.done(&narrow), "ff/101/7/-1/9false") { ret Failed }

    // A flushing builder over an arena far too small for what it is given. Every
    // push must succeed: the buffer drains through the sink and the push carries on.
    var storage: [64]u8 = zero
    let room = storage[0usize..64usize]
    var small = mem.arena_from(room)
    let sink = str.Sink { ctx: zero, write: only_x }
    var (streamed, streamed_error) = str.builder_to(&small, 16usize, sink)
    if streamed_error != ok { ret streamed_error }
    at = 0usize
    while at < 200usize {
        try str.push(&streamed, "x")
        at += 1usize
    }
    let leftover = str.done(&streamed)
    if leftover.len == 0usize || leftover.len > 64usize { ret Failed }
    if leftover[0usize] != 120u8 { ret Failed }
    ret ok
}
