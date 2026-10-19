// Sizes and glyphs for `e.text.tthint`: `size_of` runs a font's `fpgm` once and its `prep` for a pixel size in one mode (black
// and white or ClearType), and `hint_glyph` loads a glyph at a size, scales its outline to 26.6, runs its instructions and answers
// the hinted outline. A composite glyph hints its components first and runs its own program over the placed points, as
// FreeType does. In ClearType a glyph's right phantom point starts at the black-and-white advance (GDI sets ClearType text with
// the widths of the bitmap rasteriser), which is why a ClearType load makes a black-and-white one of the same glyph.

use e.math
use e.io
use e.mem
use e.text.shape
use e.text.tthint

// The glyph programs are not run when set: the points stay as scaled and the phantom points as rounded (the state a program starts from;
// the oracle tool compares it with a tap font whose glyphs have no programs).
var skip_programs: bool = zero
var trace_gid: i64 = -1i64
var top_glyph: usize = zero
var part_offset: i64 = zero

fn set_trace_glyph(gid: i64) { trace_gid = gid }

fn set_skip_programs(on: bool) { skip_programs = on }

fn set_cut(n: i64) { tthint.set_cut(n) }

fn set_cut_iup(b: bool) { tthint.set_cut_iup(b) }

type Loaded = struct { lv: usize, pp1x: i64, adv: i64 }

fn gl_metrics(h: *tthint.Hinter, gid: usize) -> (i64, i64) {
    if h.hmetrics == 0usize { ret (0i64, 0i64) }
    if gid < h.hmetrics {
        ret (tthint.rd16(h.data, h.hmtx + 4usize * gid), tthint.rds16(h.data, h.hmtx + 4usize * gid + 2usize))
    }
    ret (tthint.rd16(h.data, h.hmtx + 4usize * (h.hmetrics - 1usize)), tthint.rds16(h.data, h.hmtx + 4usize * h.hmetrics + 2usize * (gid - h.hmetrics)))
}

// The glyph's bytes in `glyf` as (start, end) offsets into the font data; equal when the glyph has no outline.
fn gl_range(h: *tthint.Hinter, gid: usize) -> (usize, usize) {
    if gid >= h.glyph_count { ret (0usize, 0usize) }
    var s = 0usize
    var e = 0usize
    if h.long_loca {
        s = usize(tthint.rd32(h.data, h.loca + 4usize * gid))
        e = usize(tthint.rd32(h.data, h.loca + 4usize * gid + 4usize))
    } else {
        s = 2usize * usize(tthint.rd16(h.data, h.loca + 2usize * gid))
        e = 2usize * usize(tthint.rd16(h.data, h.loca + 2usize * gid + 2usize))
    }
    if e <= s || e > h.glyf_len || e - s < 10usize { ret (0usize, 0usize) }
    ret (h.glyf + s, h.glyf + e)
}

