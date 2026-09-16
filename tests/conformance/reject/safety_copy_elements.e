use e.mem
use e.os

// `dst[i] = src[j]` over handles is `mem.copy` written out: E-SAFETY-0005.
fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    var files: [2]os.File = zero
    files[0usize] = try os.open(a, "np-safety.txt", flags)
    files[1usize] = files[0usize]
    try os.close(files[1usize])
    ret os.close(files[0usize])
}
