use e.mem
use e.os

// A runtime consume may have moved either slot, so neither can be consumed again.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    files[1usize] = try os.dup(os.stdout())
    let i = args.len % 2usize
    let dynamic_close = os.close(files[i])
    ret os.close(files[0usize])
}
