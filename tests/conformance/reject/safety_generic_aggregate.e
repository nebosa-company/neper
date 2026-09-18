use e.mem
use e.os

type Box[T: type] = struct { value: T }

// The concrete fields classify the generic aggregate (D611): moving Box[File]
// moves its contained file, so the old box cannot be used afterward.
fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: false,
        write: true,
        create: true,
        truncate: true,
        append: false,
    }
    let f = try os.open(a, "np-safety-generic.txt", flags)
    let box = Box[os.File] { value: f }
    let moved = box
    try os.close(moved.value)
    ret os.close(box.value)
}
