// `test --json` on a `@test` that is not a test (D256): E-TEST-9999 at the declaration.
use e.mem

@test
fn takes_no_arena() -> err {
    ret ok
}
