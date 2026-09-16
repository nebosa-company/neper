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
// What `wait_usage` answers (D311): the exit code `wait` would, and the most memory the
// process ever had resident, in bytes.
type ProcUsage = struct { exit_code: i32, peak_memory: usize }
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

type Dir = resource(dir_close) struct { raw: usize }
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

type Watch = resource(watch_close) struct { state: *void }
type WatchAction = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type WatchEvent = struct { action: WatchAction, path: str, old_path: str }

// `FILE_NOTIFY_INFORMATION`: three four-byte fields and then the name in UTF-16, whose length
// is in bytes. `next` is the offset to the following entry, or zero at the last one -- so the
// walk follows it rather than assuming a stride.
type NotifyHeader = struct { next: u32, action: u32, name_length: u32 }

// What a watch remembers: the directory handle to read from, and the path it stands for --
// because the host reports a name relative to that and `WatchEvent` wants a path.
// `OVERLAPPED`. The event is left at zero, which is what makes the file handle the thing
// completion signals.
type Overlapped = struct { status: usize, transferred: usize, offset: u32, offset_high: u32, event: usize }

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

type Lib = resource(dlclose) struct { raw: usize }

type ProcGroup = resource(proc_group_close) struct { raw: usize }
type SpawnOptions = struct { argv: []const str, env: []const str, inherit_env: bool, cwd: str, stdio: Stdio }

// `STARTUPINFOW`: the padding is written out because the three standard handles are at the end
// of it and the call reads them where the header says they are, not where they would fall if a
// field were missing.
type StartupInfo = struct {
    size: u32,
    padding: u32,
    reserved: usize,
    desktop: usize,
    title: usize,
    x: u32,
    y: u32,
    x_size: u32,
    y_size: u32,
    x_chars: u32,
    y_chars: u32,
    fill: u32,
    flags: u32,
    show: u16,
    reserved_count: u16,
    padding_two: u32,
    reserved_block: usize,
    standard_input: usize,
    standard_output: usize,
    standard_error: usize,
}

type ProcessInformation = struct { process: usize, thread: usize, process_id: u32, thread_id: u32 }

// `SYSTEM_INFO`. Only the page size is read, but the whole thing has to be here for the call
// to have somewhere to put it -- and for `page_size` to be at the offset it is.
type SystemInfo = struct {
    oem_id: u32,
    page_size: u32,
    minimum_address: usize,
    maximum_address: usize,
    active_mask: usize,
    processor_count: u32,
    processor_type: u32,
    allocation_granularity: u32,
    processor_level: u16,
    processor_revision: u16,
}

// What a watch remembers. The buffer and the `OVERLAPPED` both have to outlive the call that
// starts a read, because the host writes into them while nothing is waiting -- so they live in
// the arena with the rest of the state rather than in a frame.
type WatchState = struct {
    directory: usize,
    base: str,
    recursive: bool,
    buffer: []u8,
    overlapped: Overlapped,
}

fn arm_watch(state: *WatchState) -> err {
    state.overlapped.status = 0usize
    state.overlapped.transferred = 0usize
    state.overlapped.offset = 0u32
    state.overlapped.offset_high = 0u32
    state.overlapped.event = 0usize
    var recursive_flag = 0i32
    if state.recursive { recursive_flag = 1i32 }
    var ignored = 0u32
    // The kernel fills the buffer as changes arrive (D428): its pages committed first.
    touch(&state.buffer[0usize], WATCH_BUFFER)
    if raw_read_changes(state.directory, &state.buffer[0usize], u32(WATCH_BUFFER), recursive_flag, WATCH_FILTER, &ignored, &state.overlapped, 0usize) == 0i32 {
        ret from_last_error()
    }
    ret ok
}

fn watch_open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err) {
    var watch: Watch = zero
    // This host would take `recursive` as a parameter and the other needs a watch per
    // directory, so honouring it here alone would make a program that works here fail there.
    // Both refuse until both can.
    if recursive { ret (watch, Unsupported) }
    let checkpoint = mem.mark(a)
    let (name, name_error) = widen(a, path)
    if name_error != ok {
        mem.reset(a, checkpoint)
        ret (watch, name_error)
    }
    let directory = raw_create_file(&name[0usize], DIRECTORY_ACCESS, FILE_SHARE_ALL, 0usize, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, 0usize)
    if directory == INVALID_HANDLE {
        let open_error = from_last_error()
        mem.reset(a, checkpoint)
        ret (watch, open_error)
    }
    let (holder, holder_error) = mem.alloc[WatchState](a, 1usize)
    if holder_error != ok {
        let unused = raw_close_handle(directory)
        ret (watch, OutOfMemory)
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, WATCH_BUFFER)
    if buffer_error != ok {
        let unused = raw_close_handle(directory)
        ret (watch, OutOfMemory)
    }
    holder[0usize].directory = directory
    holder[0usize].base = path
    holder[0usize].recursive = recursive
    holder[0usize].buffer = buffer
    // Armed here, so a change made before the first read is still reported.
    let arm_error = arm_watch(&holder[0usize])
    if arm_error != ok {
        let unused = raw_close_handle(directory)
        ret (watch, arm_error)
    }
    watch.state = mem.cast[*void](&holder[0usize])
    ret (watch, ok)
}

fn action_from_code(action: u32) -> WatchAction {
    if action == FILE_ACTION_ADDED { ret .Added }
    if action == FILE_ACTION_REMOVED { ret .Removed }
    // The two halves of a rename arrive as separate entries, so each is reported as what it
    // is rather than guessed at: the old name going and the new one appearing.
    if action == FILE_ACTION_RENAMED_OLD { ret .Removed }
    if action == FILE_ACTION_RENAMED_NEW { ret .Added }
    ret .Modified
}

// The name and the watched directory joined, in the caller's arena. The separator is written
// here rather than through `e.path`, which `e.os` may not depend on.
fn watch_path(a: *mem.Arena, base: str, name: *const u16, units: usize) -> (str, err) {
    // A UTF-16 unit never becomes more than three UTF-8 bytes.
    let (bytes, allocation_error) = mem.alloc[u8](a, base.len + 1usize + units * 3usize)
    if allocation_error != ok { ret ("", OutOfMemory) }
    var at = 0usize
    while at < base.len {
        bytes[at] = base[at]
        at += 1usize
    }
    if at != 0usize && bytes[at - 1usize] != 92u8 && bytes[at - 1usize] != 47u8 {
        bytes[at] = 92u8
        at += 1usize
    }
    if units == 0usize { ret (bytes[0usize..at], ok) }
    touch(&bytes[at], units * 3usize)
    let converted = raw_narrow(CP_UTF8, 0u32, name, i32(units), &bytes[at], i32(units * 3usize), 0usize, 0usize)
    if converted <= 0i32 { ret ("", Failed) }
    ret (bytes[0usize..at + usize(converted)], ok)
}

// Waits for the read that is already outstanding, then arms the next one before returning --
// so the gap in which a change could be missed is never open.
fn watch_read(a: *mem.Arena, w: Watch, events: []WatchEvent) -> (usize, err) {
    let state = mem.cast[*WatchState](w.state)
    if events.len == 0usize { ret (0usize, ok) }
    var returned = 0u32
    if raw_overlapped_result(state.directory, &state.overlapped, &returned, 1i32) == 0i32 {
        ret (0usize, from_last_error())
    }
    let buffer = state.buffer
    var produced = 0usize
    var at = 0usize
    while at + 12usize <= usize(returned) {
        let header = mem.cast[*NotifyHeader](&buffer[at])
        let next = usize(header.next)
        let action = header.action
        let units = usize(header.name_length) / 2usize
        if produced < events.len {
            var entry: WatchEvent = zero
            entry.action = action_from_code(action)
            let names = mem.cast[*const u16](&buffer[at + 12usize])
            let (joined, join_error) = watch_path(a, state.base, names, units)
            if join_error != ok { ret (produced, join_error) }
            entry.path = joined
            events[produced] = entry
            produced += 1usize
        }
        // A zero `next` is the last entry, and following it is what keeps the walk on the
        // entries the call actually wrote rather than on a stride they do not have.
        if next == 0usize { break }
        at += next
    }
    let rearm_error = arm_watch(state)
    if rearm_error != ok { ret (produced, rearm_error) }
    ret (produced, ok)
}

