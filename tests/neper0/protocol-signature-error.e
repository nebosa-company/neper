use e.mem

type Counter = struct {
    current: i64,
}

fn counter_next(it: *Counter) -> (i64, i64) {
    ret (0i64, 0i64)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter = Counter{ current: 0i64 }
    for value in counter {
        let _ = value
    }
    ret ok
}
