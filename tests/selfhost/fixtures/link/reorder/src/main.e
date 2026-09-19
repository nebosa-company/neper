// `@reorder` (D239): the opt-in that lets the compiler sort a struct's fields by
// descending alignment, declaration order breaking ties, so the padding goes away and
// the layout stays one deterministic function of the type. The default is untouched --
// `Plain` is still section 4's declaration-order C layout -- so the two sizes below are
// the whole point of the attribute. Every field still reads and writes through its own
// offset, including a reordered struct nested inside another.

use e.mem

type Plain = struct {
    tiny: u8,
    value: i64,
    tail: u16,
}

// `value` (8) at 0, `tail` (2) at 8, `tiny` (1) at 10: 11 bytes rounded to 16, where
// declaration order pads `tiny` out to 8 and the whole to 24.
@reorder
type Packed = struct {
    tiny: u8,
    value: i64,
    tail: u16,
}

// `inner` (8) at 0, `count` (4) at 16, `flag` (1) at 20: 21 rounded to 24, where
// declaration order takes 32.
@reorder
type Nested = struct {
    flag: bool,
    inner: Packed,
    count: u32,
}

fn bump(record: *Packed) {
    record.value = record.value + 1i64
    record.tiny = record.tiny + 1u8
}

fn main() -> i64 {
    if mem.size_of[Plain]() != 24usize { ret 1i64 }
    if mem.size_of[Packed]() != 16usize { ret 2i64 }
    if mem.align_of[Packed]() != 8usize { ret 3i64 }
    if mem.size_of[Nested]() != 24usize { ret 4i64 }

    var record = Packed{ tiny: 7u8, value: 35i64, tail: 9u16 }
    if record.tiny != 7u8 || record.value != 35i64 || record.tail != 9u16 { ret 5i64 }
    record.tail = 11u16
    if record.tiny != 7u8 || record.value != 35i64 || record.tail != 11u16 { ret 6i64 }
    bump(&record)
    if record.tiny != 8u8 || record.value != 36i64 || record.tail != 11u16 { ret 7i64 }

    var blank: Packed = zero
    if blank.tiny != 0u8 || blank.value != 0i64 || blank.tail != 0u16 { ret 8i64 }

    var outer = Nested{ flag: true, inner: record, count: 12u32 }
    if !outer.flag || outer.count != 12u32 { ret 9i64 }
    if outer.inner.tiny != 8u8 || outer.inner.value != 36i64 || outer.inner.tail != 11u16 { ret 10i64 }
    outer.inner.value = 40i64
    outer.flag = false
    if outer.flag || outer.count != 12u32 || outer.inner.value != 40i64 { ret 11i64 }
    ret 0i64
}
