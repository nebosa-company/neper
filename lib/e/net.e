// Portable network values and blocking socket transport over the reviewed e.os fence.
// Address parsing/formatting stays pure; resolution and transfer map host details into
// the smaller portable error set. Deadline-aware operations are the remaining slice.

use e.io
use e.cancel
use e.mem
use e.os
use e.time

type Socket = os.Socket
type Ip4 = struct { bytes: [4]u8 }
type Ip6 = struct { bytes: [16]u8, scope: u32 }
type Address = union enum u8 { Ip4: Ip4, Ip6: Ip6 }
type Endpoint = struct { address: Address, port: u16 }
type Family = enum u8 { Any, Ip4, Ip6 }
type Shutdown = enum u8 { Read, Write, Both }

error NotFound
error Refused
error Reset
error Timeout
error AddressInUse
error Unreachable
error Failed

fn hex_value(byte: u8) -> (usize, bool) {
    if byte >= 48u8 && byte <= 57u8 { ret (usize(byte - 48u8), true) }
    if byte >= 97u8 && byte <= 102u8 { ret (usize(byte - 97u8) + 10usize, true) }
    if byte >= 65u8 && byte <= 70u8 { ret (usize(byte - 65u8) + 10usize, true) }
    ret (0usize, false)
}

fn parse_ip4(text: str) -> (Ip4, bool) {
    var address: Ip4 = zero
    var at = 0usize
    var part = 0usize
    while part < 4usize {
        let first = at
        var value = 0usize
        while at < text.len && text[at] >= 48u8 && text[at] <= 57u8 {
            if at - first == 3usize { ret (address, false) }
            value = value * 10usize + usize(text[at] - 48u8)
            if value > 255usize { ret (address, false) }
            at += 1usize
        }
        let digits = at - first
        if digits == 0usize || digits > 3usize || value > 255usize { ret (address, false) }
        // Leading zeroes have historically meant octal to some APIs. Refuse the
        // ambiguity instead of letting two spellings denote different addresses.
        if digits > 1usize && text[first] == 48u8 { ret (address, false) }
        address.bytes[part] = u8(value)
        part += 1usize
        if part < 4usize {
            if at >= text.len || text[at] != 46u8 { ret (address, false) }
            at += 1usize
        }
    }
    if at != text.len { ret (address, false) }
    ret (address, true)
}

fn parse_scope(text: str) -> (str, u32, bool) {
    var percent = text.len
    var at = 0usize
    while at < text.len {
        if text[at] == 37u8 {
            if percent != text.len { ret ("", 0u32, false) }
            percent = at
        }
        at += 1usize
    }
    if percent == text.len { ret (text, 0u32, true) }
    if percent == 0usize || percent + 1usize == text.len { ret ("", 0u32, false) }
    var scope = 0u64
    at = percent + 1usize
    while at < text.len {
        let byte = text[at]
        if byte < 48u8 || byte > 57u8 { ret ("", 0u32, false) }
        let digit = u64(byte - 48u8)
        if scope > 429496729u64 || (scope == 429496729u64 && digit > 5u64) { ret ("", 0u32, false) }
        scope = scope * 10u64 + digit
        at += 1usize
    }
    ret (text[..percent], u32(scope), true)
}

