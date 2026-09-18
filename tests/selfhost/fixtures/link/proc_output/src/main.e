// `e.proc` against a real child, which is this program again: the only image a fixture can be
// sure exists. Each mode the child is asked for is one thing a parent might need from it --
// output on both streams, a status, an echo of what it was sent, more output than allowed --
// and the parent checks each through the module rather than through `e.os`.

use e.cancel
use e.mem
use e.os
use e.str
use e.proc
use e.time

// The child's `speak` mode writes its stderr in one piece large enough to fill a pipe, so
// that a parent reading stdout first, and only then stderr, would wait forever: it is what
// proves `output` reads both at once.
const LOUD: usize = 262144usize

fn mode(a: *mem.Arena) -> str {
    let (arguments, arguments_error) = os.args(a)
    if arguments_error != ok { ret "" }
    if arguments.len < 2usize { ret "" }
    ret arguments[1usize]
}

fn child(a: *mem.Arena, what: str) {
    if str.eq(what, "np-speak") {
        let (_, out_error) = os.write(os.stdout(), "out-line")
        let (noise, noise_error) = mem.alloc[u8](a, LOUD)
        if noise_error != ok { os.exit(99i32) }
        var at = 0usize
        while at < LOUD {
            noise[at] = 101u8
            at += 1usize
        }
        var written = 0usize
        while written < LOUD {
            let (count, err_error) = os.write(os.stderr(), noise[written..])
            if err_error != ok { os.exit(98i32) }
            written += count
        }
        os.exit(0i32)
    }
    if str.eq(what, "np-status") {
        os.exit(42i32)
    }
    if str.eq(what, "np-eight") {
        let (_, eight_error) = os.write(os.stdout(), "out-line")
        os.exit(0i32)
    }
    if str.eq(what, "np-echo") {
        var buffer: [64]u8 = zero
        var filled = 0usize
        while filled < buffer.len {
            let (count, read_error) = os.read(os.stdin(), buffer[filled..])
            if read_error != ok { os.exit(97i32) }
            if count == 0usize { break }
            filled += count
        }
        let (_, echo_error) = os.write(os.stdout(), buffer[0usize..filled])
        os.exit(0i32)
    }
    if str.eq(what, "np-flood") {
        var page: [4096]u8 = zero
        var at = 0usize
        while at < page.len {
            page[at] = 102u8
            at += 1usize
        }
        // Far more than any limit the parent sets, and it never stops on its own.
        while true {
            let (_, flood_error) = os.write(os.stdout(), page[..])
            if flood_error != ok { os.exit(0i32) }
        }
    }
    if str.eq(what, "np-hang") {
        while true {}
    }
    os.exit(96i32)
}

