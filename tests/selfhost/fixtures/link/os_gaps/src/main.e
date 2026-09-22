// `e.os`'s three late additions: the zero-copy transfer (#1290), the signal surface
// (#1642) and the one-way process sandbox (#1618).
//
// Two of the three cannot be checked in this process. A sandbox is irreversible by
// definition -- once this process has one it keeps it for the rest of the run -- and a
// signal restored to its default ends the program on the host that has real signals. Both
// are therefore checked in a child, which is this image again with an argument, and what
// is asserted is the child's exit status. Nothing here installs a handler for a signal the
// runner needs, and nothing here raises one at anybody else.
//
// The bytes the transfer moves come from `scripts/algos/../os_gaps/reference.py`: the same
// LCG, and the two FNV-1a checksums below are that script's output.

use e.atomic
use e.io
use e.mem
use e.os

const PAYLOAD_LEN: usize = 1024usize
const WHOLE_SUM: u64 = 9221469956616318527u64
const PARTIAL_SUM: u64 = 2854220288634574164u64
const PARTIAL_FROM: usize = 100usize
const PARTIAL_COUNT: usize = 50usize

// `Atomic[T]` stands as a field rather than as a bare variable, which is the shape
// `link/os_futex` uses.
type Flag = struct { hit: Atomic[u32] }

var signal_flag: Flag

// The handler, which may be entered on a thread of the host's: an atomic store is the
// whole of what it does, and the fixture polls it.
fn on_signal(which: os.Signal) {
    atomic.store(&signal_flag.hit, 1u32, .Release)
}

fn flag_set() -> bool {
    ret atomic.load(&signal_flag.hit, .Acquire) == 1u32
}

// Up to two seconds in ten-millisecond waits. A wait rather than a spin, so a handler that
// runs on another thread is not raced for the processor.
fn wait_for_flag() -> bool {
    var tries = 0usize
    while tries < 200usize {
        if flag_set() { ret true }
        let ignored = os.wait_u32(&signal_flag.hit, 0u32, 10000000i64)
        tries += 1usize
    }
    ret flag_set()
}

fn windows_host() -> bool {
    ret os.NATIVE_SEPARATOR == 92u8
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at_index = 0usize
    while at_index < left.len {
        if left[at_index] != right[at_index] { ret false }
        at_index += 1usize
    }
    ret true
}

fn has_arg(a: *mem.Arena, name: str) -> bool {
    let (arguments, arguments_error) = os.args(a)
    if arguments_error != ok { ret false }
    var at_index = 0usize
    while at_index < arguments.len {
        if same(arguments[at_index], name) { ret true }
        at_index += 1usize
    }
    ret false
}

fn fill_payload(bytes: []u8) {
    var state = 2685821657736338717u64
    var at_index = 0usize
    while at_index < bytes.len {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        bytes[at_index] = u8((state >> 33u32) & 255u64)
        at_index += 1usize
    }
}

fn checksum(bytes: []const u8) -> u64 {
    var value = 14695981039346656037u64
    var at_index = 0usize
    while at_index < bytes.len {
        value = (value ^ u64(bytes[at_index])) *% 1099511628211u64
        at_index += 1usize
    }
    ret value
}

fn write_whole(a: *mem.Arena, path: str, bytes: []const u8) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    let (written, write_error) = os.write(file, bytes)
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    if written != bytes.len { ret os.Failed }
    ret close_error
}

fn loopback() -> os.SocketAddress {
    var address: os.SocketAddress = zero
    address.family = .Ip4
    address.bytes[0usize] = 127u8
    address.bytes[3usize] = 1u8
    ret address
}

// Port zero asks the host to choose, so nothing here collides with whatever else the
// machine is running.
fn bind_ephemeral(s: os.Socket) -> (u16, err) {
    var address = loopback()
    address.port = 0u16
    let bind_error = os.socket_bind(s, address)
    if bind_error != ok { ret (0u16, bind_error) }
    let (local, local_error) = os.socket_local_address(s)
    if local_error != ok { ret (0u16, local_error) }
    if local.port == 0u16 { ret (0u16, os.Failed) }
    ret (local.port, ok)
}