fn parse_ip6(source: str) -> (Ip6, bool) {
    var address: Ip6 = zero
    let (text, scope, scope_ok) = parse_scope(source)
    if !scope_ok { ret (address, false) }
    address.scope = scope
    var head: [16]u8 = zero
    var tail: [16]u8 = zero
    var head_len = 0usize
    var tail_len = 0usize
    var compressed = false
    var at = 0usize
    if text.len < 2usize { ret (address, false) }
    if text[0usize] == 58u8 {
        if text[1usize] != 58u8 { ret (address, false) }
        compressed = true
        at = 2usize
        if at == text.len { ret (address, true) }
    }
    while at < text.len {
        var value = 0usize
        var digits = 0usize
        var scan = at
        while scan < text.len {
            let (nibble, is_hex) = hex_value(text[scan])
            if !is_hex { break }
            if digits == 4usize { ret (address, false) }
            value = value * 16usize + nibble
            digits += 1usize
            scan += 1usize
        }
        if digits == 0usize || digits > 4usize { ret (address, false) }
        if scan < text.len && text[scan] == 46u8 {
            let (embedded, embedded_ok) = parse_ip4(text[at..])
            if !embedded_ok { ret (address, false) }
            var quad = 0usize
            while quad < 4usize {
                if compressed {
                    if tail_len == 16usize { ret (address, false) }
                    tail[tail_len] = embedded.bytes[quad]
                    tail_len += 1usize
                } else {
                    if head_len == 16usize { ret (address, false) }
                    head[head_len] = embedded.bytes[quad]
                    head_len += 1usize
                }
                quad += 1usize
            }
            at = text.len
            break
        }
        at = scan
        if compressed {
            if tail_len + 2usize > 16usize { ret (address, false) }
            tail[tail_len] = u8(value / 256usize)
            tail[tail_len + 1usize] = u8(value % 256usize)
            tail_len += 2usize
        } else {
            if head_len + 2usize > 16usize { ret (address, false) }
            head[head_len] = u8(value / 256usize)
            head[head_len + 1usize] = u8(value % 256usize)
            head_len += 2usize
        }
        if at == text.len { break }
        if text[at] != 58u8 { ret (address, false) }
        at += 1usize
        if at < text.len && text[at] == 58u8 {
            if compressed { ret (address, false) }
            compressed = true
            at += 1usize
            if at == text.len { break }
        } else {
            if at == text.len { ret (address, false) }
        }
    }
    if !compressed && head_len != 16usize { ret (address, false) }
    // `::` must replace at least one complete group.
    if compressed && head_len + tail_len >= 16usize { ret (address, false) }
    var index = 0usize
    while index < head_len {
        address.bytes[index] = head[index]
        index += 1usize
    }
    index = 0usize
    while index < tail_len {
        address.bytes[16usize - tail_len + index] = tail[index]
        index += 1usize
    }
    ret (address, true)
}

fn parse_ip(s: str) -> (Address, err) {
    var out: Address = zero
    let (four, is_four) = parse_ip4(s)
    if is_four { ret (Address{ Ip4: four }, ok) }
    let (six, is_six) = parse_ip6(s)
    if is_six { ret (Address{ Ip6: six }, ok) }
    ret (out, Failed)
}

fn put(dst: []u8, at: usize, byte: u8) -> (usize, bool) {
    if at == dst.len { ret (at, false) }
    dst[at] = byte
    ret (at + 1usize, true)
}

fn put_decimal(dst: []u8, at: usize, value: u32) -> (usize, bool) {
    var digits: [10]u8 = zero
    var first = digits.len
    var rest = value
    while true {
        first -= 1usize
        digits[first] = u8(rest % 10u32) + 48u8
        rest /= 10u32
        if rest == 0u32 { break }
    }
    var out = at
    var index = first
    while index < digits.len {
        let (next, wrote) = put(dst, out, digits[index])
        if !wrote { ret (at, false) }
        out = next
        index += 1usize
    }
    ret (out, true)
}

fn put_hex(dst: []u8, at: usize, value: u16) -> (usize, bool) {
    var digits: [4]u8 = zero
    var first = digits.len
    var rest = value
    while true {
        first -= 1usize
        let nibble = u8(rest % 16u16)
        if nibble < 10u8 { digits[first] = nibble + 48u8 } else { digits[first] = nibble - 10u8 + 97u8 }
        rest /= 16u16
        if rest == 0u16 { break }
    }
    var out = at
    var index = first
    while index < digits.len {
        let (next, wrote) = put(dst, out, digits[index])
        if !wrote { ret (at, false) }
        out = next
        index += 1usize
    }
    ret (out, true)
}

fn format_ip4(address: Ip4, dst: []u8) -> (str, err) {
    var at = 0usize
    var part = 0usize
    while part < 4usize {
        if part != 0usize {
            let (next, wrote) = put(dst, at, 46u8)
            if !wrote { ret ("", Failed) }
            at = next
        }
        let (next, wrote) = put_decimal(dst, at, u32(address.bytes[part]))
        if !wrote { ret ("", Failed) }
        at = next
        part += 1usize
    }
    ret (dst[..at], ok)
}