fn main(a: *mem.Arena) -> err {
    let what = mode(a)
    if what.len != 0usize { child(a, what) }

    let (image, image_error) = os.executable_path(a)
    if image_error != ok { os.exit(10i32) }
    var command: proc.Command = zero
    command.program = image
    command.inherit_env = true
    var args: [1]str = zero

    // --- `output`: both streams, read at once. The child fills its stderr pipe before its
    // stdout is drained, so a parent that read one to the end and then the other would never
    // return from here.
    args[0usize] = "np-speak"
    command.args = args[..]
    let (spoken, spoken_error) = proc.output(a, command, 0usize)
    if spoken_error != ok { os.exit(20i32) }
    if spoken.status != 0i32 { os.exit(21i32) }
    if !str.eq(spoken.stdout, "out-line") { os.exit(22i32) }
    if spoken.stderr.len != LOUD { os.exit(23i32) }
    if spoken.stderr[0usize] != 101u8 || spoken.stderr[LOUD - 1usize] != 101u8 { os.exit(24i32) }

    // --- The status is the child's own, and a child that printed nothing has empty streams
    // rather than absent ones.
    args[0usize] = "np-status"
    command.args = args[..]
    let (status_only, status_error) = proc.output(a, command, 0usize)
    if status_error != ok { os.exit(30i32) }
    if status_only.status != 42i32 { os.exit(31i32) }
    if status_only.stdout.len != 0usize { os.exit(32i32) }
    if status_only.stderr.len != 0usize { os.exit(33i32) }

    // --- More output than allowed is `TooLarge`, and the child is ended rather than waited on:
    // this one would never stop on its own, so the fixture returning at all is the proof.
    args[0usize] = "np-flood"
    command.args = args[..]
    let (_, flood_error) = proc.output(a, command, 8192usize)
    if flood_error != proc.TooLarge { os.exit(40i32) }
    // Exactly the limit is allowed and one byte past it is not: `out-line` is eight bytes.
    args[0usize] = "np-eight"
    command.args = args[..]
    let (exact, exact_error) = proc.output(a, command, 8usize)
    if exact_error != ok { os.exit(41i32) }
    if !str.eq(exact.stdout, "out-line") { os.exit(42i32) }
    let (_, short_error) = proc.output(a, command, 7usize)
    if short_error != proc.TooLarge { os.exit(43i32) }
    args[0usize] = "np-echo"
    command.args = args[..]

    // --- `spawn_piped`: the caller holds the other end of each stream. What is written to the
    // child's stdin comes back on its stdout, once its stdin is closed so it knows the end.
    let (piped, piped_error) = proc.spawn_piped(a, command)
    if piped_error != ok { os.exit(50i32) }
    var running = piped
    let (sent, send_error) = os.write(running.streams.stdin, "ping")
    if send_error != ok { os.exit(51i32) }
    if sent != 4usize { os.exit(52i32) }
    if os.close(running.streams.stdin) != ok { os.exit(53i32) }
    var reply: [16]u8 = zero
    var got = 0usize
    while got < reply.len {
        let (count, reply_error) = os.read(running.streams.stdout, reply[got..])
        if reply_error != ok { os.exit(54i32) }
        if count == 0usize { break }
        got += count
    }
    if !str.eq(reply[0usize..got], "ping") { os.exit(55i32) }
    let (echo_status, echo_wait) = proc.wait(&running)
    if echo_wait != ok { os.exit(56i32) }
    if echo_status != 0i32 { os.exit(57i32) }
    if os.close(running.streams.stdout) != ok { os.exit(58i32) }
    if os.close(running.streams.stderr) != ok { os.exit(59i32) }

    // --- `spawn` with the caller's own streams: a zero stream is the parent's, and only the
    // one set is redirected. The child's stdout goes to a pipe the caller made; its stderr and
    // stdin stay the parent's.
    let (reading, writing, pipe_error) = os.pipe()
    if pipe_error != ok { os.exit(60i32) }
    var streams: proc.Streams = zero
    streams.stdout = writing
    args[0usize] = "np-status"
    command.args = args[..]
    let (plain, plain_error) = proc.spawn(a, command, streams)
    if plain_error != ok { os.exit(61i32) }
    var plain_child = plain
    if os.close(streams.stdout) != ok { os.exit(62i32) }
    var nothing: [8]u8 = zero
    let (silent, silent_error) = os.read(reading, nothing[..])
    if silent_error != ok { os.exit(63i32) }
    if silent != 0usize { os.exit(64i32) }
    if os.close(reading) != ok { os.exit(65i32) }
    let (plain_status, plain_wait) = proc.wait(&plain_child)
    if plain_wait != ok { os.exit(66i32) }
    if plain_status != 42i32 { os.exit(67i32) }

    // --- `kill` ends a child that would otherwise run on; the status is a failure on both
    // hosts but not the same number, so only "not zero" is portable.
    args[0usize] = "np-flood"
    command.args = args[..]
    let (flooding, flooding_error) = proc.spawn_piped(a, command)
    if flooding_error != ok { os.exit(70i32) }
    var doomed = flooding
    if proc.kill(&doomed) != ok { os.exit(71i32) }
    let (killed_status, killed_wait) = proc.wait(&doomed)
    if killed_wait != ok { os.exit(72i32) }
    if killed_status == 0i32 { os.exit(73i32) }
    let closed_in = os.close(doomed.streams.stdin)
    let closed_out = os.close(doomed.streams.stdout)
    let closed_err = os.close(doomed.streams.stderr)

    // --- A program that does not exist. The two hosts answer differently and `e.os` chose not
    // to hide it: Windows refuses at `CreateProcess`, so it is the spawn's error; Linux forks
    // first and the `execve` fails in the child, which exits 127 -- there is nothing else to
    // report it to. What both promise is that it is never a success with a status of zero.
    command.program = "np-no-such-program-anywhere"
    args[0usize] = "np-status"
    command.args = args[..]
    let (missing, missing_error) = proc.output(a, command, 0usize)
    if missing_error == ok && missing.status == 0i32 { os.exit(80i32) }
    if missing_error == ok && missing.status != 127i32 { os.exit(81i32) }
    // The same in the `_detail` form (D480, H07): where the spawn is the failure,
    // the detail names it and the program; where the child exits 127, nothing is written.
    var detail: os.ErrorDetail = zero
    let (missing_again, missing_again_error) = proc.output_detail(a, command, 0usize, &detail)
    if missing_again_error != missing_error { os.exit(82i32) }
    if missing_again_error != ok && (detail.kind != .NotFound || detail.native_code == 0i32 || !mem.eq[u8](
        detail.operation,
        "spawn",
    ) || !mem.eq[u8](detail.subject, "np-no-such-program-anywhere")) { os.exit(83i32) }
    if missing_again_error == ok && (detail.native_code != 0i32 || missing_again.status != 127i32) { os.exit(
        84i32,
    ) }

    // --- `run`: a nonzero child status is an ordinary exited outcome, with the
    // status explicitly known rather than turned into an infrastructure error.
    command.program = image
    args[0usize] = "np-status"
    command.args = args[..]
    var run_options: proc.RunOptions = zero
    let (exited, exited_error) = proc.run(a, command, run_options)
    if exited_error != ok { os.exit(90i32) }
    if exited.outcome != .Exited || !exited.status_known || exited.status != 42i32 { os.exit(91i32) }
    if exited.stdout_bytes != 0u64 || exited.stderr_bytes != 0u64 || exited.truncated { os.exit(
        92i32,
    ) }

    // Independent limits admit exactly the bounded output on each stream.
    args[0usize] = "np-speak"
    command.args = args[..]
    run_options.stdout_limit = 8usize
    run_options.stderr_limit = LOUD
    let (bounded, bounded_error) = proc.run(a, command, run_options)
    if bounded_error != ok || bounded.outcome != .Exited { os.exit(93i32) }
    if !str.eq(bounded.stdout, "out-line") || bounded.stderr.len != LOUD { os.exit(94i32) }
    if bounded.stdout_bytes != 8u64 || bounded.stderr_bytes != u64(LOUD) || bounded.truncated { os.exit(
        95i32,
    ) }

    // One byte beyond a stream's limit retains the prefix, records observed bytes,
    // ends the child and reports an outcome rather than the legacy `TooLarge` error.
    args[0usize] = "np-flood"
    command.args = args[..]
    run_options.stdout_limit = 8192usize
    run_options.stderr_limit = 16usize
    let (limited, limited_error) = proc.run(a, command, run_options)
    if limited_error != ok || limited.outcome != .OutputLimit { os.exit(96i32) }
    if !limited.status_known || !limited.truncated || limited.stdout.len != 8192usize { os.exit(
        97i32,
    ) }
    if limited.stdout_bytes != 8193u64 || limited.stderr_bytes != 0u64 { os.exit(98i32) }

    // Already-stopped controls do not start a child. Cancellation wins when both
    // cancellation and an expired deadline are visible at the same observation.
    var token = cancel.token()
    cancel.request(&token)
    let (now, now_error) = time.monotonic()
    if now_error != ok { os.exit(99i32) }
    var cancel_options: proc.RunOptions = zero
    cancel_options.control.token = &token
    cancel_options.control.deadline = now
    cancel_options.control.has_deadline = true
    let (cancelled, cancelled_error) = proc.run(a, command, cancel_options)
    if cancelled_error != ok || cancelled.outcome != .Cancelled || cancelled.status_known { os.exit(
        100i32,
    ) }

    // A live deadline interrupts a silent child. The contained form establishes the
    // host process group/job before the child runs and closes it after reaping.
    args[0usize] = "np-hang"
    command.args = args[..]
    let (started, started_error) = time.monotonic()
    if started_error != ok { os.exit(101i32) }
    var timeout_options: proc.RunOptions = zero
    timeout_options.control.deadline = time.instant_add(started, time.millis(10i64))
    timeout_options.control.has_deadline = true
    timeout_options.contain_tree = true
    let (timed, timed_error) = proc.run(a, command, timeout_options)
    if timed_error != ok || timed.outcome != .TimedOut || !timed.status_known { os.exit(102i32) }
    if timed.truncated || timed.stdout_bytes != 0u64 || timed.stderr_bytes != 0u64 { os.exit(103i32) }

    // Invalid grace is rejected before any child is started.
    var invalid_options: proc.RunOptions = zero
    invalid_options.terminate_grace = time.Duration { nanos: -1i64 }
    let (_, grace_error) = proc.run(a, command, invalid_options)
    if grace_error != time.Invalid { os.exit(104i32) }
    ret ok
}
