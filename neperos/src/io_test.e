// A NeperOS program that prints through e.io (C107, D2154): it reaches the portable e.io surface --
// os.stdout() and a Writer over it -- rather than calling the console primitive directly, proving
// the e.os NeperOS variant (os.neperos.e) lets e.io compile and run unchanged on NeperOS. Started
// as program 0 of a one-program archive on the `-append shell` boot, it prints a line and exits.
use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let print_error = io.print("hello from e.io on neperos\n")
    if print_error != ok { ret print_error }
    let second_error = io.print("e.io writer runs at EL0\n")
    if second_error != ok { ret second_error }
    // e.io in-memory round-trip (D2187): write bytes to a SliceWriter, read them back from a
    // SliceReader over the same buffer -- e.io's buffer Writer/Reader, not just stdout, on NeperOS.
    var buf: [16]u8 = zero
    var ws: io.SliceWriter = io.SliceWriter { data: buf[0usize..16usize], off: 0usize }
    var w = io.slice_writer(&ws)
    var src: [7]u8 = [7]u8{ 110u8, 101u8, 112u8, 101u8, 114u8, 111u8, 115u8 }
    let (wrote, write_err) = io.write(&w, src[0usize..7usize])
    var rs: io.SliceReader = io.SliceReader { data: buf[0usize..ws.off], off: 0usize }
    var r = io.slice_reader(&rs)
    var dst: [16]u8 = zero
    let (got, read_err) = io.read(&r, dst[0usize..7usize])
    var same = wrote == 7usize && got == 7usize
    var ci = 0usize
    while ci < 7usize {
        if dst[ci] != src[ci] { same = false }
        ci += 1usize
    }
    if same {
        let ok_print = io.print("io roundtrip ok\n")
    } else {
        let bad_print = io.print("io roundtrip wrong\n")
    }
    ret ok
}
