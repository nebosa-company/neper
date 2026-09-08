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
const SYS_FCHMODAT: usize = 268usize
const SYS_UTIMENSAT: usize = 280usize
const SYS_SYMLINKAT: usize = 266usize
const SYS_READLINKAT: usize = 267usize
const SYS_GETCWD: usize = 79usize
const SYS_CHDIR: usize = 80usize
const SYS_READ: usize = 0usize
const SYS_CLOSE: usize = 3usize
const SYS_OPENAT: usize = 257usize

// O_RDONLY with O_CLOEXEC, so a spawn between here and there does not inherit it.
const OPEN_READ_ONLY: usize = 524288usize

// O_PATH with O_CLOEXEC: it opens the name and nothing else, so no permission to read is
// needed and a directory opens as readily as a file.
const OPEN_PATH_ONLY: usize = 2621440usize

// O_RDWR with O_CREAT, O_EXCL and O_CLOEXEC: the exclusive bit is what makes creating a
// name and finding out it was taken one operation rather than two.
const OPEN_CREATE_NEW: usize = 524482usize

// 0o600. A file nobody has seen yet belongs to whoever made it.
const CREATE_MODE: usize = 384usize

const SYS_GETRANDOM: usize = 318usize
const SYS_FSYNC: usize = 74usize
const SYS_LINKAT: usize = 265usize
const SYS_RENAMEAT2: usize = 316usize
const SYS_OPENAT2: usize = 437usize

// The flag that makes a rename refuse an existing destination instead of replacing it.
const RENAME_NOREPLACE: usize = 1usize

// O_RDONLY with O_DIRECTORY and O_CLOEXEC, which is how a directory is opened to be
// flushed rather than read.
const OPEN_DIRECTORY: usize = 589824usize

// The resolve flags `openat2` takes, which are the whole reason it is used instead of
// `openat`: the kernel enforces them while it walks, where a check made here would be a
// guess about a path that can change underneath it.
const RESOLVE_NO_SYMLINKS: u64 = 4u64
const RESOLVE_BENEATH: u64 = 8u64

// The access modes and the four bits `OpenFlags` carries.
const O_RDONLY: u64 = 0u64
const O_WRONLY: u64 = 1u64
const O_RDWR: u64 = 2u64
const O_CREAT: u64 = 64u64
const O_TRUNC: u64 = 512u64
const O_APPEND: u64 = 1024u64
const O_CLOEXEC: u64 = 524288u64

// 0o644 for anything this creates, which the umask narrows.
const FILE_MODE: u64 = 420u64

// The kernel caps the environment well below this.
const MAX_ENVIRONMENT: usize = 2097152usize

// A target longer than this is not a link anyone meant to write.
const MAX_LINK_LENGTH: usize = 65536usize

// AT_FDCWD is -100: every path here is relative to the process's own directory, which
// is what the plain `stat`/`mkdir` names mean. It is a `usize` because every argument
// of `os.syscall` is one.
const AT_FDCWD: usize = 18446744073709551516usize
const AT_SYMLINK_NOFOLLOW: usize = 256usize
const AT_REMOVEDIR: usize = 512usize

// 0o777, which the process umask narrows -- the same default a shell `mkdir` gets.
const DIRECTORY_MODE: usize = 511usize

const NANOSECONDS_PER_SECOND: i64 = 1000000000i64

// `UTIME_OMIT` in the nanosecond field of a `timespec` means "leave this stamp alone",
// which is what a negative nanosecond count asks for.
const UTIME_OMIT: i64 = 1073741822i64

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
    // EXDEV: a rename across filesystems, which the kernel will not do at all. EINVAL is
    // the same shape of answer -- the request cannot be honoured as asked, which is what
    // reading a link from something that is not one gets.
    if result == -18isize { ret Unsupported }
    if result == -22isize { ret Unsupported }
    if result == -38isize { ret Unsupported }
    // ELOOP: under `RESOLVE_NO_SYMLINKS` this is a link that was refused, not a cycle.
    if result == -40isize { ret Denied }
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

// What `utimensat` writes: two `timespec`s, the accessed stamp first. The layout is the
// ABI, so the kernel reads 32 bytes at the address this is handed by.
type TimeSpec = struct { seconds: i64, nanoseconds: i64 }
type TimeSpecPair = struct { accessed: TimeSpec, modified: TimeSpec }

