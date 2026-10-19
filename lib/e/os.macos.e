// `e.os` on macOS (aarch64): `project.select_source` picks this file for a target whose os is
// `macos`, the way it picks os.linux.e / os.windows.e / os.neperos.e for those. One module is one
// file, so the type block is a copy of the one in os.e and the other variants.
//
// The primitives the compiler seeds into `e.os` -- open, read, write, close, seek, stdout, stderr,
// exit, args, clock -- are lowered to calls into runtime_macos_a64.s, raw BSD system calls, and
// resolve unqualified inside this module. This file adds the thin surface the portable library
// modules reach for on top of them: the `_detail` wrappers e.io wants. The errors (NotFound,
// Denied, ...) are seeded by the compiler and must not be declared again here. The path and
// process surface (e.fs, e.proc, sockets) lands once libSystem calls back it.

use e.mem

// The separator this target's paths are written with.
const NATIVE_SEPARATOR: u8 = 47u8

type File = struct { raw: usize }
type Proc = struct { raw: usize }
type Thread = struct { raw: usize }
type Clock = enum u8 { Wall, Monotonic }
type SeekWhence = enum u8 { Start, Current, End }
type EntryKind = enum u8 { File, Dir, Symlink, Other }
type DirEntry = struct { name: str, kind: EntryKind }
type OpenFlags = struct { read: bool, write: bool, create: bool, truncate: bool, append: bool }
type Handle = struct { raw: usize }
type Stdio = struct { stdin: File, stdout: File, stderr: File, inherit: []const Handle }

// The same error shapes the other os variants expose, so a portable module's `*os.ErrorDetail`
// compiles unchanged. A failed primitive is `Other` for now.
type ErrorKind = enum u8 { NotFound, Denied, Exists, Interrupted, OutOfMemory, Timeout, WouldBlock, Unsupported, Invalid, Other }
type ErrorDetail = struct { kind: ErrorKind, native_code: i32, operation: str, subject: str }
// The same shapes the other os variants expose, so e.fs's `os.FileInfo`/`os.Dir`/`os.ResolvePolicy`
// compile unchanged.
type FileInfo = struct { kind: EntryKind, size: u64, modified_ns: i64, accessed_ns: i64, created_ns: i64, mode: u32, file_id: u64, link_count: u64 }


// A failed primitive carries only its operation; the runtime hands back the `e.os` error
// code, not the errno, so there is no native code to keep.
fn read_detail(f: File, buffer: []u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, read_error) = read(f, buffer)
    if read_error != ok { *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "read", subject: "" } }
    ret (count, read_error)
}

fn write_detail(f: File, buffer: []const u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, write_error) = write(f, buffer)
    if write_error != ok { *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "write", subject: "" } }
    ret (count, write_error)
}

fn open_detail(a: *mem.Arena, path: str, flags: OpenFlags, detail: *ErrorDetail) -> (File, err) {
    let (file, open_error) = open(a, path, flags)
    if open_error != ok {
        *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "open", subject: path }
        ret (file, open_error)
    }
    ret (file, ok)
}

fn last_error_detail(operation: str, subject: str) -> ErrorDetail {
    ret ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: operation, subject: subject }
}

fn stdin() -> File { ret File { raw: 0usize } }
