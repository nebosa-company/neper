use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [2]u32{ 10u32, 20u32 }
    let value = values[2usize]
    ret ok
}
