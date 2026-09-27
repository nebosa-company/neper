// e.str's float text, against 16,000 vectors generated from exact rational arithmetic by
// ../vectors.py (never by this implementation): random bit patterns, subnormals, every
// power of two -- where the shortest correctly rounded spelling is not what Ryu prints --
// powers of ten, exact halfway strings up to 767 digits and their neighbours, and the edges
// of the parsers' fast paths. Every pushed text is also read back through the parser. Beyond
// the tables, 200,000 pseudo-random bit patterns per width must survive push-then-parse.
//
// Exit codes: 10+ a format64 line, 20+ format32, 30+ parse64, 40+ parse32, 50+ the random
// round trips; the failing line is printed first.
use e.io
use e.mem
use e.str
use vectors

error Failed

fn hex_value(text: str) -> (u64, bool) {
    var value = 0u64
    var i = 0usize
    while i < text.len {
        let c = text[i]
        var digit = 0u64
        if c >= 48u8 && c <= 57u8 {
            digit = u64(c - 48u8)
        } else if c >= 97u8 && c <= 102u8 {
            digit = u64(c - 87u8)
        } else {
            ret (0u64, false)
        }
        value = value << 4u64 | digit
        i += 1usize
    }
    ret (value, true)
}

// The `bits text` line starting at `from`: answers the two fields and where the next line
// begins.
fn line_at(table: str, from: usize) -> (str, str, usize) {
    var space = from
    while table[space] != 32u8 { space += 1usize }
    var end = space + 1usize
    while table[end] != 10u8 { end += 1usize }
    ret (table[from..space], table[space + 1usize..end], end + 1usize)
}

