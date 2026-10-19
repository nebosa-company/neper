// The ClearType glyph oracle (docs/ui/looks/ref/windows-native/glyphs, made by scripts/winnative/glyphs.ps1 from real GDI) against
// `e.text.tthint` + `e.gfx.cleartype`: every glyph of every oracle atlas is hinted and rasterised here and compared.
//
//   no arguments   the regression check: every glyph listed in exact.txt must still match; exit 0, 3 on a regression
//   --report       a summary line per atlas and per font (what share of the glyphs agree) and no failure
//   --verbose      one line per glyph that disagrees
//   --only TEXT    atlases whose name contains TEXT   --dir PATH  the oracle folder   --dump PATH  write our atlases (BGRA) there
//   --write-exact  rewrite exact.txt from the glyphs that match now
//
// Three comparisons per glyph. Pixels: the glyph at the atlas' pen and baseline through the ClearType rasteriser and the gamma blend
// onto the atlas' background colour, against GDI's cell; `px` agrees when no channel is more than 2 levels off. Black-and-white
// outline: the black-and-white machine's hinted points against GetGlyphOutline(GGO_NATIVE), which is what GDI returns for every
// quality, point for point as a cyclic sequence with the implied on-curve points written out. Advance: the black-and-white advance
// rounded to a pixel against GDI's. A machine without the fonts passes.

use e.fmt.gzip as gzip
use e.fmt.png as png
use e.fs
use e.gfx.cleartype
use e.gfx.image
use e.io
use e.mem
use e.os
use e.str
use e.text.shape
use e.text.tthint
use e.text.ttglyph

const OL_MAX: usize = 400000usize

type Cursor = struct { d: []const u8, at: usize }
type Atlas = struct { name: str, face: usize, weight: i64, px: i64, fg: u32, bg: u32, w: usize, h: usize, cw: usize, ch: usize, asc: i64, pad: i64 }
type Totals = struct { glyphs: usize, ink: usize, px_ok: usize, px_same: usize, ink_px_ok: usize, bw_ok: usize, ink_bw_ok: usize, adv_ok: usize, bw_pts: usize, bw_pts_ok: usize }

fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

fn is_hex(b: u8) -> i64 {
    if b >= 48u8 && b <= 57u8 { ret i64(b) - 48i64 }
    if b >= 65u8 && b <= 70u8 { ret i64(b) - 55i64 }
    if b >= 97u8 && b <= 102u8 { ret i64(b) - 87i64 }
    ret -1i64
}

fn hex_color(s: str) -> u32 {
    var v = 0u32
    var i = 0usize
    while i < s.len && i < 6usize {
        let h = is_hex(s[i])
        if h >= 0i64 { v = v * 16u32 + u32(h) }
        i += 1usize
    }
    ret v
}

// The next integer of the cursor (digits with an optional minus), false at the end.
fn next_int(c: *Cursor) -> (i64, bool) {
    while c.at < c.d.len && !is_digit(c.d[c.at]) && c.d[c.at] != 45u8 { c.at += 1usize }
    if c.at >= c.d.len { ret (0i64, false) }
    var neg = false
    if c.d[c.at] == 45u8 {
        neg = true
        c.at += 1usize
    }
    var v = 0i64
    while c.at < c.d.len && is_digit(c.d[c.at]) {
        v = v * 10i64 + i64(c.d[c.at]) - 48i64
        c.at += 1usize
    }
    if neg { ret (0i64 - v, true) }
    ret (v, true)
}

// The word of the cursor: bytes up to a space or newline.
// The next run of digits (no sign), for names such as Segoe_UI-400-12-q5.
fn next_uint(c: *Cursor) -> (i64, bool) {
    while c.at < c.d.len && !is_digit(c.d[c.at]) { c.at += 1usize }
    if c.at >= c.d.len { ret (0i64, false) }
    var v = 0i64
    while c.at < c.d.len && is_digit(c.d[c.at]) {
        v = v * 10i64 + i64(c.d[c.at]) - 48i64
        c.at += 1usize
    }
    ret (v, true)
}

fn next_word(c: *Cursor) -> (usize, usize, bool) {
    while c.at < c.d.len && (c.d[c.at] == 32u8 || c.d[c.at] == 10u8 || c.d[c.at] == 13u8) { c.at += 1usize }
    if c.at >= c.d.len { ret (0usize, 0usize, false) }
    let start = c.at
    while c.at < c.d.len && c.d[c.at] != 32u8 && c.d[c.at] != 10u8 && c.d[c.at] != 13u8 { c.at += 1usize }
    ret (start, c.at, true)
}

fn skip_line(c: *Cursor) {
    while c.at < c.d.len && c.d[c.at] != 10u8 { c.at += 1usize }
}

fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

