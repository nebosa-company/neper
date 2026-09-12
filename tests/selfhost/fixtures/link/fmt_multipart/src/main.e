// `e.fmt.multipart`: a three-part message with a preamble read in 5-byte source
// chunks -- headers, a body holding CR LF and dashes that are not the delimiter, an
// empty header block, a skipped body -- and the closing delimiter; the writer's
// output read back by the reader; refusals for a bad boundary, a part limit of two,
// a byte limit below the message, a missing closing delimiter. Every check has its
// own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.mime as mime
use e.fmt.multipart as multipart

// A source that hands out at most `chunk` bytes per read, to exercise the window.
type Trickle = struct { data: []const u8, off: usize, chunk: usize }

fn trickle_read(ctx: *void, dst: []u8) -> (usize, err) {
    var s = mem.cast[*Trickle](ctx)
    if s.off >= s.data.len { ret (0usize, io.End) }
    var take = dst.len
    if take > s.chunk { take = s.chunk }
    if s.data.len - s.off < take { take = s.data.len - s.off }
    mem.copy[u8](dst[..take], s.data[s.off..s.off + take])
    s.off += take
    ret (take, ok)
}

fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

fn read_all(body: *io.Reader, out: []u8) -> (usize, err) {
    var filled = 0usize
    while true {
        let (count, read_error) = io.read(body, out[filled..])
        if read_error == io.End { ret (filled, ok) }
        if read_error != ok { ret (filled, read_error) }
        filled += count
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let message = "preamble text\r\n--b0und=ary\r\nContent-Type: text/plain\r\nX-Name: first\r\n\r\nhello\r\n--not it\r\n-- dashes\r\n--b0und=ary\r\n\r\nsecond body\r\n--b0und=ary\r\nX-Name: third\r\n\r\nskipped\r\n--b0und=ary--\r\nepilogue"
    let (storage, s_error) = aligned(a, multipart.storage_required())
    if s_error != ok { os.exit(1) }
    var source = Trickle { data: message, off: 0usize, chunk: 5usize }
    let (r0, e1) = multipart.reader(storage, io.Reader { ctx: mem.cast[*void](&source), read: trickle_read }, "b0und=ary", 8u32, 100000u64)
    if e1 != ok { os.exit(2) }
    var r = r0
    var out: [256]u8 = zero
    let (p1, has1, e2) = multipart.reader_next_err(&r)
    if e2 != ok || !has1 { os.exit(3) }
    if p1.headers.len != 2usize || !str.eq(p1.headers[1].name, "X-Name") || !str.eq(p1.headers[1].value, "first") { os.exit(4) }
    var body1 = p1.body
    let (n1, e3) = read_all(&body1, out[0..])
    if e3 != ok || !str.eq(out[..n1], "hello\r\n--not it\r\n-- dashes") { os.exit(5) }
    let (p2, has2, e4) = multipart.reader_next_err(&r)
    if e4 != ok || !has2 || p2.headers.len != 0usize { os.exit(6) }
    var body2 = p2.body
    let (n2, e5) = read_all(&body2, out[0..])
    if e5 != ok || !str.eq(out[..n2], "second body") { os.exit(7) }
    // The third part's body is skipped by asking for the next.
    let (p3, has3, e6) = multipart.reader_next_err(&r)
    if e6 != ok || !has3 || p3.headers.len != 1usize || !str.eq(p3.headers[0].value, "third") { os.exit(8) }
    let (p4, has4, e7) = multipart.reader_next_err(&r)
    if e7 != ok || has4 { os.exit(9) }
    let (p5, has5, e8) = multipart.reader_next_err(&r)
    if e8 != ok || has5 { os.exit(10) }
    // The writer, read back.
    var sink_buffer: [512]u8 = zero
    var sink_state = io.SliceWriter { data: sink_buffer[..], off: 0usize }
    let (w_storage, w_error) = aligned(a, 64usize)
    if w_error != ok { os.exit(11) }
    let (w0, e9) = multipart.writer(w_storage, io.slice_writer(&sink_state), "xyz")
    if e9 != ok { os.exit(12) }
    var w = w0
    var headers: [1]mime.Header = zero
    headers[0] = mime.Header { name: "Content-Type", value: "text/plain" }
    let (part_writer, e10) = multipart.start_part(&w, headers[0..])
    if e10 != ok { os.exit(13) }
    var pw = part_writer
    if io.write_all(&pw, "one\r\n--xy") != ok { os.exit(14) }
    let (part_writer2, e11) = multipart.start_part(&w, zero)
    if e11 != ok { os.exit(15) }
    var pw2 = part_writer2
    if io.write_all(&pw2, "two") != ok { os.exit(16) }
    if multipart.finish(&w) != ok { os.exit(17) }
    let written = sink_buffer[..sink_state.off]
    if !str.eq(written, "--xyz\r\nContent-Type: text/plain\r\n\r\none\r\n--xy\r\n--xyz\r\n\r\ntwo\r\n--xyz--\r\n") { os.exit(18) }
    var back_source = Trickle { data: written, off: 0usize, chunk: 512usize }
    let (back0, e12) = multipart.reader(storage, io.Reader { ctx: mem.cast[*void](&back_source), read: trickle_read }, "xyz", 8u32, 100000u64)
    if e12 != ok { os.exit(19) }
    var back = back0
    let (q1, hq1, e13) = multipart.reader_next_err(&back)
    if e13 != ok || !hq1 || q1.headers.len != 1usize { os.exit(20) }
    var qbody = q1.body
    let (m1, e14) = read_all(&qbody, out[0..])
    if e14 != ok || !str.eq(out[..m1], "one\r\n--xy") { os.exit(21) }
    let (q2, hq2, e15) = multipart.reader_next_err(&back)
    if e15 != ok || !hq2 { os.exit(22) }
    var qbody2 = q2.body
    let (m2, e16) = read_all(&qbody2, out[0..])
    if e16 != ok || !str.eq(out[..m2], "two") { os.exit(23) }
    let (q3, hq3, e17) = multipart.reader_next_err(&back)
    if e17 != ok || hq3 { os.exit(24) }
    // Refusals.
    var bad_source = Trickle { data: message, off: 0usize, chunk: 64usize }
    let bad_reader = io.Reader { ctx: mem.cast[*void](&bad_source), read: trickle_read }
    let (b1, e18) = multipart.reader(storage, bad_reader, "bad boundary ", 8u32, 100000u64)
    if e18 != multipart.InvalidBoundary { os.exit(25) }
    let (b2, e19) = multipart.reader(storage, bad_reader, "", 8u32, 100000u64)
    if e19 != multipart.InvalidBoundary { os.exit(26) }
    let (w1, e20) = multipart.writer(w_storage, io.slice_writer(&sink_state), "no\"quote")
    if e20 != multipart.InvalidBoundary { os.exit(27) }
    let (few0, e21) = multipart.reader(storage, bad_reader, "b0und=ary", 2u32, 100000u64)
    if e21 != ok { os.exit(28) }
    var few = few0
    let (f1, hf1, e22) = multipart.reader_next_err(&few)
    let (f2, hf2, e23) = multipart.reader_next_err(&few)
    if e22 != ok || e23 != ok { os.exit(29) }
    let (f3, hf3, e24) = multipart.reader_next_err(&few)
    if e24 != multipart.TooLarge { os.exit(30) }
    var small_source = Trickle { data: message, off: 0usize, chunk: 64usize }
    let (small0, e25) = multipart.reader(storage, io.Reader { ctx: mem.cast[*void](&small_source), read: trickle_read }, "b0und=ary", 8u32, 40u64)
    if e25 != ok { os.exit(31) }
    var small = small0
    let (g1, hg1, e26) = multipart.reader_next_err(&small)
    if e26 != multipart.TooLarge { os.exit(32) }
    var cut_source = Trickle { data: message[..80], off: 0usize, chunk: 64usize }
    let (cut0, e27) = multipart.reader(storage, io.Reader { ctx: mem.cast[*void](&cut_source), read: trickle_read }, "b0und=ary", 8u32, 100000u64)
    if e27 != ok { os.exit(33) }
    var cut = cut0
    let (c1, hc1, e28) = multipart.reader_next_err(&cut)
    if e28 != ok || !hc1 { os.exit(34) }
    var cbody = c1.body
    let (k1, e29) = read_all(&cbody, out[0..])
    if e29 != multipart.Invalid { os.exit(35) }
    ret ok
}
