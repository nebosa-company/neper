use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let zero = args.len - args.len
    let value = 1 / zero
    ret ok
}
