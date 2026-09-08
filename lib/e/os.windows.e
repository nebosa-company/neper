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

// `mode` is POSIX permission bits, which this host does not have: what it has is one
// read-only flag, so the bits are synthesised from it. `file_id` is the file index,
// unique within its volume. Unlike Linux, this host does record a creation time.
type FileInfo = struct { kind: EntryKind, size: u64, modified_ns: i64, accessed_ns: i64, created_ns: i64, mode: u32, file_id: u64, link_count: u64 }

// `BY_HANDLE_FILE_INFORMATION`: thirteen `DWORD`s. Every `FILETIME` is two of them in
// the header, so the whole struct is four-byte aligned with no padding anywhere --
// writing the times as `u64` here would insert some and move every later field.
type ByHandleFileInformation = struct {
    attributes: u32,
    created_low: u32,
    created_high: u32,
    accessed_low: u32,
    accessed_high: u32,
    written_low: u32,
    written_high: u32,
    volume_serial: u32,
    size_high: u32,
    size_low: u32,
    link_count: u32,
    index_high: u32,
    index_low: u32,
}

// `FILE_ATTRIBUTE_TAG_INFO`, which is the only way to learn *which* kind of reparse
// point a path is. The handle information above says that one is there and not what it
// stands for.
type FileAttributeTagInfo = struct { attributes: u32, reparse_tag: u32 }

// `FILETIME`: two `DWORD`s, low first, counting 100-nanosecond ticks from 1601.
type FileTime = struct { low: u32, high: u32 }

// `REPARSE_DATA_BUFFER` as a symbolic link uses it. `flags` exists for that tag alone --
// a junction's path begins four bytes earlier -- which is why only a symbolic link is
// read here and every other tag is `Unsupported`. The array covers
// `MAXIMUM_REPARSE_DATA_BUFFER_SIZE`, which is what the call may write.
type ReparseBuffer = struct {
    tag: u32,
    data_length: u16,
    reserved: u16,
    substitute_offset: u16,
    substitute_length: u16,
    print_offset: u16,
    print_length: u16,
    flags: u32,
    path: [8188]u16,
}

@import("kernel32.dll", "MultiByteToWideChar")
extern fn raw_widen(code_page: u32, flags: u32, source: *const u8, source_len: i32, destination: *u16, destination_len: i32) -> i32

@import("kernel32.dll", "CreateFileW")
extern fn raw_create_file(name: *const u16, access: u32, share: u32, security: usize, disposition: u32, flags: u32, template: usize) -> usize

@import("kernel32.dll", "CloseHandle")
extern fn raw_close_handle(handle: usize) -> i32

@import("kernel32.dll", "GetFileInformationByHandle")
extern fn raw_handle_information(handle: usize, info: *ByHandleFileInformation) -> i32

@import("kernel32.dll", "GetFileInformationByHandleEx")
extern fn raw_handle_information_ex(handle: usize, class: i32, info: *FileAttributeTagInfo, size: u32) -> i32

@import("kernel32.dll", "CreateDirectoryW")
extern fn raw_create_directory(name: *const u16, security: usize) -> i32

@import("kernel32.dll", "DeleteFileW")
extern fn raw_delete_file(name: *const u16) -> i32

@import("kernel32.dll", "RemoveDirectoryW")
extern fn raw_remove_directory(name: *const u16) -> i32

@import("kernel32.dll", "MoveFileExW")
extern fn raw_move_file(source: *const u16, destination: *const u16, flags: u32) -> i32

@import("kernel32.dll", "GetFileAttributesW")
extern fn raw_get_attributes(name: *const u16) -> u32

@import("kernel32.dll", "SetFileAttributesW")
extern fn raw_set_attributes(name: *const u16, attributes: u32) -> i32

// The three times are pointers, and a null one means "leave that stamp alone". They are
// declared as `usize` for exactly that reason: an address is what the call wants, zero is
// the address that means nothing, and `mem.address_of` (D96) is how a real one is
// spelled. A `*FileTime` parameter could not carry the null.
@import("kernel32.dll", "SetFileTime")
extern fn raw_set_file_time(handle: usize, creation: usize, accessed: usize, written: usize) -> i32

@import("kernel32.dll", "CreateSymbolicLinkW")
extern fn raw_create_symbolic_link(link: *const u16, points_to: *const u16, flags: u32) -> u8

