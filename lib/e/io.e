// Bootstrap-compatible output over the fixed e.os surface.
use e.mem
use e.os
use e.str

fn print(s: []const u8) -> err {
    let output = os.stdout()
    var written = 0usize
    while written < s.len {
        let (count, write_error) = os.write(output, s[written..])
        if write_error != ok { ret write_error }
        if count == 0usize { ret os.Failed }
        written += count
    }
    ret ok
}