fn to_timespec(value: i64) -> TimeSpec {
    var spec: TimeSpec = zero
    if value < 0i64 {
        spec.nanoseconds = UTIME_OMIT
        ret spec
    }
    spec.seconds = value / NANOSECONDS_PER_SECOND
    spec.nanoseconds = value % NANOSECONDS_PER_SECOND
    ret spec
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

// The kernel offers no way to ask how long a link is: `readlinkat` fills what it is given
// and a full buffer cannot be told from an exact fit. `lstat` reports a symbolic link's
// size as the length of its target, so that is the first guess; the buffer doubles from
// there for the filesystems that report zero.
fn read_link(a: *mem.Arena, path: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret ("", path_error)
    }
    let (described, described_error) = lstat(a, path)
    var capacity = 256usize
    if described_error == ok && described.size != 0u64 { capacity = usize(described.size) + 1usize }
    while capacity <= MAX_LINK_LENGTH {
        let (buffer, allocation_error) = mem.alloc[u8](a, capacity)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let written = syscall(SYS_READLINKAT, AT_FDCWD, path_address, mem.address_of(&buffer[0usize]), capacity, 0usize, 0usize)
        if written < 0isize {
            let call_error = from_errno(written)
            mem.reset(a, checkpoint)
            ret ("", call_error)
        }
        // A result shorter than the buffer is the whole of it. The answer and the scratch
        // the search for its length needed both stay in the caller's arena, which is what
        // `mem.mark` around the call is for.
        if usize(written) < capacity { ret (buffer[0usize..usize(written)], ok) }
        capacity = capacity * 2usize
    }
    mem.reset(a, checkpoint)
    ret ("", Failed)
}

// `symlinkat` is the one call here whose directory argument is not first: the target is a
// string the kernel stores rather than a path it resolves, so nothing is relative to
// anything until the link is read.
fn symlink(a: *mem.Arena, target_path: str, link: str) -> err {
    let checkpoint = mem.mark(a)
    let (target_address, target_error) = c_string(a, target_path)
    if target_error != ok {
        mem.reset(a, checkpoint)
        ret target_error
    }
    let (link_address, link_error) = c_string(a, link)
    if link_error != ok {
        mem.reset(a, checkpoint)
        ret link_error
    }
    let result = syscall(SYS_SYMLINKAT, target_address, AT_FDCWD, link_address, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

// `getcwd` fills the buffer and returns what it filled, the terminator included, or
// `-ERANGE` when the buffer is too small -- so unlike `readlinkat` there is no ambiguity
// about a full one and the loop is only about finding a size that fits.
fn current_dir(a: *mem.Arena) -> (str, err) {
    let checkpoint = mem.mark(a)
    var capacity = 256usize
    while capacity <= MAX_LINK_LENGTH {
        let (buffer, allocation_error) = mem.alloc[u8](a, capacity)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let written = syscall(SYS_GETCWD, mem.address_of(&buffer[0usize]), capacity, 0usize, 0usize, 0usize, 0usize)
        // ERANGE, and the only failure a bigger buffer answers.
        if written == -34isize {
            capacity = capacity * 2usize
            continue
        }
        if written < 0isize {
            let call_error = from_errno(written)
            mem.reset(a, checkpoint)
            ret ("", call_error)
        }
        if written == 0isize {
            mem.reset(a, checkpoint)
            ret ("", Failed)
        }
        // The count includes the NUL, which a `str` does not carry.
        ret (buffer[0usize..usize(written) - 1usize], ok)
    }
    mem.reset(a, checkpoint)
    ret ("", Failed)
}

// The kernel keeps the running image as a symbolic link, so this is `read_link` and
// nothing else. What comes back has its links already resolved -- that is what the kernel
// stores, not a choice made here -- and it needs `/proc` mounted, without which it is the
// `NotFound` that any missing path is.
// One NAME=VALUE record at a time. The name has to match to its whole length and end at
// the `=`, or a lookup of `PAT` would be answered by `PATH`.
fn environment_value(block: str, name: str) -> (str, bool) {
    var at = 0usize
    while at < block.len {
        var end = at
        while end < block.len && block[end] != 0u8 { end = end + 1usize }
        if end > at + name.len && block[at + name.len] == 61u8 {
            var matched = true
            var offset = 0usize
            while offset < name.len {
                if block[at + offset] != name[offset] { matched = false }
                offset += 1usize
            }
            if matched { ret (block[at + name.len + 1usize..end], true) }
        }
        at = end + 1usize
    }
    ret ("", false)
}

// The environment the process was started with, which is what `/proc/self/environ` holds:
// NAME=VALUE records separated by NUL bytes. Nothing in this language changes an
// environment, so a snapshot taken at exec is the whole truth.
//
// Every file under `/proc` reports a size of zero, so there is no asking how much to
// allocate: a buffer that filled exactly may have been cut short, and only a short read
// proves the whole of it is here.
fn env(a: *mem.Arena, name: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, "/proc/self/environ")
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret ("", path_error)
    }
    var capacity = 8192usize
    while capacity <= MAX_ENVIRONMENT {
        let (buffer, allocation_error) = mem.alloc[u8](a, capacity)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let descriptor = syscall(SYS_OPENAT, AT_FDCWD, path_address, OPEN_READ_ONLY, 0usize, 0usize, 0usize)
        if descriptor < 0isize {
            let open_error = from_errno(descriptor)
            mem.reset(a, checkpoint)
            ret ("", open_error)
        }
        var filled = 0usize
        var failure = ok
        while filled < capacity {
            let taken = syscall(SYS_READ, usize(descriptor), mem.address_of(&buffer[filled]), capacity - filled, 0usize, 0usize, 0usize)
            if taken < 0isize {
                failure = from_errno(taken)
                break
            }
            if taken == 0isize { break }
            filled += usize(taken)
        }
        let closed = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        if failure != ok {
            mem.reset(a, checkpoint)
            ret ("", failure)
        }
        if filled < capacity {
            let (value, found) = environment_value(buffer[0usize..filled], name)
            if !found {
                mem.reset(a, checkpoint)
                ret ("", NotFound)
            }
            ret (value, ok)
        }
        capacity = capacity * 2usize
    }
    mem.reset(a, checkpoint)
    ret ("", Failed)
}

