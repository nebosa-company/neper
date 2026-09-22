// MQTT 3.1.1 control packets over caller buffers plus the QoS 1/2 state
// machines; no sockets, the caller moves the bytes. Encoders answer the
// bytes written into `dst`; decoders read one whole packet from `src`.
// `Outbox` tracks outgoing QoS 1/2 publishes by packet id (`publish`,
// `outbox_receive` on PUBACK/PUBREC/PUBCOMP, `outbox_retransmit` after a
// reconnect with DUP); `Inbox` is the receiver side (`inbox_receive` on
// PUBLISH/PUBREL: QoS 1 delivers at once and answers PUBACK, QoS 2 stores
// the id, answers PUBREC and delivers exactly once on PUBREL with PUBCOMP).
// Topic filters follow section 4.7: `+` is one level, `#` the tail, and
// neither matches a `$` topic at the root.

use e.mem
use e.str

type Publish = struct { topic: str, payload: []const u8, qos: u8, retain: bool, dup: bool, packet_id: u16 }
type Connect = struct { client_id: str, keep_alive: u16, clean_session: bool, has_username: bool, username: str, has_password: bool, password: []const u8, has_will: bool, will_topic: str, will_payload: []const u8, will_qos: u8, will_retain: bool }
type Outbox = struct { ids: []u16, state: []u8, next_id: u16 }
type Inbox = struct { ids: []u16, used: []u8 }
error Malformed
error TooSmall
error Invalid
error Full

const CONNECT: u8 = 1u8
const CONNACK: u8 = 2u8
const PUBLISH: u8 = 3u8
const PUBACK: u8 = 4u8
const PUBREC: u8 = 5u8
const PUBREL: u8 = 6u8
const PUBCOMP: u8 = 7u8
const SUBSCRIBE: u8 = 8u8
const SUBACK: u8 = 9u8
const UNSUBSCRIBE: u8 = 10u8
const UNSUBACK: u8 = 11u8
const PINGREQ: u8 = 12u8
const PINGRESP: u8 = 13u8
const DISCONNECT: u8 = 14u8

// Outbox slot states.
const FREE: u8 = 0u8
const AWAIT_PUBACK: u8 = 1u8
const AWAIT_PUBREC: u8 = 2u8
const AWAIT_PUBCOMP: u8 = 3u8

const MAX_REMAINING: usize = 268435455usize

// ---- fixed header ---------------------------------------------------------

// The variable-length remaining length (1-4 bytes); `Invalid` above 268435455.
fn encode_remaining_length(dst: []u8, n: usize) -> (usize, err) {
    if n > MAX_REMAINING { ret (0usize, Invalid) }
    var rest = n
    var at = 0usize
    while at < dst.len {
        var digit = u8(rest & 127usize)
        rest = rest >> 7u32
        if rest > 0usize { digit = digit | 128u8 }
        dst[at] = digit
        at += 1usize
        if rest == 0usize { ret (at, ok) }
    }
    ret (0usize, TooSmall)
}

// Answers (length, bytes consumed); a fifth continuation byte is `Malformed`.
fn decode_remaining_length(src: []const u8) -> (usize, usize, err) {
    var value = 0usize
    var at = 0usize
    while at < 4usize {
        if at >= src.len { ret (0usize, 0usize, TooSmall) }
        let b = src[at]
        value = value | (usize(b & 127u8) << u32(7usize * at))
        at += 1usize
        if (b & 128u8) == 0u8 { ret (value, at, ok) }
    }
    ret (0usize, 0usize, Malformed)
}

// The control packet type (1-14) of the packet at `src`.
fn packet_type(src: []const u8) -> (u8, err) {
    if src.len == 0usize { ret (0u8, TooSmall) }
    let t = src[0] >> 4u32
    if t == 0u8 || t == 15u8 { ret (0u8, Malformed) }
    ret (t, ok)
}

// Answers (remaining length, fixed header bytes including the type byte).
fn remaining_length(src: []const u8) -> (usize, usize, err) {
    if src.len == 0usize { ret (0usize, 0usize, TooSmall) }
    let (n, used, e) = decode_remaining_length(src[1..])
    if e != ok { ret (0usize, 0usize, e) }
    ret (n, used + 1usize, ok)
}

