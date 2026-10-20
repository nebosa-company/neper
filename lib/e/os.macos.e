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


// BSD system call numbers (xnu's syscalls.master), reached through `syscall`.
const SYS_UNLINK: usize = 10usize
const SYS_CHDIR: usize = 12usize
const SYS_CHMOD: usize = 15usize
const SYS_OPEN: usize = 5usize
const SYS_RENAME: usize = 128usize
const SYS_MKDIR: usize = 136usize
const SYS_RMDIR: usize = 137usize
const SYS_UTIMES: usize = 138usize
const SYS_SYMLINK: usize = 57usize
const SYS_READLINK: usize = 58usize
const SYS_FCNTL: usize = 92usize
const SYS_CLOSE: usize = 6usize
const SYS_STAT64: usize = 338usize
const SYS_LSTAT64: usize = 340usize
const SYS_GETDIRENTRIES64: usize = 344usize
const SYS_GETENTROPY: usize = 500usize

const O_RDONLY: usize = 0usize
const O_RDWR: usize = 2usize
const O_CREAT: usize = 512usize
const O_EXCL: usize = 2048usize
const O_DIRECTORY: usize = 1048576usize
const O_CLOEXEC: usize = 16777216usize
const F_GETPATH: usize = 50usize
const DIRECTORY_MODE: usize = 511usize
const PERMISSION_MASK: u32 = 4095u32
const FORMAT_MASK: u32 = 61440u32
const FORMAT_FILE: u32 = 32768u32
const FORMAT_DIRECTORY: u32 = 16384u32
const FORMAT_SYMLINK: u32 = 40960u32
const NANOSECONDS_PER_SECOND: i64 = 1000000000i64
const PATH_MAX: usize = 1024usize

// The kernel's `struct stat` with 64-bit inodes, field for field: stat64 writes 144 bytes.
type StatBuffer = struct { device: i32, mode: u16, link_count: u16, inode: u64, user: u32, group: u32, represented_device: i32, padding: i32, accessed: i64, accessed_ns: i64, modified: i64, modified_ns: i64, changed: i64, changed_ns: i64, born: i64, born_ns: i64, size: i64, blocks: i64, block_size: i32, flags: u32, generation: u32, spare: i32, reserved0: i64, reserved1: i64 }

// The last failed call's errno. One slot for the process: a detail another thread overwrote
// is a wrong diagnostic, never a wrong answer.
// ponytail: no per-thread slots as on Linux; add them when a macOS build runs threads.
var last_code: i32 = 0i32

// The kernel's errno comes back negated by the runtime's `sys` shim.
fn error_of_result(result: isize) -> err {
    if result == -1isize { ret Denied }
    if result == -2isize { ret NotFound }
    if result == -4isize { ret Interrupted }
    if result == -35isize { ret WouldBlock }
    if result == -12isize { ret OutOfMemory }
    if result == -13isize { ret Denied }
    if result == -17isize { ret Exists }
    if result == -20isize { ret NotFound }
    if result == -60isize { ret Timeout }
    if result == -18isize { ret Unsupported }
    if result == -22isize { ret Unsupported }
    if result == -45isize { ret Unsupported }
    if result == -78isize { ret Unsupported }
    // ELOOP: a symlink refused or a cycle.
    if result == -62isize { ret Denied }
    ret Failed
}

fn error_kind_of(code: i32) -> ErrorKind {
    if code == 1i32 || code == 13i32 || code == 62i32 { ret .Denied }
    if code == 2i32 || code == 20i32 { ret .NotFound }
    if code == 4i32 { ret .Interrupted }
    if code == 35i32 { ret .WouldBlock }
    if code == 12i32 { ret .OutOfMemory }
    if code == 17i32 { ret .Exists }
    if code == 22i32 || code == 45i32 || code == 78i32 || code == 18i32 { ret .Unsupported }
    if code == 60i32 { ret .Timeout }
    ret .Other
}

fn kind_of_error(e: err) -> ErrorKind {
    if e == Denied { ret .Denied }
    if e == NotFound { ret .NotFound }
    if e == Interrupted { ret .Interrupted }
    if e == WouldBlock { ret .WouldBlock }
    if e == OutOfMemory { ret .OutOfMemory }
    if e == Exists { ret .Exists }
    if e == Timeout { ret .Timeout }
    if e == Unsupported { ret .Unsupported }
    ret .Other
}

// Every failing call in this file is classified here, which is why the detail is kept here
// and not at each call site.
fn from_errno(result: isize) -> err {
    if result >= 0isize { ret ok }
    last_code = i32(0isize - result)
    ret error_of_result(result)
}

fn detail_from_code(code: i32, operation: str, subject: str) -> ErrorDetail {
    ret ErrorDetail { kind: error_kind_of(code), native_code: code, operation: operation, subject: subject }
}

fn last_error_detail(operation: str, subject: str) -> ErrorDetail {
    ret detail_from_code(last_code, operation, subject)
}

// The runtime's primitives answer an `err`, not the errno, so their detail names only the kind.
fn failed_detail(e: err, operation: str, subject: str) -> ErrorDetail {
    ret ErrorDetail { kind: kind_of_error(e), native_code: 0i32, operation: operation, subject: subject }
}

fn read_detail(f: File, buffer: []u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, read_error) = read(f, buffer)
    if read_error != ok { *detail = failed_detail(read_error, "read", "") }
    ret (count, read_error)
}

fn write_detail(f: File, buffer: []const u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, write_error) = write(f, buffer)
    if write_error != ok { *detail = failed_detail(write_error, "write", "") }
    ret (count, write_error)
}

fn open_detail(a: *mem.Arena, path: str, flags: OpenFlags, detail: *ErrorDetail) -> (File, err) {
    let (file, open_error) = open(a, path, flags)
    if open_error != ok {
        *detail = failed_detail(open_error, "open", path)
        ret (file, open_error)
    }
    ret (file, ok)
}

fn stdin() -> File { ret File { raw: 0usize } }

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

fn kind_from_mode(mode: u32) -> EntryKind {
    let format = mode & FORMAT_MASK
    if format == FORMAT_FILE { ret .File }
    if format == FORMAT_DIRECTORY { ret .Dir }
    if format == FORMAT_SYMLINK { ret .Symlink }
    ret .Other
}

fn stat_with(a: *mem.Arena, path: str, number: usize) -> (FileInfo, err) {
    var info: FileInfo = zero
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (info, path_error)
    }
    var buffer: StatBuffer = zero
    let result = syscall(number, path_address, mem.address_of(&buffer), 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if result < 0isize { ret (info, from_errno(result)) }
    let mode = u32(buffer.mode)
    info.kind = kind_from_mode(mode)
    info.size = u64(buffer.size)
    info.modified_ns = buffer.modified * NANOSECONDS_PER_SECOND + buffer.modified_ns
    info.accessed_ns = buffer.accessed * NANOSECONDS_PER_SECOND + buffer.accessed_ns
    info.created_ns = buffer.born * NANOSECONDS_PER_SECOND + buffer.born_ns
    info.mode = mode & PERMISSION_MASK
    info.file_id = buffer.inode
    info.link_count = u64(buffer.link_count)
    ret (info, ok)
}

fn stat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    let (info, stat_error) = stat_with(a, path, SYS_STAT64)
    ret (info, stat_error)
}

fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    let (info, stat_error) = stat_with(a, path, SYS_LSTAT64)
    ret (info, stat_error)
}

fn stat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = stat(a, path)
    if stat_error != ok { *detail = last_error_detail("stat", path) }
    ret (info, stat_error)
}

fn lstat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = lstat(a, path)
    if stat_error != ok { *detail = last_error_detail("lstat", path) }
    ret (info, stat_error)
}

// One path and one modifier: a mode for mkdir and chmod, nothing for unlink and rmdir.
fn path_syscall(a: *mem.Arena, number: usize, path: str, modifier: usize) -> err {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret path_error
    }
    let result = syscall(number, path_address, modifier, 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

fn mkdir(a: *mem.Arena, path: str) -> err { ret path_syscall(a, SYS_MKDIR, path, DIRECTORY_MODE) }
fn remove_file(a: *mem.Arena, path: str) -> err { ret path_syscall(a, SYS_UNLINK, path, 0usize) }
fn remove_dir(a: *mem.Arena, path: str) -> err { ret path_syscall(a, SYS_RMDIR, path, 0usize) }
fn set_mode(a: *mem.Arena, path: str, mode: u32) -> err { ret path_syscall(a, SYS_CHMOD, path, usize(mode & PERMISSION_MASK)) }
fn set_current_dir(a: *mem.Arena, path: str) -> err { ret path_syscall(a, SYS_CHDIR, path, 0usize) }

fn mkdir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let failure = mkdir(a, path)
    if failure != ok { *detail = last_error_detail("mkdir", path) }
    ret failure
}

