use e.mem

// A declared resource with a named cleanup: its `slot` is this module's alone.
type Token = resource(release) struct { slot: usize }

fn acquire(a: *mem.Arena) -> (Token, err) {
    ret (Token { slot: 1usize }, ok)
}

fn release(t: own Token) -> err {
    ret ok
}
