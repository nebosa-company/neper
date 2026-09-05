use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    var bytes: [16384]u8 = zero
    bytes[0usize] = 1u8
    bytes[16383usize] = 2u8
    if bytes[0usize] + bytes[16383usize] == 3u8 {
        try io.print("large stack ok\n")
    } else {
        try io.print("large stack failed\n")
    }
    ret ok
}