fn format_ip6(address: Ip6, dst: []u8) -> (str, err) {
    var groups: [8]u16 = zero
    var index = 0usize
    while index < 8usize {
        groups[index] = u16(address.bytes[index * 2usize]) * 256u16 + u16(address.bytes[index * 2usize + 1usize])
        index += 1usize
    }
    // RFC 5952: compress the first longest zero run, but never a single group.
    var best_at = 8usize
    var best_len = 0usize
    index = 0usize
    while index < 8usize {
        if groups[index] != 0u16 {
            index += 1usize
        } else {
            let start = index
            while index < 8usize && groups[index] == 0u16 { index += 1usize }
            let length = index - start
            if length > best_len && length >= 2usize {
                best_at = start
                best_len = length
            }
        }
    }
    var at = 0usize
    index = 0usize
    while index < 8usize {
        if index == best_at {
            let (first_colon, first_ok) = put(dst, at, 58u8)
            if !first_ok { ret ("", Failed) }
            let (second_colon, second_ok) = put(dst, first_colon, 58u8)
            if !second_ok { ret ("", Failed) }
            at = second_colon
            index += best_len
        } else {
            if index != 0usize && index != best_at + best_len {
                let (colon, colon_ok) = put(dst, at, 58u8)
                if !colon_ok { ret ("", Failed) }
                at = colon
            }
            let (next, wrote) = put_hex(dst, at, groups[index])
            if !wrote { ret ("", Failed) }
            at = next
            index += 1usize
        }
    }
    if address.scope != 0u32 {
        let (percent, percent_ok) = put(dst, at, 37u8)
        if !percent_ok { ret ("", Failed) }
        let (next, scope_ok) = put_decimal(dst, percent, address.scope)
        if !scope_ok { ret ("", Failed) }
        at = next
    }
    ret (dst[..at], ok)
}

fn format_ip(address: Address, dst: []u8) -> (str, err) {
    switch address {
    case .Ip4 as four:
        let (text, format_error) = format_ip4(four, dst)
        ret (text, format_error)
    case .Ip6 as six:
        let (text, format_error) = format_ip6(six, dst)
        ret (text, format_error)
    default:
        ret ("", Failed)
    }
}

fn map_error(source_error: err) -> err {
    let detail = os.last_error_detail("network", "")
    ret map_error_with_code(source_error, detail.native_code)
}

fn map_error_with_code(source_error: err, code: i32) -> err {
    if source_error == ok { ret ok }
    if source_error == os.NotFound { ret NotFound }
    if source_error == os.Timeout { ret Timeout }
    if source_error == os.Exists { ret AddressInUse }
    if code == 111i32 || code == 10061i32 { ret Refused }
    if code == 104i32 || code == 10054i32 { ret Reset }
    if code == 101i32 || code == 113i32 || code == 10051i32 || code == 10065i32 { ret Unreachable }
    if code == 110i32 || code == 10060i32 { ret Timeout }
    if code == 98i32 || code == 10048i32 { ret AddressInUse }
    ret Failed
}

fn to_os_address(endpoint: Endpoint) -> os.SocketAddress {
    var out: os.SocketAddress = zero
    out.port = endpoint.port
    switch endpoint.address {
    case .Ip4 as four:
        out.family = .Ip4
        var at = 0usize
        while at < 4usize {
            out.bytes[at] = four.bytes[at]
            at += 1usize
        }
    case .Ip6 as six:
        out.family = .Ip6
        var at = 0usize
        while at < 16usize {
            out.bytes[at] = six.bytes[at]
            at += 1usize
        }
        out.scope = six.scope
    }
    ret out
}

