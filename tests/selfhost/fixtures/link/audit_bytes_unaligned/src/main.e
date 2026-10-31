use e.bytes
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var source: [34]u8 = zero
    var dest: [34]u8 = zero
    var i = 0usize
    while i < source.len {
        source[i] = u8(i + 1usize)
        i += 1usize
    }
    let copied = bytes.copy(dest[1usize..17usize], source[1usize..17usize])
    if copied != 16usize { os.exit(1i32) }
    i = 0usize
    while i < 16usize {
        if dest[1usize + i] != source[1usize + i] { os.exit(2i32) }
        i += 1usize
    }
    ret ok
}