fn remove_file_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let failure = remove_file(a, path)
    if failure != ok { *detail = last_error_detail("remove", path) }
    ret failure
}

fn remove_dir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let failure = remove_dir(a, path)
    if failure != ok { *detail = last_error_detail("rmdir", path) }
    ret failure
}

fn rename(a: *mem.Arena, src: str, dst: str) -> err {
    let checkpoint = mem.mark(a)
    let (source_address, source_error) = c_string(a, src)
    if source_error != ok {
        mem.reset(a, checkpoint)
        ret source_error
    }
    let (destination_address, destination_error) = c_string(a, dst)
    if destination_error != ok {
        mem.reset(a, checkpoint)
        ret destination_error
    }
    let result = syscall(SYS_RENAME, source_address, destination_address, 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

fn rename_detail(a: *mem.Arena, src: str, dst: str, detail: *ErrorDetail) -> err {
    let failure = rename(a, src, dst)
    if failure != ok { *detail = last_error_detail("rename", src) }
    ret failure
}

// rename(2) replaces an existing destination; without `overwrite` that is refused first.
// ponytail: `durable` is not honoured (no fsync of the directory).
fn replace(a: *mem.Arena, src: str, dst: str, overwrite: bool, durable: bool) -> err {
    if !overwrite {
        let (existing, existing_error) = lstat(a, dst)
        if existing_error == ok { ret Exists }
    }
    ret rename(a, src, dst)
}

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
    let result = syscall(SYS_SYMLINK, target_address, link_address, 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

fn read_link(a: *mem.Arena, path: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret ("", path_error)
    }
    var capacity = 256usize
    while capacity <= 65536usize {
        let (buffer, allocation_error) = mem.alloc[u8](a, capacity)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let written = syscall(SYS_READLINK, path_address, mem.address_of(&buffer[0usize]), capacity, 0usize, 0usize, 0usize)
        if written < 0isize {
            let call_error = from_errno(written)
            mem.reset(a, checkpoint)
            ret ("", call_error)
        }
        if usize(written) < capacity { ret (buffer[0usize..usize(written)], ok) }
        capacity = capacity * 2usize
    }
    mem.reset(a, checkpoint)
    ret ("", Failed)
}

fn read_link_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err) {
    let (link_target, link_error) = read_link(a, path)
    if link_error != ok { *detail = last_error_detail("readlink", path) }
    ret (link_target, link_error)
}

// utimes(2) takes microsecond timevals; a negative stamp keeps the file's own.
fn set_times(a: *mem.Arena, path: str, accessed_ns: i64, modified_ns: i64) -> err {
    var accessed = accessed_ns
    var modified = modified_ns
    if accessed < 0i64 || modified < 0i64 {
        let (current, current_error) = stat(a, path)
        if current_error != ok { ret current_error }
        if accessed < 0i64 { accessed = current.accessed_ns }
        if modified < 0i64 { modified = current.modified_ns }
    }
    var times: [4]i64 = zero
    times[0usize] = accessed / NANOSECONDS_PER_SECOND
    times[1usize] = (accessed % NANOSECONDS_PER_SECOND) / 1000i64
    times[2usize] = modified / NANOSECONDS_PER_SECOND
    times[3usize] = (modified % NANOSECONDS_PER_SECOND) / 1000i64
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret path_error
    }
    let result = syscall(SYS_UTIMES, path_address, mem.address_of(&times[0usize]), 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    ret from_errno(result)
}

// A file's path from its descriptor, which is how the kernel names a directory: F_GETPATH on
// an open `.` is getcwd, and on any path is realpath.
fn path_of(a: *mem.Arena, path: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret ("", path_error)
    }
    let descriptor = syscall(SYS_OPEN, path_address, O_RDONLY | O_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
    if descriptor < 0isize {
        let open_error = from_errno(descriptor)
        mem.reset(a, checkpoint)
        ret ("", open_error)
    }
    let (buffer, allocation_error) = mem.alloc[u8](a, PATH_MAX)
    if allocation_error != ok {
        let ignored = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        mem.reset(a, checkpoint)
        ret ("", OutOfMemory)
    }
    let result = syscall(SYS_FCNTL, usize(descriptor), F_GETPATH, mem.address_of(&buffer[0usize]), 0usize, 0usize, 0usize)
    let ignored_close = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
    if result < 0isize {
        let call_error = from_errno(result)
        mem.reset(a, checkpoint)
        ret ("", call_error)
    }
    var length = 0usize
    while length < PATH_MAX && buffer[length] != 0u8 { length += 1usize }
    ret (buffer[0usize..length], ok)
}

fn current_dir(a: *mem.Arena) -> (str, err) {
    let (directory, directory_error) = path_of(a, ".")
    ret (directory, directory_error)
}

fn canonical(a: *mem.Arena, path: str) -> (str, err) {
    let (resolved, resolve_error) = path_of(a, path)
    ret (resolved, resolve_error)
}

fn canonical_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err) {
    let (resolved, resolve_error) = canonical(a, path)
    if resolve_error != ok { *detail = last_error_detail("canonical", path) }
    ret (resolved, resolve_error)
}

fn create_new_with_mode(a: *mem.Arena, path: str, mode: u32) -> (File, err) {
    var file: File = zero
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (file, path_error)
    }
    let descriptor = syscall(SYS_OPEN, path_address, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, usize(mode & PERMISSION_MASK), 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize { ret (file, from_errno(descriptor)) }
    file.raw = usize(descriptor)
    ret (file, ok)
}

fn create_new(a: *mem.Arena, path: str) -> (File, err) {
    let (file, create_error) = create_new_with_mode(a, path, 420u32)
    ret (file, create_error)
}

fn create_new_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (File, err) {
    let (file, create_error) = create_new(a, path)
    if create_error != ok {
        *detail = last_error_detail("create", path)
        ret (file, create_error)
    }
    ret (file, ok)
}

// getentropy(2) fills at most 256 bytes a call.
fn random(buffer: []u8) -> err {
    var filled = 0usize
    while filled < buffer.len {
        var chunk = buffer.len - filled
        if chunk > 256usize { chunk = 256usize }
        let result = syscall(SYS_GETENTROPY, mem.address_of(&buffer[filled]), chunk, 0usize, 0usize, 0usize, 0usize)
        if result < 0isize { ret from_errno(result) }
        filled += chunk
    }
    ret ok
}


// Every entry but `.` and `..`, its name copied into the arena and its kind from d_type,
// read a block at a time with getdirentries64: d_ino, d_seekoff, d_reclen, d_namlen, d_type,
// then the name.
fn readdir(a: *mem.Arena, path: str) -> ([]DirEntry, err) {
    var none: []DirEntry = zero
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (none, path_error)
    }
    let descriptor = syscall(SYS_OPEN, path_address, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
    if descriptor < 0isize {
        let open_error = from_errno(descriptor)
        mem.reset(a, checkpoint)
        ret (none, open_error)
    }
    var capacity = 16usize
    let (first, first_error) = mem.alloc[DirEntry](a, capacity)
    if first_error != ok {
        let ignored = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        mem.reset(a, checkpoint)
        ret (none, OutOfMemory)
    }
    var entries = first
    var count = 0usize
    var block: [8192]u8 = zero
    var base: i64 = 0i64
    while true {
        let got = syscall(SYS_GETDIRENTRIES64, usize(descriptor), mem.address_of(&block[0usize]), 8192usize, mem.address_of(&base), 0usize, 0usize)
        if got < 0isize {
            let read_error = from_errno(got)
            let ignored = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
            mem.reset(a, checkpoint)
            ret (none, read_error)
        }
        if got == 0isize { break }
        var at = 0usize
        while at < usize(got) {
            let record_length = usize(block[at + 16usize]) | (usize(block[at + 17usize]) << 8usize)
            let name_length = usize(block[at + 18usize]) | (usize(block[at + 19usize]) << 8usize)
            let type_byte = block[at + 20usize]
            let name_at = at + 21usize
            var skip = false
            if name_length == 1usize && block[name_at] == 46u8 { skip = true }
            if name_length == 2usize && block[name_at] == 46u8 && block[name_at + 1usize] == 46u8 { skip = true }
            if !skip {
                if count == capacity {
                    let (grown, grown_error) = mem.alloc[DirEntry](a, capacity * 2usize)
                    if grown_error != ok {
                        let ignored = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
                        mem.reset(a, checkpoint)
                        ret (none, OutOfMemory)
                    }
                    var copy = 0usize
                    while copy < count {
                        grown[copy] = entries[copy]
                        copy += 1usize
                    }
                    entries = grown
                    capacity = capacity * 2usize
                }
                let (name_bytes, name_error) = mem.alloc[u8](a, name_length)
                if name_error != ok {
                    let ignored = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
                    mem.reset(a, checkpoint)
                    ret (none, OutOfMemory)
                }
                var letter = 0usize
                while letter < name_length {
                    name_bytes[letter] = block[name_at + letter]
                    letter += 1usize
                }
                var kind = EntryKind.Other
                if type_byte == 8u8 { kind = .File }
                if type_byte == 4u8 { kind = .Dir }
                if type_byte == 10u8 { kind = .Symlink }
                entries[count] = DirEntry { name: name_bytes[0usize..name_length], kind: kind }
                count += 1usize
            }
            if record_length == 0usize { break }
            at += record_length
        }
    }
    let ignored_close = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
    ret (entries[0usize..count], ok)
}

