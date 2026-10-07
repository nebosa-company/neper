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

use e.mem

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
// The same shapes the other os variants expose, so e.fs's `os.FileInfo`/`os.Dir`/`os.ResolvePolicy`
// compile unchanged. NeperOS fills only what its server reports (kind and size).
type FileInfo = struct { kind: EntryKind, size: u64, modified_ns: i64, accessed_ns: i64, created_ns: i64, mode: u32, file_id: u64, link_count: u64 }
type Dir = resource(dir_close) struct { raw: usize }
type ResolvePolicy = enum u8 { NoSymlinks, Beneath }

// Read into `buffer`, recording a detail on failure. A wrapper over the seeded `read` primitive;
// NeperOS has no errno, so the detail carries only the operation.
fn read_detail(f: File, buffer: []u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, read_error) = read(f, buffer)
    if read_error != ok { *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "read", subject: "" } }
    ret (count, read_error)
}

// Write `buffer`, recording a detail on failure. A wrapper over `write`.
fn write_detail(f: File, buffer: []const u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, write_error) = write(f, buffer)
    if write_error != ok { *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "write", subject: "" } }
    ret (count, write_error)
}

// (D2158, C107) The file surface, written here rather than seeded as intrinsics (the other targets
// seed the primitives). stdout and stderr -- file 1 and 2 -- go to the console through the
// `console_write` primitive; a file goes to the C106 filesystem server over IPC. The server is
// path-based and whole-file, so a File is a client-side handle: open records the path, read loads
// the whole file once and serves from an offset, write buffers, and close flushes a dirty buffer.
// The program must hold the server's request endpoint in slot 1 (send) and its reply endpoint in
// slot 2 (receive), as the filesystem-server boot grants a client (C106).

// The filesystem IPC protocol, matching neperos/src/fsproto.e. One word per rendezvous: a request
// is an op word then the path as a length-prefixed byte string (and for a write the data likewise);
// a reply is a result word, then for a read a length-prefixed byte string, for an open a size word.
const FS_REQ: usize = 1usize
const FS_REP: usize = 2usize
const FS_NO_SLOT: usize = 99usize
const FS_HANDLES: usize = 8usize
const FS_BLOCK: usize = 512usize
const FS_NAME: usize = 64usize
// A File's raw is this base plus a handle index, so a file is told apart from the console file ids.
const FILE_BASE: usize = 16usize
const OP_QUIT: usize = 0usize
const OP_MKDIR: usize = 1usize
const OP_WRITE: usize = 2usize
const OP_READ: usize = 3usize
const OP_LIST: usize = 4usize
const OP_OPEN: usize = 5usize
const OP_CLOSE: usize = 6usize
const OP_REMOVE: usize = 7usize
const FS_RESULT_OK: usize = 0usize

type FsHandle = struct { used: bool, name: [64]u8, name_len: usize, offset: usize, size: usize, loaded: bool, dirty: bool, data: [512]u8 }
var fs_handles: [8]FsHandle = zero

fn fs_send_word(word: usize) {
    let status = send(FS_REQ, word, FS_NO_SLOT)
}

fn fs_send_str(s: str) {
    let header = send(FS_REQ, s.len, FS_NO_SLOT)
    var i = 0usize
    while i < s.len {
        let sent = send(FS_REQ, usize(s[i]), FS_NO_SLOT)
        i += 1usize
    }
}

fn fs_send_handle_data(slot: usize, len: usize) {
    let header = send(FS_REQ, len, FS_NO_SLOT)
    var i = 0usize
    while i < len {
        let sent = send(FS_REQ, usize(fs_handles[slot].data[i]), FS_NO_SLOT)
        i += 1usize
    }
}

fn fs_recv_word() -> usize {
    ret recv(FS_REP, FS_NO_SLOT)
}

// Receive a reply's length-prefixed byte string into handle `slot`'s buffer; the stored count (at
// most FS_BLOCK) comes back, every word consumed so the stream stays in step.
fn fs_recv_handle_data(slot: usize) -> usize {
    let len = recv(FS_REP, FS_NO_SLOT)
    var i = 0usize
    while i < len {
        let b = recv(FS_REP, FS_NO_SLOT)
        if i < FS_BLOCK { fs_handles[slot].data[i] = u8(b) }
        i += 1usize
    }
    if len < FS_BLOCK { ret len }
    ret FS_BLOCK
}

