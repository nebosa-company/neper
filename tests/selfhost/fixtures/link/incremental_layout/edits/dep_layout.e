// The same record with its fields reordered and one added: the layout changed, the
// function's signature as spelled did not.
type Rec = struct { b: i32, a: i32, c: i64 }

fn make() -> Rec {
    ret Rec { b: 7i32, a: 1i32, c: 0i64 }
}