// Directory handles: a descriptor, with the openat family relative to it. The Linux variant
// resolves under RESOLVE_BENEATH with openat2; macOS has no such call, so a path that is
// absolute or climbs with `..` is refused here and links are refused with O_NOFOLLOW_ANY.
type Dir = resource(dir_close) struct { raw: usize }
type ResolvePolicy = enum u8 { NoSymlinks, Beneath }

const SYS_OPENAT: usize = 463usize
const SYS_RENAMEAT: usize = 465usize
const SYS_UNLINKAT: usize = 472usize
const SYS_RENAMEATX: usize = 488usize
const SYS_FSYNC: usize = 95usize
const AT_FDCWD: usize = 18446744073709551516usize
const AT_REMOVEDIR: usize = 128usize
const O_WRONLY: usize = 1usize
const O_TRUNC: usize = 1024usize
const O_APPEND: usize = 8usize
const O_NOFOLLOW_ANY: usize = 536870912usize
const RENAME_EXCL: usize = 4usize
const FILE_MODE: usize = 438usize

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

fn open_bits(flags: OpenFlags) -> usize {
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
    let descriptor = syscall(SYS_OPEN, path_address, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize { ret (dir, from_errno(descriptor)) }
    dir.raw = usize(descriptor)
    ret (dir, ok)
}

fn dir_close(dir: own Dir) -> err {
    let result = syscall(SYS_CLOSE, dir.raw, 0usize, 0usize, 0usize, 0usize, 0usize)
    ret from_errno(result)
}

fn dir_open_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (Dir, err) {
    let (dir, open_error) = dir_open(a, path)
    if open_error != ok {
        *detail = last_error_detail("dir_open", path)
        ret (dir, open_error)
    }
    ret (dir, ok)
}

fn open_at(a: *mem.Arena, dir: Dir, relative_path: str, flags: OpenFlags, policy: ResolvePolicy) -> (File, err) {
    var file: File = zero
    if !relative_path_ok(relative_path) { ret (file, Denied) }
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, relative_path)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret (file, path_error)
    }
    var bits = open_bits(flags)
    if policy == .NoSymlinks { bits = bits | O_NOFOLLOW_ANY }
    var mode = 0usize
    if flags.create { mode = FILE_MODE }
    let descriptor = syscall(SYS_OPENAT, dir.raw, path_address, bits, mode, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize { ret (file, from_errno(descriptor)) }
    file.raw = usize(descriptor)
    ret (file, ok)
}

// The parent of the final component, opened with links refused, so the last name is acted
// on relative to it. The returned handle is the caller's to close only when it is not the
// one passed in.
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
    if tail.len == 0usize { ret (parent, "", Denied) }
    let checkpoint = mem.mark(a)
    let (head_address, head_error) = c_string(a, head)
    if head_error != ok {
        mem.reset(a, checkpoint)
        ret (parent, "", head_error)
    }
    let descriptor = syscall(SYS_OPENAT, dir.raw, head_address, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize { ret (parent, "", from_errno(descriptor)) }
    parent.raw = usize(descriptor)
    ret (parent, tail, ok)
}

@unsafe
fn release_parent(parent: own Dir, dir: Dir) {
    if parent.raw != dir.raw {
        let closed = syscall(SYS_CLOSE, parent.raw, 0usize, 0usize, 0usize, 0usize, 0usize)
    }
}

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
        result = syscall(SYS_RENAMEATX, src_parent.raw, from_address, dst_parent.raw, to_address, RENAME_EXCL, 0usize)
    }
    var answer = ok
    if result < 0isize { answer = from_errno(result) }
    if answer == ok && durable {
        let flushed = syscall(SYS_FSYNC, dst_parent.raw, 0usize, 0usize, 0usize, 0usize, 0usize)
        if flushed < 0isize { answer = from_errno(flushed) }
    }
    mem.reset(a, checkpoint)
    release_parent(src_parent, src_dir)
    release_parent(dst_parent, dst_dir)
    ret answer
}

// File mappings and change watches are not served on macOS yet; e.fs compiles against these
// and they answer Unsupported.
type Mapping = resource(mapping_close) struct { raw: usize, address: *u8, len: usize }
type Watch = resource(watch_close) struct { state: *void }
type WatchAction = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type WatchEvent = struct { action: WatchAction, path: str, old_path: str }

const SYS_MMAP: usize = 197usize
const SYS_MUNMAP: usize = 73usize
const SYS_MSYNC: usize = 65usize
const PROT_READ: usize = 1usize
const PROT_WRITE: usize = 2usize
const MAP_SHARED: usize = 1usize
const MAP_FIXED: usize = 16usize
const MS_SYNC: usize = 16usize
const MAPPING_READ_ONLY: usize = 0usize
const MAPPING_WRITABLE: usize = 1usize

