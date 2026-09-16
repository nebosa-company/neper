use e.mem

type Token = resource(release) struct { slot: usize }

fn acquire(a: *mem.Arena) -> (Token, err) {
    ret (Token { slot: 1usize }, ok)
}

fn value(t: Token) -> usize {
    ret t.slot
}

fn release(t: own Token) -> err {
    ret ok
}
