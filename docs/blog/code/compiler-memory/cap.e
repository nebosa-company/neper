// Prints the ceiling this program ended up with.
use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    try io.printf["ceiling {} MiB\n"](mem.stats(a).capacity / 1048576usize)
    ret ok
}
