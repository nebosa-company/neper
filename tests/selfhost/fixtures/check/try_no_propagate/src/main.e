// `try` propagates an err, so the enclosing function must return one.

fn fallible() -> (usize, err) {
    ret (1usize, ok)
}

fn caller() -> usize {
    let v = try fallible()
    ret v
}

fn main() -> err { ret ok }