// Everything moved stays well inside a socket's own buffer, so one thread is enough: the
// sending loop never blocks for a reader that is itself.
fn move_all(destination: os.Socket, source: os.File, offset: u64, count: usize) -> (usize, err) {
    var done = 0usize
    var guard = 0usize
    while done < count {
        let (moved, move_error) = os.send_file(destination, source, offset + u64(done), count - done)
        if move_error != ok { ret (done, move_error) }
        done += moved
        guard += 1usize
        if guard > 64usize { ret (done, os.Failed) }
    }
    ret (done, ok)
}

fn take_all(s: os.Socket, into: []u8) -> err {
    var filled = 0usize
    while filled < into.len {
        let (taken, take_error) = os.socket_receive(s, into[filled..])
        if take_error != ok { ret take_error }
        if taken == 0usize { ret os.Failed }
        filled += taken
    }
    ret ok
}

fn child_argv(image: str, tag: str) -> [2]str {
    var argv: [2]str = zero
    argv[0usize] = image
    argv[1usize] = tag
    ret argv
}

fn run_child(a: *mem.Arena, image: str, tag: str) -> (i32, err) {
    var argv = child_argv(image, tag)
    var streams: os.Stdio = zero
    streams.stdin = os.stdin()
    streams.stdout = os.stdout()
    streams.stderr = os.stderr()
    let (child, spawn_error) = os.spawn(a, argv[..], streams)
    if spawn_error != ok { ret (0i32, spawn_error) }
    let (status, wait_error) = os.wait(child)
    ret (status, wait_error)
}

// --- The children. Each one exits 0 when what it is there to prove held.

// A signal taken back is the default restored: on the host with real signals the next
// raise ends this process, which is what the parent asserts; on the host without, nothing
// is delivered at all and the flag stays clear.
fn child_default(a: *mem.Arena) {
    atomic.store(&signal_flag.hit, 0u32, .Release)
    if os.signal(.Interrupt, on_signal) != ok { os.exit(70i32) }
    if os.signal_raise(.Interrupt) != ok { os.exit(71i32) }
    if !wait_for_flag() { os.exit(72i32) }
    if os.signal_default(.Interrupt) != ok { os.exit(73i32) }
    atomic.store(&signal_flag.hit, 0u32, .Release)
    if os.signal_raise(.Interrupt) != ok { os.exit(74i32) }
    if flag_set() { os.exit(75i32) }
    // Reached only where a raise cannot end the process.
    if !windows_host() { os.exit(76i32) }
    os.exit(0i32)
}

// A sandbox that refuses children: the spawn below must not make one.
fn child_deny_children(a: *mem.Arena) {
    var policy: os.SandboxPolicy = zero
    policy.deny_child_processes = true
    if os.sandbox(&policy) != ok { os.exit(80i32) }
    let (image, image_error) = os.executable_path(a)
    if image_error != ok { os.exit(81i32) }
    var argv = child_argv(image, "np-quiet")
    var streams: os.Stdio = zero
    streams.stdin = os.stdin()
    streams.stdout = os.stdout()
    streams.stderr = os.stderr()
    let (grandchild, spawn_error) = os.spawn(a, argv[..], streams)
    if spawn_error == ok {
        let (status, wait_error) = os.wait(grandchild)
        os.exit(82i32)
    }
    os.exit(0i32)
}

