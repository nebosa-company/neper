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
    let f = try os.open(a, "np-safety.txt", flags)
    var at = 0usize
    while at < args.len {
        if at == 1usize { try os.close(f) }
        at += 1usize
    }
    ret ok
}
