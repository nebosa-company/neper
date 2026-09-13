// `run --json` (D231): a program whose stdout, stderr and exit status the harness reads
// out of one record. The stderr line carries a byte that is not UTF-8, so it is base64.
use e.os
fn main() {
    let (out_written, out_error) = os.write(os.stdout(), "hello from run\n")
    let (err_written, err_error) = os.write(os.stderr(), "warn \xff\n")
    os.exit(3i32)
}
