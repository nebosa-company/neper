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

type Dir = struct { raw: usize }
type ResolvePolicy = enum u8 { NoSymlinks, Beneath }

// `UNICODE_STRING`, `OBJECT_ATTRIBUTES` and `IO_STATUS_BLOCK` as the native call takes
// them: 16, 48 and 16 bytes on this architecture, with the padding written out because it
// is what makes the later fields land where the call reads them.
type UnicodeString = struct { length: u16, maximum_length: u16, padding: u32, buffer: *u16 }

type ObjectAttributes = struct {
    length: u32,
    padding: u32,
    root_directory: usize,
    object_name: *UnicodeString,
    attributes: u32,
    padding_two: u32,
    security_descriptor: usize,
    security_quality: usize,
}

type IoStatusBlock = struct { status: usize, information: usize }

type Socket = struct { raw: usize }
type SocketFamily = enum u8 { Ip4, Ip6 }
type SocketKind = enum u8 { Stream, Datagram }
type SocketShutdown = enum u8 { Read, Write, Both }
type SocketAddress = struct { family: SocketFamily, bytes: [16]u8, scope: u32, port: u16 }

// `sockaddr_in` and `sockaddr_in6` agree on their first four bytes -- the family then the
// port -- and diverge after, so one buffer holds either and the length passed alongside
// says which. It is written by index rather than as typed fields because the port and the
// address are big-endian on the wire whatever the host is, while the family is in the
// host's own order: one struct holding both orders would hide the distinction that matters.
type RawAddress = struct { bytes: [28]u8 }

// `WSADATA`, which is read but never inspected here: the call insists on somewhere to put
// it.
type WsaData = struct { bytes: [408]u8 }

// `FILE_DISPOSITION_INFO`: one byte saying the file goes when the last handle to it closes.
type FileDispositionInfo = struct { delete_file: u8 }

// `FILE_RENAME_INFO`. The name begins at offset twenty, after a four-byte union, the
// padding that eight-byte-aligns the handle, and the length -- so the padding is written
// out here for the same reason it is in the structures above.
type FileRenameInfo = struct {
    replace: u32,
    padding: u32,
    root_directory: usize,
    name_length: u32,
    name: [520]u16,
}

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

// A null module handle asks for the running image rather than for a library, which is
// why the first argument is a `usize` (D96) and always zero here.
@import("kernel32.dll", "GetModuleFileNameW")
extern fn raw_module_file_name(module: usize, buffer: *u16, capacity: u32) -> u32

@import("kernel32.dll", "GetEnvironmentVariableW")
extern fn raw_environment_variable(name: *const u16, buffer: *u16, capacity: u32) -> u32

@import("kernel32.dll", "GetFinalPathNameByHandleW")
extern fn raw_final_path(handle: usize, buffer: *u16, capacity: u32, flags: u32) -> u32

// The one call here that is not `kernel32`. A null algorithm handle with the
// system-preferred flag is the form that needs no provider to be opened first.
@import("bcrypt.dll", "BCryptGenRandom")
extern fn raw_random(algorithm: usize, buffer: *u8, size: u32, flags: u32) -> i32

// The one call in this file from `ntdll`, and the only way this host opens a path
// relative to a directory handle at all: `kernel32` has nothing that takes a directory to
// resolve against, so every "open this name under that directory" it offers is really a
// string join, which is what the fence refuses to call safe.
@import("ntdll.dll", "NtCreateFile")
extern fn raw_nt_create_file(handle: *usize, access: u32, attributes: *ObjectAttributes, status_block: *IoStatusBlock, allocation: usize, file_attributes: u32, share: u32, disposition: u32, options: u32, ea_buffer: usize, ea_length: u32) -> u32