// The size of `ppem` pixels in the mode: found, or made by running `prep`. The answer is the index in `h.sizes`.
fn size_of(h: *tthint.Hinter, a: *mem.Arena, ppem: i64, cleartype: bool) -> (usize, err) {
    var i = 0usize
    while i < h.size_count {
        if h.sizes[i].ppem == ppem && h.sizes[i].cleartype == cleartype {
            if !h.sizes[i].ready { ret (i, tthint.Trap) }
            ret (i, ok)
        }
        i += 1usize
    }
    if h.size_count >= tthint.MAX_SIZES || ppem < 1i64 || ppem > 400i64 { ret (0usize, tthint.NoRoom) }
    let si = h.size_count
    h.size_count += 1usize
    let s = &h.sizes[si]
    s.ppem = ppem
    s.cleartype = cleartype
    s.live = true
    s.xscale = tthint.divfix(ppem * 64i64, h.upem)
    let (cvt, cvt_error) = mem.alloc[i64](a, h.cvt_count + 1usize)
    if cvt_error != ok { ret (si, tthint.NoRoom) }
    var c = 0usize
    while c < h.cvt_count {
        cvt[c] = tthint.mulfix(tthint.rds16(h.data, h.cvt_at + 2usize * c), s.xscale)
        c += 1usize
    }
    s.cvt = cvt[0usize..h.cvt_count]
    let (storage, storage_error) = mem.alloc[i64](a, h.max_storage + 1usize)
    if storage_error != ok { ret (si, tthint.NoRoom) }
    var z = 0usize
    while z < h.max_storage {
        storage[z] = 0i64
        z += 1usize
    }
    s.storage = storage[0usize..h.max_storage]
    let (twi, twi_error) = tthint.zone_new(a, h.max_twilight + 4usize, 1usize)
    if twi_error != ok { ret (si, tthint.NoRoom) }
    s.twi = twi
    tthint.zone_clear(&s.twi, h.max_twilight + 4usize)
    let (snap_org, e1) = mem.alloc[i64](a, 2usize * (h.max_twilight + 4usize))
    if e1 != ok { ret (si, tthint.NoRoom) }
    let (snap_cur, e2) = mem.alloc[i64](a, 2usize * (h.max_twilight + 4usize))
    if e2 != ok { ret (si, tthint.NoRoom) }
    let (snap_orus, e3) = mem.alloc[i64](a, 2usize * (h.max_twilight + 4usize))
    if e3 != ok { ret (si, tthint.NoRoom) }
    s.snap_org = snap_org
    s.snap_cur = snap_cur
    s.snap_orus = snap_orus
    // fpgm, once for the font.
    h.ppem = ppem
    h.xs = s.xscale
    h.cleartype = cleartype
    h.composite = false
    h.cvt = s.cvt
    h.storage = s.storage
    h.zone[0usize] = s.twi
    h.zone[1usize].n = 0usize
    if !h.fpgm_done {
        h.gs = tthint.gs_default()
        h.sp = 0usize
        h.fpgm_done = true
        if h.fpgm_len > 0usize {
            let fpgm_error = tthint.vm_run(h, h.fpgm_at, h.fpgm_at + h.fpgm_len)
            if fpgm_error != ok {
                s.ready = false
                ret (si, tthint.Trap)
            }
        }
    }
    // prep, from a fresh graphics state.
    h.gs = tthint.gs_default()
    h.sp = 0usize
    h.zone[0usize] = s.twi
    if h.prep_len > 0usize {
        let prep_error = tthint.vm_run(h, h.prep_at, h.prep_at + h.prep_len)
        if prep_error != ok {
            s.ready = false
            ret (si, tthint.Trap)
        }
    }
    var g = h.gs
    s.ic = g.instruct_control
    g.rp0 = 0i64
    g.rp1 = 0i64
    g.rp2 = 0i64
    g.gep0 = 1usize
    g.gep1 = 1usize
    g.gep2 = 1usize
    g.proj_x = 16384i64
    g.proj_y = 0i64
    g.free_x = 16384i64
    g.free_y = 0i64
    g.dual_x = 16384i64
    g.dual_y = 0i64
    g.lp = 1i64
    if (g.instruct_control & 2i64) != 0i64 { g = tthint.gs_default() }
    s.gs = g
    var t = 0usize
    while t < 2usize * (h.max_twilight + 4usize) {
        s.snap_org[t] = s.twi.org[t]
        s.snap_cur[t] = s.twi.cur[t]
        s.snap_orus[t] = s.twi.orus[t]
        t += 1usize
    }
    s.ready = true
    ret (si, ok)
}

