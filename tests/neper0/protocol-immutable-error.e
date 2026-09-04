use e.mem

type Counter = struct {
    current: i64,
}

fn counter_next(it: *Counter) -> (i64, bool) {
    ret (0i64, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let counter = Counter{ current: 0i64 }
    for value in counter {
        let _ = value
    }
    ret ok
}