// The native setter rather than `SetFileInformationByHandle`, because the Win32 wrapper
// rejects the form of `FILE_RENAME_INFORMATION` that names a root directory -- and a
// rename that has to spell its destination as a full path is the string join this whole
// family exists to avoid. Measured: the wrapper answers a rename against a root handle
// with an unmapped error while accepting the same structure's disposition sibling.
//
// The information structure differs per class, so it is passed as an address rather than
// as a typed pointer, which is what `mem.address_of` (D96) is for.
@import("ntdll.dll", "NtSetInformationFile")
extern fn raw_nt_set_information(handle: usize, status_block: *IoStatusBlock, info: usize, size: u32, class: i32) -> u32

@import("kernel32.dll", "FlushFileBuffers")
extern fn raw_flush_file(handle: usize) -> i32

@import("ws2_32.dll", "WSAStartup")
extern fn raw_wsa_startup(version: u16, data: *WsaData) -> i32

@import("ws2_32.dll", "socket")
extern fn raw_socket_open(family: i32, kind: i32, protocol: i32) -> usize

@import("ws2_32.dll", "closesocket")
extern fn raw_socket_close(s: usize) -> i32

@import("ws2_32.dll", "bind")
extern fn raw_socket_bind(s: usize, address: *RawAddress, length: i32) -> i32

@import("ws2_32.dll", "listen")
extern fn raw_socket_listen(s: usize, backlog: i32) -> i32

@import("ws2_32.dll", "accept")
extern fn raw_socket_accept(s: usize, address: *RawAddress, length: *i32) -> usize

@import("ws2_32.dll", "connect")
extern fn raw_socket_connect(s: usize, address: *RawAddress, length: i32) -> i32

@import("ws2_32.dll", "send")
extern fn raw_socket_send(s: usize, buffer: *const u8, length: i32, flags: i32) -> i32

@import("ws2_32.dll", "recv")
extern fn raw_socket_receive(s: usize, buffer: *u8, length: i32, flags: i32) -> i32

@import("ws2_32.dll", "sendto")
extern fn raw_socket_send_to(s: usize, buffer: *const u8, length: i32, flags: i32, address: *RawAddress, address_length: i32) -> i32

@import("ws2_32.dll", "recvfrom")
extern fn raw_socket_receive_from(s: usize, buffer: *u8, length: i32, flags: i32, address: *RawAddress, address_length: *i32) -> i32

@import("ws2_32.dll", "shutdown")
extern fn raw_socket_shutdown(s: usize, how: i32) -> i32

// `long cmd` in the header, so the flag's bit pattern is what matters rather than its sign.
@import("ws2_32.dll", "ioctlsocket")
extern fn raw_socket_control(s: usize, command: u32, argument: *u32) -> i32

// Sockets keep their own error channel, separate from `GetLastError`.
@import("ws2_32.dll", "WSAGetLastError")
extern fn raw_socket_error() -> i32

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

// VOLUME_NAME_DOS: a drive letter rather than a volume GUID.
const FINAL_PATH_DOS: u32 = 0u32

const BCRYPT_SYSTEM_PREFERRED: u32 = 2u32

// GENERIC_READ | GENERIC_WRITE, and CREATE_NEW, which fails rather than opening a file
// that is already there.
const GENERIC_READ_WRITE: u32 = 3221225472u32
const CREATE_NEW: u32 = 1u32

// Without REPLACE_EXISTING the move refuses a destination that is there, and without
// COPY_ALLOWED -- which is never passed -- it refuses to cross a volume rather than
// copying. WRITE_THROUGH is what makes it wait for the disk.
const MOVEFILE_REPLACE_EXISTING: u32 = 1u32
const MOVEFILE_WRITE_THROUGH: u32 = 8u32

// A directory handle to resolve against needs the right to list and to traverse; nothing
// here reads the directory's bytes.
const DIRECTORY_ACCESS: u32 = 1048737u32

const SYNCHRONIZE: u32 = 1048576u32
const GENERIC_READ: u32 = 2147483648u32
const GENERIC_WRITE: u32 = 1073741824u32

// `OBJ_CASE_INSENSITIVE`, and the flag that makes the object manager fail rather than
// follow a reparse point anywhere along the path -- which is what `NoSymlinks` is.
const OBJ_CASE_INSENSITIVE: u32 = 64u32
const OBJ_DONT_REPARSE: u32 = 4096u32

