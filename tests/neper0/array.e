use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [_]u16{ 1u16, 2u16, 500u16, 4u16 }
    let signed = [3]i16{ -2i16, 4i16, 8i16 }
    var zeros: [3]u8 = zero
    var scratch: [2]u64 = undef
    zeros[1usize] = 7u8
    zeros[1usize] += 2u8
    var total: u16 = 0u16
    for i in 0usize..values.len {
        total += values[i]
    }
    if total == 507u16 && values.len == 4usize && signed[0usize] == -2i16 && zeros[1usize] == 9u8 && zeros[2usize] == 0u8 && scratch.len == 2usize {
        try io.print("array ok\n")
    } else {
        try io.print("array failed\n")
    }
    ret ok
}