fn gunzip(a: *mem.Arena, framed: []const u8, limit: usize) -> ([]u8, err) {
    let (storage, storage_error) = aligned(a, gzip.storage_required(.Balanced))
    if storage_error != ok { ret (zero, storage_error) }
    var source_state = io.SliceReader { data: framed, off: 0usize }
    let (r0, reader_error) = gzip.reader(storage, io.slice_reader(&source_state), u64(limit))
    if reader_error != ok { ret (zero, reader_error) }
    var r = r0
    let (out, out_error) = mem.alloc[u8](a, limit)
    if out_error != ok { ret (zero, out_error) }
    var total = 0usize
    while true {
        var end = total + 4096usize
        if end > limit { end = limit }
        let (count, read_error) = gzip.read(&r, out[total..end])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        total += count
    }
    ret (out[0usize..total], ok)
}

// The oracle's outlines: one run of integers per glyph in `ol`, `at[code]` its start (or the usize maximum).
//   code adv a b c bbx bby orgx orgy ncont { npts { x y on } }
fn load_outlines(a: *mem.Arena, framed: []const u8, ol: []i64, at: []usize) -> bool {
    let (text, text_error) = gunzip(a, framed, 4000000usize)
    if text_error != ok { ret false }
    var i = 0usize
    while i < 256usize {
        at[i] = 4294967295usize
        i += 1usize
    }
    var c = Cursor { d: text, at: 0usize }
    skip_line(&c)
    var n = 0usize
    while true {
        let (code, more) = next_int(&c)
        if !more { break }
        if n + 16usize >= ol.len { ret false }
        if code >= 0i64 && code < 256i64 { at[usize(code)] = n }
        ol[n] = code
        n += 1usize
        var k = 0usize
        while k < 8usize {
            let (v, v_more) = next_int(&c)
            if !v_more { ret false }
            ol[n] = v
            n += 1usize
            k += 1usize
        }
        let (ncont, nc_more) = next_int(&c)
        if !nc_more { ret false }
        ol[n] = ncont
        n += 1usize
        var ci = 0i64
        while ci < ncont {
            let (npts, np_more) = next_int(&c)
            if !np_more || n + 3usize * usize(npts) + 4usize >= ol.len { ret false }
            ol[n] = npts
            n += 1usize
            var p = 0i64
            while p < 3i64 * npts {
                let (v, v_more) = next_int(&c)
                if !v_more { ret false }
                ol[n] = v
                n += 1usize
                p += 1i64
            }
            ci += 1i64
        }
    }
    ret true
}

// GDI's hinted points: `code n x y x y ...` per line (26.6 pixels; n points with the four phantom points last), `at[code]` the start of a
// glyph's run in `hd` (the usize maximum when absent).
fn load_hinted(a: *mem.Arena, framed: []const u8, hd: []i64, at: []usize) -> bool {
    let (text, text_error) = gunzip(a, framed, 4000000usize)
    if text_error != ok { ret false }
    var i = 0usize
    while i < 256usize {
        at[i] = 4294967295usize
        i += 1usize
    }
    var c = Cursor { d: text, at: 0usize }
    var n = 0usize
    while true {
        let (code, more) = next_int(&c)
        if !more { break }
        let (count, count_more) = next_int(&c)
        if !count_more || n + 2usize * usize(count) + 4usize >= hd.len { ret false }
        if code >= 0i64 && code < 256i64 { at[usize(code)] = n }
        hd[n] = code
        hd[n + 1usize] = count
        n += 2usize
        var p = 0i64
        while p < 2i64 * count {
            let (v, v_more) = next_int(&c)
            if !v_more { ret false }
            hd[n] = v
            n += 1usize
            p += 1i64
        }
    }
    ret true
}

// A contour with the on-curve points between two off-curve ones written out, coordinates doubled so the midpoints stay whole:
// x, y, on per point. Returns the point count.
fn expand(src: []const i64, n: usize, out: []i64) -> usize {
    var m = 0usize
    var i = 0usize
    while i < n {
        let j = (i + 1usize) % n
        let x = src[3usize * i]
        let y = src[3usize * i + 1usize]
        let on = src[3usize * i + 2usize]
        if m + 2usize > out.len / 3usize { ret m }
        out[3usize * m] = 2i64 * x
        out[3usize * m + 1usize] = 2i64 * y
        out[3usize * m + 2usize] = on
        m += 1usize
        if on == 0i64 && src[3usize * j + 2usize] == 0i64 {
            out[3usize * m] = x + src[3usize * j]
            out[3usize * m + 1usize] = y + src[3usize * j + 1usize]
            out[3usize * m + 2usize] = 1i64
            m += 1usize
        }
        i += 1usize
    }
    ret m
}