const FILE_OPEN: u32 = 1u32
const FILE_OPEN_IF: u32 = 3u32
const FILE_OVERWRITE: u32 = 4u32
const FILE_OVERWRITE_IF: u32 = 5u32

// Synchronous, so the handle behaves like one from `CreateFileW`, and never a directory:
// `open_at` opens files.
const FILE_SYNCHRONOUS_IO_NONALERT: u32 = 32u32
const FILE_NON_DIRECTORY_FILE: u32 = 64u32

const FILE_DIRECTORY_FILE: u32 = 1u32

// The final component is opened as itself, so removing a symbolic link removes the link.
const FILE_OPEN_REPARSE_POINT: u32 = 2097152u32

const DELETE_ACCESS: u32 = 65536u32

// `FlushFileBuffers` refuses a handle that cannot write, so a durable rename has to ask
// for this as well -- on a directory it is the right to add an entry, which is granted the
// same way.
const FILE_WRITE_DATA: u32 = 2u32

const AF_INET: usize = 2usize

// Not the same number as on Linux, which is the one place these two files disagree about
// the wire rather than about the call.
const AF_INET6: usize = 23usize

const SOCK_STREAM: i32 = 1i32
const SOCK_DGRAM: i32 = 2i32

// MAKEWORD(2, 2).
const WSA_VERSION: u16 = 514u16

// FIONBIO.
const FIONBIO: u32 = 2147772030u32

const RAW_IP4_SIZE: usize = 16usize
const RAW_IP6_SIZE: usize = 28usize

// `FILE_INFORMATION_CLASS`, which numbers its members differently from the Win32
// `FILE_INFO_BY_HANDLE_CLASS` the wrapper takes.
const FILE_RENAME_CLASS: i32 = 10i32
const FILE_DISPOSITION_CLASS: i32 = 13i32

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

// A directory-relative path is a name under that directory and nothing else. An absolute
// one would ignore the directory it was given, `..` would leave it, and an embedded NUL
// would make the call see a shorter path than the caller wrote -- the classic way a check
// and the thing checked come apart. Both separators count here, because both are one on
// this host.
fn relative_path_ok(path: str) -> bool {
    if path.len == 0usize { ret false }
    if path[0usize] == 47u8 || path[0usize] == 92u8 { ret false }
    if path.len >= 2usize && path[1usize] == 58u8 { ret false }
    var start = 0usize
    var at = 0usize
    while at < path.len {
        if path[at] == 0u8 { ret false }
        if path[at] == 47u8 || path[at] == 92u8 {
            if at == start + 2usize && path[start] == 46u8 && path[start + 1usize] == 46u8 { ret false }
            start = at + 1usize
        }
        at += 1usize
    }
    if at == start + 2usize && path[start] == 46u8 && path[start + 1usize] == 46u8 { ret false }
    ret true
}

// An `NTSTATUS` rather than a `GetLastError` code: the native call reports in its result
// and sets nothing afterwards, so the two error vocabularies do not meet.
fn from_nt_status(status: u32) -> err {
    if status == 0u32 { ret ok }
    if status == 3221225524u32 { ret NotFound }
    if status == 3221225530u32 { ret NotFound }
    if status == 3221225506u32 { ret Denied }
    if status == 3221225539u32 { ret Denied }
    if status == 3221225525u32 { ret Exists }
    // STATUS_REPARSE_POINT_ENCOUNTERED: a link refused under `NoSymlinks`.
    if status == 3221226763u32 { ret Denied }
    // STATUS_OBJECT_NAME_EXISTS is a warning rather than a failure, and the collision
    // above is the error form; both mean the name was taken.
    if status == 1073741824u32 { ret Exists }
    if status == 3221225731u32 { ret Failed }
    if status == 3221225658u32 { ret Failed }
    ret Failed
}

