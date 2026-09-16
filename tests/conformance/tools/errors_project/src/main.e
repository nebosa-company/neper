use e.mem
use faults

// An error's uses and rename (D451, H17): three values name the error of
// `faults`, one bare in its own module and two qualified here.
fn main(a: *mem.Arena, args: []str) -> err {
    let first = faults.attempt(args.len > 3usize)
    if first == faults.Stalled { ret first }
    let second = faults.attempt(false)
    if second != ok && second != faults.Stalled { ret second }
    ret ok
}
