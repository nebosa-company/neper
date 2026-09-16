use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    var f = try os.open(a, "np-safety.txt", flags)
    f = try os.open(a, "np-safety-2.txt", flags)
    ret os.close(f)
}
