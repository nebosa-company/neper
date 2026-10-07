// A NeperOS program that uses the portable e.fs over the C106 filesystem server (C107, D2158):
// it writes a file and reads it back through fs.write_file / fs.read_file, which reach os.open,
// os.write, os.stat, os.read and os.close -- the e.os NeperOS variant routes those to the server
// over IPC (request endpoint slot 1, reply slot 2, the caps the filesystem-server boot grants a
// client). Started as program 1 of the fsserver archive; it ends by telling the server to quit so
// the kernel powers off.
use e.mem
use e.os
use e.io
use e.fs

fn say(text: str) {
    let print_error = io.print(text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let content = "e.fs on neperos\n"
    let (buffer, buffer_error) = mem.alloc[u8](a, content.len)
    if buffer_error != ok { ret buffer_error }
    var i = 0usize
    while i < content.len {
        buffer[i] = content[i]
        i += 1usize
    }
    let write_error = fs.write_file(a, "/hello", buffer)
    if write_error != ok { say("fs write_file failed\n") } else { say("fs write_file ok\n") }
    let (data, read_error) = fs.read_file(a, "/hello", 512usize)
    if read_error != ok {
        say("fs read_file failed\n")
    } else {
        say("fs read_file: ")
        say(data)
    }
    // Quit the server (op 0 on the request endpoint) so, with every process exited, the kernel
    // powers off.
    let quit = os.send(1usize, 0usize, 99usize)
    ret ok
}
