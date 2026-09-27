use e.os

// A partition bound that can change between the sides (D1566, H01): a `var` names
// no partition, so the first side is a partial move, E-SAFETY-0003.
fn drain(files: own []os.File) -> err {
    var i = 0usize
    while i < files.len {
        try os.close(files[i])
        i += 1usize
    }
    ret ok
}

fn split(files: own []os.File, k: usize) -> err {
    var at = k
    let first = drain(files[..at])
    at = 0usize
    let second = drain(files[at..])
    if first != ok { ret first }
    if second != ok { ret second }
    ret ok
}

fn main() -> err { ret ok }
