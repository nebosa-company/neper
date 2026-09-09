// Section 9's `Field` and `Member` as declared names: a user function taking one, which the
// spec says is available "under the same rule as the `e.meta` intrinsics".
//
// `link/meta_reflect` already walks a struct inside one function. What this adds is the handover:
// the comptime value crosses a call, so the callee is instantiated per field and its own return
// type depends on which one it was given. Nothing here is reachable without that -- a `Field` has
// no spelling of its own, so the argument is always a name that already holds one.

use e.meta

error Failed

type Point = struct { x: i64, y: i32, tag: u8 }
type Colour = enum u8 { Red, Green = 7, Blue }

// A dependent return type: `FIELD.ty` is a different type in every instantiation.
fn read_field[FIELD: meta.Field, T: type](v: *const T) -> FIELD.ty {
    ret meta.get[FIELD, T](v)
}

fn write_field[FIELD: meta.Field, T: type](v: *T, x: FIELD.ty) {
    meta.set[FIELD, T](v, x)
}

fn field_offset[FIELD: meta.Field, T: type]() -> usize {
    ret FIELD.offset
}

fn field_size[FIELD: meta.Field, T: type]() -> usize {
    ret FIELD.size
}

fn field_name_length[FIELD: meta.Field, T: type]() -> usize {
    ret FIELD.name.len
}

fn member_value[MEMBER: meta.Member, E: type]() -> u64 {
    ret MEMBER.value
}

fn member_name_length[MEMBER: meta.Member, E: type]() -> usize {
    ret MEMBER.name.len
}

// One handover passed on to another: the callee's own parameter is the argument to a third
// function, which is what says a parameter and a loop's binding are the same kind of thing.
fn relayed_offset[FIELD: meta.Field, T: type]() -> usize {
    ret field_offset[FIELD, T]()
}

fn main() -> err {
    var p: Point = zero
    p.x = 100i64
    p.y = 20i32
    p.tag = 3u8

    // --- Every field read through a call rather than in place. i64 at 0, i32 at 8, u8 at 12.
    var total = 0i64
    var offsets = 0usize
    var sizes = 0usize
    var names = 0usize
    for f in meta.fields[Point]() {
        var slot: f.ty = zero
        slot = read_field[f, Point](&p)
        total += i64(slot)
        offsets += field_offset[f, Point]()
        sizes += field_size[f, Point]()
        names += field_name_length[f, Point]()
    }
    if total != 123i64 { ret Failed }
    if offsets != 20usize { ret Failed }
    if sizes != 13usize { ret Failed }
    // "x" + "y" + "tag"
    if names != 5usize { ret Failed }

    // --- Relayed one more call deep, which must give the same answer.
    var relayed = 0usize
    for f in meta.fields[Point]() {
        relayed += relayed_offset[f, Point]()
    }
    if relayed != offsets { ret Failed }

    // --- Written through a call, and read back in place. If the offset the callee used were
    // not the field's own, the value would land somewhere else and one of these would differ.
    for f in meta.fields[Point]() {
        var slot: f.ty = zero
        slot = read_field[f, Point](&p)
        write_field[f, Point](&p, slot)
    }
    if p.x != 100i64 { ret Failed }
    if p.y != 20i32 { ret Failed }
    if p.tag != 3u8 { ret Failed }

    // --- Members cross a call the same way. 0 + 7 + 8, and "Red" + "Green" + "Blue".
    var values = 0u64
    var member_names = 0usize
    for m in meta.members[Colour]() {
        values += member_value[m, Colour]()
        member_names += member_name_length[m, Colour]()
    }
    if values != 15u64 { ret Failed }
    if member_names != 12usize { ret Failed }
    ret ok
}
