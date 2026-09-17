// A module in a subdirectory: its identity is `nested/deep.e`, its module `nested.deep`;
// it uses a sibling, so the runner is built as part of the project (D263).
use e.mem
use helper

@test
fn holds(a: *mem.Arena) -> err {
    if helper.same[i32](helper.twice(4i32)) == 8i32 { ret ok }
    ret helper.Odd
}