// A list of allowed system call numbers, which one host filters by and the other has no
// table to filter at all.
fn child_allow_list(a: *mem.Arena) {
    var allowed: [3]u32 = zero
    // exit_group, exit, getpid -- and nothing that writes.
    allowed[0usize] = 231u32
    allowed[1usize] = 60u32
    allowed[2usize] = 39u32
    var policy: os.SandboxPolicy = zero
    policy.allow_syscalls = allowed[..]
    policy.kill_on_violation = true
    let sandbox_error = os.sandbox(&policy)
    if windows_host() {
        if sandbox_error != os.Unsupported { os.exit(83i32) }
        os.exit(0i32)
    }
    if sandbox_error != ok { os.exit(84i32) }
    // The filter does not name `write`, so this call is what ends the process -- and ends
    // it before anything reaches the stream, so the runner sees nothing.
    let (written, write_error) = os.write(os.stdout(), "np")
    os.exit(85i32)
}

// Dynamic code: a mitigation one host has and the other has no way to say.
fn child_dyncode(a: *mem.Arena) {
    var policy: os.SandboxPolicy = zero
    policy.deny_dynamic_code = true
    let sandbox_error = os.sandbox(&policy)
    if windows_host() {
        if sandbox_error != ok { os.exit(86i32) }
        os.exit(0i32)
    }
    if sandbox_error != os.Unsupported { os.exit(87i32) }
    os.exit(0i32)
}

