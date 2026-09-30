// A test that calls the operand's own `main` (D1716): the runner renames every `main` of
// the operand, the declaration and each call, so the test reaches this `main` and not the
// runner's -- which would dispatch the tests again instead.
use e.mem

error Odd

var runs: u32 = 0u32

fn main(a: *mem.Arena, args: []str) -> err {
    runs += 1u32
    ret ok
}

@test
fn calls_main(a: *mem.Arena) -> err {
    var none: [0]str = zero
    if main(a, none[..]) != ok || main(a, none[..]) != ok { ret Odd }
    if runs != 2u32 { ret Odd }
    ret ok
}
