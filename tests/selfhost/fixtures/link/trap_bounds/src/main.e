// Section 11's trap protocol: a check that fires writes one record to stderr --
// `file:line:col: trap[kind]: values`, the shape of a compiler diagnostic -- and exits
// 134. The last argument picks the check: `index` reads past a slice, `slice` cuts one
// past its end, and anything else trips nothing and exits 0. The runner compares the
// record text and the exit code; the index and length are computed from the arguments
// so the compiler cannot fold the check away.
use e.mem
use e.str

fn pick(data: []const u8, at: usize) -> u8 { ret data[at] }

fn cut(data: []const u8, upper: usize) -> usize {
    let part = data[1usize..upper]
    ret part.len
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buffer: [5]u8 = zero
    buffer[1usize] = 9u8
    let mode = args[args.len - 1usize]
    let over = args.len + 5usize
    if str.eq(mode, "index") {
        let v = pick(buffer[0..], over)
        if v == 3u8 { ret ok }
    }
    if str.eq(mode, "slice") {
        let n = cut(buffer[0..], over)
        if n == 3usize { ret ok }
    }
    ret ok
}
