// `e.os` on WebAssembly (C180, D5213). `project.select_source` picks this file for the `wasi`
// os, the way it picks os.neperos.e for NeperOS; one module is one file, so the type block is a
// copy of the one in os.e and the other variants rather than something shared.
//
// There is no runtime in assembly here. Lowering turns every seeded `e.os` and `e.mem` primitive
// into a call to a `neper_*` symbol, and the WebAssembly back end binds each such call to the
// function of that name in this module (src/wasm.e): `neper_os_write`, `neper_mem_alloc`,
// `neper_trap` and the rest are ordinary Neper over the WASI preview 1 imports below. The calling
// convention is the assembly runtimes' (runtime_elf_a64.s): an aggregate -- a `str`, a slice, a
// struct -- is passed by its address, an aggregate result comes back through a slot passed first,
// and a pair comes back as two values. Every WebAssembly value of a Neper function is an `i64`;
// the imports take `u32` for what WASI makes `i32`, and an address is written `u32(address)`.
//
// What WASI cannot do answers `Unsupported`, as runtime_neperos_a64.s does: threads and
// processes. `reserve` hands out address space above the root arena (D5640). The accelerator entries answer zero, "nothing done", so the library
// takes its portable path. The errors (NotFound, Denied, ...) are seeded by the compiler and must
// not be declared again here.

use e.mem
use e.algo.hash as algo_hash

// The separator this target's paths are written with (e.path asks the host nothing, so a portable
// module learns the convention only from the per-target os file). WASI uses '/'.
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
    if read_error != ok { *detail = last_error_detail("read", "") }
    ret (count, read_error)
}

// Write `buffer`, recording a detail on failure. A wrapper over `write`.
fn write_detail(f: File, buffer: []const u8, detail: *ErrorDetail) -> (usize, err) {
    let (count, write_error) = write(f, buffer)
    if write_error != ok { *detail = last_error_detail("write", "") }
    ret (count, write_error)
}


// ---- WASI preview 1 and the "wasm" instructions ---------------------------------------------------
// `u32` is what WASI makes `i32`; a pointer is written `u32(address)`. The pseudo-library "wasm" is
// not imported: the back end writes those four as the instructions themselves (src/wasm.e).

@import("wasi_snapshot_preview1", "fd_write")
extern fn wasi_fd_write(fd: u32, iovs: u32, iovs_len: u32, written: u32) -> u32

@import("wasi_snapshot_preview1", "fd_read")
extern fn wasi_fd_read(fd: u32, iovs: u32, iovs_len: u32, read_count: u32) -> u32

@import("wasi_snapshot_preview1", "fd_close")
extern fn wasi_fd_close(fd: u32) -> u32

@import("wasi_snapshot_preview1", "fd_seek")
extern fn wasi_fd_seek(fd: u32, offset: i64, whence: u32, position: u32) -> u32

@import("wasi_snapshot_preview1", "args_sizes_get")
extern fn wasi_args_sizes_get(count: u32, buffer_size: u32) -> u32

@import("wasi_snapshot_preview1", "args_get")
extern fn wasi_args_get(pointers: u32, buffer: u32) -> u32

@import("wasi_snapshot_preview1", "clock_time_get")
extern fn wasi_clock_time_get(id: u32, precision: u64, time: u32) -> u32

@import("wasi_snapshot_preview1", "poll_oneoff")
extern fn wasi_poll_oneoff(subscriptions: u32, events: u32, count: u32, taken: u32) -> u32

@import("wasi_snapshot_preview1", "proc_exit")
extern fn wasi_proc_exit(code: u32)

@import("wasi_snapshot_preview1", "fd_sync")
extern fn wasi_fd_sync(fd: u32) -> u32

@import("wasi_snapshot_preview1", "fd_readdir")
extern fn wasi_fd_readdir(fd: u32, buffer: u32, buffer_len: u32, cookie: u64, used: u32) -> u32

@import("wasi_snapshot_preview1", "fd_prestat_get")
extern fn wasi_fd_prestat_get(fd: u32, buffer: u32) -> u32

@import("wasi_snapshot_preview1", "fd_prestat_dir_name")
extern fn wasi_fd_prestat_dir_name(fd: u32, buffer: u32, buffer_len: u32) -> u32

@import("wasi_snapshot_preview1", "path_open")
extern fn wasi_path_open(fd: u32, lookup: u32, path: u32, path_len: u32, open_flags: u32, rights_base: u64, rights_inheriting: u64, fd_flags: u32, opened: u32) -> u32

@import("wasi_snapshot_preview1", "path_filestat_get")
extern fn wasi_path_filestat_get(fd: u32, lookup: u32, path: u32, path_len: u32, buffer: u32) -> u32

@import("wasi_snapshot_preview1", "path_filestat_set_times")
extern fn wasi_path_filestat_set_times(fd: u32, lookup: u32, path: u32, path_len: u32, accessed: u64, modified: u64, set: u32) -> u32

@import("wasi_snapshot_preview1", "path_create_directory")
extern fn wasi_path_create_directory(fd: u32, path: u32, path_len: u32) -> u32

@import("wasi_snapshot_preview1", "path_remove_directory")
extern fn wasi_path_remove_directory(fd: u32, path: u32, path_len: u32) -> u32

@import("wasi_snapshot_preview1", "path_unlink_file")
extern fn wasi_path_unlink_file(fd: u32, path: u32, path_len: u32) -> u32

@import("wasi_snapshot_preview1", "path_rename")
extern fn wasi_path_rename(fd: u32, path: u32, path_len: u32, new_fd: u32, new_path: u32, new_path_len: u32) -> u32

@import("wasi_snapshot_preview1", "path_readlink")
extern fn wasi_path_readlink(fd: u32, path: u32, path_len: u32, buffer: u32, buffer_len: u32, used: u32) -> u32

@import("wasi_snapshot_preview1", "path_symlink")
extern fn wasi_path_symlink(link_text: u32, link_text_len: u32, fd: u32, path: u32, path_len: u32) -> u32

@import("wasi_snapshot_preview1", "environ_sizes_get")
extern fn wasi_environ_sizes_get(count: u32, buffer_size: u32) -> u32

@import("wasi_snapshot_preview1", "environ_get")
extern fn wasi_environ_get(pointers: u32, buffer: u32) -> u32

@import("wasi_snapshot_preview1", "random_get")
extern fn wasi_random_get(buffer: u32, buffer_len: u32) -> u32

@import("wasm", "memory.grow")
extern fn wasm_memory_grow(pages: u32) -> u32

@import("wasm", "memory.size")
extern fn wasm_memory_size() -> u32

@import("wasm", "memory.fill")
extern fn wasm_memory_fill(destination: u32, value: u32, count: u32)

@import("wasm", "memory.copy")
extern fn wasm_memory_copy(destination: u32, source: u32, count: u32)

// Threads (D5672): `threads` is 1 in a `--threads` module and 0 in a plain one, which then never
// waits; the atomics work on either memory.
@import("wasm", "threads")
extern fn wasm_threads() -> u32

@import("wasm", "thread.id")
extern fn wasm_thread_id() -> u32

@import("wasm", "thread.spawn")
extern fn wasm_thread_spawn(record: u32) -> i32

@import("wasm", "memory.atomic.wait32")
extern fn wasm_wait32(address: u32, expected: u32, timeout_ns: i64) -> u32

@import("wasm", "memory.atomic.notify")
extern fn wasm_notify(address: u32, count: u32) -> u32

@import("wasm", "i32.atomic.rmw.cmpxchg")
extern fn wasm_cas32(address: u32, expected: u32, replacement: u32) -> u32

@import("wasm", "i32.atomic.load")
extern fn wasm_load32(address: u32) -> u32

@import("wasm", "i32.atomic.store")
extern fn wasm_store32(address: u32, value: u32)

// The sockets, the resolver and the poller come from the host (D5675): one more import module, each
// function answering a WASI errno and writing its outputs through the pointers it is given.
@import("neper_host", "sock_open")
extern fn host_sock_open(family: u32, kind: u32, made: u32) -> u32

@import("neper_host", "sock_set_nonblocking")
extern fn host_sock_set_nonblocking(handle: u32, enabled: u32) -> u32

@import("neper_host", "sock_bind")
extern fn host_sock_bind(handle: u32, address: u32) -> u32

@import("neper_host", "sock_local_address")
extern fn host_sock_local_address(handle: u32, address: u32) -> u32

@import("neper_host", "sock_listen")
extern fn host_sock_listen(handle: u32, backlog: u32) -> u32

@import("neper_host", "sock_accept")
extern fn host_sock_accept(handle: u32, made: u32, address: u32) -> u32

@import("neper_host", "sock_connect")
extern fn host_sock_connect(handle: u32, address: u32) -> u32

@import("neper_host", "sock_send")
extern fn host_sock_send(handle: u32, bytes: u32, length: u32, sent: u32) -> u32

@import("neper_host", "sock_recv")
extern fn host_sock_recv(handle: u32, bytes: u32, length: u32, taken: u32) -> u32

@import("neper_host", "sock_send_to")
extern fn host_sock_send_to(handle: u32, address: u32, bytes: u32, length: u32, sent: u32) -> u32

@import("neper_host", "sock_recv_from")
extern fn host_sock_recv_from(handle: u32, bytes: u32, length: u32, taken: u32, address: u32) -> u32

@import("neper_host", "sock_shutdown")
extern fn host_sock_shutdown(handle: u32, how: u32) -> u32

@import("neper_host", "sock_close")
extern fn host_sock_close(handle: u32) -> u32

@import("neper_host", "resolve")
extern fn host_resolve(host: u32, host_length: u32, port: u32, family: u32, out: u32, capacity: u32, found: u32) -> u32

@import("neper_host", "poll_open")
extern fn host_poll_open(made: u32) -> u32

@import("neper_host", "poll_ctl")
extern fn host_poll_ctl(poller: u32, operation: u32, handle: u32, token: i64, interest: u32) -> u32

@import("neper_host", "poll_wait")
extern fn host_poll_wait(poller: u32, events: u32, capacity: u32, timeout_ns: i64, count: u32) -> u32

@import("neper_host", "poll_wake")
extern fn host_poll_wake(poller: u32) -> u32

@import("neper_host", "poll_close")
extern fn host_poll_close(poller: u32) -> u32

@import("wasi_snapshot_preview1", "fd_pread")
extern fn wasi_fd_pread(fd: u32, iovs: u32, iovs_len: u32, offset: u64, read_count: u32) -> u32

// ---- the results the convention returns through a slot ---------------------------------------------

type AllocResult = struct { data: []u8, failure: err }
type ArgsResult = struct { items: []str, failure: err }
type OpenResult = struct { file: File, failure: err }
type SpawnResult = struct { proc: Proc, failure: err }
type ThreadResult = struct { thread: Thread, failure: err }
type ReaddirResult = struct { entries: []DirEntry, failure: err }

// ---- the arena -------------------------------------------------------------------------------------

