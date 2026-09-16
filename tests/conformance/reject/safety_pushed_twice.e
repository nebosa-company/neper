use e.mem
use e.os
use e.data.list

// A container's insert takes its element by `own` (D353): a handle pushed is the
// list's, and closing it here is the double ownership H01 refuses, E-SAFETY-0001.
fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    var files = try list.init[os.File](a, 2usize)
    let f = try os.open(a, "np-safety.txt", flags)
    try list.push[os.File](&files, f)
    ret os.close(f)
}
