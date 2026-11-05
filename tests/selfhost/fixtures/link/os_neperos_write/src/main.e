// NeperOS write-open semantics: a non-truncating writer preserves existing
// bytes, append writes at the current end, and truncate replaces the contents.

use e.io
use e.mem
use e.os
use e.str

fn put(a: *mem.Arena, payload: str, read: bool, create: bool, truncate: bool, append: bool) -> err {
    var flags: os.OpenFlags = zero
    flags.read = read
    flags.write = true
    flags.create = create
    flags.truncate = truncate
    flags.append = append
    let (file, open_error) = os.open(a, "np-os-write-contract.txt", flags)
    if open_error != ok { ret open_error }
    var holder = file
    let (written, write_error) = os.write(holder, payload)
    let close_error = os.close(holder)
    if write_error != ok { ret write_error }
    if close_error != ok { ret close_error }
    if written != payload.len { ret os.Failed }
    ret ok
}

fn expect(a: *mem.Arena, want: str) -> err {
    var flags: os.OpenFlags = zero
    flags.read = true
    let (file, open_error) = os.open(a, "np-os-write-contract.txt", flags)
    if open_error != ok { ret open_error }
    var holder = file
    var buffer: [64]u8 = zero
    let (count, read_error) = os.read(holder, buffer[..])
    let close_error = os.close(holder)
    if read_error != ok { ret read_error }
    if close_error != ok { ret close_error }
    if count != want.len { ret os.Failed }
    var i = 0usize
    while i < want.len {
        if buffer[i] != want[i] { ret os.Failed }
        i += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let removed = os.remove_file(a, "np-os-write-contract.txt")
    if removed != ok && removed != os.NotFound { ret removed }
    try put(a, "abc", false, true, true, false)
    try put(a, "X", false, false, false, false)
    try expect(a, "Xbc")
    try put(a, "!", true, false, false, true)
    try expect(a, "Xbc!")
    try put(a, "z", false, false, true, false)
    try expect(a, "z")
    // #108: a write larger than the client buffer is refused, not truncated
    // with an ok status; the file keeps its earlier content.
    try put(a, "abc", false, false, true, false)
    let (big_builder, big_error) = str.builder(a, 600usize)
    if big_error != ok { os.exit(101i32) }
    var big = big_builder
    var bi = 0usize
    while bi < 600usize {
        try str.push_byte(&big, 97u8)
        bi += 1usize
    }
    var wflags: os.OpenFlags = zero
    wflags.write = true
    let (wfile, wopen_error) = os.open(a, "np-os-write-contract.txt", wflags)
    if wopen_error != ok { os.exit(102i32) }
    var wholder = wfile
    let (bign, big_write_error) = os.write(wholder, str.done(&big))
    if big_write_error != os.Failed || bign != 0usize { os.exit(103i32) }
    if os.close(wholder) != ok { os.exit(104i32) }
    try expect(a, "abc")
    // #108: opening a missing file for read fails at open, and a seek past
    // the end is refused instead of reporting a position.
    var rflags: os.OpenFlags = zero
    rflags.read = true
    let (missing, missing_error) = os.open(a, "np-os-write-contract-absent.txt", rflags)
    if missing_error != os.NotFound { os.exit(12i32) }
    let (rfile, ropen_error) = os.open(a, "np-os-write-contract.txt", rflags)
    if ropen_error != ok { os.exit(13i32) }
    var rholder = rfile
    let (_, past_end) = os.seek(rholder, 5i64, os.SeekWhence.Start)
    if past_end != os.Failed { os.exit(13i32) }
    if os.close(rholder) != ok { os.exit(13i32) }
    try os.remove_file(a, "np-os-write-contract.txt")
    try io.print("neperos write contract ok\n")
    ret ok
}
