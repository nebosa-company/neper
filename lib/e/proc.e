// Child processes: a `Command` is what to run, a `Child` is one that is running, and `output`
// is the whole conversation with one -- spawn, collect, reap -- for the caller that wants
// nothing but what it printed.
//
// Everything here is `e.os` with the shape a caller wants rather than the shape the host has:
// a program and its arguments rather than an argv, three streams rather than a `Stdio`, and
// the pipes that `spawn_piped` opens closed on the side that is not the caller's. The one
// thing this file adds that `e.os` does not have is the second reader. A child that writes to
// both of its streams will fill one pipe while the parent is blocked on the other, and then
// neither moves; so `output` drains them on two threads, which is the only way two pipes can
// be read at once without a poller that both hosts have for pipes.
//
// `run` and `RunOptions` wait on `e.cancel` (a `Control` is what bounds the running work) and
// are not here; `Outcome` and `RunResult` are, because they are what it will answer with and
// nothing in them waits on anything.

use e.mem
use e.os

type Command = struct {
    program: str,
    args: []const str,
    env: []const str,
    inherit_env: bool,
    cwd: str,
}

type Streams = struct {
    stdin: os.File,
    stdout: os.File,
    stderr: os.File,
}

type Child = struct {
    process: os.Proc,
    streams: Streams,
}

type Output = struct {
    status: i32,
    stdout: []u8,
    stderr: []u8,
}

error TooLarge

type Outcome = enum u8 { Exited, Cancelled, TimedOut, OutputLimit }

type RunResult = struct {
    outcome: Outcome,
    status: i32,
    status_known: bool,
    stdout: []const u8,
    stderr: []const u8,
    stdout_bytes: u64,
    stderr_bytes: u64,
    truncated: bool,
}

// Zero means the default, as it does everywhere in `lib/e`: a caller who has not thought about
// the bound is asking for a reasonable one, not for none. A megabyte per stream is far past what
// a program's output is for and far short of what a runaway one produces.
const DEFAULT_OUTPUT_LIMIT: usize = 1048576usize
// The draining thread reads into a buffer that is already allocated and calls nothing that
// needs more, so its stack is small.
const DRAIN_STACK: usize = 262144usize

// What one stream is drained into, by whichever thread is reading it. `overflowed` is set the
// moment a byte arrives that the buffer has no room for, and the child is ended then rather
// than read to exhaustion: a program producing more than it was allowed is not one to wait on.
type Drain = struct {
    file: os.File,
    process: os.Proc,
    buffer: []u8,
    filled: usize,
    overflowed: bool,
    failure: err,
}

// The host's argv is the program followed by its arguments, which `Command` keeps apart because
// the program is the one the caller always has and the arguments are the part that varies.
fn argv_of(a: *mem.Arena, command: Command) -> ([]str, err) {
    let (argv, allocation_error) = mem.alloc[str](a, command.args.len + 1usize)
    if allocation_error != ok {
        var none: []str = zero
        ret (none, allocation_error)
    }
    argv[0usize] = command.program
    var at = 0usize
    while at < command.args.len {
        argv[at + 1usize] = command.args[at]
        at += 1usize
    }
    ret (argv, ok)
}

fn options_of(a: *mem.Arena, command: Command, streams: Streams) -> (os.SpawnOptions, err) {
    var options: os.SpawnOptions = zero
    let (argv, argv_error) = argv_of(a, command)
    if argv_error != ok { ret (options, argv_error) }
    options.argv = argv
    options.env = command.env
    options.inherit_env = command.inherit_env
    options.cwd = command.cwd
    // A stream left zero is the parent's own, which is what `e.os` says a zero `Stdio` field
    // means too -- so the three go across as they are.
    options.stdio.stdin = streams.stdin
    options.stdio.stdout = streams.stdout
    options.stdio.stderr = streams.stderr
    ret (options, ok)
}

fn spawn(a: *mem.Arena, command: Command, streams: Streams) -> (Child, err) {
    var unread: os.ErrorDetail = zero
    let (child, spawn_error) = spawn_in(a, command, streams, &unread, false)
    ret (child, spawn_error)
}

