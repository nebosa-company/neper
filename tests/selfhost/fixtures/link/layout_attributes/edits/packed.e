// The records `p` and `q` read. Each edit writes an attribute on a blank line, so no
// function moves and only the attribute differs.

@packed
type P = struct { a: u8, b: i32 }

type Q = struct { a: u8, c: i64, b: i32 }

fn make_p() -> P {
    ret P { a: 1u8, b: 1i32 }
}

fn make_q() -> Q {
    ret Q { a: 1u8, c: 0i64, b: 2i32 }
}
