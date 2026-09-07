// `try` needs a call whose last result is an err.

fn plain() -> usize {
    ret 1usize
}

fn caller() -> err {
    try plain()
    ret ok
}

fn main() -> err { ret ok }
