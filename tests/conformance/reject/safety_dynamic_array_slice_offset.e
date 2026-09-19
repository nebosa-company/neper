use e.mem
use e.os

// A runtime-offset slice alias may still select any owner slot at its first index.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    files[1usize] = try os.dup(os.stdout())
    let start = args.len % 2usize
    let tail = files[start..]
    let again = tail
    let first_close = os.close(files[0usize])
    ret os.close(again[0usize])
}