// Room up to `end`, by growing the memory: the root arena and the reservations above it (D5640) are
// what lies past the shadow stack, so growing is all that making room takes.
// Two threads growing at once may grow more than needed, never less: a grow that fails is
// looked at again, because the other thread's may have covered `end` (D5673).
fn rt_grow(end: usize) -> bool {
    let have = usize(wasm_memory_size()) * 65536usize
    if end <= have { ret true }
    let need = (end - have + 65535usize) / 65536usize
    if need > 65535usize { ret false }
    let grown = wasm_memory_grow(u32(need))
    if grown != 4294967295u32 { ret true }
    ret end <= usize(wasm_memory_size()) * 65536usize
}

// mem.alloc: the result {data, len, err} at `result`, `count` elements of `size` bytes aligned to
// `align` from `arena`.
fn neper_mem_alloc(result: *AllocResult, arena: *mem.Arena, count: usize, size: usize, align: usize) {
    var empty: []u8 = zero
    result.data = empty
    result.failure = mem.Exhausted
    if align == 0usize || (align & (align - 1usize)) != 0usize { ret }
    var total = 0usize
    if size != 0usize {
        if count > 18446744073709551615usize / size { ret }
        total = count * size
    }
    if arena.off > 18446744073709551615usize - (align - 1usize) { ret }
    let aligned = (arena.off + (align - 1usize)) & ~(align - 1usize)
    if aligned > arena.cap || total > arena.cap - aligned { ret }
    let base = mem.address_of(arena.base)
    if base == 0usize { ret }
    if !rt_grow(base + aligned + total) { ret }
    arena.off = aligned + total
    result.data = mem.view(arena, aligned, count)
    result.failure = ok
}

// Section 11's debug fill (D217): the allocation, then every byte of it 0xCD.
fn neper_mem_alloc_fill(result: *AllocResult, arena: *mem.Arena, count: usize, size: usize, align: usize) {
    neper_mem_alloc(result, arena, count, size, align)
    if result.failure != ok { ret }
    let total = count * size
    if total != 0usize { wasm_memory_fill(u32(mem.address_of(&result.data[0usize])), 205u32, u32(total)) }
}

fn neper_mem_mark(arena: *mem.Arena) -> usize { ret arena.off }

fn neper_mem_reset(arena: *mem.Arena, to: usize) { arena.off = to }

// The other debug fill (D217): what the reset gives back is 0xDD before the offset moves.
fn neper_mem_reset_fill(arena: *mem.Arena, to: usize) {
    if to < arena.off { wasm_memory_fill(u32(mem.address_of(arena.base) + to), 221u32, u32(arena.off - to)) }
    arena.off = to
}

fn neper_mem_stats(out: *mem.Stats, arena: *mem.Arena) {
    out.used = arena.off
    out.capacity = arena.cap
}

// The `length` bytes at `base`, as a slice: a one-use arena over them is the way the language says it.
fn rt_bytes(base: *u8, length: usize) -> []u8 {
    let window = mem.Arena { base: base, cap: length, off: 0usize }
    ret mem.view(&window, 0usize, length)
}

// Spec section 9 rule 4: xxHash64 seed 0 over the canonical bytes.
fn neper_hash_bytes(data: *u8, length: usize) -> u64 {
    ret algo_hash.xxhash64(rt_bytes(data, length), 0u64)
}

// ---- standard error, the trap ------------------------------------------------------------------------

fn rt_stderr_bytes(text: []const u8) {
    if text.len == 0usize { ret }
    var iov: [2]u32 = zero
    var written: [1]u32 = zero
    iov[0usize] = u32(mem.address_of(&text[0usize]))
    iov[1usize] = u32(text.len)
    let status = wasi_fd_write(2u32, u32(mem.address_of(&iov[0usize])), 1u32, u32(mem.address_of(&written[0usize])))
}

fn rt_stderr_char(value: u8) {
    var one: [1]u8 = zero
    one[0usize] = value
    rt_stderr_bytes(one[0usize..1usize])
}

fn rt_stderr_number(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    if rest == 0usize {
        at = at - 1usize
        digits[at] = 48u8
    }
    while rest != 0usize {
        at = at - 1usize
        digits[at] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
    }
    rt_stderr_bytes(digits[at..20usize])
}

// Section 11's trap protocol on this target (src/wasm_code.e): `path:line:column`, then the
// message, an operand where each separator byte stands (0 unsigned, 1 signed), a newline, and
// exit status 134. There are no frames: WebAssembly cannot walk its own stack.
fn neper_trap(record_path: *str, site: usize, first: usize, second: usize, record_message: *str) {
    rt_stderr_bytes(*record_path)
    rt_stderr_char(58u8)
    rt_stderr_number(site >> 16usize)
    rt_stderr_char(58u8)
    rt_stderr_number(site & 65535usize)
    let message = *record_message
    var at = 0usize
    var shown = 0usize
    var more = true
    while more {
        var stop = at
        while stop < message.len && message[stop] >= 2u8 { stop = stop + 1usize }
        rt_stderr_bytes(message[at..stop])
        if stop >= message.len {
            more = false
        } else {
            var value = first
            if shown > 0usize { value = second }
            shown = shown + 1usize
            if message[stop] == 1u8 && (value >> 63usize) == 1usize {
                rt_stderr_char(45u8)
                value = 0usize -% value
            }
            rt_stderr_number(value)
            at = stop + 1usize
        }
    }
    rt_stderr_char(10u8)
    wasi_proc_exit(134u32)
}

// ---- the program's arguments, exit -------------------------------------------------------------------

// The arguments as the slice of strings `main` takes, copied into `arena`. `_start` calls this
// first, with the root arena, whose end is where reservations begin (D5640).
fn neper_start_args(out: *[]str, arena: *mem.Arena) {
    if rt_reserve_top == 0usize { rt_reserve_top = (mem.address_of(arena.base) + arena.cap + 65535usize) / 65536usize * 65536usize }
    if wasm_threads() == 1u32 { load_mounts() }
    var none: []str = zero
    *out = none
    var sizes: [2]u32 = zero
    if wasi_args_sizes_get(u32(mem.address_of(&sizes[0usize])), u32(mem.address_of(&sizes[1usize]))) != 0u32 { ret }
    let count = usize(sizes[0usize])
    let buffer_size = usize(sizes[1usize])
    let (pointers, pointers_error) = mem.alloc[u32](arena, count + 1usize)
    if pointers_error != ok { ret }
    let (storage, storage_error) = mem.alloc[u8](arena, buffer_size + 1usize)
    if storage_error != ok { ret }
    let (items, items_error) = mem.alloc[str](arena, count + 1usize)
    if items_error != ok { ret }
    let base = u32(mem.address_of(&storage[0usize]))
    if wasi_args_get(u32(mem.address_of(&pointers[0usize])), base) != 0u32 { ret }
    var at = 0usize
    while at < count {
        let start = usize(pointers[at] - base)
        var stop = start
        while stop < buffer_size && storage[stop] != 0u8 { stop = stop + 1usize }
        items[at] = storage[start..stop]
        at = at + 1usize
    }
    *out = items[0usize..count]
}

fn neper_os_args(result: *ArgsResult, arena: *mem.Arena) {
    neper_start_args(&result.items, arena)
    result.failure = ok
}

// exit_group's counterpart: the status is the low byte.
fn neper_os_exit(code: i32) {
    wasi_proc_exit(u32(code & 255i32))
}

// ---- files: the standard streams ---------------------------------------------------------------------

fn neper_os_stdout(out: *File) { out.raw = 1usize }

fn neper_os_stderr(out: *File) { out.raw = 2usize }

// os.write(file: *File, bytes: *str) -> (usize, err).
fn neper_os_write(f: *File, text: *str) -> (usize, err) {
    let content: []const u8 = *text
    var done = 0usize
    var iov: [2]u32 = zero
    var written: [1]u32 = zero
    while done < content.len {
        iov[0usize] = u32(mem.address_of(&content[done]))
        iov[1usize] = u32(content.len - done)
        written[0usize] = 0u32
        let status = wasi_fd_write(fd_of(f.raw), u32(mem.address_of(&iov[0usize])), 1u32, u32(mem.address_of(&written[0usize])))
        if status != 0u32 { ret (done, wasi_error(status)) }
        if written[0usize] == 0u32 { ret (done, Failed) }
        done = done + usize(written[0usize])
    }
    ret (done, ok)
}

// os.read(file: *File, bytes: *[]u8) -> (usize, err).
fn neper_os_read(f: *File, buffer: *[]u8) -> (usize, err) {
    let target_bytes = *buffer
    if target_bytes.len == 0usize { ret (0usize, ok) }
    var iov: [2]u32 = zero
    var taken: [1]u32 = zero
    iov[0usize] = u32(mem.address_of(&target_bytes[0usize]))
    iov[1usize] = u32(target_bytes.len)
    let status = wasi_fd_read(fd_of(f.raw), u32(mem.address_of(&iov[0usize])), 1u32, u32(mem.address_of(&taken[0usize])))
    if status != 0u32 { ret (0usize, wasi_error(status)) }
    ret (usize(taken[0usize]), ok)
}

fn neper_os_close(f: *File) -> err {
    if f.raw <= 2usize { ret ok }
    ret wasi_cleanup(wasi_fd_close(fd_of(f.raw)))
}

// os.seek(file: *File, offset, whence) -> (u64, err).
fn neper_os_seek(f: *File, offset: i64, whence: SeekWhence) -> (u64, err) {
    var position: [1]u64 = zero
    var origin = 0u32
    if whence == SeekWhence.Current { origin = 1u32 }
    if whence == SeekWhence.End { origin = 2u32 }
    let status = wasi_fd_seek(fd_of(f.raw), offset, origin, u32(mem.address_of(&position[0usize])))
    if status != 0u32 { ret (0u64, wasi_error(status)) }
    ret (position[0usize], ok)
}

// os.open(result, arena, path, flags): the file, or the reason it could not be opened.
fn neper_os_open(result: *OpenResult, arena: *mem.Arena, path: *str, flags: *OpenFlags) {
    let (file, open_error) = open_path(*path, *flags, false)
    if open_error != ok {
        result.file = File { raw: 0usize }
        result.failure = open_error
        ret
    }
    result.file = file
    result.failure = ok
}

// os.clock(kind) -> (i64, err): nanoseconds of the wall or monotonic clock.
fn neper_os_clock(kind: Clock) -> (i64, err) {
    var now: [1]u64 = zero
    var id = 0u32
    if kind == Clock.Monotonic { id = 1u32 }
    let status = wasi_clock_time_get(id, 1u64, u32(mem.address_of(&now[0usize])))
    if status != 0u32 { ret (0i64, wasi_error(status)) }
    if now[0usize] > 9223372036854775807u64 { ret (0i64, Failed) }
    ret (i64(now[0usize]), ok)
}

// ---- what WASI cannot do, and what a build answers "nothing done" ------------------------------------

fn neper_os_spawn(result: *SpawnResult, arena: *mem.Arena, argv: *[]const str, stdio: *Stdio) {
    result.proc = Proc { raw: 0usize }
    result.failure = Unsupported
}

fn neper_os_wait(p: *Proc) -> (i32, err) { ret (0i32, Unsupported) }