fn fs_name_str(slot: usize) -> str {
    ret fs_handles[slot].name[0usize..fs_handles[slot].name_len]
}

fn write(f: File, buf: str) -> (usize, err) {
    if f.raw < FILE_BASE {
        if f.raw <= 2usize { ret (console_write(buf), ok) }
        ret (0usize, Unsupported)
    }
    let slot = f.raw - FILE_BASE
    if slot >= FS_HANDLES || !fs_handles[slot].used { ret (0usize, Unsupported) }
    var n = 0usize
    while n < buf.len && fs_handles[slot].offset + n < FS_BLOCK {
        fs_handles[slot].data[fs_handles[slot].offset + n] = buf[n]
        n += 1usize
    }
    fs_handles[slot].offset += n
    if fs_handles[slot].offset > fs_handles[slot].size { fs_handles[slot].size = fs_handles[slot].offset }
    fs_handles[slot].dirty = true
    ret (n, ok)
}

fn read(f: File, buffer: []u8) -> (usize, err) {
    if f.raw < FILE_BASE { ret (0usize, ok) }
    let slot = f.raw - FILE_BASE
    if slot >= FS_HANDLES || !fs_handles[slot].used { ret (0usize, Unsupported) }
    if !fs_handles[slot].loaded {
        fs_send_word(OP_READ)
        fs_send_str(fs_name_str(slot))
        let result = fs_recv_word()
        let count = fs_recv_handle_data(slot)
        if result != FS_RESULT_OK { ret (0usize, NotFound) }
        fs_handles[slot].size = count
        fs_handles[slot].loaded = true
    }
    var n = 0usize
    while n < buffer.len && fs_handles[slot].offset + n < fs_handles[slot].size {
        buffer[n] = fs_handles[slot].data[fs_handles[slot].offset + n]
        n += 1usize
    }
    fs_handles[slot].offset += n
    ret (n, ok)
}

fn open(a: *mem.Arena, path: str, flags: OpenFlags) -> (File, err) {
    if path.len > FS_NAME { ret (File { raw: 0usize }, Unsupported) }
    var slot = FS_HANDLES
    var i = 0usize
    while i < FS_HANDLES {
        if !fs_handles[i].used {
            slot = i
            i = FS_HANDLES
        } else {
            i += 1usize
        }
    }
    if slot == FS_HANDLES { ret (File { raw: 0usize }, OutOfMemory) }
    fs_handles[slot].used = true
    fs_handles[slot].name_len = path.len
    var j = 0usize
    while j < path.len {
        fs_handles[slot].name[j] = path[j]
        j += 1usize
    }
    fs_handles[slot].offset = 0usize
    fs_handles[slot].size = 0usize
    fs_handles[slot].loaded = false
    fs_handles[slot].dirty = false
    // Opened to write: start from an empty, dirty buffer, so a truncating create writes even nothing.
    if flags.write {
        fs_handles[slot].loaded = true
        fs_handles[slot].dirty = true
    }
    ret (File { raw: FILE_BASE + slot }, ok)
}

fn close(f: File) -> err {
    if f.raw < FILE_BASE { ret ok }
    let slot = f.raw - FILE_BASE
    if slot >= FS_HANDLES || !fs_handles[slot].used { ret ok }
    if fs_handles[slot].dirty {
        fs_send_word(OP_WRITE)
        fs_send_str(fs_name_str(slot))
        fs_send_handle_data(slot, fs_handles[slot].size)
        let result = fs_recv_word()
    }
    fs_handles[slot].used = false
    ret ok
}

fn seek(f: File, off: i64, whence: SeekWhence) -> (u64, err) {
    if f.raw < FILE_BASE { ret (0u64, Unsupported) }
    let slot = f.raw - FILE_BASE
    if slot >= FS_HANDLES || !fs_handles[slot].used { ret (0u64, Unsupported) }
    var pos = fs_handles[slot].offset
    if whence == SeekWhence.Start {
        pos = usize(off)
    } else {
        if whence == SeekWhence.Current { pos = fs_handles[slot].offset + usize(off) } else { pos = fs_handles[slot].size + usize(off) }
    }
    fs_handles[slot].offset = pos
    ret (u64(pos), ok)
}

