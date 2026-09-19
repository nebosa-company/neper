use e.os

// One runtime element cannot discharge an owned slice's collective obligation.
fn take_one(files: own []os.File, i: usize) -> err {
    ret os.close(files[i])
}

fn main() -> err { ret ok }
