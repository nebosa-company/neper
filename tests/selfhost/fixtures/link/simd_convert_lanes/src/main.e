// `simd.convert` is lane-wise, not a resize: unequal vectors must stop at its
// explicit contract check instead of leaving result lanes zero or indexing past one.
use e.mem
use e.simd
use e.str

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    if str.eq(mode, "expand") {
        let input = Vec[i64, 2]{ 3i64, 5i64 }
        let output = simd.convert[Vec[i64, 2], Vec[i32, 4]](input)
        if output.lanes[0usize] != 3i32 { ret Failed }
        ret ok
    }
    if str.eq(mode, "narrow") {
        let input = Vec[i32, 4]{ 3i32, 5i32, 7i32, 11i32 }
        let output = simd.convert[Vec[i32, 4], Vec[i64, 2]](input)
        if output.lanes[0usize] != 3i64 { ret Failed }
        ret ok
    }
    let input = Vec[i32, 4]{ -3i32, 5i32, 7i32, 11i32 }
    let output = simd.convert[Vec[i32, 4], Vec[i64, 4]](input)
    if output.lanes[0usize] != -3i64 || output.lanes[3usize] != 11i64 { ret Failed }
    ret ok
}
