use e.mem
use e.os

fn take(f: own os.File) -> err { ret os.close(f) }

fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    let f = try os.open(a, "np-safety.txt", flags)
    try take(f)
    let (n, read_error) = os.read(f, args[0usize][0usize..0usize])
    ret read_error
}
