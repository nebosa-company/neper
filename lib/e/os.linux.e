// `e.os` on Linux. D32 makes `e.os` the sole OS surface of `lib/e` and says it is
// written per target: here over raw system calls through the `os.syscall` intrinsic,
// which exists on Linux alone. `project.select_source` picks this file for a Linux
// target, `os.windows.e` for a Windows one, and `lib/e/os.e` for anything else --
// which is also the file the C bootstrap reads, since it knows nothing about variants.
//
// One module is one file, so the type block below is a copy of the one in those two
// files rather than something shared: the language has no way to say otherwise. The
// errors are not declared here at all -- `NotFound` and the rest are seeded by the
// compiler into this module, and declaring them again would be a second `NotFound`.
//
// The functions the compiler supplies as intrinsics -- open, read, write, close, seek,
// readdir, spawn, wait, the threads, the futex, the clock, args, exit -- appear in no
// `.e` file and are not written here either. What is here is what a system call is
// enough for now that `mem.address_of` can hand the kernel an address.

use e.mem

// The separator this target's paths are written with. `e.path` is pure -- it applies
// whatever `Style` it is handed and asks the host nothing -- and no comptime query
// names the target, so a portable module has no other way to learn which convention it
// is running under. It is here because this file is the one that is chosen per target.
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
// `mode` is the POSIX permission bits as the kernel keeps them, and `file_id` is the
// inode: unique with the device, which is what an `e.fs` caller compares two paths by.
// `created_ns` is `-1` here -- `struct stat` has no creation time, and reading one needs
// `statx`, which is a primitive of its own rather than a field of this one.
type FileInfo = struct { kind: EntryKind, size: u64, modified_ns: i64, accessed_ns: i64, created_ns: i64, mode: u32, file_id: u64, link_count: u64 }

// The kernel's `struct stat` for x86-64, field for field. `newfstatat` writes 144
// bytes at the address it is given, so this layout is the ABI rather than a choice --
// every field is here, named or reserved, because the size is part of the contract.
type StatBuffer = struct {
    device: u64,
    inode: u64,
    link_count: u64,
    mode: u32,
    user: u32,
    group: u32,
    padding: u32,
    represented_device: u64,
    size: i64,
    block_size: i64,
    blocks: i64,
    accessed: i64,
    accessed_ns: i64,
    modified: i64,
    modified_ns: i64,
    changed: i64,
    changed_ns: i64,
    reserved0: i64,
    reserved1: i64,
    reserved2: i64,
}

const SYS_NEWFSTATAT: usize = 262usize
const SYS_MKDIRAT: usize = 258usize
const SYS_UNLINKAT: usize = 263usize
const SYS_RENAMEAT: usize = 264usize

// AT_FDCWD is -100: every path here is relative to the process's own directory, which
// is what the plain `stat`/`mkdir` names mean. It is a `usize` because every argument
// of `os.syscall` is one.
const AT_FDCWD: usize = 18446744073709551516usize
const AT_SYMLINK_NOFOLLOW: usize = 256usize
const AT_REMOVEDIR: usize = 512usize

// 0o777, which the process umask narrows -- the same default a shell `mkdir` gets.
const DIRECTORY_MODE: usize = 511usize

const NANOSECONDS_PER_SECOND: i64 = 1000000000i64

// The bits `e.fs.Permissions` is made of, plus setuid, setgid and sticky above them.
// Anything higher in the mode is the format, which `kind` already carries.
const PERMISSION_MASK: u32 = 4095u32

const FORMAT_MASK: u32 = 61440u32
const FORMAT_FILE: u32 = 32768u32
const FORMAT_DIRECTORY: u32 = 16384u32
const FORMAT_SYMLINK: u32 = 40960u32

// A kernel path is NUL-terminated bytes and a neper `str` is a pointer and a length,
// so every call that takes one copies it into the arena first. The caller marks the
// arena and resets it, so the copy lasts exactly as long as the call.
fn c_string(a: *mem.Arena, text: str) -> (usize, err) {
    let (bytes, allocation_error) = mem.alloc[u8](a, text.len + 1usize)
    if allocation_error != ok { ret (0usize, OutOfMemory) }
    var at = 0usize
    while at < text.len {
        bytes[at] = text[at]
        at += 1usize
    }
    bytes[text.len] = 0u8
    ret (mem.address_of(&bytes[0usize]), ok)
}