fn main(a: *mem.Arena) -> err {
    if has_arg(a, "np-quiet") { os.exit(0i32) }
    if has_arg(a, "np-default") { child_default(a) }
    if has_arg(a, "np-deny-children") { child_deny_children(a) }
    if has_arg(a, "np-allow-list") { child_allow_list(a) }
    if has_arg(a, "np-dyncode") { child_dyncode(a) }

    // --- The file the transfer moves, and the reference's two checksums over it.
    let (payload, payload_error) = mem.alloc[u8](a, PAYLOAD_LEN)
    if payload_error != ok { os.exit(10i32) }
    fill_payload(payload)
    if checksum(payload) != WHOLE_SUM { os.exit(11i32) }
    if checksum(payload[PARTIAL_FROM..PARTIAL_FROM + PARTIAL_COUNT]) != PARTIAL_SUM { os.exit(12i32) }

    let leftover = os.remove_file(a, "np-gaps.bin")
    if write_whole(a, "np-gaps.bin", payload) != ok { os.exit(13i32) }
    var read_flags: os.OpenFlags = zero
    read_flags.read = true
    let (source, source_error) = os.open(a, "np-gaps.bin", read_flags)
    if source_error != ok { os.exit(14i32) }

    // --- A real loopback connection to move it over.
    let (listener, listener_error) = os.socket_open(.Ip4, .Stream)
    if listener_error != ok { os.exit(15i32) }
    let (port, listen_bind_error) = bind_ephemeral(listener)
    if listen_bind_error != ok { os.exit(16i32) }
    if os.socket_listen(listener, 4u32) != ok { os.exit(17i32) }
    let (client, client_error) = os.socket_open(.Ip4, .Stream)
    if client_error != ok { os.exit(18i32) }
    var server_address = loopback()
    server_address.port = port
    if os.socket_connect(client, server_address) != ok { os.exit(19i32) }
    let (served, peer, accept_error) = os.socket_accept(listener)
    if accept_error != ok { os.exit(20i32) }

    // --- The whole file, byte for byte.
    let (moved, move_error) = move_all(client, source, 0u64, PAYLOAD_LEN)
    if move_error != ok { os.exit(21i32) }
    if moved != PAYLOAD_LEN { os.exit(22i32) }
    let (received, received_error) = mem.alloc[u8](a, PAYLOAD_LEN)
    if received_error != ok { os.exit(23i32) }
    if take_all(served, received) != ok { os.exit(24i32) }
    var at_index = 0usize
    while at_index < PAYLOAD_LEN {
        if received[at_index] != payload[at_index] { os.exit(25i32) }
        at_index += 1usize
    }
    if checksum(received) != WHOLE_SUM { os.exit(26i32) }

    // --- A count of nothing moves nothing, and says so rather than moving the file.
    let (nothing, nothing_error) = os.send_file(client, source, 0u64, 0usize)
    if nothing_error != ok { os.exit(27i32) }
    if nothing != 0usize { os.exit(28i32) }

    // --- Fifty bytes from the middle: the offset is the file's own, and the transfers
    // before it did not move the descriptor's cursor.
    let (partial, partial_error) = move_all(client, source, u64(PARTIAL_FROM), PARTIAL_COUNT)
    if partial_error != ok { os.exit(29i32) }
    if partial != PARTIAL_COUNT { os.exit(30i32) }
    let (middle, middle_error) = mem.alloc[u8](a, PARTIAL_COUNT)
    if middle_error != ok { os.exit(31i32) }
    if take_all(served, middle) != ok { os.exit(32i32) }
    at_index = 0usize
    while at_index < PARTIAL_COUNT {
        if middle[at_index] != payload[PARTIAL_FROM + at_index] { os.exit(33i32) }
        at_index += 1usize
    }
    if checksum(middle) != PARTIAL_SUM { os.exit(34i32) }

    // --- Past the end is an answer of zero, not a failure: the file has no more.
    let (past, past_error) = os.send_file(client, source, u64(PAYLOAD_LEN) + 16u64, 16usize)
    if past_error != ok { os.exit(35i32) }
    if past != 0usize { os.exit(36i32) }

    if os.socket_close(client) != ok { os.exit(37i32) }
    if os.socket_close(served) != ok { os.exit(38i32) }
    if os.socket_close(listener) != ok { os.exit(39i32) }
    if os.close(source) != ok { os.exit(40i32) }
    let removed = os.remove_file(a, "np-gaps.bin")

    // --- A handler, reached. `Interrupt` is the one signal both hosts deliver without
    // something having faulted first.
    atomic.store(&signal_flag.hit, 0u32, .Release)
    if os.signal(.Interrupt, on_signal) != ok { os.exit(41i32) }
    if os.signal_raise(.Interrupt) != ok { os.exit(42i32) }
    if !wait_for_flag() { os.exit(43i32) }

    // Taken back and installed again: a second raise reaches the handler again, which is
    // what says the first install was not the only one that can work.
    if os.signal_default(.Interrupt) != ok { os.exit(44i32) }
    atomic.store(&signal_flag.hit, 0u32, .Release)
    if os.signal(.Interrupt, on_signal) != ok { os.exit(45i32) }
    if os.signal_raise(.Interrupt) != ok { os.exit(46i32) }
    if !wait_for_flag() { os.exit(47i32) }
    if os.signal_default(.Interrupt) != ok { os.exit(48i32) }

    // --- What cannot be done in this process, done in a child.
    let (image, image_error) = os.executable_path(a)
    if image_error != ok { os.exit(50i32) }

    // The default restored: nothing delivered where a raise is a call, and the end of the
    // process where it is a signal.
    let (default_status, default_error) = run_child(a, image, "np-default")
    if default_error != ok { os.exit(51i32) }
    if windows_host() {
        if default_status != 0i32 { os.exit(52i32) }
    } else {
        if default_status == 0i32 { os.exit(53i32) }
    }

    // A sandbox that refuses children, on both hosts.
    let (children_status, children_error) = run_child(a, image, "np-deny-children")
    if children_error != ok { os.exit(54i32) }
    if children_status != 0i32 { os.exit(55i32) }

    // A list of system call numbers: enforced on one host, `Unsupported` on the other.
    let (list_status, list_error) = run_child(a, image, "np-allow-list")
    if list_error != ok { os.exit(56i32) }
    if windows_host() {
        if list_status != 0i32 { os.exit(57i32) }
    } else {
        if list_status == 0i32 { os.exit(58i32) }
    }

    // Dynamic code: applied on one host, `Unsupported` on the other, and the child asserts
    // whichever it is.
    let (code_status, code_error) = run_child(a, image, "np-dyncode")
    if code_error != ok { os.exit(59i32) }
    if code_status != 0i32 { os.exit(60i32) }

    try io.print("os gaps ok\n")
    ret ok
}
