use e.mem

type Token = resource(release) struct { slot: usize }

fn release(t: Token) -> err {
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}
