// D330: a local copied from another and then reassigned in the same block. The
// allocator's promotion redirected the copy's later reads to the source when the
// source's local came after the copy's in the function, so `m` read `l` after
// `m = 5`; the use lists keep each local's redirects to its own loads.
use e.io

fn probe(n: usize) -> usize {
    var m = 0usize
    var l = n + 1usize
    m = l
    m = 5usize
    let r = m + l
    ret r
}

fn main() -> err {
    if probe(10usize) != 16usize {
        try io.print("promote copy wrong\n")
        ret ok
    }
    try io.print("promote copy ok\n")
    ret ok
}
