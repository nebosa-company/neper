// Section 9's comptime values of struct type, run rather than only checked. `Field`
// and `Member` are comptime-only, `meta.fields[T]()` may stand only as the subject of
// a `for` -- which is always unrolled -- and the binding is a distinct comptime value
// in each copy, which is what lets `f.ty` be a different type each time round.
//
// The offsets and sizes are asserted against the target layout by hand, so a `get` at
// the wrong offset or a `size` from the wrong type is a wrong value here and not just
// a type error. Nothing of the loops survives to the emitter.
use e.meta

error Failed

type Point = struct { x: i64, y: i32, tag: u8 }
type Colour = enum u8 { Red, Green = 7, Blue }

// The shape the spec gives: one function that walks any struct, reading each field
// through the comptime `Field` that names it.
fn sum_fields[T: type](v: *const T) -> i64 {
    var total = 0i64
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](v)
        total += i64(slot)
    }
    ret total
}

fn name_length[T: type]() -> usize {
    var n = 0usize
    for f in meta.fields[T]() {
        n += f.name.len
    }
    ret n
}

fn last_offset[T: type]() -> usize {
    var last = 0usize
    for f in meta.fields[T]() {
        last = f.offset
    }
    ret last
}

fn size_total[T: type]() -> usize {
    var n = 0usize
    for f in meta.fields[T]() {
        n += f.size
    }
    ret n
}

fn field_count[T: type]() -> usize {
    var n = 0usize
    for f in meta.fields[T]() {
        n += 1usize
    }
    ret n
}

fn member_values[E: type]() -> u64 {
    var total = 0u64
    for m in meta.members[E]() {
        total += m.value
    }
    ret total
}

fn member_name_length[E: type]() -> usize {
    var n = 0usize
    for m in meta.members[E]() {
        n += m.name.len
    }
    ret n
}

fn main() -> err {
    var p: Point = zero
    p.x = 100i64
    p.y = 20i32
    p.tag = 3u8

    // Every field read through its own `Field`, at its own offset and width.
    if sum_fields[Point](&p) != 123i64 { ret Failed }
    if field_count[Point]() != 3usize { ret Failed }

    // "x" + "y" + "tag"
    if name_length[Point]() != 5usize { ret Failed }

    // i64 at 0, i32 at 8, u8 at 12
    if last_offset[Point]() != 12usize { ret Failed }
    if size_total[Point]() != 13usize { ret Failed }

    // Writing through a `Field` lands where reading it does.
    for f in meta.fields[Point]() {
        var slot: f.ty = zero
        slot = meta.get[f, Point](&p)
        meta.set[f, Point](&p, slot)
    }
    if p.x != 100i64 || p.y != 20i32 || p.tag != 3u8 { ret Failed }

    // Members carry their declared values, explicit ones included: 0 + 7 + 8.
    if member_values[Colour]() != 15u64 { ret Failed }
    if member_name_length[Colour]() != 12usize { ret Failed }
    ret ok
}
