use e.os

// The two sides of a partition split at different bounds (D1566, H01): `files[j..]`
// is not what `files[..k]` left, so it is a use of a partly moved slice, E-SAFETY-0001.
fn drain(files: own []os.File) -> err {
    var i = 0usize
    while i < files.len {
        try os.close(files[i])
        i += 1usize
    }
    ret ok
}

fn split(files: own []os.File, k: usize, j: usize) -> err {
    let first = drain(files[..k])
    let second = drain(files[j..])
    if first != ok { ret first }
    if second != ok { ret second }
    ret ok
}

fn main() -> err { ret ok }
