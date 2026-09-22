// `e.net.mqtt`: CONNECT (bare and with will/credentials), PUBLISH,
// SUBSCRIBE and UNSUBSCRIBE bytes fold to the replica; remaining-length
// vectors both ways and a fifth byte is Malformed; PUBLISH and CONNACK
// decode round trips; section 4.7 topic filters; QoS 1 and QoS 2 outbound
// flows produce the replica's byte stream and complete, a stray PUBCOMP is
// Invalid, retransmission carries DUP; inbound QoS 2 delivers once for a
// duplicated PUBLISH; TooSmall and Full. Each check exits with its own code.

use e.io
use e.mem
use e.net.mqtt
use e.os

fn fold(data: []const u8) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < data.len {
        h = (h ^ u64(data[i])) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buf: [128]u8 = zero
    var stream: [64]u8 = zero

    // 1: CONNECT/PUBLISH/SUBSCRIBE/UNSUBSCRIBE bytes and remaining lengths.
    let c = mqtt.connect("cl", 60u16, true)
    let (n1, e1) = mqtt.encode_connect(buf[..], &c)
    if e1 != ok || n1 != 16usize || fold(buf[..n1]) != 0x15e34035d259a6fau64 { os.exit(1i32) }
    var full = mqtt.connect("cl", 30u16, false)
    full.has_username = true
    full.username = "user"
    full.has_password = true
    full.password = "pw"
    full.has_will = true
    full.will_topic = "w/t"
    full.will_payload = "bye"
    full.will_qos = 1u8
    full.will_retain = true
    let (n2, e2) = mqtt.encode_connect(buf[..], &full)
    if e2 != ok || n2 != 36usize || fold(buf[..n2]) != 0x8c4336622f7c6366u64 { os.exit(1i32) }
    let (n3, e3) = mqtt.encode_publish(buf[..], "a/b", "hello", 1u8, false, false, 10u16)
    if e3 != ok || n3 != 14usize || fold(buf[..n3]) != 0xf07a63e9d49ff04au64 { os.exit(1i32) }
    let topics = [2]str{ "a/b", "c/#" }
    let qoss = [2]u8{ 1u8, 2u8 }
    let (n4, e4) = mqtt.encode_subscribe(stream[..], 1u16, topics[..], qoss[..])
    if e4 != ok || n4 != 16usize || fold(stream[..n4]) != 0xbf799b6250917d0u64 { os.exit(1i32) }
    let (n5, e5) = mqtt.encode_unsubscribe(stream[..], 2u16, topics[..1usize])
    if e5 != ok || n5 != 9usize || fold(stream[..n5]) != 0x2b7b77a5a643ba55u64 { os.exit(1i32) }
    let values = [6]usize{ 0usize, 127usize, 128usize, 16383usize, 16384usize, 268435455usize }
    let widths = [6]usize{ 1usize, 1usize, 2usize, 2usize, 3usize, 4usize }
    let folds = [6]u64{ fold("\x00"), fold("\x7f"), fold("\x80\x01"), fold("\xff\x7f"), fold("\x80\x80\x01"), fold("\xff\xff\xff\x7f") }
    var k = 0usize
    while k < 6usize {
        let (w, we) = mqtt.encode_remaining_length(stream[..], values[k])
        if we != ok || w != widths[k] || fold(stream[..w]) != folds[k] { os.exit(1i32) }
        let (v, used, de) = mqtt.decode_remaining_length(stream[..w])
        if de != ok || v != values[k] || used != w { os.exit(1i32) }
        k += 1usize
    }
    let (_, oe) = mqtt.encode_remaining_length(stream[..], 268435456usize)
    if oe != mqtt.Invalid { os.exit(1i32) }
    let (_, _, me) = mqtt.decode_remaining_length("\x80\x80\x80\x80\x01")
    if me != mqtt.Malformed { os.exit(1i32) }
    let (_, _, se) = mqtt.decode_remaining_length("\x80\x80")
    if se != mqtt.TooSmall { os.exit(1i32) }

    // 2: PUBLISH and CONNACK decode round trips.
    let (p, pe) = mqtt.decode_publish(buf[..n3])
    if pe != ok || !mem.eq[u8](p.topic, "a/b") || !mem.eq[u8](p.payload, "hello") { os.exit(2i32) }
    if p.qos != 1u8 || p.retain || p.dup || p.packet_id != 10u16 { os.exit(2i32) }
    let (t, te) = mqtt.packet_type(buf[..n3])
    if te != ok || t != 3u8 { os.exit(2i32) }
    let (rl, hb, re) = mqtt.remaining_length(buf[..n3])
    if re != ok || rl != 12usize || hb != 2usize { os.exit(2i32) }
    let (present, code, ce) = mqtt.decode_connack("\x20\x02\x01\x00")
    if ce != ok || !present || code != 0u8 { os.exit(2i32) }
    let (_, truncated) = mqtt.decode_publish(buf[..n3 - 1usize])
    if truncated != mqtt.TooSmall { os.exit(2i32) }
    let (kind, id, ae) = mqtt.decode_ack("\x62\x02\x00\x05")
    if ae != ok || kind != 6u8 || id != 5u16 { os.exit(2i32) }

    // 3: topic filters from section 4.7.
    if !mqtt.topic_matches("sport/tennis/player1/#", "sport/tennis/player1") { os.exit(3i32) }
    if !mqtt.topic_matches("sport/tennis/player1/#", "sport/tennis/player1/ranking") { os.exit(3i32) }
    if !mqtt.topic_matches("sport/tennis/player1/#", "sport/tennis/player1/score/wimbledon") { os.exit(3i32) }
    if !mqtt.topic_matches("sport/#", "sport") { os.exit(3i32) }
    if mqtt.topic_matches("sport/+", "sport") { os.exit(3i32) }
    if !mqtt.topic_matches("sport/+", "sport/") { os.exit(3i32) }
    if !mqtt.topic_matches("+/+", "/finance") { os.exit(3i32) }
    if !mqtt.topic_matches("/+", "/finance") { os.exit(3i32) }
    if mqtt.topic_matches("+", "/finance") { os.exit(3i32) }
    if mqtt.topic_matches("#", "$SYS/monitor") { os.exit(3i32) }
    if mqtt.topic_matches("+/monitor/Clients", "$SYS/monitor/Clients") { os.exit(3i32) }
    if !mqtt.topic_matches("$SYS/#", "$SYS/monitor") { os.exit(3i32) }
    if !mqtt.topic_matches("$SYS/monitor/+", "$SYS/monitor/Clients") { os.exit(3i32) }
    if mqtt.topic_matches("sport/tennis/+", "sport/tennis/player1/ranking") { os.exit(3i32) }
    if !mqtt.valid_filter("sport/+/#") || mqtt.valid_filter("sport/#/x") || mqtt.valid_filter("sport+") { os.exit(3i32) }

    // 4: QoS 1 then QoS 2 outbound; the client's byte stream folds to the replica.
    var ids: [4]u16 = zero
    var state: [4]u8 = zero
    var o = mqtt.outbox(ids[..], state[..])
    var sent = 0usize
    let (id1, w1, pe1) = mqtt.publish(&o, 1u8, stream[sent..], "a/b", "hi")
    if pe1 != ok || id1 != 1u16 || mqtt.outbox_pending(&o) != 1usize { os.exit(4i32) }
    sent += w1
    let (r1, done1, ae1) = mqtt.outbox_receive(&o, "\x40\x02\x00\x01", buf[..])
    if ae1 != ok || r1 != 0usize || !done1 || mqtt.outbox_pending(&o) != 0usize { os.exit(4i32) }
    let (id2, w2, pe2) = mqtt.publish(&o, 2u8, stream[sent..], "a/b", "hi")
    if pe2 != ok || id2 != 2u16 { os.exit(4i32) }
    sent += w2
    let (r2, done2, ae2) = mqtt.outbox_receive(&o, "\x50\x02\x00\x02", stream[sent..])
    if ae2 != ok || r2 != 4usize || done2 || mqtt.outbox_pending(&o) != 1usize { os.exit(4i32) }
    sent += r2
    let (r3, done3, ae3) = mqtt.outbox_receive(&o, "\x70\x02\x00\x02", buf[..])
    if ae3 != ok || r3 != 0usize || !done3 || mqtt.outbox_pending(&o) != 0usize { os.exit(4i32) }
    if sent != 26usize || fold(stream[..sent]) != 0x919902f42d3ad458u64 { os.exit(4i32) }
    let (_, _, stray) = mqtt.outbox_receive(&o, "\x70\x02\x00\x07", buf[..])
    if stray != mqtt.Invalid { os.exit(4i32) }
    let (id3, _, pe3) = mqtt.publish(&o, 2u8, buf[..], "a/b", "hi")
    if pe3 != ok || id3 != 3u16 { os.exit(4i32) }
    let (slot_id, slot_state) = mqtt.outbox_slot(&o, 0usize)
    if slot_id != 3u16 || slot_state != 2u8 { os.exit(4i32) }
    let (rn, rte) = mqtt.outbox_retransmit(&o, 0usize, buf[..], "a/b", "hi")
    if rte != ok || fold(buf[..rn]) != 0x407900fab3bf6659u64 { os.exit(4i32) }
    let (_, free_slot) = mqtt.outbox_retransmit(&o, 1usize, buf[..], "a/b", "hi")
    if free_slot != mqtt.Invalid { os.exit(4i32) }
    let (q0_id, q0_n, q0_e) = mqtt.publish(&o, 0u8, buf[..], "a/b", "hi")
    if q0_e != ok || q0_id != 0u16 || q0_n != 9usize || mqtt.outbox_pending(&o) != 1usize { os.exit(4i32) }

    // 5: inbound QoS 2 delivers once for a duplicated PUBLISH; QoS 1 and 0 at once.
    var in_ids: [2]u16 = zero
    var in_used: [2]u8 = zero
    var ib = mqtt.inbox(in_ids[..], in_used[..])
    let (pn, ppe) = mqtt.encode_publish(buf[..], "a/b", "hi", 2u8, false, false, 5u16)
    if ppe != ok { os.exit(5i32) }
    var replies = 0usize
    let (d1, i1, s1, ie1) = mqtt.inbox_receive(&ib, buf[..pn], stream[replies..])
    if ie1 != ok || d1 || i1 != 5u16 || s1 != 4usize || mqtt.inbox_pending(&ib) != 1usize { os.exit(5i32) }
    replies += s1
    let (d2, _, s2, ie2) = mqtt.inbox_receive(&ib, buf[..pn], stream[replies..])
    if ie2 != ok || d2 || s2 != 4usize || mqtt.inbox_pending(&ib) != 1usize { os.exit(5i32) }
    replies += s2
    let (d3, i3, s3, ie3) = mqtt.inbox_receive(&ib, "\x62\x02\x00\x05", stream[replies..])
    if ie3 != ok || !d3 || i3 != 5u16 || s3 != 4usize || mqtt.inbox_pending(&ib) != 0usize { os.exit(5i32) }
    replies += s3
    if fold(stream[..replies]) != 0xc3ad59a23e41d380u64 { os.exit(5i32) }
    let (d4, _, s4, ie4) = mqtt.inbox_receive(&ib, "\x62\x02\x00\x05", buf[..])
    if ie4 != ok || d4 || s4 != 4usize { os.exit(5i32) }
    let (d5, i5, s5, ie5) = mqtt.inbox_receive(&ib, "\x32\x09\x00\x03a/b\x00\x07hi", buf[..])
    if ie5 != ok || !d5 || i5 != 7u16 || s5 != 4usize || fold(buf[..s5]) != fold("\x40\x02\x00\x07") { os.exit(5i32) }
    let (d6, _, s6, ie6) = mqtt.inbox_receive(&ib, "\x30\x07\x00\x03a/bhi", buf[..])
    if ie6 != ok || !d6 || s6 != 0usize { os.exit(5i32) }

    // 6: TooSmall and Full.
    let (_, small1) = mqtt.encode_publish(buf[..8usize], "a/b", "hello", 1u8, false, false, 10u16)
    if small1 != mqtt.TooSmall { os.exit(6i32) }
    let (_, small2) = mqtt.encode_connect(buf[..3usize], &c)
    if small2 != mqtt.TooSmall { os.exit(6i32) }
    let (_, small3) = mqtt.encode_puback(buf[..3usize], 1u16)
    if small3 != mqtt.TooSmall { os.exit(6i32) }
    var tiny_ids: [1]u16 = zero
    var tiny_state: [1]u8 = zero
    var tiny = mqtt.outbox(tiny_ids[..], tiny_state[..])
    let (_, _, first) = mqtt.publish(&tiny, 1u8, buf[..], "a", "b")
    let (_, _, second) = mqtt.publish(&tiny, 1u8, buf[..], "a", "b")
    if first != ok || second != mqtt.Full { os.exit(6i32) }
    let (pn6, _) = mqtt.encode_publish(buf[..], "a", "b", 2u8, false, false, 9u16)
    let (pn7, _) = mqtt.encode_publish(buf[64usize..], "a", "b", 2u8, false, false, 10u16)
    let (_, _, _, in1) = mqtt.inbox_receive(&ib, buf[..pn6], stream[..])
    let (_, _, _, in2) = mqtt.inbox_receive(&ib, buf[64usize..64usize + pn7], stream[..])
    if in1 != ok || in2 != ok || mqtt.inbox_pending(&ib) != 2usize { os.exit(6i32) }
    let (pn8, _) = mqtt.encode_publish(buf[..], "a", "b", 2u8, false, false, 11u16)
    let (_, _, _, in3) = mqtt.inbox_receive(&ib, buf[..pn8], stream[..])
    if in3 != mqtt.Full { os.exit(6i32) }

    try io.print("net mqtt ok\n")
    ret ok
}
