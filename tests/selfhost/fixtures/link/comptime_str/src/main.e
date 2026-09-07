// A comptime `str` parameter is a string literal bound where the call is written, so
// the body reads it as an ordinary `str` and each distinct literal is its own
// instance. It is the half of `format[FMT: str](a, args: ...)` that does not need
// varargs, and the reason it exists.

use e.mem
use e.str

error Failed

fn repeated[LABEL: str](a: *mem.Arena, count: usize) -> (str, err) {
    var (b, builder_error) = str.builder(a, 32usize)
    if builder_error != ok { ret ("", builder_error) }
    var at = 0usize
    while at < count {
        let push_error = str.push(&b, LABEL)
        if push_error != ok { ret ("", push_error) }
        at += 1usize
    }
    let out = str.done(&b)
    ret (out, ok)
}

fn width[LABEL: str]() -> usize {
    ret LABEL.len
}

fn first_byte[LABEL: str]() -> u8 {
    if LABEL.len == 0usize { ret 0u8 }
    ret LABEL[0usize]
}

// A comptime string and a comptime integer in one parameter list, to pin that the two
// kinds are bound independently and in order.
fn padded[LABEL: str, N: usize](a: *mem.Arena) -> (str, err) {
    var (b, builder_error) = str.builder(a, 32usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push(&b, LABEL)
    if push_error != ok { ret ("", push_error) }
    var at = 0usize
    while at < N {
        let pad_error = str.push_byte(&b, 46u8)
        if pad_error != ok { ret ("", pad_error) }
        at += 1usize
    }
    let out = str.done(&b)
    ret (out, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (twice, twice_error) = repeated["ab"](a, 2usize)
    if twice_error != ok { ret twice_error }
    if !str.eq(twice, "abab") { ret Failed }

    // A second literal is a second instance, not the first one reused, so the two
    // calls must not share a body.
    let (other, other_error) = repeated["xyz"](a, 1usize)
    if other_error != ok { ret other_error }
    if !str.eq(other, "xyz") { ret Failed }
    let (again, again_error) = repeated["ab"](a, 3usize)
    if again_error != ok { ret again_error }
    if !str.eq(again, "ababab") { ret Failed }
    let (none, none_error) = repeated["ab"](a, 0usize)
    if none_error != ok { ret none_error }
    if none.len != 0usize { ret Failed }

    // The bound value is an ordinary `str`: it has a length and it indexes.
    if width["hello"]() != 5usize { ret Failed }
    if width[""]() != 0usize { ret Failed }
    if first_byte["hello"]() != 104u8 { ret Failed }
    if first_byte[""]() != 0u8 { ret Failed }

    // Escapes are decoded where every other literal's are, so what the instantiation
    // carries is the source spelling and nothing has read it early.
    if width["a\nb"]() != 3usize { ret Failed }
    if first_byte["\n"]() != 10u8 { ret Failed }
    if width["\x41\x42"]() != 2usize { ret Failed }
    if first_byte["\x41"]() != 65u8 { ret Failed }
    if width["a\"b"]() != 3usize { ret Failed }

    // A raw string is a literal too, and its backslash is a byte rather than an
    // escape, so the two spellings of the same name are different instances.
    if width[r"a\nb"]() != 4usize { ret Failed }
    if first_byte[r"\n"]() != 92u8 { ret Failed }

    // Two kinds of comptime parameter in one list.
    let (dotted, dotted_error) = padded["ok", 3usize](a)
    if dotted_error != ok { ret dotted_error }
    if !str.eq(dotted, "ok...") { ret Failed }
    let (bare, bare_error) = padded["ok", 0usize](a)
    if bare_error != ok { ret bare_error }
    if !str.eq(bare, "ok") { ret Failed }
    // Same string, different count: still two instances.
    let (wider, wider_error) = padded["ok", 5usize](a)
    if wider_error != ok { ret wider_error }
    if !str.eq(wider, "ok.....") { ret Failed }
    ret ok
}