fn readdir(a: *mem.Arena, path: str) -> ([]DirEntry, err) {
    var empty: []DirEntry = zero
    ret (empty, Unsupported)
}

// The size and kind of `path`, over the server's open query (which reports existence and size). A
// file that is not there is NotFound; a directory the server cannot distinguish, so a present entry
// is reported as a file.
fn stat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    var info: FileInfo = zero
    fs_send_word(OP_OPEN)
    fs_send_str(path)
    let result = fs_recv_word()
    let size = fs_recv_word()
    if result != FS_RESULT_OK { ret (info, NotFound) }
    info.kind = EntryKind.File
    info.size = u64(size)
    info.created_ns = -1i64
    ret (info, ok)
}

fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    let (info, stat_error) = stat(a, path)
    ret (info, stat_error)
}

fn mkdir(a: *mem.Arena, path: str) -> err {
    fs_send_word(OP_MKDIR)
    fs_send_str(path)
    let result = fs_recv_word()
    if result != FS_RESULT_OK { ret Exists }
    ret ok
}

fn remove_file(a: *mem.Arena, path: str) -> err {
    fs_send_word(OP_REMOVE)
    fs_send_str(path)
    let result = fs_recv_word()
    if result != FS_RESULT_OK { ret NotFound }
    ret ok
}

fn remove_dir(a: *mem.Arena, path: str) -> err {
    ret remove_file(a, path)
}

// The detail-bearing forms, over the plain ones: NeperOS has no errno, so the detail carries only
// the operation on failure.
fn stat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = stat(a, path)
    if stat_error != ok { *detail = ErrorDetail { kind: ErrorKind.NotFound, native_code: 0i32, operation: "stat", subject: path } }
    ret (info, stat_error)
}

fn lstat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = stat_detail(a, path, detail)
    ret (info, stat_error)
}

fn open_detail(a: *mem.Arena, path: str, flags: OpenFlags, detail: *ErrorDetail) -> (File, err) {
    let (file, open_error) = open(a, path, flags)
    if open_error != ok {
        *detail = ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: "open", subject: path }
        ret (file, open_error)
    }
    ret (file, ok)
}

fn mkdir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let mkdir_error = mkdir(a, path)
    if mkdir_error != ok { *detail = ErrorDetail { kind: ErrorKind.Exists, native_code: 0i32, operation: "mkdir", subject: path } }
    ret mkdir_error
}

fn remove_file_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let remove_error = remove_file(a, path)
    if remove_error != ok { *detail = ErrorDetail { kind: ErrorKind.NotFound, native_code: 0i32, operation: "remove", subject: path } }
    ret remove_error
}

fn remove_dir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    ret remove_file_detail(a, path, detail)
}

fn last_error_detail(operation: str, subject: str) -> ErrorDetail {
    ret ErrorDetail { kind: ErrorKind.Other, native_code: 0i32, operation: operation, subject: subject }
}

// The rest of the path surface NeperOS does not serve yet: a single filesystem server, no symlinks,
// no working directory, no environment. e.fs compiles against these; they answer Unsupported.
fn rename(a: *mem.Arena, src: str, dst: str) -> err { ret Unsupported }
fn rename_detail(a: *mem.Arena, src: str, dst: str, detail: *ErrorDetail) -> err { ret Unsupported }
fn replace(a: *mem.Arena, src: str, dst: str, overwrite: bool, durable: bool) -> err { ret Unsupported }
fn canonical(a: *mem.Arena, path: str) -> (str, err) { ret (path, ok) }
fn canonical_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err) { ret (path, ok) }
fn read_link(a: *mem.Arena, path: str) -> (str, err) { ret ("", Unsupported) }
fn read_link_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err) { ret ("", Unsupported) }
fn symlink(a: *mem.Arena, target_path: str, link: str) -> err { ret Unsupported }
fn set_mode(a: *mem.Arena, path: str, mode: u32) -> err { ret Unsupported }
fn set_times(a: *mem.Arena, path: str, accessed_ns: i64, modified_ns: i64) -> err { ret Unsupported }
fn create_new(a: *mem.Arena, path: str) -> (File, err) {
    var flags: OpenFlags = zero
    flags.write = true
    flags.create = true
    let (file, open_error) = open(a, path, flags)
    ret (file, open_error)
}
fn current_dir(a: *mem.Arena) -> (str, err) { ret ("/", ok) }
fn set_current_dir(a: *mem.Arena, path: str) -> err { ret Unsupported }
fn env(a: *mem.Arena, name: str) -> (str, err) { ret ("", NotFound) }
fn executable_path(a: *mem.Arena) -> (str, err) { ret ("/init", ok) }
fn random(buffer: []u8) -> err { ret Unsupported }

