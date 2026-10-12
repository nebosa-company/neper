// `e.ui.terminal`: hand-written streams for wrap, SGR, erase, scroll regions, scrollback, the alternate screen,
// split UTF-8, wide cells, resize, replies, titles, palette and line drawing; then a 900-item generated stream
// (scripts/gen_ui_terminal_test.py, an independent Python model) whose final buffer hash, cursor and line count
// must match whether the stream is fed whole or in 7-byte pieces. Each check exits with its own code.

use e.mem
use e.os
use e.ui.terminal as term

// BEGIN GENERATED (scripts/gen_ui_terminal_test.py)
fn model_stream() -> str { ret "\x0D\x0Aterminal\x1B[1B\x1B[3D\x1B[2Bhello\x1BDworldxx\xC3\xA9\x1B[2D\x1B[6n\x1B[4Bworldxxneper\xE4\xB8\x96\x1B[3D\x1B[shello\x1B[39mxxterminal\x1B[4T\x1B[4K\x1B[3P\x0D\x0A0123456789ABCDEFGHIJ\x1B[2;19H\x0D\x0A\x1B[3X\x1B[3P\x1B[1C\x1B[2@\x1B[2K\x1B[1@\x1B[3C\x0D\x0A\x1B[4L\x1B[1Pneper\x1B[?7hABCDEFGHIJ\x1B[4JABCDEFGHIJ\x09\x1B[1L\x1B[?6lxxterminalworld\x1B[2J\x1B[7;13H\x1B[2C\x1BD\x1B[2d\x1BEABCDEFGHIJ\xE7\x95\x8C\x1B[2MhelloworldABCDEFGHIJhello\x1B[3m\xE7\x95\x8C\x1B[m\x1B[s\x1B[4M\x09\x09terminal\x1B[1Mhelloterminalhello\x0D\x0A\x1B[1Bxxxxneper\x1B[1Axx\x08ABCDEFGHIJneper\x1B[4Lhello\x1B[4P\x1B[1Jhello\x1B[3K\x1B[uxxworld\x1B[2L\x1B[1T\x1B[3S\x1B[3C\x1B[2L\x0D\x0A\x1B[9;18H\x1B[3S\x1B[4;8H\x09\x1B[4;17H\x1B[1L0123456789terminalworld\x1B[r\x1BM\x08worldworld\x1B[4l\x0D\x0Aterminal\x1B[r\x1B[6n\x0D\x0A\x1B[1C\x09\x1B[16Gterminal\x1B[1K\x1B[4M\x09\x1B[2Cworldworld\x1B[2P\x1B[r\x1B[2L\x1B[2Thello\x1B[6nxx\x1B[4E0123456789helloworldxx0123456789\x1B[3K\x1B[2@ABCDEFGHIJ\x0D\x0A\x1B]0;t84\x07\x1B[4S\x1B[2E\x1B[1S\x1B8\x1B[2Aworld\x1B[?7h\x1B[3B\x1B[4S\x1B[1Dworldhello\x1B[4D\x1B[1A\x1BM\x1B[2S\x1B[4d\x1B[4T\x1B[9;9H\x1B[15Gterminalterminal\x1BMABCDEFGHIJterminalworld\x1B[1J\x1B[3EneperterminalABCDEFGHIJterminal\x1B[2FABCDEFGHIJ\x1BE\x09\x0D\x0A\xE4\xB8\x96\x0D\x0A\x0D\x0AABCDEFGHIJ\x08neper\x1B[4P\x1B[4A\x0D\x0A\x1B[1;4rhelloneperhello\x1B[3F\x1B[4E\x1B[4dxx\x1B[0m\x1B[4FneperABCDEFGHIJ0123456789hello\x1B[2;9Hterminalneper\x1B[3@\x1B[1E\x1B[uhelloneperworldneper\x1B[2Jterminal\x1B[sneper\x0D\x0AneperhelloABCDEFGHIJ\x1B[2T\x1B[2X\x1B7\x1B[6n\x1BD\x1B[3M\x1B[8G\x0D\x0A0123456789\x1B[2b\x09\x0D\x0A0123456789helloABCDEFGHIJ\x1B[4dhelloABCDEFGHIJ\x08\x1B[sxxABCDEFGHIJhello\x1B]0;t23\x07neper\x1B7neper\x0D\x0A\x1B[2Kneperneperhello\x0D\x0A\x08terminalxx\x1B[8G\x1B[1A0123456789world\x09\x1B[4Bneper\x0D\x0A\x1B[2;19H\x1B[4E\x1B[4Kneper\x1B[1;8r\x1B[2@\x1B[1S\x1B[3m\x1B[1L\x08\x1BEABCDEFGHIJABCDEFGHIJ\x1B[sterminalhello\x1B]0;t8\x07\x1B[1S\x1B[1S\x1B[4b01234567890123456789world\x1B[8G\x1B[6n\x1B]0;t63\x07\x08terminal\x1B[1J\x1B[6n\x1B[3G\x1B[3EABCDEFGHIJ\x1B[u\x0D\x0A\x1B[44mABCDEFGHIJABCDEFGHIJABCDEFGHIJ\x1B[3J\x1B[?1049l\x1B[?7h\x1B[10Gterminalneper\x1B]0;t9\x07\x1B[3P\x09worldxxworld\x1B[3S\x08xx\x1B[3SABCDEFGHIJ\x08terminal\x1B[1Mhello\x1B[s\x1BD\x0D\x0A\x1B[4E\x0D\x0A\x08\x0D\x0A0123456789\x0D\x0Aneper\x1B[4Kworld\x1B[3Aneperterminal\x09\x1B[3C\xE7\x95\x8Cneperhello\x1B[2Jneper\x1BE\x0D\x0A0123456789\x08\xC3\xA9\x1B[6n\x09\x1B[2T\x1B[1C\x1B[4@\x1B[3E\x1B[2Bterminal\xE7\x95\x8CneperABCDEFGHIJ\x1B[6nterminal\x1B[5;16H\x1B[s\x09world\x1B[1Fxx\x1B[2T\x1BM\x1B[4Pxxworldworld\x0D\x0A\x1B[3Cneper0123456789\x1B[1G\x1B[4@\xE4\xB8\x96\x08neper\x1B[4Bxx\x08ABCDEFGHIJ\x1B[2Sneperterminal\x09\x1B[4P\x0D\x0Aworldterminal\x1B[4Xhello\x09\x1B[4P0123456789worldworld\x1B[s0123456789\x1B[u\x1B[1P\x1B[1Bworld\x1B[3BABCDEFGHIJxx\x1B[1@hello\x0D\x0A\x1B[48;2;198;133;114m\x1B[1A\x1B[4Jneper\x1B[8;17Hxxhello\xE7\x95\x8Chelloterminal\x1B[6n\xC3\xA9world\x1B[3@terminalABCDEFGHIJ\x0D\x0A\x1B[3@\x1B[2M0123456789ABCDEFGHIJ\x1B[2C\x1B[10G\x1B[8G\x1B[4l0123456789hello\x1B[2Xterminal\xC3\xA9\x1B[4EworldxxterminalABCDEFGHIJworld\x09\x1BM\x1B[1Dneperworld\x1B[4Sneper\x1B[4b\x08\x0D\x0A\x1B8helloneperneper\xC3\xA9\x1B[13G\x0D\x0A\x1B[4Jhello\x1B[2X\x08\x1B[2P\x0D\x0A\x08\x1B[1X\x1B[2@\x1B[1M\x08terminal0123456789neperABCDEFGHIJxx\x0D\x0A\x08neper\x1B[3B\x1B[u\x1B[3K\x0D\x0AABCDEFGHIJ\x1B[r\x1B[1Chello\x1B[?1049l\x1B[3M\x1BDterminalhello\x1B[2J\x1B[6;11H\x1B]0;t46\x07\x1B[2C\x09\x1B[2F\xC3\xA9\x1B[4B\x1B[3Tterminalhelloxxworldterminal\x1B[u\x1B8world\xC3\xBC\x1B[sABCDEFGHIJ\x1B[s\x1B[3Dneper\x1B[3dABCDEFGHIJworld\x1B8worldworldxxneperterminalworld\x1B[2S\x1B[4Dhelloterminal0123456789\x1BMneperhelloworld\x1B[44m\x1B[1dABCDEFGHIJ\x1B[u\x1B[2Lneper\x0D\x0Ahelloneperxx\x1B[6n01234567890123456789\x0D\x0A\xE7\x95\x8Cxx\x0D\x0Aworld0123456789\x1B[4Tterminal0123456789\x09\x1B[2T\x1B[1T\x1B[4F\x1B[4dABCDEFGHIJ\x0D\x0A\xC3\xA9\x0D\x0A\x1B[m\x1B[2L\x09\x1B[2Mterminalterminal0123456789terminal\x1B[4L\x1B[2Fhello\x1B[4Exx\x1B[2Lneperworld\x1B[1Fterminal\x1B[10G0123456789terminal\x0D\x0Axx\x1B[1M\x1B[1;5r\x1B[2M\x1B[4h\x1B[2G\x09\x1B[4F\x0D\x0AworldABCDEFGHIJhello\x1B[sABCDEFGHIJ\x0D\x0Aterminal\x1B[3P\x1B[3@\x1B[7;13H\x1B[4L\x1B[2Phello\x1B[4Xterminal\x1B[r\x1B]0;t22\x07\x1B[?1049hhelloneper\x1BM0123456789\x1BE\x1B[shello\x1B[1E\x1B[1K0123456789\x1B[2M0123456789xx\x1B[uworldterminal0123456789ABCDEFGHIJ\x1B[2;12H\x1B[2d\x0D\x0A\x1B[4dneper\x1B[2X\x1B[2d\x0D\x0A\x08worldterminalABCDEFGHIJABCDEFGHIJ\x0D\x0A\x080123456789hello\x1B[1S\x1B[4L\x1B[1Sxx\x1B[3Mterminal\x08\x1B[3E\x0D\x0A\x1B[4Cworld\x1B[1b0123456789\x1B[3d\x1B[3mxx\x1B[4@\x1B[1Lterminalxx\x1B[1Bhello\x1B[3Lxx\x0D\x0A\x1B[7;19H\x0D\x0A\x1B[2E\x08\x1B[2XhelloABCDEFGHIJterminalhello\x1B[3E\x09helloABCDEFGHIJ\x1B[4L\x1B[4Sworldhelloxxterminalworldhello\x1B[1D\x1B[2Tterminalxx\x1B[6n\x1B[6n\x1B[2@\x1B[1J\x0D\x0A\x1B[4B\x1B[1T\x08\x1BDABCDEFGHIJ\x1B[2Phelloworld\x1B[1B\x0D\x0A\x1B[uABCDEFGHIJneper\x1B[4T\x1B[3SABCDEFGHIJhello\x1B[2Aworld\x1B[6G\x1B[2K\x09\x0D\x0A\x1B[7;21H\x1B[s\x1B[4X\x1B[u0123456789terminal\x1B[5;7H\x09\x1B[0mhello\x1B[3FABCDEFGHIJhelloworld\x1B[6n\x1B[1B\x1B[1B\x1B[2L\x1B[s0123456789\x1B[u\x09worldworldhello0123456789\x1B[6n0123456789\x1B[6n\x1B[4Jworld0123456789\x1B[6nneper\x0D\x0A\x0D\x0A\xE7\x95\x8CneperneperABCDEFGHIJ\x1B[3L\x1B[2;8r\x1B[4Aterminal\x1B[3D\x1B[?7l\x1B[31mxxneper\x1B[1B\x0D\x0A\x1B[4D\x1B[4F\x1B[3L\x1B[3FABCDEFGHIJterminalhello\x1B[4C\x1B[1T\x1B[3Kterminal\x09\x1B[4C\x1B[3Aneperterminal\x1B[2S\x08\x1B[8;5H\x1B[r\x1B[2;8r\x0D\x0A\x1B[4E\x1B[3Tterminal\x1BM\x1B[3;11H\x1B[4l\x1B[9G\x0D\x0A\x1B[u\x1B[2EABCDEFGHIJ\x0D\x0A\x1B[3Sworld\x0D\x0Aneper\x1B[2D\x1B[2D\x09world\x0D\x0A\x1B[4JworldABCDEFGHIJneperterminal\x1B[?7lterminal\x1B8\x1B[6nterminalworldxx\x1B[1M\x1B[7;23H\x1B[49mterminal\x1BMABCDEFGHIJ\x1B[4D0123456789\x09\x1B[u\x1B[3F\xC3\xBC\x1B]0;t2\x07\x1B[2@\x1B[1K\x09\x1B[1Dxxworld\x1B[17G\x0D\x0A0123456789\x1B[2P\x1B[1X\x1B[3L\xC3\xBCABCDEFGHIJterminal\x1B[3D\x1B[3Bterminal\x09helloterminal\xE7\x95\x8C\x1B[1dneper\x1B[2M\x09\x1B[4lworld\x1B[2C\x1B[4lneper\x1B[6n\xC3\xBC0123456789\x1B[6n0123456789\x1B[?6l\x1B[?1049l" }
const MODEL_HASH: u64 = 8758348720990691201u64
const MODEL_LINES: usize = 24usize
const MODEL_CX: usize = 0usize
const MODEL_CY: usize = 3usize
// END GENERATED

