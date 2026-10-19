// ClearType-hinted points of every code of a font at one size, in the text form tapcmp.py reads (`code adv pp1x ncont { npts { x y on } } { x y }*4`,
// 26.6 pixels): `ctdump FONT PPEM [bw] [cut=FILE]`; FILE has `code K` lines: that glyph's program is cut after K instructions that are not
// pushes and IUP[x] runs on what they left (the probe tapfont.py makes in GDI). `only=CODE` dumps one code, `trace=CODE` also traces its programs. For comparing the hinter with GDI's points on fonts that have no atlas (scripts/winnative/synth.py).

use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.text.shape
use e.text.tthint
use e.text.ttglyph

fn append(buf: []u8, len: usize, s: []const u8) -> usize {
    var n = len
    var i = 0usize
    while i < s.len && n < buf.len {
        buf[n] = s[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

fn append_int(buf: []u8, len: usize, v: i64) -> usize {
    var n = len
    var digits: [24]u8 = zero
    var count = 0usize
    var m = v
    if m < 0i64 {
        n = append(buf, n, "-")
        m = 0i64 - m
    }
    if m == 0i64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while m > 0i64 {
        digits[count] = u8(48i64 + m % 10i64)
        count += 1usize
        m = m / 10i64
    }
    while count > 0usize {
        count = count - 1usize
        if n < buf.len {
            buf[n] = digits[count]
            n += 1usize
        }
    }
    ret n
}

fn outline_line(buf: []u8, len: usize, code: usize, out: *const tthint.Outline) -> usize {
    var n = append_int(buf, len, i64(code))
    n = append(buf, n, " ")
    n = append_int(buf, n, tthint.fdiv(out.adv + 32i64, 64i64))
    n = append(buf, n, " ")
    n = append_int(buf, n, out.pp1x)
    n = append(buf, n, " ")
    n = append_int(buf, n, i64(out.nends))
    var c = 0usize
    var first = 0usize
    while c < out.nends {
        let last = out.ends[c]
        n = append(buf, n, " ")
        n = append_int(buf, n, i64(last + 1usize - first))
        var q = first
        while q <= last {
            n = append(buf, n, " ")
            n = append_int(buf, n, out.cur[2usize * q])
            n = append(buf, n, " ")
            n = append_int(buf, n, out.cur[2usize * q + 1usize])
            n = append(buf, n, " ")
            n = append_int(buf, n, (out.tags[q] & 1i64) + ((out.tags[q] >> 3u32) & 3i64) * 2i64)
            q += 1usize
        }
        first = last + 1usize
        c += 1usize
    }
    var ph = 0usize
    while ph < 4usize {
        n = append(buf, n, " ")
        n = append_int(buf, n, out.cur[2usize * (out.n + ph)])
        n = append(buf, n, " ")
        n = append_int(buf, n, out.cur[2usize * (out.n + ph) + 1usize])
        ph += 1usize
    }
    ret append(buf, n, "\n")
}

fn number(s: str) -> i64 {
    var v = 0i64
    var i = 0usize
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        v = v * 10i64 + i64(s[i]) - 48i64
        i += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 3usize { ret ok }
    let (bytes, read_error) = fs.read_file(a, args[1usize], 16777216usize)
    if read_error != ok { ret read_error }
    let (hn, open_error) = tthint.open(a, bytes)
    if open_error != ok { ret open_error }
    let font = shape.Font { id: 1u32, data: bytes, face_index: 0u32 }
    let (cmap, has_cmap) = shape.find_table(font, shape.TAG_CMAP)
    if !has_cmap { ret ok }
    let (sub, has_sub) = shape.cmap_subtable(bytes, cmap)
    if !has_sub { ret ok }
    var cleartype = true
    var only_code = 0usize
    var cuts: [256]i64 = zero
    var ai = 3usize
    while ai < args.len {
        if str.eq(args[ai], "bw") { cleartype = false }
        if args[ai].len > 5usize && str.eq(args[ai][0usize..5usize], "only=") { only_code = usize(number(args[ai][5usize..args[ai].len])) }
        if args[ai].len > 6usize && str.eq(args[ai][0usize..6usize], "trace=") {
            only_code = usize(number(args[ai][6usize..args[ai].len]))
            ttglyph.set_trace_glyph(-2i64)
        }
        if args[ai].len > 4usize && str.eq(args[ai][0usize..4usize], "cut=") {
            let (cut_text, cut_error) = fs.read_file(a, args[ai][4usize..args[ai].len], 1000000usize)
            if cut_error != ok { ret cut_error }
            var q = 0usize
            var have_code = false
            var cur_code = 0usize
            while q < cut_text.len {
                if cut_text[q] >= 48u8 && cut_text[q] <= 57u8 {
                    var v = 0i64
                    while q < cut_text.len && cut_text[q] >= 48u8 && cut_text[q] <= 57u8 {
                        v = v * 10i64 + i64(cut_text[q]) - 48i64
                        q += 1usize
                    }
                    if !have_code {
                        cur_code = usize(v)
                        have_code = true
                    } else {
                        if cur_code < 256usize { cuts[cur_code] = v }
                        have_code = false
                    }
                } else {
                    q += 1usize
                }
            }
        }
        ai += 1usize
    }
    let ppem = number(args[2usize])
    let (buf, buf_error) = mem.alloc[u8](a, 4000000usize)
    if buf_error != ok { ret buf_error }
    var len = 0usize
    var code = 32usize
    while code < 256usize {
        if only_code != 0usize && code != only_code {
            code += 1usize
            continue
        }
        let gid = shape.glyph_of(bytes, sub, u32(code))
        ttglyph.set_cut(cuts[code])
        ttglyph.set_cut_iup(cuts[code] > 0i64)
        let (o, o_error) = ttglyph.hint_glyph(hn, a, ppem, gid, cleartype)
        if o_error == ok && o.n > 0usize { len = outline_line(buf, len, code, &o) }
        code += 1usize
    }
    try io.print(buf[0usize..len])
    ret ok
}
