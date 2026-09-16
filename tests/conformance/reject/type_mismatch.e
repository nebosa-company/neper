use e.mem

// A mismatch names both types (D401, H09): the message says what was expected and
// what was found, and the record carries them as `expected` and `actual`.
fn take(value: i32) -> i32 {
    ret value
}

fn main(a: *mem.Arena, args: []str) -> err {
    let widened: u64 = 1u64
    let taken = take(widened)
    if taken != 1i32 { ret mem.Exhausted }
    ret ok
}
