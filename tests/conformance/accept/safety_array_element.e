use e.mem
use e.os

// A literal-indexed resource array slot owns the handle stored in it and gives
// that ownership to the consuming close.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [1]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    ret os.close(files[0usize])
}