fn from_os_address(source: os.SocketAddress) -> Endpoint {
    var out: Endpoint = zero
    out.port = source.port
    if source.family == .Ip4 {
        var four: Ip4 = zero
        var at = 0usize
        while at < 4usize {
            four.bytes[at] = source.bytes[at]
            at += 1usize
        }
        out.address = Address{ Ip4: four }
    } else {
        var six: Ip6 = zero
        var at = 0usize
        while at < 16usize {
            six.bytes[at] = source.bytes[at]
            at += 1usize
        }
        six.scope = source.scope
        out.address = Address{ Ip6: six }
    }
    ret out
}

fn socket_family(address: Address) -> os.SocketFamily {
    switch address {
    case .Ip6 as six:
        ret .Ip6
    default:
        ret .Ip4
    }
}

fn append_resolved(out: []Endpoint, used: usize, addresses: []const os.SocketAddress) -> usize {
    var count = used
    var at = 0usize
    while at < addresses.len && count < out.len {
        out[count] = from_os_address(addresses[at])
        count += 1usize
        at += 1usize
    }
    ret count
}

fn resolve(a: *mem.Arena, host: str, port: u16, family: Family) -> ([]Endpoint, err) {
    var empty: []Endpoint = zero
    let mark = mem.mark(a)
    let (out, allocation_error) = mem.alloc[Endpoint](a, 32usize)
    if allocation_error != ok { ret (empty, allocation_error) }
    var used = 0usize
    var first_error: err = ok
    if family == .Any || family == .Ip4 {
        let (addresses, resolve_error) = os.socket_resolve(a, host, port, .Ip4)
        if resolve_error == ok {
            used = append_resolved(out, used, addresses)
        } else {
            first_error = map_error(resolve_error)
        }
    }
    if family == .Any || family == .Ip6 {
        let (addresses, resolve_error) = os.socket_resolve(a, host, port, .Ip6)
        if resolve_error == ok {
            used = append_resolved(out, used, addresses)
        } else {
            if first_error == ok { first_error = map_error(resolve_error) }
        }
    }
    if used == 0usize {
        mem.reset(a, mark)
        if first_error != ok { ret (empty, first_error) }
        ret (empty, NotFound)
    }
    ret (out[..used], ok)
}

fn tcp_connect(endpoint: Endpoint) -> (Socket, err) {
    var empty: Socket = zero
    let (socket, open_error) = os.socket_open(socket_family(endpoint.address), .Stream)
    if open_error != ok { ret (empty, map_error(open_error)) }
    let connect_error = os.socket_connect(socket, to_os_address(endpoint))
    if connect_error != ok {
        let mapped = map_error(connect_error)
        let unused = os.socket_close(socket)
        ret (empty, mapped)
    }
    ret (socket, ok)
}

fn tcp_listen(endpoint: Endpoint, backlog: u32) -> (Socket, err) {
    var empty: Socket = zero
    let (socket, open_error) = os.socket_open(socket_family(endpoint.address), .Stream)
    if open_error != ok { ret (empty, map_error(open_error)) }
    let bind_error = os.socket_bind(socket, to_os_address(endpoint))
    if bind_error != ok {
        let mapped = map_error(bind_error)
        let unused = os.socket_close(socket)
        ret (empty, mapped)
    }
    let listen_error = os.socket_listen(socket, backlog)
    if listen_error != ok {
        let mapped = map_error(listen_error)
        let unused = os.socket_close(socket)
        ret (empty, mapped)
    }
    ret (socket, ok)
}

fn tcp_accept(listener: Socket) -> (Socket, Endpoint, err) {
    var empty: Socket = zero
    var endpoint: Endpoint = zero
    let (accepted, peer, accept_error) = os.socket_accept(listener)
    if accept_error != ok { ret (empty, endpoint, map_error(accept_error)) }
    ret (accepted, from_os_address(peer), ok)
}

fn udp_bind(endpoint: Endpoint) -> (Socket, err) {
    var empty: Socket = zero
    let (socket, open_error) = os.socket_open(socket_family(endpoint.address), .Datagram)
    if open_error != ok { ret (empty, map_error(open_error)) }
    let bind_error = os.socket_bind(socket, to_os_address(endpoint))
    if bind_error != ok {
        let mapped = map_error(bind_error)
        let unused = os.socket_close(socket)
        ret (empty, mapped)
    }
    ret (socket, ok)
}

