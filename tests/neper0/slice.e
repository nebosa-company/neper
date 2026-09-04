use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    var values = [5]u16{ 1u16, 2u16, 3u16, 4u16, 5u16 }
    let middle = values[1usize..4usize]
    middle[1usize] = 9u16
    let tail = values[3usize..]
    let prefix = values[..2usize]
    var total: u16 = 0u16
    for value in tail {
        total += value
    }
    if middle.len == 3usize && middle[1usize] == 9u16 && prefix.len == 2usize && total == 9u16 {
        try io.print("slice ok\n")
    } else {
        try io.print("slice failed\n")
    }
    ret ok
}
