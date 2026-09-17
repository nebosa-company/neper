// An `if` over constants alone folds (D500): the comparison of two constants, the
// `&&` of two, and one with a literal are settled by the interpreter, so the arm not
// taken is no code, the same in the checker and the lowering; a condition with a local
// or a call stays a branch. `explain-file` writes a `phase` record per fold.
const LIMIT: usize = 3usize
const FLOOR: usize = 1usize
const ON: bool = true

fn pick(x: usize) -> usize {
    if LIMIT > FLOOR { ret x + 1usize }
    ret x + 100usize
}

fn both(x: usize) -> usize {
    if ON && LIMIT < 10usize { ret x + 2usize }
    ret x + 100usize
}

fn runtime(x: usize) -> usize {
    if x > LIMIT { ret x }
    ret 0usize
}

fn main() -> i32 {
    if pick(0usize) + both(0usize) + runtime(5usize) != 8usize { ret 1i32 }
    ret 0i32
}
