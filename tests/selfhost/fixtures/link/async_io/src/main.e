// `e.async.io` over loopback TCP: a connect and an accept driven through the loop, a
// write and a read over the sockets' callbacks, progress, wait_any, cancellation before
// a wait, an expired deadline, and take's refusals. A host without a poller ends the
// run happily at `init`, as the async fixture does.

use e.async
use e.async.io as aio
use e.cancel
use e.io
use e.mem
use e.os
use e.time

fn loopback() -> os.SocketAddress {
    var address: os.SocketAddress = zero
    address.family = .Ip4
    address.bytes[0usize] = 127u8
    address.bytes[3usize] = 1u8
    ret address
}

fn socket_read(ctx: *void, dst: []u8) -> (usize, err) {
    let s = mem.cast[*os.Socket](ctx)
    let (got, receive_error) = os.socket_receive(*s, dst)
    ret (got, receive_error)
}

fn socket_write(ctx: *void, src: []const u8) -> (usize, err) {
    let s = mem.cast[*os.Socket](ctx)
    let (put, send_error) = os.socket_send(*s, src)
    ret (put, send_error)
}

fn socket_flush(ctx: *void) -> err {
    let unused = ctx
    ret ok
}

fn same(a: []const u8, b: []const u8) -> bool {
    ret mem.eq[u8](a, b)
}

// The byte operations and the refusals, in their own frame so the pointers the callbacks
// hold end before the sockets are closed.
fn exchange(a: *mem.Arena, loop: *async.Loop, client: os.Socket, server: os.Socket, free: cancel.Control) -> i32 {
    // A write over the client, a read over the server: bytes counted, data intact.
    var client_socket = client
    var server_socket = server
    let sink = io.Writer { ctx: mem.cast[*void](&client_socket), write: socket_write, flush: socket_flush }
    let source = io.Reader { ctx: mem.cast[*void](&server_socket), read: socket_read }
    let (writing, write_error) = aio.write(a, loop, sink, "hello over the loop", free)
    if write_error != ok || aio.state[usize](&writing) != .Pending { ret 22i32 }
    var write_op = writing
    let (written, written_error) = aio.wait[usize](loop, &write_op)
    if written_error != ok || written != 19usize || aio.progress[usize](&write_op).bytes != 19u64 || !aio.progress[usize](&write_op).known { ret 23i32 }
    var buffer: [64]u8 = zero
    let (reading, read_error) = aio.read(a, loop, source, buffer[0..], free)
    if read_error != ok { ret 24i32 }
    var read_op = reading
    var slice: [1]aio.AnyOp = [1]aio.AnyOp{ aio.erase[usize](&read_op) }
    let (which, any_done, any_error) = aio.wait_any(loop, slice[0..], time.seconds(5i64))
    if any_error != ok || !any_done || which != 0usize { ret 25i32 }
    let (got, got_error) = aio.take[usize](&read_op)
    if got_error != ok || got != 19usize || !same(buffer[0..19usize], "hello over the loop") { ret 26i32 }

    // Cancelled before it runs; timed out by a deadline already past; taking a pending
    // operation refuses.
    let (idle, idle_error) = aio.read(a, loop, source, buffer[0..], free)
    if idle_error != ok { ret 27i32 }
    var idle_op = idle
    let (_, pending_take) = aio.take[usize](&idle_op)
    if pending_take != aio.Closed { ret 28i32 }
    let (cancelled_now, cancel_error) = aio.cancel[usize](&idle_op)
    let (cancelled_again, cancel_again_error) = aio.cancel[usize](&idle_op)
    if cancel_error != ok || !cancelled_now || cancel_again_error != ok || cancelled_again || aio.state[usize](&idle_op) != .Cancelled { ret 29i32 }
    let (_, cancelled_take) = aio.take[usize](&idle_op)
    if cancelled_take != aio.Cancelled { ret 30i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    let (loop0, loop_error) = async.init(a)
    if loop_error == async.Unsupported { ret ok }
    if loop_error != ok { os.exit(10i32) }
    var loop = loop0
    var token = cancel.token()
    let free = cancel.Control { token: &token, deadline: time.Instant { nanos: 0i64 }, has_deadline: false }

    // A listener on an ephemeral port; an accept operation registered on the loop.
    let (listener, listener_error) = os.socket_open(.Ip4, .Stream)
    if listener_error != ok { os.exit(11i32) }
    var address = loopback()
    address.port = 0u16
    if os.socket_bind(listener, address) != ok || os.socket_listen(listener, 4u32) != ok { os.exit(12i32) }
    let (local, local_error) = os.socket_local_address(listener)
    if local_error != ok || local.port == 0u16 { os.exit(13i32) }
    let (accepting, accept_error) = aio.accept(a, &loop, listener, free)
    if accept_error != ok || aio.state[os.Socket](&accepting) != .Pending { os.exit(14i32) }
    var accept_op = accepting

    // A client connects through the loop; the accept then completes.
    let (client, client_error) = os.socket_open(.Ip4, .Stream)
    if client_error != ok { os.exit(15i32) }
    var goal = loopback()
    goal.port = local.port
    let (connecting, connect_error) = aio.connect(a, &loop, client, goal, free)
    if connect_error != ok { os.exit(16i32) }
    var connect_op = connecting
    let (connected, connected_error) = aio.wait[bool](&loop, &connect_op)
    if connected_error != ok || !connected || aio.state[bool](&connect_op) != .Succeeded { os.exit(17i32) }
    let (server, server_error) = aio.wait[os.Socket](&loop, &accept_op)
    if server_error != ok { os.exit(18i32) }
    if aio.state[os.Socket](&accept_op) != .Succeeded { os.exit(18i32) }
    if os.socket_set_nonblocking(server, false) != ok || os.socket_set_nonblocking(client, false) != ok { os.exit(19i32) }
    let (_, taken_twice) = aio.take[os.Socket](&accept_op)
    if taken_twice != aio.Closed { os.exit(20i32) }
    if aio.progress[os.Socket](&accept_op).known { os.exit(21i32) }

    let exchange_code = exchange(a, &loop, client, server, free)
    if exchange_code != 0i32 { os.exit(exchange_code) }
    let (now, now_error) = time.monotonic()
    if now_error != ok { os.exit(31i32) }
    let expired = cancel.Control { token: &token, deadline: now, has_deadline: true }
    let (late_accept, late_error) = aio.accept(a, &loop, listener, expired)
    if late_error != ok { os.exit(32i32) }
    var late_op = late_accept
    let (_, timed_out) = aio.wait[os.Socket](&loop, &late_op)
    if timed_out != aio.Timeout || aio.state[os.Socket](&late_op) != .TimedOut { os.exit(33i32) }
    let (_, second_take) = aio.take[os.Socket](&late_op)
    if second_take != aio.Closed { os.exit(34i32) }

    if os.socket_close(server) != ok || os.socket_close(client) != ok || os.socket_close(listener) != ok { os.exit(35i32) }
    if async.close(&loop) != ok { os.exit(36i32) }
    try io.print("async io ok\n")
    ret ok
}