fn receive(socket: Socket, dst: []u8) -> (usize, err) {
    let (count, receive_error) = os.socket_receive(socket, dst)
    if receive_error != ok { ret (count, map_error(receive_error)) }
    ret (count, ok)
}

fn send(socket: Socket, src: []const u8) -> (usize, err) {
    let (count, send_error) = os.socket_send(socket, src)
    if send_error != ok { ret (count, map_error(send_error)) }
    ret (count, ok)
}

fn receive_from(socket: Socket, dst: []u8) -> (usize, Endpoint, err) {
    var endpoint: Endpoint = zero
    let (count, source, receive_error) = os.socket_receive_from(socket, dst)
    if receive_error != ok { ret (count, endpoint, map_error(receive_error)) }
    ret (count, from_os_address(source), ok)
}

fn send_to(socket: Socket, dst: Endpoint, src: []const u8) -> (usize, err) {
    let (count, send_error) = os.socket_send_to(socket, to_os_address(dst), src)
    if send_error != ok { ret (count, map_error(send_error)) }
    ret (count, ok)
}

fn shutdown(socket: Socket, how: Shutdown) -> err {
    var os_how: os.SocketShutdown = .Read
    if how == .Write { os_how = .Write }
    if how == .Both { os_how = .Both }
    ret map_error(os.socket_shutdown(socket, os_how))
}

fn close(socket: own Socket) -> err {
    ret map_error(os.socket_close(socket))
}

fn socket_read(ctx: *void, dst: []u8) -> (usize, err) {
    let socket = mem.cast[*Socket](ctx)
    let (count, read_error) = receive(*socket, dst)
    if read_error != ok { ret (count, read_error) }
    if count == 0usize { ret (0usize, io.End) }
    ret (count, ok)
}

fn socket_write(ctx: *void, src: []const u8) -> (usize, err) {
    let socket = mem.cast[*Socket](ctx)
    let (count, write_error) = send(*socket, src)
    ret (count, write_error)
}

fn socket_flush(ctx: *void) -> err {
    ret ok
}

fn reader(socket: *Socket) -> io.Reader {
    ret io.Reader { ctx: mem.cast[*void](socket), read: socket_read }
}

fn writer(socket: *Socket) -> io.Writer {
    ret io.Writer { ctx: mem.cast[*void](socket), write: socket_write, flush: socket_flush }
}

const CONTROL_SLICE_NS: i64 = 1000000i64

fn control_wait(control: cancel.Control) -> (i64, err) {
    var now: time.Instant = zero
    if control.has_deadline {
        let (observed, clock_error) = time.monotonic()
        if clock_error != ok { ret (0i64, clock_error) }
        now = observed
    }
    let stopped = cancel.check(control, now)
    if stopped == cancel.Cancelled { ret (0i64, cancel.Cancelled) }
    if stopped == cancel.Timeout { ret (0i64, Timeout) }
    var wait = CONTROL_SLICE_NS
    if control.has_deadline {
        let remaining = control.deadline.nanos - now.nanos
        if remaining < wait { wait = remaining }
    }
    ret (wait, ok)
}

fn wait_socket(socket: Socket, writable: bool, control: cancel.Control) -> err {
    var storage: [8192]u8 = zero
    var arena = mem.arena_from(storage[0..])
    let (poller, open_error) = os.poller_open(&arena)
    if open_error != ok { ret map_error(open_error) }
    defer let _ = os.poller_close(poller)
    let interest = os.PollInterest { readable: !writable, writable: writable }
    let register_error = os.poller_register(poller, os.socket_handle(socket), 1usize, interest)
    if register_error != ok { ret map_error(register_error) }
    var events: [1]os.PollEvent = zero
    while true {
        let (wait, control_error) = control_wait(control)
        if control_error != ok { ret control_error }
        let (count, wait_error) = os.poller_wait(poller, events[0..], wait)
        if wait_error != ok { ret map_error(wait_error) }
        if count != 0usize { ret ok }
    }
    ret Failed
}

fn precheck(control: cancel.Control) -> err {
    let (wait, control_error) = control_wait(control)
    ret control_error
}