// The native call takes one separator, and a caller writing a relative path may well have
// used the other. The conversion happens on the wide copy, after `widen`, so the byte
// length the caller wrote is never what is scanned.
fn widen_relative(a: *mem.Arena, path: str) -> ([]u16, usize, err) {
    var nothing: []u16 = zero
    let (units, widen_error) = widen(a, path)
    if widen_error != ok { ret (nothing, 0usize, widen_error) }
    var count = 0usize
    while count < units.len {
        if units[count] == 0u16 { break }
        if units[count] == 47u16 { units[count] = 92u16 }
        count += 1usize
    }
    ret (units, count, ok)
}

fn dir_open(a: *mem.Arena, path: str) -> (Dir, err) {
    var dir: Dir = zero
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret (dir, name_error)
    }
    let handle = raw_create_file(&name[0usize], DIRECTORY_ACCESS, FILE_SHARE_ALL, 0usize, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0usize)
    if handle == INVALID_HANDLE {
        let open_error = from_last_error()
        mem.reset(a, checkpoint)
        ret (dir, open_error)
    }
    mem.reset(a, checkpoint)
    dir.raw = handle
    ret (dir, ok)
}

fn dir_close(dir: Dir) -> err {
    if raw_close_handle(dir.raw) == 0i32 { ret from_last_error() }
    ret ok
}

fn disposition_for(flags: OpenFlags) -> u32 {
    if flags.create && flags.truncate { ret FILE_OVERWRITE_IF }
    if flags.create { ret FILE_OPEN_IF }
    if flags.truncate { ret FILE_OVERWRITE }
    ret FILE_OPEN
}

// `Beneath` has no equivalent here. The object manager will refuse a reparse point, which
// is `NoSymlinks`, but nothing in it confines a walk to a subtree -- and the fence is
// explicit that a lexical check or a canonicalise-then-open is not a substitute, so this
// says `Unsupported` rather than claiming a guarantee it cannot keep.
fn open_at(a: *mem.Arena, dir: Dir, relative_path: str, flags: OpenFlags, policy: ResolvePolicy) -> (File, err) {
    var file: File = zero
    if policy == .Beneath { ret (file, Unsupported) }
    if !relative_path_ok(relative_path) { ret (file, Denied) }
    var access = SYNCHRONIZE
    if flags.read { access = access | GENERIC_READ }
    if flags.write { access = access | GENERIC_WRITE }
    let (handle, open_error) = open_relative(a, dir, relative_path, access, disposition_for(flags), OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE, FILE_SYNCHRONOUS_IO_NONALERT | FILE_NON_DIRECTORY_FILE)
    if open_error != ok { ret (file, open_error) }
    file.raw = handle
    ret (file, ok)
}

// One relative open against a directory handle. `attributes` and `options` are the
// caller's, because what varies between these calls is exactly whether a reparse point is
// refused and whether a directory is wanted.
fn open_relative(a: *mem.Arena, dir: Dir, relative_path: str, access: u32, disposition: u32, attribute_flags: u32, options: u32) -> (usize, err) {
    let checkpoint = mem.mark(a)
    let (name, count, name_error) = widen_relative(a, relative_path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret (INVALID_HANDLE, name_error)
    }
    var text: UnicodeString = zero
    text.length = u16(count * 2usize)
    text.maximum_length = u16(count * 2usize)
    text.buffer = &name[0usize]
    var attributes: ObjectAttributes = zero
    attributes.length = 48u32
    attributes.root_directory = dir.raw
    attributes.object_name = &text
    attributes.attributes = attribute_flags
    var status_block: IoStatusBlock = zero
    var handle = 0usize
    let status = raw_nt_create_file(&handle, access, &attributes, &status_block, 0usize, ATTRIBUTE_NORMAL, FILE_SHARE_ALL, disposition, options, 0usize, 0u32)
    mem.reset(a, checkpoint)
    if status != 0u32 { ret (INVALID_HANDLE, from_nt_status(status)) }
    ret (handle, ok)
}

