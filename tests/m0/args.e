use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2 {
        try io.print(args[1])
    } else {
        try io.print("bad args")
    }
    ret ok
}
