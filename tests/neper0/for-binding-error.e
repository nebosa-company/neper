use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [2]u64{ 1u64, 2u64 }
    for value in values {
        value = 3u64
    }
    ret ok
}
