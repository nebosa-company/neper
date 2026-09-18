use e.mem
use e.os

// A literal-indexed resource array slot is consumed once, like a resource local.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [1]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    try os.close(files[0usize])
    ret os.close(files[0usize])
}
