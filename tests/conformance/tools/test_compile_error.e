// `test --json` on a test that does not compile (D264): the compiler's diagnostic comes
// back through the runner's source map at the operand's own span, the generated one related.
use e.mem

@test
fn mistyped(a: *mem.Arena) -> err {
    let wrong: i64 = 1i32
    ret ok
}
