use e.mem
use e.os

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len != 5usize { ret os.Failed }
    if !same(args[1usize], "alpha beta") || !same(args[2usize], "gamma") { ret os.Failed }
    if !same(args[3usize], "quote\"slash\\tail\\") || args[4usize].len != 0usize { ret os.Failed }
    ret ok
}
