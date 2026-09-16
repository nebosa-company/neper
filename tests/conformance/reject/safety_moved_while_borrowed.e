use e.io
use e.mem
use e.os

// A writer holds a pointer to the file until this block ends (D351): closing the
// file under it is E-SAFETY-0004. A pointer that is an argument alone pins nothing.
fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: false,
        write: true,
        create: true,
        truncate: true,
        append: false,
    }
    var f = try os.open(a, "np-safety.txt", flags)
    var out = io.file_writer(&f)
    let (n, write_error) = io.write(&out, "hello")
    let close_error = os.close(f)
    if write_error != ok { ret write_error }
    ret close_error
}
