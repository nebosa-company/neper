use e.meta
use e.os

error Failed

fn field_count[T: type]() -> usize {
    var count = 0usize
    for _ in meta.fields[T]() {
        count += 1usize
    }
    ret count
}

// Reflection outside e.os sees a File as an opaque resource with no fields.
fn main() -> err {
    if field_count[os.File]() != 0usize { ret Failed }
    ret ok
}