// The parent of the final component, opened with reparse points refused so every step but
// the last is walked without following a link. The last component is then acted on
// relative to that -- which is how "do not follow a link on the way there, but do act on
// the link that is there" gets said, since one call cannot mean both.
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
        if relative_path[at] == 47u8 || relative_path[at] == 92u8 {
            cut = at
            found = true
        }
        at += 1usize
    }
    if !found { ret (parent, relative_path, ok) }
    let head = relative_path[0usize..cut]
    let tail = relative_path[cut + 1usize..relative_path.len]
    if tail.len == 0usize { ret (parent, "", Denied) }
    let (handle, open_error) = open_relative(a, dir, head, DIRECTORY_ACCESS, FILE_OPEN, OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE, FILE_SYNCHRONOUS_IO_NONALERT | FILE_DIRECTORY_FILE)
    if open_error != ok { ret (parent, "", open_error) }
    parent.raw = handle
    ret (parent, tail, ok)
}

fn release_parent(parent: Dir, dir: Dir) {
    if parent.raw != dir.raw {
        let closed = raw_close_handle(parent.raw)
    }
}

// The file is opened for deletion and then marked to go, which is this host's way of
// unlinking a name. `FILE_OPEN_REPARSE_POINT` without `OBJ_DONT_REPARSE` on this last step
// is what removes a symbolic link rather than its target -- the path to it was already
// walked with links refused.
fn remove_at(a: *mem.Arena, dir: Dir, relative_path: str, directory: bool) -> err {
    if !relative_path_ok(relative_path) { ret Denied }
    let (parent, name, parent_error) = open_parent(a, dir, relative_path)
    if parent_error != ok { ret parent_error }
    var options = FILE_SYNCHRONOUS_IO_NONALERT | FILE_OPEN_REPARSE_POINT | FILE_NON_DIRECTORY_FILE
    if directory { options = FILE_SYNCHRONOUS_IO_NONALERT | FILE_OPEN_REPARSE_POINT | FILE_DIRECTORY_FILE }
    let (handle, open_error) = open_relative(a, parent, name, DELETE_ACCESS | SYNCHRONIZE, FILE_OPEN, OBJ_CASE_INSENSITIVE, options)
    if open_error != ok {
        release_parent(parent, dir)
        ret open_error
    }
    var disposition: FileDispositionInfo = zero
    disposition.delete_file = 1u8
    var status_block: IoStatusBlock = zero
    var answer = from_nt_status(raw_nt_set_information(handle, &status_block, mem.address_of(&disposition), 1u32, FILE_DISPOSITION_CLASS))
    let closed = raw_close_handle(handle)
    release_parent(parent, dir)
    ret answer
}

// A rename here is a property of the open file rather than a call on two paths: the handle
// carries where it should go, and the destination directory is a handle too, so nothing in
// it is a string join.
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
    var rename_access = DELETE_ACCESS | SYNCHRONIZE
    if durable { rename_access = rename_access | FILE_WRITE_DATA }
    let (handle, open_error) = open_relative(a, src_parent, src_name, rename_access, FILE_OPEN, OBJ_CASE_INSENSITIVE, FILE_SYNCHRONOUS_IO_NONALERT | FILE_OPEN_REPARSE_POINT)
    if open_error != ok {
        release_parent(src_parent, src_dir)
        release_parent(dst_parent, dst_dir)
        ret open_error
    }
    let checkpoint = mem.mark(a)
    let (wide_name, count, wide_error) = widen_relative(a, dst_name)
    var answer = ok
    if wide_error != ok {
        answer = wide_error
    } else {
        var information: FileRenameInfo = zero
        if overwrite { information.replace = 1u32 }
        information.root_directory = dst_parent.raw
        information.name_length = u32(count * 2usize)
        var copied = 0usize
        while copied < count {
            information.name[copied] = wide_name[copied]
            copied += 1usize
        }
        var status_block: IoStatusBlock = zero
        answer = from_nt_status(raw_nt_set_information(handle, &status_block, mem.address_of(&information), 20u32 + u32(count * 2usize), FILE_RENAME_CLASS))
        // The handle followed the file through the rename, so this is the moved file.
        if answer == ok && durable {
            if raw_flush_file(handle) == 0i32 { answer = from_last_error() }
        }
    }
    mem.reset(a, checkpoint)
    let closed = raw_close_handle(handle)
    release_parent(src_parent, src_dir)
    release_parent(dst_parent, dst_dir)
    ret answer
}

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

