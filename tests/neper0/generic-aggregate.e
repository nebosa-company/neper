use e.mem
use e.io

type Buffer[T: type, N: usize] = struct {
    values: [N]T,
    used: usize,
}

fn last[T: type, N: usize](buffer: *Buffer[T, N]) -> T {
    ret buffer.values[buffer.used - 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buffer: Buffer[i64, 3] = zero
    buffer.values[0usize] = 5i64
    buffer.values[1usize] = 8i64
    buffer.values[2usize] = 13i64
    buffer.used = 3usize
    var initialized = Buffer[i64, 3]{ values: [3]i64{ 21i64, 34i64, 55i64 }, used: 3usize }
    if buffer.values.len == 3usize && last[i64, 3](&buffer) == 13i64 && last[i64, 3](&initialized) == 55i64 {
        try io.print("generic aggregate ok\n")
    } else {
        try io.print("generic aggregate failed\n")
    }
    ret ok
}