// The whole packet's body: type/flags byte checked against `first`, the
// remaining length must fit `src`. Answers (body, first byte).
fn body(src: []const u8, expect_type: u8) -> ([]const u8, u8, err) {
    let (n, head, e) = remaining_length(src)
    if e != ok { ret (src[..0usize], 0u8, e) }
    if src[0] >> 4u32 != expect_type { ret (src[..0usize], 0u8, Invalid) }
    if head + n > src.len { ret (src[..0usize], 0u8, TooSmall) }
    ret (src[head..head + n], src[0], ok)
}

fn header(dst: []u8, first: u8, remaining: usize) -> (usize, err) {
    if dst.len == 0usize { ret (0usize, TooSmall) }
    dst[0] = first
    let (n, e) = encode_remaining_length(dst[1..], remaining)
    if e != ok { ret (0usize, e) }
    ret (n + 1usize, ok)
}

// ---- field helpers --------------------------------------------------------

fn put_u16(dst: []u8, at: usize, v: u16) -> err {
    if at + 2usize > dst.len { ret TooSmall }
    dst[at] = u8(v >> 8u32)
    dst[at + 1usize] = u8(v & 255u16)
    ret ok
}

fn get_u16(src: []const u8, at: usize) -> (u16, err) {
    if at + 2usize > src.len { ret (0u16, TooSmall) }
    ret ((u16(src[at]) << 8u32) | u16(src[at + 1usize]), ok)
}

// A length-prefixed UTF-8 string (at most 65535 bytes); answers bytes written.
fn utf8_string(dst: []u8, s: []const u8) -> (usize, err) {
    if s.len > 65535usize { ret (0usize, Invalid) }
    if dst.len < 2usize + s.len { ret (0usize, TooSmall) }
    let e = put_u16(dst, 0usize, u16(s.len))
    if e != ok { ret (0usize, e) }
    mem.copy[u8](dst[2usize..], s)
    ret (2usize + s.len, ok)
}

// The length-prefixed string at `src`; answers (bytes, bytes consumed).
fn decode_utf8_string(src: []const u8) -> ([]const u8, usize, err) {
    let (n, e) = get_u16(src, 0usize)
    if e != ok { ret (src[..0usize], 0usize, Malformed) }
    let end = 2usize + usize(n)
    if end > src.len { ret (src[..0usize], 0usize, Malformed) }
    ret (src[2usize..end], end, ok)
}

// A length-prefixed string appended at `*at`, which moves past it.
fn put_string(dst: []u8, at: *usize, s: []const u8) -> err {
    if *at > dst.len { ret TooSmall }
    let (n, e) = utf8_string(dst[*at..], s)
    *at += n
    ret e
}

// Assembled body in `dst[head_room..]` shifted down behind its fixed header;
// `head_room` is the 5 bytes reserved for it. Answers total bytes.
fn finish(dst: []u8, first: u8, body_len: usize) -> (usize, err) {
    var tmp: [5]u8 = zero
    let (h, e) = header(tmp[..], first, body_len)
    if e != ok { ret (0usize, e) }
    if h + body_len > dst.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < body_len {
        dst[h + i] = dst[5usize + i]
        i += 1usize
    }
    mem.copy[u8](dst[..h], tmp[..h])
    ret (h + body_len, ok)
}

// ---- CONNECT / CONNACK ----------------------------------------------------

// A CONNECT without credentials or will; set the `has_*` fields for more.
fn connect(client_id: str, keep_alive: u16, clean_session: bool) -> Connect {
    ret Connect { client_id: client_id, keep_alive: keep_alive, clean_session: clean_session, has_username: false, username: "", has_password: false, password: "", has_will: false, will_topic: "", will_payload: "", will_qos: 0u8, will_retain: false }
}