fn from_socket_error() -> err {
    let code = raw_socket_error()
    if code == 10004i32 { ret Interrupted }
    if code == 10013i32 { ret Denied }
    if code == 10035i32 { ret WouldBlock }
    if code == 10036i32 { ret WouldBlock }
    if code == 10048i32 { ret Exists }
    if code == 10049i32 { ret NotFound }
    if code == 10060i32 { ret Timeout }
    ret Failed
}

// Winsock insists on being started before anything else touches it, and there is nowhere to
// remember that it has been: D109 is why this file keeps no ambient state to hold a flag.
// The call is reference counted, so asking again is cheap and asking once per socket is
// correct.
fn socket_open(family: SocketFamily, kind: SocketKind) -> (Socket, err) {
    var socket: Socket = zero
    var data: WsaData = zero
    if raw_wsa_startup(WSA_VERSION, &data) != 0i32 { ret (socket, Failed) }
    var type_bits = SOCK_STREAM
    if kind == .Datagram { type_bits = SOCK_DGRAM }
    let handle = raw_socket_open(i32(family_value(family)), type_bits, 0i32)
    if handle == INVALID_HANDLE { ret (socket, from_socket_error()) }
    socket.raw = handle
    ret (socket, ok)
}

fn socket_close(s: Socket) -> err {
    if raw_socket_close(s.raw) != 0i32 { ret from_socket_error() }
    ret ok
}

fn socket_set_nonblocking(s: Socket, enabled: bool) -> err {
    var wanted = 0u32
    if enabled { wanted = 1u32 }
    if raw_socket_control(s.raw, FIONBIO, &wanted) != 0i32 { ret from_socket_error() }
    ret ok
}

fn socket_bind(s: Socket, address: SocketAddress) -> err {
    var (raw, length) = encode_address(address)
    if raw_socket_bind(s.raw, &raw, i32(length)) != 0i32 { ret from_socket_error() }
    ret ok
}

fn socket_listen(s: Socket, backlog: u32) -> err {
    if raw_socket_listen(s.raw, i32(backlog)) != 0i32 { ret from_socket_error() }
    ret ok
}

fn socket_connect(s: Socket, address: SocketAddress) -> err {
    var (raw, length) = encode_address(address)
    if raw_socket_connect(s.raw, &raw, i32(length)) != 0i32 { ret from_socket_error() }
    ret ok
}

fn socket_accept(s: Socket) -> (Socket, SocketAddress, err) {
    var accepted: Socket = zero
    var peer: SocketAddress = zero
    var raw: RawAddress = zero
    var length = i32(RAW_IP6_SIZE)
    let handle = raw_socket_accept(s.raw, &raw, &length)
    if handle == INVALID_HANDLE { ret (accepted, peer, from_socket_error()) }
    accepted.raw = handle
    ret (accepted, decode_address(raw), ok)
}

fn socket_send(s: Socket, src: []const u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let sent = raw_socket_send(s.raw, &src[0usize], i32(src.len), 0i32)
    if sent < 0i32 { ret (0usize, from_socket_error()) }
    ret (usize(sent), ok)
}

fn socket_receive(s: Socket, dst: []u8) -> (usize, err) {
    if dst.len == 0usize { ret (0usize, ok) }
    let taken = raw_socket_receive(s.raw, &dst[0usize], i32(dst.len), 0i32)
    if taken < 0i32 { ret (0usize, from_socket_error()) }
    ret (usize(taken), ok)
}

