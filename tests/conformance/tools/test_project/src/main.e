// `test-project --json` (D263): every module under src, one stream. No tests here.
use e.mem
use helper

fn main(a: *mem.Arena, args: []str) -> err {
    if helper.twice(2i32) == 4i32 { ret ok }
    ret helper.Odd
}
