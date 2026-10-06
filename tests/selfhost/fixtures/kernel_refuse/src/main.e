// (D2126) The machine intrinsics exist on aarch64-none alone: anywhere else `os.mrs` is
// an unknown member, refused where it is written.
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let control = os.mrs(49280usize)
    if control == 0usize { ret mem.Exhausted }
    ret ok
}
