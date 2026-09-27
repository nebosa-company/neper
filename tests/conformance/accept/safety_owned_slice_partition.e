use e.os

// Partitions of owned resources (D1566, H01): an owned slice split at a parameter,
// a fixed array at a runtime bound and at a comptime one, each side handed to an
// `own` slice parameter; the errors are tested once both sides are handed over.
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
    let second = drain(files[k..])
    if first != ok { ret first }
    if second != ok { ret second }
    ret ok
}

fn main() -> err {
    var files: [3]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    files[1usize] = try os.dup(os.stdout())
    files[2usize] = try os.dup(os.stdout())
    let k = files.len - 1usize
    let head = drain(files[0usize..k])
    let tail = drain(files[k..])
    if head != ok { ret head }
    if tail != ok { ret tail }
    var more: [2]os.File = zero
    more[0usize] = try os.dup(os.stdout())
    more[1usize] = try os.dup(os.stdout())
    let front = drain(more[..1usize])
    let back = drain(more[1usize..])
    if front != ok { ret front }
    if back != ok { ret back }
    ret ok
}