fn pushed64(a: *mem.Arena, bits: u64) -> (str, err) {
    var (b, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push_f64(&b, mem.bitcast[f64](bits))
    ret (str.done(&b), push_error)
}

fn pushed32(a: *mem.Arena, bits: u32) -> (str, err) {
    var (b, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push_f32(&b, mem.bitcast[f32](bits))
    ret (str.done(&b), push_error)
}

fn report(kind: str, field: str, text: str, got: str) {
    let printed = io.printf["{} mismatch: {} {} -> {}\n"](kind, field, text, got)
}

fn is_special(text: str) -> bool { ret str.eq(text, "nan") || str.eq(text, "inf") || str.eq(text, "-inf") }

fn formats64(a: *mem.Arena) -> i32 {
    var chunk = 0usize
    while chunk < vectors.FORMAT64_CHUNKS {
        let table = vectors.format64(chunk)
        var at = 0usize
        while at < table.len {
            let mark = mem.mark(a)
            let (field, text, next) = line_at(table, at)
            let (bits, parsed) = hex_value(field)
            if !parsed { ret 10i32 }
            let (got, push_error) = pushed64(a, bits)
            if push_error != ok || !str.eq(got, text) {
                report("format64", field, text, got)
                ret 11i32
            }
            // NaN reads back as the canonical NaN, not these bits; every other text is exact.
            if !is_special(text) {
                let (back, back_error) = str.parse_f64(got)
                if back_error != ok || mem.bitcast[u64](back) != bits {
                    report("format64 read-back", field, text, got)
                    ret 12i32
                }
            }
            mem.reset(a, mark)
            at = next
        }
        chunk += 1usize
    }
    ret 0i32
}

fn formats32(a: *mem.Arena) -> i32 {
    var chunk = 0usize
    while chunk < vectors.FORMAT32_CHUNKS {
        let table = vectors.format32(chunk)
        var at = 0usize
        while at < table.len {
            let mark = mem.mark(a)
            let (field, text, next) = line_at(table, at)
            let (bits, parsed) = hex_value(field)
            if !parsed { ret 20i32 }
            let (got, push_error) = pushed32(a, u32(bits))
            if push_error != ok || !str.eq(got, text) {
                report("format32", field, text, got)
                ret 21i32
            }
            if !is_special(text) {
                let (back, back_error) = str.parse_f32(got)
                if back_error != ok || u64(mem.bitcast[u32](back)) != bits {
                    report("format32 read-back", field, text, got)
                    ret 22i32
                }
            }
            mem.reset(a, mark)
            at = next
        }
        chunk += 1usize
    }
    ret 0i32
}

fn parses64() -> i32 {
    var chunk = 0usize
    while chunk < vectors.PARSE64_CHUNKS {
        let table = vectors.parse64(chunk)
        var at = 0usize
        while at < table.len {
            let (field, text, next) = line_at(table, at)
            let (value, value_error) = str.parse_f64(text)
            if str.eq(field, "!") {
                if value_error != str.BadNumber {
                    report("parse64 (want BadNumber)", field, text, "accepted")
                    ret 31i32
                }
            } else {
                let (bits, parsed) = hex_value(field)
                if !parsed { ret 30i32 }
                if value_error != ok || mem.bitcast[u64](value) != bits {
                    report("parse64", field, text, "other bits")
                    ret 32i32
                }
            }
            at = next
        }
        chunk += 1usize
    }
    ret 0i32
}

fn parses32() -> i32 {
    var chunk = 0usize
    while chunk < vectors.PARSE32_CHUNKS {
        let table = vectors.parse32(chunk)
        var at = 0usize
        while at < table.len {
            let (field, text, next) = line_at(table, at)
            let (value, value_error) = str.parse_f32(text)
            if str.eq(field, "!") {
                if value_error != str.BadNumber {
                    report("parse32 (want BadNumber)", field, text, "accepted")
                    ret 41i32
                }
            } else {
                let (bits, parsed) = hex_value(field)
                if !parsed { ret 40i32 }
                if value_error != ok || u64(mem.bitcast[u32](value)) != bits {
                    report("parse32", field, text, "other bits")
                    ret 42i32
                }
            }
            at = next
        }
        chunk += 1usize
    }
    ret 0i32
}

// xorshift64*: a fixed stream of bit patterns, so a failure reproduces.
type Random = struct { state: u64 }

fn next_random(r: *Random) -> u64 {
    var x = r.state
    x = x ^ (x >> 12u64)
    x = x ^ (x << 25u64)
    x = x ^ (x >> 27u64)
    r.state = x
    ret x *% 2685821657736338717u64
}

fn round_trips(a: *mem.Arena, count: usize) -> i32 {
    var random = Random { state: 88172645463325252u64 }
    var i = 0usize
    while i < count {
        let mark = mem.mark(a)
        let bits = next_random(&random)
        if (bits >> 52u64) & 2047u64 != 2047u64 {
            let (text, push_error) = pushed64(a, bits)
            let (back, back_error) = str.parse_f64(text)
            if push_error != ok || back_error != ok || mem.bitcast[u64](back) != bits {
                report("random64", "", text, "did not read back")
                ret 51i32
            }
        }
        let narrow = u32.trunc(bits >> 32u64)
        if (narrow >> 23u32) & 255u32 != 255u32 {
            let (text32, push32_error) = pushed32(a, narrow)
            let (back32, back32_error) = str.parse_f32(text32)
            if push32_error != ok || back32_error != ok || mem.bitcast[u32](back32) != narrow {
                report("random32", "", text32, "did not read back")
                ret 52i32
            }
        }
        mem.reset(a, mark)
        i += 1usize
    }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    // An argument overrides the random round-trip count (0 skips them).
    var count = 200000usize
    if args.len > 1usize {
        let (n, n_error) = str.parse_u64(args[1])
        if n_error == ok { count = usize(n) }
    }
    var code = formats64(a)
    if code == 0i32 { code = formats32(a) }
    if code == 0i32 { code = parses64() }
    if code == 0i32 { code = parses32() }
    if code == 0i32 { code = round_trips(a, count) }
    if code != 0i32 {
        let failed = io.printf["exit {}\n"](code)
        ret Failed
    }
    ret ok
}