// ---- threads (D5673) ---------------------------------------------------------------------------------
// A plain module has one thread and no way to start another, so it answers what a refusing host
// gives. A `--threads` module starts each thread on a block of reserved memory that is its record
// and its shadow stack (little-endian): u32 state at 0 (1 running, 2 detached, 0 finished), u32
// tid at 4, u64 entry slot at 8, context at 16, stack top at 24, stack floor at 32, size at 40 and
// the free list's link at 48. `wasi_thread_start` (src/wasm_threads.e) reads it, calls the entry,
// then stores 0 over the state and wakes its joiners, its last touches of the block.
//
// `rt_lock` is Drepper's mutex (0 free, 1 held, 2 held and waited for) over the reservations and the
// free list of finished blocks. It is an element, not a scalar `var`: the checker refuses the
// address of a module-level scalar (D5713).
var rt_lock: [1]u32 = zero
var rt_free: [1]usize = zero

fn rt_acquire() {
    let lock = u32(mem.address_of(&rt_lock[0usize]))
    if wasm_cas32(lock, 0u32, 1u32) == 0u32 { ret }
    while true {
        let seen = wasm_load32(lock)
        if seen == 0u32 {
            if wasm_cas32(lock, 0u32, 2u32) == 0u32 { ret }
        } else if seen == 1u32 {
            let marked = wasm_cas32(lock, 1u32, 2u32)
        } else {
            let woken = wasm_wait32(lock, 2u32, 0i64 - 1i64)
        }
    }
}

fn rt_release() {
    let lock = u32(mem.address_of(&rt_lock[0usize]))
    if wasm_cas32(lock, 1u32, 0u32) == 1u32 { ret }
    wasm_store32(lock, 0u32)
    let woken = wasm_notify(lock, 1u32)
}

fn rt_load64(address: usize) -> usize {
    var word: [1]u64 = zero
    wasm_memory_copy(u32(mem.address_of(&word[0usize])), u32(address), 8u32)
    ret usize(word[0usize])
}

fn rt_store64(address: usize, value: usize) {
    var word: [1]u64 = zero
    word[0usize] = u64(value)
    wasm_memory_copy(u32(address), u32(mem.address_of(&word[0usize])), 8u32)
}

// A finished block of at least `size` bytes from the free list (first fit), else 0.
fn rt_block_take(size: usize) -> usize {
    rt_acquire()
    var previous = 0usize
    var block = rt_free[0usize]
    while block != 0usize {
        let next = rt_load64(block + 48usize)
        if rt_load64(block + 40usize) >= size {
            if previous == 0usize { rt_free[0usize] = next } else { rt_store64(previous + 48usize, next) }
            rt_release()
            ret block
        }
        previous = block
        block = next
    }
    rt_release()
    ret 0usize
}

fn rt_block_give(block: usize) {
    rt_acquire()
    rt_store64(block + 48usize, rt_free[0usize])
    rt_free[0usize] = block
    rt_release()
}

// os.thread_create(result, entry, context, stack): `entry` is the function's table slot (D5604).
fn neper_os_thread_create(result: *ThreadResult, entry: usize, context: usize, stack: usize) {
    result.thread = Thread { raw: 0usize }
    result.failure = Unsupported
    if wasm_threads() == 0u32 { ret }
    result.failure = Failed
    var room = stack
    if room < 65536usize { room = 65536usize }
    if room > MEMORY_END { ret }
    var size = (room + 64usize + 65535usize) / 65536usize * 65536usize
    var block = rt_block_take(size)
    if block != 0usize {
        size = rt_load64(block + 40usize)
    } else {
        let (start, reserve_error) = neper_os_reserve(size)
        if reserve_error != ok { ret }
        block = mem.address_of(start)
    }
    // Only a fresh block can fail to grow (a free one was grown before); its addresses are lost.
    if !rt_grow(block + size) { ret }
    var record: [7]u64 = zero
    record[0usize] = 1u64
    record[1usize] = u64(entry)
    record[2usize] = u64(context)
    record[3usize] = u64(block + size)
    record[4usize] = u64(block + 64usize)
    record[5usize] = u64(size)
    wasm_memory_copy(u32(block), u32(mem.address_of(&record[0usize])), 56u32)
    let tid = wasm_thread_spawn(u32(block))
    if tid <= 0i32 {
        rt_block_give(block)
        ret
    }
    wasm_store32(u32(block + 4usize), u32(tid))
    result.thread = Thread { raw: block }
    result.failure = ok
}

fn neper_os_thread_join(t: *Thread) -> err {
    if wasm_threads() == 0u32 { ret Unsupported }
    let block = t.raw
    if block == 0usize { ret Failed }
    let state = u32(block)
    var seen = wasm_load32(state)
    while seen != 0u32 {
        if seen == 2u32 { ret Failed }
        let woken = wasm_wait32(state, seen, 0i64 - 1i64)
        seen = wasm_load32(state)
    }
    t.raw = 0usize
    rt_block_give(block)
    ret ok
}

// A detached thread still running stores 0 over the 2 when it ends and its block is not
// reclaimed, as the native runtimes leave a detached thread's stack.
// ponytail: that block leaks; the host reporting finished detached blocks would reclaim it.
fn neper_os_thread_detach(t: *Thread) -> err {
    if wasm_threads() == 0u32 { ret Unsupported }
    let block = t.raw
    if block == 0usize { ret Failed }
    let old = wasm_cas32(u32(block), 1u32, 2u32)
    if old == 2u32 { ret Failed }
    t.raw = 0usize
    if old == 0u32 { rt_block_give(block) }
    ret ok
}

// Reservations (D5640): address space above the root arena, handed out upward in 64 KiB steps.
// Memory reaches a reservation when an allocation in it does (`rt_grow`), so `commit` only checks
// the range and a commit-on-touch host's pages cost nothing until used; the memory below the
// highest byte touched is the engine's commit. `release` gives the address back only for the
// latest reservation. The ceiling: 4 GiB of address for the root and every reservation together.
const MEMORY_END: usize = 4294901760usize
var rt_reserve_top: usize = 0usize
var rt_anchor: [1]u8 = zero

// The byte at `address` as a pointer: a window from a byte of this module's data, which lies below
// every reservation.
fn rt_pointer(address: usize) -> *u8 {
    let at = mem.address_of(&rt_anchor[0usize])
    let window = mem.Arena { base: &rt_anchor[0usize], cap: address - at + 1usize, off: 0usize }
    let bytes = mem.view(&window, address - at, 1usize)
    ret &bytes[0usize]
}

fn neper_os_reserve(n: usize) -> (*u8, err) {
    if rt_reserve_top == 0usize || n == 0usize { ret (nil, Unsupported) }
    rt_acquire()
    if rt_reserve_top >= MEMORY_END || n > MEMORY_END - rt_reserve_top {
        rt_release()
        ret (nil, mem.Exhausted)
    }
    let start = rt_reserve_top
    rt_reserve_top = start + (n + 65535usize) / 65536usize * 65536usize
    rt_release()
    ret (rt_pointer(start), ok)
}

fn neper_os_commit(p: *u8, n: usize) -> err {
    let start = mem.address_of(p)
    if start > rt_reserve_top || n > rt_reserve_top - start { ret Failed }
    ret ok
}

// A futex wait on a module with one thread. Nobody can change the word while this thread waits, so
// there are three cases: the word is not `expected` (the wait is over, as on Linux); a finite
// timeout (sleep for it on the monotonic clock with a `poll_oneoff` clock subscription, then report
// `Timeout`; zero polls once); no timeout (negative), which can never end and which every caller
// of `wait_u32` would answer by waiting again, so the module stops with the deadlock named.
// A `--threads` module waits for real: woken (0) and not equal (1) are `ok`, timed out (2) is
// `Timeout`, the native contract, which allows a spurious wake.
fn neper_os_wait_u32(p: *u8, expected: u32, timeout_ns: i64) -> err {
    if wasm_threads() == 1u32 {
        if wasm_wait32(u32(mem.address_of(p)), expected, timeout_ns) == 2u32 { ret Timeout }
        ret ok
    }
    var word: [1]u32 = zero
    wasm_memory_copy(u32(mem.address_of(&word[0usize])), u32(mem.address_of(p)), 4u32)
    if word[0usize] != expected { ret ok }
    if timeout_ns < 0i64 {
        rt_stderr_bytes("trap[deadlock]: wait_u32 with no timeout on a word nothing can change (this module has one thread)\n")
        wasi_proc_exit(134u32)
    }
    if timeout_ns > 0i64 {
        var subscription: [6]u64 = zero
        var event: [4]u64 = zero
        var count: [1]u32 = zero
        subscription[2usize] = 1u64
        subscription[3usize] = u64(timeout_ns)
        let status = wasi_poll_oneoff(u32(mem.address_of(&subscription[0usize])), u32(mem.address_of(&event[0usize])), 1u32, u32(mem.address_of(&count[0usize])))
        if status != 0u32 { ret wasi_error(status) }
    }
    ret Timeout
}

fn neper_os_wake_one_u32(p: *u8) { let woken = wasm_notify(u32(mem.address_of(p)), 1u32) }

fn neper_os_wake_all_u32(p: *u8) { let woken = wasm_notify(u32(mem.address_of(p)), 4294967295u32) }

// os.copy_bytes(dst: *[]u8, src: *[]const u8): the shorter length's worth.
fn neper_os_copy_bytes(dst: *[]u8, src: *[]const u8) {
    let to = *dst
    let from = *src
    var count = from.len
    if to.len < count { count = to.len }
    if count == 0usize { ret }
    wasm_memory_copy(u32(mem.address_of(&to[0usize])), u32(mem.address_of(&from[0usize])), u32(count))
}

fn neper_os_touch(p: *u8, n: usize) {}

fn neper_os_cpu_features() -> usize { ret 0usize }

fn neper_os_sha256_blocks(state: *[]usize, bytes: *[]const u8) -> usize { ret 0usize }

fn neper_os_crc32c_bytes(crc: *[]usize, bytes: *[]const u8) -> usize { ret 0usize }

fn neper_os_aes_expand_key(features: usize, key: *[]const u8, out: *[]u8) -> usize { ret 0usize }

fn neper_os_aes_ctr(features: usize, keys: *[]const u8, counter: *[]u8, data: *[]u8) -> usize { ret 0usize }

fn neper_os_ghash_blocks(features: usize, state: *[]u8, h: *[]const u8, data: *[]const u8) -> usize { ret 0usize }

// ---- the file system: WASI preview 1 over the directories the host preopened --------------------------
// A module names files only through a preopened directory (a descriptor from 3 up that
// fd_prestat_get describes), so a path is resolved here: an absolute path against the preopen whose
// name is its longest prefix, a relative one against the working directory. `.` -- what scripts/
// run-wasm.mjs preopens -- stands for `/`, so `/np-fs` and `np-fs` are one file. WASI has no working
// directory, so `set_current_dir` holds a descriptor and the text of its path. It also has no
// permission bits, no creation time and no atomic no-replace rename: `stat` reports 0644 for a file
// and 0755 for a directory, `set_mode` only checks that the path exists, and `replace` without
// `overwrite` looks before it renames.

