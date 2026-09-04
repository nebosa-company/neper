use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    for i, value in args[1usize..] {
        if i == 0usize {
            try io.print(value)
        }
    }
    ret ok
}
