use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let marker: u64 = 99
    if marker == 99u64 && args.len == 2 {
        try io.print(args[1])
    } else {
        try io.print("bad args")
    }
    ret ok
}