const MOUNT_MAX: usize = 8usize
const NO_FD: u32 = 4294967295u32
const PATH_CAPACITY: usize = 4096usize
const LINK_LIMIT: usize = 40usize

// WASI rights (bit n of the mask). A descriptor opened for reading gets the read set; one opened for
// writing adds the write set. Node's host maps the pair to O_RDONLY, O_WRONLY or O_RDWR.
const FILE_READ_RIGHTS: u64 = 136315070u64
const FILE_WRITE_RIGHTS: u64 = 12583233u64
const DIR_RIGHTS: u64 = 264240830u64
const ALL_RIGHTS: u64 = 268435455u64

// The host's errno, kept for last_error_detail in a slot per thread keyed by current_thread_id, as
// os.linux.e keeps it: a read requires the identifier to match, so a thread never reads another's.
// used: 0 unused, 1 the kind from the code, 2 a contextual `Denied`; fresh: recorded and not read.
// ponytail: sixty-four slots, no eviction, no atomics; more live threads than that lose details,
// a diagnostic and never a wrong answer. Real thread-local storage would replace it.
const ERROR_SLOTS: usize = 64usize
var error_slot_thread: [64]usize = zero
var error_slot_code: [64]i32 = zero
var error_slot_used: [64]u8 = zero
var error_slot_fresh: [64]u8 = zero

var mounts_loaded: bool = false
var mount_count: usize = 0usize
var mount_fds: [8]u32 = zero
var mount_starts: [8]usize = zero
var mount_lens: [8]usize = zero
var mount_names: [1024]u8 = zero
var mount_used: usize = 0usize
var root_mount: usize = 8usize
var cwd_fd: u32 = 4294967295u32
var cwd_owned: bool = false
var cwd_text: [1024]u8 = zero
var cwd_len: usize = 1usize

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
    if error_slot_fresh[slot] == 1u8 && error_slot_used[slot] != 0u8 && error_slot_thread[slot] == thread { ret }
    record_error_detail(code)
}

// WASI's errno numbers: EACCES 2, EAGAIN 6, EEXIST 20, EINTR 27, EINVAL 28, ELOOP 32, ENOENT 44,
// ENOMEM 48, ENOSYS 52, ENOTSUP 58, EPERM 63, ETIMEDOUT 73, EXDEV 75, ENOTCAPABLE 76. Only the codes
// the fence names are distinguished; the rest is `Failed`.
fn error_of_status(status: u32) -> err {
    if status == 0u32 { ret ok }
    if status == 2u32 || status == 63u32 || status == 76u32 || status == 32u32 { ret Denied }
    if status == 44u32 { ret NotFound }
    if status == 20u32 { ret Exists }
    if status == 27u32 { ret Interrupted }
    if status == 6u32 { ret WouldBlock }
    if status == 48u32 { ret OutOfMemory }
    if status == 73u32 { ret Timeout }
    if status == 28u32 || status == 52u32 || status == 58u32 || status == 75u32 { ret Unsupported }
    ret Failed
}

fn error_kind_of(code: i32) -> ErrorKind {
    if code == 2i32 || code == 63i32 || code == 76i32 || code == 32i32 { ret ErrorKind.Denied }
    if code == 44i32 { ret ErrorKind.NotFound }
    if code == 20i32 { ret ErrorKind.Exists }
    if code == 27i32 { ret ErrorKind.Interrupted }
    if code == 6i32 { ret ErrorKind.WouldBlock }
    if code == 48i32 { ret ErrorKind.OutOfMemory }
    if code == 73i32 { ret ErrorKind.Timeout }
    if code == 28i32 || code == 52i32 || code == 58i32 || code == 75i32 { ret ErrorKind.Unsupported }
    ret ErrorKind.Other
}

fn wasi_error(status: u32) -> err {
    if status == 0u32 { ret ok }
    record_error_detail(i32(status))
    ret error_of_status(status)
}

fn wasi_cleanup(status: u32) -> err {
    if status == 0u32 { ret ok }
    record_cleanup_error_detail(i32(status))
    ret error_of_status(status)
}

fn detail_from_code(code: i32, operation: str, subject: str) -> ErrorDetail {
    var detail: ErrorDetail = zero
    detail.kind = error_kind_of(code)
    detail.native_code = code
    detail.operation = operation
    detail.subject = subject
    ret detail
}

fn last_error_detail(operation: str, subject: str) -> ErrorDetail {
    var detail: ErrorDetail = zero
    detail.kind = ErrorKind.Other
    detail.operation = operation
    detail.subject = subject
    let thread = current_thread_id()
    let slot = thread % ERROR_SLOTS
    let used = error_slot_used[slot]
    if used == 0u8 || error_slot_thread[slot] != thread { ret detail }
    error_slot_fresh[slot] = 0u8
    detail = detail_from_code(error_slot_code[slot], operation, subject)
    if used == 2u8 { detail.kind = ErrorKind.Denied }
    ret detail
}

fn address_of_str(text: str) -> u32 {
    if text.len == 0usize { ret 0u32 }
    let bytes: []const u8 = text
    ret u32(mem.address_of(&bytes[0usize]))
}

fn address_of_bytes(bytes: []u8) -> u32 {
    if bytes.len == 0usize { ret 0u32 }
    ret u32(mem.address_of(&bytes[0usize]))
}

// The text appended at `at`; the position after it even where it did not fit, so the caller can tell.
fn push_text(buffer: []u8, at: usize, text: str) -> usize {
    var offset = 0usize
    while offset < text.len {
        if at + offset < buffer.len { buffer[at + offset] = text[offset] }
        offset += 1usize
    }
    ret at + text.len
}

// ---- preopens and paths ----------------------------------------------------------------------------------

fn load_mounts() {
    if mounts_loaded { ret }
    mounts_loaded = true
    cwd_text[0usize] = 47u8
    cwd_len = 1usize
    var fd = 3u32
    var info: [2]u32 = zero
    var name: [256]u8 = zero
    while mount_count < MOUNT_MAX {
        if wasi_fd_prestat_get(fd, u32(mem.address_of(&info[0usize]))) != 0u32 { break }
        let name_len = usize(info[1usize])
        if (info[0usize] & 255u32) == 0u32 && name_len > 0usize && name_len < 255usize && mount_used + name_len + 2usize <= 1024usize {
            if wasi_fd_prestat_dir_name(fd, u32(mem.address_of(&name[0usize])), u32(name_len)) == 0u32 {
                let start = mount_used
                var at = start
                if name[0usize] == 46u8 && name_len == 1usize {
                    mount_names[at] = 47u8
                    at += 1usize
                } else {
                    if name[0usize] != 47u8 {
                        mount_names[at] = 47u8
                        at += 1usize
                    }
                    var copied = 0usize
                    while copied < name_len {
                        mount_names[at] = name[copied]
                        at += 1usize
                        copied += 1usize
                    }
                    while at > start + 1usize && mount_names[at - 1usize] == 47u8 { at = at - 1usize }
                }
                mount_fds[mount_count] = fd
                mount_starts[mount_count] = start
                mount_lens[mount_count] = at - start
                if at - start == 1usize && root_mount == MOUNT_MAX { root_mount = mount_count }
                mount_count += 1usize
                mount_used = at
            }
        }
        fd += 1u32
    }
    if root_mount < MOUNT_MAX { cwd_fd = mount_fds[root_mount] }
}

fn mount_matches(path: str, index: usize) -> bool {
    let length = mount_lens[index]
    if path.len < length { ret false }
    var at = 0usize
    while at < length {
        if path[at] != mount_names[mount_starts[index] + at] { ret false }
        at += 1usize
    }
    if length == 1usize || path.len == length { ret true }
    ret path[length] == 47u8
}

// The descriptor a path is relative to and the path relative to it.
fn resolve(path: str) -> (u32, str, err) {
    load_mounts()
    if path.len == 0usize {
        record_error_detail(44i32)
        ret (NO_FD, "", NotFound)
    }
    if path[0usize] != 47u8 {
        if cwd_fd == NO_FD {
            record_error_detail(44i32)
            ret (NO_FD, "", NotFound)
        }
        ret (cwd_fd, path, ok)
    }
    var best = MOUNT_MAX
    var index = 0usize
    while index < mount_count {
        if mount_matches(path, index) && (best == MOUNT_MAX || mount_lens[index] > mount_lens[best]) { best = index }
        index += 1usize
    }
    if best == MOUNT_MAX {
        record_error_detail(44i32)
        ret (NO_FD, "", NotFound)
    }
    var from = mount_lens[best]
    while from < path.len && path[from] == 47u8 { from += 1usize }
    if from >= path.len { ret (mount_fds[best], ".", ok) }
    ret (mount_fds[best], path[from..path.len], ok)
}

// A name under a directory and nothing else: an absolute one would ignore the directory, `..` would
// leave it, and an embedded NUL would make the host see a shorter path than the caller wrote.
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

// ---- stat, directories, links ------------------------------------------------------------------------------

fn kind_of_filetype(filetype: u64) -> EntryKind {
    if filetype == 4u64 { ret EntryKind.File }
    if filetype == 3u64 { ret EntryKind.Dir }
    if filetype == 7u64 { ret EntryKind.Symlink }
    ret EntryKind.Other
}

fn stat_path(path: str, follow: bool) -> (FileInfo, err) {
    var info: FileInfo = zero
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret (info, resolve_error) }
    var raw: [8]u64 = zero
    var lookup = 0u32
    if follow { lookup = 1u32 }
    let status = wasi_path_filestat_get(fd, lookup, address_of_str(rel), u32(rel.len), u32(mem.address_of(&raw[0usize])))
    if status != 0u32 { ret (info, wasi_error(status)) }
    info.kind = kind_of_filetype(raw[2usize] & 255u64)
    info.size = raw[4usize]
    info.accessed_ns = i64(raw[5usize])
    info.modified_ns = i64(raw[6usize])
    info.created_ns = -1i64
    info.file_id = raw[1usize]
    info.link_count = raw[3usize]
    info.mode = 420u32
    if info.kind == EntryKind.Dir { info.mode = 493u32 }
    if info.kind == EntryKind.Symlink { info.mode = 511u32 }
    ret (info, ok)
}

fn stat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    let (info, stat_error) = stat_path(path, true)
    ret (info, stat_error)
}

fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err) {
    let (info, stat_error) = stat_path(path, false)
    ret (info, stat_error)
}

fn mkdir(a: *mem.Arena, path: str) -> err {
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret resolve_error }
    ret wasi_error(wasi_path_create_directory(fd, address_of_str(rel), u32(rel.len)))
}

fn remove_file(a: *mem.Arena, path: str) -> err {
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret resolve_error }
    ret wasi_error(wasi_path_unlink_file(fd, address_of_str(rel), u32(rel.len)))
}

fn remove_dir(a: *mem.Arena, path: str) -> err {
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret resolve_error }
    ret wasi_error(wasi_path_remove_directory(fd, address_of_str(rel), u32(rel.len)))
}

