// `e.os` on NeperOS (C107, D2154). `project.select_source` picks this file for a target whose os is
// `neperos`, the way it picks os.linux.e / os.windows.e for those hosts; one module is one file, so
// the type block is a copy of the one in os.e and those variants rather than something shared.
//
// NeperOS is a capability microkernel, not a POSIX host: there is no `os.syscall`. The portable
// primitives the compiler seeds into `e.os` -- open, read, write, close, seek, stdout, stderr,
// exit, the threads, the clock -- are lowered to NeperOS system calls (see src/lower.e, em.e and
// runtime_neperos_a64.s), and resolve unqualified inside this module. This file adds the thin
// surface the portable library modules reach for on top of those: the `_detail` wrappers e.io
// wants, and the error classification. The errors (NotFound, Denied, ...) are seeded by the
// compiler and must not be declared again here. The larger surface (e.fs, e.time wall clock,
// e.thread) lands in later C107 increments.

// The separator this target's paths are written with (e.path asks the host nothing, so a portable
// module learns the convention only from the per-target os file). NeperOS uses '/'.
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
// compiles unchanged. NeperOS classifies little for now: a failed primitive is `Other`.
type ErrorKind = enum u8 { NotFound, Denied, Exists, Interrupted, OutOfMemory, Timeout, WouldBlock, Unsupported, Invalid, Other }
type ErrorDetail = struct { kind: ErrorKind, native_code: i32, operation: str, subject: str }

// Read into `buffer`, recording a detail on failure. A wrapper over the seeded `read` primitive;
// NeperOS has no errno, so the detail carries only the operation.
fn read_detail(f: File, buffer: []u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, read_error) = read(f, buffer)
    if read_error != ok { *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "read", subject: "" } }
    ret (count, read_error)
}

// Write `buffer`, recording a detail on failure. A wrapper over the seeded `write` primitive.
fn write_detail(f: File, buffer: []const u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, write_error) = write(f, buffer)
    if write_error != ok { *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "write", subject: "" } }
    ret (count, write_error)
}