// How many points of `ours` agree with `theirs` at the best rotation (both expanded), and whether all do with equal lengths.
fn rotate_match(ours: []const i64, mo: usize, theirs: []const i64, mt: usize) -> usize {
    var best = 0usize
    if mo == 0usize || mt == 0usize { ret 0usize }
    var r = 0usize
    while r < mo {
        var same = 0usize
        var k = 0usize
        while k < mt && k < mo {
            let o = (r + k) % mo
            if ours[3usize * o] == theirs[3usize * k] && ours[3usize * o + 1usize] == theirs[3usize * k + 1usize] && ours[3usize * o + 2usize] == theirs[3usize * k + 2usize] { same += 1usize }
            k += 1usize
        }
        if same > best { best = same }
        r += 1usize
    }
    ret best
}

type BwResult = struct { exact: bool, points: usize, points_ok: usize, adv_ok: bool }

// The black-and-white machine's outline of `gid` against the oracle's glyph at `ol[at..]`.
fn compare_bw(h: *tthint.Hinter, a: *mem.Arena, ppem: i64, gid: u32, ol: []const i64, at: usize, scratch: []i64) -> BwResult {
    var r = BwResult { exact: false, points: 0usize, points_ok: 0usize, adv_ok: false }
    let (out, hint_error) = ttglyph.hint_glyph(h, a, ppem, gid, false)
    if hint_error != ok { ret r }
    r.adv_ok = tthint.fdiv(out.adv + 32i64, 64i64) == ol[at + 1usize]
    let ncont = usize(ol[at + 9usize])
    var p = at + 10usize
    var ours_flat = scratch[0usize..60000usize]
    var theirs_flat = scratch[60000usize..120000usize]
    var src = scratch[120000usize..130000usize]
    let ours_contours = out.nends
    var all_exact = ours_contours == ncont
    var c = 0usize
    while c < ncont {
        let npts = usize(ol[p])
        p += 1usize
        var t = 0usize
        while t < npts {
            src[3usize * t] = ol[p + 3usize * t]
            src[3usize * t + 1usize] = ol[p + 3usize * t + 1usize]
            src[3usize * t + 2usize] = ol[p + 3usize * t + 2usize]
            t += 1usize
        }
        p += 3usize * npts
        let mt = expand(src, npts, theirs_flat)
        r.points += mt
        if c < ours_contours {
            var first = 0usize
            if c > 0usize { first = out.ends[c - 1usize] + 1usize }
            let last = out.ends[c]
            let count = last + 1usize - first
            var s2 = scratch[130000usize..140000usize]
            var q = 0usize
            while q < count {
                s2[3usize * q] = out.cur[2usize * (first + q)] - out.pp1x
                s2[3usize * q + 1usize] = out.cur[2usize * (first + q) + 1usize]
                s2[3usize * q + 2usize] = out.tags[first + q] & 1i64
                q += 1usize
            }
            let mo = expand(s2, count, ours_flat)
            let same = rotate_match(ours_flat, mo, theirs_flat, mt)
            r.points_ok += same
            if same != mt || mo != mt { all_exact = false }
        } else {
            all_exact = false
        }
        c += 1usize
    }
    r.exact = all_exact
    ret r
}

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

// One outline as a line of integers: code adv pp1x ncont { npts { x y on } } { x y }*4, x as the hinter has it (the left phantom point `pp1x`
// is the pen); the four pairs at the end are the phantom points (left, right, top, bottom).
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

fn cvt_text(a: *mem.Arena, cvt: []const i64) -> []u8 {
    let (buf, buf_error) = mem.alloc[u8](a, 16usize * (cvt.len + 1usize))
    if buf_error != ok { ret zero }
    var n = 0usize
    var i = 0usize
    while i < cvt.len {
        n = append_int(buf, n, cvt[i])
        n = append(buf, n, "\n")
        i += 1usize
    }
    ret buf[0usize..n]
}

fn trace_code_number(t: str) -> usize {
    var v = 0usize
    var i = 0usize
    while i < t.len {
        if is_digit(t[i]) { v = v * 10usize + usize(t[i] - 48u8) }
        i += 1usize
    }
    ret v
}

fn font_path_of(over: str, face: usize, weight: i64) -> str {
    if over.len > 0usize { ret over }
    ret font_file(face, weight)
}

fn font_file(face: usize, weight: i64) -> str {
    if face == 0usize {
        if weight >= 600i64 { ret "C:/Windows/Fonts/segoeuib.ttf" }
        ret "C:/Windows/Fonts/segoeui.ttf"
    }
    if weight >= 600i64 { ret "C:/Windows/Fonts/tahomabd.ttf" }
    ret "C:/Windows/Fonts/tahoma.ttf"
}

fn byte_of(v: f32) -> i64 { ret i64(v * 255.0 + 0.5) }

fn abs_i(v: i64) -> i64 {
    if v < 0i64 { ret 0i64 - v }
    ret v
}

// Our cell of glyph `gid` against the atlas cell at (cx, cy): the largest channel difference and the channels more than 2 off.
type CellDiff = struct { max: i64, over: usize, same: bool }

