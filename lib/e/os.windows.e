// `e.os` on Windows. D32 makes `e.os` the sole OS surface of `lib/e` and says it is
// written per target: here over `kernel32`, reached by `extern fn` with `@import`.
// `project.select_source` picks this file for a Windows target, `os.linux.e` for a
// Linux one, and `lib/e/os.e` for anything else -- which is also the file the C
// bootstrap reads, since it knows nothing about variants.
//
// One module is one file, so the type block below is a copy of the one in those two
// files rather than something shared: the language has no way to say otherwise. The
// errors are not declared here at all -- `NotFound` and the rest are seeded by the
// compiler into this module, and declaring them again would be a second `NotFound`.
//
// The functions the compiler supplies as intrinsics -- open, read, write, close, seek,
// readdir, spawn, wait, the threads, the wait/wake pair, the clock, args, exit --
// appear in no `.e` file and are not written here either.

use e.mem

// The separator this target's paths are written with. `e.path` is pure -- it applies
// whatever `Style` it is handed and asks the host nothing -- and no comptime query
// names the target, so a portable module has no other way to learn which convention it
// is running under. It is here because this file is the one that is chosen per target.
const NATIVE_SEPARATOR: u8 = 92u8

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
type FileInfo = struct { kind: EntryKind, size: u64 }

// `WIN32_FILE_ATTRIBUTE_DATA`. Every `FILETIME` is two `DWORD`s in the header, so the
// whole struct is four-byte aligned and there is no padding anywhere in it -- writing
// the times as `u64` here would insert some and move `size_high` off its offset.
type FileAttributeData = struct {
    attributes: u32,
    created_low: u32,
    created_high: u32,
    accessed_low: u32,
    accessed_high: u32,
    written_low: u32,
    written_high: u32,
    size_high: u32,
    size_low: u32,
}

// `WIN32_FIND_DATAW`, which is how a path is described without following the link at
// the end of it. Same alignment reasoning as above, and both name arrays are part of
// the size the call writes.
type FindData = struct {
    attributes: u32,
    created_low: u32,
    created_high: u32,
    accessed_low: u32,
    accessed_high: u32,
    written_low: u32,
    written_high: u32,
    size_high: u32,
    size_low: u32,
    reparse_tag: u32,
    reserved: u32,
    name: [260]u16,
    alternate_name: [14]u16,
}

@import("kernel32.dll", "MultiByteToWideChar")
extern fn raw_widen(code_page: u32, flags: u32, source: *const u8, source_len: i32, destination: *u16, destination_len: i32) -> i32

@import("kernel32.dll", "GetFileAttributesExW")
extern fn raw_attributes(name: *const u16, level: i32, info: *FileAttributeData) -> i32

@import("kernel32.dll", "FindFirstFileW")
extern fn raw_find_first(name: *const u16, data: *FindData) -> usize

@import("kernel32.dll", "FindClose")
extern fn raw_find_close(handle: usize) -> i32

@import("kernel32.dll", "CreateDirectoryW")
extern fn raw_create_directory(name: *const u16, security: usize) -> i32

@import("kernel32.dll", "DeleteFileW")
extern fn raw_delete_file(name: *const u16) -> i32

@import("kernel32.dll", "RemoveDirectoryW")
extern fn raw_remove_directory(name: *const u16) -> i32

@import("kernel32.dll", "MoveFileExW")
extern fn raw_move_file(source: *const u16, destination: *const u16, flags: u32) -> i32

@import("kernel32.dll", "GetLastError")
extern fn raw_last_error() -> u32

const CP_UTF8: u32 = 65001u32
const GET_FILE_EX_INFO_STANDARD: i32 = 0i32
const INVALID_HANDLE: usize = 18446744073709551615usize

const ATTRIBUTE_DIRECTORY: u32 = 16u32
const ATTRIBUTE_REPARSE_POINT: u32 = 1024u32

// A reparse point is not always a symlink: a mount point and an app-execution stub are
// reparse points too, and only these two tags stand for something a caller would call
// a symbolic link.
const REPARSE_TAG_SYMLINK: u32 = 2684354572u32
const REPARSE_TAG_MOUNT_POINT: u32 = 2684354563u32

// The wide, NUL-terminated copy of a path that every `W` call takes. It stays a slice
// rather than an address because there is no way back from a `usize` to a pointer
// (D96) -- and a slice is what the callers want anyway, since `&name[0]` is the
// argument.
fn widen(a: *mem.Arena, text: str) -> ([]u16, err) {
    var nothing: []u16 = zero
    // A UTF-16 encoding never needs more units than the UTF-8 encoding needs bytes --
    // a four-byte sequence becomes two units -- so one allocation of the byte length
    // plus the terminator always fits.
    let (units, allocation_error) = mem.alloc[u16](a, text.len + 1usize)
    if allocation_error != ok { ret (nothing, OutOfMemory) }
    if text.len == 0usize {
        units[0usize] = 0u16
        ret (units, ok)
    }
    let converted = raw_widen(CP_UTF8, 0u32, &text[0usize], i32(text.len), &units[0usize], i32(text.len + 1usize))
    // With an explicit source length the call does not terminate what it writes, and a
    // zero result is a source that is not UTF-8 at all.
    if converted <= 0i32 { ret (nothing, Failed) }
    units[usize(converted)] = 0u16
    ret (units, ok)
}

