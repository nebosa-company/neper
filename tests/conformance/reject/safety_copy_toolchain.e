use e.mem
use e.os

// A resource copied inside a toolchain module (D427): the diagnostic lands in
// lib/e/mem.e when `mem.copy` is instantiated over `os.File`, and its span names
// the module under its root -- `toolchain-lib`, or `project-lib` when the
// repository itself is the project, as the suite runs it -- not a basename under
// `operand`.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    var copies: [2]os.File = zero
    mem.copy[os.File](copies[..], files[..])
    ret ok
}
