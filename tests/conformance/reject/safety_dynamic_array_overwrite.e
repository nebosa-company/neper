use e.mem
use e.os

// A runtime store may select the live obligated slot and overwrite its handle.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[1usize] = try os.dup(os.stdout())
    let i = args.len % 2usize
    files[i] = os.stdout()
    ret os.close(files[1usize])
}