// The kernel returns its errno negated in the result register. Only the codes the
// fence names are distinguished; everything else is `Failed`, which is what an
// `ErrorDetail` is for once `last_error_detail` exists.
fn from_errno(result: isize) -> err {
    if result >= 0isize { ret ok }
    if result == -1isize { ret Denied }
    if result == -2isize { ret NotFound }
    if result == -4isize { ret Interrupted }
    if result == -11isize { ret WouldBlock }
    if result == -12isize { ret OutOfMemory }
    if result == -13isize { ret Denied }
    if result == -17isize { ret Exists }
    // EXDEV: a rename across filesystems, which the kernel will not do at all.
    if result == -18isize { ret Unsupported }
    if result == -38isize { ret Unsupported }
    ret Failed
}

// S_IFMT is the top four bits of the mode. A socket, a fifo and a device are all
// `Other`: the fence distinguishes only what a directory walk has to act on.
fn kind_from_mode(mode: u32) -> EntryKind {
    let format = mode & FORMAT_MASK
    if format == FORMAT_FILE { ret .File }
    if format == FORMAT_DIRECTORY { ret .Dir }
    if format == FORMAT_SYMLINK { ret .Symlink }
    ret .Other
}

fn stat_with_flags(a: *mem.Arena, path: str, flags: usize) -> (FileInfo, err) {
    var info: FileInfo = zero
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (info, path_error)
    }
    // The buffer is a local, so the kernel writes into this frame and the arena copy
    // of the path is the only thing that has to outlive the call.
    var buffer: StatBuffer = zero
    let result = syscall(SYS_NEWFSTATAT, AT_FDCWD, path_address, mem.address_of(&buffer), flags, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if result < 0isize { ret (info, from_errno(result)) }
    info.kind = kind_from_mode(buffer.mode)
    info.size = u64(buffer.size)
    info.modified_ns = buffer.modified * NANOSECONDS_PER_SECOND + buffer.modified_ns
    info.accessed_ns = buffer.accessed * NANOSECONDS_PER_SECOND + buffer.accessed_ns
    info.created_ns = -1i64
    info.mode = buffer.mode & PERMISSION_MASK
    info.file_id = buffer.inode
    info.link_count = buffer.link_count
    ret (info, ok)
}

fn stat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    let (info, stat_error) = stat_with_flags(a, path, 0usize)
    ret (info, stat_error)
}

// The link itself rather than what it points at, which is the whole difference: a
// dangling symlink has an `lstat` and no `stat`.
fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    let (info, stat_error) = stat_with_flags(a, path, AT_SYMLINK_NOFOLLOW)
    ret (info, stat_error)
}

// `mkdirat` and `unlinkat` have the same shape: the directory a path is relative to,
// the path, and one modifier -- a mode for one, a flag for the other.
fn path_syscall(a: *mem.Arena, number: usize, path: str, modifier: usize) -> err {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret path_error
    }
    let result = syscall(number, AT_FDCWD, path_address, modifier, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

fn mkdir(a: *mem.Arena, path: str) -> err {
    ret path_syscall(a, SYS_MKDIRAT, path, DIRECTORY_MODE)
}

// A symlink is removed as itself: `unlinkat` never follows the final component.
fn remove_file(a: *mem.Arena, path: str) -> err {
    ret path_syscall(a, SYS_UNLINKAT, path, 0usize)
}

fn remove_dir(a: *mem.Arena, path: str) -> err {
    ret path_syscall(a, SYS_UNLINKAT, path, AT_REMOVEDIR)
}

fn rename(a: *mem.Arena, src: str, dst: str) -> err {
    let checkpoint = mem.mark(a)
    let (from_address, from_error) = c_string(a, src)
    if from_error != ok {
        mem.reset(a, checkpoint)
        ret from_error
    }
    let (to_address, to_error) = c_string(a, dst)
    if to_error != ok {
        mem.reset(a, checkpoint)
        ret to_error
    }
    let result = syscall(SYS_RENAMEAT, AT_FDCWD, from_address, AT_FDCWD, to_address, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}