// Fills the zone `z` (already holding its points scaled to 26.6) with the glyph program at `lo..hi` run over it. A program that
// traps leaves the points where they had got to.
fn gl_run(h: *tthint.Hinter, a: *mem.Arena, si: usize, gid: usize, z: *tthint.Zone, lo: usize, hi: usize, composite: bool) -> err {
    let top_gid = top_glyph
    let off_here = part_offset
    let s = &h.sizes[si]
    let n = z.n
    var bw_adv = 0i64
    if s.cleartype {
        let (bw, bw_error) = size_of(h, a, s.ppem, false)
        if bw_error != ok { ret bw_error }
        // a component is fitted to the advance of the glyph it belongs to
        let (loaded, load_error) = gl_load(h, a, bw, top_gid, 0usize)
        if load_error != ok { ret load_error }
        bw_adv = device_advance(h, false, s.ppem, top_gid, loaded.adv)
        h.level = loaded.lv
    }
    var i = 0usize
    while i < 2usize * n {
        z.org[i] = z.cur[i]
        i += 1usize
    }
    z.cur[2usize * (n - 4usize)] = tthint.pix_round(z.cur[2usize * (n - 4usize)])
    z.cur[2usize * (n - 3usize)] = tthint.pix_round(z.cur[2usize * (n - 3usize)])
    // In ClearType GDI starts the right phantom point at the advance rounded to 1/16 pixel (26.6 first, as scaled), not at the
    // black-and-white advance: read back from a copy of Segoe UI whose glyphs have no programs, all 189 glyphs of the oracle.
    if s.cleartype {
        let scaled = z.org[2usize * (n - 3usize)] - z.org[2usize * (n - 4usize)]
        z.cur[2usize * (n - 3usize)] = z.cur[2usize * (n - 4usize)] + tthint.fdiv(scaled + 2i64, 4i64) * 4i64
    }
    z.cur[2usize * (n - 2usize) + 1usize] = tthint.pix_round(z.cur[2usize * (n - 2usize) + 1usize])
    z.cur[2usize * (n - 1usize) + 1usize] = tthint.pix_round(z.cur[2usize * (n - 1usize) + 1usize])
    if (s.ic & 1i64) != 0i64 || hi <= lo || skip_programs { ret ok }
    h.ppem = s.ppem
    h.xs = s.xscale
    h.cleartype = s.cleartype
    h.composite = composite
    // The advance fitting of GDI's ClearType (`tthint.ct_scale`): the points a glyph's x program interpolated or paired are stretched
    // by the device table's advance over the scaled one when it reaches IUP[x]. Composites are not fitted yet.
    h.ctA = 0i64
    h.ctX = 0i64
    h.ct_stop = false
    if s.cleartype && !composite && bw_adv > 0i64 {
        h.ctX = z.org[2usize * (n - 3usize)] - z.org[2usize * (n - 4usize)]
        if top_gid != gid {
            let (top_adv, top_lsb) = gl_metrics(h, top_gid)
            h.ctX = tthint.mulfix(top_adv, s.xscale)
        }
        h.ctA = bw_adv
        h.ctOff = 0i64
    }
    h.gs = s.gs
    h.sp = 0usize
    h.ran = true
    h.iup_y = false
    var k = 0usize
    while k < h.cvt_count {
        h.cvt_work[k] = s.cvt[k]
        k += 1usize
    }
    h.cvt = h.cvt_work[0usize..h.cvt_count]
    k = 0usize
    while k < h.max_storage {
        h.storage_work[k] = s.storage[k]
        k += 1usize
    }
    h.storage = h.storage_work[0usize..h.max_storage]
    k = 0usize
    while k < 2usize * (h.max_twilight + 4usize) {
        s.twi.org[k] = s.snap_org[k]
        s.twi.cur[k] = s.snap_cur[k]
        s.twi.orus[k] = s.snap_orus[k]
        k += 1usize
    }
    h.zone[0usize] = s.twi
    h.zone[1usize] = *z
    tthint.set_trace((i64(gid) == trace_gid || trace_gid == -2i64) && s.cleartype)
    h.ct_done = false
    h.ct_part = top_gid != gid
    tthint.set_cut_here(top_gid == gid)
    let run_error = tthint.vm_run(h, lo, hi)
    if top_gid != gid && h.ctA != 0i64 && !h.ct_done && h.zone[1usize].n > 4usize { tthint.ct_scale(h) }
    tthint.set_trace(false)
    ret ok
}

// The advance of a glyph: GDI takes it from the device metrics table at the sizes the table lists, whatever the hinted phantom point
// says (every one of the 14000 advances of the oracle agrees with it), in ClearType too, where the pen steps by the same whole pixels.
// The hinter itself keeps the hinted phantom point for the fitting of the outline.
fn device_advance(h: *tthint.Hinter, cleartype: bool, ppem: i64, gid: usize, hinted: i64) -> i64 {
    if cleartype { ret hinted }
    let (w, found) = tthint.hdmx_width(h, ppem, gid)
    if found { ret w * 64i64 }
    ret hinted
}

