// `e.gfx.dwtext`: Roboto drawn as Chromium on Windows draws it (Skia over DirectWrite, grey anti-aliasing), against alpha bytes read
// from a Chromium 149 capture of black text on white at 1x (--disable-lcd-text --font-render-hinting=none, the face from the Windows
// font directory as a web font). The mask of "H" at 16 px is checked on the four sub-pixel positions Skia has (0, 1/4, 1/2 and 3/4 of
// a pixel, which DirectWrite takes as 0, 1/3, 1/2 and 5/6), all of its 12 rows by 15 columns, byte for byte. The whole check passes
// when the font is not there (the table keys are checked first). `main dump` prints the four masks instead of checking them;
// `main overflow` and `main race` run only the rasteriser's own bound (#711) or concurrency (#712) checks.

use e.atomic
use e.fs
use e.gfx.dwtext
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.text.shape
use e.text.tthint
use e.text.ttglyph
use e.thread

fn font_path() -> str { ret "C:/Windows/Fonts/Roboto-Regular.ttf" }

fn append_int(buf: []u8, len: usize, v: i64) -> usize {
    var n = len
    var digits: [24]u8 = zero
    var count = 0usize
    var m = v
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

// The sub-pixel positions of the capture, as the sixths DirectWrite uses.
fn fraction(k: usize) -> f32 {
    if k == 0usize { ret 0.0 }
    if k == 1usize { ret 2.0 / 6.0 }
    if k == 2usize { ret 3.0 / 6.0 }
    ret 5.0 / 6.0
}

// Chromium's alpha bytes of "H" at 16 px at the four positions, row by row, a blank line between the masks.
fn expected() -> str {
    ret "0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 253 228 226 226 226 226 250 225 25 0 \n0 0 161 255 255 255 255 255 255 255 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 161 192 12 0 0 0 0 161 225 25 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 255 234 226 226 226 226 238 255 77 0 0 \n0 0 77 255 255 255 255 255 255 255 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 77 245 51 0 0 0 0 77 255 77 0 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 238 226 226 226 226 234 255 119 0 0 \n0 0 51 245 255 255 255 255 255 255 255 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 51 245 77 0 0 0 0 51 245 119 0 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n0 0 0 0 0 0 0 0 0 0 0 0 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 250 226 226 226 226 228 253 192 12 0 \n0 12 192 255 255 255 255 255 255 255 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 12 192 161 0 0 0 0 12 192 192 12 0 \n0 0 0 0 0 0 0 0 0 0 0 0 0 \n\n"
}

// --- The rasteriser's own bounds and shared state, exercised without a font (#711, #712).

type RaceJob = struct { cur: []i64, tags: []i64, ends: []usize, n: usize, nends: usize, scratch: []u8, want: []u8, tw: usize, th: usize, lut: []const u8, ft: bool, rounds: usize, bad: usize }

// `count` side-by-side rectangles, four on-curve points each, one pixel apart.
fn build_rects(cur: []i64, tags: []i64, ends: []usize, count: usize, width: i64, height: i64) -> usize {
    var r = 0usize
    while r < count {
        let x = i64(r) * 64i64
        let base = 4usize * r
        cur[2usize * base] = x
        cur[2usize * base + 1usize] = 0i64
        cur[2usize * (base + 1usize)] = x + width
        cur[2usize * (base + 1usize) + 1usize] = 0i64
        cur[2usize * (base + 2usize)] = x + width
        cur[2usize * (base + 2usize) + 1usize] = height
        cur[2usize * (base + 3usize)] = x
        cur[2usize * (base + 3usize) + 1usize] = height
        tags[base] = 1i64
        tags[base + 1usize] = 1i64
        tags[base + 2usize] = 1i64
        tags[base + 3usize] = 1i64
        ends[r] = base + 3usize
        r += 1usize
    }
    ret 4usize * count
}

// #711: a contour past flatten's point arrays and a scan line past its 256 crossings
// must answer false, never a truncated mask with true. Ten rectangles still draw.
fn overflow_checks(a: *mem.Arena) -> bool {
    let (scratch, scratch_error) = mem.alloc[u8](a, dwtext.scratch_bytes())
    if scratch_error != ok { ret false }
    var lut: [256]u8 = zero
    dwtext.lut_build(0usize, lut[0..])
    var circle_cur: [2200]i64 = zero
    var circle_tags: [1100]i64 = zero
    var circle_ends: [1]usize = zero
    var p = 0usize
    while p < 1100usize {
        let angle = 6.283185307179586f64 * f64(p) / 1100.0f64
        circle_cur[2usize * p] = 1280i64 + i64(math.floor[f64](1000.0f64 * math.cos[f64](angle) + 0.5f64))
        circle_cur[2usize * p + 1usize] = 1280i64 + i64(math.floor[f64](1000.0f64 * math.sin[f64](angle) + 0.5f64))
        circle_tags[p] = 1i64
        p += 1usize
    }
    circle_ends[0usize] = 1099usize
    let (_, circle_drawn) = dwtext.rasterize(scratch, circle_cur[..], circle_tags[..], circle_ends[..], 1usize, 1100usize, 1.0, 0.0, lut[0..])
    if circle_drawn { ret false }
    var wide_cur: [2400]i64 = zero
    var wide_tags: [1200]i64 = zero
    var wide_ends: [300]usize = zero
    let wide_n = build_rects(wide_cur[..], wide_tags[..], wide_ends[..], 300usize, 32i64, 128i64)
    let (_, wide_drawn) = dwtext.rasterize(scratch, wide_cur[..], wide_tags[..], wide_ends[..], 300usize, wide_n, 1.0, 0.0, lut[0..])
    if wide_drawn { ret false }
    var small_cur: [80]i64 = zero
    var small_tags: [40]i64 = zero
    var small_ends: [10]usize = zero
    let small_n = build_rects(small_cur[..], small_tags[..], small_ends[..], 10usize, 32i64, 128i64)
    let (_, small_drawn) = dwtext.rasterize(scratch, small_cur[..], small_tags[..], small_ends[..], 10usize, small_n, 1.0, 0.0, lut[0..])
    ret small_drawn
}

fn race_worker(j: *RaceJob) {
    var r = 0usize
    while r < j.rounds {
        var mask: dwtext.GlyphMask = zero
        var drawn = false
        if j.ft {
            let (m, d) = dwtext.rasterize_ft(j.scratch, j.cur, j.tags, j.ends, j.nends, j.n, 1.0, 0.0, j.lut)
            mask = m
            drawn = d
        } else {
            let (m, d) = dwtext.rasterize(j.scratch, j.cur, j.tags, j.ends, j.nends, j.n, 1.0, 0.0, j.lut)
            mask = m
            drawn = d
        }
        if !drawn || mask.width != j.tw || mask.height != j.th {
            j.bad += 1usize
        } else {
            var z = 0usize
            var same = true
            while z < j.tw * j.th {
                if j.scratch[dwtext.GRID_BYTES + z] != j.want[z] { same = false }
                z += 1usize
            }
            if !same { j.bad += 1usize }
        }
        r += 1usize
    }
}

// #712: one thread rasterises a wide glyph while another repeatedly rasterises a small
// one; each must keep its own mask byte for byte.
fn race_checks(a: *mem.Arena) -> bool {
    var lut: [256]u8 = zero
    dwtext.lut_build(0usize, lut[0..])
    var big_cur: [960]i64 = zero
    var big_tags: [480]i64 = zero
    var big_ends: [120]usize = zero
    let big_n = build_rects(big_cur[..], big_tags[..], big_ends[..], 120usize, 32i64, 20480i64)
    var small_cur: [80]i64 = zero
    var small_tags: [40]i64 = zero
    var small_ends: [10]usize = zero
    let small_n = build_rects(small_cur[..], small_tags[..], small_ends[..], 10usize, 32i64, 128i64)
    let (big_scratch, e0) = mem.alloc[u8](a, dwtext.scratch_bytes())
    if e0 != ok { ret false }
    let (small_scratch, e1) = mem.alloc[u8](a, dwtext.scratch_bytes())
    if e1 != ok { ret false }
    let (big_mask, big_ok) = dwtext.rasterize(big_scratch, big_cur[..], big_tags[..], big_ends[..], 120usize, big_n, 1.0, 0.0, lut[0..])
    if !big_ok { ret false }
    let (small_mask, small_ok) = dwtext.rasterize_ft(small_scratch, small_cur[..], small_tags[..], small_ends[..], 10usize, small_n, 1.0, 0.0, lut[0..])
    if !small_ok { ret false }
    let (big_want, e2) = mem.alloc[u8](a, big_mask.width * big_mask.height)
    if e2 != ok { ret false }
    let (small_want, e3) = mem.alloc[u8](a, small_mask.width * small_mask.height)
    if e3 != ok { ret false }
    var z = 0usize
    while z < big_mask.width * big_mask.height {
        big_want[z] = big_scratch[dwtext.GRID_BYTES + z]
        z += 1usize
    }
    z = 0usize
    while z < small_mask.width * small_mask.height {
        small_want[z] = small_scratch[dwtext.GRID_BYTES + z]
        z += 1usize
    }
    var big_job = RaceJob { cur: big_cur[..], tags: big_tags[..], ends: big_ends[..], n: big_n, nends: 120usize, scratch: big_scratch, want: big_want, tw: big_mask.width, th: big_mask.height, lut: lut[0..], ft: false, rounds: 1usize, bad: 0usize }
    var small_job = RaceJob { cur: small_cur[..], tags: small_tags[..], ends: small_ends[..], n: small_n, nends: 10usize, scratch: small_scratch, want: small_want, tw: small_mask.width, th: small_mask.height, lut: lut[0..], ft: true, rounds: 20000usize, bad: 0usize }
    let (big_thread, e4) = thread.spawn[RaceJob](race_worker, &big_job, 0usize)
    if e4 != ok { ret false }
    let (small_thread, e5) = thread.spawn[RaceJob](race_worker, &small_job, 0usize)
    if e5 != ok {
        let joined = thread.join(big_thread)
        if joined != ok { ret false }
        ret false
    }
    let joined_big = thread.join(big_thread)
    let joined_small = thread.join(small_thread)
    if joined_big != ok || joined_small != ok { ret false }
    ret big_job.bad == 0usize && small_job.bad == 0usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    var mode: str = ""
    if args.len > 1usize { mode = args[1usize] }
    // The rasteriser's own limits and shared state before any font is read; `dump` keeps
    // the mask printer free of them and `overflow`/`race` select one for evidence.
    if !str.eq(mode, "dump") {
        let synthetic_mark = mem.mark(a)
        if str.eq(mode, "race") {
            if !race_checks(a) { os.exit(7i32) }
        } else if str.eq(mode, "overflow") {
            if !overflow_checks(a) { os.exit(6i32) }
        } else {
            if !overflow_checks(a) { os.exit(6i32) }
            if !race_checks(a) { os.exit(7i32) }
        }
        mem.reset(a, synthetic_mark)
    }
    // The table a colour selects (measured on Chromium's text in 90 colours): each channel is cut to three bits before the luminance is taken.
    if dwtext.lut_key(56.0 / 255.0, 30.0 / 255.0, 114.0 / 255.0) != 0usize { ret tthint.Trap }
    if dwtext.lut_key(28.0 / 255.0, 16.0 / 255.0, 252.0 / 255.0) != 0usize { ret tthint.Trap }
    if dwtext.lut_key(192.0 / 255.0, 4.0 / 255.0, 231.0 / 255.0) != 2usize { ret tthint.Trap }
    if dwtext.lut_key(36.0 / 255.0, 36.0 / 255.0, 36.0 / 255.0) != 1usize { ret tthint.Trap }
    if dwtext.lut_key(1.0, 1.0, 1.0) != 7usize { ret tthint.Trap }
    let (bytes, read_error) = fs.read_file(a, font_path(), 16777216usize)
    if read_error != ok {
        let (written, write_error) = os.write(os.stdout(), "skipped: the font is not present\n")
        ret ok
    }
    let (h, open_error) = tthint.open(a, bytes)
    if open_error != ok { ret open_error }
    let font = shape.Font { id: 1u32, data: bytes, face_index: 0u32 }
    let (cmap, has_cmap) = shape.find_table(font, shape.TAG_CMAP)
    if !has_cmap { ret tthint.Unsupported }
    let (sub, has_sub) = shape.cmap_subtable(bytes, cmap)
    if !has_sub { ret tthint.Unsupported }
    ttglyph.set_end_fit(false)
    let gid = shape.glyph_of(bytes, sub, 72u32)
    let (outline, hint_error) = ttglyph.hint_glyph(h, a, 16i64, gid, true)
    if hint_error != ok { ret hint_error }
    let (scratch, scratch_error) = mem.alloc[u8](a, dwtext.scratch_bytes())
    if scratch_error != ok { ret scratch_error }
    var lut: [256]u8 = zero
    dwtext.lut_build(0usize, lut[0..])
    var out: [4096]u8 = zero
    var len = 0usize
    var k = 0usize
    while k < 4usize {
        let (m, drawn) = dwtext.rasterize(scratch, outline.cur, outline.tags, outline.ends, outline.nends, outline.n, 1.0, fraction(k), lut[0..])
        if !drawn { ret tthint.Trap }
        var y = 0usize
        while y < m.height {
            var x = 0usize
            while x < m.width {
                len = append_int(out[0..], len, i64(scratch[dwtext.GRID_BYTES + y * m.width + x]))
                if len < out.len {
                    out[len] = 32u8
                    len += 1usize
                }
                x += 1usize
            }
            if len < out.len {
                out[len] = 10u8
                len += 1usize
            }
            y += 1usize
        }
        if len < out.len {
            out[len] = 10u8
            len += 1usize
        }
        k += 1usize
    }
    if args.len > 1usize && str.eq(args[1usize], "dump") {
        try io.print(out[0..len])
        ret ok
    }
    if !str.eq(out[0..len], expected()) { ret tthint.Trap }
    ret ok
}
