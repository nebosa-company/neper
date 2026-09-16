use e.mem
use e.os

// A parameter not declared `own` is borrowed: closing it is E-SAFETY-0012.
fn peek(f: os.File) -> err {
    ret os.close(f)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    let f = try os.open(a, "np-safety.txt", flags)
    try peek(f)
    ret os.close(f)
}
