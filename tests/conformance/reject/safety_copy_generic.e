use e.mem
use e.os

// A template that copies its `T` is checked in the instance: over handles it fails
// where the copy is, E-SAFETY-0005, as `mem.copy` does.
fn copy_all[T: type](dst: []T, src: []const T) {
    var at = 0usize
    while at < src.len {
        dst[at] = src[at]
        at += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    var others: [2]os.File = zero
    copy_all[os.File](others[..], files[..])
    ret ok
}