// Two of the eight arguments are always null here -- there is no input buffer and no
// overlapped structure -- so they are `usize`, which is what carries an address when the
// address is allowed to be none (D96).
@import("kernel32.dll", "DeviceIoControl")
extern fn raw_device_control(handle: usize, code: u32, in_buffer: usize, in_size: u32, out_buffer: *ReparseBuffer, out_size: u32, returned: *u32, overlapped: usize) -> i32

@import("kernel32.dll", "WideCharToMultiByte")
extern fn raw_narrow(code_page: u32, flags: u32, source: *const u16, source_len: i32, destination: *u8, destination_len: i32, default_char: usize, used_default: usize) -> i32

@import("kernel32.dll", "GetCurrentDirectoryW")
extern fn raw_current_directory(capacity: u32, buffer: *u16) -> u32

@import("kernel32.dll", "SetCurrentDirectoryW")
extern fn raw_set_current_directory(name: *const u16) -> i32

@import("kernel32.dll", "GetLastError")
extern fn raw_last_error() -> u32

const CP_UTF8: u32 = 65001u32
const INVALID_HANDLE: usize = 18446744073709551615usize

// `FILE_READ_ATTRIBUTES` alone: nothing here reads the bytes of a file, and asking for
// less is what lets a path that is open elsewhere still be described. The three share
// bits are for the same reason -- a file someone else is writing is not an error here.
const FILE_READ_ATTRIBUTES: u32 = 128u32
const FILE_WRITE_ATTRIBUTES: u32 = 256u32
const FILE_SHARE_ALL: u32 = 7u32
const OPEN_EXISTING: u32 = 3u32

// A directory cannot be opened at all without `BACKUP_SEMANTICS`, and
// `OPEN_REPARSE_POINT` is the difference between `lstat` and `stat`: without it
// `CreateFileW` follows the link, which is exactly what `stat` is asked to do.
const FILE_FLAG_BACKUP_SEMANTICS: u32 = 33554432u32
const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 2097152u32

const FILE_ATTRIBUTE_TAG_CLASS: i32 = 9i32

const ATTRIBUTE_READONLY: u32 = 1u32
const ATTRIBUTE_DIRECTORY: u32 = 16u32
const ATTRIBUTE_REPARSE_POINT: u32 = 1024u32

// `SetFileAttributesW` rejects an empty attribute word, so a file left with no attribute
// at all is spelled `NORMAL` -- which is what "none of the others" means there.
const ATTRIBUTE_NORMAL: u32 = 128u32
const INVALID_FILE_ATTRIBUTES: u32 = 4294967295u32

const FSCTL_GET_REPARSE_POINT: u32 = 589992u32
const MAXIMUM_REPARSE_DATA: u32 = 16384u32

// A working directory longer than this is not one anybody arrived at.
const MAX_DIRECTORY_UNITS: usize = 32768usize

// Making a link is privileged unless the host is in developer mode, which is what the
// second flag asks for; without it an ordinary process is refused.
const SYMLINK_DIRECTORY: u32 = 1u32
const SYMLINK_ALLOW_UNPRIVILEGED: u32 = 2u32

// A reparse point is not always a link: an app-execution alias is one too, and a walk
// that called it a symlink would skip a real executable. Only these two tags stand for
// something a caller would follow.
const REPARSE_TAG_SYMLINK: u32 = 2684354572u32
const REPARSE_TAG_MOUNT_POINT: u32 = 2684354563u32

// 1601-01-01 to 1970-01-01 in 100-nanosecond ticks, which is what a `FILETIME` counts.
const FILETIME_UNIX_EPOCH: u64 = 116444736000000000u64

// Read, and write unless the read-only flag is set; a directory is also traversable.
// This is a synthesis, not a translation: Windows has no group or other, so all three
// classes get the same answer rather than a narrower one that nothing enforces.
const MODE_READ_ONLY: u32 = 292u32
const MODE_READ_WRITE: u32 = 438u32
const MODE_TRAVERSABLE: u32 = 73u32

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
    // ERROR_NOT_A_REPARSE_POINT: asking a plain file what it links to. The request cannot
    // be honoured as asked, which is the same answer Linux gives it as EINVAL.
    if code == 4390u32 { ret Unsupported }
    // ERROR_PRIVILEGE_NOT_HELD: making a symbolic link without the right to.
    if code == 1314u32 { ret Denied }
    ret Failed
}

fn pair_to_u64(high: u32, low: u32) -> u64 {
    ret u64(high) * 4294967296u64 + u64(low)
}

// A `FILETIME` of zero means the host did not record one, which the fence spells `-1`.
// So does a stamp from before the Unix epoch, which this field cannot carry.
fn time_from_filetime(high: u32, low: u32) -> i64 {
    let ticks = pair_to_u64(high, low)
    if ticks < FILETIME_UNIX_EPOCH { ret -1i64 }
    ret i64((ticks - FILETIME_UNIX_EPOCH) * 100u64)
}

