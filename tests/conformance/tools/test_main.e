// `test --json` on an operand that defines `main` and carries tests (D281): the runner
// renames the operand's `main` so its own can be the program root.
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
fn after_main(a: *mem.Arena) -> err {
    if twice(4i32) == 8i32 { ret ok }
    ret Odd
}