fn socket_send_to(s: Socket, dst: SocketAddress, src: []const u8) -> (usize, err) {
    var (raw, length) = encode_address(dst)
    if src.len == 0usize { ret (0usize, ok) }
    let sent = raw_socket_send_to(s.raw, &src[0usize], i32(src.len), 0i32, &raw, i32(length))
    if sent < 0i32 { ret (0usize, from_socket_error()) }
    ret (usize(sent), ok)
}

fn socket_receive_from(s: Socket, dst: []u8) -> (usize, SocketAddress, err) {
    var peer: SocketAddress = zero
    if dst.len == 0usize { ret (0usize, peer, ok) }
    var raw: RawAddress = zero
    var length = i32(RAW_IP6_SIZE)
    let taken = raw_socket_receive_from(s.raw, &dst[0usize], i32(dst.len), 0i32, &raw, &length)
    if taken < 0i32 { ret (0usize, peer, from_socket_error()) }
    ret (usize(taken), decode_address(raw), ok)
}

fn shutdown_value(how: SocketShutdown) -> i32 {
    if how == .Write { ret 1i32 }
    if how == .Both { ret 2i32 }
    ret 0i32
}

fn socket_shutdown(s: Socket, how: SocketShutdown) -> err {
    if raw_socket_shutdown(s.raw, shutdown_value(how)) != 0i32 { ret from_socket_error() }
    ret ok
}

fn socket_handle(s: Socket) -> Handle {
    var handle: Handle = zero
    handle.raw = s.raw
    ret handle
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
// An NTSTATUS, where zero is success and nothing else is. A zero-length request asks the
// provider for nothing, so it is answered here.
fn random(buffer: []u8) -> err {
    if buffer.len == 0usize { ret ok }
    if raw_random(0usize, &buffer[0usize], u32(buffer.len), BCRYPT_SYSTEM_PREFERRED) != 0i32 { ret Failed }
    ret ok
}

// The file must not be there, and finding out is the same operation as creating it. That
// is the whole point: a name checked and then opened is a name something else can take in
// between. No share bits either, so nothing else opens it while the caller holds it.
fn create_new(a: *mem.Arena, path: str) -> (File, err) {
    var file: File = zero
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret (file, name_error)
    }
    let handle = raw_create_file(&name[0usize], GENERIC_READ_WRITE, 0u32, 0usize, CREATE_NEW, ATTRIBUTE_NORMAL, 0usize)
    if handle == INVALID_HANDLE {
        let open_error = from_last_error()
        mem.reset(a, checkpoint)
        ret (file, open_error)
    }
    mem.reset(a, checkpoint)
    file.raw = handle
    ret (file, ok)
}

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

