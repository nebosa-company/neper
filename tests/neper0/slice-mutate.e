use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize {
        args[1usize] = "slice mutation ok\n"
        try io.print(args[1usize])
    }
    ret ok
}
