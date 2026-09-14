// Two tests, one of them failing.
use e.mem

error Odd

fn twice(x: i32) -> i32 {
    ret x + x
}

@test
fn doubles(a: *mem.Arena) -> err {
    if twice(3i32) == 6i32 { ret ok }
    ret Odd
}

@test
fn is_odd(a: *mem.Arena) -> err {
    ret Odd
}
