// An aggregate a dependent's body reads through a signature (D493, H14): `main`
// reads `.b` of what `make` returns; a change to the fields' order is a change to
// the layout `main`'s body was lowered against, so `main` must be rebuilt.
type Rec = struct { a: i32, b: i32 }

fn make() -> Rec {
    ret Rec { a: 1i32, b: 7i32 }
}
