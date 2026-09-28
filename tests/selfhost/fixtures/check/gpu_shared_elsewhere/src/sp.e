// Names `shared` only in a local's type, and does not import e.gpu: naming it still
// makes the function device-only (spec section 10), whatever the program imports.
fn plain() -> u32 {
    var s: []shared u32 = zero
    ret u32(s.len) + 1u32
}
