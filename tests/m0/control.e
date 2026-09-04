use e.mem
use e.io

fn twice(n: i64) -> i64 {
    ret n * 2
}

fn main(a: *mem.Arena, args: []str) -> err {
    let answer: i64 = twice(21)
    if answer == 42 {
        try io.print("control ok\n")
    } else {
        try io.print("control failed\n")
    }
    ret ok
}
