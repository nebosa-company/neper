// A literal with the wrong number of fields. Inside a `for`, this used to be reported
// as "multiple binding count does not match function results": the diagnostic was
// guessed from the statement the error happened in rather than from the error.

type Bad = struct {
    a: usize,
}

fn main() -> err {
    var xs: [3]usize = zero
    for x in xs[..] {
        let b = Bad { a: 1usize, a: 2usize }
    }
    ret ok
}