fn resolve_with_control(a: *mem.Arena, host: str, port: u16, family: Family, control: cancel.Control) -> ([]Endpoint, err) {
    var empty: []Endpoint = zero
    let check_error = precheck(control)
    if check_error != ok { ret (empty, check_error) }
    // The host resolver is one blocking call. A live deadline/token would promise an
    // acknowledgement bound it cannot provide without a worker whose lifetime outlives
    // this call, so reject that guarantee explicitly.
    if control.token != nil || control.has_deadline { ret (empty, os.Unsupported) }
    let (addresses, resolve_error) = resolve(a, host, port, family)
    ret (addresses, resolve_error)
}

fn tcp_connect_with_control(endpoint: Endpoint, control: cancel.Control) -> (Socket, err) {
    var empty: Socket = zero
    let check_error = precheck(control)
    if check_error != ok { ret (empty, check_error) }
    let (socket, open_error) = os.socket_open(socket_family(endpoint.address), .Stream)
    if open_error != ok { ret (empty, map_error(open_error)) }
    let nonblock_error = os.socket_set_nonblocking(socket, true)
    if nonblock_error != ok {
        let mapped = map_error(nonblock_error)
        let unused = os.socket_close(socket)
        ret (empty, mapped)
    }
    var connect_error = os.socket_connect(socket, to_os_address(endpoint))
    while connect_error == os.WouldBlock {
        let wait_error = wait_socket(socket, true, control)
        if wait_error != ok {
            let unused = os.socket_close(socket)
            ret (empty, wait_error)
        }
        connect_error = os.socket_connect(socket, to_os_address(endpoint))
    }
    if connect_error != ok {
        let detail = os.last_error_detail("connect", "")
        // A second connect after writable readiness reports already-connected on both
        // hosts rather than repeating success.
        if detail.native_code != 106i32 && detail.native_code != 10056i32 {
            let mapped = map_error_with_code(connect_error, detail.native_code)
            let unused = os.socket_close(socket)
            ret (empty, mapped)
        }
    }
    let block_error = os.socket_set_nonblocking(socket, false)
    if block_error != ok {
        let mapped = map_error(block_error)
        let unused = os.socket_close(socket)
        ret (empty, mapped)
    }
    ret (socket, ok)
}

fn receive_with_control(socket: Socket, dst: []u8, control: cancel.Control) -> (usize, err) {
    let check_error = precheck(control)
    if check_error != ok { ret (0usize, check_error) }
    let nonblock_error = os.socket_set_nonblocking(socket, true)
    if nonblock_error != ok { ret (0usize, map_error(nonblock_error)) }
    while true {
        let (count, receive_error) = os.socket_receive(socket, dst)
        if receive_error == ok {
            let block_error = os.socket_set_nonblocking(socket, false)
            if block_error != ok { ret (count, map_error(block_error)) }
            ret (count, ok)
        }
        if receive_error != os.WouldBlock {
            let mapped = map_error(receive_error)
            let unused = os.socket_set_nonblocking(socket, false)
            ret (count, mapped)
        }
        let wait_error = wait_socket(socket, false, control)
        if wait_error != ok {
            let unused = os.socket_set_nonblocking(socket, false)
            ret (0usize, wait_error)
        }
    }
    ret (0usize, Failed)
}

fn send_with_control(socket: Socket, src: []const u8, control: cancel.Control) -> (usize, err) {
    let check_error = precheck(control)
    if check_error != ok { ret (0usize, check_error) }
    let nonblock_error = os.socket_set_nonblocking(socket, true)
    if nonblock_error != ok { ret (0usize, map_error(nonblock_error)) }
    while true {
        let (count, send_error) = os.socket_send(socket, src)
        if send_error == ok {
            let block_error = os.socket_set_nonblocking(socket, false)
            if block_error != ok { ret (count, map_error(block_error)) }
            ret (count, ok)
        }
        if send_error != os.WouldBlock {
            let mapped = map_error(send_error)
            let unused = os.socket_set_nonblocking(socket, false)
            ret (count, mapped)
        }
        let wait_error = wait_socket(socket, true, control)
        if wait_error != ok {
            let unused = os.socket_set_nonblocking(socket, false)
            ret (0usize, wait_error)
        }
    }
    ret (0usize, Failed)
}


