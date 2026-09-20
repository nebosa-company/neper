// Section 11's arithmetic rows that trap in every mode, each with its record: `zero`
// divides by zero, `rem` takes a remainder by zero, `min` divides the minimum by -1 --
// the quotient two's complement cannot hold, which the check reports before x64 can --
// `shift` shifts by a count past the width and `vshift` a vector's lanes by one. The
// operands come from the argument count so nothing folds; a signed operand prints signed.
use e.mem
use e.simd
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    let n = i32(args.len) - 2i32
    if str.eq(mode, "zero") {
        let q = 7i32 / n
        if q == 3i32 { ret ok }
    }
    if str.eq(mode, "rem") {
        let q = 7u64 % u64(n)
        if q == 3u64 { ret ok }
    }
    if str.eq(mode, "min") {
        let m = -2147483647i32 - 1i32
        let q = m / (n - 1i32)
        if q == 3i32 { ret ok }
    }
    if str.eq(mode, "shift") {
        let s = 1u32 << (u32(n) + 40u32)
        if s == 3u32 { ret ok }
    }
    if str.eq(mode, "vshift") {
        let v = Vec[i32, 4]{ 1i32, 2i32, 3i32, 4i32 }
        let s = (v << (u32(n) + 40u32))[0]
        if s == 3i32 { ret ok }
    }
    let fine = 100i32 / (n + 4i32) + i32(8u32 >> u32(n + 1i32))
    if fine == 99i32 { ret ok }
    ret ok
}
