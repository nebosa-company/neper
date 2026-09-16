use e.mem

// A field the struct does not declare, within two edits of one it does (D448,
// H09): the diagnostic names the type and the field at the member's token, the
// nearest field, and offers it as a `maybe` fix.
type Point = struct { x: i64, depth: i64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let p = Point { x: 1i64, depth: 2i64 }
    let sum = p.x + p.dept
    if sum != 3i64 { ret mem.Exhausted }
    ret ok
}
