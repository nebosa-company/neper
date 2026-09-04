use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [3]u64{ 1u64, 2u64, 3u64 }
    let invalid = values[2usize..1usize]
    ret ok
}