fn rename(a: *mem.Arena, src: str, dst: str) -> err {
    let (from_fd, from_rel, from_error) = resolve(src)
    if from_error != ok { ret from_error }
    let (to_fd, to_rel, to_error) = resolve(dst)
    if to_error != ok { ret to_error }
    ret wasi_error(wasi_path_rename(from_fd, address_of_str(from_rel), u32(from_rel.len), to_fd, address_of_str(to_rel), u32(to_rel.len)))
}

// Best effort: the name is already where it was sent, and a host that cannot sync a descriptor says so.
fn flush_path(path: str) {
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret }
    var opened: [1]u32 = zero
    let status = wasi_path_open(fd, 1u32, address_of_str(rel), u32(rel.len), 0u32, FILE_READ_RIGHTS | FILE_WRITE_RIGHTS, 0u64, 0u32, u32(mem.address_of(&opened[0usize])))
    if status != 0u32 { ret }
    let synced = wasi_fd_sync(opened[0usize])
    let closed = wasi_fd_close(opened[0usize])
}

// WASI has no rename that refuses an existing destination, so without `overwrite` the destination is
// looked at first (ceiling: another process can take the name in between; there is one thread here).
fn replace(a: *mem.Arena, src: str, dst: str, overwrite: bool, durable: bool) -> err {
    if !overwrite {
        let (present, present_error) = stat_path(dst, false)
        if present_error == ok {
            record_error_detail(20i32)
            ret Exists
        }
        if present_error != NotFound { ret present_error }
    }
    let renamed = rename(a, src, dst)
    if renamed != ok { ret renamed }
    if durable { flush_path(dst) }
    ret ok
}

fn read_link(a: *mem.Arena, path: str) -> (str, err) {
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret ("", resolve_error) }
    var capacity = 256usize
    while capacity <= 65536usize {
        let checkpoint = mem.mark(a)
        let (buffer, allocation_error) = mem.alloc[u8](a, capacity)
        if allocation_error != ok { ret ("", OutOfMemory) }
        var used: [1]u32 = zero
        let status = wasi_path_readlink(fd, address_of_str(rel), u32(rel.len), address_of_bytes(buffer), u32(capacity), u32(mem.address_of(&used[0usize])))
        if status != 0u32 {
            let read_error = wasi_error(status)
            mem.reset(a, checkpoint)
            ret ("", read_error)
        }
        if usize(used[0usize]) < capacity { ret (buffer[0usize..usize(used[0usize])], ok) }
        mem.reset(a, checkpoint)
        capacity = capacity * 2usize
    }
    ret ("", Failed)
}

fn symlink(a: *mem.Arena, target_path: str, link: str) -> err {
    let (fd, rel, resolve_error) = resolve(link)
    if resolve_error != ok { ret resolve_error }
    ret wasi_error(wasi_path_symlink(address_of_str(target_path), u32(target_path.len), fd, address_of_str(rel), u32(rel.len)))
}

// The path, absolute, with every `.`, `..` and link resolved, by walking it a component at a time and
// reading each link met: there is no realpath in WASI. Every component has to exist.
fn canonical(a: *mem.Arena, path: str) -> (str, err) {
    load_mounts()
    if path.len == 0usize {
        record_error_detail(44i32)
        ret ("", NotFound)
    }
    let checkpoint = mem.mark(a)
    let (done, done_error) = mem.alloc[u8](a, PATH_CAPACITY)
    if done_error != ok { ret ("", OutOfMemory) }
    let (pending, pending_error) = mem.alloc[u8](a, PATH_CAPACITY)
    if pending_error != ok {
        mem.reset(a, checkpoint)
        ret ("", OutOfMemory)
    }
    let (scratch, scratch_error) = mem.alloc[u8](a, PATH_CAPACITY)
    if scratch_error != ok {
        mem.reset(a, checkpoint)
        ret ("", OutOfMemory)
    }
    var pending_len = 0usize
    if path[0usize] != 47u8 {
        if cwd_len > 1usize {
            var copied = 0usize
            while copied < cwd_len {
                pending[copied] = cwd_text[copied]
                copied += 1usize
            }
            pending_len = cwd_len
        }
        pending_len = push_text(pending, pending_len, "/")
    }
    pending_len = push_text(pending, pending_len, path)
    if pending_len > PATH_CAPACITY {
        mem.reset(a, checkpoint)
        ret ("", Failed)
    }
    var done_len = 0usize
    var position = 0usize
    var links = 0usize
    while true {
        while position < pending_len && pending[position] == 47u8 { position += 1usize }
        if position >= pending_len { break }
        var stop = position
        while stop < pending_len && pending[stop] != 47u8 { stop += 1usize }
        let part = pending[position..stop]
        position = stop
        if part.len == 1usize && part[0usize] == 46u8 { continue }
        if part.len == 2usize && part[0usize] == 46u8 && part[1usize] == 46u8 {
            while done_len > 0usize && done[done_len - 1usize] != 47u8 { done_len = done_len - 1usize }
            if done_len > 0usize { done_len = done_len - 1usize }
            continue
        }
        let candidate_len = push_text(done, push_text(done, done_len, "/"), part)
        if candidate_len > PATH_CAPACITY {
            mem.reset(a, checkpoint)
            ret ("", Failed)
        }
        let (info, info_error) = stat_path(done[0usize..candidate_len], false)
        if info_error != ok {
            mem.reset(a, checkpoint)
            ret ("", info_error)
        }
        if info.kind != EntryKind.Symlink {
            done_len = candidate_len
            continue
        }
        links += 1usize
        if links > LINK_LIMIT {
            record_error_detail(32i32)
            mem.reset(a, checkpoint)
            ret ("", Denied)
        }
        let (link_target, link_error) = read_link(a, done[0usize..candidate_len])
        if link_error != ok {
            mem.reset(a, checkpoint)
            ret ("", link_error)
        }
        if link_target.len > 0usize && link_target[0usize] == 47u8 { done_len = 0usize }
        var scratch_len = push_text(scratch, 0usize, link_target)
        scratch_len = push_text(scratch, scratch_len, "/")
        scratch_len = push_text(scratch, scratch_len, pending[position..pending_len])
        if scratch_len > PATH_CAPACITY {
            mem.reset(a, checkpoint)
            ret ("", Failed)
        }
        var moved = 0usize
        while moved < scratch_len {
            pending[moved] = scratch[moved]
            moved += 1usize
        }
        pending_len = scratch_len
        position = 0usize
    }
    if done_len == 0usize {
        mem.reset(a, checkpoint)
        ret ("/", ok)
    }
    ret (done[0usize..done_len], ok)
}

fn open_directory(path: str) -> (u32, err) {
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret (NO_FD, resolve_error) }
    var opened: [1]u32 = zero
    let status = wasi_path_open(fd, 1u32, address_of_str(rel), u32(rel.len), 2u32, DIR_RIGHTS, ALL_RIGHTS, 0u32, u32(mem.address_of(&opened[0usize])))
    if status != 0u32 { ret (NO_FD, wasi_error(status)) }
    ret (opened[0usize], ok)
}

fn current_dir(a: *mem.Arena) -> (str, err) {
    load_mounts()
    let (bytes, allocation_error) = mem.alloc[u8](a, cwd_len)
    if allocation_error != ok { ret ("", OutOfMemory) }
    var at = 0usize
    while at < cwd_len {
        bytes[at] = cwd_text[at]
        at += 1usize
    }
    ret (bytes[0usize..cwd_len], ok)
}

fn set_current_dir(a: *mem.Arena, path: str) -> err {
    let checkpoint = mem.mark(a)
    let (resolved, resolved_error) = canonical(a, path)
    if resolved_error != ok { ret resolved_error }
    if resolved.len > 1024usize {
        mem.reset(a, checkpoint)
        ret Failed
    }
    let (fd, open_error) = open_directory(resolved)
    if open_error != ok {
        mem.reset(a, checkpoint)
        ret open_error
    }
    if cwd_owned { let closed = wasi_fd_close(cwd_fd) }
    cwd_fd = fd
    cwd_owned = true
    var at = 0usize
    while at < resolved.len {
        cwd_text[at] = resolved[at]
        at += 1usize
    }
    cwd_len = resolved.len
    mem.reset(a, checkpoint)
    ret ok
}

// ---- files ------------------------------------------------------------------------------------------------------

// `rel` under `fd`. `follow` lets a link in the last component lead on; `excl` fails if it is there.
fn open_relative(fd: u32, rel: str, flags: OpenFlags, excl: bool, follow: bool) -> (File, err) {
    var file: File = zero
    var open_flags = 0u32
    if flags.create { open_flags = open_flags | 1u32 }
    if flags.create && excl { open_flags = open_flags | 4u32 }
    var rights = 0u64
    if flags.read || !flags.write { rights = FILE_READ_RIGHTS }
    if flags.write {
        rights = rights | FILE_WRITE_RIGHTS
        if flags.truncate { open_flags = open_flags | 8u32 }
    }
    var fd_flags = 0u32
    if flags.append { fd_flags = 1u32 }
    var lookup = 0u32
    if follow { lookup = 1u32 }
    var opened: [1]u32 = zero
    let status = wasi_path_open(fd, lookup, address_of_str(rel), u32(rel.len), open_flags, rights, 0u64, fd_flags, u32(mem.address_of(&opened[0usize])))
    if status != 0u32 { ret (file, wasi_error(status)) }
    file.raw = usize(opened[0usize])
    ret (file, ok)
}

fn open_path(path: str, flags: OpenFlags, excl: bool) -> (File, err) {
    var file: File = zero
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret (file, resolve_error) }
    let (opened, open_error) = open_relative(fd, rel, flags, excl, true)
    ret (opened, open_error)
}

fn create_new(a: *mem.Arena, path: str) -> (File, err) {
    var flags: OpenFlags = zero
    flags.write = true
    flags.create = true
    let (file, create_error) = open_path(path, flags, true)
    ret (file, create_error)
}

fn le32(bytes: []u8, at: usize) -> usize {
    ret usize(bytes[at]) | (usize(bytes[at + 1usize]) << 8usize) | (usize(bytes[at + 2usize]) << 16usize) | (usize(bytes[at + 3usize]) << 24usize)
}

