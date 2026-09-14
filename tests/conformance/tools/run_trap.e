// `run --json` on a program that traps (D252): the record and its backtrace as a payload.
use e.mem

fn pick(values: []const i32, index: usize) -> i32 {
    ret values[index]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var values: [5]i32 = zero
    let chosen = pick(values[..], args.len + 6usize)
    if chosen == 0i32 { ret ok }
    ret ok
}
