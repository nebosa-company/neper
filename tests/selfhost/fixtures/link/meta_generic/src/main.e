// Reflection inside a generic function, where the type is a parameter rather than a name.
//
// A generic body is checked twice: once as a template, with nothing bound, and once per
// instance with the argument in place. A `meta` question has no answer in the first pass, so
// it stands there and is settled in the second -- which is what `mem.size_of` always did and
// why that one worked inside a generic while `kind` and `element_type` did not (D136).
//
// What this pins is that the deferral is only a deferral: every answer below is the instance's
// own, not a placeholder that survived.

use e.mem
use e.meta
use e.os
use e.str

type Point = struct { x: i64, y: i64 }
type Level = enum u8 { Low, High }

error Failed

// `kind` decides which of these a `T` is, from inside the generic.
fn classify[T: type]() -> u8 {
    let answer = meta.kind[T]()
    if answer == .Int { ret 1u8 }
    if answer == .Bool { ret 2u8 }
    if answer == .Slice { ret 3u8 }
    if answer == .Array { ret 4u8 }
    if answer == .Struct { ret 5u8 }
    if answer == .Enum { ret 6u8 }
    ret 0u8
}

fn length[T: type]() -> usize {
    ret meta.array_len[T]()
}

fn name[T: type]() -> str {
    ret meta.type_name[T]()
}

// A deferred `element_type` handed to another generic as its comptime argument. The chain is
// two deep, so what arrives at `width` is the element of the element.
fn width[T: type]() -> usize {
    ret mem.size_of[T]()
}

fn element_width[T: type]() -> usize {
    ret width[meta.element_type[T]()]()
}

fn inner_width[T: type]() -> usize {
    ret element_width[meta.element_type[T]()]()
}

// `fields` was never blocked -- it is only ever a `for` subject, and a binding is not a type
// parameter. It is here so that the deferral cannot quietly cost it.
fn total[T: type](v: *const T) -> i64 {
    var sum = 0i64
    for f in meta.fields[T]() {
        sum += meta.get[f, T](v)
    }
    ret sum
}

fn main(a: *mem.Arena) -> err {
    // Each instantiation answers for its own type, and the answers differ -- a placeholder
    // that survived the template pass would make them all agree.
    if classify[u64]() != 1u8 { ret Failed }
    if classify[bool]() != 2u8 { ret Failed }
    if classify[str]() != 3u8 { ret Failed }
    if classify[[3]u8]() != 4u8 { ret Failed }
    if classify[Point]() != 5u8 { ret Failed }
    if classify[Level]() != 6u8 { ret Failed }

    if length[[3]u8]() != 3usize { ret Failed }
    if length[[7]Point]() != 7usize { ret Failed }

    if !str.eq(name[Point](), "Point") { ret Failed }
    if !str.eq(name[u64](), "u64") { ret Failed }

    // `[2][4]u64` is an array of arrays: one level in is `[4]u64`, two levels in is `u64`.
    if element_width[[4]u64]() != 8usize { ret Failed }
    if element_width[[4]u8]() != 1usize { ret Failed }
    if inner_width[[2][4]u64]() != 8usize { ret Failed }

    var p = Point { x: 3i64, y: 4i64 }
    if total[Point](&p) != 7i64 { ret Failed }
    ret ok
}
