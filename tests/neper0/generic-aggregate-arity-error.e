use e.mem

type Buffer[T: type, N: usize] = struct {
    values: [N]T,
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buffer: Buffer[i64] = zero
    ret ok
}
