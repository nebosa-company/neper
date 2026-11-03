use e.algo.coding as coding
use e.mem

fn main(a: *mem.Arena) -> err {
    var out: [16]u8 = zero
    var writer = coding.bit_writer(out[..])
    let e = coding.write_bits(&writer, 0u64, 65u32)
    if e != coding.Invalid { ret coding.Invalid }
    ret ok
}
