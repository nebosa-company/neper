// Section 11's trap protocol, the backtrace: after the record, one `  at
// module.function` line per frame from the trapping function up to `main`, walked
// over the rbp chain and named from the symbol table the driver appends after the
// code. The index past the end is computed from the argument count so nothing folds,
// and the call goes through a second module so a frame of each is named. `deeper` is
// small enough to be inlined into `main` (D207), so it is no frame of its own: the
// walk names `helper.pick`, then `main.main`, each with the file and line of the
// instruction its frame is at (D209).
use e.mem
use helper

fn deeper(data: []const u8, at: usize) -> u8 { ret helper.pick(data, at) }

fn main(a: *mem.Arena, args: []str) -> err {
    var buffer: [5]u8 = zero
    let v = deeper(buffer[0..], args.len + 6usize)
    if v == 3u8 { ret ok }
    ret ok
}
