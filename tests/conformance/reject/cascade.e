// D950: a check goes on past a failing declaration. What fails because of it -- a
// signature naming its type, a call of it, a local of its type -- is a note under its
// error; a failure of its own is an error, whichever declaration it is in.
use e.mem

type Pair = struct { left: i64, right: Missing }

fn widen(x: Wide) -> i64 {
    ret 0i64
}

fn sum(p: Pair) -> i64 {
    ret p.left
}

fn twice(n: i64) -> i64 {
    ret widen(n) * 2i64
}

fn flag(n: i64) -> bool {
    ret n
}

fn lost(n: i64) -> i64 {
    ret n + nowhere
}

fn main(a: *mem.Arena, args: []str) -> err {
    var p: Pair = zero
    ret ok
}
