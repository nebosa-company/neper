// Provenance through inlining in a diagnostic (D1528): with selection made to fail
// at a copied instruction two bodies deep, the release build's diagnostic names the
// source that holds it -- `deep.inner`, under its own module -- the function it was
// inlined into and the body it came through.
use deep
use e.os

fn main() -> err {
    var bytes: [2]u8 = zero
    os.exit(i32(deep.outer(bytes[..], 1usize)))
    ret ok
}
