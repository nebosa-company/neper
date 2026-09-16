// Combined inputs and one input to several declarations (D464, H19): the generator
// read two inputs, both hashed and checked, and one line of the first became two
// declarations, so each diagnostic maps to the one original span.
use e.mem

fn first() -> i32 {
    let n: i32 = true
    ret n
}

fn second() -> i32 {
    let m: i32 = true
    ret m
}

fn main(a: *mem.Arena, args: []str) -> err {
    if first() != second() { ret mem.Exhausted }
    ret ok
}