fn encode_connect(dst: []u8, c: *const Connect) -> (usize, err) {
    if c.will_qos > 2u8 || (c.has_password && !c.has_username) { ret (0usize, Invalid) }
    if dst.len < 5usize { ret (0usize, TooSmall) }
    var flags = 0u8
    if c.clean_session { flags = flags | 2u8 }
    if c.has_will { flags = flags | 4u8 | (c.will_qos << 3u32) }
    if c.has_will && c.will_retain { flags = flags | 32u8 }
    if c.has_username { flags = flags | 128u8 }
    if c.has_password { flags = flags | 64u8 }
    var at = 5usize
    let e0 = put_string(dst, &at, "MQTT")
    if e0 != ok { ret (0usize, e0) }
    if at + 4usize > dst.len { ret (0usize, TooSmall) }
    dst[at] = 4u8
    dst[at + 1usize] = flags
    let _ = put_u16(dst, at + 2usize, c.keep_alive)
    at += 4usize
    let e1 = put_string(dst, &at, c.client_id)
    if e1 != ok { ret (0usize, e1) }
    if c.has_will {
        let e2 = put_string(dst, &at, c.will_topic)
        if e2 != ok { ret (0usize, e2) }
        let e3 = put_string(dst, &at, c.will_payload)
        if e3 != ok { ret (0usize, e3) }
    }
    if c.has_username {
        let e4 = put_string(dst, &at, c.username)
        if e4 != ok { ret (0usize, e4) }
    }
    if c.has_password {
        let e5 = put_string(dst, &at, c.password)
        if e5 != ok { ret (0usize, e5) }
    }
    let (n, fe) = finish(dst, CONNECT << 4u32, at - 5usize)
    ret (n, fe)
}

// Answers (session present, return code).
fn decode_connack(src: []const u8) -> (bool, u8, err) {
    let (b, _, e) = body(src, CONNACK)
    if e != ok { ret (false, 0u8, e) }
    if b.len != 2usize || (b[0] & 254u8) != 0u8 { ret (false, 0u8, Malformed) }
    ret ((b[0] & 1u8) == 1u8, b[1], ok)
}

fn encode_connack(dst: []u8, session_present: bool, return_code: u8) -> (usize, err) {
    if dst.len < 4usize { ret (0usize, TooSmall) }
    dst[0] = CONNACK << 4u32
    dst[1] = 2u8
    dst[2] = 0u8
    if session_present { dst[2] = 1u8 }
    dst[3] = return_code
    ret (4usize, ok)
}

// ---- PUBLISH and acks -----------------------------------------------------

fn encode_publish(dst: []u8, topic: str, payload: []const u8, qos: u8, retain: bool, dup: bool, packet_id: u16) -> (usize, err) {
    if qos > 2u8 || (qos > 0u8 && packet_id == 0u16) { ret (0usize, Invalid) }
    if dst.len < 5usize { ret (0usize, TooSmall) }
    var first = (PUBLISH << 4u32) | (qos << 1u32)
    if retain { first = first | 1u8 }
    if dup { first = first | 8u8 }
    var at = 5usize
    let e0 = put_string(dst, &at, topic)
    if e0 != ok { ret (0usize, e0) }
    if qos > 0u8 {
        let e1 = put_u16(dst, at, packet_id)
        if e1 != ok { ret (0usize, e1) }
        at += 2usize
    }
    if at + payload.len > dst.len { ret (0usize, TooSmall) }
    mem.copy[u8](dst[at..], payload)
    at += payload.len
    let (n, fe) = finish(dst, first, at - 5usize)
    ret (n, fe)
}

fn decode_publish(src: []const u8) -> (Publish, err) {
    var p = Publish { topic: "", payload: "", qos: 0u8, retain: false, dup: false, packet_id: 0u16 }
    let (b, first, e) = body(src, PUBLISH)
    if e != ok { ret (p, e) }
    p.qos = (first >> 1u32) & 3u8
    if p.qos == 3u8 { ret (p, Malformed) }
    p.retain = (first & 1u8) == 1u8
    p.dup = (first & 8u8) == 8u8
    let (topic, used, te) = decode_utf8_string(b)
    if te != ok { ret (p, te) }
    p.topic = topic
    var at = used
    if p.qos > 0u8 {
        let (id, ie) = get_u16(b, at)
        if ie != ok || id == 0u16 { ret (p, Malformed) }
        p.packet_id = id
        at += 2usize
    }
    p.payload = b[at..]
    ret (p, ok)
}