fn mode_from_attributes(attributes: u32) -> u32 {
    var mode = MODE_READ_WRITE
    if attributes & ATTRIBUTE_READONLY != 0u32 { mode = MODE_READ_ONLY }
    if attributes & ATTRIBUTE_DIRECTORY != 0u32 { mode = mode | MODE_TRAVERSABLE }
    ret mode
}

fn kind_from_attributes(attributes: u32) -> EntryKind {
    if attributes & ATTRIBUTE_DIRECTORY != 0u32 { ret .Dir }
    ret .File
}

// A directory needs `BACKUP_SEMANTICS` to open at all, and nothing here reads a byte of
// the file, so one helper covers both calls -- the flag that separates them is the
// caller's.
fn open_for_info(a: *mem.Arena, path: str, extra_flags: u32) -> (usize, err) {
    let (name, name_error) = widen(a, path)
    if name_error != ok { ret (INVALID_HANDLE, name_error) }
    let handle = raw_create_file(&name[0usize], FILE_READ_ATTRIBUTES, FILE_SHARE_ALL, 0usize, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | extra_flags, 0usize)
    if handle == INVALID_HANDLE { ret (INVALID_HANDLE, from_last_error()) }
    ret (handle, ok)
}

// One call answers every field, which is what the handle is worth opening for: the
// attribute-only call has no link count and no file index at all. The attributes come
// back too, because whether a reparse point is there is not a field of `FileInfo`.
fn info_from_handle(handle: usize) -> (FileInfo, u32, err) {
    var info: FileInfo = zero
    var data: ByHandleFileInformation = zero
    if raw_handle_information(handle, &data) == 0i32 { ret (info, 0u32, from_last_error()) }
    info.kind = kind_from_attributes(data.attributes)
    info.size = pair_to_u64(data.size_high, data.size_low)
    info.modified_ns = time_from_filetime(data.written_high, data.written_low)
    info.accessed_ns = time_from_filetime(data.accessed_high, data.accessed_low)
    info.created_ns = time_from_filetime(data.created_high, data.created_low)
    info.mode = mode_from_attributes(data.attributes)
    info.file_id = pair_to_u64(data.index_high, data.index_low)
    info.link_count = u64(data.link_count)
    ret (info, data.attributes, ok)
}

fn reparse_kind(handle: usize) -> EntryKind {
    var tag: FileAttributeTagInfo = zero
    if raw_handle_information_ex(handle, FILE_ATTRIBUTE_TAG_CLASS, &tag, 8u32) == 0i32 { ret .Other }
    if tag.reparse_tag == REPARSE_TAG_SYMLINK { ret .Symlink }
    if tag.reparse_tag == REPARSE_TAG_MOUNT_POINT { ret .Symlink }
    ret .Other
}

// Without `OPEN_REPARSE_POINT`, `CreateFileW` follows the link, so what is described is
// the target -- which is what `stat` means, and why a dangling link is `NotFound` here.
fn stat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    var info: FileInfo = zero
    let checkpoint = mem.mark(a)
    let (handle, open_error) = open_for_info(a, path, 0u32)
    if open_error != ok {
        mem.reset(a, checkpoint)
        ret (info, open_error)
    }
    let (described, attributes, info_error) = info_from_handle(handle)
    let closed = raw_close_handle(handle)
    mem.reset(a, checkpoint)
    ret (described, info_error)
}

// The entry itself rather than what it leads to, which is the whole difference: a
// dangling symlink has an `lstat` and no `stat`.
fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    var info: FileInfo = zero
    let checkpoint = mem.mark(a)
    let (handle, open_error) = open_for_info(a, path, FILE_FLAG_OPEN_REPARSE_POINT)
    if open_error != ok {
        mem.reset(a, checkpoint)
        ret (info, open_error)
    }
    let (described, attributes, info_error) = info_from_handle(handle)
    var answer = described
    if info_error == ok && attributes & ATTRIBUTE_REPARSE_POINT != 0u32 {
        answer.kind = reparse_kind(handle)
    }
    let closed = raw_close_handle(handle)
    mem.reset(a, checkpoint)
    ret (answer, info_error)
}

fn to_filetime(value: i64) -> FileTime {
    var stamp: FileTime = zero
    let ticks = u64(value) / 100u64 + FILETIME_UNIX_EPOCH
    stamp.low = u32(ticks % 4294967296u64)
    stamp.high = u32(ticks / 4294967296u64)
    ret stamp
}