// The outstanding read is cancelled before the handle goes, so the host is not left writing
// into a buffer nothing is waiting for.
fn watch_close(w: own Watch) -> err {
    let state = mem.cast[*WatchState](w.state)
    let cancelled = raw_cancel_io(state.directory)
    if raw_close_handle(state.directory) == 0i32 { ret from_last_error_cleanup() }
    ret ok
}

type Mapping = resource(mapping_close) struct { raw: usize, address: *u8, len: usize }

// `raw` carries whether the mapping may be written and nothing else. The mapping object is
// closed as soon as the view exists -- the view holds its own reference, so the handle is not
// worth keeping -- which leaves the field for the one thing that has to be remembered:
// `mapping_bytes_mut` must refuse rather than let a write fault.
const MAPPING_READ_ONLY: usize = 0usize
const MAPPING_WRITABLE: usize = 1usize

// The offset is the caller's to align, and this host wants it on a 64 KiB boundary rather
// than a page -- the allocation granularity, not the page size.
fn map_file(f: File, offset: u64, len: usize, writable: bool) -> (Mapping, err) {
    var mapping: Mapping = zero
    if len == 0usize { ret (mapping, Failed) }
    var protection = PAGE_READONLY
    var access = FILE_MAP_READ
    if writable {
        protection = PAGE_READWRITE
        access = FILE_MAP_READ | FILE_MAP_WRITE
    }
    // A zero size maps the whole file, which is what a length past the end would mean here
    // anyway: the size asked for is the view's, not the object's.
    let object = raw_create_mapping(f.raw, 0usize, protection, 0u32, 0u32, 0usize)
    if object == 0usize { ret (mapping, from_last_error()) }
    let address = raw_map_view(object, access, u32(offset / 4294967296u64), u32(offset % 4294967296u64), len)
    // The object goes now: the view keeps it alive, and nothing later needs the handle.
    let closed = raw_close_handle(object)
    if mem.address_of(address) == 0usize { ret (mapping, from_last_error()) }
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
    if raw_flush_view(m.address, m.len) == 0i32 { ret from_last_error() }
    ret ok
}

fn mapping_close(m: own Mapping) -> err {
    if raw_unmap_view(m.address) == 0i32 { ret from_last_error_cleanup() }
    ret ok
}

type Poller = resource(poller_close) struct { state: *void }
type PollInterest = struct { readable: bool, writable: bool }
type PollEvent = struct { token: usize, readable: bool, writable: bool, closed: bool, failed: bool }

// `WSAPOLLFD`, and the opposite problem from `epoll_event` on the other host. That one is
// packed, so its padding has to be kept out by hand; this one is ordinary, and the socket's
// eight-byte alignment rounds the whole structure back up to sixteen without anything being
// said -- which is the stride the call indexes by. Measured: writing a tail field changes
// nothing, so it is not written.
type WsaPollFd = struct { handle: usize, events: u16, revents: u16 }

type PollRegistration = struct { handle: usize, token: usize, readable: bool, writable: bool, active: bool }

// `WSAPoll` retains nothing between calls, so what the fence calls a poller is this: the
// set, kept in the arena `poller_open` was given, plus the socket a wake arrives on. A
// completion port would retain the set and even carry the token as its completion key, but
// it reports finished operations rather than ready handles, so `readable` and `writable`
// would have nothing to mean -- which is why the set is held here rather than by the host.
type PollerState = struct {
    wake: Socket,
    wake_address: SocketAddress,
    registrations: []PollRegistration,
}

// Only sockets. `WSAPoll` reports `POLLNVAL` for anything else, which arrives as a failed
// event rather than as a lie -- a file handle registered here is answered, not ignored.
fn poller_open(a: *mem.Arena) -> (Poller, err) {
    var poller: Poller = zero
    let (wake, wake_error) = socket_open(.Ip4, .Datagram)
    if wake_error != ok { ret (poller, wake_error) }
    var wanted: SocketAddress = zero
    wanted.family = .Ip4
    wanted.bytes[0usize] = 127u8
    wanted.bytes[3usize] = 1u8
    // Port zero, and then ask: the wake has to know where to send, and D112 is what makes
    // that answerable without a library choosing a port for the machine.
    let bind_error = socket_bind(wake, wanted)
    if bind_error != ok {
        let unused = socket_close(wake)
        ret (poller, bind_error)
    }
    let (local, local_error) = socket_local_address(wake)
    if local_error != ok {
        let unused = socket_close(wake)
        ret (poller, local_error)
    }
    // Non-blocking, so draining the wake stops when it is empty rather than waiting for a
    // datagram that is not coming.
    let block_error = socket_set_nonblocking(wake, true)
    if block_error != ok {
        let unused = socket_close(wake)
        ret (poller, block_error)
    }
    let (holder, holder_error) = mem.alloc[PollerState](a, 1usize)
    if holder_error != ok {
        let unused = socket_close(wake)
        ret (poller, OutOfMemory)
    }
    let (table, table_error) = mem.alloc[PollRegistration](a, POLL_CAPACITY)
    if table_error != ok {
        let unused = socket_close(wake)
        ret (poller, OutOfMemory)
    }
    var at = 0usize
    while at < POLL_CAPACITY {
        table[at].active = false
        at += 1usize
    }
    holder[0usize].wake = wake
    holder[0usize].wake_address = local
    holder[0usize].registrations = table
    poller.state = mem.cast[*void](&holder[0usize])
    ret (poller, ok)
}

