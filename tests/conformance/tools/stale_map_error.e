// A stale source map beside an operand that does not compile (D300): E-TOOL-0001 first,
// then the module's own diagnostic at its unmapped span, exit 1 and no artifact.
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let n: i32 = true
    ret ok
}
