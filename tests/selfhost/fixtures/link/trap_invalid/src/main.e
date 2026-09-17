// Section 11's `invalid` row for a representation (D548, D554): `mem.bitcast`
// reading bytes as a `bool` that are not 0 or 1, as an enum whose members they do
// not name, or as a tagged union whose tag names no arm traps in every checked mode;
// the same puns over valid representations exit 0. The values come from the argument
// count so nothing folds.
use e.mem
use e.str

type Color = enum u8 { Red, Green = 5, Blue }
type Maybe = union enum u8 { None, Some: u32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    let n = args.len + 5usize
    if str.eq(mode, "bool") {
        let b = mem.bitcast[bool](u8(n))
        if b { ret ok }
    }
    if str.eq(mode, "color") {
        let c = mem.bitcast[Color](u8(n))
        if c == .Red { ret ok }
    }
    if str.eq(mode, "bool-bytes") {
        let raw = [1]u8{ u8(n) }
        let b = mem.bitcast[bool](raw)
        if b { ret ok }
    }
    if str.eq(mode, "color-bytes") {
        let raw = [1]u8{ u8(n) }
        let c = mem.bitcast[Color](raw)
        if c == .Red { ret ok }
    }
    if str.eq(mode, "union") {
        let raw = [8]u8{ u8(n), 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8 }
        let value = mem.bitcast[Maybe](raw)
        if value.tag == .None { ret ok }
    }
    let fine = mem.bitcast[bool](u8(n - 6usize))
    if !fine { ret ok }
    let blue = mem.bitcast[Color](u8(n - 1usize))
    if blue != .Blue { ret ok }
    let valid_raw = [8]u8{ u8(n - 6usize), 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8 }
    let some = mem.bitcast[Maybe](valid_raw)
    if some.tag != .Some { ret ok }
    ret ok
}
