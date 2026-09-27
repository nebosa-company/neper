// Every position `try` may take (D1567, spec "Where `try` may appear"): a binding of
// one result and of two, an assignment of one and of two, and the whole statement,
// in a function answering more than its `err`. Each failure returns the error beside
// zero values and runs the deferred call once; `main` binds one too.
error Nope

type Pair = struct { a: usize, b: usize }

fn one(fail: bool) -> (usize, err) {
    if fail { ret (0usize, Nope) }
    ret (7usize, ok)
}

fn two(fail: bool) -> (usize, Pair, err) {
    if fail { ret (0usize, zero, Nope) }
    ret (3usize, Pair { a: 4usize, b: 5usize }, ok)
}

fn plain(fail: bool) -> err {
    if fail { ret Nope }
    ret ok
}

var deferred_runs: usize = 0usize

fn note() { deferred_runs += 1usize }

fn forms(fail_at: usize) -> (usize, Pair, err) {
    defer note()
    let x = try one(fail_at == 1usize)
    var (y, pair) = try two(fail_at == 2usize)
    var z = 0usize
    z = try one(fail_at == 3usize)
    (y, pair) = try two(fail_at == 4usize)
    try plain(fail_at == 5usize)
    ret (x + y + z + pair.a, pair, ok)
}

fn main() -> err {
    let (total, pair, all_ok) = forms(0usize)
    if all_ok != ok || total != 21usize || pair.b != 5usize { ret Nope }
    var at = 1usize
    while at <= 5usize {
        let (failed_total, failed_pair, failed) = forms(at)
        if failed != Nope || failed_total != 0usize || failed_pair.a != 0usize || failed_pair.b != 0usize { ret Nope }
        at += 1usize
    }
    if deferred_runs != 6usize { ret Nope }
    let v = try one(false)
    if v != 7usize { ret Nope }
    ret ok
}
