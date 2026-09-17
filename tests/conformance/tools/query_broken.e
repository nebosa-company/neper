// A program that does not check (D520, H08, H18): every query over it is still a
// stream -- its header, the diagnostic, a result of exit 1 -- where `context-file`
// and `uses-file` had written the diagnostic as text on stderr and nothing on
// stdout, which a harness reading JSON could not read.
use e.os

fn helper(n: usize) -> usize {
    ret n + 1usize
}

fn main() -> err {
    let x: i32 = true
    os.exit(i32(helper(2usize)))
    ret ok
}
