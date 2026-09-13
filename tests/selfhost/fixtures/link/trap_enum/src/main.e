// Section 4's integer-to-enum cast, `Kind(x)`, and section 11's `enum` row, which traps
// in every mode: `color` casts a value no member of an `enum u8` has, `level` one no
// member of an `enum i8` has -- printed signed -- and anything else casts values that
// do name members, including a negative one, and exits 0. The values come from the
// argument count so nothing folds.
use e.mem
use e.str

type Color = enum u8 { Red, Green = 5, Blue }
type Level = enum i8 { Low = -3, Mid = 0, High = 3 }

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    let n = args.len + 5usize
    if str.eq(mode, "color") {
        let c = Color(u8(n))
        if c == .Red { ret ok }
    }
    if str.eq(mode, "level") {
        let l = Level(i8(1i32 - i32(n)))
        if l == .Low { ret ok }
    }
    let fine = Color(u8(n - 1usize))
    if fine != .Blue { ret ok }
    let low = Level(i8(0i32 - i32(n) + 4i32))
    if low != .Low { ret ok }
    ret ok
}
