// A lowering worker's references start again at its mark for every module (D1664). At
// `-j 1` one worker lowers `a`, `b` and `c` in that order: `a` calls `x.fixed`, `b`
// lowers no function and names no reference, and `c` calls `x.widened`, whose reference
// lands on the index `a`'s had. The used marks `a` left must be gone before `c`'s
// artifact records its edges: a warm build after `edits/x.e` widens `x.widened`'s
// result rebuilds `c` as `edge-changed`, exits 0 and is the clean build. With `a`'s
// marks left set, `c`'s artifact had no edge to `x.widened`, and the warm build kept it.
use a
use b
use c

fn main() -> i64 {
    ret a.run() + c.run() - b.BASE
}
