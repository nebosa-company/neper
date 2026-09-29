// An error on the renamed `main`'s own line (T015): the runner renames `main`, so the
// mapping past the rename begins mid-line, and the column moves with it -- `Missing`
// is reported where the operand has it, not where the runner does.
use e.mem

fn main(a: *mem.Arena, args: []str) -> Missing {
    ret ok
}

@test
fn runs(a: *mem.Arena) -> err {
    ret ok
}