// A descriptor number as decimal, which is the only formatting this file needs -- and the
// reason it does not reach for `e.str`, since `e.os` may depend on `e.mem` and nothing
// else.
// `getrandom` may return fewer bytes than were asked for, and may be interrupted before
// it returns any, so the loop is not decoration. A zero-length request is not a failure.
fn random(buffer: []u8) -> err {
    var filled = 0usize
    while filled < buffer.len {
        let taken = syscall(SYS_GETRANDOM, mem.address_of(&buffer[filled]), buffer.len - filled, 0usize, 0usize, 0usize, 0usize)
        if taken < 0isize {
            // EINTR: a signal arrived before anything was written, so ask again.
            if taken == -4isize { continue }
            ret from_errno(taken)
        }
        if taken == 0isize { ret Failed }
        filled += usize(taken)
    }
    ret ok
}

// The file must not be there, and finding out is the same operation as creating it. That
// is the whole point: a name checked and then opened is a name something else can take in
// between.
fn create_new(a: *mem.Arena, path: str) -> (File, err) {
    var file: File = zero
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (file, path_error)
    }
    let descriptor = syscall(SYS_OPENAT, AT_FDCWD, path_address, OPEN_CREATE_NEW, CREATE_MODE, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize { ret (file, from_errno(descriptor)) }
    file.raw = usize(descriptor)
    ret (file, ok)
}

fn descriptor_path(a: *mem.Arena, descriptor: usize) -> (str, err) {
    let prefix = "/proc/self/fd/"
    let (bytes, allocation_error) = mem.alloc[u8](a, prefix.len + 20usize)
    if allocation_error != ok { ret ("", OutOfMemory) }
    var at = 0usize
    while at < prefix.len {
        bytes[at] = prefix[at]
        at += 1usize
    }
    var digits: [20]u8 = zero
    var count = 0usize
    var value = descriptor
    if value == 0usize {
        digits[0usize] = 48u8
        count = 1usize
    }
    while value != 0usize {
        digits[count] = 48u8 + u8(value % 10usize)
        value = value / 10usize
        count += 1usize
    }
    var placed = 0usize
    while placed < count {
        bytes[at + placed] = digits[count - 1usize - placed]
        placed += 1usize
    }
    ret (bytes[0usize..at + count], ok)
}

// The kernel resolves a path once and for all when it opens it, and then keeps the result
// where it can be read back. So this is an open and a `read_link` rather than an
// implementation of `realpath`: every symbolic link, `.` and `..` is already gone by the
// time the descriptor exists, and the answer is absolute because the kernel's own record
// of it is.
fn canonical(a: *mem.Arena, path: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret ("", path_error)
    }
    let descriptor = syscall(SYS_OPENAT, AT_FDCWD, path_address, OPEN_PATH_ONLY, 0usize, 0usize, 0usize)
    if descriptor < 0isize {
        let open_error = from_errno(descriptor)
        mem.reset(a, checkpoint)
        ret ("", open_error)
    }
    let (name, name_error) = descriptor_path(a, usize(descriptor))
    if name_error != ok {
        let unused_close = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        mem.reset(a, checkpoint)
        ret ("", name_error)
    }
    // A `/proc` symbolic link reports a fixed size rather than its target's length, so
    // `read_link` finds the real one by growing -- which it already does.
    let (resolved, resolved_error) = read_link(a, name)
    let closed = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
    if resolved_error != ok {
        mem.reset(a, checkpoint)
        ret ("", resolved_error)
    }
    ret (resolved, ok)
}

