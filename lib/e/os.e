// neper-0 fixed host surface. The bootstrap compiler supplies these declarations
// and lowers them to bootstrap/runtime.c; general extern-backed e.os lands in M1.
type File = struct { raw: usize }
type Proc = struct { raw: usize }
type Clock = enum u8 { Wall, Monotonic }
type EntryKind = enum u8 { File, Dir, Symlink, Other }
type DirEntry = struct { name: str, kind: EntryKind }
type OpenFlags = struct { read: bool, write: bool, create: bool, truncate: bool, append: bool }
type Handle = struct { raw: usize }
type Stdio = struct { stdin: File, stdout: File, stderr: File, inherit: []const Handle }