// Directory handles and the *_at family: a single flat server, so these are not served. e.fs
// compiles against them; a program that needs them gets Unsupported rather than wrong behaviour.
fn dir_open(a: *mem.Arena, path: str) -> (Dir, err) { ret (Dir { raw: 0usize }, Unsupported) }
fn dir_close(dir: own Dir) -> err { ret ok }

// (D2165, C110) Dynamic linking and the thread id: NeperOS has no shared libraries, so dlopen is
// Unsupported (the modules that reach for it -- e.gpu's Vulkan backend -- only use the CPU backend
// here, where that path is pruned). current_thread_id is a single value for a NeperOS program.
type Lib = resource(dlclose) struct { raw: usize }
fn dlopen(a: *mem.Arena, name: str) -> (Lib, err) { ret (Lib { raw: 0usize }, Unsupported) }
fn dlclose(l: own Lib) -> err { ret ok }
// The symbol lookup `os.dlsym[fn ...]` is intercepted onto: without it the checker reports dlsym as
// Unsupported. NeperOS has no dynamic symbols, so it always answers not-found; the modules that use
// dlsym (e.gpu's Vulkan backend) only run their CPU backend here, where this path is pruned.
fn dl_lookup(a: *mem.Arena, l: Lib, sym: str) -> (usize, err) { ret (0usize, Unsupported) }
// A NeperOS program runs on one thread here, so a fixed non-zero id identifies it. Non-zero
// matters: a zero reads as "no owner" to a reentrant lock (e.gpu's device lock), which would then
// re-lock a mutex it already holds on the same thread and deadlock. (A real per-thread id would be
// a kernel query, for when a program's own threads each take the lock.)
fn current_thread_id() -> usize { ret 1usize }
fn open_at(a: *mem.Arena, dir: Dir, relative_path: str, flags: OpenFlags, policy: ResolvePolicy) -> (File, err) { ret (File { raw: 0usize }, Unsupported) }
fn remove_at(a: *mem.Arena, dir: Dir, relative_path: str, directory: bool) -> err { ret Unsupported }
fn rename_at(a: *mem.Arena, src_dir: Dir, src_path: str, dst_dir: Dir, dst_path: str, overwrite: bool, durable: bool) -> err { ret Unsupported }