// os.readdir(result, arena, path): the entries of one directory, `.` and `..` left out, their names
// in the arena. The listing is read whole; a buffer that came back full may have been cut short, so
// it is read again into a bigger one.
fn neper_os_readdir(result: *ReaddirResult, arena: *mem.Arena, path: *str) {
    var none: []DirEntry = zero
    result.entries = none
    result.failure = Failed
    let (fd, open_error) = open_directory(*path)
    if open_error != ok {
        result.failure = open_error
        ret
    }
    let checkpoint = mem.mark(arena)
    var capacity = 4096usize
    var used = 0usize
    var listing: []u8 = zero
    while true {
        let (block, block_error) = mem.alloc[u8](arena, capacity)
        if block_error != ok {
            let closed = wasi_fd_close(fd)
            mem.reset(arena, checkpoint)
            result.failure = block_error
            ret
        }
        var written: [1]u32 = zero
        let status = wasi_fd_readdir(fd, address_of_bytes(block), u32(capacity), 0u64, u32(mem.address_of(&written[0usize])))
        if status != 0u32 {
            let failure = wasi_error(status)
            let closed = wasi_fd_close(fd)
            mem.reset(arena, checkpoint)
            result.failure = failure
            ret
        }
        used = usize(written[0usize])
        listing = block
        if used < capacity { break }
        if capacity >= 16777216usize {
            let closed = wasi_fd_close(fd)
            mem.reset(arena, checkpoint)
            result.failure = Failed
            ret
        }
        mem.reset(arena, checkpoint)
        capacity = capacity * 2usize
    }
    let closed = wasi_fd_close(fd)
    var count = 0usize
    var at = 0usize
    while at + 24usize <= used {
        let name_len = le32(listing, at + 16usize)
        if at + 24usize + name_len > used { break }
        let name = listing[at + 24usize..at + 24usize + name_len]
        if !(name.len == 1usize && name[0usize] == 46u8) && !(name.len == 2usize && name[0usize] == 46u8 && name[1usize] == 46u8) { count += 1usize }
        at = at + 24usize + name_len
    }
    let (entries, entries_error) = mem.alloc[DirEntry](arena, count + 1usize)
    if entries_error != ok {
        result.failure = entries_error
        ret
    }
    var filled = 0usize
    at = 0usize
    while at + 24usize <= used {
        let name_len = le32(listing, at + 16usize)
        if at + 24usize + name_len > used { break }
        let name = listing[at + 24usize..at + 24usize + name_len]
        if !(name.len == 1usize && name[0usize] == 46u8) && !(name.len == 2usize && name[0usize] == 46u8 && name[1usize] == 46u8) {
            entries[filled].name = name
            entries[filled].kind = kind_of_filetype(u64(listing[at + 20usize]))
            filled += 1usize
        }
        at = at + 24usize + name_len
    }
    result.entries = entries[0usize..filled]
    result.failure = ok
}

// ---- directory handles and the *_at family -------------------------------------------------------------------

fn dir_open(a: *mem.Arena, path: str) -> (Dir, err) {
    var dir: Dir = zero
    let (fd, open_error) = open_directory(path)
    if open_error != ok { ret (dir, open_error) }
    dir.raw = usize(fd)
    ret (dir, ok)
}

fn dir_close(dir: own Dir) -> err {
    ret wasi_cleanup(wasi_fd_close(u32(dir.raw)))
}

// The directory that holds the last component of `relative_path`, reached one step at a time with
// links refused, and that component. The handle is the caller's to close only when it is not `dir_fd`.
// A step that is a link, or is not a directory, is `Denied`, as the policy's refusal is on Linux.
fn open_parent(dir_fd: u32, relative_path: str) -> (u32, str, err) {
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
    if !found { ret (dir_fd, relative_path, ok) }
    let tail = relative_path[cut + 1usize..relative_path.len]
    if tail.len == 0usize { ret (dir_fd, "", Denied) }
    var current = dir_fd
    var position = 0usize
    while position < cut {
        var stop = position
        while stop < cut && relative_path[stop] != 47u8 { stop += 1usize }
        let step = relative_path[position..stop]
        if step.len != 0usize && !(step.len == 1usize && step[0usize] == 46u8) {
            var opened: [1]u32 = zero
            let status = wasi_path_open(current, 0u32, address_of_str(step), u32(step.len), 2u32, DIR_RIGHTS, ALL_RIGHTS, 0u32, u32(mem.address_of(&opened[0usize])))
            if current != dir_fd { let closed = wasi_fd_close(current) }
            if status != 0u32 {
                if status == 32u32 || status == 54u32 {
                    record_error_detail(i32(status))
                    error_slot_used[current_thread_id() % ERROR_SLOTS] = 2u8
                    ret (dir_fd, "", Denied)
                }
                ret (dir_fd, "", wasi_error(status))
            }
            current = opened[0usize]
        }
        position = stop + 1usize
    }
    ret (current, tail, ok)
}

// The policy is enforced while the path is walked: `NoSymlinks` opens every step but the last as a
// directory without following links and the last without following one either; `Beneath` leaves the
// walk to the host, whose sandbox already refuses a path that leaves the preopened directory.
fn open_at(a: *mem.Arena, dir: Dir, relative_path: str, flags: OpenFlags, policy: ResolvePolicy) -> (File, err) {
    var file: File = zero
    if !relative_path_ok(relative_path) { ret (file, Denied) }
    if policy == ResolvePolicy.NoSymlinks {
        let (parent, name, parent_error) = open_parent(u32(dir.raw), relative_path)
        if parent_error != ok { ret (file, parent_error) }
        let (opened, open_error) = open_relative(parent, name, flags, false, false)
        if parent != u32(dir.raw) { let closed = wasi_fd_close(parent) }
        ret (opened, open_error)
    }
    let (beneath, beneath_error) = open_relative(u32(dir.raw), relative_path, flags, false, true)
    ret (beneath, beneath_error)
}

// unlink never follows the last component, which is what makes removing a link remove the link.
fn remove_at(a: *mem.Arena, dir: Dir, relative_path: str, directory: bool) -> err {
    if !relative_path_ok(relative_path) { ret Denied }
    let (parent, name, parent_error) = open_parent(u32(dir.raw), relative_path)
    if parent_error != ok { ret parent_error }
    var status = 0u32
    if directory {
        status = wasi_path_remove_directory(parent, address_of_str(name), u32(name.len))
    } else {
        status = wasi_path_unlink_file(parent, address_of_str(name), u32(name.len))
    }
    let removed = wasi_error(status)
    if parent != u32(dir.raw) { let closed = wasi_fd_close(parent) }
    ret removed
}

fn rename_at(a: *mem.Arena, src_dir: Dir, src_path: str, dst_dir: Dir, dst_path: str, overwrite: bool, durable: bool) -> err {
    if !relative_path_ok(src_path) { ret Denied }
    if !relative_path_ok(dst_path) { ret Denied }
    let (src_parent, src_name, src_error) = open_parent(u32(src_dir.raw), src_path)
    if src_error != ok { ret src_error }
    let (dst_parent, dst_name, dst_error) = open_parent(u32(dst_dir.raw), dst_path)
    if dst_error != ok {
        if src_parent != u32(src_dir.raw) { let closed = wasi_fd_close(src_parent) }
        ret dst_error
    }
    var answer = ok
    if !overwrite {
        var raw: [8]u64 = zero
        let probe = wasi_path_filestat_get(dst_parent, 0u32, address_of_str(dst_name), u32(dst_name.len), u32(mem.address_of(&raw[0usize])))
        if probe == 0u32 {
            record_error_detail(20i32)
            answer = Exists
        }
    }
    if answer == ok {
        answer = wasi_error(wasi_path_rename(src_parent, address_of_str(src_name), u32(src_name.len), dst_parent, address_of_str(dst_name), u32(dst_name.len)))
    }
    if answer == ok && durable { let synced = wasi_fd_sync(dst_parent) }
    if src_parent != u32(src_dir.raw) { let closed = wasi_fd_close(src_parent) }
    if dst_parent != u32(dst_dir.raw) { let closed = wasi_fd_close(dst_parent) }
    ret answer
}

// ---- modes, times, the environment, random bytes -------------------------------------------------------------

// WASI has no chmod: the path is checked to exist and nothing changes (see the note at the top).
fn set_mode(a: *mem.Arena, path: str, mode: u32) -> err {
    let (info, stat_error) = stat_path(path, true)
    ret stat_error
}

// A negative stamp is left as it is; the host keeps the precision its filesystem has.
fn set_times(a: *mem.Arena, path: str, accessed_ns: i64, modified_ns: i64) -> err {
    let (fd, rel, resolve_error) = resolve(path)
    if resolve_error != ok { ret resolve_error }
    var which = 0u32
    var accessed = 0u64
    var modified = 0u64
    if accessed_ns >= 0i64 {
        which = which | 1u32
        accessed = u64(accessed_ns)
    }
    if modified_ns >= 0i64 {
        which = which | 4u32
        modified = u64(modified_ns)
    }
    ret wasi_error(wasi_path_filestat_set_times(fd, 1u32, address_of_str(rel), u32(rel.len), accessed, modified, which))
}

// One NAME=VALUE record at a time. The name has to match to its whole length and end at the `=`, or a
// lookup of `PAT` would be answered by `PATH`.
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

fn env(a: *mem.Arena, name: str) -> (str, err) {
    var sizes: [2]u32 = zero
    let sizes_status = wasi_environ_sizes_get(u32(mem.address_of(&sizes[0usize])), u32(mem.address_of(&sizes[1usize])))
    if sizes_status != 0u32 { ret ("", wasi_error(sizes_status)) }
    let count = usize(sizes[0usize])
    let block_size = usize(sizes[1usize])
    if count == 0usize { ret ("", NotFound) }
    let checkpoint = mem.mark(a)
    let (pointers, pointers_error) = mem.alloc[u32](a, count + 1usize)
    if pointers_error != ok { ret ("", OutOfMemory) }
    let (block, block_error) = mem.alloc[u8](a, block_size + 1usize)
    if block_error != ok {
        mem.reset(a, checkpoint)
        ret ("", OutOfMemory)
    }
    let get_status = wasi_environ_get(u32(mem.address_of(&pointers[0usize])), u32(mem.address_of(&block[0usize])))
    if get_status != 0u32 {
        mem.reset(a, checkpoint)
        ret ("", wasi_error(get_status))
    }
    let (value, found) = environment_value(block[0usize..block_size], name)
    if !found {
        mem.reset(a, checkpoint)
        ret ("", NotFound)
    }
    ret (value, ok)
}

// The module's own path as the host was told it, made absolute against the root: the runner passes a
// path inside a preopened directory as the first argument.
fn executable_path(a: *mem.Arena) -> (str, err) {
    var items: []str = zero
    neper_start_args(&items, a)
    if items.len == 0usize {
        record_error_detail(44i32)
        ret ("", NotFound)
    }
    let first = items[0usize]
    if first.len == 0usize || first[0usize] == 47u8 { ret (first, ok) }
    let (bytes, allocation_error) = mem.alloc[u8](a, first.len + 1usize)
    if allocation_error != ok { ret ("", OutOfMemory) }
    bytes[0usize] = 47u8
    var at = 0usize
    while at < first.len {
        bytes[at + 1usize] = first[at]
        at += 1usize
    }
    ret (bytes[0usize..first.len + 1usize], ok)
}

fn random(buffer: []u8) -> err {
    var filled = 0usize
    while filled < buffer.len {
        var chunk = buffer.len - filled
        if chunk > 65536usize { chunk = 65536usize }
        let status = wasi_random_get(u32(mem.address_of(&buffer[filled])), u32(chunk))
        if status != 0u32 { ret wasi_error(status) }
        filled += chunk
    }
    ret ok
}

// ---- the checked forms: the failing call's detail written into the caller's value -----------------------

fn stat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = stat(a, path)
    if stat_error != ok {
        *detail = last_error_detail("stat", path)
        ret (info, stat_error)
    }
    ret (info, ok)
}

fn lstat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err) {
    let (info, stat_error) = lstat(a, path)
    if stat_error != ok {
        *detail = last_error_detail("lstat", path)
        ret (info, stat_error)
    }
    ret (info, ok)
}

