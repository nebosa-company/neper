use e.mem

// A call nested in another's arguments (D1641): with the order `1,0`, `pair(pair(1, 2), 3)`
// is one edit over the outer list with the inner call reordered inside it, so no two edits
// overlap, and the value is still 123.
fn pair(high: i64, low: i64) -> i64 {
    ret high * 10i64 + low
}

fn main(a: *mem.Arena, args: []str) -> err {
    let nested = pair(pair(1i64, 2i64), 3i64)
    if nested != 123i64 { ret mem.Exhausted }
    ret ok
}
