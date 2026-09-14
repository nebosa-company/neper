// `run --json -- ARGS...` (D267): what follows `--` reaches the program as its arguments;
// each is echoed on its own line, and the count is the exit status.
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let out = os.stdout()
    var at = 1usize
    while at < args.len {
        let (put, write_error) = os.write(out, args[at])
        if write_error != ok { ret write_error }
        let (nl, nl_error) = os.write(out, "\n")
        if nl_error != ok { ret nl_error }
        at += 1usize
    }
    os.exit(i32(args.len - 1usize))
    ret ok
}