// A two-byte-body ack: PUBACK, PUBREC, PUBREL (flags 2), PUBCOMP, UNSUBACK.
fn encode_ack(dst: []u8, kind: u8, packet_id: u16) -> (usize, err) {
    if dst.len < 4usize { ret (0usize, TooSmall) }
    dst[0] = kind << 4u32
    if kind == PUBREL { dst[0] = dst[0] | 2u8 }
    dst[1] = 2u8
    let e = put_u16(dst, 2usize, packet_id)
    if e != ok { ret (0usize, e) }
    ret (4usize, ok)
}

fn encode_puback(dst: []u8, packet_id: u16) -> (usize, err) {
    let (n, e) = encode_ack(dst, PUBACK, packet_id)
    ret (n, e)
}

fn encode_pubrec(dst: []u8, packet_id: u16) -> (usize, err) {
    let (n, e) = encode_ack(dst, PUBREC, packet_id)
    ret (n, e)
}

fn encode_pubrel(dst: []u8, packet_id: u16) -> (usize, err) {
    let (n, e) = encode_ack(dst, PUBREL, packet_id)
    ret (n, e)
}

fn encode_pubcomp(dst: []u8, packet_id: u16) -> (usize, err) {
    let (n, e) = encode_ack(dst, PUBCOMP, packet_id)
    ret (n, e)
}

fn encode_unsuback(dst: []u8, packet_id: u16) -> (usize, err) {
    let (n, e) = encode_ack(dst, UNSUBACK, packet_id)
    ret (n, e)
}

// Answers (packet type, packet id) of a PUBACK/PUBREC/PUBREL/PUBCOMP/UNSUBACK.
fn decode_ack(src: []const u8) -> (u8, u16, err) {
    let (t, te) = packet_type(src)
    if te != ok { ret (0u8, 0u16, te) }
    if t != PUBACK && t != PUBREC && t != PUBREL && t != PUBCOMP && t != UNSUBACK { ret (0u8, 0u16, Invalid) }
    let (b, first, e) = body(src, t)
    if e != ok { ret (0u8, 0u16, e) }
    var want_flags = 0u8
    if t == PUBREL { want_flags = 2u8 }
    if b.len != 2usize || (first & 15u8) != want_flags { ret (0u8, 0u16, Malformed) }
    let (id, _) = get_u16(b, 0usize)
    ret (t, id, ok)
}

// ---- SUBSCRIBE / SUBACK / UNSUBSCRIBE ------------------------------------

fn encode_subscribe(dst: []u8, packet_id: u16, topics: []const str, qoss: []const u8) -> (usize, err) {
    if packet_id == 0u16 || topics.len == 0usize || topics.len != qoss.len { ret (0usize, Invalid) }
    if dst.len < 7usize { ret (0usize, TooSmall) }
    let _ = put_u16(dst, 5usize, packet_id)
    var at = 7usize
    var i = 0usize
    while i < topics.len {
        if qoss[i] > 2u8 { ret (0usize, Invalid) }
        let e = put_string(dst, &at, topics[i])
        if e != ok { ret (0usize, e) }
        if at >= dst.len { ret (0usize, TooSmall) }
        dst[at] = qoss[i]
        at += 1usize
        i += 1usize
    }
    let (n, fe) = finish(dst, (SUBSCRIBE << 4u32) | 2u8, at - 5usize)
    ret (n, fe)
}

// Answers (packet id, return codes written into `codes`).
fn decode_suback(src: []const u8, codes: []u8) -> (u16, usize, err) {
    let (b, _, e) = body(src, SUBACK)
    if e != ok { ret (0u16, 0usize, e) }
    let (id, ie) = get_u16(b, 0usize)
    if ie != ok || b.len < 3usize { ret (0u16, 0usize, Malformed) }
    let n = b.len - 2usize
    if n > codes.len { ret (id, 0usize, TooSmall) }
    var i = 0usize
    while i < n {
        let c = b[2usize + i]
        if c > 2u8 && c != 128u8 { ret (id, 0usize, Malformed) }
        codes[i] = c
        i += 1usize
    }
    ret (id, n, ok)
}

