use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    if true {
        let hidden: u64 = 1
    }
    let leaked: u64 = hidden
    ret ok
}
