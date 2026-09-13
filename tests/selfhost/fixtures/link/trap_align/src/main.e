// Section 11's `align` row: `simd.load_aligned` and `store_aligned` at an address
// that is not a multiple of the vector's width trap in debug. The lanes start at the
// first 32-byte boundary inside a larger array, so an offset of four floats is aligned
// for a four-lane vector and an offset of one or two is not; `load` reads at one and
// `store` writes at two, each with a record naming the width, and anything else does
// both at aligned offsets and exits 0. The offsets come from the argument count so
// nothing folds.
use e.mem
use e.simd
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    var raw: [16]f32 = zero
    let base = mem.address_of(&raw[0])
    let skew = (32usize - base % 32usize) % 32usize / 4usize
    var data = raw[skew..skew + 8usize]
    var i = 0usize
    while i < 8usize {
        data[i] = f32(i)
        i += 1usize
    }
    var off = 4usize
    if args.len > 100usize { off = 0usize }
    var at = off
    if str.eq(mode, "load") { off = 1usize }
    if str.eq(mode, "store") { at = 2usize }
    let v = simd.load_aligned[Vec[f32, 4]](data[0..], off)
    if v.lanes[0] != f32(off) { ret ok }
    let w = simd.splat[Vec[f32, 4]](9.0)
    simd.store_aligned[Vec[f32, 4]](data[0..], at, w)
    if data[at] != 9.0 || data[at + 3usize] != 9.0 { ret ok }
    ret ok
}