fn find_registration(state: *PollerState, handle: Handle) -> (usize, bool) {
    var at = 0usize
    while at < state.registrations.len {
        if state.registrations[at].active && state.registrations[at].handle == handle.raw { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A second registration of one handle is `Exists` and a full table is `OutOfMemory`, which
// are the answers the other host's kernel gives to the same two mistakes.
fn poller_register(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    let state = mem.cast[*PollerState](p.state)
    let (existing, found) = find_registration(state, handle)
    if found { ret Exists }
    var at = 0usize
    while at < state.registrations.len {
        if !state.registrations[at].active {
            state.registrations[at].handle = handle.raw
            state.registrations[at].token = token
            state.registrations[at].readable = interest.readable
            state.registrations[at].writable = interest.writable
            state.registrations[at].active = true
            ret ok
        }
        at += 1usize
    }
    ret OutOfMemory
}

fn poller_modify(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    let state = mem.cast[*PollerState](p.state)
    let (slot, found) = find_registration(state, handle)
    if !found { ret NotFound }
    state.registrations[slot].token = token
    state.registrations[slot].readable = interest.readable
    state.registrations[slot].writable = interest.writable
    ret ok
}

fn poller_unregister(p: Poller, handle: Handle) -> err {
    let state = mem.cast[*PollerState](p.state)
    let (slot, found) = find_registration(state, handle)
    if !found { ret NotFound }
    state.registrations[slot].active = false
    ret ok
}

// One datagram to the wake socket's own address. It is the same socket sending and
// receiving, which is what makes this need no second descriptor and no pair.
fn poller_wake(p: Poller) -> err {
    let state = mem.cast[*PollerState](p.state)
    var one: [1]u8 = zero
    one[0usize] = 1u8
    let (sent, send_error) = socket_send_to(state.wake, state.wake_address, one[..])
    if send_error != ok { ret send_error }
    ret ok
}

fn poller_wait(p: Poller, events: []PollEvent, timeout_ns: i64) -> (usize, err) {
    let state = mem.cast[*PollerState](p.state)
    if events.len == 0usize { ret (0usize, ok) }
    // The whole set goes in on every call, the wake last so its index is known.
    var entries: [65]WsaPollFd = zero
    var slots: [65]usize = zero
    var count = 0usize
    var at = 0usize
    while at < state.registrations.len {
        if state.registrations[at].active && count < POLL_CAPACITY {
            var mask = 0u16
            if state.registrations[at].readable { mask = mask | POLLRDNORM }
            if state.registrations[at].writable { mask = mask | POLLWRNORM }
            entries[count].handle = state.registrations[at].handle
            entries[count].events = mask
            slots[count] = at
            count += 1usize
        }
        at += 1usize
    }
    let wake_index = count
    entries[wake_index].handle = state.wake.raw
    entries[wake_index].events = POLLRDNORM
    count += 1usize

    var milliseconds = -1i32
    if timeout_ns == 0i64 { milliseconds = 0i32 }
    if timeout_ns > 0i64 {
        milliseconds = i32(timeout_ns / 1000000i64)
        // Anything positive but shorter than a millisecond is rounded up, so asking for a
        // little time never means asking for none.
        if milliseconds == 0i32 { milliseconds = 1i32 }
    }
    let ready = raw_socket_poll(&entries[0usize], u32(count), milliseconds)
    if ready < 0i32 { ret (0usize, from_socket_error()) }
    if ready == 0i32 { ret (0usize, ok) }

    var produced = 0usize
    at = 0usize
    while at < count {
        if entries[at].revents != 0u16 {
            if at == wake_index {
                // The poller's own datagrams, drained so the next wait does not see them
                // again and never reported, because they are not the caller's.
                var drain: [16]u8 = zero
                var draining = true
                while draining {
                    let (taken, source, drain_error) = socket_receive_from(state.wake, drain[..])
                    if drain_error != ok { draining = false }
                }
            } else {
                if produced < events.len {
                    events[produced].token = state.registrations[slots[at]].token
                    events[produced].readable = entries[at].revents & POLLRDNORM != 0u16
                    events[produced].writable = entries[at].revents & POLLWRNORM != 0u16
                    events[produced].closed = entries[at].revents & POLLHUP != 0u16
                    events[produced].failed = entries[at].revents & (POLLERR | POLLNVAL) != 0u16
                    produced += 1usize
                }
            }
        }
        at += 1usize
    }
    ret (produced, ok)
}

fn poller_close(p: own Poller) -> err {
    let state = mem.cast[*PollerState](p.state)
    ret socket_close(state.wake)
}

type Socket = resource(socket_close) struct { raw: usize }
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

// `ADDRINFOW`. `address` is a pointer rather than a `usize` because the bytes behind it have to
// be read, and there is no way back from an address to a pointer (D96); `next` is `*void` for
// the same reason with the added one that a type cannot name itself here.
type AddressInfo = struct {
    flags: i32,
    family: i32,
    kind: i32,
    protocol: i32,
    address_len: usize,
    canonical_name: usize,
    address: *u8,
    next: *void,
}

// The call answers with a pointer, so it is given somewhere to put one: a `*AddressInfo` out
// parameter would be an address this file could not follow, and this is a pointer it can.
type AddressInfoHead = struct { node: *void }

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

@import("kernel32.dll", "SetHandleInformation")
extern fn raw_set_handle_information(handle: usize, mask: u32, flags: u32) -> i32

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

@import("ws2_32.dll", "getsockname")
extern fn raw_socket_local(s: usize, address: *RawAddress, length: *i32) -> i32

// The whole readiness set is passed in on every call: `WSAPoll` retains nothing, which is
// why the registrations are kept here instead.
@import("ws2_32.dll", "WSAPoll")
extern fn raw_socket_poll(entries: *WsaPollFd, count: u32, timeout: i32) -> i32

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
@import("ws2_32.dll", "GetAddrInfoW")
extern fn raw_address_info(node: *const u16, service: usize, hints: *AddressInfo, result: *AddressInfoHead) -> i32

@import("ws2_32.dll", "FreeAddrInfoW")
extern fn raw_free_address_info(head: *void)

@import("ws2_32.dll", "WSAGetLastError")
extern fn raw_socket_error() -> i32

@import("kernel32.dll", "CreateFileMappingW")
extern fn raw_create_mapping(file: usize, security: usize, protect: u32, size_high: u32, size_low: u32, name: usize) -> usize

// The one call in this file that hands back a pointer. That is what makes a file mapping
// expressible here at all: an address cannot become a pointer in source (D96), and a foreign
// declaration is where one comes into existence.
@import("kernel32.dll", "MapViewOfFile")
extern fn raw_map_view(mapping: usize, access: u32, offset_high: u32, offset_low: u32, length: usize) -> *u8

@import("kernel32.dll", "UnmapViewOfFile")
extern fn raw_unmap_view(address: *u8) -> i32

@import("kernel32.dll", "FlushViewOfFile")
extern fn raw_flush_view(address: *u8, length: usize) -> i32

// The overlapped form, and it has to be: the synchronous one starts recording when it is
// called, so a change between opening a watch and first reading it would be lost -- where the
// other host queues from the moment the watch exists. Arming the read at open is what makes
// the two contracts the same.
@import("kernel32.dll", "ReadDirectoryChangesW")
extern fn raw_read_changes(directory: usize, buffer: *u8, length: u32, recursive: i32, filter: u32, returned: *u32, overlapped: *Overlapped, routine: usize) -> i32

// With no event in the `OVERLAPPED`, the file handle itself is what completion signals, and
// waiting for it is this call -- so no event object and no separate wait are needed while one
// read is outstanding at a time, which is all this ever has.
@import("kernel32.dll", "GetOverlappedResult")
extern fn raw_overlapped_result(handle: usize, overlapped: *Overlapped, returned: *u32, block: i32) -> i32

@import("kernel32.dll", "CancelIo")
extern fn raw_cancel_io(handle: usize) -> i32

@import("kernel32.dll", "CreatePipe")
extern fn raw_create_pipe(reading: *usize, writing: *usize, security: usize, size: u32) -> i32

@import("kernel32.dll", "DuplicateHandle")
extern fn raw_duplicate_handle(source_process: usize, source: usize, target_process: usize, duplicate: *usize, access: u32, inherit: i32, options: u32) -> i32

@import("kernel32.dll", "TerminateProcess")
extern fn raw_terminate_process(process: usize, code: u32) -> i32

@import("kernel32.dll", "WaitForSingleObject")
extern fn raw_wait_for_single_object(handle: usize, milliseconds: u32) -> u32

@import("kernel32.dll", "GetExitCodeProcess")
extern fn raw_exit_code_process(process: usize, code: *u32) -> i32

@import("kernel32.dll", "GetCurrentProcess")
extern fn raw_current_process() -> usize

// `psapi`'s counters, exported by `kernel32` under this name since Windows 7.
@import("kernel32.dll", "K32GetProcessMemoryInfo")
extern fn raw_process_memory_info(process: usize, counters: *MemoryCounters, size: u32) -> i32

@import("kernel32.dll", "VirtualFree")
extern fn raw_virtual_free(address: *u8, size: usize, kind: u32) -> i32

@import("kernel32.dll", "GetSystemInfo")
extern fn raw_system_info(info: *SystemInfo)

@import("kernel32.dll", "LockFileEx")
extern fn raw_lock_file(file: usize, flags: u32, reserved: u32, length_low: u32, length_high: u32, overlapped: *Overlapped) -> i32

@import("kernel32.dll", "UnlockFileEx")
extern fn raw_unlock_file(file: usize, reserved: u32, length_low: u32, length_high: u32, overlapped: *Overlapped) -> i32

@import("kernel32.dll", "Sleep")
extern fn raw_sleep(milliseconds: u32)

@import("kernel32.dll", "CreateProcessW")
extern fn raw_create_process(image: usize, command: *u16, process_attributes: usize, thread_attributes: usize, inherit: i32, flags: u32, environment: usize, directory: usize, startup: *StartupInfo, information: *ProcessInformation) -> i32

@import("kernel32.dll", "CreateJobObjectW")
extern fn raw_create_job(security: usize, name: usize) -> usize

@import("kernel32.dll", "AssignProcessToJobObject")
extern fn raw_assign_job(job: usize, process: usize) -> i32

@import("kernel32.dll", "TerminateJobObject")
extern fn raw_terminate_job(job: usize, code: u32) -> i32

@import("kernel32.dll", "ResumeThread")
extern fn raw_resume_thread(thread: usize) -> u32

@import("kernel32.dll", "GetEnvironmentStringsW")
extern fn raw_environment_strings() -> *u8

@import("kernel32.dll", "FreeEnvironmentStringsW")
extern fn raw_free_environment_strings(block: *u8) -> i32

@import("kernel32.dll", "GetStdHandle")
extern fn raw_std_handle(which: u32) -> usize

@import("kernel32.dll", "FormatMessageW")
extern fn raw_format_message(flags: u32, source: usize, code: u32, language: u32, buffer: *u16, size: u32, arguments: usize) -> u32

@import("kernel32.dll", "LoadLibraryW")
extern fn raw_load_library(name: *const u16) -> usize

// The only call here whose string is bytes rather than units: a symbol name is ASCII and there
// is no wide form of this one to prefer.
@import("kernel32.dll", "GetProcAddress")
extern fn raw_proc_address(library: usize, symbol: *const u8) -> usize

@import("kernel32.dll", "FreeLibrary")
extern fn raw_free_library(library: usize) -> i32

@import("kernel32.dll", "GetCurrentThreadId")
extern fn raw_current_thread() -> u32

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

// `WSAPOLLFD`'s request and result bits. Read and write are asked for by name; the other
// three arrive whether or not anything asked.
const POLLRDNORM: u16 = 256u16
const POLLWRNORM: u16 = 16u16
const POLLERR: u16 = 1u16
const POLLHUP: u16 = 2u16
const POLLNVAL: u16 = 4u16

// ponytail: a fixed set, because the table is one arena allocation made when the poller
// opens; a growing one is what to write if something registers more than this.
const POLL_CAPACITY: usize = 64usize

const PAGE_READONLY: u32 = 2u32
const PAGE_READWRITE: u32 = 4u32
const FILE_MAP_WRITE: u32 = 2u32
const FILE_MAP_READ: u32 = 4u32

// Names appearing or going, sizes changing, and contents written: what a change to a
// directory's contents means.
const WATCH_FILTER: u32 = 27u32

const FILE_ACTION_ADDED: u32 = 1u32
const FILE_ACTION_REMOVED: u32 = 2u32
const FILE_ACTION_RENAMED_OLD: u32 = 4u32
const FILE_ACTION_RENAMED_NEW: u32 = 5u32

// ponytail: one read takes at most this much, so a burst larger than it arrives across
// successive reads rather than being lost.
const WATCH_BUFFER: usize = 8192usize

// Asynchronous use has to be asked for when the handle is opened.
const FILE_FLAG_OVERLAPPED: u32 = 1073741824u32

// `MEM_RELEASE`, which gives back a whole reservation and insists the size be zero -- the
// reservation's own length is what it uses.
const MEM_RELEASE: u32 = 32768u32

// What `kill` reports as the exit code. The other host has no say in this: there a signal
// becomes 128 plus its number, so the two do not agree on the value and a caller can only
// rely on it being a failure.
const KILL_EXIT_CODE: u32 = 9u32

const LOCKFILE_FAIL_IMMEDIATELY: u32 = 1u32
const LOCKFILE_EXCLUSIVE_LOCK: u32 = 2u32

// ERROR_LOCK_VIOLATION: someone else holds it, which is the one failure worth trying again.
const ERROR_LOCK_VIOLATION: u32 = 33u32

// ponytail: a timeout is polled, because neither host offers one -- ten milliseconds between
// tries. A host call that took a deadline would replace the loop entirely.
const LOCK_POLL_MS: u32 = 10u32

// Suspended, so the child is in the job before it can start anything of its own; assigning
// afterwards is a race against the children it has already had.
const CREATE_SUSPENDED: u32 = 4u32
const CREATE_UNICODE_ENVIRONMENT: u32 = 1024u32
const STARTF_USESTDHANDLES: u32 = 256u32
const HANDLE_FLAG_INHERIT: u32 = 1u32

// `STD_INPUT_HANDLE` and its two neighbours, which are negative numbers passed as unsigned.
const STD_INPUT: u32 = 4294967286u32
const STD_OUTPUT: u32 = 4294967285u32
const STD_ERROR: u32 = 4294967284u32

// ponytail: an argument or environment list longer than this is refused rather than growing the
// buffers; a caller with more than a thousand of either is doing something this is not for.
const SPAWN_LIST_MAX: usize = 1024usize

// ponytail: how far into the inherited environment block this reads before giving up on finding
// its end. The host does not say how long the block is, and there is no counted call that would;
// this is well past what `CreateProcessW` itself accepts.
const MAX_ENVIRONMENT_UNITS: usize = 65536usize

const RAW_IP4_SIZE: usize = 16usize
const RAW_IP6_SIZE: usize = 28usize

// ponytail: how many addresses one name may answer with here. A name behind more than this is
// answered with the first of them, which is what a caller about to connect to one of them wants
// anyway.
const RESOLVE_ADDRESS_MAX: usize = 8usize

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
    touch(mem.cast[*const u8](&units[0usize]), (text.len + 1usize) * 2usize)
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
fn current_thread_id() -> usize {
    ret usize(raw_current_thread())
}

// The same classification `from_last_error` makes, as the enum the fence names. A native code here
// may be a Win32 error, a socket error or an `NTSTATUS`, and the three do not share a numbering --
// which is the reason the detail carries the raw code as well as the kind.
fn error_kind_of(code: i32) -> ErrorKind {
    if code == 2i32 { ret .NotFound }
    if code == 3i32 { ret .NotFound }
    if code == 123i32 { ret .NotFound }
    if code == 5i32 { ret .Denied }
    if code == 32i32 { ret .Denied }
    if code == 80i32 { ret .Exists }
    if code == 183i32 { ret .Exists }
    if code == 8i32 { ret .OutOfMemory }
    if code == 87i32 { ret .Invalid }
    if code == 50i32 { ret .Unsupported }
    if code == 258i32 { ret .Timeout }
    if code == 10035i32 { ret .WouldBlock }
    if code == 10060i32 { ret .Timeout }
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
// Set when a failure was recorded and not yet read (D360, H07): a failing cleanup
// then leaves the slot alone, so the primary failure's detail is what
// `last_error_detail` finds after the cleanup.
var error_slot_fresh: [64]u8

// The code is written first and the identifier last, so a reader that sees its own identifier is
// looking at a slot whose code was already stored. Without atomics that is the most that can be
// said, and it is enough for the only failure that matters here.
fn record_error_detail(code: i32) {
    let thread = current_thread_id()
    let slot = thread % ERROR_SLOTS
    error_slot_code[slot] = code
    error_slot_used[slot] = 1u8
    error_slot_thread[slot] = thread
    error_slot_fresh[slot] = 1u8
}

// A cleanup's failure is recorded only when no primary failure waits to be read.
fn record_cleanup_error_detail(code: i32) {
    let thread = current_thread_id()
    let slot = thread % ERROR_SLOTS
    if error_slot_fresh[slot] == 1u8 && error_slot_used[slot] == 1u8 && error_slot_thread[slot] == thread { ret }
    record_error_detail(code)
}

// The checked path with the caller's detail (D417, H07): the failure's detail is
// written into `detail` at the failing call, before any cleanup on the way out can
// record over it, and the caller holds it as ordinary data -- `kind`,
// `native_code`, the operation and the subject -- with no slot to read later and no
// order to keep. On success `detail` is not written. The same `err` comes back
// as from the plain call, so `try` and the affine rules see nothing new.
fn stat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = stat(a, path)
    if stat_error != ok {
        *detail = last_error_detail("stat", path)
        ret (info, stat_error)
    }
    ret (info, ok)
}

fn dir_open_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (Dir, err) {
    let (dir, open_error) = dir_open(a, path)
    if open_error != ok {
        *detail = last_error_detail("dir_open", path)
        ret (dir, open_error)
    }
    ret (dir, ok)
}

fn open_detail(a: *mem.Arena, path: str, flags: OpenFlags, detail: *ErrorDetail) -> (File, err) {
    let (file, open_error) = open(a, path, flags)
    if open_error != ok {
        *detail = last_error_detail("open", path)
        ret (file, open_error)
    }
    ret (file, ok)
}

// The rest of the path-taking surface in the `_detail` form (D443, H07): each
// writes its own failure into the caller's value at the call, as `stat_detail`
// does, so no order with a later failing operation is the caller's to keep.
fn lstat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = lstat(a, path)
    if stat_error != ok {
        *detail = last_error_detail("lstat", path)
        ret (info, stat_error)
    }
    ret (info, ok)
}

fn mkdir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let made = mkdir(a, path)
    if made != ok { *detail = last_error_detail("mkdir", path) }
    ret made
}

fn remove_file_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let removed = remove_file(a, path)
    if removed != ok { *detail = last_error_detail("remove_file", path) }
    ret removed
}