// The checked path with the caller's detail (D480, H07), as `e.os` and `e.fs` have
// it: the host's account of the failing call is written into `detail` at that call,
// before the closes on the way out, naming the `e.os` operation -- `spawn` with the
// program as its subject, `pipe` -- and the same `err` comes back as from the plain
// form. On success `detail` is not written. A host that forks first cannot report a
// program it could not run as the spawn's failure (the child exits 127), and then
// nothing is written either.
fn spawn_detail(a: *mem.Arena, command: Command, streams: Streams, detail: *os.ErrorDetail) -> (Child, err) {
    let (child, spawn_error) = spawn_in(a, command, streams, detail, true)
    ret (child, spawn_error)
}

fn spawn_in(a: *mem.Arena, command: Command, streams: Streams, detail: *os.ErrorDetail, record: bool) -> (Child, err) {
    var child: Child = zero
    let (options, options_error) = options_of(a, command, streams)
    if options_error != ok { ret (child, options_error) }
    let (process, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok {
        if record { *detail = os.last_error_detail("spawn", command.program) }
        ret (child, spawn_error)
    }
    child.process = process
    child.streams = streams
    ret (child, ok)
}

// Three pipes, the child on one side of each and the caller on the other. The child's ends are
// closed here once it has them: a write end the parent still held would keep the child's stdout
// open after the child was gone, and the caller's read would never see the end of it.
fn spawn_piped(a: *mem.Arena, command: Command) -> (Child, err) {
    var unread: os.ErrorDetail = zero
    let (child, spawn_error) = spawn_piped_in(a, command, &unread, false)
    ret (child, spawn_error)
}

fn spawn_piped_detail(a: *mem.Arena, command: Command, detail: *os.ErrorDetail) -> (Child, err) {
    let (child, spawn_error) = spawn_piped_in(a, command, detail, true)
    ret (child, spawn_error)
}

fn spawn_piped_in(a: *mem.Arena, command: Command, detail: *os.ErrorDetail, record: bool) -> (Child, err) {
    var child: Child = zero
    let (in_read, in_write, in_error) = os.pipe()
    if in_error != ok {
        if record { *detail = os.last_error_detail("pipe", command.program) }
        ret (child, in_error)
    }
    let (out_read, out_write, out_error) = os.pipe()
    if out_error != ok {
        if record { *detail = os.last_error_detail("pipe", command.program) }
        let closed_in_read = os.close(in_read)
        let closed_in_write = os.close(in_write)
        ret (child, out_error)
    }
    let (err_read, err_write, err_error) = os.pipe()
    if err_error != ok {
        if record { *detail = os.last_error_detail("pipe", command.program) }
        let closed_in_read = os.close(in_read)
        let closed_in_write = os.close(in_write)
        let closed_out_read = os.close(out_read)
        let closed_out_write = os.close(out_write)
        ret (child, err_error)
    }
    var theirs: Streams = zero
    theirs.stdin = in_read
    theirs.stdout = out_write
    theirs.stderr = err_write
    let (options, options_error) = options_of(a, command, theirs)
    var failure = options_error
    var process: os.Proc = zero
    if failure == ok {
        let (started, spawn_error) = os.spawn_with_options(a, options)
        process = started
        failure = spawn_error
        if spawn_error != ok && record { *detail = os.last_error_detail("spawn", command.program) }
    }
    // Whether or not the child exists, its ends are not the caller's to keep: they
    // went into `theirs`, and are closed from there.
    let closed_in_read = os.close(theirs.stdin)
    let closed_out_write = os.close(theirs.stdout)
    let closed_err_write = os.close(theirs.stderr)
    if failure != ok {
        let closed_in_write = os.close(in_write)
        let closed_out_read = os.close(out_read)
        let closed_err_read = os.close(err_read)
        ret (child, failure)
    }
    child.process = process
    child.streams.stdin = in_write
    child.streams.stdout = out_read
    child.streams.stderr = err_read
    ret (child, ok)
}

fn wait(child: *Child) -> (i32, err) {
    let (status, wait_error) = os.wait(child.process)
    ret (status, wait_error)
}

fn kill(child: *Child) -> err {
    ret os.kill(child.process)
}

// One stream to its end, or to the limit. Runs on whichever thread was given it; touches only
// what it was given, which is what lets two of these run at once over one arena that neither
// allocates from.
fn drain(d: *Drain) {
    while true {
        if d.filled == d.buffer.len {
            // Room is gone, and the next byte decides: the end of the stream is exactly the
            // limit, which is allowed; anything more is over it.
            var probe: [1]u8 = zero
            let (count, read_error) = os.read(d.file, probe[..])
            if read_error != ok {
                d.failure = read_error
                ret
            }
            if count == 0usize { ret }
            d.overflowed = true
            let ended = os.kill(d.process)
            ret
        }
        let (count, read_error) = os.read(d.file, d.buffer[d.filled..])
        if read_error != ok {
            d.failure = read_error
            ret
        }
        if count == 0usize { ret }
        d.filled += count
    }
}

// Run to completion and bring back what it printed. The child is always reaped before this
// returns, whatever happened -- a process left behind is worse than any error.
fn output(a: *mem.Arena, command: Command, limit: usize) -> (Output, err) {
    var unread: os.ErrorDetail = zero
    let (result, output_error) = output_in(a, command, limit, &unread, false)
    ret (result, output_error)
}

// The spawn's detail, as `spawn_piped_detail` writes it; what the child then did is
// its status and its streams, which are the answer, not a failure.
fn output_detail(a: *mem.Arena, command: Command, limit: usize, detail: *os.ErrorDetail) -> (Output, err) {
    let (result, output_error) = output_in(a, command, limit, detail, true)
    ret (result, output_error)
}

fn output_in(a: *mem.Arena, command: Command, limit: usize, detail: *os.ErrorDetail, record: bool) -> (Output, err) {
    var result: Output = zero
    var bound = limit
    if bound == 0usize { bound = DEFAULT_OUTPUT_LIMIT }
    let (child, spawn_error) = spawn_piped_in(a, command, detail, record)
    if spawn_error != ok { ret (result, spawn_error) }
    // Nothing is sent, so the child sees the end of its input at once rather than waiting on it.
    let closed_stdin = os.close(child.streams.stdin)
    let (out_buffer, out_error) = mem.alloc[u8](a, bound)
    let (err_buffer, err_error) = mem.alloc[u8](a, bound)
    var failure = out_error
    if failure == ok { failure = err_error }
    var out_drain: Drain = zero
    var err_drain: Drain = zero
    if failure == ok {
        out_drain.file = child.streams.stdout
        out_drain.process = child.process
        out_drain.buffer = out_buffer
        err_drain.file = child.streams.stderr
        err_drain.process = child.process
        err_drain.buffer = err_buffer
        let (worker, thread_error) = os.thread_create[Drain](drain, &err_drain, DRAIN_STACK)
        if thread_error == ok {
            drain(&out_drain)
            let joined = os.thread_join(worker)
        } else {
            failure = thread_error
        }
    }
    if failure != ok {
        // The child was never read, so it may be blocked on a full pipe; ending it is what lets
        // the wait below return.
        let ended = os.kill(child.process)
    }
    let closed_stdout = os.close(child.streams.stdout)
    let closed_stderr = os.close(child.streams.stderr)
    let (status, wait_error) = os.wait(child.process)
    if failure != ok { ret (result, failure) }
    if wait_error != ok { ret (result, wait_error) }
    if out_drain.failure != ok { ret (result, out_drain.failure) }
    if err_drain.failure != ok { ret (result, err_drain.failure) }
    if out_drain.overflowed || err_drain.overflowed { ret (result, TooLarge) }
    result.status = status
    result.stdout = out_buffer[0usize..out_drain.filled]
    result.stderr = err_buffer[0usize..err_drain.filled]
    ret (result, ok)
}
