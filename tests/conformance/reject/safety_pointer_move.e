use e.mem
use e.os

// A move through a kept pointer is still a move of the resource (D610). The
// pointer pins the file until this block ends, so the close is E-SAFETY-0004.
fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: false,
        write: true,
        create: true,
        truncate: true,
        append: false,
    }
    var f = try os.open(a, "np-safety-pointer.txt", flags)
    let p = &f
    ret os.close(*p)
}