// Loads a glyph at a size: its points in a zone of `h.zsets`, the zone's level in the answer. Levels are released by the caller
// setting `h.level` back.
fn gl_load(h: *tthint.Hinter, a: *mem.Arena, si: usize, gid: usize, depth: usize) -> (Loaded, err) {
    var out: Loaded = zero
    if depth > 4usize || h.level >= tthint.MAX_LEVEL { ret (out, tthint.NoRoom) }
    let lv = h.level
    h.level = lv + 1usize
    out.lv = lv
    let s = &h.sizes[si]
    let z = &h.zsets[lv]
    let (adv, lsb) = gl_metrics(h, gid)
    let (g0, g1) = gl_range(h, gid)
    if g1 <= g0 {
        tthint.zone_clear(z, 4usize)
        z.orus[0usize] = 0i64 - lsb
        z.orus[2usize] = adv - lsb
        var q = 0usize
        while q < 4usize {
            z.cur[2usize * q] = tthint.mulfix(z.orus[2usize * q], s.xscale)
            z.cur[2usize * q + 1usize] = tthint.mulfix(z.orus[2usize * q + 1usize], s.xscale)
            z.org[2usize * q] = z.cur[2usize * q]
            z.org[2usize * q + 1usize] = z.cur[2usize * q + 1usize]
            z.tags[q] = 1i64
            q += 1usize
        }
        out.pp1x = z.cur[0usize]
        out.adv = z.cur[2usize] - z.cur[0usize]
        ret (out, ok)
    }
    let d = h.data
    let contours = tthint.rds16(d, g0)
    let xmin = tthint.rds16(d, g0 + 2usize)
    let ymax = tthint.rds16(d, g0 + 8usize)
    if contours >= 0i64 {
        let count = usize(contours)
        if count > tthint.MAX_ENDS { ret (out, tthint.NoRoom) }
        tthint.zone_clear(z, 0usize)
        var npts = 0usize
        var c = 0usize
        while c < count {
            z.ends[c] = usize(tthint.rd16(d, g0 + 10usize + 2usize * c))
            npts = z.ends[c] + 1usize
            c += 1usize
        }
        z.nends = count
        if npts + 4usize > tthint.MAX_PTS + 4usize { ret (out, tthint.NoRoom) }
        let ilen = usize(tthint.rd16(d, g0 + 10usize + 2usize * count))
        let code_lo = g0 + 12usize + 2usize * count
        var at = code_lo + ilen
        zone_prepare(z, npts + 4usize, count)
        var i = 0usize
        while i < npts {
            if at >= g1 { ret (out, tthint.NoRoom) }
            let flag = i64(d[at])
            at += 1usize
            z.tags[i] = flag
            i += 1usize
            if (flag & 8i64) != 0i64 {
                if at >= g1 { ret (out, tthint.NoRoom) }
                var repeats = usize(d[at])
                at += 1usize
                while repeats > 0usize && i < npts {
                    z.tags[i] = flag
                    i += 1usize
                    repeats = repeats - 1usize
                }
            }
        }
        var value = 0i64
        i = 0usize
        while i < npts {
            let flag = z.tags[i]
            if (flag & 2i64) != 0i64 {
                let delta = i64(d[at])
                at += 1usize
                if (flag & 16i64) != 0i64 {
                    value = value + delta
                } else {
                    value = value - delta
                }
            } else if (flag & 16i64) == 0i64 {
                value = value + tthint.rds16(d, at)
                at += 2usize
            }
            z.orus[2usize * i] = value
            i += 1usize
        }
        value = 0i64
        i = 0usize
        while i < npts {
            let flag = z.tags[i]
            if (flag & 4i64) != 0i64 {
                let delta = i64(d[at])
                at += 1usize
                if (flag & 32i64) != 0i64 {
                    value = value + delta
                } else {
                    value = value - delta
                }
            } else if (flag & 32i64) == 0i64 {
                value = value + tthint.rds16(d, at)
                at += 2usize
            }
            z.orus[2usize * i + 1usize] = value
            i += 1usize
        }
        i = 0usize
        while i < npts {
            z.tags[i] = z.tags[i] & 1i64
            i += 1usize
        }
        // The phantom points: the left one where the side bearing puts it, the right one an advance on, and two on the baseline.
        z.orus[2usize * npts] = xmin - lsb
        z.orus[2usize * npts + 1usize] = 0i64
        z.orus[2usize * npts + 2usize] = xmin - lsb + adv
        z.orus[2usize * npts + 3usize] = 0i64
        z.orus[2usize * npts + 4usize] = 0i64
        z.orus[2usize * npts + 5usize] = ymax
        z.orus[2usize * npts + 6usize] = 0i64
        z.orus[2usize * npts + 7usize] = 0i64
        i = 0usize
        while i < npts + 4usize {
            z.cur[2usize * i] = tthint.mulfix(z.orus[2usize * i], s.xscale)
            z.cur[2usize * i + 1usize] = tthint.mulfix(z.orus[2usize * i + 1usize], s.xscale)
            if i >= npts { z.tags[i] = 1i64 }
            i += 1usize
        }
        let run_error = gl_run(h, a, si, gid, z, code_lo, code_lo + ilen, false)
        if run_error != ok { ret (out, run_error) }
        let n = z.n
        out.pp1x = z.cur[2usize * (n - 4usize)]
        out.adv = z.cur[2usize * (n - 3usize)] - z.cur[2usize * (n - 4usize)]
        ret (out, ok)
    }
    // A composite glyph: components first, placed, then the glyph's own program over the placed points.
    tthint.zone_clear(z, 0usize)
    var at = g0 + 10usize
    var more = true
    var np = 0usize
    var last_flags = 0i64
    var ends_n = 0usize
    while more && at + 4usize <= g1 {
        let flags = tthint.rd16(d, at)
        let component = usize(tthint.rd16(d, at + 2usize))
        at += 4usize
        var dx = 0i64
        var dy = 0i64
        if (flags & 1i64) != 0i64 {
            dx = tthint.rds16(d, at)
            dy = tthint.rds16(d, at + 2usize)
            at += 4usize
        } else {
            dx = i64(d[at])
            dy = i64(d[at + 1usize])
            if dx >= 128i64 { dx = dx - 256i64 }
            if dy >= 128i64 { dy = dy - 256i64 }
            at += 2usize
        }
        var sxx = 1.0f64
        var sxy = 0.0f64
        var syx = 0.0f64
        var syy = 1.0f64
        if (flags & 8i64) != 0i64 {
            sxx = f64(tthint.rds16(d, at)) / 16384.0
            syy = sxx
            at += 2usize
        } else if (flags & 64i64) != 0i64 {
            sxx = f64(tthint.rds16(d, at)) / 16384.0
            syy = f64(tthint.rds16(d, at + 2usize)) / 16384.0
            at += 4usize
        } else if (flags & 128i64) != 0i64 {
            sxx = f64(tthint.rds16(d, at)) / 16384.0
            sxy = f64(tthint.rds16(d, at + 2usize)) / 16384.0
            syx = f64(tthint.rds16(d, at + 4usize)) / 16384.0
            syy = f64(tthint.rds16(d, at + 6usize)) / 16384.0
            at += 8usize
        }
        last_flags = flags
        more = (flags & 32i64) != 0i64
        if (flags & 2i64) == 0i64 { ret (out, tthint.Unsupported) }
        var px = tthint.mulfix(dx, s.xscale)
        var py = tthint.mulfix(dy, s.xscale)
        if (flags & 4i64) != 0i64 {
            // ClearType rounds along x on its grid of 1/16 pixel
            if s.cleartype {
                px = tthint.fdiv(px + 2i64, 4i64) * 4i64
            } else {
                px = tthint.pix_round(px)
            }
            py = tthint.pix_round(py)
        }
        part_offset = px
        let (part, part_error) = gl_load(h, a, si, component, depth + 1usize)
        part_offset = 0i64
        if part_error != ok { ret (out, part_error) }
        let cz = &h.zsets[part.lv]
        let m = cz.n - 4usize
        if trace_gid == -2i64 {
            let e9 = io.printf["component {} offset {} pp1x {} adv {} first x {}\n"](component, px, part.pp1x, part.adv, cz.cur[0usize])
        }
        if np + m + 4usize > tthint.MAX_PTS + 4usize || ends_n + cz.nends > tthint.MAX_ENDS {
            h.level = part.lv
            ret (out, tthint.NoRoom)
        }
        var e = 0usize
        while e < cz.nends {
            z.ends[ends_n + e] = np + cz.ends[e]
            e += 1usize
        }
        ends_n += cz.nends
        var j = 0usize
        while j < m {
            let x = f64(cz.cur[2usize * j] - part.pp1x)
            let y = f64(cz.cur[2usize * j + 1usize])
            let tx = i64(math.floor[f64](x * sxx + y * syx + 0.5))
            let ty = i64(math.floor[f64](x * sxy + y * syy + 0.5))
            z.cur[2usize * (np + j)] = tx + px
            z.cur[2usize * (np + j) + 1usize] = ty + py
            z.tags[np + j] = cz.tags[j] & 1i64
            j += 1usize
        }
        np += m
        h.level = part.lv
    }
    z.nends = ends_n
    zone_prepare(z, np + 4usize, ends_n)
    let (g_lo, g_hi) = composite_program(h, g0, g1, at, last_flags)
    var i = 0usize
    // Phantoms: the left at zero, the right an advance on, the vertical pair on the baseline.
    z.cur[2usize * np] = 0i64
    z.cur[2usize * np + 1usize] = 0i64
    z.cur[2usize * np + 2usize] = tthint.mulfix(adv, s.xscale)
    z.cur[2usize * np + 3usize] = 0i64
    z.cur[2usize * np + 4usize] = 0i64
    z.cur[2usize * np + 5usize] = tthint.mulfix(ymax, s.xscale)
    z.cur[2usize * np + 6usize] = 0i64
    z.cur[2usize * np + 7usize] = 0i64
    var q = 0usize
    while q < 4usize {
        z.tags[np + q] = 1i64
        q += 1usize
    }
    i = 0usize
    while i < np + 4usize {
        z.org[2usize * i] = z.cur[2usize * i]
        z.org[2usize * i + 1usize] = z.cur[2usize * i + 1usize]
        i += 1usize
    }
    i = 0usize
    while i < np + 4usize {
        z.orus[2usize * i] = z.cur[2usize * i]
        z.orus[2usize * i + 1usize] = z.cur[2usize * i + 1usize]
        i += 1usize
    }
    let run_error = gl_run(h, a, si, gid, z, g_lo, g_hi, true)
    if run_error != ok { ret (out, run_error) }
    let n = z.n
    out.pp1x = z.cur[2usize * (n - 4usize)]
    out.adv = z.cur[2usize * (n - 3usize)] - z.cur[2usize * (n - 4usize)]
    ret (out, ok)
}

