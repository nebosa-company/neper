use e.mem

type Big = struct {
    a: u64,
    b: u64,
    c: u64,
}

fn mutate(value: Big) {
    value.a = 9u64
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}