fn remove_dir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err {
    let removed = remove_dir(a, path)
    if removed != ok { *detail = last_error_detail("remove_dir", path) }
    ret removed
}

fn rename_detail(a: *mem.Arena, src: str, dst: str, detail: *ErrorDetail) -> err {
    let renamed = rename(a, src, dst)
    if renamed != ok { *detail = last_error_detail("rename", src) }
    ret renamed
}

fn create_new_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (File, err) {
    let (file, create_error) = create_new(a, path)
    if create_error != ok {
        *detail = last_error_detail("create_new", path)
        ret (file, create_error)
    }
    ret (file, ok)
}

fn read_link_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err) {
    let (points_to, link_error) = read_link(a, path)
    if link_error != ok {
        *detail = last_error_detail("read_link", path)
        ret (points_to, link_error)
    }
    ret (points_to, ok)
}

fn canonical_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err) {
    let (resolved, canonical_error) = canonical(a, path)
    if canonical_error != ok {
        *detail = last_error_detail("canonical", path)
        ret (resolved, canonical_error)
    }
    ret (resolved, ok)
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
    error_slot_fresh[slot] = 0u8
    detail.native_code = code
    detail.kind = error_kind_of(code)
    ret detail
}

fn from_last_error() -> err {
    let code = raw_last_error()
    record_error_detail(i32(code))
    ret error_of_code(code)
}

