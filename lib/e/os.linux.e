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
const SYS_WRITE: usize = 1usize
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
const SYS_SOCKET: usize = 41usize
const SYS_CONNECT: usize = 42usize
const SYS_SENDTO: usize = 44usize
const SYS_RECVFROM: usize = 45usize
const SYS_SHUTDOWN: usize = 48usize
const SYS_BIND: usize = 49usize
const SYS_LISTEN: usize = 50usize
const SYS_GETSOCKNAME: usize = 51usize
const SYS_SETSOCKOPT: usize = 54usize
const SYS_GETTID: usize = 186usize
const SYS_MMAP: usize = 9usize
const SYS_NANOSLEEP: usize = 35usize
const SYS_KILL: usize = 62usize
const SYS_FLOCK: usize = 73usize
const SYS_DUP2: usize = 33usize
const SYS_FORK: usize = 57usize
const SYS_EXECVE: usize = 59usize
const SYS_SETPGID: usize = 109usize
const SYS_EXIT_GROUP: usize = 231usize
const SYS_PIPE2: usize = 293usize
const SYS_MUNMAP: usize = 11usize
const SYS_MSYNC: usize = 26usize
const SYS_INOTIFY_ADD_WATCH: usize = 254usize
const SYS_INOTIFY_INIT1: usize = 294usize
const SYS_FCNTL: usize = 72usize
const SYS_ACCEPT4: usize = 288usize
const SYS_EPOLL_WAIT: usize = 232usize
const SYS_EPOLL_CTL: usize = 233usize
const SYS_EVENTFD2: usize = 290usize
const SYS_EPOLL_CREATE1: usize = 291usize

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

const AF_INET: usize = 2usize
const AF_INET6: usize = 10usize
const SOCK_STREAM: usize = 1usize
const SOCK_DGRAM: usize = 2usize

// Every socket this opens is close-on-exec, for the same reason every file is.
const SOCK_CLOEXEC: usize = 524288usize

const F_GETFL: usize = 3usize
const F_SETFL: usize = 4usize
const O_NONBLOCK: usize = 2048usize

const PROT_READ: usize = 1usize
const PROT_WRITE: usize = 2usize
const MAP_SHARED: usize = 1usize

// The flag that puts a mapping exactly where it is told, replacing whatever was there.
const MAP_FIXED: usize = 16usize

const MS_SYNC: usize = 4usize

// The same bit as `O_CLOEXEC`, which is a `u64` here because `openat2` reads its flags from a
// structure while every other call takes them in a register. Each API names it for itself,
// which is what the several spellings of 524288 in this file are.
const PIPE_CLOEXEC: usize = 524288usize

// The signal that cannot be caught or ignored, which is what `kill` means here.
const SIGKILL: usize = 9usize
const SIGTERM: usize = 15usize

// What a child exits with when the program it was told to become could not be reached. The
// shell's number for the same thing, so it is not a new convention to learn.
const EXEC_FAILED: usize = 127usize

// ponytail: an argument or environment list longer than this is refused rather than growing
// the arrays; a caller with more than a thousand of either is doing something this is not for.
const SPAWN_LIST_MAX: usize = 1024usize

const LOCK_SH: usize = 1usize
const LOCK_EX: usize = 2usize
const LOCK_NB: usize = 4usize
const LOCK_UN: usize = 8usize

// ponytail: a timeout is polled, because neither host offers one -- ten milliseconds between
// tries, which is a compromise between waking up for nothing and waiting past the deadline.
// A host call that took a deadline would replace the loop entirely.
const LOCK_POLL_NS: i64 = 10000000i64

// The page size for this architecture. Every syscall number in this file already pins it to
// x86-64, where the base page is four kilobytes whatever else the kernel maps in larger ones,
// so there is nothing to ask -- and no way to ask without reading the startup stack, which a
// library does not have.
const PAGE_SIZE: usize = 4096usize

const IN_CLOEXEC: usize = 524288usize

// What a change to a directory's contents looks like: something appeared, went, was written
// to, or was moved in or out. The two move halves are reported separately, which is why a
// rename arrives as a removal and an addition rather than as one event.
const IN_MODIFY: u32 = 2u32
const IN_MOVED_FROM: u32 = 64u32
const IN_MOVED_TO: u32 = 128u32
const IN_CREATE: u32 = 256u32
const IN_DELETE: u32 = 512u32
const IN_Q_OVERFLOW: u32 = 16384u32
const WATCH_MASK: usize = 962usize

// ponytail: one read takes at most this much at a time, so a burst larger than it arrives
// across successive reads rather than being lost.
const WATCH_BUFFER: usize = 8192usize

const EPOLL_CLOEXEC: usize = 524288usize
const EFD_CLOEXEC: usize = 524288usize

const EPOLL_CTL_ADD: usize = 1usize
const EPOLL_CTL_DEL: usize = 2usize
const EPOLL_CTL_MOD: usize = 3usize

const EPOLLIN: u32 = 1u32
const EPOLLOUT: u32 = 4u32
const EPOLLERR: u32 = 8u32
const EPOLLHUP: u32 = 16u32
const EPOLLRDHUP: u32 = 8192u32

// The largest `usize`, used as the token of the poller's own wake descriptor. A caller
// that hands this in as a token of its own will not see those events, which is the one
// value it may not use.
const WAKE_TOKEN: usize = 18446744073709551615usize