fn line_is(t: *term.Term, i: usize, expect: str) -> bool {
    var buf: [128]u8 = zero
    let n = term.line_text(t, i, buf[..])
    if n != expect.len { ret false }
    var k = 0usize
    while k < n {
        if buf[k] != expect[k] { ret false }
        k += 1usize
    }
    ret true
}

fn mix(h: u64, v: u32) -> u64 { ret (h ^ u64(v)) *% 1099511628211u64 }

fn digest(t: *term.Term, replies: []const u8) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    let n = term.line_count(t)
    while i < n {
        var c = 0usize
        while c < t.cols {
            let cl = term.line_cell(t, i, c)
            h = mix(h, cl.ch)
            h = mix(h, cl.fg)
            h = mix(h, cl.bg)
            h = mix(h, cl.attr)
            c += 1usize
        }
        var wrapped = 0u32
        if term.line_wrapped(t, i) { wrapped = 1u32 }
        h = mix(h, wrapped)
        i += 1usize
    }
    h = mix(h, u32(t.cx))
    h = mix(h, u32(t.cy))
    h = mix(h, u32(t.sb_len))
    h = mix(h, u32(t.top))
    h = mix(h, u32(t.bottom))
    var altv = 0u32
    if t.alt { altv = 1u32 }
    h = mix(h, altv)
    var k = 0usize
    while k < replies.len {
        h = mix(h, u32(replies[k]))
        k += 1usize
    }
    k = 0usize
    while k < t.title_len {
        h = mix(h, u32(t.title[k]))
        k += 1usize
    }
    ret h
}

