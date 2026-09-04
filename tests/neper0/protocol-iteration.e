use e.mem
use e.io

type Counter = struct {
    current: i64,
    end: i64,
    cleanups: i64,
}

type Pair = struct {
    left: i64,
    right: i64,
}

type PairIter = struct {
    current: i64,
    end: i64,
    cleanups: i64,
}

fn counter_next(it: *Counter) -> (i64, bool) {
    if it.current >= it.end {
        ret (0i64, false)
    }
    let value = it.current
    it.current += 1i64
    defer {
        it.cleanups += 1i64
    }
    ret (value, true)
}

fn pair_iter_next(it: *PairIter) -> (Pair, bool) {
    if it.current >= it.end {
        ret (zero, false)
    }
    let value = it.current
    it.current += 1i64
    defer {
        it.cleanups += 1i64
    }
    ret (Pair{ left: value, right: value + 10i64 }, true)
}

fn success_message() -> str {
    ret "protocol iteration ok\n"
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter = Counter{ current: 1i64, end: 5i64, cleanups: 0i64 }
    var sum = 0i64
    for value in counter {
        sum += value
    }

    var pointed = Counter{ current: 5i64, end: 8i64, cleanups: 0i64 }
    let pointer = &pointed
    for value in pointer {
        sum += value
    }

    var pairs = PairIter{ current: 2i64, end: 4i64, cleanups: 0i64 }
    for pair in pairs {
        sum += pair.left + pair.right
    }

    if sum == 58i64 && counter.current == 5i64 && counter.cleanups == 4i64 && pointed.current == 8i64 && pointed.cleanups == 3i64 && pairs.current == 4i64 && pairs.cleanups == 2i64 {
        try io.print(success_message())
    } else {
        try io.print("protocol iteration failed\n")
    }
    ret ok
}
