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
    ret second_error
}
