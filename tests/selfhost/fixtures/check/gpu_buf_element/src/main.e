// Section 10 (D1589): `usize` is 32 bits on the device, so no buffer holds one.
use e.gpu

fn make(q: *gpu.Queue) -> err {
    let (buf, alloc_error) = gpu.alloc[usize](q, 16usize)
    if alloc_error != ok { ret alloc_error }
    ret ok
}
