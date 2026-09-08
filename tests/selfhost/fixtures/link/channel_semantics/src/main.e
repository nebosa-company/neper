// `e.channel`'s uncontended behaviour, which is where the fence's promises live: a
// capacity of zero is refused, the ring wraps, what is buffered stays receivable after
// a close and `Closed` comes only once it is drained, and a second instantiation is a
// second channel with its own state and element type.
use e.mem
use e.channel
use e.sync

error Failed

fn main(a: *mem.Arena) -> err {
    // A capacity of zero is invalid.
    let (bad, bad_error) = channel.init[i64](a, 0usize)
    if bad_error != sync.Invalid { ret Failed }

    let (made, init_error) = channel.init[i64](a, 3usize)
    if init_error != ok { ret init_error }
    var c = made
    if channel.capacity[i64](&c) != 3usize { ret Failed }
    if channel.len[i64](&c) != 0usize { ret Failed }

    // An empty channel that is open has nothing to give and says so without an error.
    let (nothing, took, empty_error) = channel.try_receive[i64](&c)
    if took || empty_error != ok { ret Failed }

    // Fill it, and the fourth send finds it full.
    var at = 0i64
    while at < 3i64 {
        let (sent, send_error) = channel.try_send[i64](&c, at)
        if !sent || send_error != ok { ret Failed }
        at += 1i64
    }
    if channel.len[i64](&c) != 3usize { ret Failed }
    let (overflowed, full_error) = channel.try_send[i64](&c, 99i64)
    if overflowed || full_error != ok { ret Failed }

    // First in, first out.
    let (first, first_error) = channel.receive[i64](&c)
    if first_error != ok || first != 0i64 { ret Failed }
    if channel.len[i64](&c) != 2usize { ret Failed }

    // The ring wraps: a send after a receive reuses the slot that was freed.
    let (wrapped, wrap_error) = channel.try_send[i64](&c, 3i64)
    if !wrapped || wrap_error != ok { ret Failed }
    var expected = 1i64
    while expected < 4i64 {
        let (value, receive_error) = channel.receive[i64](&c)
        if receive_error != ok || value != expected { ret Failed }
        expected += 1i64
    }
    if channel.len[i64](&c) != 0usize { ret Failed }

    // What is buffered stays receivable after a close; `Closed` comes only once drained.
    let (kept, kept_error) = channel.try_send[i64](&c, 42i64)
    if !kept || kept_error != ok { ret Failed }
    if channel.close[i64](&c) != ok { ret Failed }
    if channel.close[i64](&c) != channel.Closed { ret Failed }
    let (survivor, survivor_error) = channel.receive[i64](&c)
    if survivor_error != ok || survivor != 42i64 { ret Failed }
    let (gone, gone_error) = channel.receive[i64](&c)
    if gone_error != channel.Closed { ret Failed }
    let (drained, drained_took, drained_error) = channel.try_receive[i64](&c)
    if drained_took || drained_error != channel.Closed { ret Failed }

    // A closed channel refuses sends.
    if channel.send[i64](&c, 1i64) != channel.Closed { ret Failed }
    let (refused, refused_error) = channel.try_send[i64](&c, 1i64)
    if refused || refused_error != channel.Closed { ret Failed }

    // A second instantiation is a second channel, with its own state and element type.
    let (made_bytes, bytes_error) = channel.init[u8](a, 2usize)
    if bytes_error != ok { ret bytes_error }
    var b = made_bytes
    if channel.capacity[u8](&b) != 2usize { ret Failed }
    let (byte_sent, byte_error) = channel.try_send[u8](&b, 7u8)
    if !byte_sent || byte_error != ok { ret Failed }
    let (byte_value, byte_took, byte_receive_error) = channel.try_receive[u8](&b)
    if !byte_took || byte_receive_error != ok || byte_value != 7u8 { ret Failed }
    ret ok
}
