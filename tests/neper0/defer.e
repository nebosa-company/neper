use e.io

error DeferredError

type Pair = struct {
    left: i64,
    right: i64,
}

fn add(p: *i64, amount: i64) {
    *p += amount
}

fn step(p: *i64, expected: i64, next: i64) {
    if *p == expected {
        *p = next
    } else {
        *p = -99i64
    }
}

fn fail() -> err {
    ret DeferredError
}

fn return_with_defer(p: *i64) -> i64 {
    defer step(p, 1i64, 2i64)
    defer step(p, 0i64, 1i64)
    ret 44i64
}

fn try_with_defer(p: *i64) -> err {
    defer add(p, 1i64)
    try fail()
    ret ok
}

fn fallible_add(p: *i64, amount: i64) -> err {
    *p += amount
    ret DeferredError
}

fn discard_with_defer(p: *i64) {
    defer let _ = fallible_add(p, 3i64)
}

fn capture_call(p: *i64) {
    var amount = 4i64
    defer add(p, amount)
    amount = 20i64
}

fn capture_block(p: *i64) {
    var amount = 5i64
    defer {
        add(p, amount)
    }
    amount = 6i64
}

fn read_pair(p: *i64, pair: Pair) {
    *p = pair.left + pair.right
}

fn capture_aggregate(p: *i64) {
    var pair = Pair{ left: 7i64, right: 8i64 }
    defer read_pair(p, pair)
    pair.left = 30i64
}

fn aggregate_return_with_defer(p: *i64) -> Pair {
    defer add(p, 1i64)
    ret Pair{ left: 10i64, right: 11i64 }
}

fn single_assignment(p: *i64) {
    defer *p = 8i64
    *p = 7i64
}

fn loop_cleanup(p: *i64) {
    for i in 0usize..3usize {
        defer add(p, 1i64)
        if i == 0usize { continue }
        if i == 1usize { break }
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 0i64
    let returned = return_with_defer(&state)
    if returned != 44i64 { ret ok }
    if state != 2i64 { ret ok }

    state = 0i64
    let failed = try_with_defer(&state)
    if failed != DeferredError { ret ok }
    if state != 1i64 { ret ok }

    state = 0i64
    discard_with_defer(&state)
    if state != 3i64 { ret ok }

    state = 0i64
    capture_call(&state)
    if state != 4i64 { ret ok }

    state = 0i64
    capture_block(&state)
    if state != 6i64 { ret ok }

    state = 0i64
    capture_aggregate(&state)
    if state != 15i64 { ret ok }

    state = 0i64
    let pair = aggregate_return_with_defer(&state)
    if state != 1i64 { ret ok }
    if pair.left != 10i64 { ret ok }
    if pair.right != 11i64 { ret ok }

    single_assignment(&state)
    if state != 8i64 { ret ok }

    state = 0i64
    loop_cleanup(&state)
    if state != 2i64 { ret ok }

    if true {
        defer step(&state, 3i64, 4i64)
        defer step(&state, 2i64, 3i64)
    }
    if state != 4i64 { ret ok }

    try io.print("defer ok")
    ret ok
}
