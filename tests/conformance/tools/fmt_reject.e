// `fmt --json` on what it refuses (D257): an invalid token under its lexical code, and a
// comment between an attribute and its declaration under E-FORMAT-9999.
use e.mem

@test
// the attribute is no longer adjacent
fn holds(a: *mem.Arena) -> err {
    let price = 3 $ 4
    ret ok
}