fn encode_suback(dst: []u8, packet_id: u16, codes: []const u8) -> (usize, err) {
    if codes.len == 0usize { ret (0usize, Invalid) }
    if dst.len < 7usize + codes.len { ret (0usize, TooSmall) }
    let _ = put_u16(dst, 5usize, packet_id)
    mem.copy[u8](dst[7usize..], codes)
    let (n, fe) = finish(dst, SUBACK << 4u32, 2usize + codes.len)
    ret (n, fe)
}

fn encode_unsubscribe(dst: []u8, packet_id: u16, topics: []const str) -> (usize, err) {
    if packet_id == 0u16 || topics.len == 0usize { ret (0usize, Invalid) }
    if dst.len < 7usize { ret (0usize, TooSmall) }
    let _ = put_u16(dst, 5usize, packet_id)
    var at = 7usize
    var i = 0usize
    while i < topics.len {
        let e = put_string(dst, &at, topics[i])
        if e != ok { ret (0usize, e) }
        i += 1usize
    }
    let (n, fe) = finish(dst, (UNSUBSCRIBE << 4u32) | 2u8, at - 5usize)
    ret (n, fe)
}

// ---- bodiless packets -----------------------------------------------------

fn encode_empty(dst: []u8, kind: u8) -> (usize, err) {
    if dst.len < 2usize { ret (0usize, TooSmall) }
    dst[0] = kind << 4u32
    dst[1] = 0u8
    ret (2usize, ok)
}

fn encode_pingreq(dst: []u8) -> (usize, err) {
    let (n, e) = encode_empty(dst, PINGREQ)
    ret (n, e)
}

fn encode_pingresp(dst: []u8) -> (usize, err) {
    let (n, e) = encode_empty(dst, PINGRESP)
    ret (n, e)
}

fn encode_disconnect(dst: []u8) -> (usize, err) {
    let (n, e) = encode_empty(dst, DISCONNECT)
    ret (n, e)
}

// ---- topic filters (section 4.7) ------------------------------------------

fn level_end(s: str, from: usize) -> usize {
    var at = from
    while at < s.len && s[at] != 47u8 { at += 1usize }
    ret at
}

// Does `filter` (with `+` and `#`) match `topic`? A wildcard at the root
// never matches a `$` topic; `sport/#` matches `sport`; `sport/+` does not.
fn topic_matches(filter: str, topic: str) -> bool {
    if filter.len == 0usize || topic.len == 0usize { ret false }
    if topic[0] == 36u8 && (filter[0] == 35u8 || filter[0] == 43u8) { ret false }
    var fi = 0usize
    var ti = 0usize
    while fi <= filter.len {
        let fe = level_end(filter, fi)
        let te = level_end(topic, ti)
        let wild = fe - fi == 1usize
        if wild && filter[fi] == 35u8 { ret fe == filter.len }
        if !(wild && filter[fi] == 43u8) && !str.eq(filter[fi..fe], topic[ti..te]) { ret false }
        let f_end = fe == filter.len
        let t_end = te == topic.len
        if f_end && t_end { ret true }
        if f_end != t_end {
            // `a/#` matches `a` (the parent level itself).
            ret t_end && fe + 2usize == filter.len && filter[fe + 1usize] == 35u8
        }
        fi = fe + 1usize
        ti = te + 1usize
    }
    ret false
}

// Is `filter` a well-formed topic filter: non-empty, `#` only last and
// alone in its level, `+` alone in its level?
fn valid_filter(filter: str) -> bool {
    if filter.len == 0usize { ret false }
    var at = 0usize
    while at < filter.len {
        let c = filter[at]
        let starts = at == 0usize || filter[at - 1usize] == 47u8
        let ends = at + 1usize == filter.len || filter[at + 1usize] == 47u8
        if c == 35u8 && !(starts && at + 1usize == filter.len) { ret false }
        if c == 43u8 && !(starts && ends) { ret false }
        at += 1usize
    }
    ret true
}

