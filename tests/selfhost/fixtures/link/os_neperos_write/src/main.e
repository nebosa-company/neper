// NeperOS write-open semantics: a non-truncating writer preserves existing
// bytes, append writes at the current end, and truncate replaces the contents.

use e.io
use e.mem
use e.os

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
    try os.remove_file(a, "np-os-write-contract.txt")
    try io.print("neperos write contract ok\n")
    ret ok
}