// ponytail: one wait returns at most this many at a time, because the buffer it reads into
// is a frame local; a caller asking for more gets them across successive waits.
const POLL_BATCH: usize = 64usize

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
fn current_thread_id() -> usize {
    let answer = syscall(SYS_GETTID, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if answer < 0isize { ret 0usize }
    ret usize(answer)
}

// The same classification `from_errno` makes, as the enum the fence names. The two are written
// apart because one answers with an `err` a caller matches on and the other with a kind a caller
// prints, and neither is derivable from the other.
fn error_kind_of(code: i32) -> ErrorKind {
    if code == 1i32 { ret .Denied }
    if code == 2i32 { ret .NotFound }
    if code == 4i32 { ret .Interrupted }
    if code == 11i32 { ret .WouldBlock }
    if code == 12i32 { ret .OutOfMemory }
    if code == 17i32 { ret .Exists }
    if code == 22i32 { ret .Invalid }
    if code == 38i32 { ret .Unsupported }
    if code == 110i32 { ret .Timeout }
    ret .Other
}

// Section 5's per-thread error detail, which is the one piece of ambient state `e.os` keeps.
// `docs/modules.md` names it an explicit exception rather than an invisible guarantee, and D109
// spells out that H07 is chartered to delete it -- so it is written to be replaceable and to fail
// by saying nothing rather than by saying something another thread's.
//
// A slot per thread, keyed by the thread's own identifier. `e.os` may depend on `e.mem` and
// nothing else (docs/modules.json), so there are no atomics to claim a slot with; two threads
// whose identifiers land on the same slot overwrite each other. That is why a read requires the
// identifier to match exactly and answers `Other` with no code when it does not: a detail that is
// absent costs a caller a diagnostic, and one belonging to another thread costs it the truth.
//
// ponytail: sixty-four slots, no eviction, no atomics. A program with more live threads than that
// loses details it would otherwise keep, which is a diagnostic and never a wrong answer. Real
// thread-local storage would replace the whole of it, and H07 is where that belongs.
const ERROR_SLOTS: usize = 64usize

var error_slot_thread: [64]usize
var error_slot_code: [64]i32
var error_slot_used: [64]u8

// The code is written first and the identifier last, so a reader that sees its own identifier is
// looking at a slot whose code was already stored. Without atomics that is the most that can be
// said, and it is enough for the only failure that matters here.
fn record_error_detail(code: i32) {
    let thread = current_thread_id()
    let slot = thread % ERROR_SLOTS
    error_slot_code[slot] = code
    error_slot_used[slot] = 1u8
    error_slot_thread[slot] = thread
}

fn last_error_detail(operation: str, subject: str) -> ErrorDetail {
    var detail: ErrorDetail = zero
    detail.kind = .Other
    detail.operation = operation
    detail.subject = subject
    let thread = current_thread_id()
    let slot = thread % ERROR_SLOTS
    // Another thread's slot, or one nothing has written, is no detail at all.
    if error_slot_used[slot] == 0u8 { ret detail }
    if error_slot_thread[slot] != thread { ret detail }
    let code = error_slot_code[slot]
    detail.native_code = code
    detail.kind = error_kind_of(code)
    ret detail
}

fn from_errno(result: isize) -> err {
    if result >= 0isize { ret ok }
    // Every failing syscall in this file is classified here, which is why the detail is kept here
    // and not at forty call sites.
    record_error_detail(i32(0isize - result))
    if result == -1isize { ret Denied }
    if result == -2isize { ret NotFound }
    if result == -4isize { ret Interrupted }
    if result == -11isize { ret WouldBlock }
    if result == -12isize { ret OutOfMemory }
    if result == -13isize { ret Denied }
    if result == -17isize { ret Exists }
    // EADDRINUSE: a name already taken, which is what `Exists` means for a path too.
    if result == -98isize { ret Exists }
    if result == -110isize { ret Timeout }
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
fn environment_bytes(a: *mem.Arena) -> (str, err) {
    let (path_address, path_error) = c_string(a, "/proc/self/environ")
    if path_error != ok { ret ("", path_error) }
    var capacity = 8192usize
    while capacity <= MAX_ENVIRONMENT {
        let (buffer, allocation_error) = mem.alloc[u8](a, capacity)
        if allocation_error != ok { ret ("", OutOfMemory) }
        let descriptor = syscall(SYS_OPENAT, AT_FDCWD, path_address, OPEN_READ_ONLY, 0usize, 0usize, 0usize)
        if descriptor < 0isize { ret ("", from_errno(descriptor)) }
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
        if failure != ok { ret ("", failure) }
        if filled < capacity { ret (buffer[0usize..filled], ok) }
        capacity = capacity * 2usize
    }
    ret ("", Failed)
}

fn env(a: *mem.Arena, name: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (block, block_error) = environment_bytes(a)
    if block_error != ok {
        mem.reset(a, checkpoint)
        ret ("", block_error)
    }
    let (value, found) = environment_value(block, name)
    if !found {
        mem.reset(a, checkpoint)
        ret ("", NotFound)
    }
    ret (value, ok)
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

type Watch = struct { state: *void }
type WatchAction = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type WatchEvent = struct { action: WatchAction, path: str, old_path: str }

// `struct inotify_event`: sixteen bytes and then the name, whose length the header carries
// and which the kernel pads so the next one starts aligned. The four fields are all
// four-byte, so this needs no padding of its own.
type InotifyHeader = struct { descriptor: i32, mask: u32, cookie: u32, name_length: u32 }

// What a watch remembers: the descriptor to read from, and the directory it is watching --
// because the kernel reports a name relative to that and `WatchEvent` wants a path.
type WatchState = struct { descriptor: usize, base: str }

fn watch_open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err) {
    var watch: Watch = zero
    // A recursive watch here is a watch per directory plus a table mapping each descriptor
    // back to its path, and adding one whenever a directory appears. Until that is written
    // this refuses, rather than watching only the top and looking like it did more.
    if recursive { ret (watch, Unsupported) }
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (watch, path_error)
    }
    let descriptor = syscall(SYS_INOTIFY_INIT1, IN_CLOEXEC, 0usize, 0usize, 0usize, 0usize, 0usize)
    if descriptor < 0isize {
        mem.reset(a, checkpoint)
        ret (watch, from_errno(descriptor))
    }
    let added = syscall(SYS_INOTIFY_ADD_WATCH, usize(descriptor), path_address, WATCH_MASK, 0usize, 0usize, 0usize)
    if added < 0isize {
        let call_error = from_errno(added)
        let unused = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        mem.reset(a, checkpoint)
        ret (watch, call_error)
    }
    let (holder, holder_error) = mem.alloc[WatchState](a, 1usize)
    if holder_error != ok {
        let unused = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (watch, OutOfMemory)
    }
    holder[0usize].descriptor = usize(descriptor)
    holder[0usize].base = path
    watch.state = mem.cast[*void](&holder[0usize])
    ret (watch, ok)
}

fn action_from_mask(mask: u32) -> WatchAction {
    if mask & IN_Q_OVERFLOW != 0u32 { ret .Overflow }
    if mask & IN_CREATE != 0u32 { ret .Added }
    if mask & IN_MOVED_TO != 0u32 { ret .Added }
    if mask & IN_DELETE != 0u32 { ret .Removed }
    if mask & IN_MOVED_FROM != 0u32 { ret .Removed }
    ret .Modified
}

// The name and the watched directory joined, in the caller's arena. The separator is written
// here rather than through `e.path`, which `e.os` may not depend on.
fn watch_path(a: *mem.Arena, base: str, name: str) -> (str, err) {
    let (bytes, allocation_error) = mem.alloc[u8](a, base.len + 1usize + name.len)
    if allocation_error != ok { ret ("", OutOfMemory) }
    var at = 0usize
    while at < base.len {
        bytes[at] = base[at]
        at += 1usize
    }
    if at != 0usize && bytes[at - 1usize] != 47u8 {
        bytes[at] = 47u8
        at += 1usize
    }
    var offset = 0usize
    while offset < name.len {
        bytes[at + offset] = name[offset]
        offset += 1usize
    }
    ret (bytes[0usize..at + name.len], ok)
}

// One read returns as many whole events as fit, and the kernel never splits one, so the walk
// is over a buffer that always ends on a boundary.
fn watch_read(a: *mem.Arena, w: Watch, events: []WatchEvent) -> (usize, err) {
    let state = mem.cast[*WatchState](w.state)
    if events.len == 0usize { ret (0usize, ok) }
    let (buffer, allocation_error) = mem.alloc[u8](a, WATCH_BUFFER)
    if allocation_error != ok { ret (0usize, OutOfMemory) }
    let taken = syscall(SYS_READ, state.descriptor, mem.address_of(&buffer[0usize]), WATCH_BUFFER, 0usize, 0usize, 0usize)
    if taken < 0isize { ret (0usize, from_errno(taken)) }
    var produced = 0usize
    var at = 0usize
    while at + 16usize <= usize(taken) {
        let header = mem.cast[*InotifyHeader](&buffer[at])
        let name_length = usize(header.name_length)
        let mask = header.mask
        at += 16usize
        // The name is NUL-padded inside the length the header gave, so its own end is the
        // first NUL rather than that length.
        var name_end = 0usize
        while name_end < name_length && buffer[at + name_end] != 0u8 { name_end += 1usize }
        if produced < events.len {
            var entry: WatchEvent = zero
            entry.action = action_from_mask(mask)
            if name_end != 0usize {
                let (joined, join_error) = watch_path(a, state.base, buffer[at..at + name_end])
                if join_error != ok { ret (produced, join_error) }
                entry.path = joined
            } else {
                entry.path = state.base
            }
            events[produced] = entry
            produced += 1usize
        }
        at += name_length
    }
    ret (produced, ok)
}

fn watch_close(w: Watch) -> err {
    let state = mem.cast[*WatchState](w.state)
    ret from_errno(syscall(SYS_CLOSE, state.descriptor, 0usize, 0usize, 0usize, 0usize, 0usize))
}

type Mapping = struct { raw: usize, address: *u8, len: usize }

// `raw` carries whether the mapping may be written and nothing else. This host needs no
// handle to keep a mapping alive, and the other closes its mapping object as soon as the
// view exists, so the field is free -- and something has to remember, because
// `mapping_bytes_mut` must refuse rather than let a write fault.
const MAPPING_READ_ONLY: usize = 0usize
const MAPPING_WRITABLE: usize = 1usize

// A file mapping has to arrive as a `*u8`, and `mmap` answers with an address. D96 leaves no
// way from one to the other, so the pointer comes from `os.reserve` -- which returns a real
// one over a `PROT_NONE` region -- and `MAP_FIXED` then replaces that reservation with the
// file at the same address. The pointer already held is the mapping afterwards, so nothing
// has to invent one and this host needs no assembly of its own.
//
// The offset is the caller's to page-align; the kernel refuses anything else.
fn map_file(f: File, offset: u64, len: usize, writable: bool) -> (Mapping, err) {
    var mapping: Mapping = zero
    if len == 0usize { ret (mapping, Failed) }
    let (address, reserve_error) = reserve(len)
    if reserve_error != ok { ret (mapping, reserve_error) }
    var protection = PROT_READ
    if writable { protection = PROT_READ | PROT_WRITE }
    let placed = syscall(SYS_MMAP, mem.address_of(address), len, protection, MAP_SHARED | MAP_FIXED, f.raw, usize(offset))
    if placed < 0isize {
        let unused = syscall(SYS_MUNMAP, mem.address_of(address), len, 0usize, 0usize, 0usize, 0usize)
        ret (mapping, from_errno(placed))
    }
    mapping.raw = MAPPING_READ_ONLY
    if writable { mapping.raw = MAPPING_WRITABLE }
    mapping.address = address
    mapping.len = len
    ret (mapping, ok)
}

// `mem.view` is the one operation that turns a base pointer and a length into a slice, which
// is the whole reason an `Arena` is built here: not to allocate out of, but because naming a
// region is what an `Arena` is and `view` is the only thing that will describe one.
fn mapping_region(m: Mapping) -> []u8 {
    var region: mem.Arena = zero
    region.base = m.address
    region.cap = m.len
    region.off = 0usize
    ret mem.view(&region, 0usize, m.len)
}

fn mapping_bytes(m: Mapping) -> []const u8 {
    ret mapping_region(m)
}

// A mapping opened for reading refuses rather than handing back a slice whose first write
// would fault: the refusal is an error a caller can act on and the fault is not.
fn mapping_bytes_mut(m: Mapping) -> ([]u8, err) {
    var nothing: []u8 = zero
    if m.raw != MAPPING_WRITABLE { ret (nothing, Unsupported) }
    ret (mapping_region(m), ok)
}

fn mapping_flush(m: Mapping) -> err {
    ret from_errno(syscall(SYS_MSYNC, mem.address_of(m.address), m.len, MS_SYNC, 0usize, 0usize, 0usize))
}

fn mapping_close(m: Mapping) -> err {
    ret from_errno(syscall(SYS_MUNMAP, mem.address_of(m.address), m.len, 0usize, 0usize, 0usize, 0usize))
}

type Poller = struct { state: *void }
type PollInterest = struct { readable: bool, writable: bool }
type PollEvent = struct { token: usize, readable: bool, writable: bool, closed: bool, failed: bool }

// The kernel's `struct epoll_event` is **packed** on this architecture: the 64-bit datum
// follows the 32-bit mask with no padding between them, so the whole thing is twelve bytes
// and not sixteen. Writing the datum as two halves is what keeps that true -- a `u64` field
// here would be eight-byte aligned and every entry after the first would be read from the
// wrong offset.
type RawPollEvent = struct { events: u32, token_low: u32, token_high: u32 }

// What a poller retains: the set is the kernel's, and this is the pair of descriptors that
// reaches it. It lives in the arena the poller was opened with.
type PollerState = struct { epoll: usize, wake: usize }

fn interest_mask(interest: PollInterest) -> u32 {
    var mask = 0u32
    if interest.readable { mask = mask | EPOLLIN }
    if interest.writable { mask = mask | EPOLLOUT }
    // A peer that closed is worth hearing about whatever was asked for: a caller waiting to
    // read would otherwise wait for a write that will never come.
    ret mask | EPOLLRDHUP
}

fn control_epoll(state: *PollerState, operation: usize, handle: Handle, token: usize, interest: PollInterest) -> err {
    var raw: RawPollEvent = zero
    raw.events = interest_mask(interest)
    raw.token_low = u32(token % 4294967296usize)
    raw.token_high = u32(token / 4294967296usize)
    ret from_errno(syscall(SYS_EPOLL_CTL, state.epoll, operation, handle.raw, mem.address_of(&raw), 0usize, 0usize))
}

fn poller_open(a: *mem.Arena) -> (Poller, err) {
    var poller: Poller = zero
    let epoll = syscall(SYS_EPOLL_CREATE1, EPOLL_CLOEXEC, 0usize, 0usize, 0usize, 0usize, 0usize)
    if epoll < 0isize { ret (poller, from_errno(epoll)) }
    let wake = syscall(SYS_EVENTFD2, 0usize, EFD_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
    if wake < 0isize {
        let unused = syscall(SYS_CLOSE, usize(epoll), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (poller, from_errno(wake))
    }
    let (holder, holder_error) = mem.alloc[PollerState](a, 1usize)
    if holder_error != ok {
        let unused_wake = syscall(SYS_CLOSE, usize(wake), 0usize, 0usize, 0usize, 0usize, 0usize)
        let unused_epoll = syscall(SYS_CLOSE, usize(epoll), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (poller, OutOfMemory)
    }
    holder[0usize].epoll = usize(epoll)
    holder[0usize].wake = usize(wake)
    var wake_handle: Handle = zero
    wake_handle.raw = usize(wake)
    var wake_interest: PollInterest = zero
    wake_interest.readable = true
    let register_error = control_epoll(&holder[0usize], EPOLL_CTL_ADD, wake_handle, WAKE_TOKEN, wake_interest)
    if register_error != ok {
        let unused_wake = syscall(SYS_CLOSE, usize(wake), 0usize, 0usize, 0usize, 0usize, 0usize)
        let unused_epoll = syscall(SYS_CLOSE, usize(epoll), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (poller, register_error)
    }
    poller.state = mem.cast[*void](&holder[0usize])
    ret (poller, ok)
}

fn poller_register(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    ret control_epoll(mem.cast[*PollerState](p.state), EPOLL_CTL_ADD, handle, token, interest)
}

fn poller_modify(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    ret control_epoll(mem.cast[*PollerState](p.state), EPOLL_CTL_MOD, handle, token, interest)
}

fn poller_unregister(p: Poller, handle: Handle) -> err {
    var nothing: PollInterest = zero
    ret control_epoll(mem.cast[*PollerState](p.state), EPOLL_CTL_DEL, handle, 0usize, nothing)
}

// One eight-byte write is what an event descriptor counts, and one read drains it however
// many wakes arrived, so a burst of them costs one wakeup rather than one each.
fn poller_wake(p: Poller) -> err {
    let state = mem.cast[*PollerState](p.state)
    var one: [8]u8 = zero
    one[0usize] = 1u8
    let written = syscall(SYS_WRITE, state.wake, mem.address_of(&one[0usize]), 8usize, 0usize, 0usize, 0usize)
    if written < 0isize { ret from_errno(written) }
    ret ok
}

fn poller_wait(p: Poller, events: []PollEvent, timeout_ns: i64) -> (usize, err) {
    let state = mem.cast[*PollerState](p.state)
    if events.len == 0usize { ret (0usize, ok) }
    var capacity = events.len
    if capacity > POLL_BATCH { capacity = POLL_BATCH }
    // A negative timeout waits forever; anything positive but shorter than the kernel's
    // millisecond is rounded up, so asking for a little time never means asking for none.
    var milliseconds = -1isize
    if timeout_ns == 0i64 { milliseconds = 0isize }
    if timeout_ns > 0i64 {
        milliseconds = isize(timeout_ns / 1000000i64)
        if milliseconds == 0isize { milliseconds = 1isize }
    }
    var raw: [64]RawPollEvent = zero
    let ready = syscall(SYS_EPOLL_WAIT, state.epoll, mem.address_of(&raw[0usize]), capacity, usize(milliseconds), 0usize, 0usize)
    if ready < 0isize { ret (0usize, from_errno(ready)) }
    var produced = 0usize
    var at = 0usize
    while at < usize(ready) {
        let token = usize(raw[at].token_low) + usize(raw[at].token_high) * 4294967296usize
        if token == WAKE_TOKEN {
            // The poller's own descriptor: drained here so the next wait does not see it
            // again, and never reported, because it is not the caller's.
            var drain: [8]u8 = zero
            let taken = syscall(SYS_READ, state.wake, mem.address_of(&drain[0usize]), 8usize, 0usize, 0usize, 0usize)
        } else {
            events[produced].token = token
            events[produced].readable = raw[at].events & EPOLLIN != 0u32
            events[produced].writable = raw[at].events & EPOLLOUT != 0u32
            events[produced].closed = raw[at].events & (EPOLLHUP | EPOLLRDHUP) != 0u32
            events[produced].failed = raw[at].events & EPOLLERR != 0u32
            produced += 1usize
        }
        at += 1usize
    }
    ret (produced, ok)
}

fn poller_close(p: Poller) -> err {
    let state = mem.cast[*PollerState](p.state)
    let wake_result = syscall(SYS_CLOSE, state.wake, 0usize, 0usize, 0usize, 0usize, 0usize)
    let epoll_result = syscall(SYS_CLOSE, state.epoll, 0usize, 0usize, 0usize, 0usize, 0usize)
    if epoll_result < 0isize { ret from_errno(epoll_result) }
    ret from_errno(wake_result)
}

type Socket = struct { raw: usize }
type SocketFamily = enum u8 { Ip4, Ip6 }
type SocketKind = enum u8 { Stream, Datagram }
type SocketShutdown = enum u8 { Read, Write, Both }
type SocketAddress = struct { family: SocketFamily, bytes: [16]u8, scope: u32, port: u16 }

// The kernel's `sockaddr_in` and `sockaddr_in6` agree on their first four bytes -- the
// family then the port -- and diverge after, so one buffer holds either and the length
// passed alongside says which. It is written by index rather than as typed fields because
// the port and the address are big-endian on the wire whatever the host is, while the
// family is in the host's own order: mixing the two in one struct would hide exactly the
// distinction that matters.
type RawAddress = struct { bytes: [28]u8 }

// `struct timeval`, which is how a receive deadline is spelled here.
type TimeVal = struct { seconds: i64, microseconds: i64 }

const SOL_SOCKET: usize = 1usize
const SO_RCVTIMEO: usize = 20usize

const DNS_PORT: u16 = 53u16
const DNS_TYPE_A: usize = 1usize
const DNS_TYPE_AAAA: usize = 28usize
const DNS_CLASS_IN: usize = 1usize

// ponytail: plain 512-byte UDP DNS -- no EDNS0, and no retry over TCP when an answer is
// truncated. A truncated answer is used for whatever it did carry, which for a name with a
// handful of addresses is all of them. A name behind dozens wants EDNS0 first.
const DNS_MESSAGE_MAX: usize = 512usize

// ponytail: how many addresses one name may answer with, and how many resolvers are asked. Both
// are what a caller about to connect to one of them actually uses.
const RESOLVE_ADDRESS_MAX: usize = 8usize
const RESOLVE_SERVER_MAX: usize = 3usize
const RESOLVE_ATTEMPTS: usize = 2usize
const RESOLVE_TIMEOUT_SECONDS: i64 = 2i64

const HOSTS_MAX: usize = 262144usize
const RESOLV_CONF_MAX: usize = 8192usize

const RAW_IP4_SIZE: usize = 16usize
const RAW_IP6_SIZE: usize = 28usize

fn family_value(family: SocketFamily) -> usize {
    if family == .Ip6 { ret AF_INET6 }
    ret AF_INET
}

fn encode_address(address: SocketAddress) -> (RawAddress, usize) {
    var raw: RawAddress = zero
    let value = family_value(address.family)
    raw.bytes[0usize] = u8(value % 256usize)
    raw.bytes[1usize] = u8(value / 256usize)
    // Network order: the high byte first, whatever this host stores integers as.
    raw.bytes[2usize] = u8(usize(address.port) / 256usize)
    raw.bytes[3usize] = u8(usize(address.port) % 256usize)
    if address.family == .Ip6 {
        var at = 0usize
        while at < 16usize {
            raw.bytes[8usize + at] = address.bytes[at]
            at += 1usize
        }
        raw.bytes[24usize] = u8(address.scope % 256u32)
        raw.bytes[25usize] = u8(address.scope / 256u32 % 256u32)
        raw.bytes[26usize] = u8(address.scope / 65536u32 % 256u32)
        raw.bytes[27usize] = u8(address.scope / 16777216u32)
        ret (raw, RAW_IP6_SIZE)
    }
    // Section 5: an IPv4 address is the first four bytes and the rest are zero.
    var at = 0usize
    while at < 4usize {
        raw.bytes[4usize + at] = address.bytes[at]
        at += 1usize
    }
    ret (raw, RAW_IP4_SIZE)
}

fn decode_address(raw: RawAddress) -> SocketAddress {
    var address: SocketAddress = zero
    let value = usize(raw.bytes[0usize]) + usize(raw.bytes[1usize]) * 256usize
    address.port = u16(usize(raw.bytes[2usize]) * 256usize + usize(raw.bytes[3usize]))
    if value == AF_INET6 {
        address.family = .Ip6
        var at = 0usize
        while at < 16usize {
            address.bytes[at] = raw.bytes[8usize + at]
            at += 1usize
        }
        address.scope = u32(raw.bytes[24usize]) + u32(raw.bytes[25usize]) * 256u32 + u32(raw.bytes[26usize]) * 65536u32 + u32(raw.bytes[27usize]) * 16777216u32
        ret address
    }
    address.family = .Ip4
    var at = 0usize
    while at < 4usize {
        address.bytes[at] = raw.bytes[4usize + at]
        at += 1usize
    }
    ret address
}

type ErrorKind = enum u8 {
    NotFound,
    Denied,
    Exists,
    Interrupted,
    OutOfMemory,
    Timeout,
    WouldBlock,
    Unsupported,
    Invalid,
    Other,
}

// The two strings are the caller's, borrowed rather than copied: they name the operation and
// its subject, and nothing here needs them to outlive the call that supplied them.
type ErrorDetail = struct { kind: ErrorKind, native_code: i32, operation: str, subject: str }

type Lib = struct { raw: usize }

type ProcGroup = struct { raw: usize }
type SpawnOptions = struct { argv: []const str, env: []const str, inherit_env: bool, cwd: str, stdio: Stdio }

// `execve` wants an array of addresses ending in a zero, which is what this builds: each string
// copied with a terminator, and then a vector of where each landed. Both live in the arena,
// because the child may not allocate -- everything it needs has to exist before the fork.
fn c_string_vector(a: *mem.Arena, items: []const str) -> (usize, err) {
    if items.len >= SPAWN_LIST_MAX { ret (0usize, Failed) }
    let (vector, vector_error) = mem.alloc[usize](a, items.len + 1usize)
    if vector_error != ok { ret (0usize, OutOfMemory) }
    var at = 0usize
    while at < items.len {
        let (address, address_error) = c_string(a, items[at])
        if address_error != ok { ret (0usize, address_error) }
        vector[at] = address
        at += 1usize
    }
    vector[items.len] = 0usize
    ret (mem.address_of(&vector[0usize]), ok)
}

// Everything the child will need, prepared while it is still safe to allocate. After the fork
// the child does nothing but a handful of syscalls: a language runtime in a forked child is only
// safe if it never touches anything, and the way to keep that true is to leave it nothing to do.
type SpawnPlan = struct {
    argv: usize,
    envp: usize,
    program: usize,
    directory: usize,
    grouped: bool,
}

fn spawn_plan(a: *mem.Arena, options: SpawnOptions, grouped: bool) -> (SpawnPlan, err) {
    var plan: SpawnPlan = zero
    plan.grouped = grouped
    if options.argv.len == 0usize { ret (plan, Failed) }
    let (program, program_error) = c_string(a, options.argv[0usize])
    if program_error != ok { ret (plan, program_error) }
    plan.program = program
    let (argv, argv_error) = c_string_vector(a, options.argv)
    if argv_error != ok { ret (plan, argv_error) }
    plan.argv = argv
    // `inherit_env` overlays: the parent's environment with these entries over it. Without it
    // they are the whole of the child's environment, which is what an empty vector says.
    if options.inherit_env {
        let (inherited, inherited_error) = environment_vector(a, options.env)
        if inherited_error != ok { ret (plan, inherited_error) }
        plan.envp = inherited
    } else {
        let (envp, envp_error) = c_string_vector(a, options.env)
        if envp_error != ok { ret (plan, envp_error) }
        plan.envp = envp
    }
    if options.cwd.len != 0usize {
        let (directory, directory_error) = c_string(a, options.cwd)
        if directory_error != ok { ret (plan, directory_error) }
        plan.directory = directory
    }
    ret (plan, ok)
}

// The name a `NAME=VALUE` record sets. A record with no `=` in it is its own name, which is
// not a shape the host produces but is one a caller can pass.
fn entry_name(entry: str) -> str {
    var at = 0usize
    while at < entry.len {
        if entry[at] == 61u8 { ret entry[0usize..at] }
        at += 1usize
    }
    ret entry
}

fn same_bytes(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn overridden(entry: str, additions: []const str) -> bool {
    let name = entry_name(entry)
    var at = 0usize
    while at < additions.len {
        if same_bytes(name, entry_name(additions[at])) { ret true }
        at += 1usize
    }
    ret false
}

// The parent's environment with the caller's entries laid over it: a record the caller also
// sets is dropped in favour of theirs, and the rest are kept. That is what `inherit_env` means,
// and it has to be built here because nothing appends to an environment.
fn environment_vector(a: *mem.Arena, additions: []const str) -> (usize, err) {
    if additions.len >= SPAWN_LIST_MAX { ret (0usize, Failed) }
    let (block, block_error) = environment_bytes(a)
    if block_error != ok { ret (0usize, block_error) }
    let (vector, vector_error) = mem.alloc[usize](a, SPAWN_LIST_MAX)
    if vector_error != ok { ret (0usize, OutOfMemory) }
    var count = 0usize
    var at = 0usize
    while at < block.len && count + additions.len + 1usize < SPAWN_LIST_MAX {
        var end = at
        while end < block.len && block[end] != 0u8 { end = end + 1usize }
        // The records are NUL-terminated where they lie, so a kept one is pointed at rather
        // than copied.
        if end > at && !overridden(block[at..end], additions) {
            vector[count] = mem.address_of(&block[at])
            count += 1usize
        }
        at = end + 1usize
    }
    var added = 0usize
    while added < additions.len {
        let (address, address_error) = c_string(a, additions[added])
        if address_error != ok { ret (0usize, address_error) }
        vector[count] = address
        count += 1usize
        added += 1usize
    }
    vector[count] = 0usize
    ret (mem.address_of(&vector[0usize]), ok)
}

// Between the fork and the exec, and nothing else. Each step is one syscall and none of them
// allocates, which is the only way this is safe in a forked child.
fn become_child(plan: SpawnPlan, stdio: Stdio) {
    if plan.grouped {
        // Its own group, set by the child so that it is true before it can spawn anything --
        // the parent doing it afterwards is a race against the child's own children.
        let grouped = syscall(SYS_SETPGID, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    }
    if plan.directory != 0usize {
        let moved = syscall(SYS_CHDIR, plan.directory, 0usize, 0usize, 0usize, 0usize, 0usize)
        if moved < 0isize { let failed = syscall(SYS_EXIT_GROUP, EXEC_FAILED, 0usize, 0usize, 0usize, 0usize, 0usize) }
    }
    if stdio.stdin.raw != 0usize { let bound = syscall(SYS_DUP2, stdio.stdin.raw, 0usize, 0usize, 0usize, 0usize, 0usize) }
    if stdio.stdout.raw != 1usize { let bound = syscall(SYS_DUP2, stdio.stdout.raw, 1usize, 0usize, 0usize, 0usize, 0usize) }
    if stdio.stderr.raw != 2usize { let bound = syscall(SYS_DUP2, stdio.stderr.raw, 2usize, 0usize, 0usize, 0usize, 0usize) }
    let replaced = syscall(SYS_EXECVE, plan.program, plan.argv, plan.envp, 0usize, 0usize, 0usize)
    // `execve` only returns when it failed, and there is nothing to report it to.
    let gone = syscall(SYS_EXIT_GROUP, EXEC_FAILED, 0usize, 0usize, 0usize, 0usize, 0usize)
}

fn spawn_with_options(a: *mem.Arena, options: SpawnOptions) -> (Proc, err) {
    var child: Proc = zero
    let (plan, plan_error) = spawn_plan(a, options, false)
    if plan_error != ok { ret (child, plan_error) }
    let forked = syscall(SYS_FORK, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if forked < 0isize { ret (child, from_errno(forked)) }
    if forked == 0isize {
        become_child(plan, options.stdio)
        ret (child, Failed)
    }
    child.raw = usize(forked)
    ret (child, ok)
}

// The group is the child's own, and its identifier is the child's own process. Containment is
// what the host gives and no more: a descendant that starts a new group of its own leaves it,
// which is why the fence calls this containment rather than a sandbox.
fn proc_group_spawn(a: *mem.Arena, options: SpawnOptions) -> (ProcGroup, Proc, err) {
    var group: ProcGroup = zero
    var child: Proc = zero
    let (plan, plan_error) = spawn_plan(a, options, true)
    if plan_error != ok { ret (group, child, plan_error) }
    let forked = syscall(SYS_FORK, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if forked < 0isize { ret (group, child, from_errno(forked)) }
    if forked == 0isize {
        become_child(plan, options.stdio)
        ret (group, child, Failed)
    }
    // The parent sets it as well: whichever wins, the group exists before either returns, and
    // the loser's attempt is harmless.
    let grouped = syscall(SYS_SETPGID, usize(forked), usize(forked), 0usize, 0usize, 0usize, 0usize)
    group.raw = usize(forked)
    child.raw = usize(forked)
    ret (group, child, ok)
}

// A negative process identifier is the whole group, which is what `killpg` is.
fn proc_group_terminate(group: ProcGroup, force: bool) -> err {
    var signal = SIGTERM
    if force { signal = SIGKILL }
    let negated = 0usize - group.raw
    ret from_errno(syscall(SYS_KILL, negated, signal, 0usize, 0usize, 0usize, 0usize))
}

// A group identifier is not a handle here, so there is nothing to give back. The call exists
// because on the other host there is.
fn proc_group_close(group: ProcGroup) -> err {
    ret ok
}

type FileLock = struct { raw: usize }

// `flock` is per open file description, so two `open` calls on one path contend and two
// handles from one call do not -- which is what makes a lock worth having between processes
// and nearly meaningless within one.
//
// These locks are advisory: nothing stops a reader that never asked. The fence says as much,
// and this host is the reason it is worded that way.
fn file_lock(file: File, exclusive: bool, timeout_ns: i64) -> (FileLock, err) {
    var lock: FileLock = zero
    var operation = LOCK_SH
    if exclusive { operation = LOCK_EX }
    // A negative timeout waits, which the host does natively.
    if timeout_ns < 0i64 {
        let waited = syscall(SYS_FLOCK, file.raw, operation, 0usize, 0usize, 0usize, 0usize)
        if waited < 0isize { ret (lock, from_errno(waited)) }
        lock.raw = file.raw
        ret (lock, ok)
    }
    var remaining = timeout_ns
    while true {
        let result = syscall(SYS_FLOCK, file.raw, operation | LOCK_NB, 0usize, 0usize, 0usize, 0usize)
        if result >= 0isize {
            lock.raw = file.raw
            ret (lock, ok)
        }
        // Anything but "someone else holds it" is the caller's answer rather than another try.
        if result != -11isize { ret (lock, from_errno(result)) }
        if remaining <= 0i64 {
            // Zero asked for one attempt, which is `WouldBlock`; a deadline that ran out is a
            // `Timeout`. Two different questions deserve two different answers.
            if timeout_ns == 0i64 { ret (lock, WouldBlock) }
            ret (lock, Timeout)
        }
        var slice = LOCK_POLL_NS
        if remaining < slice { slice = remaining }
        var pause: TimeSpec = zero
        pause.seconds = slice / NANOSECONDS_PER_SECOND
        pause.nanoseconds = slice % NANOSECONDS_PER_SECOND
        let slept = syscall(SYS_NANOSLEEP, mem.address_of(&pause), 0usize, 0usize, 0usize, 0usize, 0usize)
        remaining = remaining - slice
    }
    ret (lock, Failed)
}

fn file_unlock(lock: FileLock) -> err {
    ret from_errno(syscall(SYS_FLOCK, lock.raw, LOCK_UN, 0usize, 0usize, 0usize, 0usize))
}

fn page_size() -> usize {
    ret PAGE_SIZE
}

// Both ends at once, close-on-exec for the same reason every other descriptor here is: a
// pipe that leaked into an unrelated child would keep its write end open and the reader would
// never see the end of it.
fn pipe() -> (File, File, err) {
    var reading: File = zero
    var writing: File = zero
    var pair: [2]i32 = zero
    let result = syscall(SYS_PIPE2, mem.address_of(&pair[0usize]), PIPE_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
    if result < 0isize { ret (reading, writing, from_errno(result)) }
    reading.raw = usize(pair[0usize])
    writing.raw = usize(pair[1usize])
    ret (reading, writing, ok)
}

// `SIGKILL`, so this is not a request. What `wait` then reports is 128 plus the signal, which
// is the fence's rule and not this call's choice.
fn kill(p: Proc) -> err {
    ret from_errno(syscall(SYS_KILL, p.raw, SIGKILL, 0usize, 0usize, 0usize, 0usize))
}

// The other half of `reserve`. The length matters here, unlike on the host where a release
// takes the whole reservation and rejects a size.
fn release(p: *u8, n: usize) -> err {
    ret from_errno(syscall(SYS_MUNMAP, mem.address_of(p), n, 0usize, 0usize, 0usize, 0usize))
}

// The system's own wording for a code, which is the one thing a table here could not keep in step
// with: it is per host and per locale, and libc already has it. Reached the same way the loader is,
// and costing the same nothing until it is called.
@import("libc.so.6", "strerror")
extern fn raw_strerror(code: i32) -> *u8

// ponytail: how far a message is read before it is taken as unterminated. No `strerror` text comes
// close, and the alternative is trusting a foreign string with no bound at all.
const MESSAGE_MAX: usize = 1024usize

// The message for a code, copied into the caller's arena. `detail` carries the code, so this asks
// for no ambient state and is exact whatever the last failing call was -- which is why it is
// written while `last_error_detail` is not.
fn error_message(a: *mem.Arena, detail: ErrorDetail) -> (str, err) {
    let text = raw_strerror(detail.native_code)
    if mem.address_of(text) == 0usize { ret ("", Failed) }
    // `mem.view` names the region without reading it, and the scan below stops at the terminator,
    // so nothing past the string libc owns is touched.
    var region: mem.Arena = zero
    region.base = text
    region.cap = MESSAGE_MAX
    region.off = 0usize
    let bytes = mem.view(&region, 0usize, MESSAGE_MAX)
    var length = 0usize
    while length < MESSAGE_MAX && bytes[length] != 0u8 { length += 1usize }
    if length == 0usize { ret ("", NotFound) }
    let (copy, copy_error) = mem.alloc[u8](a, length)
    if copy_error != ok { ret ("", OutOfMemory) }
    var at = 0usize
    while at < length {
        copy[at] = bytes[at]
        at += 1usize
    }
    ret (copy[0usize..length], ok)
}

// The one place this file names a library rather than a syscall number. There is no system call
// that loads a shared object: that is the dynamic linker's work, and `dlopen` is how it is asked.
// D32 keeps `e.os` on Linux over raw syscalls so that a neper binary needs no loader, and this
// does not spend that -- an `@import` that is never called adds neither `PT_INTERP` nor
// `DT_NEEDED`, so only a program that actually opens a library pays for one, which it must.
@import("libc.so.6", "dlopen")
extern fn raw_dlopen(name: *const u8, flags: i32) -> usize

@import("libc.so.6", "dlsym")
extern fn raw_dlsym(handle: usize, symbol: *const u8) -> usize

@import("libc.so.6", "dlclose")
extern fn raw_dlclose(handle: usize) -> i32

// `RTLD_NOW`: every symbol resolved when the object is opened rather than at first use, so a
// missing one is this call's failure and not a crash somewhere later.
const RTLD_NOW: i32 = 2i32

// A NUL-terminated copy as a slice rather than as an address: `c_string` answers with an address
// for the syscalls, and a foreign declaration wants a pointer, which only a slice can spell.
fn c_string_bytes(a: *mem.Arena, text: str) -> ([]u8, err) {
    var nothing: []u8 = zero
    let (buffer, allocation_error) = mem.alloc[u8](a, text.len + 1usize)
    if allocation_error != ok { ret (nothing, OutOfMemory) }
    var at = 0usize
    while at < text.len {
        buffer[at] = text[at]
        at += 1usize
    }
    buffer[text.len] = 0u8
    ret (buffer, ok)
}

// The name is passed as it was given, which is what the fence means by "as in `@import`": that
// takes `libc.so.6` and `kernel32` alike and adds nothing to either, so neither does this.
fn dlopen(a: *mem.Arena, name: str) -> (Lib, err) {
    var library: Lib = zero
    if name.len == 0usize { ret (library, NotFound) }
    let (bytes, bytes_error) = c_string_bytes(a, name)
    if bytes_error != ok { ret (library, bytes_error) }
    let handle = raw_dlopen(&bytes[0usize], RTLD_NOW)
    // `dlerror` says why, and there is nowhere to keep it (D109): a name that will not load is
    // reported as one that was not found.
    if handle == 0usize { ret (library, NotFound) }
    library.raw = handle
    ret (library, ok)
}

// The address of a symbol, which is all a library can answer with. Turning it into something
// callable is `dlsym`'s, and only the compiler can do that.
fn dl_lookup(a: *mem.Arena, l: Lib, sym: str) -> (usize, err) {
    if sym.len == 0usize { ret (0usize, NotFound) }
    let (bytes, bytes_error) = c_string_bytes(a, sym)
    if bytes_error != ok { ret (0usize, bytes_error) }
    let address = raw_dlsym(l.raw, &bytes[0usize])
    // A symbol may legitimately resolve to zero on this host, and `dlerror` is the only way to
    // tell that from a failure -- there is nowhere to keep it (D109), so zero is not found.
    if address == 0usize { ret (0usize, NotFound) }
    ret (address, ok)
}

fn dlclose(l: Lib) -> err {
    if raw_dlclose(l.raw) != 0i32 { ret Failed }
    ret ok
}

fn socket_open(family: SocketFamily, kind: SocketKind) -> (Socket, err) {
    var socket: Socket = zero
    var type_bits = SOCK_STREAM
    if kind == .Datagram { type_bits = SOCK_DGRAM }
    let descriptor = syscall(SYS_SOCKET, family_value(family), type_bits | SOCK_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
    if descriptor < 0isize { ret (socket, from_errno(descriptor)) }
    socket.raw = usize(descriptor)
    ret (socket, ok)
}

fn socket_close(s: Socket) -> err {
    ret from_errno(syscall(SYS_CLOSE, s.raw, 0usize, 0usize, 0usize, 0usize, 0usize))
}

// Read the flags before changing them: setting the whole word would drop whatever else the
// descriptor carries.
fn socket_set_nonblocking(s: Socket, enabled: bool) -> err {
    let current = syscall(SYS_FCNTL, s.raw, F_GETFL, 0usize, 0usize, 0usize, 0usize)
    if current < 0isize { ret from_errno(current) }
    var wanted = usize(current) | O_NONBLOCK
    if !enabled {
        wanted = usize(current)
        if usize(current) & O_NONBLOCK != 0usize { wanted = usize(current) - O_NONBLOCK }
    }
    ret from_errno(syscall(SYS_FCNTL, s.raw, F_SETFL, wanted, 0usize, 0usize, 0usize))
}

fn socket_bind(s: Socket, address: SocketAddress) -> err {
    var (raw, length) = encode_address(address)
    ret from_errno(syscall(SYS_BIND, s.raw, mem.address_of(&raw), length, 0usize, 0usize, 0usize))
}

// The address a socket is actually bound to. With port zero the host chose one and this is
// the only way to learn it; with a port the caller named it reports that one back, which
// makes the two cases the same call rather than two.
fn socket_local_address(s: Socket) -> (SocketAddress, err) {
    var address: SocketAddress = zero
    var raw: RawAddress = zero
    var length = u32(RAW_IP6_SIZE)
    let result = syscall(SYS_GETSOCKNAME, s.raw, mem.address_of(&raw), mem.address_of(&length), 0usize, 0usize, 0usize)
    if result < 0isize { ret (address, from_errno(result)) }
    ret (decode_address(raw), ok)
}

fn socket_listen(s: Socket, backlog: u32) -> err {
    ret from_errno(syscall(SYS_LISTEN, s.raw, usize(backlog), 0usize, 0usize, 0usize, 0usize))
}

fn socket_connect(s: Socket, address: SocketAddress) -> err {
    var (raw, length) = encode_address(address)
    let result = syscall(SYS_CONNECT, s.raw, mem.address_of(&raw), length, 0usize, 0usize, 0usize)
    // EINPROGRESS on a socket that was made non-blocking is the connect having started,
    // which is what `WouldBlock` means for every other call here.
    if result == -115isize { ret WouldBlock }
    ret from_errno(result)
}

fn socket_accept(s: Socket) -> (Socket, SocketAddress, err) {
    var accepted: Socket = zero
    var peer: SocketAddress = zero
    var raw: RawAddress = zero
    var length = u32(RAW_IP6_SIZE)
    let descriptor = syscall(SYS_ACCEPT4, s.raw, mem.address_of(&raw), mem.address_of(&length), SOCK_CLOEXEC, 0usize, 0usize)
    if descriptor < 0isize { ret (accepted, peer, from_errno(descriptor)) }
    accepted.raw = usize(descriptor)
    ret (accepted, decode_address(raw), ok)
}

// A connected socket is `sendto` and `recvfrom` with no address, which is one pair of
// syscalls for both the connected and the unconnected form.
fn socket_send(s: Socket, src: []const u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let sent = syscall(SYS_SENDTO, s.raw, mem.address_of(&src[0usize]), src.len, 0usize, 0usize, 0usize)
    if sent < 0isize { ret (0usize, from_errno(sent)) }
    ret (usize(sent), ok)
}

fn socket_receive(s: Socket, dst: []u8) -> (usize, err) {
    if dst.len == 0usize { ret (0usize, ok) }
    let taken = syscall(SYS_RECVFROM, s.raw, mem.address_of(&dst[0usize]), dst.len, 0usize, 0usize, 0usize)
    if taken < 0isize { ret (0usize, from_errno(taken)) }
    ret (usize(taken), ok)
}

fn socket_send_to(s: Socket, dst: SocketAddress, src: []const u8) -> (usize, err) {
    var (raw, length) = encode_address(dst)
    var source_address = 0usize
    if src.len != 0usize { source_address = mem.address_of(&src[0usize]) }
    let sent = syscall(SYS_SENDTO, s.raw, source_address, src.len, 0usize, mem.address_of(&raw), length)
    if sent < 0isize { ret (0usize, from_errno(sent)) }
    ret (usize(sent), ok)
}

fn socket_receive_from(s: Socket, dst: []u8) -> (usize, SocketAddress, err) {
    var peer: SocketAddress = zero
    if dst.len == 0usize { ret (0usize, peer, ok) }
    var raw: RawAddress = zero
    var length = u32(RAW_IP6_SIZE)
    let taken = syscall(SYS_RECVFROM, s.raw, mem.address_of(&dst[0usize]), dst.len, 0usize, mem.address_of(&raw), mem.address_of(&length))
    if taken < 0isize { ret (0usize, peer, from_errno(taken)) }
    ret (usize(taken), decode_address(raw), ok)
}

// A whole file, up to a limit, which is how both of the resolver's configuration files are
// read. `environment_bytes` cannot be reused for this: a `/proc` file reports a size of zero and
// has to be read until a short read proves the end, where an ordinary file does not.
fn read_text_file(a: *mem.Arena, path: str, cap: usize) -> (str, err) {
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok { ret ("", path_error) }
    let (buffer, allocation_error) = mem.alloc[u8](a, cap)
    if allocation_error != ok { ret ("", OutOfMemory) }
    let descriptor = syscall(SYS_OPENAT, AT_FDCWD, path_address, OPEN_READ_ONLY, 0usize, 0usize, 0usize)
    if descriptor < 0isize { ret ("", from_errno(descriptor)) }
    var filled = 0usize
    var failure = ok
    while filled < cap {
        let taken = syscall(SYS_READ, usize(descriptor), mem.address_of(&buffer[filled]), cap - filled, 0usize, 0usize, 0usize)
        if taken < 0isize {
            failure = from_errno(taken)
            break
        }
        if taken == 0isize { break }
        filled += usize(taken)
    }
    let closed = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
    if failure != ok { ret ("", failure) }
    ret (buffer[0usize..filled], ok)
}

// Host names do not distinguish case, wherever they are written down, so the hosts file is read
// the way a resolver would answer.
fn folded(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

fn same_folded(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if folded(left[at]) != folded(right[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn hex_value(byte: u8) -> (usize, bool) {
    if byte >= 48u8 && byte <= 57u8 { ret (usize(byte - 48u8), true) }
    if byte >= 97u8 && byte <= 102u8 { ret (usize(byte - 97u8) + 10usize, true) }
    if byte >= 65u8 && byte <= 70u8 { ret (usize(byte - 65u8) + 10usize, true) }
    ret (0usize, false)
}

// A dotted quad and nothing else: four parts, each of one to three digits and none above 255,
// with no room left over. A resolver that accepted `1.2.3` or `1.2.3.4.5` would be answering a
// question nobody asked.
fn parse_ip4(text: str) -> (SocketAddress, bool) {
    var address: SocketAddress = zero
    address.family = .Ip4
    var at = 0usize
    var part = 0usize
    while part < 4usize {
        var value = 0usize
        var digits = 0usize
        while at < text.len && text[at] >= 48u8 && text[at] <= 57u8 {
            value = value * 10usize + usize(text[at] - 48u8)
            digits += 1usize
            at += 1usize
        }
        if digits == 0usize || digits > 3usize || value > 255usize { ret (address, false) }
        address.bytes[part] = u8(value)
        part += 1usize
        if part < 4usize {
            if at >= text.len || text[at] != 46u8 { ret (address, false) }
            at += 1usize
        }
    }
    if at != text.len { ret (address, false) }
    ret (address, true)
}

// The groups before a `::` and the groups after it: the first go at the front, the last at the
// back, and whatever is between them stays zero. A group followed by a dot is where the two
// syntaxes meet -- the rest of the address is a dotted quad, as in `::ffff:127.0.0.1`.
//
// ponytail: a zone suffix (`fe80::1%eth0`) is not accepted. Naming an interface means asking the
// host for its index, which is a syscall family this file does not otherwise touch.
fn parse_ip6(text: str) -> (SocketAddress, bool) {
    var address: SocketAddress = zero
    address.family = .Ip6
    var head: [16]u8 = zero
    var tail: [16]u8 = zero
    var head_len = 0usize
    var tail_len = 0usize
    var compressed = false
    var at = 0usize
    if text.len < 2usize { ret (address, false) }
    if text[0usize] == 58u8 {
        if text[1usize] != 58u8 { ret (address, false) }
        compressed = true
        at = 2usize
        // `::` on its own is every byte zero, and there is nothing more to read.
        if at == text.len { ret (address, true) }
    }
    while at < text.len {
        var value = 0usize
        var digits = 0usize
        var scan = at
        while scan < text.len {
            let (nibble, is_hex) = hex_value(text[scan])
            if !is_hex { break }
            value = value * 16usize + nibble
            digits += 1usize
            scan += 1usize
        }
        if digits == 0usize || digits > 4usize { ret (address, false) }
        if scan < text.len && text[scan] == 46u8 {
            let (embedded, is_embedded) = parse_ip4(text[at..text.len])
            if !is_embedded { ret (address, false) }
            var quad = 0usize
            while quad < 4usize {
                if compressed {
                    if tail_len >= 16usize { ret (address, false) }
                    tail[tail_len] = embedded.bytes[quad]
                    tail_len += 1usize
                } else {
                    if head_len >= 16usize { ret (address, false) }
                    head[head_len] = embedded.bytes[quad]
                    head_len += 1usize
                }
                quad += 1usize
            }
            at = text.len
            break
        }
        at = scan
        if compressed {
            if tail_len + 2usize > 16usize { ret (address, false) }
            tail[tail_len] = u8(value / 256usize)
            tail[tail_len + 1usize] = u8(value % 256usize)
            tail_len += 2usize
        } else {
            if head_len + 2usize > 16usize { ret (address, false) }
            head[head_len] = u8(value / 256usize)
            head[head_len + 1usize] = u8(value % 256usize)
            head_len += 2usize
        }
        if at == text.len { break }
        if text[at] != 58u8 { ret (address, false) }
        at += 1usize
        if at < text.len && text[at] == 58u8 {
            // One `::` and no more, or the length it stands for is not decidable.
            if compressed { ret (address, false) }
            compressed = true
            at += 1usize
            if at == text.len { break }
        } else {
            // A single colon at the end is not an address.
            if at == text.len { ret (address, false) }
        }
    }
    if !compressed && head_len != 16usize { ret (address, false) }
    if head_len + tail_len > 16usize { ret (address, false) }
    var index = 0usize
    while index < head_len {
        address.bytes[index] = head[index]
        index += 1usize
    }
    index = 0usize
    while index < tail_len {
        address.bytes[16usize - tail_len + index] = tail[index]
        index += 1usize
    }
    ret (address, true)
}

fn parse_literal(text: str, family: SocketFamily) -> (SocketAddress, bool) {
    if family == .Ip6 {
        let (six, is_six) = parse_ip6(text)
        ret (six, is_six)
    }
    let (four, is_four) = parse_ip4(text)
    ret (four, is_four)
}

// One field of a configuration line, and where to look for the next. Fields are separated by
// spaces and tabs, and a `#` ends the line wherever it stands.
fn next_field(line: str, from: usize) -> (str, usize) {
    var start = from
    while start < line.len && (line[start] == 32u8 || line[start] == 9u8 || line[start] == 13u8) { start += 1usize }
    if start >= line.len || line[start] == 35u8 { ret ("", line.len) }
    var end = start
    while end < line.len {
        if line[end] == 32u8 || line[end] == 9u8 || line[end] == 13u8 || line[end] == 35u8 { break }
        end += 1usize
    }
    ret (line[start..end], end)
}

fn line_end(text: str, from: usize) -> usize {
    var end = from
    while end < text.len && text[end] != 10u8 { end += 1usize }
    ret end
}

// `/etc/hosts`: an address, then every name it answers to. This is what makes `localhost`
// resolvable with no network at all, and it is the only part of the resolver that works when
// there is none.
fn hosts_lookup(a: *mem.Arena, host: str, family: SocketFamily, port: u16, out: []SocketAddress) -> usize {
    let (text, text_error) = read_text_file(a, "/etc/hosts", HOSTS_MAX)
    if text_error != ok { ret 0usize }
    var found = 0usize
    var at = 0usize
    while at < text.len && found < out.len {
        let end = line_end(text, at)
        let line = text[at..end]
        let (address_text, after_address) = next_field(line, 0usize)
        if address_text.len != 0usize {
            let (address, is_address) = parse_literal(address_text, family)
            // A line whose address is of the other family answers a different question.
            if is_address {
                var cursor = after_address
                while cursor < line.len {
                    let (name, after_name) = next_field(line, cursor)
                    if name.len == 0usize { break }
                    if same_folded(name, host) {
                        out[found] = address
                        out[found].port = port
                        found += 1usize
                        break
                    }
                    cursor = after_name
                }
            }
        }
        at = end + 1usize
    }
    ret found
}

// `/etc/resolv.conf`, for the `nameserver` lines and nothing else. `search` and `options` are
// not read: a suffix list turns one question into several, and this asks the one it was given.
fn resolv_servers(a: *mem.Arena, out: []SocketAddress) -> usize {
    let (text, text_error) = read_text_file(a, "/etc/resolv.conf", RESOLV_CONF_MAX)
    if text_error != ok { ret 0usize }
    var found = 0usize
    var at = 0usize
    while at < text.len && found < out.len {
        let end = line_end(text, at)
        let line = text[at..end]
        let (keyword, after_keyword) = next_field(line, 0usize)
        if same_bytes(keyword, "nameserver") {
            let (address_text, after_address) = next_field(line, after_keyword)
            if address_text.len != 0usize {
                // A resolver's own family has nothing to do with the family being asked about.
                let (four, is_four) = parse_ip4(address_text)
                let (six, is_six) = parse_ip6(address_text)
                if is_four {
                    out[found] = four
                    out[found].port = DNS_PORT
                    found += 1usize
                } else {
                    if is_six {
                        out[found] = six
                        out[found].port = DNS_PORT
                        found += 1usize
                    }
                }
            }
        }
        at = end + 1usize
    }
    ret found
}

// A name on the wire is its labels, each with its length in front, ending in a zero length. A
// trailing dot is the root and is already what the terminator says.
fn dns_write_name(message: []u8, at: usize, host: str) -> (usize, bool) {
    var cursor = at
    var start = 0usize
    while start <= host.len {
        var end = start
        while end < host.len && host[end] != 46u8 { end += 1usize }
        let length = end - start
        // An empty label in the middle of a name is not a name.
        if length == 0usize && end < host.len { ret (0usize, false) }
        if length > 63usize { ret (0usize, false) }
        if length > 0usize {
            if cursor + 1usize + length >= message.len { ret (0usize, false) }
            message[cursor] = u8(length)
            cursor += 1usize
            var index = 0usize
            while index < length {
                message[cursor] = host[start + index]
                cursor += 1usize
                index += 1usize
            }
        }
        if end >= host.len { break }
        start = end + 1usize
    }
    if cursor >= message.len { ret (0usize, false) }
    message[cursor] = 0u8
    cursor += 1usize
    ret (cursor, true)
}

fn dns_build_query(message: []u8, identifier: u16, host: str, kind: usize) -> (usize, bool) {
    if message.len < 12usize { ret (0usize, false) }
    var index = 0usize
    while index < 12usize {
        message[index] = 0u8
        index += 1usize
    }
    message[0usize] = u8(usize(identifier) / 256usize)
    message[1usize] = u8(usize(identifier) % 256usize)
    // Recursion desired: this asks a resolver for the answer rather than walking the tree
    // itself, which is the difference between a stub and a resolver.
    message[2usize] = 1u8
    // One question.
    message[5usize] = 1u8
    let (after_name, named) = dns_write_name(message, 12usize, host)
    if !named { ret (0usize, false) }
    if after_name + 4usize > message.len { ret (0usize, false) }
    message[after_name] = u8(kind / 256usize)
    message[after_name + 1usize] = u8(kind % 256usize)
    message[after_name + 2usize] = u8(DNS_CLASS_IN / 256usize)
    message[after_name + 3usize] = u8(DNS_CLASS_IN % 256usize)
    ret (after_name + 4usize, true)
}

// Any label in a name may be a pointer to a name earlier in the message instead of a label, and
// a pointer is the end of the name that holds it. Only where the name ends matters here, so no
// pointer is ever followed and a message cannot make this loop.
fn dns_skip_name(message: []const u8, at: usize) -> (usize, bool) {
    var cursor = at
    while cursor < message.len {
        let length = usize(message[cursor])
        if length == 0usize { ret (cursor + 1usize, true) }
        if length >= 192usize { ret (cursor + 2usize, true) }
        if length > 63usize { ret (0usize, false) }
        cursor = cursor + 1usize + length
    }
    ret (0usize, false)
}

fn dns_parse(message: []const u8, kind: usize, port: u16, out: []SocketAddress) -> (usize, err) {
    if message.len < 12usize { ret (0usize, Failed) }
    // The response bit. A query coming back as a query is not an answer.
    if message[2usize] / 128u8 != 1u8 { ret (0usize, Failed) }
    let code = message[3usize] % 16u8
    // NXDOMAIN: the name does not exist. That is an answer, not a failure to get one, and it is
    // why asking a second resolver would be asking the same question twice.
    if code == 3u8 { ret (0usize, NotFound) }
    if code != 0u8 { ret (0usize, Failed) }
    let questions = usize(message[4usize]) * 256usize + usize(message[5usize])
    let answers = usize(message[6usize]) * 256usize + usize(message[7usize])
    var cursor = 12usize
    var asked = 0usize
    while asked < questions {
        let (after, skipped) = dns_skip_name(message, cursor)
        if !skipped { ret (0usize, Failed) }
        cursor = after + 4usize
        asked += 1usize
    }
    var found = 0usize
    var index = 0usize
    while index < answers && found < out.len {
        let (after, skipped) = dns_skip_name(message, cursor)
        if !skipped { ret (0usize, Failed) }
        cursor = after
        if cursor + 10usize > message.len { ret (0usize, Failed) }
        let record = usize(message[cursor]) * 256usize + usize(message[cursor + 1usize])
        let class = usize(message[cursor + 2usize]) * 256usize + usize(message[cursor + 3usize])
        let length = usize(message[cursor + 8usize]) * 256usize + usize(message[cursor + 9usize])
        cursor += 10usize
        if cursor + length > message.len { ret (0usize, Failed) }
        // A `CNAME` is not followed. A resolver asked to recurse puts the target's addresses in
        // the same message, and those are the records this picks up; whose name each one is
        // under was already decided on the far side of the socket.
        if record == kind && class == DNS_CLASS_IN {
            var width = 4usize
            var family: SocketFamily = .Ip4
            if kind == DNS_TYPE_AAAA {
                width = 16usize
                family = .Ip6
            }
            if length == width {
                var address: SocketAddress = zero
                address.family = family
                address.port = port
                var byte = 0usize
                while byte < width {
                    address.bytes[byte] = message[cursor + byte]
                    byte += 1usize
                }
                out[found] = address
                found += 1usize
            }
        }
        cursor += length
        index += 1usize
    }
    // A name that exists with nothing of the family that was asked about is the same answer as
    // a name that does not exist: there is nothing here to connect to.
    if found == 0usize { ret (0usize, NotFound) }
    ret (found, ok)
}

fn dns_ask(server: SocketAddress, query: []const u8, response: []u8, identifier: u16, kind: usize, port: u16, out: []SocketAddress) -> (usize, err) {
    let (socket, open_error) = socket_open(server.family, .Datagram)
    if open_error != ok { ret (0usize, open_error) }
    // Connected rather than sent to: the host then drops anything arriving from anywhere else,
    // which is the cheap half of not believing a stranger. The identifier below is the other.
    let connect_error = socket_connect(socket, server)
    if connect_error != ok {
        let unused = socket_close(socket)
        ret (0usize, connect_error)
    }
    var window: TimeVal = zero
    window.seconds = RESOLVE_TIMEOUT_SECONDS
    let timed = syscall(SYS_SETSOCKOPT, socket.raw, SOL_SOCKET, SO_RCVTIMEO, mem.address_of(&window), 16usize, 0usize)
    if timed < 0isize {
        let deadline_error = from_errno(timed)
        let unused = socket_close(socket)
        ret (0usize, deadline_error)
    }
    let (sent, send_error) = socket_send(socket, query)
    if send_error != ok {
        let unused = socket_close(socket)
        ret (0usize, send_error)
    }
    let (taken, receive_error) = socket_receive(socket, response)
    let closed = socket_close(socket)
    if receive_error != ok {
        // The deadline running out arrives as "nothing to read", which here means the resolver
        // never answered rather than that the caller should ask again immediately.
        if receive_error == WouldBlock { ret (0usize, Timeout) }
        ret (0usize, receive_error)
    }
    if taken < 12usize { ret (0usize, Failed) }
    // An answer to a different question is not an answer.
    if usize(response[0usize]) * 256usize + usize(response[1usize]) != usize(identifier) { ret (0usize, Failed) }
    let (found, parse_error) = dns_parse(response[0usize..taken], kind, port, out)
    ret (found, parse_error)
}

// The other host has a resolver behind one call. This one has no libc to ask and no syscall that
// resolves a name, so the three steps are here: a literal, the hosts file, and DNS over UDP.
fn socket_resolve(a: *mem.Arena, host: str, port: u16, family: SocketFamily) -> ([]SocketAddress, err) {
    var nothing: []SocketAddress = zero
    if host.len == 0usize { ret (nothing, NotFound) }
    let (results, results_error) = mem.alloc[SocketAddress](a, RESOLVE_ADDRESS_MAX)
    if results_error != ok { ret (nothing, OutOfMemory) }
    // A literal is not a name: nothing is read and nobody is asked.
    let (literal, is_literal) = parse_literal(host, family)
    if is_literal {
        results[0usize] = literal
        results[0usize].port = port
        ret (results[0usize..1usize], ok)
    }
    // A literal of the other family is not a name either. Sending it to a resolver would ask the
    // network about an address it can only say no to.
    var other: SocketFamily = .Ip6
    if family == .Ip6 { other = .Ip4 }
    let (crossed, is_crossed) = parse_literal(host, other)
    if is_crossed { ret (nothing, NotFound) }

    let checkpoint = mem.mark(a)
    // The hosts file first, because that is what it is for, and because it is the only answer
    // available when there is no network at all. The addresses are copied out, so the file's
    // bytes are given back before anything else is allocated.
    let found = hosts_lookup(a, host, family, port, results)
    if found != 0usize { ret (results[0usize..found], ok) }
    mem.reset(a, checkpoint)

    let (servers, servers_error) = mem.alloc[SocketAddress](a, RESOLVE_SERVER_MAX)
    if servers_error != ok { ret (nothing, OutOfMemory) }
    let server_count = resolv_servers(a, servers)
    // Nothing configured is not a failure to reach anyone; there is nobody to reach.
    if server_count == 0usize { ret (nothing, NotFound) }
    let (query, query_error) = mem.alloc[u8](a, DNS_MESSAGE_MAX)
    if query_error != ok { ret (nothing, OutOfMemory) }
    let (response, response_error) = mem.alloc[u8](a, DNS_MESSAGE_MAX)
    if response_error != ok { ret (nothing, OutOfMemory) }
    // A predictable identifier is an invitation: an answer counts only if it carries the one it
    // was asked with, and the one it was asked with is not guessable.
    var identifier_bytes: [2]u8 = zero
    let identifier_error = random(identifier_bytes[..])
    if identifier_error != ok { ret (nothing, identifier_error) }
    let identifier = u16(usize(identifier_bytes[0usize]) * 256usize + usize(identifier_bytes[1usize]))
    var kind = DNS_TYPE_A
    if family == .Ip6 { kind = DNS_TYPE_AAAA }
    let (query_length, built) = dns_build_query(query, identifier, host, kind)
    // A name too long to ask about is a name nothing has.
    if !built { ret (nothing, NotFound) }
    var outcome = Timeout
    var attempt = 0usize
    while attempt < RESOLVE_ATTEMPTS {
        var index = 0usize
        while index < server_count {
            let (answered, ask_error) = dns_ask(servers[index], query[0usize..query_length], response, identifier, kind, port, results)
            if ask_error == ok { ret (results[0usize..answered], ok) }
            // A resolver that said the name does not exist has answered the question.
            if ask_error == NotFound { ret (nothing, NotFound) }
            outcome = ask_error
            index += 1usize
        }
        attempt += 1usize
    }
    ret (nothing, outcome)
}

fn shutdown_value(how: SocketShutdown) -> usize {
    if how == .Write { ret 1usize }
    if how == .Both { ret 2usize }
    ret 0usize
}

fn socket_shutdown(s: Socket, how: SocketShutdown) -> err {
    ret from_errno(syscall(SYS_SHUTDOWN, s.raw, shutdown_value(how), 0usize, 0usize, 0usize, 0usize))
}

// Descriptor zero, which is what the host started this process with. `stdout` and `stderr` are
// intrinsics from before `e.os` was written as source; this one never was, so it is written here
// rather than added to the runtime on two platforms.
fn stdin() -> File {
    var file: File = zero
    file.raw = 0usize
    ret file
}

// A poller takes a `Handle`, and a `File` and a `Socket` are different types with the same
// thing inside them. These two are the whole of the conversion.
fn file_handle(f: File) -> Handle {
    var handle: Handle = zero
    handle.raw = f.raw
    ret handle
}

fn socket_handle(s: Socket) -> Handle {
    var handle: Handle = zero
    handle.raw = s.raw
    ret handle
}

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

// The parent of the final component, opened under the policy so every step but the last is
// walked with links refused. The last component is then acted on by name relative to that.
// This is how "do not follow a link on the way there, but do act on the link that is
// there" gets said: neither host has a single call that means both, and removing a
// symbolic link has to remove the link rather than what it points at.
//
// The returned handle is the caller's to close only when it is not the one passed in,
// which is what comparing the two raw values says.
fn open_parent(a: *mem.Arena, dir: Dir, relative_path: str) -> (Dir, str, err) {
    var parent: Dir = zero
    parent.raw = dir.raw
    var cut = 0usize
    var found = false
    var at = 0usize
    while at < relative_path.len {
        if relative_path[at] == 47u8 {
            cut = at
            found = true
        }
        at += 1usize
    }
    if !found { ret (parent, relative_path, ok) }
    let head = relative_path[0usize..cut]
    let tail = relative_path[cut + 1usize..relative_path.len]
    // A name ending in a separator names no final component to act on.
    if tail.len == 0usize { ret (parent, "", Denied) }
    let checkpoint = mem.mark(a)
    let (head_address, head_error) = c_string(a, head)
    if head_error != ok {
        mem.reset(a, checkpoint)
        ret (parent, "", head_error)
    }
    var how: OpenHow = zero
    how.flags = u64(OPEN_DIRECTORY)
    how.resolve = RESOLVE_NO_SYMLINKS | RESOLVE_BENEATH
    let descriptor = syscall(SYS_OPENAT2, dir.raw, head_address, mem.address_of(&how), 24usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize {
        if descriptor == -18isize { ret (parent, "", Denied) }
        ret (parent, "", from_errno(descriptor))
    }
    parent.raw = usize(descriptor)
    ret (parent, tail, ok)
}

fn release_parent(parent: Dir, dir: Dir) {
    if parent.raw != dir.raw {
        let closed = dir_close(parent)
    }
}

// `unlinkat` never follows the final component, which is what makes removing a symbolic
// link remove the link.
fn remove_at(a: *mem.Arena, dir: Dir, relative_path: str, directory: bool) -> err {
    if !relative_path_ok(relative_path) { ret Denied }
    let (parent, name, parent_error) = open_parent(a, dir, relative_path)
    if parent_error != ok { ret parent_error }
    let checkpoint = mem.mark(a)
    let (name_address, name_error) = c_string(a, name)
    if name_error != ok {
        mem.reset(a, checkpoint)
        release_parent(parent, dir)
        ret name_error
    }
    var modifier = 0usize
    if directory { modifier = AT_REMOVEDIR }
    let result = syscall(SYS_UNLINKAT, parent.raw, name_address, modifier, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    release_parent(parent, dir)
    ret from_errno(result)
}

// The same two-step as `remove_at`, on both sides: each parent is resolved under the
// policy and the rename is then between two final names. `RENAME_NOREPLACE` and its
// `linkat` fallback are the same pair `replace` uses, for the same reason -- a filesystem
// that does not know the flag rejects the call rather than the destination.
fn rename_at(a: *mem.Arena, src_dir: Dir, src_path: str, dst_dir: Dir, dst_path: str, overwrite: bool, durable: bool) -> err {
    if !relative_path_ok(src_path) { ret Denied }
    if !relative_path_ok(dst_path) { ret Denied }
    let (src_parent, src_name, src_parent_error) = open_parent(a, src_dir, src_path)
    if src_parent_error != ok { ret src_parent_error }
    let (dst_parent, dst_name, dst_parent_error) = open_parent(a, dst_dir, dst_path)
    if dst_parent_error != ok {
        release_parent(src_parent, src_dir)
        ret dst_parent_error
    }
    let checkpoint = mem.mark(a)
    let (from_address, from_error) = c_string(a, src_name)
    if from_error != ok {
        mem.reset(a, checkpoint)
        release_parent(src_parent, src_dir)
        release_parent(dst_parent, dst_dir)
        ret from_error
    }
    let (to_address, to_error) = c_string(a, dst_name)
    if to_error != ok {
        mem.reset(a, checkpoint)
        release_parent(src_parent, src_dir)
        release_parent(dst_parent, dst_dir)
        ret to_error
    }
    var result = 0isize
    if overwrite {
        result = syscall(SYS_RENAMEAT, src_parent.raw, from_address, dst_parent.raw, to_address, 0usize, 0usize)
    } else {
        result = syscall(SYS_RENAMEAT2, src_parent.raw, from_address, dst_parent.raw, to_address, RENAME_NOREPLACE, 0usize)
        if result == -22isize || result == -38isize || result == -95isize {
            result = syscall(SYS_LINKAT, src_parent.raw, from_address, dst_parent.raw, to_address, 0usize, 0usize)
            if result >= 0isize {
                result = syscall(SYS_UNLINKAT, src_parent.raw, from_address, 0usize, 0usize, 0usize, 0usize)
            }
        }
    }
    var answer = ok
    if result < 0isize { answer = from_errno(result) }
    // The directory the name landed in is what has to reach the disk for the name to
    // survive; the bytes were already the caller's to have flushed.
    if answer == ok && durable {
        let flushed = syscall(SYS_FSYNC, dst_parent.raw, 0usize, 0usize, 0usize, 0usize, 0usize)
        if flushed < 0isize { answer = from_errno(flushed) }
    }
    mem.reset(a, checkpoint)
    release_parent(src_parent, src_dir)
    release_parent(dst_parent, dst_dir)
    ret answer
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
