use e.mem

type Counter = struct {
    current: i64,
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter = Counter{ current: 0i64 }
    for value in counter {
        let _ = value
    }
    ret ok
}
