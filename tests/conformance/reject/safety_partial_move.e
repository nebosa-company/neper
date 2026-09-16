use e.mem
use e.os

type Pair = struct { left: os.File, right: os.File }

fn take(p: own Pair) -> err {
    let left_closed = os.close(p.left)
    let right_closed = os.close(p.right)
    if left_closed != ok { ret left_closed }
    ret right_closed
}

fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    let left = try os.open(a, "np-safety.txt", flags)
    let (right, right_error) = os.open(a, "np-safety.txt", flags)
    if right_error != ok {
        let dropped = os.close(left)
        ret right_error
    }
    let pair = Pair { left: left, right: right }
    let left_closed = os.close(pair.left)
    ret take(pair)
}
