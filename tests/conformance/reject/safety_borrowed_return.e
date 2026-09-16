use e.mem
use e.os

// A borrowed handle returned would be the caller's to close: E-SAFETY-0012.
fn again(f: os.File) -> os.File {
    ret f
}

fn main(a: *mem.Arena, args: []str) -> err {
    let out = again(os.stdout())
    ret os.close(out)
}
