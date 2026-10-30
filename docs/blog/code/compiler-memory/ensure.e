// Asks whether the memory is there before committing to the work.
use e.io
use e.mem
use e.mem.pages

const GIB: usize = 1073741824usize

fn main(a: *mem.Arena, args: []str) -> err {
    if pages.ensure(a, GIB) != ok {
        try io.printf["1 GiB is not there\n"]()
        ret ok
    }
    try io.printf["1 GiB is there\n"]()
    if pages.ensure(a, 512usize * GIB) == mem.Exhausted {
        try io.printf["512 GiB is not: shed the load, and keep running\n"]()
    }
    ret ok
}