// This host has one writable flag where POSIX has nine bits, so what a mode says here is
// whether the owner may write and nothing else. The read and execute bits cannot be
// turned off -- there is no attribute for either -- so `stat` reads them back as set
// whatever was asked for, which is why the fence calls this the portable subset.
fn set_mode(a: *mem.Arena, path: str, mode: u32) -> err {
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret name_error
    }
    let current = raw_get_attributes(&name[0usize])
    if current == INVALID_FILE_ATTRIBUTES {
        let query_error = from_last_error()
        mem.reset(a, checkpoint)
        ret query_error
    }
    var wanted = current | ATTRIBUTE_READONLY
    if mode & 128u32 != 0u32 {
        wanted = current
        if current & ATTRIBUTE_READONLY != 0u32 { wanted = current - ATTRIBUTE_READONLY }
    }
    if wanted == 0u32 { wanted = ATTRIBUTE_NORMAL }
    var call_error = ok
    if raw_set_attributes(&name[0usize], wanted) == 0i32 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
}

// The stamps are set through a handle, so this is the one call here that needs
// `FILE_WRITE_ATTRIBUTES` rather than the read of it -- and a directory still needs
// `BACKUP_SEMANTICS` to be opened at all.
fn set_times(a: *mem.Arena, path: str, accessed_ns: i64, modified_ns: i64) -> err {
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret name_error
    }
    let handle = raw_create_file(&name[0usize], FILE_WRITE_ATTRIBUTES, FILE_SHARE_ALL, 0usize, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0usize)
    if handle == INVALID_HANDLE {
        let open_error = from_last_error()
        mem.reset(a, checkpoint)
        ret open_error
    }
    var accessed = to_filetime(accessed_ns)
    var written = to_filetime(modified_ns)
    var accessed_address = 0usize
    var written_address = 0usize
    if accessed_ns >= 0i64 { accessed_address = mem.address_of(&accessed) }
    if modified_ns >= 0i64 { written_address = mem.address_of(&written) }
    var call_error = ok
    if raw_set_file_time(handle, 0usize, accessed_address, written_address) == 0i32 { call_error = from_last_error() }
    let closed = raw_close_handle(handle)
    mem.reset(a, checkpoint)
    ret call_error
}

// A drive letter or a leading separator: the two ways a path on this host does not depend
// on where it is read from.
fn target_absolute(text: str) -> bool {
    if text.len == 0usize { ret false }
    if text[0usize] == 47u8 || text[0usize] == 92u8 { ret true }
    if text.len >= 2usize && text[1usize] == 58u8 { ret true }
    ret false
}

// A relative target is relative to the link's own directory and not to the current one,
// so deciding whether it names a directory has to look where the link will look.
fn target_as_link_sees_it(a: *mem.Arena, target_path: str, link: str) -> str {
    if target_absolute(target_path) { ret target_path }
    var cut = 0usize
    var at = 0usize
    while at < link.len {
        if link[at] == 47u8 || link[at] == 92u8 { cut = at + 1usize }
        at += 1usize
    }
    if cut == 0usize { ret target_path }
    let (bytes, allocation_error) = mem.alloc[u8](a, cut + target_path.len)
    if allocation_error != ok { ret target_path }
    var written = 0usize
    while written < cut {
        bytes[written] = link[written]
        written += 1usize
    }
    var read_at = 0usize
    while read_at < target_path.len {
        bytes[cut + read_at] = target_path[read_at]
        read_at += 1usize
    }
    ret bytes[0usize..cut + target_path.len]
}

// This host records at creation whether a link names a directory, which POSIX does not,
// so the target is looked at first; one that is not there yet is taken to be a file.
fn symlink(a: *mem.Arena, target_path: str, link: str) -> err {
    let checkpoint = mem.mark(a)
    let (target_name, target_error) = widen(a, target_path)
    if target_error != ok {
        mem.reset(a, checkpoint)
        ret target_error
    }
    let (link_name, link_error) = widen(a, link)
    if link_error != ok {
        mem.reset(a, checkpoint)
        ret link_error
    }
    var flags = SYMLINK_ALLOW_UNPRIVILEGED
    let seen = target_as_link_sees_it(a, target_path, link)
    let (described, described_error) = stat(a, seen)
    if described_error == ok && described.kind == .Dir { flags = flags | SYMLINK_DIRECTORY }
    var call_error = ok
    if raw_create_symbolic_link(&link_name[0usize], &target_name[0usize], flags) == 0u8 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
}

