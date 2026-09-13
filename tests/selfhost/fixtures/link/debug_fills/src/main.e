// Section 11's debug fills (D217): `mem.alloc` hands out 0xCD and `mem.reset` gives
// back 0xDD, in debug alone. A read before a write from a fresh allocation sees 0xCD;
// after a mark, an allocation written to 9, and a reset, the same bytes read 0xDD and
// the next allocation of the same bytes 0xCD again. Exit 0 when every read is as
// section 11 says for the mode named by the last argument: `debug`, or `release`,
// where a fresh page reads 0 and the reset leaves the 9s in place.
use e.mem
use e.os
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let release = str.eq(args[args.len - 1usize], "release")
    let (first, first_error) = mem.alloc[u8](a, 64usize)
    if first_error != ok { ret first_error }
    var expected_fresh = 205u8
    if release { expected_fresh = 0u8 }
    if first[0] != expected_fresh || first[63] != expected_fresh { os.exit(10) }
    let m = mem.mark(a)
    let (second, second_error) = mem.alloc[u8](a, 32usize)
    if second_error != ok { ret second_error }
    var i = 0usize
    while i < 32usize {
        second[i] = 9u8
        i += 1usize
    }
    mem.reset(a, m)
    var expected_reset = 221u8
    if release { expected_reset = 9u8 }
    if second[0] != expected_reset || second[31] != expected_reset { os.exit(11) }
    let (third, third_error) = mem.alloc[u8](a, 32usize)
    if third_error != ok { ret third_error }
    var expected_again = 205u8
    if release { expected_again = 9u8 }
    if third[0] != expected_again || third[31] != expected_again { os.exit(12) }
    if first[1] != expected_fresh { os.exit(13) }
    ret ok
}
