// A loop, an accumulator and a formatted line. The format string is checked at compile time.

use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    var total: u64 = 0
    for i in 0u64..10 {
        total += i*i
    }
    try io.printf["sum of the squares below 10: {}\n"](total)
    ret ok
}