fn executable_path(a: *mem.Arena) -> (str, err) {
    let (image, image_error) = read_link(a, "/proc/self/exe")
    ret (image, image_error)
}

fn set_current_dir(a: *mem.Arena, path: str) -> err {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret path_error
    }
    let result = syscall(SYS_CHDIR, path_address, 0usize, 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

// `fchmodat` takes no flag this host honours -- it rejects `AT_SYMLINK_NOFOLLOW` rather
// than changing a link's own bits -- so the modifier slot carries the mode itself.
fn set_mode(a: *mem.Arena, path: str, mode: u32) -> err {
    ret path_syscall(a, SYS_FCHMODAT, path, usize(mode & PERMISSION_MASK))
}

// Whether the stamps are kept at all is the filesystem's business: this call succeeds on
// one that stores no times of its own and reading them back is the only way to tell.
fn set_times(a: *mem.Arena, path: str, accessed_ns: i64, modified_ns: i64) -> err {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret path_error
    }
    var times: TimeSpecPair = zero
    times.accessed = to_timespec(accessed_ns)
    times.modified = to_timespec(modified_ns)
    let result = syscall(SYS_UTIMENSAT, AT_FDCWD, path_address, mem.address_of(&times), 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

type Dir = struct { raw: usize }
type ResolvePolicy = enum u8 { NoSymlinks, Beneath }

// `openat2` reads this rather than taking flags in registers, which is what lets it grow
// resolve rules without a new call. The size is passed alongside it and the kernel checks
// both, so the layout is the ABI.
type OpenHow = struct { flags: u64, mode: u64, resolve: u64 }

// A directory-relative path is a name under that directory and nothing else. An absolute
// one would ignore the directory it was given, `..` would leave it, and an embedded NUL
// would make the kernel see a shorter path than the caller wrote -- the classic way a
// check and the thing checked come apart. Each is refused rather than interpreted.
fn relative_path_ok(path: str) -> bool {
    if path.len == 0usize { ret false }
    if path[0usize] == 47u8 { ret false }
    var start = 0usize
    var at = 0usize
    while at < path.len {
        if path[at] == 0u8 { ret false }
        if path[at] == 47u8 {
            if at == start + 2usize && path[start] == 46u8 && path[start + 1usize] == 46u8 { ret false }
            start = at + 1usize
        }
        at += 1usize
    }
    if at == start + 2usize && path[start] == 46u8 && path[start + 1usize] == 46u8 { ret false }
    ret true
}

fn open_bits(flags: OpenFlags) -> u64 {
    var bits = O_RDONLY
    if flags.read && flags.write { bits = O_RDWR }
    if !flags.read && flags.write { bits = O_WRONLY }
    if flags.create { bits = bits | O_CREAT }
    if flags.truncate { bits = bits | O_TRUNC }
    if flags.append { bits = bits | O_APPEND }
    ret bits | O_CLOEXEC
}

fn dir_open(a: *mem.Arena, path: str) -> (Dir, err) {
    var dir: Dir = zero
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (dir, path_error)
    }
    let descriptor = syscall(SYS_OPENAT, AT_FDCWD, path_address, OPEN_DIRECTORY, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize { ret (dir, from_errno(descriptor)) }
    dir.raw = usize(descriptor)
    ret (dir, ok)
}

fn dir_close(dir: Dir) -> err {
    let result = syscall(SYS_CLOSE, dir.raw, 0usize, 0usize, 0usize, 0usize, 0usize)
    ret from_errno(result)
}

// The policy is the kernel's to enforce, not this file's. `RESOLVE_BENEATH` refuses any
// step that would leave the directory, and `RESOLVE_NO_SYMLINKS` refuses any link at all,
// both while the walk is happening -- which is the difference between a guarantee and a
// check made before a path that something else can change.
fn open_at(a: *mem.Arena, dir: Dir, relative_path: str, flags: OpenFlags, policy: ResolvePolicy) -> (File, err) {
    var file: File = zero
    if !relative_path_ok(relative_path) { ret (file, Denied) }
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, relative_path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (file, path_error)
    }
    var how: OpenHow = zero
    how.flags = open_bits(flags)
    // `openat2` insists the mode be zero unless something is being created, and rejects
    // the whole call with EINVAL otherwise -- so this is not a default that can be set
    // once and left.
    if flags.create { how.mode = FILE_MODE }
    how.resolve = RESOLVE_BENEATH
    if policy == .NoSymlinks { how.resolve = RESOLVE_NO_SYMLINKS | RESOLVE_BENEATH }
    let descriptor = syscall(SYS_OPENAT2, dir.raw, path_address, mem.address_of(&how), 24usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize {
        // EXDEV here is the resolve policy refusing a step that would leave the directory,
        // not a device boundary -- a different thing from what `rename` means by it, which
        // is why it is read here rather than in `from_errno`.
        if descriptor == -18isize { ret (file, Denied) }
        ret (file, from_errno(descriptor))
    }
    file.raw = usize(descriptor)
    ret (file, ok)
}

// The directory part of a path, `.` when it has none. Not `e.path`: `e.os` may depend on
// `e.mem` and nothing else, and all this has to find is the last separator.
fn parent_of(path: str) -> str {
    var cut = 0usize
    var at = 0usize
    while at < path.len {
        if path[at] == 47u8 { cut = at }
        at += 1usize
    }
    if cut == 0usize {
        if path.len != 0usize && path[0usize] == 47u8 { ret "/" }
        ret "."
    }
    ret path[0usize..cut]
}

// `fsync` on the file puts its bytes on the disk; `fsync` on the directory puts the name
// there. Both are needed, because a name that survives a crash pointing at bytes that did
// not is worse than losing both.
fn flush_path(a: *mem.Arena, path: str) -> err {
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok { ret path_error }
    let file = syscall(SYS_OPENAT, AT_FDCWD, path_address, OPEN_READ_ONLY, 0usize, 0usize, 0usize)
    if file < 0isize { ret from_errno(file) }
    let flushed = syscall(SYS_FSYNC, usize(file), 0usize, 0usize, 0usize, 0usize, 0usize)
    let file_closed = syscall(SYS_CLOSE, usize(file), 0usize, 0usize, 0usize, 0usize, 0usize)
    if flushed < 0isize { ret from_errno(flushed) }
    let (parent_address, parent_error) = c_string(a, parent_of(path))
    if parent_error != ok { ret parent_error }
    let directory = syscall(SYS_OPENAT, AT_FDCWD, parent_address, OPEN_DIRECTORY, 0usize, 0usize, 0usize)
    if directory < 0isize { ret from_errno(directory) }
    let directory_flushed = syscall(SYS_FSYNC, usize(directory), 0usize, 0usize, 0usize, 0usize, 0usize)
    let directory_closed = syscall(SYS_CLOSE, usize(directory), 0usize, 0usize, 0usize, 0usize, 0usize)
    if directory_flushed < 0isize { ret from_errno(directory_flushed) }
    ret ok
}

// Replacing is what `rename` already does, so the interesting half is refusing to.
// `RENAME_NOREPLACE` is the one call that decides and acts at once, but a filesystem that
// does not know the flag rejects the call rather than the destination -- the 9p mount this
// is tested over is one. The answer there is what every Unix could always do: a hard link
// fails if the name is taken, and the old name goes afterwards. It is two operations, so a
// failure between them leaves both names; the destination still never appears half made,
// which is the guarantee that matters.
fn replace(a: *mem.Arena, src: str, dst: str, overwrite: bool, durable: bool) -> err {
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
    var result = 0isize
    if overwrite {
        result = syscall(SYS_RENAMEAT, AT_FDCWD, from_address, AT_FDCWD, to_address, 0usize, 0usize)
    } else {
        result = syscall(SYS_RENAMEAT2, AT_FDCWD, from_address, AT_FDCWD, to_address, RENAME_NOREPLACE, 0usize)
        // EINVAL, ENOSYS, EOPNOTSUPP: the flag was refused, not the rename.
        if result == -22isize || result == -38isize || result == -95isize {
            result = syscall(SYS_LINKAT, AT_FDCWD, from_address, AT_FDCWD, to_address, 0usize, 0usize)
            if result >= 0isize {
                result = syscall(SYS_UNLINKAT, AT_FDCWD, from_address, 0usize, 0usize, 0usize, 0usize)
            }
        }
    }
    if result < 0isize {
        let call_error = from_errno(result)
        mem.reset(a, checkpoint)
        ret call_error
    }
    var durability = ok
    if durable { durability = flush_path(a, dst) }
    mem.reset(a, checkpoint)
    ret durability
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