// A file mapped shared over address space `reserve` set aside; `offset` must be a multiple of the page
// size (16 KB on Apple Silicon). `raw` records whether it may be written.
fn map_file(f: File, offset: u64, len: usize, writable: bool) -> (Mapping, err) {
    var mapping: Mapping = zero
    if len == 0usize { ret (mapping, Failed) }
    var protection = PROT_READ
    if writable { protection = PROT_READ | PROT_WRITE }
    let (address, reserve_error) = reserve(len)
    if reserve_error != ok { ret (mapping, reserve_error) }
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

// The other half of `reserve`: the pages given back.
fn release(p: *u8, n: usize) -> err {
    ret from_errno(syscall(SYS_MUNMAP, mem.address_of(p), n, 0usize, 0usize, 0usize, 0usize))
}

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
// would fault.
fn mapping_bytes_mut(m: Mapping) -> ([]u8, err) {
    var nothing: []u8 = zero
    if m.raw != MAPPING_WRITABLE { ret (nothing, Unsupported) }
    ret (mapping_region(m), ok)
}

fn mapping_flush(m: Mapping) -> err {
    ret from_errno(syscall(SYS_MSYNC, mem.address_of(m.address), m.len, MS_SYNC, 0usize, 0usize, 0usize))
}

fn mapping_close(m: own Mapping) -> err {
    ret from_errno(syscall(SYS_MUNMAP, mem.address_of(m.address), m.len, 0usize, 0usize, 0usize, 0usize))
}

// Change watches are kqueue's. A vnode event wakes the wait but names nothing, so a watch keeps
// a snapshot of the directory -- each entry's name, inode, size and modification time -- and a
// wake is a rescan and a diff against it: a new name is Added, a missing one Removed, a changed
// size or time Modified. Every entry, and the directory, is registered for vnode events so a
// change to a file's contents wakes the wait too, not only a change to the listing.
// ponytail: at most WATCH_ENTRIES (and 64 directories to descend into) are tracked; a larger
// tree is watched for its first ones, breadth first.
const SYS_KQUEUE: usize = 362usize
const SYS_KEVENT: usize = 363usize
const EVFILT_VNODE: i16 = -4i16
const EV_ADD_CLEAR: u16 = 33u16
const NOTE_ALL_VNODE: u32 = 63u32
const O_EVTONLY: usize = 32768usize
const O_SYMLINK: usize = 2097152usize
const WATCH_ENTRIES: usize = 256usize
const WATCH_NAME: usize = 256usize

// `struct kevent`, 32 bytes: the identifier (a descriptor), the filter, the flags, the filter's
// flags, its data, and the caller's word.
type Kevent = struct { ident: u64, filter: i16, flags: u16, fflags: u32, data: i64, udata: u64 }
type Snapshot = struct { name: [256]u8, name_length: usize, inode: u64, size: u64, modified_ns: i64, descriptor: isize, live: bool, directory: bool }
type WatchState = struct { queue: usize, directory: usize, base: str, recursive: bool, entries: [256]Snapshot, found: [256]bool }

fn snapshot_has(entry: *const Snapshot, name: str) -> bool {
    if !entry.live || entry.name_length != name.len { ret false }
    var at = 0usize
    while at < name.len {
        if entry.name[at] != name[at] { ret false }
        at += 1usize
    }
    ret true
}

fn snapshot_find(state: *WatchState, name: str) -> isize {
    var at = 0usize
    while at < WATCH_ENTRIES {
        if snapshot_has(&state.entries[at], name) { ret isize(at) }
        at += 1usize
    }
    ret -1isize
}

fn snapshot_free(state: *WatchState) -> isize {
    var at = 0usize
    while at < WATCH_ENTRIES {
        if !state.entries[at].live { ret isize(at) }
        at += 1usize
    }
    ret -1isize
}

// A descriptor opened only to be watched, registered on the queue for every vnode event;
// -1 when it could not be had, in which case the entry is still diffed but cannot wake a wait.
fn watch_register(a: *mem.Arena, state: *WatchState, full: str) -> isize {
    let checkpoint = mem.mark(a)
    let (path_address, path_error) = c_string(a, full)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret -1isize
    }
    let descriptor = syscall(SYS_OPEN, path_address, O_RDONLY | O_EVTONLY | O_SYMLINK | O_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
    mem.reset(a, checkpoint)
    if descriptor < 0isize { ret -1isize }
    var change: Kevent = zero
    change.ident = u64(descriptor)
    change.filter = EVFILT_VNODE
    change.flags = EV_ADD_CLEAR
    change.fflags = NOTE_ALL_VNODE
    let added = syscall(SYS_KEVENT, state.queue, mem.address_of(&change), 1usize, 0usize, 0usize, 0usize)
    if added < 0isize {
        let closed = syscall(SYS_CLOSE, usize(descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret -1isize
    }
    ret descriptor
}

// The watched directory and a name joined, in the arena.
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

// The entries to watch, each by its path relative to the watched directory: its direct children,
// and with `recursive` the children of every directory found, breadth first, up to WATCH_ENTRIES
// entries and WATCH_QUEUE directories. A directory that goes away between being found and
// being read is skipped; the top one failing is the caller's error.
const WATCH_QUEUE: usize = 64usize

fn watch_collect(a: *mem.Arena, base: str, recursive: bool) -> ([]DirEntry, err) {
    var none: []DirEntry = zero
    let (out, out_error) = mem.alloc[DirEntry](a, WATCH_ENTRIES)
    if out_error != ok { ret (none, OutOfMemory) }
    let (queue, queue_error) = mem.alloc[str](a, WATCH_QUEUE)
    if queue_error != ok { ret (none, OutOfMemory) }
    queue[0usize] = ""
    var head = 0usize
    var tail = 1usize
    var count = 0usize
    while head < tail && count < WATCH_ENTRIES {
        let relative = queue[head]
        head += 1usize
        var directory = base
        if relative.len != 0usize {
            let (joined, join_error) = watch_path(a, base, relative)
            if join_error != ok { ret (none, join_error) }
            directory = joined
        }
        let (listing, listing_error) = readdir(a, directory)
        if listing_error != ok {
            if head == 1usize { ret (none, listing_error) }
            continue
        }
        var at = 0usize
        while at < listing.len && count < WATCH_ENTRIES {
            var name = listing[at].name
            if relative.len != 0usize {
                let (nested, nested_error) = watch_path(a, relative, name)
                if nested_error != ok { ret (none, nested_error) }
                name = nested
            }
            out[count] = DirEntry { name: name, kind: listing[at].kind }
            count += 1usize
            if recursive && listing[at].kind == .Dir && tail < WATCH_QUEUE {
                queue[tail] = name
                tail += 1usize
            }
            at += 1usize
        }
    }
    ret (out[0usize..count], ok)
}

fn watch_open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err) {
    var watch: Watch = zero
    let queue = syscall(SYS_KQUEUE, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if queue < 0isize { ret (watch, from_errno(queue)) }
    let (holder, holder_error) = mem.alloc[WatchState](a, 1usize)
    if holder_error != ok {
        let closed = syscall(SYS_CLOSE, usize(queue), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (watch, OutOfMemory)
    }
    let state = &holder[0usize]
    // `mem.alloc` hands back memory as it was, so the snapshot is cleared here.
    var clear = 0usize
    while clear < WATCH_ENTRIES {
        state.entries[clear].live = false
        state.entries[clear].name_length = 0usize
        state.entries[clear].descriptor = -1isize
        state.found[clear] = false
        clear += 1usize
    }
    state.queue = usize(queue)
    state.base = path
    state.recursive = recursive
    // The directory itself, so a name added or removed wakes the wait.
    let directory = watch_register(a, state, path)
    if directory < 0isize {
        let closed = syscall(SYS_CLOSE, usize(queue), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (watch, Failed)
    }
    state.directory = usize(directory)
    // The first snapshot: what is there now is not news.
    let (listing, listing_error) = watch_collect(a, path, recursive)
    if listing_error != ok {
        let closed = syscall(SYS_CLOSE, usize(queue), 0usize, 0usize, 0usize, 0usize, 0usize)
        let closed_directory = syscall(SYS_CLOSE, usize(directory), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (watch, listing_error)
    }
    var at = 0usize
    while at < listing.len {
        let slot = snapshot_free(state)
        if slot < 0isize { break }
        let name = listing[at].name
        if name.len < WATCH_NAME {
            let (full, full_error) = watch_path(a, path, name)
            if full_error == ok {
                let (info, info_error) = lstat(a, full)
                if info_error == ok {
                    var entry = &state.entries[usize(slot)]
                    var letter = 0usize
                    while letter < name.len {
                        entry.name[letter] = name[letter]
                        letter += 1usize
                    }
                    entry.name_length = name.len
                    entry.inode = info.file_id
                    entry.size = info.size
                    entry.modified_ns = info.modified_ns
                    entry.directory = info.kind == .Dir
                    entry.descriptor = watch_register(a, state, full)
                    entry.live = true
                }
            }
        }
        at += 1usize
    }
    watch.state = mem.cast[*void](state)
    ret (watch, ok)
}

// The next changes, waiting for one if there are none: a rescan first, since a change may have
// landed since the last, then the kqueue until something moves. At most `events.len` are
// reported at a time; the snapshot is updated only for those, so the rest are found again.
fn watch_read(a: *mem.Arena, w: Watch, events: []WatchEvent) -> (usize, err) {
    let state = mem.cast[*WatchState](w.state)
    if events.len == 0usize { ret (0usize, ok) }
    while true {
        let checkpoint = mem.mark(a)
        let (listing, listing_error) = watch_collect(a, state.base, state.recursive)
        if listing_error != ok {
            mem.reset(a, checkpoint)
            ret (0usize, listing_error)
        }
        // Names seen this scan are marked; whatever stays unmarked in the snapshot is gone.
        var mark = 0usize
        while mark < WATCH_ENTRIES {
            state.found[mark] = false
            mark += 1usize
        }
        var produced = 0usize
        var at = 0usize
        while at < listing.len && produced < events.len {
            let name = listing[at].name
            at += 1usize
            if name.len >= WATCH_NAME { continue }
            let slot = snapshot_find(state, name)
            let (full, full_error) = watch_path(a, state.base, name)
            if full_error != ok { ret (produced, full_error) }
            let (info, info_error) = lstat(a, full)
            if info_error != ok { continue }
            if slot < 0isize {
                let free = snapshot_free(state)
                if free < 0isize { continue }
                var entry = &state.entries[usize(free)]
                var letter = 0usize
                while letter < name.len {
                    entry.name[letter] = name[letter]
                    letter += 1usize
                }
                entry.name_length = name.len
                entry.inode = info.file_id
                entry.size = info.size
                entry.modified_ns = info.modified_ns
                entry.directory = info.kind == .Dir
                entry.descriptor = watch_register(a, state, full)
                entry.live = true
                state.found[usize(free)] = true
                var added: WatchEvent = zero
                added.action = .Added
                added.path = full
                events[produced] = added
                produced += 1usize
            } else {
                state.found[usize(slot)] = true
                var entry = &state.entries[usize(slot)]
                if entry.inode != info.file_id || entry.size != info.size || entry.modified_ns != info.modified_ns {
                    entry.inode = info.file_id
                    entry.size = info.size
                    entry.modified_ns = info.modified_ns
                    // A directory's own time moves with its listing, which is reported as the
                    // names that came and went and not as the directory changing.
                    if !entry.directory {
                        var changed: WatchEvent = zero
                        changed.action = .Modified
                        changed.path = full
                        events[produced] = changed
                        produced += 1usize
                    }
                }
            }
        }
        // The names that are gone, when every name has been looked at and room is left.
        if at >= listing.len {
            var gone = 0usize
            while gone < WATCH_ENTRIES && produced < events.len {
                var entry = &state.entries[gone]
                if entry.live && !state.found[gone] {
                    let (full, full_error) = watch_path(a, state.base, entry.name[0usize..entry.name_length])
                    if full_error != ok { ret (produced, full_error) }
                    if entry.descriptor >= 0isize {
                        let closed = syscall(SYS_CLOSE, usize(entry.descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
                    }
                    entry.live = false
                    var removed: WatchEvent = zero
                    removed.action = .Removed
                    removed.path = full
                    events[produced] = removed
                    produced += 1usize
                }
                gone += 1usize
            }
        }
        if produced != 0usize { ret (produced, ok) }
        mem.reset(a, checkpoint)
        // Nothing changed: wait for the kernel to say something did.
        var arrived: Kevent = zero
        let waited = syscall(SYS_KEVENT, state.queue, 0usize, 0usize, mem.address_of(&arrived), 1usize, 0usize)
        if waited < 0isize && waited != -4isize { ret (0usize, from_errno(waited)) }
    }
    ret (0usize, ok)
}

fn watch_close(w: own Watch) -> err {
    let state = mem.cast[*WatchState](w.state)
    var at = 0usize
    while at < WATCH_ENTRIES {
        if state.entries[at].live && state.entries[at].descriptor >= 0isize {
            let closed = syscall(SYS_CLOSE, usize(state.entries[at].descriptor), 0usize, 0usize, 0usize, 0usize, 0usize)
        }
        at += 1usize
    }
    let closed_directory = syscall(SYS_CLOSE, state.directory, 0usize, 0usize, 0usize, 0usize, 0usize)
    ret from_errno(syscall(SYS_CLOSE, state.queue, 0usize, 0usize, 0usize, 0usize, 0usize))
}

// ---------------------------------------------------------------- environment and processes

const SYS_PIPE: usize = 42usize
const SYS_DUP: usize = 41usize
const SYS_DUP2: usize = 90usize
const SYS_KILL: usize = 37usize
const SYS_WAIT4: usize = 7usize
const SYS_FCHDIR: usize = 13usize
const SYS_POSIX_SPAWN: usize = 244usize
const SYS_POLL: usize = 230usize
const SIGKILL: usize = 9usize
const SIGTERM: usize = 15usize
const SPAWN_LIST_MAX: usize = 1024usize
const EXEC_FAILED: usize = 127usize

type ProcUsage = struct { exit_code: i32, peak_memory: usize }
type SpawnOptions = struct { argv: []const str, env: []const str, inherit_env: bool, cwd: str, stdio: Stdio }
type ProcGroup = resource(proc_group_close) struct { raw: usize }
// `struct rusage`: two `timeval`s and then fourteen longs, of which `ru_maxrss` is the first
// -- bytes on macOS.
type Rusage = struct { words: [18]i64 }

// One NAME=VALUE record at a time. The name has to match to its whole length and end at the
// `=`, or a lookup of `PAT` would be answered by `PATH`.
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

// The environment the process was started with. Nothing in this language changes an
// environment, so the block the entry saved is the whole truth.
fn env(a: *mem.Arena, name: str) -> (str, err) {
    let (block, block_error) = env_block(a)
    if block_error != ok { ret ("", block_error) }
    let (value, found) = environment_value(block, name)
    if !found { ret ("", NotFound) }
    ret (value, ok)
}

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
// sets is dropped in favour of theirs.
fn environment_vector(a: *mem.Arena, additions: []const str) -> (usize, err) {
    if additions.len >= SPAWN_LIST_MAX { ret (0usize, Failed) }
    let (block, block_error) = env_block(a)
    if block_error != ok { ret (0usize, block_error) }
    let (vector, vector_error) = mem.alloc[usize](a, SPAWN_LIST_MAX)
    if vector_error != ok { ret (0usize, OutOfMemory) }
    var count = 0usize
    var at = 0usize
    while at < block.len && count + additions.len + 1usize < SPAWN_LIST_MAX {
        var end = at
        while end < block.len && block[end] != 0u8 { end = end + 1usize }
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

// posix_spawn(2) is the one way to start a process here: fork without libSystem leaves the
// child with no Mach state to exec from. It has no file actions in this call, so the child's
// descriptors 0 to 2 are set up in the parent around it -- saved, replaced by the stdio the
// caller named, and put back -- and likewise the working directory. That is not safe against
// another thread spawning at the same moment.
// ponytail: stdio and cwd are swapped in the parent around the spawn; add
// POSIX_SPAWN file actions (psfa) when threads exist on macOS.
fn spawn_with_options(a: *mem.Arena, options: SpawnOptions) -> (Proc, err) {
    let (child, spawn_error) = spawn_inner(a, options, false)
    ret (child, spawn_error)
}

fn spawn_inner(a: *mem.Arena, options: SpawnOptions, grouped: bool) -> (Proc, err) {
    var child: Proc = zero
    if options.argv.len == 0usize { ret (child, Failed) }
    let (program, program_error) = c_string(a, options.argv[0usize])
    if program_error != ok { ret (child, program_error) }
    let (argv, argv_error) = c_string_vector(a, options.argv)
    if argv_error != ok { ret (child, argv_error) }
    var envp = 0usize
    if options.inherit_env {
        let (inherited, inherited_error) = environment_vector(a, options.env)
        if inherited_error != ok { ret (child, inherited_error) }
        envp = inherited
    } else {
        let (own_vector, own_error) = c_string_vector(a, options.env)
        if own_error != ok { ret (child, own_error) }
        envp = own_vector
    }
    var directory = 0usize
    var home = 0isize
    if options.cwd.len != 0usize {
        let (directory_address, directory_error) = c_string(a, options.cwd)
        if directory_error != ok { ret (child, directory_error) }
        directory = directory_address
        let (dot, dot_error) = c_string(a, ".")
        if dot_error != ok { ret (child, dot_error) }
        home = syscall(SYS_OPEN, dot, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0usize, 0usize, 0usize, 0usize)
        if home < 0isize { ret (child, from_errno(home)) }
        let moved = syscall(SYS_CHDIR, directory, 0usize, 0usize, 0usize, 0usize, 0usize)
        if moved < 0isize {
            let closed = syscall(SYS_CLOSE, usize(home), 0usize, 0usize, 0usize, 0usize, 0usize)
            ret (child, from_errno(moved))
        }
    }
    var saved: [3]isize = zero
    var slot = 0usize
    while slot < 3usize {
        saved[slot] = -1isize
        var wanted = stdio_raw(options.stdio, slot)
        if wanted != slot {
            saved[slot] = syscall(SYS_DUP, slot, 0usize, 0usize, 0usize, 0usize, 0usize)
            let bound = syscall(SYS_DUP2, wanted, slot, 0usize, 0usize, 0usize, 0usize)
        }
        slot += 1usize
    }
    var pid: i32 = 0i32
    var description: [32]i64 = zero
    // A group is the child's own, made by the kernel as it starts: POSIX_SPAWN_SETPGROUP (2) in
    // the attribute block's flags, with a group of 0 meaning the child's pid. Afterwards it is too
    // late -- setpgid on a child that has exec'd answers EACCES. The descriptor's first word is
    // the attribute block's size and its second the block's address; the flags are the first
    // short of the block and the group its fourth word, so a 16-byte block is enough.
    var attributes: [4]i32 = zero
    if grouped {
        attributes[0usize] = 2i32
        description[0usize] = 16i64
        description[1usize] = i64(mem.address_of(&attributes[0usize]))
    }
    let result = syscall(SYS_POSIX_SPAWN, mem.address_of(&pid), program, mem.address_of(&description[0usize]), argv, envp, 0usize)
    var restore = 0usize
    while restore < 3usize {
        if saved[restore] >= 0isize {
            let back = syscall(SYS_DUP2, usize(saved[restore]), restore, 0usize, 0usize, 0usize, 0usize)
            let closed = syscall(SYS_CLOSE, usize(saved[restore]), 0usize, 0usize, 0usize, 0usize, 0usize)
        }
        restore += 1usize
    }
    if home >= 0isize && directory != 0usize {
        let back = syscall(SYS_FCHDIR, usize(home), 0usize, 0usize, 0usize, 0usize, 0usize)
        let closed = syscall(SYS_CLOSE, usize(home), 0usize, 0usize, 0usize, 0usize, 0usize)
    }
    if result < 0isize { ret (child, from_errno(result)) }
    child.raw = usize(pid)
    ret (child, ok)
}

fn stdio_raw(stdio: Stdio, slot: usize) -> usize {
    if slot == 0usize { ret stdio.stdin.raw }
    if slot == 1usize { ret stdio.stdout.raw }
    ret stdio.stderr.raw
}

// `wait`, and what the child's peak was: `wait4` hands both back at once.
@unsafe
fn wait_usage(p: own Proc) -> (ProcUsage, err) {
    var usage: ProcUsage = zero
    usage.exit_code = -1i32
    var status = 0u32
    var used: Rusage = zero
    let result = syscall(SYS_WAIT4, p.raw, mem.address_of(&status), 0usize, mem.address_of(&used), 0usize, 0usize)
    if result < 0isize { ret (usage, from_errno(result)) }
    if status & 127u32 == 0u32 {
        usage.exit_code = i32((status >> 8u32) & 255u32)
    } else {
        usage.exit_code = i32(128u32 + (status & 127u32))
    }
    usage.peak_memory = usize(used.words[4usize])
    ret (usage, ok)
}

fn peak_memory() -> (usize, err) { ret (0usize, Unsupported) }

// SIGKILL, so this is not a request.
fn kill(p: Proc) -> err {
    ret from_errno(syscall(SYS_KILL, p.raw, SIGKILL, 0usize, 0usize, 0usize, 0usize))
}

// pipe(2) answers with two descriptors; the runtime's syscall stores them to the slots the
// first argument names. macOS has no pipe2, so they are not close-on-exec.
fn pipe() -> (File, File, err) {
    var reading: File = zero
    var writing: File = zero
    var pair: [2]i32 = zero
    let result = syscall(SYS_PIPE, mem.address_of(&pair[0usize]), 0usize, 0usize, 0usize, 0usize, 0usize)
    if result < 0isize { ret (reading, writing, from_errno(result)) }
    reading.raw = usize(pair[0usize])
    writing.raw = usize(pair[1usize])
    ret (reading, writing, ok)
}

// A read that does not wait: poll for zero time, then read.
fn pipe_read(f: File, buffer: []u8) -> (usize, err) {
    if buffer.len == 0usize { ret (0usize, ok) }
    var descriptor: [2]u32 = zero
    descriptor[0usize] = u32(f.raw)
    descriptor[1usize] = 1u32
    let ready = syscall(SYS_POLL, mem.address_of(&descriptor[0usize]), 1usize, 0usize, 0usize, 0usize, 0usize)
    if ready < 0isize { ret (0usize, from_errno(ready)) }
    if ready == 0isize { ret (0usize, WouldBlock) }
    let taken = syscall(3usize, f.raw, mem.address_of(&buffer[0usize]), buffer.len, 0usize, 0usize, 0usize)
    if taken < 0isize { ret (0usize, from_errno(taken)) }
    ret (usize(taken), ok)
}

fn dup(f: File) -> (File, err) {
    var second: File = zero
    let result = syscall(SYS_DUP, f.raw, 0usize, 0usize, 0usize, 0usize, 0usize)
    if result < 0isize { ret (second, from_errno(result)) }
    second.raw = usize(result)
    ret (second, ok)
}

// The group is the child's own and its identifier is the child's pid. Containment is what the
// host gives and no more: a descendant that starts a group of its own leaves it.
fn proc_group_spawn(a: *mem.Arena, options: SpawnOptions) -> (ProcGroup, Proc, err) {
    var group: ProcGroup = zero
    let (child, spawn_error) = spawn_inner(a, options, true)
    if spawn_error != ok { ret (group, child, spawn_error) }
    group.raw = child.raw
    ret (group, child, ok)
}

// A negative pid is the whole group, which is what killpg is.
fn proc_group_terminate(group: ProcGroup, force: bool) -> err {
    var number = SIGTERM
    if force { number = SIGKILL }
    let negated = 0usize -% group.raw
    let result = syscall(SYS_KILL, negated, number, 0usize, 0usize, 0usize, 0usize)
    // ESRCH: the group is already empty, which is what termination was after.
    if result == -3isize { ret ok }
    ret from_errno(result)
}

// A group identifier is not a handle here, so there is nothing to give back.
fn proc_group_close(group: own ProcGroup) -> err { ret ok }

// ---------------------------------------------------------------- libraries, signals, the executable

// libSystem's loader. The name is passed as it was given, as `@import` takes one: nothing is
// added to it, so "libvulkan.dylib" and "/usr/lib/libz.dylib" both work.
type Lib = resource(dlclose) struct { raw: usize }

@import("c", "dlopen")
extern fn raw_dlopen(name: usize, flags: i32) -> usize

@import("c", "dlsym")
extern fn raw_dlsym(handle: usize, symbol: usize) -> usize

@import("c", "dlclose")
extern fn raw_dlclose(handle: usize) -> i32

@import("c", "_NSGetExecutablePath")
extern fn raw_executable_path(buffer: usize, size: usize) -> i32

@import("c", "sigaction")
extern fn raw_sigaction(number: i32, action: usize, previous: usize) -> i32

const RTLD_NOW: i32 = 2i32

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

fn dlopen(a: *mem.Arena, name: str) -> (Lib, err) {
    var library: Lib = zero
    if name.len == 0usize { ret (library, NotFound) }
    let (bytes, bytes_error) = c_string_bytes(a, name)
    if bytes_error != ok { ret (library, bytes_error) }
    let handle = raw_dlopen(mem.address_of(&bytes[0usize]), RTLD_NOW)
    // `dlerror` says why, and there is nowhere to keep it: a name that will not load is
    // reported as one that was not found.
    if handle == 0usize { ret (library, NotFound) }
    library.raw = handle
    ret (library, ok)
}

fn dl_lookup(a: *mem.Arena, l: Lib, sym: str) -> (usize, err) {
    if sym.len == 0usize { ret (0usize, NotFound) }
    let (bytes, bytes_error) = c_string_bytes(a, sym)
    if bytes_error != ok { ret (0usize, bytes_error) }
    let address = raw_dlsym(l.raw, mem.address_of(&bytes[0usize]))
    if address == 0usize { ret (0usize, NotFound) }
    ret (address, ok)
}

fn dlclose(l: own Lib) -> err {
    if raw_dlclose(l.raw) != 0i32 { ret Failed }
    ret ok
}

// The path of the running image, from dyld, made canonical: `_NSGetExecutablePath` answers
// the path the process was started by, which may be relative or run through a link.
fn executable_path(a: *mem.Arena) -> (str, err) {
    var capacity = 1024usize
    while capacity <= 65536usize {
        let (buffer, allocation_error) = mem.alloc[u8](a, capacity)
        if allocation_error != ok { ret ("", OutOfMemory) }
        var size = u32(capacity)
        let answer = raw_executable_path(mem.address_of(&buffer[0usize]), mem.address_of(&size))
        if answer == 0i32 {
            var length = 0usize
            while length < capacity && buffer[length] != 0u8 { length += 1usize }
            let (resolved, resolve_error) = canonical(a, buffer[0usize..length])
            ret (resolved, resolve_error)
        }
        // A negative answer is the size it needed.
        capacity = capacity * 2usize
    }
    ret ("", Failed)
}

// The six signals the fence names, handled through libSystem's sigaction (which brings its own
// return trampoline, unlike the raw call). The numbers are the same on Darwin as on Linux for
// these six.
type Signal = enum u8 { Interrupt, Terminate, Abort, SegmentFault, FloatingPoint, Illegal }

// The caller's handler as bits, which is the only way to keep one in a table: a slot is a
// `usize` and a function is not.
type SignalHandler = union { function: fn(Signal), bits: usize }
type SignalEntry = union { function: fn(i32, usize, usize), bits: usize }

// `struct sigaction` on Darwin: the handler, the mask (32 bits) and the flags.
type DarwinSigAction = struct { handler: usize, mask: u32, flags: i32 }

const SA_SIGINFO: i32 = 64i32
const SIGINT: usize = 2usize
const SIGILL: usize = 4usize
const SIGABRT: usize = 6usize
const SIGFPE: usize = 8usize
const SIGSEGV: usize = 11usize
const SYS_GETPID: usize = 20usize

var signal_slot: [6]usize

fn signal_number(which: Signal) -> usize {
    if which == .Interrupt { ret SIGINT }
    if which == .Terminate { ret SIGTERM }
    if which == .Abort { ret SIGABRT }
    if which == .SegmentFault { ret SIGSEGV }
    if which == .FloatingPoint { ret SIGFPE }
    ret SIGILL
}

fn signal_index(which: Signal) -> usize {
    if which == .Interrupt { ret 0usize }
    if which == .Terminate { ret 1usize }
    if which == .Abort { ret 2usize }
    if which == .SegmentFault { ret 3usize }
    if which == .FloatingPoint { ret 4usize }
    ret 5usize
}

fn signal_of_number(number: i32) -> (Signal, bool) {
    var which: Signal = .Interrupt
    if number == 2i32 { ret (which, true) }
    which = .Terminate
    if number == 15i32 { ret (which, true) }
    which = .Abort
    if number == 6i32 { ret (which, true) }
    which = .SegmentFault
    if number == 11i32 { ret (which, true) }
    which = .FloatingPoint
    if number == 8i32 { ret (which, true) }
    which = .Illegal
    if number == 4i32 { ret (which, true) }
    ret (which, false)
}

fn signal_dispatch(which: Signal) {
    let bits = signal_slot[signal_index(which)]
    if bits == 0usize { ret }
    var entry: SignalHandler = zero
    entry.bits = bits
    entry.function(which)
}

// What the system enters, in the C convention it calls with; SA_SIGINFO makes it three
// arguments, of which only the number is read.
@cc(c)
fn signal_entry(number: i32, information: usize, context: usize) {
    let (which, known) = signal_of_number(number)
    if !known { ret }
    signal_dispatch(which)
}

fn signal_install(which: Signal, handler: usize, flags: i32) -> err {
    var action: DarwinSigAction = zero
    action.handler = handler
    action.mask = 0u32
    action.flags = flags
    if raw_sigaction(i32(signal_number(which)), mem.address_of(&action), 0usize) != 0i32 { ret Failed }
    ret ok
}

// The slot is written before the system is told, so a signal that arrives between the two
// finds a handler rather than a zero; a failed install takes it back.
fn signal(which: Signal, handler: fn(Signal)) -> err {
    var entry: SignalHandler = zero
    entry.function = handler
    if entry.bits == 0usize { ret Failed }
    var trampoline: SignalEntry = zero
    trampoline.function = signal_entry
    let slot = signal_index(which)
    let previous = signal_slot[slot]
    signal_slot[slot] = entry.bits
    let install_error = signal_install(which, trampoline.bits, SA_SIGINFO)
    if install_error != ok {
        signal_slot[slot] = previous
        ret install_error
    }
    ret ok
}

// SIG_DFL is a handler of zero.
fn signal_default(which: Signal) -> err {
    signal_slot[signal_index(which)] = 0usize
    ret signal_install(which, 0usize, 0i32)
}

// A real signal to this process, so it takes the same path as one the system decided to send.
fn signal_raise(which: Signal) -> err {
    let identity = syscall(SYS_GETPID, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if identity < 0isize { ret from_errno(identity) }
    ret from_errno(syscall(SYS_KILL, usize(identity), signal_number(which), 0usize, 0usize, 0usize, 0usize))
}

// ---------------------------------------------------------------- sockets and pollers

type Socket = resource(socket_close) struct { raw: usize }
type SocketFamily = enum u8 { Ip4, Ip6 }
type SocketKind = enum u8 { Stream, Datagram }
type SocketShutdown = enum u8 { Read, Write, Both }
type SocketAddress = struct { family: SocketFamily, bytes: [16]u8, scope: u32, port: u16 }
type Poller = resource(poller_close) struct { state: *void }
type PollInterest = struct { readable: bool, writable: bool }
type PollEvent = struct { token: usize, readable: bool, writable: bool, closed: bool, failed: bool }

// Darwin's sockaddr_in and sockaddr_in6 lead with a length byte and then the family byte;
// the port is big-endian on the wire. One buffer holds either and the length passed beside it
// says which, written by index so the byte order of each field stays visible.
type RawAddress = struct { bytes: [28]u8 }

const SYS_SOCKET: usize = 97usize
const SYS_BIND: usize = 104usize
const SYS_LISTEN: usize = 106usize
const SYS_ACCEPT: usize = 30usize
const SYS_CONNECT: usize = 98usize
const SYS_SENDTO: usize = 133usize
const SYS_RECVFROM: usize = 29usize
const SYS_SHUTDOWN: usize = 134usize
const SYS_GETSOCKNAME: usize = 32usize
const SYS_SETSOCKOPT: usize = 105usize
const SYS_SENDFILE: usize = 337usize
const AF_INET: usize = 2usize
const AF_INET6: usize = 30usize
const SOCK_STREAM: usize = 1usize
const SOCK_DGRAM: usize = 2usize
const SOL_SOCKET: usize = 65535usize
const SO_NOSIGPIPE: usize = 4130usize
const F_GETFL: usize = 3usize
const F_SETFL: usize = 4usize
const F_SETFD: usize = 2usize
const O_NONBLOCK: usize = 4usize
const RAW_IP4_SIZE: usize = 16usize
const RAW_IP6_SIZE: usize = 28usize
const RESOLVE_ADDRESS_MAX: usize = 8usize

fn family_value(family: SocketFamily) -> usize {
    if family == .Ip6 { ret AF_INET6 }
    ret AF_INET
}

fn encode_address(address: SocketAddress) -> (RawAddress, usize) {
    var raw: RawAddress = zero
    raw.bytes[1usize] = u8(family_value(address.family))
    raw.bytes[2usize] = u8(usize(address.port) / 256usize)
    raw.bytes[3usize] = u8(usize(address.port) % 256usize)
    if address.family == .Ip6 {
        raw.bytes[0usize] = u8(RAW_IP6_SIZE)
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
    raw.bytes[0usize] = u8(RAW_IP4_SIZE)
    var at = 0usize
    while at < 4usize {
        raw.bytes[4usize + at] = address.bytes[at]
        at += 1usize
    }
    ret (raw, RAW_IP4_SIZE)
}

fn decode_address(raw: RawAddress) -> SocketAddress {
    var address: SocketAddress = zero
    address.port = u16(usize(raw.bytes[2usize]) * 256usize + usize(raw.bytes[3usize]))
    if usize(raw.bytes[1usize]) == AF_INET6 {
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

// A descriptor that is close-on-exec and never raises SIGPIPE: Darwin's socket and accept take
// no flags for either, so both are set after the fact.
fn socket_prepare(descriptor: usize) {
    let marked = syscall(SYS_FCNTL, descriptor, F_SETFD, 1usize, 0usize, 0usize, 0usize)
    var on: i32 = 1i32
    let quiet = syscall(SYS_SETSOCKOPT, descriptor, SOL_SOCKET, SO_NOSIGPIPE, mem.address_of(&on), 4usize, 0usize)
}

fn socket_open(family: SocketFamily, kind: SocketKind) -> (Socket, err) {
    var socket: Socket = zero
    var type_bits = SOCK_STREAM
    if kind == .Datagram { type_bits = SOCK_DGRAM }
    let descriptor = syscall(SYS_SOCKET, family_value(family), type_bits, 0usize, 0usize, 0usize, 0usize)
    if descriptor < 0isize { ret (socket, from_errno(descriptor)) }
    socket_prepare(usize(descriptor))
    socket.raw = usize(descriptor)
    ret (socket, ok)
}

fn socket_close(s: own Socket) -> err {
    ret from_errno(syscall(SYS_CLOSE, s.raw, 0usize, 0usize, 0usize, 0usize, 0usize))
}

fn socket_handle(s: Socket) -> Handle {
    var handle: Handle = zero
    handle.raw = s.raw
    ret handle
}

fn file_handle(f: File) -> Handle {
    var handle: Handle = zero
    handle.raw = f.raw
    ret handle
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
    // EINPROGRESS on a socket made non-blocking is the connect having started, which is what
    // `WouldBlock` means for every other call here.
    if result == -36isize { ret WouldBlock }
    ret from_errno(result)
}

fn socket_accept(s: Socket) -> (Socket, SocketAddress, err) {
    var accepted: Socket = zero
    var peer: SocketAddress = zero
    var raw: RawAddress = zero
    var length = u32(RAW_IP6_SIZE)
    let descriptor = syscall(SYS_ACCEPT, s.raw, mem.address_of(&raw), mem.address_of(&length), 0usize, 0usize, 0usize)
    if descriptor < 0isize { ret (accepted, peer, from_errno(descriptor)) }
    socket_prepare(usize(descriptor))
    accepted.raw = usize(descriptor)
    ret (accepted, decode_address(raw), ok)
}

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

fn socket_shutdown(s: Socket, how: SocketShutdown) -> err {
    var value = 2usize
    if how == .Read { value = 0usize }
    if how == .Write { value = 1usize }
    ret from_errno(syscall(SYS_SHUTDOWN, s.raw, value, 0usize, 0usize, 0usize, 0usize))
}

// sendfile(2) on Darwin takes the file first, the socket second and the count by address, where
// it answers with the bytes moved -- also when it stops short with EAGAIN on a non-blocking
// socket, which is progress and not a failure.
fn send_file(destination: Socket, source: File, offset: u64, count: usize) -> (usize, err) {
    if count == 0usize { ret (0usize, ok) }
    var moved = mem.bitcast[i64](u64(count))
    let result = syscall(SYS_SENDFILE, source.raw, destination.raw, usize(offset), mem.address_of(&moved), 0usize, 0usize)
    if result < 0isize && result != -35isize { ret (0usize, from_errno(result)) }
    ret (usize(moved), ok)
}

// ---------------------------------------------------------------- name resolution

// getaddrinfo's `struct addrinfo` on Darwin: four ints, the address length, the canonical name,
// the address and the next entry. The answer is a list libSystem owns until freeaddrinfo.
type AddrInfo = struct { flags: i32, family: i32, socktype: i32, protocol: i32, length: u32, padding: u32, canonical: usize, address: usize, next: usize }

@import("c", "getaddrinfo")
extern fn raw_getaddrinfo(node: usize, service: usize, hints: usize, result: usize) -> i32

@import("c", "freeaddrinfo")
extern fn raw_freeaddrinfo(info: usize)

// C memory cannot be read through a pointer made from an address, so what libSystem hands back
// is copied out with its own memcpy.
@import("c", "memcpy")
extern fn raw_memcpy(destination: usize, source: usize, length: usize) -> usize

// A literal address needs no lookup and a name goes to the system's resolver, which is what
// getaddrinfo is; at most RESOLVE_ADDRESS_MAX answers are kept, in the order given.
fn socket_resolve(a: *mem.Arena, host: str, port: u16, family: SocketFamily) -> ([]SocketAddress, err) {
    var nothing: []SocketAddress = zero
    if host.len == 0usize { ret (nothing, NotFound) }
    let (results, results_error) = mem.alloc[SocketAddress](a, RESOLVE_ADDRESS_MAX)
    if results_error != ok { ret (nothing, OutOfMemory) }
    let (name, name_error) = c_string_bytes(a, host)
    if name_error != ok { ret (nothing, name_error) }
    var hints: AddrInfo = zero
    hints.family = i32(family_value(family))
    hints.socktype = i32(SOCK_STREAM)
    var list: usize = 0usize
    let answer = raw_getaddrinfo(mem.address_of(&name[0usize]), 0usize, mem.address_of(&hints), mem.address_of(&list))
    if answer != 0i32 || list == 0usize { ret (nothing, NotFound) }
    var count = 0usize
    var cursor = list
    while cursor != 0usize && count < RESOLVE_ADDRESS_MAX {
        var entry: AddrInfo = zero
        let copied = raw_memcpy(mem.address_of(&entry), cursor, 48usize)
        if entry.address != 0usize && (entry.length == u32(RAW_IP4_SIZE) || entry.length == u32(RAW_IP6_SIZE)) {
            var source: RawAddress = zero
            let copied_address = raw_memcpy(mem.address_of(&source), entry.address, usize(entry.length))
            var found = decode_address(source)
            found.port = port
            results[count] = found
            count += 1usize
        }
        cursor = entry.next
    }
    raw_freeaddrinfo(list)
    if count == 0usize { ret (nothing, NotFound) }
    ret (results[0usize..count], ok)
}

// ---------------------------------------------------------------- the poller (kqueue)

const EVFILT_READ: i16 = -1i16
const EVFILT_WRITE: i16 = -2i16
const EVFILT_USER: i16 = -10i16
const EV_ADD: u16 = 1u16
const EV_DELETE: u16 = 2u16
const EV_CLEAR: u16 = 32u16
const EV_ERROR: u16 = 16384u16
const EV_EOF: u16 = 32768u16
const NOTE_TRIGGER: u32 = 16777216u32
const WAKE_IDENT: u64 = 1u64
const POLL_BATCH: usize = 64usize

type PollerState = struct { queue: usize }

// One change to the queue; an error from a delete (the filter was never added) is the caller's
// to ignore, so the result is returned as it came.
fn poller_change(queue: usize, ident: u64, filter: i16, flags: u16, fflags: u32, token: usize) -> isize {
    var change: Kevent = zero
    change.ident = ident
    change.filter = filter
    change.flags = flags
    change.fflags = fflags
    change.udata = u64(token)
    ret syscall(SYS_KEVENT, queue, mem.address_of(&change), 1usize, 0usize, 0usize, 0usize)
}

fn poller_open(a: *mem.Arena) -> (Poller, err) {
    var poller: Poller = zero
    let queue = syscall(SYS_KQUEUE, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if queue < 0isize { ret (poller, from_errno(queue)) }
    let (holder, holder_error) = mem.alloc[PollerState](a, 1usize)
    if holder_error != ok {
        let closed = syscall(SYS_CLOSE, usize(queue), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (poller, OutOfMemory)
    }
    holder[0usize].queue = usize(queue)
    // The wake is a user event, cleared as it is delivered.
    let added = poller_change(usize(queue), WAKE_IDENT, EVFILT_USER, EV_ADD | EV_CLEAR, 0u32, 0usize)
    if added < 0isize {
        let closed = syscall(SYS_CLOSE, usize(queue), 0usize, 0usize, 0usize, 0usize, 0usize)
        ret (poller, from_errno(added))
    }
    poller.state = mem.cast[*void](&holder[0usize])
    ret (poller, ok)
}

fn poller_register(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    let state = mem.cast[*PollerState](p.state)
    // Level-triggered, as epoll is without EPOLLET: no EV_CLEAR.
    if interest.readable {
        let added = poller_change(state.queue, u64(handle.raw), EVFILT_READ, EV_ADD, 0u32, token)
        if added < 0isize { ret from_errno(added) }
    }
    if interest.writable {
        let added = poller_change(state.queue, u64(handle.raw), EVFILT_WRITE, EV_ADD, 0u32, token)
        if added < 0isize { ret from_errno(added) }
    }
    ret ok
}

fn poller_unregister(p: Poller, handle: Handle) -> err {
    let state = mem.cast[*PollerState](p.state)
    // Either filter may never have been added, so ENOENT from one is not a failure; both gone
    // is what the caller asked for.
    let read_removed = poller_change(state.queue, u64(handle.raw), EVFILT_READ, EV_DELETE, 0u32, 0usize)
    let write_removed = poller_change(state.queue, u64(handle.raw), EVFILT_WRITE, EV_DELETE, 0u32, 0usize)
    if read_removed < 0isize && write_removed < 0isize { ret from_errno(read_removed) }
    ret ok
}

fn poller_modify(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    let ignored = poller_unregister(p, handle)
    ret poller_register(p, handle, token, interest)
}

fn poller_wake(p: Poller) -> err {
    let state = mem.cast[*PollerState](p.state)
    let triggered = poller_change(state.queue, WAKE_IDENT, EVFILT_USER, 0u16, NOTE_TRIGGER, 0usize)
    if triggered < 0isize { ret from_errno(triggered) }
    ret ok
}

// A negative timeout waits for ever; a positive one shorter than a nanosecond tick is still
// a wait. One descriptor ready for both reading and writing arrives as two kernel events and
// is reported as one.
fn poller_wait(p: Poller, events: []PollEvent, timeout_ns: i64) -> (usize, err) {
    let state = mem.cast[*PollerState](p.state)
    if events.len == 0usize { ret (0usize, ok) }
    var capacity = events.len
    if capacity > POLL_BATCH { capacity = POLL_BATCH }
    var raw: [64]Kevent = zero
    var limit: [2]i64 = zero
    var limit_address = 0usize
    if timeout_ns >= 0i64 {
        limit[0usize] = timeout_ns / 1000000000i64
        limit[1usize] = timeout_ns % 1000000000i64
        limit_address = mem.address_of(&limit[0usize])
    }
    let ready = syscall(SYS_KEVENT, state.queue, 0usize, 0usize, mem.address_of(&raw[0usize]), capacity, limit_address)
    if ready < 0isize {
        if ready == -4isize { ret (0usize, ok) }
        ret (0usize, from_errno(ready))
    }
    var produced = 0usize
    var at = 0usize
    while at < usize(ready) {
        if raw[at].filter == EVFILT_USER {
            at += 1usize
            continue
        }
        let token = usize(raw[at].udata)
        var slot = produced
        if produced != 0usize && events[produced - 1usize].token == token { slot = produced - 1usize } else {
            events[slot].token = token
            events[slot].readable = false
            events[slot].writable = false
            events[slot].closed = false
            events[slot].failed = false
            produced += 1usize
        }
        if raw[at].filter == EVFILT_READ { events[slot].readable = true }
        if raw[at].filter == EVFILT_WRITE { events[slot].writable = true }
        if raw[at].flags & EV_EOF != 0u16 { events[slot].closed = true }
        if raw[at].flags & EV_ERROR != 0u16 { events[slot].failed = true }
        at += 1usize
    }
    ret (produced, ok)
}

fn poller_close(p: own Poller) -> err {
    let state = mem.cast[*PollerState](p.state)
    ret from_errno(syscall(SYS_CLOSE, state.queue, 0usize, 0usize, 0usize, 0usize, 0usize))
}
