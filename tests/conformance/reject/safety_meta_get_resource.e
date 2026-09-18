use e.meta
use e.os

type Box = struct { file: os.File }

// Reflectively returning an affine field would copy it out of its owner.
fn main() -> err {
    var box: Box = zero
    for field in meta.fields[Box]() {
        let _ = meta.get[field, Box](&box)
    }
    ret ok
}