// Win32 reports failure through a code fetched afterwards rather than in the result,
// so every call here reads it immediately. Only the codes the fence names are
// distinguished; everything else is `Failed`.
fn from_last_error() -> err {
    let code = raw_last_error()
    // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_INVALID_NAME: a name that
    // cannot exist and a name that does not are the same answer to a caller.
    if code == 2u32 { ret NotFound }
    if code == 3u32 { ret NotFound }
    if code == 123u32 { ret NotFound }
    if code == 5u32 { ret Denied }
    // ERROR_SHARING_VIOLATION: someone else has it open, which is denial by another
    // name on a platform that locks rather than unlinks.
    if code == 32u32 { ret Denied }
    if code == 80u32 { ret Exists }
    if code == 183u32 { ret Exists }
    if code == 8u32 { ret OutOfMemory }
    if code == 14u32 { ret OutOfMemory }
    // ERROR_NOT_SAME_DEVICE: a move Windows will not do without copying.
    if code == 17u32 { ret Unsupported }
    ret Failed
}

fn size_from_parts(high: u32, low: u32) -> u64 {
    ret u64(high) * 4294967296u64 + u64(low)
}

fn kind_from_attributes(attributes: u32) -> EntryKind {
    if attributes & ATTRIBUTE_DIRECTORY != 0u32 { ret .Dir }
    ret .File
}

// `GetFileAttributesExW` describes what a path leads to. It is the following call: for
// a symbolic link it answers about the target, which is what `stat` is asked for.
fn stat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    var info: FileInfo = zero
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret (info, name_error)
    }
    var data: FileAttributeData = zero
    let result = raw_attributes(&name[0usize], GET_FILE_EX_INFO_STANDARD, &data)
    if result == 0i32 {
        let call_error = from_last_error()
        mem.reset(a, checkpoint)
        ret (info, call_error)
    }
    mem.reset(a, checkpoint)
    info.kind = kind_from_attributes(data.attributes)
    info.size = size_from_parts(data.size_high, data.size_low)
    ret (info, ok)
}

// `FindFirstFileW` describes the entry itself and never follows the link at the end of
// the path, which is the difference `lstat` exists for. It cannot name a drive root --
// there is no directory entry for `C:\` to find -- so that one case falls back to the
// following call, where a root is a directory either way.
fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    var info: FileInfo = zero
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret (info, name_error)
    }
    var data: FindData = zero
    let handle = raw_find_first(&name[0usize], &data)
    if handle == INVALID_HANDLE {
        mem.reset(a, checkpoint)
        let (followed, followed_error) = stat(a, path)
        ret (followed, followed_error)
    }
    let ignored = raw_find_close(handle)
    mem.reset(a, checkpoint)
    if data.attributes & ATTRIBUTE_REPARSE_POINT != 0u32 {
        if data.reparse_tag == REPARSE_TAG_SYMLINK || data.reparse_tag == REPARSE_TAG_MOUNT_POINT {
            info.kind = .Symlink
            info.size = size_from_parts(data.size_high, data.size_low)
            ret (info, ok)
        }
        info.kind = .Other
        info.size = size_from_parts(data.size_high, data.size_low)
        ret (info, ok)
    }
    info.kind = kind_from_attributes(data.attributes)
    info.size = size_from_parts(data.size_high, data.size_low)
    ret (info, ok)
}

fn mkdir(a: *mem.Arena, path: str) -> err {
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret name_error
    }
    let result = raw_create_directory(&name[0usize], 0usize)
    var call_error = ok
    if result == 0i32 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
}

// A symbolic link is removed as itself: `DeleteFileW` unlinks the name, not what the
// name leads to.
fn remove_file(a: *mem.Arena, path: str) -> err {
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret name_error
    }
    let result = raw_delete_file(&name[0usize])
    var call_error = ok
    if result == 0i32 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
}

fn remove_dir(a: *mem.Arena, path: str) -> err {
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret name_error
    }
    let result = raw_remove_directory(&name[0usize])
    var call_error = ok
    if result == 0i32 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
}

// `MOVEFILE_REPLACE_EXISTING` is not passed: `rename` is the primitive `e.fs.move`
// uses, and Linux's `renameat` without a flag also refuses nothing -- it replaces a
// file and refuses a non-empty directory. Windows refuses an existing destination
// outright, which is the one place the two differ and is why `e.fs.replace` needs a
// call of its own rather than this one.
fn rename(a: *mem.Arena, src: str, dst: str) -> err {
    let checkpoint = mem.mark(a)
    let (from_name, from_error) = widen(a, src)
    if from_error != ok {
        mem.reset(a, checkpoint)
        ret from_error
    }
    let (to_name, to_error) = widen(a, dst)
    if to_error != ok {
        mem.reset(a, checkpoint)
        ret to_error
    }
    let result = raw_move_file(&from_name[0usize], &to_name[0usize], 0u32)
    var call_error = ok
    if result == 0i32 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
}
