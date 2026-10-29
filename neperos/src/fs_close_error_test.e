// A buffered NeperOS file write reaches the filesystem server only on close. The parent below
// does not exist after the fsserver format, so the local write succeeds and the close must return
// the server's failed flush rather than discarding it.
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
    let (file, open_error) = os.open(a, "/missing/close-error", flags)
    if open_error != ok {
        say("fs close error setup failed\n")
    } else {
        let (written, write_error) = os.write(file, "x")
        let close_error = os.close(file)
        if written == 1usize && write_error == ok && close_error == os.Failed {
            say("fs close error propagated\n")
        } else {
            say("fs close error discarded\n")
        }
    }
    let quit = os.send(1usize, fsproto.OP_QUIT, fsproto.NO_SLOT)
    ret ok
}