fn fresh(a: *mem.Arena, cols: usize, rows: usize, sb: usize) -> term.Term {
    let (t, e) = term.new(a, cols, rows, 40usize, 12usize, sb)
    if e != ok { os.exit(250i32) }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: text, CR LF and the cursor.
    var t1 = fresh(a, 20usize, 8usize, 16usize)
    term.feed(&t1, "hi\r\nthere")
    if !line_is(&t1, 0usize, "hi") || !line_is(&t1, 1usize, "there") || t1.cx != 5usize || t1.cy != 1usize { os.exit(1i32) }

    // 2: deferred wrap, the wrapped flag and that the next character lands on the next line.
    var t2 = fresh(a, 10usize, 3usize, 4usize)
    term.feed(&t2, "0123456789")
    if t2.cx != 9usize || t2.cy != 0usize || !t2.wrap_pending { os.exit(2i32) }
    term.feed(&t2, "A")
    if !line_is(&t2, 0usize, "0123456789") || !line_is(&t2, 1usize, "A") || t2.cx != 1usize || t2.cy != 1usize { os.exit(2i32) }
    if !term.line_wrapped(&t2, 0usize) || term.line_wrapped(&t2, 1usize) { os.exit(2i32) }

    // 3: SGR attributes, 16/256/true colours.
    var t3 = fresh(a, 10usize, 2usize, 0usize)
    term.feed(&t3, "\x1b[1;31;44mX\x1b[0mY\x1b[38;2;1;2;3mZ\x1b[38;5;200mW\x1b[4;7;9mV")
    let c30 = term.line_cell(&t3, 0usize, 0usize)
    if c30.ch != 88u32 || c30.attr != term.BOLD || c30.fg != term.indexed(1u32) || c30.bg != term.indexed(4u32) { os.exit(3i32) }
    let c31 = term.line_cell(&t3, 0usize, 1usize)
    if c31.attr != 0u32 || c31.fg != 0u32 || c31.bg != 0u32 { os.exit(3i32) }
    if term.line_cell(&t3, 0usize, 2usize).fg != term.rgb(66051u32) { os.exit(3i32) }
    if term.line_cell(&t3, 0usize, 3usize).fg != term.indexed(200u32) { os.exit(3i32) }
    if term.line_cell(&t3, 0usize, 4usize).attr != (term.UNDERLINE | term.REVERSE | term.STRIKE) { os.exit(3i32) }

    // 4: cursor movement and erase (erase takes the current background).
    var t4 = fresh(a, 10usize, 3usize, 0usize)
    term.feed(&t4, "abcdef\x1b[3D\x1b[K")
    if !line_is(&t4, 0usize, "abc") || t4.cx != 3usize { os.exit(4i32) }
    term.feed(&t4, "\x1b[2;3Hxy")
    if !line_is(&t4, 1usize, "  xy") { os.exit(4i32) }
    term.feed(&t4, "\x1b[44m\x1b[1;1H\x1b[2J")
    if !line_is(&t4, 0usize, "") || !line_is(&t4, 1usize, "") || t4.cx != 0usize || t4.cy != 0usize { os.exit(4i32) }
    if term.line_cell(&t4, 2usize, 9usize).bg != term.indexed(4u32) { os.exit(4i32) }

    // 5: scrollback and a scroll region.
    var t5 = fresh(a, 10usize, 3usize, 5usize)
    term.feed(&t5, "a\r\nb\r\nc\r\nd\r\ne")
    if t5.sb_len != 2usize || term.line_count(&t5) != 5usize { os.exit(5i32) }
    if !line_is(&t5, 0usize, "a") || !line_is(&t5, 1usize, "b") || !line_is(&t5, 2usize, "c") || !line_is(&t5, 4usize, "e") { os.exit(5i32) }
    var snap: [30]term.Cell = zero
    if term.snapshot(&t5, 2usize, snap[..]) != 30usize || snap[0].ch != 97u32 || snap[10].ch != 98u32 { os.exit(5i32) }
    if term.snapshot(&t5, 0usize, snap[..]) != 30usize || snap[0].ch != 99u32 { os.exit(5i32) }
    var t5b = fresh(a, 10usize, 4usize, 5usize)
    term.feed(&t5b, "r0\r\nr1\r\nr2\r\nr3\x1b[2;3r\x1b[3;1H\n")
    if t5b.sb_len != 0usize || !line_is(&t5b, 0usize, "r0") || !line_is(&t5b, 1usize, "r2") || !line_is(&t5b, 2usize, "") || !line_is(&t5b, 3usize, "r3") { os.exit(5i32) }
    if t5b.top != 1usize || t5b.bottom != 2usize { os.exit(5i32) }

    // 6: the alternate screen keeps the main screen and cursor.
    var t6 = fresh(a, 10usize, 3usize, 4usize)
    term.feed(&t6, "main\x1b[?1049h")
    if !t6.alt || !line_is(&t6, 0usize, "") { os.exit(6i32) }
    term.feed(&t6, "\x1b[HALT")
    if !line_is(&t6, 0usize, "ALT") { os.exit(6i32) }
    term.feed(&t6, "\x1b[?1049l")
    if t6.alt || !line_is(&t6, 0usize, "main") || t6.cx != 4usize || t6.cy != 0usize { os.exit(6i32) }

    // 7: UTF-8 split across feeds, a wide cell, an invalid byte.
    var t7 = fresh(a, 10usize, 2usize, 0usize)
    term.feed(&t7, "\xC3")
    term.feed(&t7, "\xA9\xE4\xB8")
    term.feed(&t7, "\x96\xFF!")
    if term.line_cell(&t7, 0usize, 0usize).ch != 233u32 { os.exit(7i32) }
    let w1 = term.line_cell(&t7, 0usize, 1usize)
    let w2 = term.line_cell(&t7, 0usize, 2usize)
    if w1.ch != 19990u32 || (w1.attr & term.WIDE) == 0u32 || (w2.attr & term.CONT) == 0u32 { os.exit(7i32) }
    if term.line_cell(&t7, 0usize, 3usize).ch != 65533u32 || term.line_cell(&t7, 0usize, 4usize).ch != 33u32 { os.exit(7i32) }
    if !line_is(&t7, 0usize, "\xC3\xA9\xE4\xB8\x96\xEF\xBF\xBD!") || t7.cx != 5usize { os.exit(7i32) }
    term.feed(&t7, "\x1b[1GX")
    if term.line_cell(&t7, 0usize, 0usize).ch != 88u32 { os.exit(7i32) }
    term.feed(&t7, "\x1b[2GQ")
    if term.line_cell(&t7, 0usize, 1usize).ch != 81u32 || term.line_cell(&t7, 0usize, 2usize).ch != 32u32 { os.exit(7i32) }

    // 8: a wide character that does not fit wraps whole.
    var t8 = fresh(a, 4usize, 3usize, 0usize)
    term.feed(&t8, "abc\xE4\xB8\x96")
    if !line_is(&t8, 0usize, "abc") || !term.line_wrapped(&t8, 0usize) || term.line_cell(&t8, 1usize, 0usize).ch != 19990u32 || t8.cx != 2usize || t8.cy != 1usize { os.exit(8i32) }

    // 9: resize keeps rows by pushing and pulling history, clips and pads columns.
    var t9 = fresh(a, 10usize, 4usize, 5usize)
    term.feed(&t9, "1\r\n2\r\n3\r\n4")
    if term.resize(&t9, 10usize, 2usize) != ok || t9.sb_len != 2usize || t9.cy != 1usize { os.exit(9i32) }
    if !line_is(&t9, 0usize, "1") || !line_is(&t9, 2usize, "3") || !line_is(&t9, 3usize, "4") { os.exit(9i32) }
    if term.resize(&t9, 10usize, 4usize) != ok || t9.sb_len != 0usize || t9.cy != 3usize { os.exit(9i32) }
    if !line_is(&t9, 0usize, "1") || !line_is(&t9, 3usize, "4") { os.exit(9i32) }
    var t9b = fresh(a, 10usize, 2usize, 0usize)
    term.feed(&t9b, "abcdefghij")
    if term.resize(&t9b, 5usize, 2usize) != ok || !line_is(&t9b, 0usize, "abcde") || t9b.cols != 5usize { os.exit(9i32) }
    if term.resize(&t9b, 10usize, 2usize) != ok || !line_is(&t9b, 0usize, "abcde") { os.exit(9i32) }
    if term.resize(&t9b, 41usize, 2usize) == ok || term.resize(&t9b, 10usize, 0usize) == ok { os.exit(9i32) }

    // 10: replies and titles; ST ends an OSC and the next byte is ordinary text.
    var t10 = fresh(a, 20usize, 5usize, 0usize)
    term.feed(&t10, "\x1b[5n\x1b[3;4H\x1b[6n\x1b[c")
    var rb: [64]u8 = zero
    let rn = term.take_output(&t10, rb[..])
    let want = "\x1b[0n\x1b[3;4R\x1b[?62;22c"
    if rn != want.len { os.exit(10i32) }
    var q = 0usize
    while q < rn {
        if rb[q] != want[q] { os.exit(10i32) }
        q += 1usize
    }
    if term.take_output(&t10, rb[..]) != 0usize { os.exit(10i32) }
    term.feed(&t10, "\x1b]0;hello\x07\x1b]2;abc\x1b\\Z")
    if t10.title_len != 3usize || t10.title[0] != 97u8 || term.line_cell(&t10, 2usize, 3usize).ch != 90u32 { os.exit(10i32) }
    term.feed(&t10, "\x07\x07")
    if t10.bells != 2u32 { os.exit(10i32) }

    // 11: palette and colour resolution.
    if term.resolve_color(term.indexed(1u32), 7u32) != 13434880u32 { os.exit(11i32) }
    if term.resolve_color(term.indexed(16u32), 7u32) != 0u32 || term.resolve_color(term.indexed(231u32), 7u32) != 16777215u32 { os.exit(11i32) }
    if term.resolve_color(term.indexed(232u32), 7u32) != 526344u32 || term.resolve_color(term.indexed(255u32), 7u32) != 15658734u32 { os.exit(11i32) }
    if term.resolve_color(term.indexed(196u32), 7u32) != 16711680u32 || term.resolve_color(term.rgb(1193046u32), 7u32) != 1193046u32 { os.exit(11i32) }
    if term.resolve_color(0u32, 7u32) != 7u32 { os.exit(11i32) }

    // 12: DEC line drawing, tabs, REP, insert mode, origin mode, reset.
    var t12 = fresh(a, 20usize, 6usize, 0usize)
    term.feed(&t12, "\x1b(0q\x1b(Bq")
    if term.line_cell(&t12, 0usize, 0usize).ch != 9472u32 || term.line_cell(&t12, 0usize, 1usize).ch != 113u32 { os.exit(12i32) }
    term.feed(&t12, "\r\na\tb\r\nx\x1b[3b")
    if term.line_cell(&t12, 1usize, 8usize).ch != 98u32 || !line_is(&t12, 2usize, "xxxx") { os.exit(12i32) }
    term.feed(&t12, "\r\nabc\x1b[1G\x1b[4hZ\x1b[4l")
    if !line_is(&t12, 3usize, "Zabc") { os.exit(12i32) }
    term.feed(&t12, "\x1b[2;3r\x1b[?6h\x1b[1;1H*")
    if t12.cy != 1usize || term.line_cell(&t12, 1usize, 0usize).ch != 42u32 { os.exit(12i32) }
    term.feed(&t12, "\x1bc")
    if t12.cy != 0usize || t12.top != 0usize || t12.origin || !line_is(&t12, 1usize, "") { os.exit(12i32) }

    // 13: the generated stream matches the Python model, whole and in 7-byte pieces.
    let stream = model_stream()
    var whole = fresh(a, 20usize, 8usize, 16usize)
    term.feed(&whole, stream)
    var bw: [512]u8 = zero
    let rw = term.take_output(&whole, bw[..])
    if term.line_count(&whole) != MODEL_LINES || whole.cx != MODEL_CX || whole.cy != MODEL_CY { os.exit(13i32) }
    if digest(&whole, bw[..rw]) != MODEL_HASH { os.exit(14i32) }
    var piece = fresh(a, 20usize, 8usize, 16usize)
    var at = 0usize
    while at < stream.len {
        var stop = at + 7usize
        if stop > stream.len { stop = stream.len }
        term.feed(&piece, stream[at..stop])
        at = stop
    }
    var bp: [512]u8 = zero
    let rp = term.take_output(&piece, bp[..])
    if digest(&piece, bp[..rp]) != MODEL_HASH { os.exit(15i32) }
    ret ok
}
