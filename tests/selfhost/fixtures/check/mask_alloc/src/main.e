// Section 4: a `Mask[T, N]` is register-only -- not an allocation's element.
use e.mem
use e.simd

fn run(a: *mem.Arena) -> err {
    let masks = try mem.alloc[Mask[f32, 4]](a, 4usize)
    ret ok
}