// The link is opened as itself and asked what it stands for. The print name is what was
// written; the substitute name is the same target with the object manager's device prefix
// in front of it, which is why it is only the fallback and why that prefix is stripped
// when it is used.
fn read_link(a: *mem.Arena, path: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret ("", name_error)
    }
    let (holder, holder_error) = mem.alloc[ReparseBuffer](a, 1usize)
    if holder_error != ok {
        mem.reset(a, checkpoint)
        ret ("", OutOfMemory)
    }
    let handle = raw_create_file(&name[0usize], FILE_READ_ATTRIBUTES, FILE_SHARE_ALL, 0usize, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, 0usize)
    if handle == INVALID_HANDLE {
        let open_error = from_last_error()
        mem.reset(a, checkpoint)
        ret ("", open_error)
    }
    var returned = 0u32
    let controlled = raw_device_control(handle, FSCTL_GET_REPARSE_POINT, 0usize, 0u32, &holder[0usize], MAXIMUM_REPARSE_DATA, &returned, 0usize)
    let closed = raw_close_handle(handle)
    if controlled == 0i32 {
        let control_error = from_last_error()
        mem.reset(a, checkpoint)
        ret ("", control_error)
    }
    if holder[0usize].tag != REPARSE_TAG_SYMLINK {
        mem.reset(a, checkpoint)
        ret ("", Unsupported)
    }
    var offset = usize(holder[0usize].print_offset) / 2usize
    var units = usize(holder[0usize].print_length) / 2usize
    if units == 0usize {
        offset = usize(holder[0usize].substitute_offset) / 2usize
        units = usize(holder[0usize].substitute_length) / 2usize
        if units >= 4usize {
            if holder[0usize].path[offset] == 92u16 && holder[0usize].path[offset + 1usize] == 63u16 {
                if holder[0usize].path[offset + 2usize] == 63u16 && holder[0usize].path[offset + 3usize] == 92u16 {
                    offset += 4usize
                    units = units - 4usize
                }
            }
        }
    }
    if units == 0usize {
        mem.reset(a, checkpoint)
        ret ("", Failed)
    }
    // A UTF-16 unit never becomes more than three UTF-8 bytes -- a surrogate pair is two
    // units and four bytes -- so three per unit always fits.
    let (bytes, bytes_error) = mem.alloc[u8](a, units * 3usize)
    if bytes_error != ok {
        mem.reset(a, checkpoint)
        ret ("", OutOfMemory)
    }
    let converted = raw_narrow(CP_UTF8, 0u32, &holder[0usize].path[offset], i32(units), &bytes[0usize], i32(units * 3usize), 0usize, 0usize)
    if converted <= 0i32 {
        mem.reset(a, checkpoint)
        ret ("", Failed)
    }
    ret (bytes[0usize..usize(converted)], ok)
}

// `GetCurrentDirectoryW` answers two different questions with one number: how much it
// wrote when the buffer was big enough, and how much it needs -- terminator included --
// when it was not. Comparing against the capacity is what tells the two apart.
fn current_dir(a: *mem.Arena) -> (str, err) {
    let checkpoint = mem.mark(a)
    var capacity = 260usize
    while capacity <= MAX_DIRECTORY_UNITS {
        let (units, allocation_error) = mem.alloc[u16](a, capacity + 1usize)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let written = raw_current_directory(u32(capacity + 1usize), &units[0usize])
        if written == 0u32 {
            let call_error = from_last_error()
            mem.reset(a, checkpoint)
            ret ("", call_error)
        }
        if usize(written) <= capacity {
            let count = usize(written)
            // A UTF-16 unit never becomes more than three UTF-8 bytes.
            let (bytes, bytes_error) = mem.alloc[u8](a, count * 3usize)
            if bytes_error != ok {
                mem.reset(a, checkpoint)
                ret ("", OutOfMemory)
            }
            let converted = raw_narrow(CP_UTF8, 0u32, &units[0usize], i32(count), &bytes[0usize], i32(count * 3usize), 0usize, 0usize)
            if converted <= 0i32 {
                mem.reset(a, checkpoint)
                ret ("", Failed)
            }
            ret (bytes[0usize..usize(converted)], ok)
        }
        capacity = usize(written)
    }
    mem.reset(a, checkpoint)
    ret ("", Failed)
}

fn set_current_dir(a: *mem.Arena, path: str) -> err {
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret name_error
    }
    var call_error = ok
    if raw_set_current_directory(&name[0usize]) == 0i32 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
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
