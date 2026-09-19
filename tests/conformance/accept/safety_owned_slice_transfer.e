use e.mem
use e.os

fn drain(files: own []os.File) -> err {
    var i = 0usize
    while i < files.len {
        try os.close(files[i])
        i += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena) -> err {
    var files: [2]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    files[1usize] = try os.dup(os.stdout())
    try drain(files[..])
    ret ok
}