// (D2168/D2169, C110) The native-window surface e.ui.window compiles against. NeperOS has no window
// manager: a window IS the compositor's shared surface (vm.SHARED_FRAME_VA, a fixed 256x256 BGRA
// frame the kernel maps into a windowed app's space in a compositor boot). window_present copies the
// app's rendered pixels into that frame and signals the compositor on endpoint slot 1, exactly as a
// hand-written compositor app does; window_poll reports no event (neperos input reaches an app over
// the compositor's routed endpoint, not here). The headless testing harness touches none of these.
const SHARED_FRAME_VA: usize = 548683907072usize
const SURFACE_SIDE: usize = 256usize
const COMP_ENDPOINT: usize = 1usize
const FRAME_READY: usize = 1usize
type Window = struct { raw: usize }
type WindowMode = enum u8 { Windowed, Maximized, Fullscreen }
type WindowOptions = struct { title: str, width: u32, height: u32, resizable: bool, visible: bool, mode: WindowMode }
type WindowMetrics = struct { width: u32, height: u32, scale_percent: u32, focused: bool, visible: bool }
type CursorShape = enum u8 { Arrow, Text, Hand, Crosshair, ResizeHorizontal, ResizeVertical, Hidden }
type MonitorInfo = struct { x: i32, y: i32, width: u32, height: u32, work_x: i32, work_y: i32, work_width: u32, work_height: u32, scale_percent: u32, primary: bool }
type AccessibleNode = struct { id: u32, generation: u32, parent: u32, parent_generation: u32, has_parent: bool, role: u8, label: str, value: str, hint: str, flags: u16, actions: u32, sort: u8, live: u8, row: u32, column: u32, row_count: u32, column_count: u32, level: u8, selection_start: usize, selection_end: usize, labelled_by: u32, labelled_by_generation: u32, described_by: u32, described_by_generation: u32, error_by: u32, error_by_generation: u32, controls: u32, controls_generation: u32, active: u32, active_generation: u32, relation_flags: u8, x: f32, y: f32, width: f32, height: f32 }
fn window_open(a: *mem.Arena, options: WindowOptions) -> (Window, err) { ret (Window { raw: 1usize }, ok) }
fn window_close(w: Window) -> err { ret ok }
fn window_metrics(w: Window) -> (WindowMetrics, err) { ret (WindowMetrics { width: u32(SURFACE_SIDE), height: u32(SURFACE_SIDE), scale_percent: 100u32, focused: true, visible: true }, ok) }
fn window_title(w: Window, value: str) -> err { ret ok }
fn window_visible(w: Window, value: bool) -> err { ret ok }
fn window_cursor(w: Window, shape: CursorShape) -> err { ret ok }
// Blit the rendered pixels (Bgra8 packed into u32) into the shared surface at its 256-stride, then
// signal the compositor that the frame is ready. A pixel outside the surface is dropped.
fn window_present(w: Window, pixels: []const u32, width: u32, height: u32) -> err {
    var y = 0usize
    while y < usize(height) && y < SURFACE_SIDE {
        var x = 0usize
        while x < usize(width) && x < SURFACE_SIDE {
            store32(SHARED_FRAME_VA + (y * SURFACE_SIDE + x) * 4usize, u32(pixels[y * usize(width) + x]))
            x += 1usize
        }
        y += 1usize
    }
    let signalled = send(COMP_ENDPOINT, FRAME_READY, 99usize)
    ret ok
}
fn monitors(a: *mem.Arena, limit: usize) -> ([]const MonitorInfo, err) {
    var none: []const MonitorInfo = zero
    ret (none, Unsupported)
}
fn clipboard_text(a: *mem.Arena) -> (str, err) { ret ("", Unsupported) }
fn set_clipboard_text(value: str) -> err { ret Unsupported }
// e.ui.input polls this; a NeperOS app gets input over the compositor's routed endpoint instead, so
// there is never a window event here -- but it answers ok (no event), not Unsupported, or the e.ui
// app loop would treat the poll as a failure.
type WindowEventKind = enum u8 { Close, Resize, Focus, Blur, PointerMove, PointerDown, PointerUp, Scroll, KeyDown, KeyUp, Text, Paint }
type WindowEvent = struct { kind: WindowEventKind, window: Window, x: i32, y: i32, width: u32, height: u32, button: u8, key: u32, modifiers: u8, delta: i32, codepoint: u32, repeat: bool }
fn window_poll(timeout_ns: i64) -> (WindowEvent, bool, err) {
    var event: WindowEvent = zero
    ret (event, false, ok)
}
fn window_capture(w: Window, on: bool) -> err { ret Unsupported }
// The accessibility-bridge surface e.ui.accessibility compiles against -- no window, no AT client.
type AccessibleRequest = struct { id: u32, generation: u32, action: u8, value: str }
fn accessibility_listening(w: Window) -> bool { ret false }
fn accessibility_publish(w: Window, nodes: []const AccessibleNode) -> err { ret Unsupported }
fn accessibility_take(w: Window) -> (AccessibleRequest, bool) {
    var request: AccessibleRequest = zero
    ret (request, false)
}
