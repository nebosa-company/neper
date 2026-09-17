// Section 11's `invalid` row for a representation (D548): `mem.bitcast` reading bytes
// as a `bool` that are not 0 or 1, or as an enum whose members they do not name, traps
// in every checked mode; the same puns over bytes that are a member exit 0. The values
// come from the argument count so nothing folds.
use e.mem
use e.str

type Color = enum u8 { Red, Green = 5, Blue }

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
    let fine = mem.bitcast[bool](u8(n - 6usize))
    if !fine { ret ok }
    let blue = mem.bitcast[Color](u8(n - 1usize))
    if blue != .Blue { ret ok }
    ret ok
}