fn compare_cell(sc: *cleartype.Scratch, img: image.Image, at: Atlas, cx: usize, cy: usize, dump: []u8) -> CellDiff {
    var d = CellDiff { max: 0i64, over: 0usize, same: true }
    let bg_r = f32((at.bg >> 16u32) & 255u32) / 255.0
    let bg_g = f32((at.bg >> 8u32) & 255u32) / 255.0
    let bg_b = f32(at.bg & 255u32) / 255.0
    let fg_r = f32((at.fg >> 16u32) & 255u32) / 255.0
    let fg_g = f32((at.fg >> 8u32) & 255u32) / 255.0
    let fg_b = f32(at.fg & 255u32) / 255.0
    var y = 0usize
    while y < at.ch {
        var x = 0usize
        while x < at.cw {
            // a pixel no channel covers is left as it was; a covered one sends all three channels through GDI's tables
            let touched = cleartype.coverage(sc, i64(x), i64(y), 0usize) + cleartype.coverage(sc, i64(x), i64(y), 1usize) + cleartype.coverage(sc, i64(x), i64(y), 2usize) > 0i64
            var c = 0usize
            while c < 3usize {
                var bg = bg_r
                var fg = fg_r
                if c == 1usize {
                    bg = bg_g
                    fg = fg_g
                }
                if c == 2usize {
                    bg = bg_b
                    fg = fg_b
                }
                let k = cleartype.coverage(sc, i64(x), i64(y), c)
                var v = bg
                if touched { v = cleartype.blend(bg, fg, k) }
                let ours = byte_of(v)
                let ref_at = (cy + y) * img.stride + (cx + x) * 4usize + c
                let theirs = i64(img.pixels[ref_at])
                let diff = abs_i(ours - theirs)
                if diff > d.max { d.max = diff }
                if diff > 2i64 { d.over += 1usize }
                if diff != 0i64 { d.same = false }
                if dump.len > 0usize {
                    let off = 24usize + ((cy + y) * (at.w) + cx + x) * 4usize
                    dump[off + 2usize - c] = u8(ours)
                }
                c += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    ret d
}

fn main(a: *mem.Arena, args: []str) -> err {
    var dir: str = "docs/ui/looks/ref/windows-native/glyphs"
    var only: str = ""
    var dump_dir: str = ""
    var font_override: str = ""
    var trace_code: str = ""
    var verbose = false
    var report = false
    var write_exact = false
    var i = 0usize
    while i < args.len {
        if str.eq(args[i], "--dir") && i + 1usize < args.len {
            dir = args[i + 1usize]
            i += 1usize
        } else if str.eq(args[i], "--only") && i + 1usize < args.len {
            only = args[i + 1usize]
            i += 1usize
        } else if str.eq(args[i], "--dump") && i + 1usize < args.len {
            dump_dir = args[i + 1usize]
            i += 1usize
        } else if str.eq(args[i], "--fontfile") && i + 1usize < args.len {
            font_override = args[i + 1usize]
            i += 1usize
        } else if str.eq(args[i], "--trace") && i + 1usize < args.len {
            trace_code = args[i + 1usize]
            i += 1usize
        } else if str.eq(args[i], "--iup") {
            ttglyph.set_cut_iup(true)
        } else if str.eq(args[i], "--cutiup") {
            ttglyph.set_cut(-1i64)
        } else if str.eq(args[i], "--cut") && i + 1usize < args.len {
            ttglyph.set_cut(i64(trace_code_number(args[i + 1usize])))
            i += 1usize
        } else if str.eq(args[i], "--noprog") {
            ttglyph.set_skip_programs(true)
        } else if str.eq(args[i], "--verbose") {
            verbose = true
        } else if str.eq(args[i], "--report") {
            report = true
        } else if str.eq(args[i], "--write-exact") {
            write_exact = true
        }
        i += 1usize
    }
    let (list_path, list_path_error) = str.concat(a, dir, "/atlases.txt")
    if list_path_error != ok { ret list_path_error }
    let (present, present_error) = fs.exists(a, list_path)
    if present_error != ok || !present { ret ok }
    let (listing, listing_error) = fs.read_file(a, list_path, 1000000usize)
    if listing_error != ok { ret listing_error }
    // The expectation: per atlas name, a bit per code that must still agree (exact.txt).
    let (exact_path, exact_path_error) = str.concat(a, dir, "/exact.txt")
    if exact_path_error != ok { ret exact_path_error }
    var expected: str = ""
    let (has_exact, has_exact_error) = fs.exists(a, exact_path)
    if has_exact_error == ok && has_exact {
        let (e_bytes, e_error) = fs.read_file(a, exact_path, 1000000usize)
        if e_error == ok { expected = e_bytes }
    }
    // What lives for the whole run (the fonts, their hinters, the rasteriser's storage) goes in its own arena; the rest of an atlas is
    // read into `a` and dropped when the next one starts.
    let (hbuf, hbuf_error) = mem.alloc[u8](a, 134217728usize)
    if hbuf_error != ok { ret hbuf_error }
    var ha_state = mem.arena_from(hbuf)
    let ha = &ha_state
    let (ol, ol_error) = mem.alloc[i64](ha, OL_MAX)
    if ol_error != ok { ret ol_error }
    let (ol_at, ol_at_error) = mem.alloc[usize](ha, 256usize)
    if ol_at_error != ok { ret ol_at_error }
    let (hd, hd_error) = mem.alloc[i64](ha, 400000usize)
    if hd_error != ok { ret hd_error }
    let (hd_at, hd_at_error) = mem.alloc[usize](ha, 256usize)
    if hd_at_error != ok { ret hd_at_error }
    var hint_glyphs_ok = 0usize
    var hint_glyphs = 0usize
    var hint_points_ok = 0usize
    var hint_points = 0usize
    let (scratch, scratch_error) = mem.alloc[i64](ha, 150000usize)
    if scratch_error != ok { ret scratch_error }
    let (sc, sc_error) = cleartype.scratch(ha)
    if sc_error != ok { ret sc_error }
    var font_data: [16]str = zero
    var hinters: [16]*tthint.Hinter = zero
    var subs: [16]usize = zero
    var font_state: [16]u8 = zero
    let (exact_buf, exact_buf_error) = mem.alloc[u8](a, 65536usize)
    if exact_buf_error != ok { ret exact_buf_error }
    var exact_len = 0usize
    let (bw_buf, bw_buf_error) = mem.alloc[u8](ha, 600000usize)
    if bw_buf_error != ok { ret bw_buf_error }
    let (ct_buf, ct_buf_error) = mem.alloc[u8](ha, 600000usize)
    if ct_buf_error != ok { ret ct_buf_error }
    var failures = 0usize
    if verbose { try io.printf["arena {} of {}\n"](a.off, a.cap) }
    var total = Totals { glyphs: 0usize, ink: 0usize, px_ok: 0usize, px_same: 0usize, ink_px_ok: 0usize, bw_ok: 0usize, ink_bw_ok: 0usize, adv_ok: 0usize, bw_pts: 0usize, bw_pts_ok: 0usize }
    var c = Cursor { d: listing, at: 0usize }
    skip_line(&c)
    let atlas_mark = mem.mark(a)
    while true {
        mem.reset(a, atlas_mark)
        let (name_lo, name_hi, more) = next_word(&c)
        if !more { break }
        let name: str = listing[name_lo..name_hi]
        let (w, w_more) = next_int(&c)
        let (h, h_more) = next_int(&c)
        let (cw, cw_more) = next_int(&c)
        let (ch, ch_more) = next_int(&c)
        let (asc, asc_more) = next_int(&c)
        let (pad, pad_more) = next_int(&c)
        if !w_more || !h_more || !cw_more || !ch_more || !asc_more || !pad_more { break }
        // blend ramps are not glyph atlases
        if name.len < 8usize || (font_override.len == 0usize && name[0] != 83u8 && name[0] != 84u8 && name[0] != 78u8) { continue }
        if only.len > 0usize {
            var found = false
            var s = 0usize
            while s + only.len <= name.len {
                if str.eq(name[s..s + only.len], only) { found = true }
                s += 1usize
            }
            if !found { continue }
        }
        // Segoe_UI-400-12-q5.000000-FFFFFF
        var at = Atlas { name: name, face: 0usize, weight: 400i64, px: 12i64, fg: 0u32, bg: 0u32, w: usize(w), h: usize(h), cw: usize(cw), ch: usize(ch), asc: asc, pad: pad }
        if name[0] == 84u8 { at.face = 1usize }
        var nc = Cursor { d: name, at: 0usize }
        while nc.at < name.len && name[nc.at] != 45u8 { nc.at += 1usize }
        let (wt, wt_more) = next_uint(&nc)
        let (px, px_more) = next_uint(&nc)
        if !wt_more || !px_more { continue }
        at.weight = wt
        at.px = px
        while nc.at < name.len && name[nc.at] != 46u8 { nc.at += 1usize }
        nc.at += 1usize
        if nc.at + 13usize > name.len { continue }
        at.fg = hex_color(name[nc.at..nc.at + 6usize])
        at.bg = hex_color(name[nc.at + 7usize..nc.at + 13usize])
        var fi = at.face * 2usize
        if at.weight >= 600i64 { fi += 1usize }
        // A probe atlas (scripts/winnative/probe_fonts.py) carries its own font next to it.
        var probe_font = false
        if name.len > 7usize && str.eq(name[0usize..6usize], "NProbe") && name[6usize] >= 48u8 && name[6usize] <= 57u8 {
            probe_font = true
            fi = 4usize + usize(name[6usize] - 48u8)
        }
        if font_state[fi] == 0u8 {
            font_state[fi] = 2u8
            var font_text: str = font_path_of(font_override, at.face, at.weight)
            if probe_font {
                let (pd, pd_error) = str.concat(a, dir, "/")
                if pd_error != ok { ret pd_error }
                let (pf, pf_error) = str.concat(a, pd, name[0usize..7usize])
                if pf_error != ok { ret pf_error }
                let (pt, pt_error) = str.concat(a, pf, ".ttf")
                if pt_error != ok { ret pt_error }
                font_text = pt
            }
            let (bytes, read_error) = fs.read_file(ha, font_text, 16777216usize)
            if read_error == ok {
                let (hn, open_error) = tthint.open(ha, bytes)
                let font = shape.Font { id: 1u32, data: bytes, face_index: 0u32 }
                let (cmap, has_cmap) = shape.find_table(font, shape.TAG_CMAP)
                if open_error == ok && has_cmap {
                    let (sub, has_sub) = shape.cmap_subtable(bytes, cmap)
                    if has_sub {
                        font_data[fi] = bytes
                        hinters[fi] = hn
                        subs[fi] = sub
                        font_state[fi] = 1u8
                    }
                }
            }
        }
        if font_state[fi] != 1u8 { continue }
        // the outlines of the same font and size
        var base_name = name
        var dot = 0usize
        while dot < base_name.len && base_name[dot] != 46u8 { dot += 1usize }
        let (ol_path, ol_path_error) = str.concat(a, dir, "/")
        if ol_path_error != ok { ret ol_path_error }
        let (ol_path2, ol_path2_error) = str.concat(a, ol_path, name[0usize..dot])
        if ol_path2_error != ok { ret ol_path2_error }
        let (ol_path3, ol_path3_error) = str.concat(a, ol_path2, ".outline.gz")
        if ol_path3_error != ok { ret ol_path3_error }
        let (ol_bytes, ol_read_error) = fs.read_file(a, ol_path3, 4000000usize)
        if ol_read_error != ok { continue }
        if !load_outlines(a, ol_bytes, ol, ol_at) { continue }
        // GDI's ClearType-hinted points (tap fonts, scripts/winnative/tapall.py), when this font and size has them
        var has_hinted = false
        let (hd_path1, hd_path1_error) = str.concat(a, dir, "/")
        if hd_path1_error != ok { ret hd_path1_error }
        let (hd_path2, hd_path2_error) = str.concat(a, hd_path1, name[0usize..dot])
        if hd_path2_error != ok { ret hd_path2_error }
        let (hd_path3, hd_path3_error) = str.concat(a, hd_path2, ".hinted.gz")
        if hd_path3_error != ok { ret hd_path3_error }
        let (hd_present, hd_present_error) = fs.exists(a, hd_path3)
        if hd_present_error == ok && hd_present {
            let (hd_bytes, hd_read_error) = fs.read_file(a, hd_path3, 4000000usize)
            if hd_read_error == ok { has_hinted = load_hinted(a, hd_bytes, hd, hd_at) }
        }
        let (png_path, png_path_error) = str.concat(a, dir, "/")
        if png_path_error != ok { ret png_path_error }
        let (png_path2, png_path2_error) = str.concat(a, png_path, name)
        if png_path2_error != ok { ret png_path2_error }
        let (png_path3, png_path3_error) = str.concat(a, png_path2, ".png")
        if png_path3_error != ok { ret png_path3_error }
        let (png_bytes, png_read_error) = fs.read_file(a, png_path3, 8000000usize)
        if png_read_error != ok { continue }
        var png_state = io.SliceReader { data: png_bytes, off: 0usize }
        let (img, img_error) = png.decode(a, io.slice_reader(&png_state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 0u64, verify_crc: false })
        if img_error != ok { continue }
        if img.format != .Rgba8 || usize(img.width) != at.w || usize(img.height) != at.h { continue }
        var dump: []u8 = zero
        if dump_dir.len > 0usize {
            let (buf, buf_error) = mem.alloc[u8](a, 24usize + at.w * at.h * 4usize)
            if buf_error != ok { ret buf_error }
            dump = buf
            var z = 0usize
            while z < dump.len {
                dump[z] = 255u8
                z += 1usize
            }
            let hdr = [6]i64{ w, h, cw, ch, asc, pad }
            var hz = 0usize
            while hz < 6usize {
                dump[4usize * hz] = u8(hdr[hz] & 255i64)
                dump[4usize * hz + 1usize] = u8((hdr[hz] >> 8u32) & 255i64)
                dump[4usize * hz + 2usize] = u8((hdr[hz] >> 16u32) & 255i64)
                dump[4usize * hz + 3usize] = 0u8
                hz += 1usize
            }
        }
        // the expectation line for this atlas
        var want: [674]u8 = zero
        var has_want = false
        var line_at = 0usize
        while line_at + name.len + 1usize < expected.len {
            if str.eq(expected[line_at..line_at + name.len], name) && expected[line_at + name.len] == 32u8 {
                var q = 0usize
                while q < 674usize && line_at + name.len + 1usize + q < expected.len && expected[line_at + name.len + 1usize + q] != 10u8 {
                    want[q] = expected[line_at + name.len + 1usize + q]
                    q += 1usize
                }
                has_want = true
                break
            }
            while line_at < expected.len && expected[line_at] != 10u8 { line_at += 1usize }
            line_at += 1usize
        }
        var line_sum = Totals { glyphs: 0usize, ink: 0usize, px_ok: 0usize, px_same: 0usize, ink_px_ok: 0usize, bw_ok: 0usize, ink_bw_ok: 0usize, adv_ok: 0usize, bw_pts: 0usize, bw_pts_ok: 0usize }
        var marks: [674]u8 = zero
        marks[224usize] = 32u8
        marks[449usize] = 32u8
        var line_hint_ok = 0usize
        var line_hint = 0usize
        var line_hint_points_ok = 0usize
        var line_hint_points = 0usize
        var bw_len = 0usize
        var ct_len = 0usize
        var code = 32usize
        while code < 256usize {
            let idx = code - 32usize
            let gid = shape.glyph_of(font_data[fi], subs[fi], u32(code))
            if ol_at[code] > ol.len {
                code += 1usize
                continue
            }
            let col = idx % 16usize
            let row = idx / 16usize
            if trace_code.len > 0usize && usize(code) == trace_code_number(trace_code) { ttglyph.set_trace_glyph(i64(gid)) } else { ttglyph.set_trace_glyph(-1i64) }
            let (ct, ct_error) = ttglyph.hint_glyph(hinters[fi], ha, at.px, gid, true)
            if !cleartype.begin(sc, 0i64, 0i64, at.cw, at.ch) { ret tthint.NoRoom }
            if ct_error == ok {
                if !cleartype.add_glyph(sc, &ct, at.pad, at.pad + at.asc) { ret tthint.NoRoom }
            }
            let diff = compare_cell(sc, img, at, col * at.cw, row * at.ch, dump)
            if dump_dir.len > 0usize {
                if ct_error == ok {
                    ct_len = outline_line(ct_buf, ct_len, code, &ct)
                }
                let (bwo, bwo_error) = ttglyph.hint_glyph(hinters[fi], ha, at.px, gid, false)
                if bwo_error == ok { bw_len = outline_line(bw_buf, bw_len, code, &bwo) }
            }
            // GDI's hinted points against ours (body points and the left and right phantom points, x and y)
            var hint_exact = false
            if has_hinted && hd_at[code] < hd.len && ct_error == ok && usize(hd[hd_at[code] + 1usize]) == ct.n + 4usize {
                line_hint += 1usize
                hint_exact = true
                var pi = 0usize
                while pi < ct.n + 2usize {
                    line_hint_points += 1usize
                    if ct.cur[2usize * pi] == hd[hd_at[code] + 2usize + 2usize * pi] && ct.cur[2usize * pi + 1usize] == hd[hd_at[code] + 3usize + 2usize * pi] {
                        line_hint_points_ok += 1usize
                    } else {
                        hint_exact = false
                    }
                    pi += 1usize
                }
                if hint_exact { line_hint_ok += 1usize }
                if hint_exact { marks[450usize + idx] = 49u8 } else { marks[450usize + idx] = 48u8 }
                if has_want && want[450usize + idx] == 49u8 && !hint_exact {
                    failures += 1usize
                    try io.printf["REGRESSION {} code {}: hinted points differ from GDI's\n"](name, code)
                }
            }
            let bw = compare_bw(hinters[fi], ha, at.px, gid, ol, ol_at[code], scratch)
            let ink = ol[ol_at[code] + 9usize] > 0i64
            line_sum.glyphs += 1usize
            if ink { line_sum.ink += 1usize }
            var px_ok = diff.max <= 2i64
            if ct_error != ok { px_ok = false }
            if px_ok {
                line_sum.px_ok += 1usize
                if ink { line_sum.ink_px_ok += 1usize }
                marks[idx] = 49u8
            } else {
                marks[idx] = 48u8
            }
            if diff.same && ct_error == ok { line_sum.px_same += 1usize }
            if bw.exact {
                line_sum.bw_ok += 1usize
                if ink { line_sum.ink_bw_ok += 1usize }
            }
            if bw.adv_ok { line_sum.adv_ok += 1usize }
            line_sum.bw_pts += bw.points
            line_sum.bw_pts_ok += bw.points_ok
            if verbose && (!px_ok || !bw.exact || !bw.adv_ok) {
                try io.printf["{} code {} gid {} hint-ok {} trap {} noroom {} px-over {} max {} bw {} ({} of {} points) adv {}\n"](name, code, gid, ct_error == ok, ct_error == tthint.Trap, ct_error == tthint.NoRoom, diff.over, diff.max, bw.exact, bw.points_ok, bw.points, bw.adv_ok)
            }
            if bw.exact && bw.adv_ok {
                marks[225usize + idx] = 49u8
            } else {
                marks[225usize + idx] = 48u8
            }
            if has_want && want[225usize + idx] == 49u8 && !(bw.exact && bw.adv_ok) {
                failures += 1usize
                try io.printf["REGRESSION {} code {}: black-and-white outline or advance differs from GetGlyphOutline\n"](name, code)
            }
            if has_want && want[idx] == 49u8 && !px_ok {
                failures += 1usize
                try io.printf["REGRESSION {} code {}: max channel difference {}\n"](name, code, diff.max)
            }
            code += 1usize
        }
        if dump_dir.len > 0usize {
            // the control value table as the size's `prep` left it, in ClearType (cvt.txt) and black and white (cvt-bw.txt)
            var sz = 0usize
            while sz < hinters[fi].size_count {
                if hinters[fi].sizes[sz].ppem == at.px && hinters[fi].sizes[sz].ready {
                    let buf = cvt_text(ha, hinters[fi].sizes[sz].cvt)
                    var suffix: str = ".cvt-bw.txt"
                    if hinters[fi].sizes[sz].cleartype { suffix = ".cvt.txt" }
                    let (c1, c1_error) = str.concat(a, dump_dir, "/")
                    if c1_error != ok { ret c1_error }
                    let (c2, c2_error) = str.concat(a, c1, name[0usize..dot])
                    if c2_error != ok { ret c2_error }
                    let (c3, c3_error) = str.concat(a, c2, suffix)
                    if c3_error != ok { ret c3_error }
                    try fs.write_file(a, c3, buf)
                }
                sz += 1usize
            }
            let (d1, d1_error) = str.concat(a, dump_dir, "/")
            if d1_error != ok { ret d1_error }
            let (d2, d2_error) = str.concat(a, d1, name)
            if d2_error != ok { ret d2_error }
            let (d3, d3_error) = str.concat(a, d2, ".ours.bgra")
            if d3_error != ok { ret d3_error }
            try fs.write_file(a, d3, dump)
            let (o1, o1_error) = str.concat(a, d1, name)
            if o1_error != ok { ret o1_error }
            let (o2, o2_error) = str.concat(a, o1, ".bw.txt")
            if o2_error != ok { ret o2_error }
            try fs.write_file(a, o2, bw_buf[0usize..bw_len])
            let (o3, o3_error) = str.concat(a, o1, ".ct.txt")
            if o3_error != ok { ret o3_error }
            try fs.write_file(a, o3, ct_buf[0usize..ct_len])
        }
        if write_exact {
            exact_len = append(exact_buf, exact_len, name)
            exact_len = append(exact_buf, exact_len, " ")
            exact_len = append(exact_buf, exact_len, marks[0usize..674usize])
            exact_len = append(exact_buf, exact_len, "\n")
        }
        hint_glyphs_ok += line_hint_ok
        hint_glyphs += line_hint
        hint_points_ok += line_hint_points_ok
        hint_points += line_hint_points
        total.glyphs += line_sum.glyphs
        total.ink += line_sum.ink
        total.px_ok += line_sum.px_ok
        total.px_same += line_sum.px_same
        total.ink_px_ok += line_sum.ink_px_ok
        total.bw_ok += line_sum.bw_ok
        total.ink_bw_ok += line_sum.ink_bw_ok
        total.adv_ok += line_sum.adv_ok
        total.bw_pts += line_sum.bw_pts
        total.bw_pts_ok += line_sum.bw_pts_ok
        if report || verbose || write_exact {
            try io.printf["{}: ink glyphs {} px(<=2) {} px(identical) {} bw-outline {} adv {} bw-points {} of {} hinted {} of {} ({} of {} points)\n"](name, line_sum.ink, line_sum.ink_px_ok, line_sum.px_same, line_sum.ink_bw_ok, line_sum.adv_ok, line_sum.bw_pts_ok, line_sum.bw_pts, line_hint_ok, line_hint, line_hint_points_ok, line_hint_points)
        }
    }
    if report || verbose || write_exact {
        try io.printf["TOTAL glyphs {} (ink {}): px within 2 levels {} / ink {}, px identical {}, bw outline exact {} / ink {}, advance {}, bw points {} of {}, ClearType points exact for {} of {} glyphs ({} of {} points)\n"](total.glyphs, total.ink, total.px_ok, total.ink_px_ok, total.px_same, total.bw_ok, total.ink_bw_ok, total.adv_ok, total.bw_pts_ok, total.bw_pts, hint_glyphs_ok, hint_glyphs, hint_points_ok, hint_points)
    }
    if write_exact {
        let (out_path, out_path_error) = str.concat(a, dir, "/exact.txt")
        if out_path_error != ok { ret out_path_error }
        try fs.write_file(a, out_path, exact_buf[0usize..exact_len])
    }
    if failures > 0usize { os.exit(3) }
    ret ok
}