// `GetModuleFileNameW` signals a buffer that was too small by filling it exactly and
// leaving the count equal to the capacity, so a result that fills the buffer is never
// trusted to be complete. The path is the one the process was started from, links and all.
// A zero result means two different things here, and the code afterwards is what tells
// them apart: a name nothing set, or a name set to nothing. The second is not a failure,
// and reporting it as one would make an empty value indistinguishable from a missing one
// -- which is the whole reason this returns an `err` rather than an empty `str`.
fn env(a: *mem.Arena, name: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (wide_name, name_error) = widen(a, name)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret ("", name_error)
    }
    var capacity = 256usize
    while capacity <= MAX_DIRECTORY_UNITS {
        let (units, allocation_error) = mem.alloc[u16](a, capacity)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let written = raw_environment_variable(&wide_name[0usize], &units[0usize], u32(capacity))
        if written == 0u32 {
            let code = raw_last_error()
            mem.reset(a, checkpoint)
            if code == 0u32 { ret ("", ok) }
            // ERROR_ENVVAR_NOT_FOUND.
            if code == 203u32 { ret ("", NotFound) }
            ret ("", Failed)
        }
        // A count that reaches the capacity is the size needed, terminator included,
        // rather than the size written.
        if usize(written) < capacity {
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

// `GetFinalPathNameByHandleW` answers in extended-length form, which is correct and is
// not what anyone means by a path. The device prefix is dropped, and a UNC name gets its
// two leading separators back -- written over the tail of the prefix, since that is
// exactly where they belong.
fn without_device_prefix(units: []u16, count: usize) -> (usize, usize) {
    if count >= 8usize {
        if units[0usize] == 92u16 && units[1usize] == 92u16 && units[2usize] == 63u16 && units[3usize] == 92u16 {
            if units[4usize] == 85u16 && units[5usize] == 78u16 && units[6usize] == 67u16 && units[7usize] == 92u16 {
                units[6usize] = 92u16
                units[7usize] = 92u16
                ret (6usize, count - 6usize)
            }
        }
    }
    if count >= 4usize {
        if units[0usize] == 92u16 && units[1usize] == 92u16 && units[2usize] == 63u16 && units[3usize] == 92u16 {
            ret (4usize, count - 4usize)
        }
    }
    ret (0usize, count)
}

// Opening the path is what resolves it: the handle names one object, and the host is then
// asked which one. Following the links is the default, which is why this uses the same
// open `stat` does.
fn canonical(a: *mem.Arena, path: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (handle, open_error) = open_for_info(a, path, 0u32)
    if open_error != ok {
        mem.reset(a, checkpoint)
        ret ("", open_error)
    }
    var capacity = 260usize
    while capacity <= MAX_DIRECTORY_UNITS {
        let (units, allocation_error) = mem.alloc[u16](a, capacity)
        if allocation_error != ok {
            let unused_close = raw_close_handle(handle)
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let written = raw_final_path(handle, &units[0usize], u32(capacity), FINAL_PATH_DOS)
        if written == 0u32 {
            let call_error = from_last_error()
            let unused_close = raw_close_handle(handle)
            mem.reset(a, checkpoint)
            ret ("", call_error)
        }
        if usize(written) < capacity {
            let closed = raw_close_handle(handle)
            let (offset, count) = without_device_prefix(units, usize(written))
            // A UTF-16 unit never becomes more than three UTF-8 bytes.
            let (bytes, bytes_error) = mem.alloc[u8](a, count * 3usize)
            if bytes_error != ok {
                mem.reset(a, checkpoint)
                ret ("", OutOfMemory)
            }
            let converted = raw_narrow(CP_UTF8, 0u32, &units[offset], i32(count), &bytes[0usize], i32(count * 3usize), 0usize, 0usize)
            if converted <= 0i32 {
                mem.reset(a, checkpoint)
                ret ("", Failed)
            }
            ret (bytes[0usize..usize(converted)], ok)
        }
        capacity = usize(written)
    }
    let unused_close = raw_close_handle(handle)
    mem.reset(a, checkpoint)
    ret ("", Failed)
}

fn executable_path(a: *mem.Arena) -> (str, err) {
    let checkpoint = mem.mark(a)
    var capacity = 260usize
    while capacity <= MAX_DIRECTORY_UNITS {
        let (units, allocation_error) = mem.alloc[u16](a, capacity)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", OutOfMemory)
        }
        let written = raw_module_file_name(0usize, &units[0usize], u32(capacity))
        if written == 0u32 {
            let call_error = from_last_error()
            mem.reset(a, checkpoint)
            ret ("", call_error)
        }
        if usize(written) < capacity {
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
        capacity = capacity * 2usize
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
// One call answers both questions here: the flags say whether an existing destination is
// replaced and whether the move is on the disk before it returns.
fn replace(a: *mem.Arena, src: str, dst: str, overwrite: bool, durable: bool) -> err {
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
    var flags = 0u32
    if overwrite { flags = flags | MOVEFILE_REPLACE_EXISTING }
    if durable { flags = flags | MOVEFILE_WRITE_THROUGH }
    var call_error = ok
    if raw_move_file(&from_name[0usize], &to_name[0usize], flags) == 0i32 { call_error = from_last_error() }
    mem.reset(a, checkpoint)
    ret call_error
}

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
