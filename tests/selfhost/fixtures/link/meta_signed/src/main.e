// `meta.signed[T]()` (D782): a folded question -- `link/gpu_tensor` shows the arm an
// unsigned type cannot reach is not the instance's code -- and a value at run time;
// a float is signed, `usize` is not.

use e.io
use e.mem
use e.meta
use e.os

fn tag[T: type]() -> u32 {
    if meta.signed[T]() { ret 1u32 } else { ret 2u32 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    if tag[i8]() != 1u32 || tag[u16]() != 2u32 || tag[f32]() != 1u32 || tag[usize]() != 2u32 || tag[isize]() != 1u32 { os.exit(2i32) }
    let asked = meta.signed[i32]()
    if !asked || meta.signed[u64]() { os.exit(3i32) }
    try io.print("meta signed ok\n")
    ret ok
}
