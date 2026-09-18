use e.meta
use e.os

type Box = struct { file: os.File }

// Reflectively storing an affine field would copy the supplied identity.
fn main() -> err {
    var box: Box = zero
    for field in meta.fields[Box]() {
        var slot: field.ty = zero
        meta.set[field, Box](&box, slot)
    }
    ret ok
}
