use e.os

// One side of a partition handed over and the function left (D1566, H01): the
// other side is still owned at the exit, E-SAFETY-0002.
fn drain(files: own []os.File) -> err {
    var i = 0usize
    while i < files.len {
        try os.close(files[i])
        i += 1usize
    }
    ret ok
}

fn split(files: own []os.File, k: usize) -> err {
    let first = drain(files[..k])
    if first != ok { ret first }
    ret ok
}

fn main() -> err { ret ok }