// A cleanup's failure (D360): classified the same, recorded only over no unread
// primary failure.
fn from_last_error_cleanup() -> err {
    let code = raw_last_error()
    record_cleanup_error_detail(i32(code))
    ret error_of_code(code)
}

fn error_of_code(code: u32) -> err {
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

fn dir_close(dir: own Dir) -> err {
    if raw_close_handle(dir.raw) == 0i32 { ret from_last_error_cleanup() }
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

// The parent is the caller's own directory or one opened for the walk (D350): it is
// taken either way, and closed by raw means only when it is the latter.
@unsafe
fn release_parent(parent: own Dir, dir: Dir) {
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

// This host takes one command line rather than a vector, so the vector has to be joined -- and
// joined the way `CommandLineToArgvW` will take it apart again, or a path with a space in it
// arrives as two arguments. An argument is quoted when it holds a space, a tab or a quote, and
// inside the quotes a run of backslashes is doubled only where it meets one.
fn needs_quotes(argument: str) -> bool {
    if argument.len == 0usize { ret true }
    var at = 0usize
    while at < argument.len {
        if argument[at] == 32u8 || argument[at] == 9u8 || argument[at] == 34u8 { ret true }
        at += 1usize
    }
    ret false
}

fn command_line(a: *mem.Arena, argv: []const str) -> (str, err) {
    if argv.len == 0usize || argv.len >= SPAWN_LIST_MAX { ret ("", Failed) }
    var total = 0usize
    var counted = 0usize
    while counted < argv.len {
        total += argv[counted].len
        counted += 1usize
    }
    // Every byte can at worst double, and every argument can add two quotes and a separator.
    let (bytes, allocation_error) = mem.alloc[u8](a, total * 2usize + argv.len * 3usize + 1usize)
    if allocation_error != ok { ret ("", OutOfMemory) }
    var written = 0usize
    var index = 0usize
    while index < argv.len {
        if index != 0usize {
            bytes[written] = 32u8
            written += 1usize
        }
        let argument = argv[index]
        if !needs_quotes(argument) {
            var plain = 0usize
            while plain < argument.len {
                bytes[written] = argument[plain]
                written += 1usize
                plain += 1usize
            }
        } else {
            bytes[written] = 34u8
            written += 1usize
            var at = 0usize
            while at < argument.len {
                // Count the backslashes first, then decide: doubled where they meet a quote or
                // the closing one, left alone anywhere else.
                var slashes = 0usize
                while at < argument.len && argument[at] == 92u8 {
                    slashes += 1usize
                    at += 1usize
                }
                var repeat = slashes
                if at == argument.len || argument[at] == 34u8 { repeat = slashes * 2usize }
                var emitted = 0usize
                while emitted < repeat {
                    bytes[written] = 92u8
                    written += 1usize
                    emitted += 1usize
                }
                if at < argument.len {
                    if argument[at] == 34u8 {
                        bytes[written] = 92u8
                        written += 1usize
                    }
                    bytes[written] = argument[at]
                    written += 1usize
                    at += 1usize
                }
            }
            bytes[written] = 34u8
            written += 1usize
        }
        index += 1usize
    }
    ret (bytes[0usize..written], ok)
}

// The name a `NAME=VALUE` record sets. A record with no `=` in it is its own name, which is not
// a shape the host produces but is one a caller can pass.
fn entry_name(entry: str) -> str {
    var at = 0usize
    while at < entry.len {
        if entry[at] == 61u8 { ret entry[0usize..at] }
        at += 1usize
    }
    ret entry
}

// Environment names are not case-sensitive on this host -- the block says `Path` and a lookup
// for `PATH` finds it -- so an addition replaces a record that differs only in case. Getting
// this wrong leaves both records in the block and the host answers with whichever it reaches
// first, which is not the caller's entry.
fn folded(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

// The units of one inherited record before its `=`, compared against an addition's name. The
// records are UTF-16 and the additions are not, so this compares a unit at a time: a name with
// anything but ASCII in it never matches, which keeps it rather than dropping it.
fn wide_name_is(bytes: []const u8, start: usize, end: usize, name: str) -> bool {
    if end - start < name.len * 2usize + 2usize { ret false }
    if bytes[start + name.len * 2usize] != 61u8 { ret false }
    if bytes[start + name.len * 2usize + 1usize] != 0u8 { ret false }
    var at = 0usize
    while at < name.len {
        if folded(bytes[start + at * 2usize]) != folded(name[at]) { ret false }
        if bytes[start + at * 2usize + 1usize] != 0u8 { ret false }
        at += 1usize
    }
    ret true
}

fn wide_record_overridden(bytes: []const u8, start: usize, end: usize, entries: []const str) -> bool {
    var at = 0usize
    while at < entries.len {
        if wide_name_is(bytes, start, end, entry_name(entries[at])) { ret true }
        at += 1usize
    }
    ret false
}

// The block this host wants: `NAME=VALUE` records one after another with a terminator each and
// one more at the end. Inheriting means the parent's records go in first, minus the ones the
// caller also sets -- nothing appends to an environment, so an overlay has to be built.
fn environment_block(a: *mem.Arena, entries: []const str, inherit: bool) -> ([]u16, err) {
    var nothing: []u16 = zero
    if entries.len >= SPAWN_LIST_MAX { ret (nothing, Failed) }
    var capacity = 2usize
    var counted = 0usize
    while counted < entries.len {
        // A UTF-16 encoding never needs more units than the UTF-8 one needs bytes.
        capacity += entries[counted].len + 1usize
        counted += 1usize
    }
    if inherit { capacity += MAX_ENVIRONMENT_UNITS }
    let (units, allocation_error) = mem.alloc[u16](a, capacity)
    if allocation_error != ok { ret (nothing, OutOfMemory) }
    var written = 0usize
    if inherit {
        let inherited = raw_environment_strings()
        if mem.address_of(inherited) == 0usize { ret (nothing, from_last_error()) }
        // `mem.view` names the region without reading it, and the walk below stops at the
        // double terminator -- so nothing past the block the host allocated is ever touched.
        var region: mem.Arena = zero
        region.base = inherited
        region.cap = MAX_ENVIRONMENT_UNITS * 2usize
        region.off = 0usize
        let bytes = mem.view(&region, 0usize, MAX_ENVIRONMENT_UNITS * 2usize)
        var at = 0usize
        while at + 1usize < bytes.len {
            if bytes[at] == 0u8 && bytes[at + 1usize] == 0u8 { break }
            var end = at
            while end + 1usize < bytes.len {
                if bytes[end] == 0u8 && bytes[end + 1usize] == 0u8 { break }
                end += 2usize
            }
            if !wide_record_overridden(bytes, at, end, entries) && written + (end - at) / 2usize + 1usize <= capacity {
                var offset = at
                while offset < end {
                    units[written] = u16(bytes[offset]) + u16(bytes[offset + 1usize]) * 256u16
                    written += 1usize
                    offset += 2usize
                }
                units[written] = 0u16
                written += 1usize
            }
            at = end + 2usize
        }
        let freed = raw_free_environment_strings(inherited)
    }
    var index = 0usize
    while index < entries.len {
        // `widen` already answers what the encoding is; its result is terminated, and the
        // terminator is where the copy stops.
        let (entry, entry_error) = widen(a, entries[index])
        if entry_error != ok { ret (nothing, entry_error) }
        var at = 0usize
        while at < entry.len && entry[at] != 0u16 {
            units[written] = entry[at]
            written += 1usize
            at += 1usize
        }
        units[written] = 0u16
        written += 1usize
        index += 1usize
    }
    // An empty block is still two terminators: a child with no environment at all is not the
    // same request as a child with the parent's.
    units[written] = 0u16
    written += 1usize
    ret (units[0usize..written], ok)
}

type StartResult = struct { group: ProcGroup, child: Proc }

// One place for both spawns: `grouped` decides whether a job is made and whether the child is
// held suspended long enough to be put in it.
// Every handle the child is to receive, marked so that `CreateProcess` passes it on: the three
// standard streams the caller set, and whatever `inherit` names besides. A zero stream is the
// parent's own and already inheritable.
fn make_inheritable(stdio: Stdio) -> err {
    if stdio.stdin.raw != 0usize && raw_set_handle_information(stdio.stdin.raw, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT) == 0i32 { ret from_last_error() }
    if stdio.stdout.raw != 0usize && raw_set_handle_information(stdio.stdout.raw, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT) == 0i32 { ret from_last_error() }
    if stdio.stderr.raw != 0usize && raw_set_handle_information(stdio.stderr.raw, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT) == 0i32 { ret from_last_error() }
    var at = 0usize
    while at < stdio.inherit.len {
        if raw_set_handle_information(stdio.inherit[at].raw, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT) == 0i32 { ret from_last_error() }
        at += 1usize
    }
    ret ok
}

fn start_process(a: *mem.Arena, options: SpawnOptions, grouped: bool) -> (StartResult, err) {
    var result: StartResult = zero
    let (line, line_error) = command_line(a, options.argv)
    if line_error != ok { ret (result, line_error) }
    let (wide_line, wide_line_error) = widen(a, line)
    if wide_line_error != ok { ret (result, wide_line_error) }

    var flags = 0u32
    var environment = 0usize
    // Inheriting with nothing added is the parent's own block, which is what a null pointer
    // already asks for -- so that case is not copied at all.
    if !options.inherit_env || options.env.len != 0usize {
        let (block, block_error) = environment_block(a, options.env, options.inherit_env)
        if block_error != ok { ret (result, block_error) }
        environment = mem.address_of(&block[0usize])
        flags = flags | CREATE_UNICODE_ENVIRONMENT
    }
    var directory = 0usize
    if options.cwd.len != 0usize {
        let (wide_directory, directory_error) = widen(a, options.cwd)
        if directory_error != ok { ret (result, directory_error) }
        directory = mem.address_of(&wide_directory[0usize])
    }

    var job = 0usize
    if grouped {
        job = raw_create_job(0usize, 0usize)
        if job == 0usize { ret (result, from_last_error()) }
        flags = flags | CREATE_SUSPENDED
    }

    var startup: StartupInfo = zero
    startup.size = 104u32
    startup.flags = STARTF_USESTDHANDLES
    // A stream the caller left unset is this process's own, because the alternative -- a child
    // holding nothing where its output should be -- is not what leaving a field alone means.
    startup.standard_input = options.stdio.stdin.raw
    if startup.standard_input == 0usize { startup.standard_input = raw_std_handle(STD_INPUT) }
    startup.standard_output = options.stdio.stdout.raw
    if startup.standard_output == 0usize { startup.standard_output = raw_std_handle(STD_OUTPUT) }
    startup.standard_error = options.stdio.stderr.raw
    if startup.standard_error == 0usize { startup.standard_error = raw_std_handle(STD_ERROR) }
    // A handle reaches the child only if it is marked inheritable, and a caller's handles
    // generally are not: `pipe` makes its ends the opposite on purpose, so that a pipe never
    // leaks into an unrelated child. The marking is done here, at the one moment the caller has
    // said which child should have them -- which is what the `spawn` intrinsic has always done
    // and this path had not, so a pipe handed to it arrived in the child as nothing.
    let inherit_error = make_inheritable(options.stdio)
    if inherit_error != ok {
        if job != 0usize { let unused_job = raw_close_handle(job) }
        ret (result, inherit_error)
    }
    var information: ProcessInformation = zero
    // Handles are inherited, which is what makes the three above reach the child at all.
    if raw_create_process(0usize, &wide_line[0usize], 0usize, 0usize, 1i32, flags, environment, directory, &startup, &information) == 0i32 {
        let start_error = from_last_error()
        if job != 0usize { let unused_job = raw_close_handle(job) }
        ret (result, start_error)
    }
    if grouped {
        if raw_assign_job(job, information.process) == 0i32 {
            // The child is still suspended and now belongs to nothing, so it is ended rather
            // than resumed: a caller that asked for containment does not get a loose process.
            let assign_error = from_last_error()
            let unused_kill = raw_terminate_process(information.process, KILL_EXIT_CODE)
            let unused_thread = raw_close_handle(information.thread)
            let unused_process = raw_close_handle(information.process)
            let unused_job = raw_close_handle(job)
            ret (result, assign_error)
        }
        let resumed = raw_resume_thread(information.thread)
    }
    let closed_thread = raw_close_handle(information.thread)
    result.group.raw = job
    result.child.raw = information.process
    ret (result, ok)
}

fn spawn_with_options(a: *mem.Arena, options: SpawnOptions) -> (Proc, err) {
    var child: Proc = zero
    let (result, start_error) = start_process(a, options, false)
    if start_error != ok { ret (child, start_error) }
    ret (result.child, ok)
}

// Containment is what the host gives and no more: a job holds a process and everything it
// starts, which is why the fence calls this containment rather than a sandbox.
fn proc_group_spawn(a: *mem.Arena, options: SpawnOptions) -> (ProcGroup, Proc, err) {
    var group: ProcGroup = zero
    var child: Proc = zero
    let (result, start_error) = start_process(a, options, true)
    if start_error != ok { ret (group, child, start_error) }
    ret (result.group, result.child, ok)
}

// Everything in the job at once. `force` has nothing to choose between here: this host has no
// signal to ask politely with, so both are the same end.
fn proc_group_terminate(group: ProcGroup, force: bool) -> err {
    if raw_terminate_job(group.raw, KILL_EXIT_CODE) == 0i32 { ret from_last_error() }
    ret ok
}

// The job handle goes; what is in it does not, because nothing asked for that. A job that should
// end with its owner needs a limit set on it, which is not in the fence.
fn proc_group_close(group: own ProcGroup) -> err {
    if raw_close_handle(group.raw) == 0i32 { ret from_last_error_cleanup() }
    ret ok
}

type FileLock = resource(file_unlock) struct { raw: usize }

// The whole file, however long it is: offset zero and a length of every byte there could be.
// Locking a range is not in the fence, so there is nothing for a caller to get wrong here.
fn lock_whole(file: usize, flags: u32) -> i32 {
    var region: Overlapped = zero
    ret raw_lock_file(file, flags, 0u32, 4294967295u32, 4294967295u32, &region)
}

// Unlike the other host these locks are mandatory: a reader that never asked is refused by the
// system rather than merely being impolite. The fence allows a host to guarantee more than
// cooperation, and this is the one that does.
fn file_lock(file: File, exclusive: bool, timeout_ns: i64) -> (FileLock, err) {
    var lock: FileLock = zero
    var flags = 0u32
    if exclusive { flags = LOCKFILE_EXCLUSIVE_LOCK }
    // A negative timeout waits, which the host does natively.
    if timeout_ns < 0i64 {
        if lock_whole(file.raw, flags) == 0i32 { ret (lock, from_last_error()) }
        lock.raw = file.raw
        ret (lock, ok)
    }
    var remaining = timeout_ns
    while true {
        if lock_whole(file.raw, flags | LOCKFILE_FAIL_IMMEDIATELY) != 0i32 {
            lock.raw = file.raw
            ret (lock, ok)
        }
        let code = raw_last_error()
        // Anything but "someone else holds it" is the caller's answer rather than another try.
        if code != ERROR_LOCK_VIOLATION { ret (lock, from_last_error()) }
        if remaining <= 0i64 {
            // Zero asked for one attempt, which is `WouldBlock`; a deadline that ran out is a
            // `Timeout`. Two different questions deserve two different answers.
            if timeout_ns == 0i64 { ret (lock, WouldBlock) }
            ret (lock, Timeout)
        }
        var slice = i64(LOCK_POLL_MS) * 1000000i64
        if remaining < slice { slice = remaining }
        raw_sleep(u32(slice / 1000000i64))
        remaining = remaining - slice
    }
    ret (lock, Failed)
}

fn file_unlock(lock: own FileLock) -> err {
    var region: Overlapped = zero
    if raw_unlock_file(lock.raw, 0u32, 4294967295u32, 4294967295u32, &region) == 0i32 { ret from_last_error_cleanup() }
    ret ok
}

// Asked rather than assumed. This host is not tied to one architecture by anything else in
// this file, so the page size is read from it.
fn page_size() -> usize {
    var info: SystemInfo = zero
    raw_system_info(&info)
    if info.page_size == 0u32 { ret 4096usize }
    ret usize(info.page_size)
}

// Both ends at once. The handles are not inheritable: a pipe that leaked into an unrelated
// child would keep its write end open and the reader would never see the end of it.
fn pipe() -> (File, File, err) {
    var reading: File = zero
    var writing: File = zero
    var read_handle = 0usize
    var write_handle = 0usize
    if raw_create_pipe(&read_handle, &write_handle, 0usize, 0u32) == 0i32 {
        ret (reading, writing, from_last_error())
    }
    reading.raw = read_handle
    writing.raw = write_handle
    ret (reading, writing, ok)
}

// A second identity for the same open file (D349): the OS's duplication, owed its own
// close; copying the bits of `f` would not be. Same access, not inheritable.
fn dup(f: File) -> (File, err) {
    var second: File = zero
    var handle = 0usize
    let process = raw_current_process()
    if raw_duplicate_handle(process, f.raw, process, &handle, 0u32, 0i32, DUPLICATE_SAME_ACCESS) == 0i32 { ret (second, from_last_error()) }
    second.raw = handle
    ret (second, ok)
}

const DUPLICATE_SAME_ACCESS: u32 = 2u32

// `PROCESS_MEMORY_COUNTERS`: the size first, then a page-fault count, then eight sizes of
// which the peak working set is the first. The layout is the ABI.
type MemoryCounters = struct {
    size: u32,
    page_faults: u32,
    peak_working_set: usize,
    working_set: usize,
    quota_peak_paged: usize,
    quota_paged: usize,
    quota_peak_nonpaged: usize,
    quota_nonpaged: usize,
    pagefile: usize,
    peak_pagefile: usize,
}

const WAIT_OBJECT_0: u32 = 0u32
const WAIT_INFINITE: u32 = 4294967295u32

fn peak_of(process: usize) -> (usize, err) {
    var counters: MemoryCounters = zero
    counters.size = 72u32
    if raw_process_memory_info(process, &counters, 72u32) == 0i32 { ret (0usize, from_last_error()) }
    ret (counters.peak_working_set, ok)
}

// The peak working set of this process so far, which at the end of a run is its peak.
fn peak_memory() -> (usize, err) {
    let (peak, peak_error) = peak_of(raw_current_process())
    ret (peak, peak_error)
}

// `wait`, and what the child's peak was: the handle is closed by the wait, so the peak is
// read in the same call, between the exit and the close (D311).
@unsafe
fn wait_usage(p: own Proc) -> (ProcUsage, err) {
    var usage: ProcUsage = zero
    usage.exit_code = -1i32
    if raw_wait_for_single_object(p.raw, WAIT_INFINITE) != WAIT_OBJECT_0 { ret (usage, from_last_error_cleanup()) }
    var code = 0u32
    if raw_exit_code_process(p.raw, &code) == 0i32 { ret (usage, from_last_error_cleanup()) }
    let (peak, peak_error) = peak_of(p.raw)
    let unused_close = raw_close_handle(p.raw)
    if peak_error != ok { ret (usage, peak_error) }
    usage.exit_code = i32(code)
    usage.peak_memory = peak
    ret (usage, ok)
}

// Not a request: this host has no signal to send, so the process is ended and told what its
// exit code is.
fn kill(p: Proc) -> err {
    if raw_terminate_process(p.raw, KILL_EXIT_CODE) == 0i32 { ret from_last_error() }
    ret ok
}

// The other half of `reserve`. `MEM_RELEASE` takes the whole reservation and refuses a size,
// so the length the caller gave is not passed on -- which is the one place this and the other
// host disagree about what a release is.
fn release(p: *u8, n: usize) -> err {
    if raw_virtual_free(p, 0usize, MEM_RELEASE) == 0i32 { ret from_last_error() }
    ret ok
}

// Winsock insists on being started before anything else touches it, and there is nowhere to
// remember that it has been: D109 is why this file keeps no ambient state to hold a flag.
// The call is reference counted, so asking again is cheap and asking once per socket is
// correct.
// `FORMAT_MESSAGE_FROM_SYSTEM` with inserts ignored: a system message may name arguments this
// has none of, and asking for them without supplying any is how that call is made to fail.
const FORMAT_MESSAGE_FROM_SYSTEM: u32 = 4096u32
const FORMAT_MESSAGE_IGNORE_INSERTS: u32 = 512u32

// ponytail: one buffer, no growing. A system message longer than this is truncated rather than
// retried, which for a diagnostic is the right trade.
const MESSAGE_UNITS: usize = 1024usize

// The message for a code, copied into the caller's arena. `detail` carries the code, so this asks
// for no ambient state and is exact whatever the last failing call was -- which is why it is
// written while `last_error_detail` is not.
fn error_message(a: *mem.Arena, detail: ErrorDetail) -> (str, err) {
    let (units, units_error) = mem.alloc[u16](a, MESSAGE_UNITS)
    if units_error != ok { ret ("", OutOfMemory) }
    touch(mem.cast[*const u8](&units[0usize]), MESSAGE_UNITS * 2usize)
    let written = raw_format_message(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, 0usize, u32(detail.native_code), 0u32, &units[0usize], u32(MESSAGE_UNITS), 0usize)
    if written == 0u32 { ret ("", NotFound) }
    // The system ends its messages with a period and a newline, which belongs to the display and
    // not to the message: a caller that wants one can add it.
    var count = usize(written)
    while count > 0usize {
        let last = units[count - 1usize]
        if last != 13u16 && last != 10u16 { break }
        count = count - 1usize
    }
    if count == 0usize { ret ("", NotFound) }
    // A UTF-16 unit never becomes more than three UTF-8 bytes.
    let (bytes, bytes_error) = mem.alloc[u8](a, count * 3usize)
    if bytes_error != ok { ret ("", OutOfMemory) }
    touch(&bytes[0usize], count * 3usize)
    let converted = raw_narrow(CP_UTF8, 0u32, &units[0usize], i32(count), &bytes[0usize], i32(count * 3usize), 0usize, 0usize)
    if converted <= 0i32 { ret ("", Failed) }
    ret (bytes[0usize..usize(converted)], ok)
}

// A NUL-terminated byte copy, which `GetProcAddress` wants where every other call here wants
// units. `widen` is the other direction and cannot serve.
fn narrow_c_string(a: *mem.Arena, text: str) -> ([]u8, err) {
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
// takes `kernel32` and `libc.so.6` alike and adds nothing to either, so neither does this.
fn dlopen(a: *mem.Arena, name: str) -> (Lib, err) {
    var library: Lib = zero
    if name.len == 0usize { ret (library, NotFound) }
    let (wide_name, wide_name_error) = widen(a, name)
    if wide_name_error != ok { ret (library, wide_name_error) }
    let handle = raw_load_library(&wide_name[0usize])
    if handle == 0usize { ret (library, from_last_error()) }
    library.raw = handle
    ret (library, ok)
}

// The address of a symbol, which is all a library can answer with. Turning it into something
// callable is `dlsym`'s, and only the compiler can do that.
fn dl_lookup(a: *mem.Arena, l: Lib, sym: str) -> (usize, err) {
    if sym.len == 0usize { ret (0usize, NotFound) }
    let (bytes, bytes_error) = narrow_c_string(a, sym)
    if bytes_error != ok { ret (0usize, bytes_error) }
    let address = raw_proc_address(l.raw, &bytes[0usize])
    if address == 0usize { ret (0usize, from_last_error()) }
    ret (address, ok)
}

fn dlclose(l: own Lib) -> err {
    if raw_free_library(l.raw) == 0i32 { ret from_last_error_cleanup() }
    ret ok
}

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

fn socket_close(s: own Socket) -> err {
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

// The address a socket is actually bound to. With port zero the host chose one and this is
// the only way to learn it; with a port the caller named it reports that one back.
fn socket_local_address(s: Socket) -> (SocketAddress, err) {
    var address: SocketAddress = zero
    var raw: RawAddress = zero
    var length = i32(RAW_IP6_SIZE)
    if raw_socket_local(s.raw, &raw, &length) != 0i32 { ret (address, from_socket_error()) }
    ret (decode_address(raw), ok)
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
    touch(&dst[0usize], dst.len)
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
    touch(&dst[0usize], dst.len)
    let taken = raw_socket_receive_from(s.raw, &dst[0usize], i32(dst.len), 0i32, &raw, &length)
    if taken < 0i32 { ret (0usize, peer, from_socket_error()) }
    ret (usize(taken), decode_address(raw), ok)
}

fn shutdown_value(how: SocketShutdown) -> i32 {
    if how == .Write { ret 1i32 }
    if how == .Both { ret 2i32 }
    ret 0i32
}

// This host has a resolver and it is the whole of the answer: a literal, the hosts file, the
// cache and DNS itself are all behind one call, which is why this half is short and the other
// one is not.
//
// The service is not named -- a port is a number the caller already has, and asking this to
// look one up would mean a second string to build and a table to disagree with.
fn socket_resolve(a: *mem.Arena, host: str, port: u16, family: SocketFamily) -> ([]SocketAddress, err) {
    var nothing: []SocketAddress = zero
    if host.len == 0usize { ret (nothing, NotFound) }
    var data: WsaData = zero
    if raw_wsa_startup(WSA_VERSION, &data) != 0i32 { ret (nothing, Failed) }
    let (wide_host, wide_host_error) = widen(a, host)
    if wide_host_error != ok { ret (nothing, wide_host_error) }
    var hints: AddressInfo = zero
    hints.family = i32(family_value(family))
    var head: AddressInfoHead = zero
    let code = raw_address_info(&wide_host[0usize], 0usize, &hints, &head)
    if code != 0i32 {
        // WSAHOST_NOT_FOUND and WSANO_DATA: the name is not there, or is there with nothing of
        // the family that was asked for. Both are the same answer to a caller.
        if code == 11001i32 { ret (nothing, NotFound) }
        if code == 11004i32 { ret (nothing, NotFound) }
        // WSATRY_AGAIN: the resolver could not reach anyone, which is not the name's fault.
        if code == 11002i32 { ret (nothing, Timeout) }
        ret (nothing, Failed)
    }
    let (results, results_error) = mem.alloc[SocketAddress](a, RESOLVE_ADDRESS_MAX)
    if results_error != ok {
        raw_free_address_info(head.node)
        ret (nothing, OutOfMemory)
    }
    var found = 0usize
    var entry = mem.cast[*AddressInfo](head.node)
    while mem.address_of(entry) != 0usize && found < RESOLVE_ADDRESS_MAX {
        if entry.family == hints.family && entry.address_len != 0usize {
            // The sockaddr is behind a pointer and `mem.view` is the only way to name it as
            // bytes, so an `Arena` is built over it -- not to allocate out of, but to describe
            // the region, the same as a file mapping.
            var region: mem.Arena = zero
            region.base = entry.address
            region.cap = entry.address_len
            region.off = 0usize
            let bytes = mem.view(&region, 0usize, entry.address_len)
            var raw: RawAddress = zero
            var at = 0usize
            while at < bytes.len && at < 28usize {
                raw.bytes[at] = bytes[at]
                at += 1usize
            }
            results[found] = decode_address(raw)
            // The port comes from the caller, not from a service lookup that was never asked
            // for, so whatever the resolver left in the sockaddr is overwritten.
            results[found].port = port
            found += 1usize
        }
        entry = mem.cast[*AddressInfo](entry.next)
    }
    raw_free_address_info(head.node)
    if found == 0usize { ret (nothing, NotFound) }
    ret (results[0usize..found], ok)
}

fn socket_shutdown(s: Socket, how: SocketShutdown) -> err {
    if raw_socket_shutdown(s.raw, shutdown_value(how)) != 0i32 { ret from_socket_error() }
    ret ok
}

// The handle the host started this process with. `stdout` and `stderr` are intrinsics from
// before `e.os` was written as source; this one never was, so it is written here rather than
// added to the runtime on two platforms.
fn stdin() -> File {
    var file: File = zero
    file.raw = raw_std_handle(STD_INPUT)
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

fn to_filetime(value: i64) -> FileTime {
    var stamp: FileTime = zero
    let ticks = u64.trunc(value) / 100u64 + FILETIME_UNIX_EPOCH
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
    touch(&buffer[0usize], buffer.len)
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
    touch(mem.cast[*const u8](&holder[0usize]), usize(MAXIMUM_REPARSE_DATA))
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
    touch(&bytes[0usize], units * 3usize)
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
        touch(mem.cast[*const u8](&units[0usize]), (capacity + 1usize) * 2usize)
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
            touch(&bytes[0usize], count * 3usize)
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
        touch(mem.cast[*const u8](&units[0usize]), capacity * 2usize)
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
            touch(&bytes[0usize], count * 3usize)
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
        touch(mem.cast[*const u8](&units[0usize]), capacity * 2usize)
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
            touch(&bytes[0usize], count * 3usize)
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
        touch(mem.cast[*const u8](&units[0usize]), capacity * 2usize)
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
            touch(&bytes[0usize], count * 3usize)
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
