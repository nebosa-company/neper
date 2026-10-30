// (D5935) Windows: a kernel call cannot fault a page in, and a fresh arena allocation has no
// pages. `&buffer[0]` handed to an import through a writable pointer is touched by the compiler,
// so this `ReadFile` into a slice nothing has written works. Before, in a release build, it
// failed with ERROR_NOACCESS; a debug build's fill hid that, so the suite builds this --release.
// `recv`, `ReadDirectoryChangesW` and the rest are the same case.
use e.mem
use e.os

@import("kernel32.dll", "ReadFile")
extern fn raw_read_file(file: usize, buffer: *u8, size: u32, read: *u32, overlapped: usize) -> i32

const BYTES: usize = 8388608usize

error ReadFailed
error NothingRead
error WrongBytes

@unsafe
fn handle_of(f: *const os.File) -> usize { ret f.raw }

fn main(a: *mem.Arena, args: []str) -> err {
    let path = "import-touch.bin"
    let (content, content_error) = mem.alloc[u8](a, 65536usize)
    if content_error != ok { ret content_error }
    content[0usize] = 77u8
    let (buffer, buffer_error) = mem.alloc[u8](a, BYTES)
    if buffer_error != ok { ret buffer_error }

    var options: os.OpenFlags = zero
    options.write = true
    options.create = true
    options.truncate = true
    let (out, out_error) = os.open(a, path, options)
    if out_error != ok { ret out_error }
    let (wrote, write_error) = os.write(out, content)
    let out_closed = os.close(out)
    if write_error != ok { ret write_error }
    if wrote != content.len || out_closed != ok { ret ReadFailed }

    var reading: os.OpenFlags = zero
    reading.read = true
    let (f, open_error) = os.open(a, path, reading)
    if open_error != ok { ret open_error }
    var got = 0u32
    let status = raw_read_file(handle_of(&f), &buffer[0usize], u32(BYTES), &got, 0usize)
    let closed = os.close(f)
    let removed = os.remove_file(a, path)
    if status == 0i32 { ret ReadFailed }
    if got == 0u32 { ret NothingRead }
    if buffer[0usize] != 77u8 { ret WrongBytes }
    ret ok
}