// ---- outbound QoS state machine -------------------------------------------

// An outbox over `ids`/`state` slots (zeroed, same length); ids start at 1.
fn outbox(ids: []u16, state: []u8) -> Outbox {
    ret Outbox { ids: ids, state: state, next_id: 1u16 }
}

fn slots(o: *const Outbox) -> usize {
    if o.ids.len < o.state.len { ret o.ids.len }
    ret o.state.len
}

fn find_slot(o: *const Outbox, id: u16) -> (usize, bool) {
    var i = 0usize
    let n = slots(o)
    while i < n {
        if o.state[i] != FREE && o.ids[i] == id { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn outbox_pending(o: *const Outbox) -> usize {
    var count = 0usize
    var i = 0usize
    let n = slots(o)
    while i < n {
        if o.state[i] != FREE { count += 1usize }
        i += 1usize
    }
    ret count
}

// Send `payload` on `topic` at `qos`: QoS 0 is fire and forget (id 0);
// QoS 1 records AwaitPuback and QoS 2 AwaitPubrec. Answers (packet id,
// bytes written); `Full` when every slot is taken.
fn publish(o: *Outbox, qos: u8, dst: []u8, topic: str, payload: []const u8) -> (u16, usize, err) {
    if qos > 2u8 { ret (0u16, 0usize, Invalid) }
    if qos == 0u8 {
        let (n, e) = encode_publish(dst, topic, payload, 0u8, false, false, 0u16)
        ret (0u16, n, e)
    }
    var slot = 0usize
    let count = slots(o)
    while slot < count && o.state[slot] != FREE { slot += 1usize }
    if slot >= count { ret (0u16, 0usize, Full) }
    var id = o.next_id
    // ponytail: linear scan for an unused id (a free slot guarantees one); a bitmap past a few hundred slots
    var searching = true
    while searching {
        let (_, taken) = find_slot(o, id)
        if id != 0u16 && !taken { searching = false } else { id = id +% 1u16 }
    }
    let (n, e) = encode_publish(dst, topic, payload, qos, false, false, id)
    if e != ok { ret (0u16, 0usize, e) }
    o.next_id = id +% 1u16
    if o.next_id == 0u16 { o.next_id = 1u16 }
    o.ids[slot] = id
    if qos == 1u8 { o.state[slot] = AWAIT_PUBACK } else { o.state[slot] = AWAIT_PUBREC }
    ret (id, n, ok)
}

// An incoming ack packet (`src`): PUBACK completes a QoS 1 publish; PUBREC
// turns a QoS 2 one into AwaitPubcomp and answers a PUBREL in `dst`;
// PUBCOMP completes it. Answers (bytes to send, done); an id no slot
// awaits is `Invalid`.
fn outbox_receive(o: *Outbox, src: []const u8, dst: []u8) -> (usize, bool, err) {
    let (kind, id, e) = decode_ack(src)
    if e != ok { ret (0usize, false, e) }
    let (slot, found) = find_slot(o, id)
    if !found { ret (0usize, false, Invalid) }
    let st = o.state[slot]
    if kind == PUBACK && st == AWAIT_PUBACK {
        o.state[slot] = FREE
        ret (0usize, true, ok)
    }
    if kind == PUBREC && (st == AWAIT_PUBREC || st == AWAIT_PUBCOMP) {
        let (n, re) = encode_pubrel(dst, id)
        if re != ok { ret (0usize, false, re) }
        o.state[slot] = AWAIT_PUBCOMP
        ret (n, false, ok)
    }
    if kind == PUBCOMP && st == AWAIT_PUBCOMP {
        o.state[slot] = FREE
        ret (0usize, true, ok)
    }
    ret (0usize, false, Invalid)
}

// The state of slot `slot`: (packet id, state; FREE when unused).
fn outbox_slot(o: *const Outbox, slot: usize) -> (u16, u8) {
    if slot >= slots(o) { ret (0u16, FREE) }
    ret (o.ids[slot], o.state[slot])
}

// After a reconnect, the packet slot `slot` still owes: the PUBLISH again
// with DUP set (the caller keeps topic and payload) while a PUBACK/PUBREC
// is awaited, the PUBREL while a PUBCOMP is; `Invalid` for a free slot.
fn outbox_retransmit(o: *const Outbox, slot: usize, dst: []u8, topic: str, payload: []const u8) -> (usize, err) {
    if slot >= slots(o) || o.state[slot] == FREE { ret (0usize, Invalid) }
    let id = o.ids[slot]
    if o.state[slot] == AWAIT_PUBCOMP {
        let (n, e) = encode_pubrel(dst, id)
        ret (n, e)
    }
    var qos = 1u8
    if o.state[slot] == AWAIT_PUBREC { qos = 2u8 }
    let (n, e) = encode_publish(dst, topic, payload, qos, false, true, id)
    ret (n, e)
}

// ---- inbound QoS state machine --------------------------------------------

// An inbox over `ids`/`used` slots (zeroed, same length) for QoS 2 ids.
fn inbox(ids: []u16, used: []u8) -> Inbox {
    ret Inbox { ids: ids, used: used }
}

fn inbox_slots(i: *const Inbox) -> usize {
    if i.ids.len < i.used.len { ret i.ids.len }
    ret i.used.len
}

fn inbox_find(i: *const Inbox, id: u16) -> (usize, bool) {
    var k = 0usize
    let n = inbox_slots(i)
    while k < n {
        if i.used[k] != 0u8 && i.ids[k] == id { ret (k, true) }
        k += 1usize
    }
    ret (0usize, false)
}

fn inbox_pending(i: *const Inbox) -> usize {
    var count = 0usize
    var k = 0usize
    let n = inbox_slots(i)
    while k < n {
        if i.used[k] != 0u8 { count += 1usize }
        k += 1usize
    }
    ret count
}

// An incoming PUBLISH or PUBREL (`src`). Answers (deliver, packet id, bytes
// to send). QoS 0: deliver, nothing to send. QoS 1: deliver and PUBACK.
// QoS 2 (method B): the id is stored and PUBREC answered, the message is
// delivered exactly once when its PUBREL arrives, with PUBCOMP; a repeated
// PUBLISH of a stored id only re-answers PUBREC. A PUBREL for an unknown id
// is answered with PUBCOMP and not delivered; `Full` when no slot is free.
fn inbox_receive(i: *Inbox, src: []const u8, dst: []u8) -> (bool, u16, usize, err) {
    let (t, te) = packet_type(src)
    if te != ok { ret (false, 0u16, 0usize, te) }
    if t == PUBREL {
        let (_, id, e) = decode_ack(src)
        if e != ok { ret (false, 0u16, 0usize, e) }
        let (n, ce) = encode_pubcomp(dst, id)
        if ce != ok { ret (false, id, 0usize, ce) }
        let (slot, found) = inbox_find(i, id)
        if !found { ret (false, id, n, ok) }
        i.used[slot] = 0u8
        ret (true, id, n, ok)
    }
    let (p, e) = decode_publish(src)
    if e != ok { ret (false, 0u16, 0usize, e) }
    if p.qos == 0u8 { ret (true, 0u16, 0usize, ok) }
    if p.qos == 1u8 {
        let (n, ae) = encode_puback(dst, p.packet_id)
        if ae != ok { ret (false, p.packet_id, 0usize, ae) }
        ret (true, p.packet_id, n, ok)
    }
    let (n, re) = encode_pubrec(dst, p.packet_id)
    if re != ok { ret (false, p.packet_id, 0usize, re) }
    let (_, stored) = inbox_find(i, p.packet_id)
    if stored { ret (false, p.packet_id, n, ok) }
    var slot = 0usize
    let count = inbox_slots(i)
    while slot < count && i.used[slot] != 0u8 { slot += 1usize }
    if slot >= count { ret (false, p.packet_id, 0usize, Full) }
    i.ids[slot] = p.packet_id
    i.used[slot] = 1u8
    ret (false, p.packet_id, n, ok)
}
