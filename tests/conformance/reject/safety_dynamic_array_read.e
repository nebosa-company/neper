use e.mem
use e.os

// A runtime index may select the fixed-array slot already consumed above.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    files[1usize] = try os.dup(os.stdout())
    let first_close = os.close(files[0usize])
    let i = args.len % 2usize
    ret os.close(files[i])
}
