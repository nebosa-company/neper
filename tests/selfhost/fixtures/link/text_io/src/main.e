// `e.text.io`: lines read from UTF-8 with LF, CRLF, a bare CR and an unterminated
// last line through a capacity smaller than the text, then End; a UTF-16LE source
// with a BOM through `reader_bom` and through `reader` with the encoding given; a
// line over the limit; an invalid byte under Reject and under Replace; `read_all`
// with and without a limit; a writer to UTF-16BE with a BOM and CRLF read back by
// the reader; a writer to UTF-8 with LF. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.text.encoding as encoding
use e.text.io as text

fn source_of(a: *mem.Arena, data: []const u8) -> io.Reader {
    let (state, state_error) = mem.alloc[io.SliceReader](a, 1usize)
    if state_error != ok { os.exit(99) }
    state[0] = io.SliceReader { data: data, off: 0usize }
    ret io.slice_reader(&state[0])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let utf8 = "first line\nsecond\r\nbare\rcr\n\nlast"
    let (r0, e1) = text.reader(a, source_of(a, utf8), .Utf8, .Reject, 8usize)
    if e1 != ok { os.exit(1) }
    var r = r0
    let (l1, e2) = text.read_line(a, &r, 1024usize)
    if e2 != ok || !str.eq(l1, "first line") { os.exit(2) }
    let (l2, e3) = text.read_line(a, &r, 1024usize)
    if e3 != ok || !str.eq(l2, "second") { os.exit(3) }
    let (l3, e4) = text.read_line(a, &r, 1024usize)
    if e4 != ok || !str.eq(l3, "bare\rcr") { os.exit(4) }
    let (l4, e5) = text.read_line(a, &r, 1024usize)
    if e5 != ok || l4.len != 0usize { os.exit(5) }
    let (l5, e6) = text.read_line(a, &r, 1024usize)
    if e6 != ok || !str.eq(l5, "last") { os.exit(6) }
    let (l6, e7) = text.read_line(a, &r, 1024usize)
    if e7 != text.End { os.exit(7) }
    let (l7, e8) = text.read_line(a, &r, 1024usize)
    if e8 != text.End { os.exit(8) }
    // UTF-16LE with a BOM: "hi\nyo" -- sniffed, and told.
    let utf16 = "\xff\xfeh\x00i\x00\n\x00y\x00o\x00"
    let (b0, e9) = text.reader_bom(a, source_of(a, utf16), .Utf8, .Reject, 8usize)
    if e9 != ok { os.exit(9) }
    var b = b0
    let (m1, e10) = text.read_line(a, &b, 100usize)
    if e10 != ok || !str.eq(m1, "hi") { os.exit(10) }
    let (m2, e11) = text.read_line(a, &b, 100usize)
    if e11 != ok || !str.eq(m2, "yo") { os.exit(11) }
    let (m3, e12) = text.read_line(a, &b, 100usize)
    if e12 != text.End { os.exit(12) }
    let (t0, e13) = text.reader(a, source_of(a, utf16), .Utf16Le, .Reject, 8usize)
    if e13 != ok { os.exit(13) }
    var t = t0
    let (all16, e14) = text.read_all(a, &t, 100usize)
    if e14 != ok || !str.eq(all16, "hi\nyo") { os.exit(14) }
    // Limits and invalid bytes.
    let (long0, e15) = text.reader(a, source_of(a, "0123456789abcdef\n"), .Utf8, .Reject, 8usize)
    if e15 != ok { os.exit(15) }
    var long = long0
    let (over, e16) = text.read_line(a, &long, 10usize)
    if e16 != text.TooLarge { os.exit(16) }
    let (bad0, e17) = text.reader(a, source_of(a, "ok\nb\xffd\n"), .Utf8, .Reject, 8usize)
    if e17 != ok { os.exit(17) }
    var bad = bad0
    let (ok_line, e18) = text.read_line(a, &bad, 100usize)
    if e18 != ok || !str.eq(ok_line, "ok") { os.exit(18) }
    let (bad_line, e19) = text.read_line(a, &bad, 100usize)
    if e19 != text.Invalid { os.exit(19) }
    let (soft0, e20) = text.reader(a, source_of(a, "b\xffd\n"), .Utf8, .Replace, 8usize)
    if e20 != ok { os.exit(20) }
    var soft = soft0
    let (soft_line, e21) = text.read_line(a, &soft, 100usize)
    if e21 != ok || !str.eq(soft_line, "b\xef\xbf\xbdd") { os.exit(21) }
    let (all0, e22) = text.reader(a, source_of(a, utf8), .Utf8, .Reject, 8usize)
    if e22 != ok { os.exit(22) }
    var all = all0
    let (everything, e23) = text.read_all(a, &all, 1024usize)
    if e23 != ok || !str.eq(everything, utf8) { os.exit(23) }
    let (capped0, e24) = text.reader(a, source_of(a, utf8), .Utf8, .Reject, 8usize)
    if e24 != ok { os.exit(24) }
    var capped = capped0
    let (too_much, e25) = text.read_all(a, &capped, 10usize)
    if e25 != text.TooLarge { os.exit(25) }
    // The writer to UTF-16BE with a BOM and CRLF, read back.
    var buffer: [128]u8 = zero
    var sink_state = io.SliceWriter { data: buffer[..], off: 0usize }
    let (w0, e26) = text.writer(a, io.slice_writer(&sink_state), .Utf16Be, true, .CrLf, 8usize)
    if e26 != ok { os.exit(26) }
    var w = w0
    if text.write_line(&w, "ab") != ok || text.write(&w, "c\xc3\xa9") != ok || text.flush(&w) != ok { os.exit(27) }
    let written = buffer[..sink_state.off]
    if !str.eq(written, "\xfe\xff\x00a\x00b\x00\r\x00\n\x00c\x00\xe9") { os.exit(28) }
    let (back0, e27) = text.reader_bom(a, source_of(a, written), .Utf8, .Reject, 8usize)
    if e27 != ok { os.exit(29) }
    var back = back0
    let (k1, e28) = text.read_line(a, &back, 100usize)
    if e28 != ok || !str.eq(k1, "ab") { os.exit(30) }
    let (k2, e29) = text.read_line(a, &back, 100usize)
    if e29 != ok || !str.eq(k2, "c\xc3\xa9") { os.exit(31) }
    var plain_state = io.SliceWriter { data: buffer[..], off: 0usize }
    let (p0, e30) = text.writer(a, io.slice_writer(&plain_state), .Utf8, false, .Native, 8usize)
    if e30 != ok { os.exit(32) }
    var p = p0
    if text.write_line(&p, "a longer line than the staging holds") != ok { os.exit(33) }
    if !str.eq(buffer[..plain_state.off], "a longer line than the staging holds\n") { os.exit(34) }
    let (tiny, e31) = text.writer(a, io.slice_writer(&plain_state), .Utf8, false, .Lf, 2usize)
    if e31 != text.Invalid { os.exit(35) }
    ret ok
}