// Sizes the zone for `n` points and `ends` contours, its per-point state cleared.
fn zone_prepare(z: *tthint.Zone, n: usize, ends: usize) {
    z.n = n
    z.nends = ends
    var i = 0usize
    while i < n {
        z.sh[i] = 0i64
        z.ipd[i] = false
        z.mp[i] = 0i64
        z.lp[i] = 0i64
        z.ipr[i] = 0i64
        i += 1usize
    }
}

// The composite glyph's own instructions: after the last component, when it says there are any.
fn composite_program(h: *tthint.Hinter, g0: usize, g1: usize, at: usize, last_flags: i64) -> (usize, usize) {
    if (last_flags & 256i64) == 0i64 || at + 2usize > g1 { ret (0usize, 0usize) }
    let count = usize(tthint.rd16(h.data, at))
    if at + 2usize + count > g1 { ret (0usize, 0usize) }
    ret (at + 2usize, at + 2usize + count)
}

// The scan conversion mode a size's SCANCTRL and SCANTYPE ask for, as the bits `Outline.scan` documents. Drop-out control is on when
// SCANCTRL says so for this ppem (threshold in the low byte, 0x100 on up to the threshold, 0x800 off above it); a font that never
// set either gets 4 + 8, the smart rounding the unhinted fonts show.
fn scan_mode(ctrl: i64, kind: i64, ppem: i64) -> i64 {
    if ctrl == 0i64 && kind == 0i64 { ret 12i64 }
    let thr = ctrl & 255i64
    var on = false
    if thr == 255i64 {
        on = true
    } else if thr != 0i64 {
        if (ctrl & 256i64) != 0i64 && ppem <= thr { on = true }
        if (ctrl & 2048i64) != 0i64 && ppem > thr { on = false }
    }
    if !on { ret 2i64 }
    if kind == 0i64 { ret 0i64 }
    if kind == 1i64 { ret 1i64 }
    if kind == 4i64 { ret 4i64 }
    if kind == 5i64 { ret 5i64 }
    ret 2i64
}

// The hinted outline of glyph `gid` at `ppem` pixels, in the mode. Its slices stay valid until the next call.
fn hint_glyph(h: *tthint.Hinter, a: *mem.Arena, ppem: i64, gid: u32, cleartype: bool) -> (tthint.Outline, err) {
    var out: tthint.Outline = zero
    let (si, size_error) = size_of(h, a, ppem, cleartype)
    if size_error != ok { ret (out, size_error) }
    h.level = 0usize
    h.ran = false
    top_glyph = usize(gid)
    let (loaded, load_error) = gl_load(h, a, si, usize(gid), 0usize)
    if load_error != ok { ret (out, load_error) }
    let z = &h.zsets[loaded.lv]
    out.n = z.n - 4usize
    out.cur = z.cur
    out.hinted = h.ran
    out.tags = z.tags
    out.ends = z.ends
    out.nends = z.nends
    out.pp1x = loaded.pp1x
    out.adv = device_advance(h, false, ppem, usize(gid), loaded.adv)
    out.smooth = (tthint.gasp_flags(h, ppem) & 8i64) != 0i64
    out.scan = scan_mode(h.sizes[si].gs.scan_control, h.sizes[si].gs.scan_type, ppem)
    ret (out, ok)
}
