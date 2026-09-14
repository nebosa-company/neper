// A test after the operand's `main` that does not compile (D281): the map's second
// mapping, past the rename, brings the diagnostic back to the operand's own span.
use e.mem

error Odd

fn twice(x: i32) -> i32 {
    ret x + x
}

fn main(a: *mem.Arena, args: []str) -> err {
    if twice(2i32) == 4i32 { ret ok }
    ret Odd
}

@test
fn doubles(a: *mem.Arena) -> err {
    if twice(3i32) == 6i32 { ret ok }
    ret Odd
}

@test
fn mistyped_after_main(a: *mem.Arena) -> err {
    let wrong: i64 = 1i32
    ret ok
}
