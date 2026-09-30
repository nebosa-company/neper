// An error after two calls of the operand's `main` on one line (D1716): each renamed call
// is a seam in the runner's map, so the error is reported at the operand's own column.
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}

@test
fn mistyped_after_calls(a: *mem.Arena) -> err {
    var none: [0]str = zero
    if main(a, none[..]) == ok && main(a, none[..]) == ok { let wrong: i64 = 1i32 }
    ret ok
}
