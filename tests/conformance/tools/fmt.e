// `fmt --json` (D234): canonical layout -- indentation, operator and delimiter spacing,
// comments preserved, blank runs collapsed to one.
use e.mem

const LIMIT: i32 = 10i32

fn classify(value: i32) -> i32 {
    var total = value +% 1i32 // running total
    // negate through a unary operator
    let flipped = -total
    if flipped < 0i32 && total > LIMIT {
        ret total * 2i32
    } else {
        ret flipped
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let n = classify(3i32)
    ret ok
}
