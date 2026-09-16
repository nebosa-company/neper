use e.mem
use e.os

// A member a module does not export, within two edits of one it does (D447,
// H09): the diagnostic names the module and the member, the nearest export,
// and offers it as a `maybe` fix over the member's token.
fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags { read: true, write: false, create: false, truncate: false, append: false }
    let (file, open_error) = os.opne(a, "np-no-such-file-anywhere", flags)
    if open_error != ok { ret open_error }
    ret os.close(file)
}
