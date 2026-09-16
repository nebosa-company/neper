use e.mem
use e.os

// The bits of a handle read as another handle: a copy, E-SAFETY-0005.
fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    let f = try os.open(a, "np-safety.txt", flags)
    let g = mem.bitcast[os.File](f)
    try os.close(g)
    ret os.close(f)
}