// --- CIDR prefixes (#952) and the private ranges an SSRF guard refuses (#1436).

type Cidr = struct { address: Address, prefix: u8 }

// The address bytes and their count: four for v4, sixteen for v6.
fn address_bytes(address: Address, out: []u8) -> usize {
    switch address {
    case .Ip4 as four:
        var i = 0usize
        while i < 4usize {
            out[i] = four.bytes[i]
            i += 1usize
        }
        ret 4usize
    case .Ip6 as six:
        var j = 0usize
        while j < 16usize {
            out[j] = six.bytes[j]
            j += 1usize
        }
        ret 16usize
    }
    ret 0usize
}

// `10.0.0.0/8`, `fd00::/8`; a bare address is a host prefix (`/32`, `/128`).
fn cidr_parse(text: str) -> (Cidr, err) {
    var slash = text.len
    var at = 0usize
    while at < text.len {
        if text[at] == 47u8 { slash = at }
        at += 1usize
    }
    let (address, address_error) = parse_ip(text[..slash])
    if address_error != ok { ret (zero, address_error) }
    var width = 32usize
    switch address {
    case .Ip6 as six:
        width = 128usize
    default:
        width = 32usize
    }
    var prefix = width
    if slash < text.len {
        let digits = text[slash + 1usize..]
        if digits.len == 0usize || digits.len > 3usize { ret (zero, Failed) }
        prefix = 0usize
        at = 0usize
        while at < digits.len {
            if digits[at] < 48u8 || digits[at] > 57u8 { ret (zero, Failed) }
            prefix = prefix * 10usize + usize(digits[at] - 48u8)
            at += 1usize
        }
        if prefix > width { ret (zero, Failed) }
    }
    ret (Cidr { address: address, prefix: u8(prefix) }, ok)
}

// Whether `address` lies in `c`: the same family and the first `prefix` bits equal.
fn cidr_contains(c: Cidr, address: Address) -> bool {
    var net_bytes: [16]u8 = zero
    var host_bytes: [16]u8 = zero
    let net_len = address_bytes(c.address, net_bytes[0..])
    let host_len = address_bytes(address, host_bytes[0..])
    if net_len != host_len { ret false }
    var remaining = usize(c.prefix)
    var i = 0usize
    while i < net_len && remaining > 0usize {
        var mask = 255u8
        if remaining < 8usize { mask = u8((255u32 << u32(8usize - remaining)) & 255u32) }
        if (net_bytes[i] & mask) != (host_bytes[i] & mask) { ret false }
        if remaining >= 8usize { remaining -= 8usize } else { remaining = 0usize }
        i += 1usize
    }
    ret true
}

fn in_range(address: Address, text: str) -> bool {
    let (c, parse_error) = cidr_parse(text)
    if parse_error != ok { ret false }
    ret cidr_contains(c, address)
}

// The ranges a request to a user-supplied host must not reach: RFC 1918,
// loopback and link-local for v4; loopback, link-local and unique-local for
// v6, plus a v4-mapped v6 address judged as the v4 address it carries.
fn is_private(address: Address) -> bool {
    switch address {
    case .Ip4 as four:
        ret in_range(address, "10.0.0.0/8") || in_range(address, "172.16.0.0/12") || in_range(address, "192.168.0.0/16") || in_range(address, "127.0.0.0/8") || in_range(address, "169.254.0.0/16")
    case .Ip6 as six:
        if in_range(address, "::ffff:0:0/96") {
            var mapped: Ip4 = zero
            mapped.bytes[0usize] = six.bytes[12usize]
            mapped.bytes[1usize] = six.bytes[13usize]
            mapped.bytes[2usize] = six.bytes[14usize]
            mapped.bytes[3usize] = six.bytes[15usize]
            ret is_private(Address{ Ip4: mapped })
        }
        ret in_range(address, "::1/128") || in_range(address, "fe80::/10") || in_range(address, "fc00::/7")
    }
    ret false
}
