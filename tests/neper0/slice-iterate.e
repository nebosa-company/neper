use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    for i, value in args {
        if i == 1usize {
            try io.print(value)
        }
    }
    ret ok
}
