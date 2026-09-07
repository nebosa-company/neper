// A field whose type is a generic instantiation reached through an alias. The first
// `collect_aliases` pass runs before any aggregate is registered, so `BoxU` cannot
// resolve there; the field type keeps the alias name and canonicalises at use, once
// the second pass has resolved it. `lead` and `tail` bracket the instance so a wrong
// size or offset for it shows up as a wrong value, not just a wrong type.

error Failed

type Box[T: type] = struct { v: T, w: T }
type BoxU = Box[u32]
type BoxI = Box[i64]
type Holder = struct { lead: u32, slot: BoxU, wide: BoxI, tail: u32 }

fn total(b: BoxU) -> u32 {
    ret b.v + b.w
}

fn main() -> err {
    var h: Holder = zero
    h.lead = 1u32
    h.slot.v = 2u32
    h.slot.w = 3u32
    h.wide.v = 4i64
    h.wide.w = 5i64
    h.tail = 6u32
    if h.lead != 1u32 { ret Failed }
    if h.slot.v != 2u32 || h.slot.w != 3u32 { ret Failed }
    if h.wide.v != 4i64 || h.wide.w != 5i64 { ret Failed }
    if h.tail != 6u32 { ret Failed }
    let copy = h.slot
    if copy.v != 2u32 || copy.w != 3u32 { ret Failed }
    if total(h.slot) != 5u32 { ret Failed }
    ret ok
}