fn open_detail(a: *mem.Arena, path: str, flags: OpenFlags, detail: *ErrorDetail) -> (File, err) {
    let (file, open_error) = open(a, path, flags)
    if open_error != ok {
        *detail = last_error_detail("open", path)
        ret (file, open_error)
    }
    ret (file, ok)
}

fn dir_open_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (Dir, err) {
    let (dir, open_error) = dir_open(a, path)
    if open_error != ok {
        *detail = last_error_detail("dir_open", path)
        ret (dir, open_error)
    }
    ret (dir, ok)
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
// The wasi-threads tid plus one: 1 on the main thread (tid 0) and in a plain module, non-zero and
// distinct on every other. Non-zero matters: a zero reads as "no owner" to a reentrant lock
// (e.gpu's device lock), which would then re-lock a mutex it already holds and deadlock.
fn current_thread_id() -> usize { ret usize(wasm_thread_id()) + 1usize }

// (D2168/D2169, C110) The native-window surface e.ui.window compiles against, as os.neperos.e has it:
// there is no window manager under WASI, so a window opens and presents nothing. The headless testing
// harness touches none of these.
const SURFACE_W: usize = 1280usize
const SURFACE_H: usize = 2856usize
type Window = struct { raw: usize }
type WindowMode = enum u8 { Windowed, Maximized, Fullscreen }
type WindowOptions = struct { title: str, width: u32, height: u32, resizable: bool, visible: bool, mode: WindowMode }
type WindowMetrics = struct { width: u32, height: u32, scale_percent: u32, focused: bool, visible: bool }
type CursorShape = enum u8 { Arrow, Text, Hand, Crosshair, ResizeHorizontal, ResizeVertical, Hidden }
type MonitorInfo = struct { x: i32, y: i32, width: u32, height: u32, work_x: i32, work_y: i32, work_width: u32, work_height: u32, scale_percent: u32, primary: bool }
type AccessibleNode = struct { id: u32, generation: u32, parent: u32, parent_generation: u32, has_parent: bool, role: u8, label: str, value: str, hint: str, flags: u16, actions: u32, sort: u8, live: u8, row: u32, column: u32, row_count: u32, column_count: u32, level: u8, selection_start: usize, selection_end: usize, labelled_by: u32, labelled_by_generation: u32, described_by: u32, described_by_generation: u32, error_by: u32, error_by_generation: u32, controls: u32, controls_generation: u32, active: u32, active_generation: u32, relation_flags: u8, x: f32, y: f32, width: f32, height: f32 }
fn window_open(a: *mem.Arena, options: WindowOptions) -> (Window, err) { ret (Window { raw: 1usize }, ok) }
fn window_close(w: Window) -> err { ret ok }
fn window_metrics(w: Window) -> (WindowMetrics, err) { ret (WindowMetrics { width: u32(SURFACE_W), height: u32(SURFACE_H), scale_percent: 100u32, focused: true, visible: true }, ok) }
fn window_title(w: Window, value: str) -> err { ret ok }
fn window_visible(w: Window, value: bool) -> err { ret ok }
fn window_cursor(w: Window, shape: CursorShape) -> err { ret ok }
// No window manager here: a program presents nothing.
fn window_present(w: Window, pixels: []const u32, width: u32, height: u32) -> err { ret Unsupported }
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

// (D4704, C107) The rest of the fence's surface, so every `e.*` module that compiles against the
// other targets' `e.os` compiles for NeperOS: a NeperOS program has no sockets, pollers, mappings,
// watches, signals, pipes, processes of its own or sandbox, and each of these answers
// `Unsupported` -- never a wrong answer -- except what has a true value here (`page_size`, 4 KiB
// frames) or a harmless one (`error_message` renders the operation). The shapes are the fence's.
type ProcUsage = struct { exit_code: i32, peak_memory: usize }
type Socket = resource(socket_close) struct { raw: usize }
type Poller = resource(poller_close) struct { state: *void }
type Mapping = resource(mapping_close) struct { raw: usize, address: *u8, len: usize }
type Watch = resource(watch_close) struct { state: *void }
type WatchAction = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type WatchEvent = struct { action: WatchAction, path: str, old_path: str }
type SpawnOptions = struct { argv: []const str, env: []const str, inherit_env: bool, cwd: str, stdio: Stdio }
type SocketFamily = enum u8 { Ip4, Ip6 }
type SocketKind = enum u8 { Stream, Datagram }
type SocketShutdown = enum u8 { Read, Write, Both }
type SocketAddress = struct { family: SocketFamily, bytes: [16]u8, scope: u32, port: u16 }
type PollInterest = struct { readable: bool, writable: bool }
type PollEvent = struct { token: usize, readable: bool, writable: bool, closed: bool, failed: bool }
type FileLock = resource(file_unlock) struct { raw: usize }
type ProcGroup = resource(proc_group_close) struct { raw: usize }
type Signal = enum u8 { Interrupt, Terminate, Abort, SegmentFault, FloatingPoint, Illegal }
type SandboxPolicy = struct { allow_syscalls: []const u32, deny_child_processes: bool, deny_dynamic_code: bool, kill_on_violation: bool }

fn page_size() -> usize { ret 4096usize }
fn release(p: *u8, n: usize) -> err {
    let start = mem.address_of(p)
    rt_acquire()
    if start + (n + 65535usize) / 65536usize * 65536usize == rt_reserve_top { rt_reserve_top = start }
    rt_release()
    ret ok
}
// The memory never shrinks, so its size is the most the module has held (D5640).
fn peak_memory() -> (usize, err) { ret (usize(wasm_memory_size()) * 65536usize, ok) }
fn stdin() -> File { ret File { raw: 0usize } }
fn create_new_with_mode(a: *mem.Arena, path: str, mode: u32) -> (File, err) {
    let (file, create_error) = create_new(a, path)
    ret (file, create_error)
}
fn error_message(a: *mem.Arena, detail: ErrorDetail) -> (str, err) { ret (detail.operation, ok) }
fn window_native(w: Window) -> (usize, usize, err) { ret (0usize, 0usize, Unsupported) }

fn pipe() -> (File, File, err) { ret (File { raw: 0usize }, File { raw: 0usize }, Unsupported) }
fn pipe_read(f: File, buffer: []u8) -> (usize, err) { ret (0usize, Unsupported) }
fn dup(f: File) -> (File, err) { ret (File { raw: 0usize }, Unsupported) }
fn spawn_with_options(a: *mem.Arena, options: SpawnOptions) -> (Proc, err) { ret (Proc { raw: 0usize }, Unsupported) }
fn wait_usage(p: own Proc) -> (ProcUsage, err) {
    let (code, wait_error) = wait(p)
    ret (ProcUsage { exit_code: code, peak_memory: 0usize }, wait_error)
}
fn kill(p: Proc) -> err { ret Unsupported }
fn proc_group_spawn(a: *mem.Arena, options: SpawnOptions) -> (ProcGroup, Proc, err) { ret (ProcGroup { raw: 0usize }, Proc { raw: 0usize }, Unsupported) }
fn proc_group_terminate(group: ProcGroup, force: bool) -> err { ret Unsupported }
fn proc_group_close(group: own ProcGroup) -> err { ret ok }
fn file_lock(file: File, exclusive: bool, timeout_ns: i64) -> (FileLock, err) { ret (FileLock { raw: 0usize }, Unsupported) }
fn file_unlock(lock: own FileLock) -> err { ret ok }
// The file's bytes at `offset`, read in pieces and sent; the file's own position stays where it was.
// A socket that takes no more answers the count so far, as sendfile does.
fn send_file(destination: Socket, source: File, offset: u64, count: usize) -> (usize, err) {
    var piece: [32768]u8 = zero
    var iov: [2]u32 = zero
    var taken: [1]u32 = zero
    var total = 0usize
    while total < count {
        var want = count - total
        if want > piece.len { want = piece.len }
        iov[0usize] = u32(mem.address_of(&piece[0usize]))
        iov[1usize] = u32(want)
        taken[0usize] = 0u32
        let status = wasi_fd_pread(fd_of(source.raw), u32(mem.address_of(&iov[0usize])), 1u32, offset + u64(total), u32(mem.address_of(&taken[0usize])))
        if status != 0u32 { ret (total, wasi_error(status)) }
        let got = usize(taken[0usize])
        if got == 0usize { ret (total, ok) }
        var sent_so_far = 0usize
        while sent_so_far < got {
            let (sent, send_error) = socket_send(destination, piece[sent_so_far..got])
            if send_error == WouldBlock { ret (total + sent_so_far, ok) }
            if send_error != ok { ret (total + sent_so_far, send_error) }
            sent_so_far += sent
        }
        total += got
    }
    ret (total, ok)
}
fn signal(which: Signal, handler: fn(Signal)) -> err { ret Unsupported }
fn signal_default(which: Signal) -> err { ret Unsupported }
fn signal_raise(which: Signal) -> err { ret Unsupported }
fn sandbox(policy: *const SandboxPolicy) -> err { ret Unsupported }

fn file_handle(f: File) -> Handle { ret Handle { raw: f.raw } }
fn socket_handle(s: Socket) -> Handle { ret Handle { raw: s.raw } }
// ---- sockets, name resolution and the poller: the `neper_host` imports (D5675, D5676) ---------------------
// The host answers a WASI errno for each; a handle is a number the host counts up from 0x40000000. The
// address record is 32 bytes written byte by byte: family at 0 (0 Ip4, 1 Ip6), port at 2 (u16) and scope
// at 4 (u32), both little-endian, the address at 8.

const HOST_BASE: usize = 1073741824usize
const ADDRESS_RECORD: usize = 32usize
const RESOLVE_MAX: usize = 8usize
const POLL_RECORD: usize = 16usize
const POLL_BATCH: usize = 32usize

type WasiPoller = struct { host: u32 }

// The error for a status; EINPROGRESS and EALREADY are a call that has started and must be asked again.
fn net_error(status: u32) -> err {
    if status == 0u32 { ret ok }
    record_error_detail(i32(status))
    if status == 26u32 || status == 7u32 { ret WouldBlock }
    ret error_of_status(status)
}

fn net_cleanup(status: u32) -> err {
    if status == 0u32 { ret ok }
    record_cleanup_error_detail(i32(status))
    ret error_of_status(status)
}

// A handle no host would have made is the one number that is never open, so the host answers EBADF.
fn host_handle(raw: usize) -> u32 {
    if raw < HOST_BASE || raw > 4294967295usize { ret NO_FD }
    ret u32(raw)
}

fn put_address(record: []u8, address: SocketAddress) {
    var at = 0usize
    while at < ADDRESS_RECORD {
        record[at] = 0u8
        at += 1usize
    }
    if address.family == .Ip6 { record[0usize] = 1u8 }
    record[2usize] = u8(usize(address.port) % 256usize)
    record[3usize] = u8(usize(address.port) / 256usize)
    record[4usize] = u8(address.scope % 256u32)
    record[5usize] = u8(address.scope / 256u32 % 256u32)
    record[6usize] = u8(address.scope / 65536u32 % 256u32)
    record[7usize] = u8(address.scope / 16777216u32)
    at = 0usize
    while at < 16usize {
        record[8usize + at] = address.bytes[at]
        at += 1usize
    }
}

fn get_address(record: []u8, base: usize) -> SocketAddress {
    var address: SocketAddress = zero
    if record[base] == 1u8 { address.family = .Ip6 }
    address.port = u16(usize(record[base + 2usize]) + usize(record[base + 3usize]) * 256usize)
    address.scope = u32(record[base + 4usize]) + u32(record[base + 5usize]) * 256u32 + u32(record[base + 6usize]) * 65536u32 + u32(record[base + 7usize]) * 16777216u32
    var at = 0usize
    while at < 16usize {
        address.bytes[at] = record[base + 8usize + at]
        at += 1usize
    }
    ret address
}

fn socket_open(family: SocketFamily, kind: SocketKind) -> (Socket, err) {
    var made: [1]u32 = zero
    var family_value = 0u32
    if family == .Ip6 { family_value = 1u32 }
    var kind_value = 0u32
    if kind == .Datagram { kind_value = 1u32 }
    let status = host_sock_open(family_value, kind_value, u32(mem.address_of(&made[0usize])))
    if status != 0u32 { ret (Socket { raw: 0usize }, net_error(status)) }
    ret (Socket { raw: usize(made[0usize]) }, ok)
}

fn socket_set_nonblocking(s: Socket, enabled: bool) -> err {
    var flag = 0u32
    if enabled { flag = 1u32 }
    ret net_error(host_sock_set_nonblocking(host_handle(s.raw), flag))
}

fn socket_bind(s: Socket, address: SocketAddress) -> err {
    var record: [32]u8 = zero
    put_address(record[..], address)
    ret net_error(host_sock_bind(host_handle(s.raw), u32(mem.address_of(&record[0usize]))))
}

fn socket_local_address(s: Socket) -> (SocketAddress, err) {
    var record: [32]u8 = zero
    let status = host_sock_local_address(host_handle(s.raw), u32(mem.address_of(&record[0usize])))
    if status != 0u32 {
        var none: SocketAddress = zero
        ret (none, net_error(status))
    }
    ret (get_address(record[..], 0usize), ok)
}

fn socket_listen(s: Socket, backlog: u32) -> err {
    ret net_error(host_sock_listen(host_handle(s.raw), backlog))
}

fn socket_accept(s: Socket) -> (Socket, SocketAddress, err) {
    var made: [1]u32 = zero
    var record: [32]u8 = zero
    var none: SocketAddress = zero
    let status = host_sock_accept(host_handle(s.raw), u32(mem.address_of(&made[0usize])), u32(mem.address_of(&record[0usize])))
    if status != 0u32 { ret (Socket { raw: 0usize }, none, net_error(status)) }
    ret (Socket { raw: usize(made[0usize]) }, get_address(record[..], 0usize), ok)
}

fn socket_connect(s: Socket, address: SocketAddress) -> err {
    var record: [32]u8 = zero
    put_address(record[..], address)
    ret net_error(host_sock_connect(host_handle(s.raw), u32(mem.address_of(&record[0usize]))))
}

fn socket_receive(s: Socket, dst: []u8) -> (usize, err) {
    if dst.len == 0usize { ret (0usize, ok) }
    var taken: [1]u32 = zero
    let status = host_sock_recv(host_handle(s.raw), u32(mem.address_of(&dst[0usize])), u32(dst.len), u32(mem.address_of(&taken[0usize])))
    if status != 0u32 { ret (0usize, net_error(status)) }
    ret (usize(taken[0usize]), ok)
}

fn socket_send(s: Socket, src: []const u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    var sent: [1]u32 = zero
    let status = host_sock_send(host_handle(s.raw), u32(mem.address_of(&src[0usize])), u32(src.len), u32(mem.address_of(&sent[0usize])))
    if status != 0u32 { ret (0usize, net_error(status)) }
    ret (usize(sent[0usize]), ok)
}

fn socket_receive_from(s: Socket, dst: []u8) -> (usize, SocketAddress, err) {
    var peer: SocketAddress = zero
    if dst.len == 0usize { ret (0usize, peer, ok) }
    var taken: [1]u32 = zero
    var record: [32]u8 = zero
    let status = host_sock_recv_from(host_handle(s.raw), u32(mem.address_of(&dst[0usize])), u32(dst.len), u32(mem.address_of(&taken[0usize])), u32(mem.address_of(&record[0usize])))
    if status != 0u32 { ret (0usize, peer, net_error(status)) }
    ret (usize(taken[0usize]), get_address(record[..], 0usize), ok)
}

fn socket_send_to(s: Socket, dst: SocketAddress, src: []const u8) -> (usize, err) {
    var record: [32]u8 = zero
    put_address(record[..], dst)
    var sent: [1]u32 = zero
    var source_address = 0u32
    if src.len != 0usize { source_address = u32(mem.address_of(&src[0usize])) }
    let status = host_sock_send_to(host_handle(s.raw), u32(mem.address_of(&record[0usize])), source_address, u32(src.len), u32(mem.address_of(&sent[0usize])))
    if status != 0u32 { ret (0usize, net_error(status)) }
    ret (usize(sent[0usize]), ok)
}

fn socket_shutdown(s: Socket, how: SocketShutdown) -> err {
    var how_value = 2u32
    if how == .Read { how_value = 0u32 }
    if how == .Write { how_value = 1u32 }
    ret net_error(host_sock_shutdown(host_handle(s.raw), how_value))
}

fn socket_close(s: own Socket) -> err {
    ret net_cleanup(host_sock_close(host_handle(s.raw)))
}

fn socket_resolve(a: *mem.Arena, host: str, port: u16, family: SocketFamily) -> ([]SocketAddress, err) {
    var nothing: []SocketAddress = zero
    if host.len == 0usize { ret (nothing, NotFound) }
    let (results, results_error) = mem.alloc[SocketAddress](a, RESOLVE_MAX)
    if results_error != ok { ret (nothing, OutOfMemory) }
    var records: [256]u8 = zero
    var found: [1]u32 = zero
    var family_value = 0u32
    if family == .Ip6 { family_value = 1u32 }
    let status = host_resolve(address_of_str(host), u32(host.len), u32(port), family_value, u32(mem.address_of(&records[0usize])), u32(RESOLVE_MAX), u32(mem.address_of(&found[0usize])))
    if status != 0u32 { ret (nothing, net_error(status)) }
    let count = usize(found[0usize])
    if count == 0usize || count > RESOLVE_MAX { ret (nothing, NotFound) }
    var at = 0usize
    while at < count {
        results[at] = get_address(records[..], at * ADDRESS_RECORD)
        at += 1usize
    }
    ret (results[0usize..count], ok)
}

// A poller's state is the host's handle for it, kept in the arena it was opened with.
fn poller_open(a: *mem.Arena) -> (Poller, err) {
    var poller: Poller = zero
    let (holder, holder_error) = mem.alloc[WasiPoller](a, 1usize)
    if holder_error != ok { ret (poller, OutOfMemory) }
    var made: [1]u32 = zero
    let status = host_poll_open(u32(mem.address_of(&made[0usize])))
    if status != 0u32 { ret (poller, net_error(status)) }
    holder[0usize].host = made[0usize]
    poller.state = mem.cast[*void](&holder[0usize])
    ret (poller, ok)
}

fn poller_interest(interest: PollInterest) -> u32 {
    var mask = 0u32
    if interest.readable { mask = mask | 1u32 }
    if interest.writable { mask = mask | 2u32 }
    ret mask
}

fn poller_control(p: Poller, operation: u32, handle: Handle, token: usize, interest: PollInterest) -> err {
    let state = mem.cast[*WasiPoller](p.state)
    ret net_error(host_poll_ctl(state.host, operation, host_handle(handle.raw), mem.bitcast[i64](u64(token)), poller_interest(interest)))
}

fn poller_register(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    ret poller_control(p, 0u32, handle, token, interest)
}

fn poller_modify(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err {
    ret poller_control(p, 1u32, handle, token, interest)
}

fn poller_unregister(p: Poller, handle: Handle) -> err {
    var nothing: PollInterest = zero
    ret poller_control(p, 2u32, handle, 0usize, nothing)
}

fn poller_wait(p: Poller, events: []PollEvent, timeout_ns: i64) -> (usize, err) {
    let state = mem.cast[*WasiPoller](p.state)
    if events.len == 0usize { ret (0usize, ok) }
    var capacity = events.len
    if capacity > POLL_BATCH { capacity = POLL_BATCH }
    var raw: [512]u8 = zero
    var count: [1]u32 = zero
    let status = host_poll_wait(state.host, u32(mem.address_of(&raw[0usize])), u32(capacity), timeout_ns, u32(mem.address_of(&count[0usize])))
    if status != 0u32 { ret (0usize, net_error(status)) }
    let ready = usize(count[0usize])
    var at = 0usize
    while at < ready && at < capacity {
        let base = at * POLL_RECORD
        let flags = le32(raw[..], base + 8usize)
        events[at].token = le32(raw[..], base) + le32(raw[..], base + 4usize) * 4294967296usize
        events[at].readable = flags & 1usize != 0usize
        events[at].writable = flags & 2usize != 0usize
        events[at].closed = flags & 4usize != 0usize
        events[at].failed = flags & 8usize != 0usize
        at += 1usize
    }
    ret (at, ok)
}

fn poller_wake(p: Poller) -> err {
    let state = mem.cast[*WasiPoller](p.state)
    ret net_error(host_poll_wake(state.host))
}

fn poller_close(p: own Poller) -> err {
    let state = mem.cast[*WasiPoller](p.state)
    ret net_cleanup(host_poll_close(state.host))
}

fn map_file(f: File, offset: u64, len: usize, writable: bool) -> (Mapping, err) {
    var none: Mapping = zero
    ret (none, Unsupported)
}
fn mapping_bytes(m: Mapping) -> []const u8 {
    var none: []const u8 = zero
    ret none
}
fn mapping_bytes_mut(m: Mapping) -> ([]u8, err) {
    var none: []u8 = zero
    ret (none, Unsupported)
}
fn mapping_flush(m: Mapping) -> err { ret Unsupported }
fn mapping_close(m: own Mapping) -> err { ret ok }

fn watch_open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err) {
    var none: Watch = zero
    ret (none, Unsupported)
}
fn watch_read(a: *mem.Arena, w: Watch, events: []WatchEvent) -> (usize, err) { ret (0usize, Unsupported) }
fn watch_close(w: own Watch) -> err { ret ok }

// The mapping's bytes as the writable region e.fs.mmap hands out; no mapping is ever made here, so
// the region is empty.
fn mapping_region(m: Mapping) -> []u8 {
    var none: []u8 = zero
    ret none
}

// A descriptor number as WASI takes it; a value no descriptor can have (the fixtures close and reuse
// handles on purpose) is the one that is never open, so the host answers EBADF instead of a trap.
fn fd_of(raw: usize) -> u32 {
    if raw > 4294967295usize { ret NO_FD }
    ret u32(raw)
}
