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

fn env(a: *mem.Arena, name: str) -> (str, err) { ret ("", NotFound) }
fn executable_path(a: *mem.Arena) -> (str, err) { ret ("", Unsupported) }

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
