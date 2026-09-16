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
    var buffer: [4]u8 = zero
    let (n, read_error) = os.read(f, buffer[..])
    if read_error != ok { ret read_error }
    ret os.close(f)
}
