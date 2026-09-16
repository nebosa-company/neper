// `run --json --capture N` (D370, H18): a program whose output is larger than the
// record's bound. The record holds the first N bytes of each stream; the result record
// says how many bytes there were and that the capture is not complete; the whole
// output is in the files beside the executable.
use e.os
fn main() {
    var line = 0usize
    while line < 8usize {
        let (written, write_error) = os.write(os.stdout(), "0123456789abcdefghijklmnopqrstuvwxyz\n")
        line += 1usize
    }
    let (err_written, err_error) = os.write(os.stderr(), "a short warning\n")
    os.exit(0i32)
}
