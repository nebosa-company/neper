// A NeperOS filesystem client that checks its bounded, client-side file cursor. Each invalid
// seek must fail without changing the cursor, then the client asks the filesystem server to exit.
use e.mem
use e.os
use fsproto

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, "/seek", flags)
    if open_error != ok {
        say("fs seek setup failed\n")
    } else {
        let (written, write_error) = os.write(file, "hello world")
        let (_, before_start_error) = os.seek(file, 0i64 - 1i64, os.SeekWhence.Start)
        let (_, before_current_error) = os.seek(file, 0i64 - 12i64, os.SeekWhence.Current)
        let (_, before_end_error) = os.seek(file, 0i64 - 12i64, os.SeekWhence.End)
        let (_, over_capacity_error) = os.seek(file, 513i64, os.SeekWhence.Start)
        let (_, huge_current_error) = os.seek(file, 9223372036854775807i64, os.SeekWhence.Current)
        let (_, minimum_start_error) = os.seek(file, 0i64 - 9223372036854775807i64 - 1i64, os.SeekWhence.Start)
        let (position, position_error) = os.seek(file, 0i64, os.SeekWhence.Current)
        if written == 11usize && write_error == ok && before_start_error != ok && before_current_error != ok && before_end_error != ok && over_capacity_error != ok && huge_current_error != ok && minimum_start_error != ok && position_error == ok && position == 11u64 {
            say("fs seek bounds ok\n")
        } else {
            say("fs seek bounds failed\n")
        }
        let close_error = os.close(file)
    }
    let quit = os.send(1usize, fsproto.OP_QUIT, fsproto.NO_SLOT)
    ret ok
}
