// Masked SIMD offsets must check the enabled lane's logical offset even in a release
// build. `load` and `store` each use lane 1 so `usize.max + 1` cannot silently wrap
// to the first element; `quiet` proves a disabled lane still forms no address.
use e.mem
use e.os
use e.simd
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    var input: [1]u8 = [1]u8{ 42u8 }
    var mask: Mask[u8, 16] = zero
    mask.lanes[1] = true
    var value: Vec[u8, 16] = zero
    value.lanes[1] = 99u8
    var mode = ""
    if args.len > 1usize { mode = args[1usize] }
    if str.eq(mode, "load") {
        let got = simd.load_masked[Vec[u8, 16]](input[..], 0usize -% 1usize, mask)
        if got.lanes[1] == 42u8 { ret ok }
        ret ok
    }
    if str.eq(mode, "store") {
        simd.store_masked[Vec[u8, 16]](input[..], 0usize -% 1usize, mask, value)
        if input[0usize] == 99u8 { ret ok }
        ret ok
    }
    mask.lanes[1] = false
    let quiet = simd.load_masked[Vec[u8, 16]](input[..], 0usize -% 1usize, mask)
    if quiet.lanes[1] != 0u8 || input[0usize] != 42u8 { os.exit(10i32) }
    ret ok
}
