// `e.meta`'s two type-valued questions: `element_type` and `backing_type`.
//
// Both answer with a type rather than a number, so what this fixture checks is not that they
// return something but that what they return is a type in every respect -- a comptime argument to
// anything that takes one, including another question of the same kind and a generic of the
// caller's own.
//
// A local's annotation is one of those places, and it took a parser change to reach: the type
// grammar accepted a dotted name there (`FIELD.ty`) but not a call. The same change let a
// composite type stand as a comptime argument in a type position, which had never worked.

use e.mem
use e.os
use e.meta
use e.data.list

type Level = enum u16 { Low, Mid, High }
type Wide = enum i64 { Below, Above }

// A parenthesised comptime argument in a type position, which is an instantiation and not a call
// however much it looks like one from the tokens: the `(` here belongs to the argument. Getting
// that wrong routes every such type to the comptime-call path, which `check/constant_operators_valid`
// caught and this keeps caught next to the feature that caused it.
type Sized[N: usize] = struct { values: [N]u8 }
type Doubled[N: usize] = struct { inner: Sized[(N << 1u8) | 1usize] }

// The way a caller reaches the type without being able to name it: hand it to a generic of its
// own and let the parameter be it. This is what a format module walking an array would do.
fn zero_of[T: type]() -> T {
    var value: T = zero
    ret value
}

fn round_trip[T: type](value: T) -> T {
    var copy: T = zero
    copy = value
    ret copy
}

fn main(a: *mem.Arena) -> err {
    var source: [4]u8 = zero
    source[0usize] = 9u8

    // --- The element of an array or a slice, as a comptime argument. Asking the size of a
    // slice's element without naming the element is the point of it.
    if mem.size_of[meta.element_type[[]u8]()]() != 1usize { os.exit(10i32) }
    if mem.size_of[meta.element_type[[]u64]()]() != 8usize { os.exit(11i32) }
    if mem.size_of[meta.element_type[[3]u16]()]() != 2usize { os.exit(12i32) }
    // An array of arrays gives back the inner array, not its element.
    if mem.size_of[meta.element_type[[2][4]u8]()]() != 4usize { os.exit(13i32) }
    if mem.align_of[meta.element_type[[2][4]u8]()]() != 1usize { os.exit(14i32) }
    // A slice of pointers gives back the pointer.
    if mem.size_of[meta.element_type[[]*u8]()]() != 8usize { os.exit(15i32) }

    // --- `backing_type` is the integer an enum is stored as, which is the whole reason it
    // exists: `Member.value` is always a u64, and only this says how to read one back.
    if mem.size_of[meta.backing_type[Level]()]() != 2usize { os.exit(20i32) }
    if mem.size_of[meta.backing_type[Wide]()]() != 8usize { os.exit(21i32) }

    // --- One as the other's subject, which is what says the answer is a type and not a special
    // form that only works at the outside: the element of an array of enums has a backing type.
    if mem.size_of[meta.backing_type[meta.element_type[[2]Level]()]()]() != 2usize { os.exit(30i32) }

    // --- The kind of the answer is the kind of the part, not of the whole.
    if meta.kind[meta.element_type[[4]u32]()]() != .Int { os.exit(31i32) }
    if meta.kind[meta.element_type[[]Level]()]() != .Enum { os.exit(32i32) }
    if meta.kind[meta.backing_type[Level]()]() != .Int { os.exit(33i32) }
    // A slice of slices is a slice, and its element is one too.
    if meta.kind[meta.element_type[[][]u8]()]() != .Slice { os.exit(34i32) }

    // --- The answer instantiating a generic of the caller's own, which is how a value of the
    // element type is reached without a name for it.
    let empty = zero_of[meta.element_type[[]u32]()]()
    if empty != 0u32 { os.exit(40i32) }
    let carried = round_trip[meta.element_type[[]u16]()](65535u16)
    if carried != 65535u16 { os.exit(41i32) }
    // And the signed backing of a signed enum carries a negative value, which a size alone
    // would not show.
    let negative = round_trip[meta.backing_type[Wide]()](-5i64)
    if negative != -5i64 { os.exit(42i32) }

    // --- `array_len` alongside them, since anything walking an array needs both halves.
    if meta.array_len[[7]u8]() != 7usize { os.exit(50i32) }

    // --- The answer as a local's annotation, which is where section 9 says it stands and where
    // the grammar used to refuse it. If it were not a type this would not parse, and if it were
    // the wrong type the assignment would not check.
    var element: meta.element_type[[4]u32]() = zero
    element = 4000000000u32
    if element != 4000000000u32 { os.exit(60i32) }
    // The signed backing of a signed enum, which carries a negative value.
    var below: meta.backing_type[Wide]() = zero
    below = -5i64
    if below != -5i64 { os.exit(61i32) }
    // Nested, in the same position.
    var inner: meta.backing_type[meta.element_type[[2]Level]()]() = zero
    inner = 65535u16
    if inner != 65535u16 { os.exit(62i32) }

    // --- An instantiation whose argument is parenthesised still instantiates.
    var doubled: Doubled[3usize] = zero
    if doubled.inner.values.len != 7usize { os.exit(65i32) }

    // --- The other half of the same parser change: a composite type as a comptime argument
    // where a type is written. `list.List[[]u8]` had never parsed there, for the same reason.
    let (rows, rows_error) = list.init[[]u8](a, 2usize)
    if rows_error != ok { os.exit(70i32) }
    var holder: list.List[[]u8] = zero
    holder = rows
    if list.push[[]u8](&holder, source[..]) != ok { os.exit(71i32) }
    if holder.len != 1usize { os.exit(72i32) }
    if list.slice[[]u8](&holder)[0usize].len != 4usize { os.exit(73i32) }
    ret ok
}
