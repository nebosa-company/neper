use e.mem
use e.os

// Each fixed-array slot retains its own acquisition site for exit diagnostics.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    files[1usize] = try os.dup(os.stdout())
    try os.close(files[1usize])
    ret ok
}
