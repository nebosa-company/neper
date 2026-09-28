// The records `p` and `q` read. Each edit writes an attribute on a blank line, so no
// function moves and only the attribute differs; this one makes `P` a resource, whose
// fields only this module may read (D348).
@align(16)
@packed
type P = resource(drop_p) struct { a: u8, b: i32 }
@reorder
type Q = struct { a: u8, c: i64, b: i32 }

fn make_p() -> P {
    ret P { a: 1u8, b: 1i32 }
}

fn make_q() -> Q {
    ret Q { a: 1u8, c: 0i64, b: 2i32 }
}

fn drop_p(v: own P) {
}
