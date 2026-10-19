// TrueType bytecode hinting over caller-provided font bytes: the `fpgm`, `prep` and glyph
// programs of a `glyf` font run in an interpreter, and a glyph comes back as the hinted
// outline in 26.6 pixel units. Two modes share one machine. Black-and-white (`cleartype`
// false) is the plain interpreter and gives GDI's hinted advance widths. ClearType
// (`cleartype` true) answers `GETINFO` as the GDI rasteriser does, rounds and measures along
// x at 1/16 pixel, ignores `DELTAP` along x, and lays stems out the way GDI's ClearType
// does (see `vm_mirp`). The ClearType rules were fitted to what `GetGlyphOutline` and the
// ClearType renderer of Windows return for Segoe UI and Tahoma; they are the most that
// could be measured, not the whole of what Windows does, and the module says so in its
// name: it hints, it does not claim to reproduce GDI. A program that traps leaves the glyph
// as far as it got, as a real rasteriser does.
//
// Nothing is read from disk and nothing is cached across `open`: the caller owns the font
// bytes and the arena. Every number is an `i64`; coordinates are 26.6 unless the name says
// they are font units (`orus`). The result of `hint_glyph` points into the hinter's own
// storage and is valid until the next call.

use e.io
use e.math
use e.mem
use e.text.shape

error Trap
error NoRoom
error Unsupported

const TAG_GLYF: u32 = 0x676C7966u32
const TAG_LOCA: u32 = 0x6C6F6361u32
const TAG_CVT: u32 = 0x63767420u32
const TAG_FPGM: u32 = 0x6670676Du32
const TAG_PREP: u32 = 0x70726570u32
const TAG_HDMX: u32 = 0x68646D78u32
const TAG_GASP: u32 = 0x67617370u32

const MAX_PTS: usize = 800usize
const MAX_ENDS: usize = 160usize
const MAX_LEVEL: usize = 14usize
const MAX_SIZES: usize = 24usize
const MAX_CALL: usize = 64usize
const MAX_STEPS: usize = 2000000usize

type Zone = struct { n: usize, org: []i64, cur: []i64, orus: []i64, tags: []i64, sh: []i64, ipd: []bool, mp: []i64, lp: []i64, ipr: []i64, ends: []usize, nends: usize }
type Gs = struct { rp0: i64, rp1: i64, rp2: i64, dual_x: i64, dual_y: i64, proj_x: i64, proj_y: i64, free_x: i64, free_y: i64, lp: i64, min_dist: i64, round_state: i64, auto_flip: bool, cvt_cut_in: i64, sw_cut_in: i64, sw_value: i64, delta_base: i64, delta_shift: i64, instruct_control: i64, scan_control: i64, scan_type: i64, gep0: usize, gep1: usize, gep2: usize }
// A size of the face in one mode: its cvt and storage after `prep`, the graphics state `prep` left, and the twilight zone
// with a copy of how `prep` left it (restored before every glyph so a glyph never sees another's twilight points).
type Size = struct { ppem: i64, cleartype: bool, live: bool, ready: bool, xscale: i64, cvt: []i64, storage: []i64, gs: Gs, ic: i64, twi: Zone, snap_org: []i64, snap_cur: []i64, snap_orus: []i64 }
type Hinter = struct {
    data: []const u8,
    upem: i64,
    glyf: usize, glyf_len: usize, loca: usize, long_loca: bool, glyph_count: usize,
    hmtx: usize, hmetrics: usize,
    cvt_at: usize, cvt_count: usize,
    fpgm_at: usize, fpgm_len: usize, prep_at: usize, prep_len: usize,
    hdmx_at: usize, hdmx_records: usize, hdmx_record_size: usize,
    gasp_at: usize, gasp_ranges: usize,
    max_storage: usize, max_twilight: usize, max_fdefs: usize, max_stack: usize,
    fdef_lo: []usize, fdef_hi: []usize, fdef_delta: []bool, fdef_bypass: []i64, in_delta: bool, iup_y: bool, ct_done: bool, ct_part: bool, bypass: i64, fpgm_done: bool,
    sizes: [24]Size, size_count: usize,
    zsets: [14]Zone, level: usize,
    stack: []i64, sp: usize, fail: bool,
    cvt: []i64, storage: []i64, cvt_work: []i64, storage_work: []i64,
    gs: Gs,
    zone: [2]Zone,
    code_lo: usize, code_hi: usize, ip: usize, depth: usize, steps: usize,
    ppem: i64, xs: i64, cleartype: bool, composite: bool,
    sr_per: i64, sr_phase: i64, sr_thr: i64,
    ctA: i64, ctX: i64, ctOff: i64, ran: bool, ct_stop: bool, ct_cyc: bool
}
// What `hint_glyph` answers: the points of the outline (x, y interleaved, 26.6, x relative to the glyph's left phantom point),
// whether each is on the curve (bit 0 of `tags`), the last point of each contour, the glyph's advance in this mode and the
// scan conversion the size's `prep` asked for (`scan`: bit 0 exclude stubs, bit 1 no drop-out control, bit 2 smart rounding; 8 added
// when the font never set a scan type).
type Outline = struct { n: usize, cur: []i64, hinted: bool, tags: []i64, ends: []usize, nends: usize, pp1x: i64, adv: i64, scan: i64, smooth: bool }

fn sgn1(x: i64) -> i64 {
    if x < 0i64 { ret -1i64 }
    ret 1i64
}

fn abs64(x: i64) -> i64 {
    if x < 0i64 { ret 0i64 - x }
    ret x
}

// Division rounding toward negative infinity, as the reference does (`//`).
fn fdiv(a: i64, b: i64) -> i64 {
    var q = a / b
    if a % b != 0i64 && ((a < 0i64) != (b < 0i64)) { q = q - 1i64 }
    ret q
}

// Half up, which is what the hinter's own scaling uses. FreeType's `FT_MulFix` rounds half away from zero; the unhinted outline of the
// Android look's FreeType mode (`ttglyph.set_skip_programs`) asks for that with `set_symmetric`.
var symmetric: bool = false
fn set_symmetric(on: bool) { symmetric = on }

fn mulfix(a: i64, b: i64) -> i64 {
    if symmetric && a * b < 0i64 { ret 0i64 - (((0i64 - a * b) + 32768i64) >> 16u32) }
    ret (a * b + 32768i64) >> 16u32
}

fn divfix(a: i64, b: i64) -> i64 {
    let s = sgn1(a) * sgn1(b)
    let x = abs64(a)
    let y = abs64(b)
    if y == 0i64 { ret 2147483647i64 }
    ret s * (((x << 16u32) + (y >> 1u32)) / y)
}

// Symmetric rounding: half away from zero.
fn muldiv(a: i64, b: i64, c: i64) -> i64 {
    if c == 0i64 { ret 2147483647i64 }
    let s = sgn1(a) * sgn1(b) * sgn1(c)
    let x = abs64(a)
    let y = abs64(b)
    let z = abs64(c)
    ret s * ((x * y + (z >> 1u32)) / z)
}

// The x-direction product GDI takes: the half-divisor is added before the sign is read.
fn muldiv_ms(a: i64, b: i64, c: i64) -> i64 {
    if c == 16384i64 && b == 16384i64 { ret a }
    var n = a * b
    var sc = 1i64
    var d = c
    if d < 0i64 {
        sc = -1i64
        d = 0i64 - d
    }
    if d == 0i64 { ret 2147483647i64 }
    n = n + (d >> 1u32)
    var q = abs64(n) / d
    if n < 0i64 { q = 0i64 - q }
    ret sc * q
}

// The interpolation product of IUP along x: as `muldiv_ms`, without its shortcut or its zero guard.
fn muldiv_x(a: i64, b: i64, c: i64) -> i64 {
    var n = a * b
    var sc = 1i64
    var d = c
    if d < 0i64 {
        sc = -1i64
        d = 0i64 - d
    }
    n = n + (d >> 1u32)
    var q = abs64(n) / d
    if n < 0i64 { q = 0i64 - q }
    ret sc * q
}

fn muldiv_nr(a: i64, b: i64, c: i64) -> i64 {
    if c == 0i64 { ret 2147483647i64 }
    let s = sgn1(a) * sgn1(b) * sgn1(c)
    ret s * ((abs64(a) * abs64(b)) / abs64(c))
}

fn mulfix14(a: i64, b: i64) -> i64 {
    let s = sgn1(a) * sgn1(b)
    ret s * ((abs64(a) * abs64(b) + 8192i64) >> 14u32)
}

fn pix_round(x: i64) -> i64 { ret (x + 32i64) & (0i64 - 64i64) }
fn pix_floor(x: i64) -> i64 { ret x & (0i64 - 64i64) }
fn pix_ceil(x: i64) -> i64 { ret (x + 63i64) & (0i64 - 64i64) }

// The gasp flags of the first range that reaches `ppem` (0 without a table).
fn gasp_flags(h: *Hinter, ppem: i64) -> i64 {
    var r = 0usize
    while r < h.gasp_ranges {
        if ppem <= rd16(h.data, h.gasp_at + 4usize * r) { ret rd16(h.data, h.gasp_at + 4usize * r + 2usize) }
        r += 1usize
    }
    ret 0i64
}

// The hdmx advance of `gid` at `ppem` in whole pixels, if the table has the size.
fn hdmx_width(h: *Hinter, ppem: i64, gid: usize) -> (i64, bool) {
    var r = 0usize
    while r < h.hdmx_records {
        let at = h.hdmx_at + r * h.hdmx_record_size
        if i64(h.data[at]) == ppem && gid < h.glyph_count { ret (i64(h.data[at + 2usize + gid]), true) }
        r += 1usize
    }
    ret (0i64, false)
}

fn rd16(d: []const u8, at: usize) -> i64 { ret i64(shape.u16_at(d, at)) }
fn rds16(d: []const u8, at: usize) -> i64 { ret i64(shape.i16_at(d, at)) }
fn rd32(d: []const u8, at: usize) -> i64 { ret i64(shape.u32_at(d, at)) }

fn zone_new(a: *mem.Arena, n: usize, nends: usize) -> (Zone, err) {
    var z: Zone = zero
    let (org, e1) = mem.alloc[i64](a, 2usize * n)
    if e1 != ok { ret (z, NoRoom) }
    let (cur, e2) = mem.alloc[i64](a, 2usize * n)
    if e2 != ok { ret (z, NoRoom) }
    let (orus, e3) = mem.alloc[i64](a, 2usize * n)
    if e3 != ok { ret (z, NoRoom) }
    let (tags, e4) = mem.alloc[i64](a, n)
    if e4 != ok { ret (z, NoRoom) }
    let (sh, e5) = mem.alloc[i64](a, n)
    if e5 != ok { ret (z, NoRoom) }
    let (ipd, e6) = mem.alloc[bool](a, n)
    if e6 != ok { ret (z, NoRoom) }
    let (mp, e8) = mem.alloc[i64](a, n)
    let (lpp, e9) = mem.alloc[i64](a, n)
    if e9 != ok { ret (z, NoRoom) }
    let (iprr, e10) = mem.alloc[i64](a, n)
    if e10 != ok { ret (z, NoRoom) }
    if e8 != ok { ret (z, NoRoom) }
    let (ends, e7) = mem.alloc[usize](a, nends)
    if e7 != ok { ret (z, NoRoom) }
    z.n = n
    z.org = org
    z.cur = cur
    z.orus = orus
    z.tags = tags
    z.sh = sh
    z.ipd = ipd
    z.mp = mp
    z.lp = lpp
    z.ipr = iprr
    z.ends = ends
    ret (z, ok)
}

fn zone_clear(z: *Zone, n: usize) {
    z.n = n
    z.nends = 0usize
    var i = 0usize
    while i < n {
        z.org[2usize * i] = 0i64
        z.org[2usize * i + 1usize] = 0i64
        z.cur[2usize * i] = 0i64
        z.cur[2usize * i + 1usize] = 0i64
        z.orus[2usize * i] = 0i64
        z.orus[2usize * i + 1usize] = 0i64
        z.tags[i] = 0i64
        z.sh[i] = 0i64
        z.ipd[i] = false
        z.mp[i] = 0i64
        z.lp[i] = 0i64
        z.ipr[i] = 0i64
        i += 1usize
    }
}

fn gs_default() -> Gs {
    ret Gs { rp0: 0i64, rp1: 0i64, rp2: 0i64, dual_x: 16384i64, dual_y: 0i64, proj_x: 16384i64, proj_y: 0i64, free_x: 16384i64, free_y: 0i64, lp: 1i64, min_dist: 64i64, round_state: 1i64, auto_flip: true, cvt_cut_in: 68i64, sw_cut_in: 0i64, sw_value: 0i64, delta_base: 9i64, delta_shift: 3i64, instruct_control: 0i64, scan_control: 0i64, scan_type: 0i64, gep0: 1usize, gep1: 1usize, gep2: 1usize }
}

// The hinter of a font: its tables found, its function table and zone storage allocated in `a`. `Unsupported` when the font has
// no `glyf`, `loca` or `hmtx`, or no instructions at all (an unhinted face is drawn by the caller as it was).
fn open(a: *mem.Arena, data: []const u8) -> (*Hinter, err) {
    let (hs, hs_error) = mem.alloc[Hinter](a, 1usize)
    if hs_error != ok { ret (zero, NoRoom) }
    let h = &hs[0usize]
    var blank: Hinter = zero
    *h = blank
    h.data = data
    let font = shape.Font { id: 0u32, data: data, face_index: 0u32 }
    let (head, has_head) = shape.find_table(font, shape.TAG_HEAD)
    let (maxp, has_maxp) = shape.find_table(font, shape.TAG_MAXP)
    let (hhea, has_hhea) = shape.find_table(font, shape.TAG_HHEA)
    let (hmtx, has_hmtx) = shape.find_table(font, shape.TAG_HMTX)
    let (glyf, has_glyf) = shape.find_table(font, TAG_GLYF)
    let (loca, has_loca) = shape.find_table(font, TAG_LOCA)
    if !has_head || !has_maxp || !has_hhea || !has_hmtx || !has_glyf || !has_loca { ret (zero, Unsupported) }
    if head.len < 54usize || maxp.len < 32usize || hhea.len < 36usize { ret (zero, Unsupported) }
    h.upem = rd16(data, head.at + 18usize)
    if h.upem == 0i64 { ret (zero, Unsupported) }
    h.long_loca = rd16(data, head.at + 50usize) != 0i64
    h.glyph_count = usize(rd16(data, maxp.at + 4usize))
    h.max_twilight = usize(rd16(data, maxp.at + 16usize))
    h.max_storage = usize(rd16(data, maxp.at + 18usize))
    h.max_fdefs = usize(rd16(data, maxp.at + 20usize))
    h.max_stack = usize(rd16(data, maxp.at + 24usize))
    h.glyf = glyf.at
    h.glyf_len = glyf.len
    h.loca = loca.at
    h.hmtx = hmtx.at
    h.hmetrics = usize(rd16(data, hhea.at + 34usize))
    let (cvt, has_cvt) = shape.find_table(font, TAG_CVT)
    if has_cvt {
        h.cvt_at = cvt.at
        h.cvt_count = cvt.len / 2usize
    }
    let (fpgm, has_fpgm) = shape.find_table(font, TAG_FPGM)
    let (prep, has_prep) = shape.find_table(font, TAG_PREP)
    if !has_fpgm && !has_prep { ret (zero, Unsupported) }
    if has_fpgm {
        h.fpgm_at = fpgm.at
        h.fpgm_len = fpgm.len
    }
    if has_prep {
        h.prep_at = prep.at
        h.prep_len = prep.len
    }
    // The device metrics: GDI takes a glyph's advance at the sizes this table lists from it, not from the hinted phantom point.
    let (hdmx, has_hdmx) = shape.find_table(font, TAG_HDMX)
    if has_hdmx && hdmx.len >= 8usize {
        h.hdmx_records = usize(rd16(data, hdmx.at + 2usize))
        h.hdmx_record_size = usize(rd32(data, hdmx.at + 4usize))
        if h.hdmx_record_size >= 2usize + h.glyph_count && 8usize + h.hdmx_records * h.hdmx_record_size <= hdmx.len {
            h.hdmx_at = hdmx.at + 8usize
        } else {
            h.hdmx_records = 0usize
        }
    }
    // The gasp table says at which sizes symmetric smoothing (six samples by five rows) is on.
    let (gasp, has_gasp) = shape.find_table(font, TAG_GASP)
    if has_gasp && gasp.len >= 4usize {
        h.gasp_ranges = usize(rd16(data, gasp.at + 2usize))
        if 4usize + 4usize * h.gasp_ranges <= gasp.len { h.gasp_at = gasp.at + 4usize } else { h.gasp_ranges = 0usize }
    }
    if h.max_storage > 4096usize || h.max_fdefs > 4096usize || h.max_twilight > 4096usize || h.max_stack > 8192usize { ret (zero, Unsupported) }
    let (lo, lo_error) = mem.alloc[usize](a, h.max_fdefs + 1usize)
    if lo_error != ok { ret (zero, NoRoom) }
    let (hi, hi_error) = mem.alloc[usize](a, h.max_fdefs + 1usize)
    if hi_error != ok { ret (zero, NoRoom) }
    var f = 0usize
    while f <= h.max_fdefs {
        lo[f] = 0usize
        hi[f] = 0usize
        f += 1usize
    }
    let (dk, dk_error) = mem.alloc[bool](a, h.max_fdefs + 1usize)
    if dk_error != ok { ret (zero, NoRoom) }
    f = 0usize
    while f <= h.max_fdefs {
        dk[f] = false
        f += 1usize
    }
    h.fdef_delta = dk
    let (bp, bp_error) = mem.alloc[i64](a, h.max_fdefs + 1usize)
    if bp_error != ok { ret (zero, NoRoom) }
    f = 0usize
    while f <= h.max_fdefs {
        bp[f] = -1i64
        f += 1usize
    }
    h.fdef_bypass = bp
    h.bypass = -1i64
    h.fdef_lo = lo
    h.fdef_hi = hi
    let (stack, stack_error) = mem.alloc[i64](a, h.max_stack + 96usize)
    if stack_error != ok { ret (zero, NoRoom) }
    h.stack = stack
    let (cvt_work, cvt_work_error) = mem.alloc[i64](a, h.cvt_count + 1usize)
    if cvt_work_error != ok { ret (zero, NoRoom) }
    h.cvt_work = cvt_work
    let (storage_work, storage_work_error) = mem.alloc[i64](a, h.max_storage + 1usize)
    if storage_work_error != ok { ret (zero, NoRoom) }
    h.storage_work = storage_work
    var l = 0usize
    while l < MAX_LEVEL {
        let (z, z_error) = zone_new(a, MAX_PTS + 4usize, MAX_ENDS)
        if z_error != ok { ret (zero, NoRoom) }
        h.zsets[l] = z
        l += 1usize
    }
    let (empty, empty_error) = zone_new(a, 1usize, 1usize)
    if empty_error != ok { ret (zero, NoRoom) }
    h.zone[1usize] = empty
    zone_clear(&h.zone[1usize], 0usize)
    ret (h, ok)
}

// ---------------------------------------------------------------- the machine

fn vm_push(h: *Hinter, v: i64) {
    if h.sp >= h.stack.len {
        h.fail = true
        ret
    }
    h.stack[h.sp] = v
    h.sp += 1usize
}

fn vm_pop(h: *Hinter) -> i64 {
    if h.sp == 0usize {
        h.fail = true
        ret 0i64
    }
    h.sp = h.sp - 1usize
    ret h.stack[h.sp]
}

// A point index off the zone sets the failure flag and answers false.
fn vm_pt(h: *Hinter, zi: usize, p: i64) -> bool {
    if p < 0i64 || p >= i64(h.zone[zi].n) {
        h.fail = true
        ret false
    }
    ret true
}

fn vm_is_x(h: *Hinter) -> bool {
    // The programs that set the size up (`fpgm`, `prep`) have no glyph zone and run as the black-and-white machine does: GDI's control
    // values come out of `prep` the same in ClearType (all 1297 of Segoe UI at 12 px), which they do not if x rounds to 1/16 pixel there.
    if h.zone[1usize].n == 0usize { ret false }
    ret h.cleartype && h.gs.free_x == 16384i64 && h.gs.free_y == 0i64
}

// Whether distances are rounded and limited on the 1/16 pixel grid of ClearType's x: in GDI that is every measure whose projection is
// not along y (a diagonal measured across rounds as finely as x does; found with synthetic fonts).
fn vm_grid_x(h: *Hinter) -> bool {
    if h.zone[1usize].n == 0usize { ret false }
    ret h.cleartype && !(h.gs.proj_x == 0i64 && h.gs.proj_y == 16384i64)
}

fn vm_ct_x(h: *Hinter) -> bool { ret vm_is_x(h) && h.gs.proj_x == 16384i64 }

fn vm_project(h: *Hinter, dx: i64, dy: i64) -> i64 {
    if h.gs.proj_x == 16384i64 { ret dx }
    if h.gs.proj_y == 16384i64 { ret dy }
    ret mulfix14(dx, h.gs.proj_x) + mulfix14(dy, h.gs.proj_y)
}

fn vm_dualproj(h: *Hinter, dx: i64, dy: i64) -> i64 {
    if h.gs.dual_x == 16384i64 { ret dx }
    if h.gs.dual_y == 16384i64 { ret dy }
    ret mulfix14(dx, h.gs.dual_x) + mulfix14(dy, h.gs.dual_y)
}

fn vm_fdotp(h: *Hinter) -> i64 {
    var v = 0i64
    if h.gs.free_x == 16384i64 {
        v = h.gs.proj_x
    } else if h.gs.free_y == 16384i64 {
        v = h.gs.proj_y
    } else {
        v = (h.gs.proj_x * h.gs.free_x + h.gs.proj_y * h.gs.free_y) >> 14u32
    }
    if abs64(v) < 1024i64 { v = 16384i64 }
    ret v
}

// Moves point `p` of zone `zi` by `dist` along the freedom vector. The right phantom point of a ClearType glyph never moves.
fn vm_move(h: *Hinter, zi: usize, p: usize, dist: i64) {
    let z = &h.zone[zi]
    if h.cleartype && zi == 1usize && p + 3usize == z.n { ret }
    let fx = h.gs.free_x
    let fy = h.gs.free_y
    if fx == h.gs.proj_x && fy == h.gs.proj_y && fx != 0i64 && fx != 16384i64 && fy != 0i64 && fy != 16384i64 {
        z.cur[2usize * p] = z.cur[2usize * p] + mulfix14(dist, fx)
        z.tags[p] = z.tags[p] | 8i64
        z.cur[2usize * p + 1usize] = z.cur[2usize * p + 1usize] + mulfix14(dist, fy)
        z.tags[p] = z.tags[p] | 16i64
        ret
    }
    let fdp = vm_fdotp(h)
    if fx != 0i64 {
        z.cur[2usize * p] = z.cur[2usize * p] + muldiv_ms(dist, fx, fdp)
        z.tags[p] = z.tags[p] | 8i64
    }
    if fy != 0i64 {
        z.cur[2usize * p + 1usize] = z.cur[2usize * p + 1usize] + muldiv(dist, fy, fdp)
        z.tags[p] = z.tags[p] | 16i64
    }
}

fn vm_move_orig(h: *Hinter, zi: usize, p: usize, dist: i64) {
    let z = &h.zone[zi]
    let fdp = vm_fdotp(h)
    if h.gs.free_x != 0i64 { z.org[2usize * p] = z.org[2usize * p] + muldiv_ms(dist, h.gs.free_x, fdp) }
    if h.gs.free_y != 0i64 { z.org[2usize * p + 1usize] = z.org[2usize * p + 1usize] + muldiv(dist, h.gs.free_y, fdp) }
}

fn vm_move_by(h: *Hinter, zi: usize, p: usize, dx: i64, dy: i64) {
    let z = &h.zone[zi]
    if h.cleartype && zi == 1usize && p + 3usize == z.n { ret }
    if h.gs.free_x != 0i64 {
        z.cur[2usize * p] = z.cur[2usize * p] + dx
        z.tags[p] = z.tags[p] | 8i64
    }
    if h.gs.free_y != 0i64 {
        z.cur[2usize * p + 1usize] = z.cur[2usize * p + 1usize] + dy
        z.tags[p] = z.tags[p] | 16i64
    }
}

fn vm_mind(h: *Hinter) -> i64 {
    if vm_grid_x(h) { ret h.gs.min_dist / 2i64 }
    ret h.gs.min_dist
}

fn vm_cutin(h: *Hinter) -> i64 {
    if vm_grid_x(h) { ret h.gs.cvt_cut_in / 16i64 }
    ret h.gs.cvt_cut_in
}

// Round `d` as the round state says, on a grid of 1/16 pixel along x in ClearType and a pixel otherwise.
fn vm_round(h: *Hinter, d: i64) -> i64 {
    let rs = h.gs.round_state
    var p = 64i64
    if vm_grid_x(h) { p = 4i64 }
    let half = p >> 1u32
    var m = d
    var neg = false
    if d < 0i64 {
        m = 0i64 - d
        neg = true
    }
    var v = 0i64
    if rs == 1i64 {
        v = ((m + half) / p) * p
    } else if rs == 0i64 {
        v = (m / p) * p + half
    } else if rs == 2i64 {
        let q = half
        v = ((m + (q >> 1u32)) / q) * q
    } else if rs == 3i64 {
        v = (m / p) * p
    } else if rs == 4i64 {
        v = ((m + p - 1i64) / p) * p
    } else if rs == 5i64 {
        v = m
    } else {
        var per = h.sr_per
        var phase = h.sr_phase
        var thr = h.sr_thr
        if p != 64i64 {
            per = per * p / 64i64
            if per < 1i64 { per = 1i64 }
            phase = phase * p / 64i64
            thr = thr * p / 64i64
        }
        if !neg {
            v = ((m - phase + thr) & (0i64 - per)) + phase
            if v < 0i64 { v = phase }
        } else {
            v = ((thr - phase + m) & (0i64 - per)) + phase
            if v < 0i64 { v = phase }
        }
    }
    if neg { ret 0i64 - v }
    ret v
}

fn vm_set_super(h: *Hinter, sel: i64) {
    h.gs.round_state = 6i64
    var per = 64i64
    let grid = sel & 192i64
    if grid == 0i64 { per = 32i64 }
    if grid == 128i64 { per = 128i64 }
    var phase = 0i64
    let ph = sel & 48i64
    if ph == 16i64 { phase = per / 4i64 }
    if ph == 32i64 { phase = per / 2i64 }
    if ph == 48i64 { phase = per * 3i64 / 4i64 }
    var thr = per - 1i64
    if (sel & 15i64) != 0i64 { thr = fdiv(((sel & 15i64) - 4i64) * per, 8i64) }
    h.sr_per = per
    h.sr_phase = phase
    h.sr_thr = thr
}

// Instruction length at `at`.
fn vm_len(h: *Hinter, at: usize) -> usize {
    let op = h.data[at]
    if op == 0x40u8 { ret 2usize + usize(h.data[at + 1usize]) }
    if op == 0x41u8 { ret 2usize + 2usize * usize(h.data[at + 1usize]) }
    if op >= 0xB0u8 && op <= 0xB7u8 { ret 2usize + usize(op - 0xB0u8) }
    if op >= 0xB8u8 && op <= 0xBFu8 { ret 3usize + 2usize * usize(op - 0xB8u8) }
    ret 1usize
}

// Skips to just past the EIF that closes the `if` being skipped (or the ELSE of it when `stop_else`), nested ifs passed over.
fn vm_skip_if(h: *Hinter, stop_else: bool) {
    var depth = 1usize
    while true {
        if h.ip >= h.code_hi {
            h.fail = true
            ret
        }
        let op = h.data[h.ip]
        h.ip += vm_len(h, h.ip)
        if op == 0x58u8 {
            depth += 1usize
        } else if op == 0x59u8 {
            depth = depth - 1usize
            if depth == 0usize { ret }
        } else if op == 0x1Bu8 && depth == 1usize && stop_else {
            ret
        }
    }
}

// Skips to just past the ENDF of the function being defined.
fn vm_skip_fdef(h: *Hinter) {
    var depth = 1usize
    while true {
        if h.ip >= h.code_hi {
            h.fail = true
            ret
        }
        let op = h.data[h.ip]
        h.ip += vm_len(h, h.ip)
        if op == 0x2Cu8 || op == 0x89u8 {
            depth += 1usize
        } else if op == 0x2Du8 {
            depth = depth - 1usize
            if depth == 0usize { ret }
        }
    }
}

fn vm_norm14(x: i64, y: i64) -> (i64, i64) {
    if x == 0i64 && y == 0i64 { ret (16384i64, 0i64) }
    let fx = f64(x)
    let fy = f64(y)
    let l = math.sqrt[f64](fx * fx + fy * fy)
    ret (i64(math.floor[f64](fx / l * 16384.0 + 0.5)), i64(math.floor[f64](fy / l * 16384.0 + 0.5)))
}

// The unit vector of the line between two points, `which` 0 the projection (and dual) vector, 1 the freedom vector.
fn vm_line_vec(h: *Hinter, perpendicular: bool, org: bool, p1: i64, p2: i64, which: i64) {
    let z1 = &h.zone[h.gs.gep1]
    let z2 = &h.zone[h.gs.gep2]
    if p1 < 0i64 || p2 < 0i64 || p2 >= i64(z1.n) || p1 >= i64(z2.n) {
        h.fail = true
        ret
    }
    var dx = 0i64
    var dy = 0i64
    if org {
        dx = z1.org[2usize * usize(p2)] - z2.org[2usize * usize(p1)]
        dy = z1.org[2usize * usize(p2) + 1usize] - z2.org[2usize * usize(p1) + 1usize]
    } else {
        dx = z1.cur[2usize * usize(p2)] - z2.cur[2usize * usize(p1)]
        dy = z1.cur[2usize * usize(p2) + 1usize] - z2.cur[2usize * usize(p1) + 1usize]
    }
    var perp = perpendicular
    if dx == 0i64 && dy == 0i64 {
        dx = 16384i64
        dy = 0i64
        perp = false
    }
    if perp {
        let t = dx
        dx = 0i64 - dy
        dy = t
    }
    let (nx, ny) = vm_norm14(dx, dy)
    if which == 0i64 {
        h.gs.proj_x = nx
        h.gs.proj_y = ny
        h.gs.dual_x = nx
        h.gs.dual_y = ny
    } else if which == 1i64 {
        h.gs.free_x = nx
        h.gs.free_y = ny
    } else if which == 2i64 {
        h.gs.dual_x = nx
        h.gs.dual_y = ny
    } else {
        h.gs.proj_x = nx
        h.gs.proj_y = ny
    }
}

fn vm_getinfo(h: *Hinter, sel: i64) -> i64 {
    var k = 0i64
    if (sel & 1i64) != 0i64 { k = 42i64 }
    if h.cleartype {
        if (sel & 64i64) != 0i64 { k = k | 8192i64 }
        if (sel & 128i64) != 0i64 { k = k | 16384i64 }
        if (sel & 8i64) != 0i64 { k = k | 1024i64 }
        if (sel & 16i64) != 0i64 { k = k | 2048i64 }
        // symmetrically smoothed ClearType (six samples by five rows): the font's gasp table switches it on
        if (sel & 2048i64) != 0i64 && (gasp_flags(h, h.ppem) & 8i64) != 0i64 { k = k | 262144i64 }
    }
    ret k
}

fn vm_iup_interp(h: *Hinter, ax: usize, p1: usize, p2: usize, r1: usize, r2: usize) {
    if p1 > p2 { ret }
    let z = &h.zone[1usize]
    var ref1 = r1
    var ref2 = r2
    var orus1 = z.orus[2usize * ref1 + ax]
    var orus2 = z.orus[2usize * ref2 + ax]
    if orus1 >= orus2 {
        let t = orus1
        orus1 = orus2
        orus2 = t
        let tr = ref1
        ref1 = ref2
        ref2 = tr
    }
    let org1 = z.org[2usize * ref1 + ax]
    let org2 = z.org[2usize * ref2 + ax]
    let cur1 = z.cur[2usize * ref1 + ax]
    let cur2 = z.cur[2usize * ref2 + ax]
    let delta1 = cur1 - org1
    let delta2 = cur2 - org2
    let flat = cur1 == cur2 || orus1 == orus2
    var i = p1
    while i <= p2 {
        var x = z.org[2usize * i + ax]
        if x <= org1 {
            x = x + delta1
        } else if x >= org2 {
            x = x + delta2
        } else if flat {
            x = cur1
        } else if ax == 0usize {
            x = cur1 + muldiv_x(z.orus[2usize * i + ax] - orus1, cur2 - cur1, orus2 - orus1)
        } else {
            x = cur1 + muldiv(z.orus[2usize * i + ax] - orus1, cur2 - cur1, orus2 - orus1)
        }
        z.cur[2usize * i + ax] = x
        i += 1usize
    }
}

// GDI's ClearType fits a glyph to its device advance when its x program reaches IUP[x]: A is the advance of the device table, X the
// advance as scaled, and every point an instruction placed carries a shift along x that IUP[x] adds. IP shifts a point by the shifts
// of its two references (the left phantom point none, the right one A - X) interpolated by where the unhinted point lies between them,
// cut towards zero. A stem (MIRP or MSIRP set a point against another that is not far above or below) moves with the point IP placed
// it against, or else, both points together, so that its centre lands at round(centre * A / X). A point MDRP, ALIGNRP or SHP placed
// against another takes that one's shift; points no instruction touched follow in IUP. Zone tags: bit 32 a point resolved, 64 one that
// carries a shift, 128 one that has one so far.
// The advance of the zone's own glyph as scaled, and the shift its right phantom point carries. A component's advance is not the top
// glyph's: the right phantom point of a component moves by (A - X) in proportion to the component's advance, round(own * (A - X) / X),
// and a point IP places against it is interpolated over the component's own span (found with composites of synthetic fonts).
fn ct_own(h: *Hinter, z: *Zone) -> i64 {
    if !h.ct_part { ret h.ctX }
    let own = z.org[2usize * (z.n - 3usize)] - z.org[2usize * (z.n - 4usize)]
    if own <= 0i64 { ret h.ctX }
    ret own
}

fn ct_pp2(h: *Hinter, z: *Zone) -> i64 {
    if !h.ct_part { ret h.ctA - h.ctX }
    let own = z.cur[2usize * (z.n - 3usize)] - z.cur[2usize * (z.n - 4usize)]
    ret fdiv(2i64 * own * (h.ctA - h.ctX) + h.ctX, 2i64 * h.ctX)
}

// A stem's shift: its centre times (A - X) / X, rounded with a tie going down (found with the ties in the oracle).
fn ct_centre_hd(h: *Hinter, c2: i64) -> i64 {
    let num = c2 * (h.ctA - h.ctX)
    let den = 2i64 * h.ctX
    ret 0i64 - fdiv(den - 2i64 * num, 2i64 * den)
}

fn ct_centre(h: *Hinter, c2: i64) -> i64 {
    let num = c2 * (h.ctA - h.ctX)
    let den = 2i64 * h.ctX
    ret fdiv(2i64 * num + den, 2i64 * den)
}

// A component is fitted as part of the glyph it belongs to: its offset is stretched by the same ratio.
fn ct_off_shift(h: *Hinter) -> i64 {
    if h.ctOff == 0i64 || h.ctX <= 0i64 { ret 0i64 }
    ret fdiv(2i64 * h.ctOff * (h.ctA - h.ctX) + h.ctX, 2i64 * h.ctX)
}

fn ct_live(z: *Zone, p: usize) -> bool { ret z.ipd[p] || z.mp[p] != 0i64 || (z.tags[p] & 128i64) != 0i64 }

fn ct_kind_msirp(h: *Hinter) -> i64 {
    if !vm_is_x(h) { ret 0i64 }
    ret 3i64
}

fn ct_kind_mirp(h: *Hinter, flags: i64) -> i64 {
    if !vm_is_x(h) { ret 0i64 }
    if (flags & 3i64) == 1i64 { ret 1i64 }
    ret 2i64
}

// Whether points `a` and `b` follow each other on one contour of the zone.
fn ct_adjacent(z: *Zone, a: usize, b: usize) -> bool {
    var first = 0usize
    var c = 0usize
    while c < z.nends {
        let last = z.ends[c]
        if a >= first && a <= last {
            if b < first || b > last { ret false }
            if a + 1usize == b || b + 1usize == a { ret true }
            ret (a == first && b == last) || (b == first && a == last)
        }
        first = last + 1usize
        c += 1usize
    }
    ret false
}

// Whether point `from` is, through the points that were set against each other, a follower of `to`.
fn ct_follows(z: *Zone, from: usize, to: usize) -> bool {
    let npt = z.n - 4usize
    var q = from
    var steps = 0usize
    while steps <= npt {
        if q == to { ret true }
        let m = z.mp[q]
        if m <= 0i64 || z.ipd[q] || usize(m - 1i64) >= npt { ret false }
        q = usize(m - 1i64)
        steps += 1usize
    }
    ret false
}

// A follower an instruction sets against another along the freedom vector y but with a projection that has some x in it (a diagonal stem
// measured across, say) still takes its reference's shift when it had none: GDI notes the relation whatever the freedom vector.
fn ct_derive_y(h: *Hinter, p: usize, r: usize) {
    if h.zone[1usize].n == 0usize || h.ctA == 0i64 { ret }
    if h.gs.proj_x == 0i64 && h.gs.proj_y == 16384i64 { ret }
    let z = &h.zone[1usize]
    if p + 4usize > z.n { ret }
    var q = 0usize
    while q + 4usize < z.n {
        if z.mp[q] == i64(p) + 1i64 && !z.ipd[q] {
            h.ct_cyc = true
            break
        }
        q += 1usize
    }
    if ct_live(z, p) && !ct_follows(z, r, p) { ret }
    ct_derive(h, p, r, 0i64)
}

// MIRP and MSIRP (a pair) and MDRP, ALIGNRP and SHP (a point that follows) note which point they set against and give the point the
// shift its reference has now; a pair is settled by IUP[x] once the points are where the program leaves them.
// `kind`: 0 a follower (MDRP, ALIGNRP, SHP), 1 MIRP of distance type 01, 2 MIRP of another type, 3 MSIRP. Two points make a stem when they are
// not neighbours on the contour and the MIRP is of type 01 (or an MSIRP), or when they are neighbours and the contour edge between them is flat
// (a stem's top or bottom, not steeper than two to one); neighbours on a steep edge measure a height, not a width (found with synthetic
// fonts of random polygons).
fn ct_derive(h: *Hinter, p: usize, r: usize, kind: i64) {
    if h.ct_stop { ret }
    let z = &h.zone[1usize]
    let npt = z.n - 4usize
    if p >= npt || r >= z.n { ret }
    var plain = r + 4usize == z.n
    var is_pair = false
    if kind != 0i64 && r < npt {
        let adj = ct_adjacent(z, p, r)
        let flat = abs64(z.org[2usize * p + 1usize] - z.org[2usize * r + 1usize]) <= 2i64 * abs64(z.org[2usize * p] - z.org[2usize * r])
        if adj {
            is_pair = flat
        } else {
            is_pair = kind != 2i64
        }
    }
    if trace_on {
        let e13 = io.printf["ct_derive p {} r {} kind {} pair {} plain {} mp {} live {}\n"](p, r, kind, is_pair, plain, z.mp[p], ct_live(z, p))
    }
    if plain {
        z.mp[p] = 0i64
        z.sh[p] = 0i64
        z.tags[p] = z.tags[p] & (0i64 - 129i64)
        ret
    }
    if kind == 0i64 && !vm_ct_x(h) && z.mp[p] == 0i64 && !z.ipd[p] {
        z.tags[p] = z.tags[p] | 2048i64
        ret
    }
    // The first point a point is set against is the one it follows; a later instruction setting it against another changes nothing, but one
    // that would make its reference follow it in turn (a circle) tells GDI to fit the whole glyph by another rule (ct_cycles).
    if !is_pair && r < npt {
        if r != p && ct_follows(z, r, p) {
            h.ct_cyc = true
            ret
        }
        if z.mp[p] > 0i64 && !z.ipd[p] { ret }
    }
    if r + 3usize == z.n && z.mp[p] > 0i64 && !z.ipd[p] { ret }
    z.tags[p] = z.tags[p] | 128i64
    if r + 3usize == z.n {
        z.mp[p] = i64(r) + 1i64
        z.sh[p] = ct_pp2(h, z)
        ret
    }
    if r >= npt { ret }
    if !is_pair {
        z.mp[p] = i64(r) + 1i64
        z.sh[p] = 0i64
        if ct_live(z, r) { z.sh[p] = z.sh[r] }
        ret
    }
    if z.ipd[p] && z.ipd[r] { z.ipd[p] = false }
    z.mp[p] = 0i64 - (i64(r) + 1i64)
    z.lp[r] = i64(p) + 1i64
    if z.ipd[r] || z.mp[r] < 0i64 {
        z.sh[p] = z.sh[r]
        ret
    }
    let d = ct_centre_hd(h, z.cur[2usize * r] + z.cur[2usize * p])
    z.sh[p] = d
    z.sh[r] = d
    z.tags[r] = z.tags[r] | 128i64
}

fn ct_ip_shift(h: *Hinter, r1: usize, r2: usize, p: usize, lazy: bool) -> i64 {
    let z = &h.zone[1usize]
    let n = z.n
    var o1 = z.org[2usize * r1]
    var o2 = z.org[2usize * r2]
    let op = z.org[2usize * p]
    var s1 = 0i64
    var s2 = 0i64
    if r1 + 3usize == n {
        o1 = ct_own(h, z)
        s1 = ct_pp2(h, z)
    } else if r1 + 4usize != n && (lazy || ct_live(z, r1)) {
        s1 = z.sh[r1]
    }
    if r2 + 3usize == n {
        o2 = ct_own(h, z)
        s2 = ct_pp2(h, z)
    } else if r2 + 4usize != n && (lazy || ct_live(z, r2)) {
        s2 = z.sh[r2]
    }
    if o2 == o1 { ret s1 }
    ret (s1 * (o2 - op) + s2 * (op - o1)) / (o2 - o1)
}

fn ct_resolve(h: *Hinter, p: usize, depth: usize) {
    let z = &h.zone[1usize]
    if (z.tags[p] & 32i64) != 0i64 || depth > 64usize { ret }
    z.tags[p] = z.tags[p] | 32i64
    if z.ipd[p] {
        z.tags[p] = z.tags[p] | 64i64
        ret
    }
    let m = z.mp[p]
    if m == 0i64 { ret }
    var rr = m - 1i64
    if m < 0i64 { rr = 0i64 - m - 1i64 }
    if rr >= i64(z.n) { ret }
    let r = usize(rr)
    if r + 4usize == z.n {
        z.sh[p] = 0i64
        ret
    }
    if r + 3usize == z.n {
        z.sh[p] = ct_pp2(h, z)
        z.tags[p] = z.tags[p] | 64i64
        ret
    }
    ct_resolve(h, r, depth + 1usize)
    if m < 0i64 && !z.ipd[r] && z.mp[r] >= 0i64 && z.lp[r] > 0i64 && usize(z.lp[r] - 1i64) != p {
        // an earlier mate of a point that a later pair has taken: it keeps the shift of that pair
        ct_resolve(h, usize(z.lp[r] - 1i64), depth + 1usize)
        z.sh[p] = z.sh[r]
        z.tags[p] = z.tags[p] | 64i64
        ret
    }
    if m > 0i64 || z.ipd[r] || z.mp[r] < 0i64 {
        z.sh[p] = z.sh[r]
        if (z.tags[r] & 64i64) != 0i64 { z.tags[p] = z.tags[p] | 64i64 }
        ret
    }
    let d = ct_centre_hd(h, z.cur[2usize * r] + z.cur[2usize * p])
    z.sh[p] = d
    z.sh[r] = d
    z.tags[p] = z.tags[p] | 64i64
    z.tags[r] = z.tags[r] | 64i64
}

// A glyph in which an instruction tried to set a point against one that follows it (a diagonal measured across, say) is fitted by another
// rule, found with synthetic fonts: every point that follows another moves by its own share, round(x * (A - X) / X) at the x it has,
// and only the points no instruction set against another keep their shift of nought.
fn ct_cycles(h: *Hinter) {
    if !h.ct_cyc { ret }
    let z = &h.zone[1usize]
    let npt = z.n - 4usize
    var p = 0usize
    while p < npt {
        if z.mp[p] > 0i64 && !z.ipd[p] && z.lp[p] == 0i64 && usize(z.mp[p] - 1i64) < npt {
            let r = usize(z.mp[p] - 1i64)
            let on_stem = z.lp[r] > 0i64 || z.mp[r] < 0i64
            if !on_stem || (z.tags[p] & 1024i64) != 0i64 { z.sh[p] = ct_centre(h, 2i64 * z.cur[2usize * p]) }
        }
        p += 1usize
    }
}

// A point only a diagonal measure moved along x (the projection not along x) is fitted like a point nobody touched: by the shifts of the
// nearest points on its contour that were placed along x, interpolated by where the unhinted point lies between them.
fn ct_soft(h: *Hinter) {
    let z = &h.zone[1usize]
    let npt = z.n - 4usize
    var p = 0usize
    while p < npt {
        if (z.tags[p] & 2048i64) != 0i64 && z.mp[p] == 0i64 && !z.ipd[p] {
            var first = 0usize
            var last = npt - 1usize
            var c = 0usize
            while c < z.nends {
                if p <= z.ends[c] {
                    last = z.ends[c]
                    break
                }
                first = z.ends[c] + 1usize
                c += 1usize
            }
            var span = last - first + 1usize
            var plain = false
            var w0 = first
            while w0 <= last {
                if (z.tags[w0] & 8i64) != 0i64 && (z.tags[w0] & 2048i64) == 0i64 && !z.ipd[w0] { plain = true }
                w0 += 1usize
            }
            var q = p
            var back = 0usize
            var r1 = npt
            while back < span {
                if q == first { q = last } else { q = q - 1usize }
                back += 1usize
                if (z.tags[q] & 8i64) != 0i64 && (z.tags[q] & 2048i64) == 0i64 && !(plain && z.ipd[q]) {
                    r1 = q
                    break
                }
            }
            q = p
            var fwd = 0usize
            var r2 = npt
            while fwd < span {
                if q == last { q = first } else { q = q + 1usize }
                fwd += 1usize
                if (z.tags[q] & 8i64) != 0i64 && (z.tags[q] & 2048i64) == 0i64 && !(plain && z.ipd[q]) {
                    r2 = q
                    break
                }
            }
            if r1 < npt && r2 < npt {
                var o1 = z.orus[2usize * r1]
                var o2 = z.orus[2usize * r2]
                var s1 = z.sh[r1]
                var s2 = z.sh[r2]
                if o1 > o2 {
                    let to = o1
                    o1 = o2
                    o2 = to
                    let ts = s1
                    s1 = s2
                    s2 = ts
                }
                let op = z.orus[2usize * p]
                if op <= o1 {
                    z.sh[p] = s1
                } else if op >= o2 {
                    z.sh[p] = s2
                } else {
                    z.sh[p] = (s1 * (o2 - op) + s2 * (op - o1)) / (o2 - o1)
                }
            }
        }
        p += 1usize
    }
}

// What IUP[x] of a ClearType glyph does first: the shifts settle and the points that carry one move.
fn ct_scale(h: *Hinter) {
    let z = &h.zone[1usize]
    let npt = z.n - 4usize
    var p = 0usize
    while p < npt {
        z.tags[p] = z.tags[p] & (0i64 - 225i64)
        p += 1usize
    }
    p = 0usize
    while p < npt {
        ct_resolve(h, p, 0usize)
        p += 1usize
    }
    var again = 0usize
    while again < 4usize {
        p = 0usize
        while p < npt {
            if z.ipd[p] {
                z.sh[p] = ct_ip_shift(h, usize(z.ipr[p] / 65536i64 - 1i64), usize(z.ipr[p] % 65536i64 - 1i64), p, true)
            }
            p += 1usize
        }
        p = 0usize
        while p < npt {
            if !z.ipd[p] { z.tags[p] = z.tags[p] & (0i64 - 225i64) }
            p += 1usize
        }
        p = 0usize
        while p < npt {
            ct_resolve(h, p, 0usize)
            p += 1usize
        }
        again += 1usize
    }
    // A point SHP, MDRP or ALIGNRP set against another follows that point's shift as it ends up. The resolution above reads the shift the
    // point has when it is visited, and a pair whose second point has the higher index changes its first point's shift after that.
    var pass = 0usize
    while pass < 4usize {
        p = 0usize
        while p < npt {
            if z.ipd[p] {
                z.sh[p] = ct_ip_shift(h, usize(z.ipr[p] / 65536i64 - 1i64), usize(z.ipr[p] % 65536i64 - 1i64), p, true)
            }
            p += 1usize
        }
        p = 0usize
        while p < npt {
            let m = z.mp[p]
            if m > 0i64 && !z.ipd[p] && z.lp[p] == 0i64 && usize(m - 1i64) < npt { z.sh[p] = z.sh[usize(m - 1i64)] }
            p += 1usize
        }
        pass += 1usize
    }
    ct_soft(h)
    ct_cycles(h)
    if trace_on {
        let e5 = io.printf["ct_scale ip {} n {} A {} X {} off {} part {}: "](h.ip, z.n, h.ctA, h.ctX, h.ctOff, h.ct_part)
        p = 0usize
        while p < npt {
            let e6 = io.printf["{}:{}{} "](p, z.sh[p], z.ipd[p])
            p += 1usize
        }
        let e7 = io.print("\n")
    }
    p = 0usize
    while p < npt {
        z.cur[2usize * p] = z.cur[2usize * p] + z.sh[p] + ct_off_shift(h)
        z.tags[p] = z.tags[p] & (0i64 - 225i64)
        z.ipd[p] = false
        z.mp[p] = 0i64
        z.sh[p] = 0i64
        p += 1usize
    }
}

fn vm_iup(h: *Hinter, x_axis: bool) {
    if !x_axis {
        h.iup_y = true
    }
    var ax = 1usize
    var mask = 16i64
    if x_axis {
        ax = 0usize
        mask = 8i64
        if h.cleartype && h.ctA != 0i64 && h.ctX > 0i64 && h.zone[1usize].n > 4usize {
            ct_scale(h)
            h.ct_done = true
        }
    }
    let z = &h.zone[1usize]
    var first = 0usize
    var c = 0usize
    while c < z.nends {
        let fp = first
        let lp = z.ends[c]
        var p = fp
        while p <= lp && (z.tags[p] & mask) == 0i64 { p += 1usize }
        if p > lp {
            first = lp + 1usize
            c += 1usize
            continue
        }
        let first_touched = p
        var cur_touched = p
        p += 1usize
        while p <= lp {
            if (z.tags[p] & mask) != 0i64 {
                vm_iup_interp(h, ax, cur_touched + 1usize, p - 1usize, cur_touched, p)
                cur_touched = p
            }
            p += 1usize
        }
        if cur_touched == first_touched {
            let d = z.cur[2usize * cur_touched + ax] - z.org[2usize * cur_touched + ax]
            if d != 0i64 {
                var q = fp
                while q <= lp {
                    if q != cur_touched { z.cur[2usize * q + ax] = z.cur[2usize * q + ax] + d }
                    q += 1usize
                }
            }
        } else {
            vm_iup_interp(h, ax, cur_touched + 1usize, lp, cur_touched, first_touched)
            if first_touched > fp { vm_iup_interp(h, ax, fp, first_touched - 1usize, cur_touched, first_touched) }
        }
        first = lp + 1usize
        c += 1usize
    }
}

// The displacement SHP, SHC and SHZ apply: how far the reference point has moved, as a vector along the freedom vector.
fn vm_shift_vec(h: *Hinter, one: bool) -> (i64, i64, usize, usize) {
    var zi = h.gs.gep1
    var rp = h.gs.rp2
    if one {
        zi = h.gs.gep0
        rp = h.gs.rp1
    }
    if !vm_pt(h, zi, rp) { ret (0i64, 0i64, zi, 0usize) }
    let z = &h.zone[zi]
    let r = usize(rp)
    let d = vm_project(h, z.cur[2usize * r] - z.org[2usize * r], z.cur[2usize * r + 1usize] - z.org[2usize * r + 1usize])
    let fdp = vm_fdotp(h)
    ret (muldiv(d, h.gs.free_x, fdp), muldiv(d, h.gs.free_y, fdp), zi, r)
}

fn vm_shp(h: *Hinter, one: bool) {
    let (dx, dy, rzi, rr) = vm_shift_vec(h, one)
    let zi = h.gs.gep2
    var k = 0i64
    while k < h.gs.lp {
        let p = vm_pop(h)
        if h.fail { ret }
        if vm_pt(h, zi, p) {
            vm_move_by(h, zi, usize(p), dx, dy)
            if vm_is_x(h) && zi == 1usize && rzi == 1usize && h.ctA != 0i64 {
                ct_derive(h, usize(p), rr, 0i64)
                if h.zone[1usize].mp[usize(p)] == i64(rr) + 1i64 { h.zone[1usize].tags[usize(p)] = h.zone[1usize].tags[usize(p)] | 1024i64 }
            } else if zi == 1usize && rzi == 1usize {
                ct_derive_y(h, usize(p), rr)
            }
        }
        k += 1i64
    }
    h.gs.lp = 1i64
}

// SHC ends the advance fitting for the rest of the glyph program: what was fitted before it stays, what comes after it is not (found by
// probing GDI with synthetic programs; SHZ does not do this).
fn vm_shc(h: *Hinter, one: bool) {
    let c = vm_pop(h)
    let (dx, dy, rzi, rp) = vm_shift_vec(h, one)
    if h.fail { ret }
    let zi = h.gs.gep2
    let z = &h.zone[zi]
    var s = 0usize
    var e = z.n
    if zi != 0usize {
        if c < 0i64 || usize(c) >= z.nends {
            h.fail = true
            ret
        }
        if c > 0i64 { s = z.ends[usize(c) - 1usize] + 1usize }
        e = z.ends[usize(c)] + 1usize
    }
    var p = s
    while p < e {
        if !(zi == rzi && p == rp) {
            vm_move_by(h, zi, p, dx, dy)
            if vm_is_x(h) && zi == 1usize && rzi == 1usize && h.ctA != 0i64 && p + 4usize <= z.n {
                ct_derive(h, p, rp, 0i64)
            } else if zi == 1usize && rzi == 1usize && p + 4usize <= z.n {
                ct_derive_y(h, p, rp)
            }
        }
        p += 1usize
    }
    h.ct_stop = true
}

fn vm_shz(h: *Hinter, one: bool) {
    let e = vm_pop(h)
    let (dx, dy, rzi, rp) = vm_shift_vec(h, one)
    if h.fail { ret }
    let zi = h.gs.gep2
    let z = &h.zone[zi]
    var n = z.n
    if zi != 0usize { n = z.n - 4usize }
    var p = 0usize
    while p < n {
        if !(zi == rzi && p == rp) {
            if h.gs.free_x != 0i64 { z.cur[2usize * p] = z.cur[2usize * p] + dx }
            if h.gs.free_y != 0i64 { z.cur[2usize * p + 1usize] = z.cur[2usize * p + 1usize] + dy }
        }
        p += 1usize
    }
}

fn vm_shpix(h: *Hinter) {
    let d = vm_pop(h)
    let dx = mulfix14(d, h.gs.free_x)
    let dy = mulfix14(d, h.gs.free_y)
    let zi = h.gs.gep2
    var k = 0i64
    while k < h.gs.lp {
        let p = vm_pop(h)
        if h.fail { ret }
        var blocked = false
        if h.cleartype && h.gs.free_y == 0i64 && vm_pt(h, zi, p) {
            if h.in_delta || h.composite { blocked = true }
        }
        if h.cleartype && h.gs.free_x == 0i64 && h.in_delta && vm_pt(h, zi, p) && vm_delta_skipped(h, zi, usize(p)) { blocked = true }
        if !blocked && vm_pt(h, zi, p) { vm_move_by(h, zi, usize(p), dx, dy) }
        k += 1i64
    }
    h.gs.lp = 1i64
}

// IP: points between two reference points keep their place between them, measured on the font-unit outline. GDI's ClearType
// takes the same product, and marks the point as interpolated so a stem it later pairs with does not shift it again.
fn vm_ip(h: *Hinter) {
    let z0 = &h.zone[h.gs.gep0]
    let z1 = &h.zone[h.gs.gep1]
    let z2 = &h.zone[h.gs.gep2]
    let twilight = h.gs.gep0 == 0usize || h.gs.gep1 == 0usize || h.gs.gep2 == 0usize
    if !vm_pt(h, h.gs.gep0, h.gs.rp1) || !vm_pt(h, h.gs.gep1, h.gs.rp2) { ret }
    let r1 = usize(h.gs.rp1)
    let r2 = usize(h.gs.rp2)
    var old_range = 0i64
    if twilight {
        old_range = vm_dualproj(h, z1.org[2usize * r2] - z0.org[2usize * r1], z1.org[2usize * r2 + 1usize] - z0.org[2usize * r1 + 1usize])
    } else {
        old_range = vm_dualproj(h, z1.orus[2usize * r2] - z0.orus[2usize * r1], z1.orus[2usize * r2 + 1usize] - z0.orus[2usize * r1 + 1usize])
    }
    let cur_range = vm_project(h, z1.cur[2usize * r2] - z0.cur[2usize * r1], z1.cur[2usize * r2 + 1usize] - z0.cur[2usize * r1 + 1usize])
    var k = 0i64
    while k < h.gs.lp {
        let p = vm_pop(h)
        if h.fail { ret }
        if !vm_pt(h, h.gs.gep2, p) { ret }
        let pi = usize(p)
        var org_dist = 0i64
        if twilight {
            org_dist = vm_dualproj(h, z2.org[2usize * pi] - z0.org[2usize * r1], z2.org[2usize * pi + 1usize] - z0.org[2usize * r1 + 1usize])
        } else {
            org_dist = vm_dualproj(h, z2.orus[2usize * pi] - z0.orus[2usize * r1], z2.orus[2usize * pi + 1usize] - z0.orus[2usize * r1 + 1usize])
        }
        let cur_dist = vm_project(h, z2.cur[2usize * pi] - z0.cur[2usize * r1], z2.cur[2usize * pi + 1usize] - z0.cur[2usize * r1 + 1usize])
        var new_dist = 0i64
        if org_dist != 0i64 {
            if old_range != 0i64 {
                new_dist = muldiv(org_dist, cur_range, old_range)
            } else {
                new_dist = org_dist
            }
        }
        vm_move(h, h.gs.gep2, pi, new_dist - cur_dist)
        if vm_is_x(h) && h.ctA != 0i64 && !h.ct_stop && h.gs.gep0 == 1usize && h.gs.gep1 == 1usize && h.gs.gep2 == 1usize && pi + 4usize <= z2.n && r1 < z2.n && r2 < z2.n && !(z2.mp[pi] > 0i64 && !z2.ipd[pi]) {
            z2.sh[pi] = ct_ip_shift(h, r1, r2, pi, false)
            z2.ipr[pi] = (i64(r1) + 1i64) * 65536i64 + i64(r2) + 1i64
            z2.ipd[pi] = true
        }
        k += 1i64
    }
    h.gs.lp = 1i64
}

fn vm_msirp(h: *Hinter, set_rp0: bool) {
    let d = vm_pop(h)
    let p = vm_pop(h)
    if h.fail { ret }
    if !vm_pt(h, h.gs.gep1, p) || !vm_pt(h, h.gs.gep0, h.gs.rp0) { ret }
    let pi = usize(p)
    let r0 = usize(h.gs.rp0)
    let z1 = &h.zone[h.gs.gep1]
    let z0 = &h.zone[h.gs.gep0]
    if h.gs.gep1 == 0usize {
        z1.org[2usize * pi] = z0.org[2usize * r0]
        z1.org[2usize * pi + 1usize] = z0.org[2usize * r0 + 1usize]
        vm_move_orig(h, h.gs.gep1, pi, d)
        z1.cur[2usize * pi] = z1.org[2usize * pi]
        z1.cur[2usize * pi + 1usize] = z1.org[2usize * pi + 1usize]
    }
    let dist = vm_project(h, z1.cur[2usize * pi] - z0.cur[2usize * r0], z1.cur[2usize * pi + 1usize] - z0.cur[2usize * r0 + 1usize])
    vm_move(h, h.gs.gep1, pi, d - dist)
    if vm_is_x(h) && h.gs.gep0 == 1usize && h.gs.gep1 == 1usize && h.ctA != 0i64 { ct_derive(h, pi, r0, ct_kind_msirp(h)) }
    h.gs.rp1 = h.gs.rp0
    h.gs.rp2 = p
    if set_rp0 { h.gs.rp0 = p }
}

fn vm_alignrp(h: *Hinter) {
    if !vm_pt(h, h.gs.gep0, h.gs.rp0) { ret }
    let r0 = usize(h.gs.rp0)
    let z0 = &h.zone[h.gs.gep0]
    let z1 = &h.zone[h.gs.gep1]
    var k = 0i64
    while k < h.gs.lp {
        let p = vm_pop(h)
        if h.fail { ret }
        if !vm_pt(h, h.gs.gep1, p) { ret }
        let pi = usize(p)
        let d = vm_project(h, z1.cur[2usize * pi] - z0.cur[2usize * r0], z1.cur[2usize * pi + 1usize] - z0.cur[2usize * r0 + 1usize])
        vm_move(h, h.gs.gep1, pi, 0i64 - d)
        if vm_is_x(h) && h.gs.gep0 == 1usize && h.gs.gep1 == 1usize && h.ctA != 0i64 {
            ct_derive(h, pi, r0, 0i64)
        } else if h.gs.gep0 == 1usize && h.gs.gep1 == 1usize {
            ct_derive_y(h, pi, r0)
        }
        k += 1i64
    }
    h.gs.lp = 1i64
}

fn vm_miap(h: *Hinter, round: bool) {
    let ci = vm_pop(h)
    let p = vm_pop(h)
    if h.fail { ret }
    if ci < 0i64 || ci >= i64(h.cvt.len) || !vm_pt(h, h.gs.gep0, p) {
        h.fail = true
        ret
    }
    let pi = usize(p)
    let z = &h.zone[h.gs.gep0]
    var dist = h.cvt[usize(ci)]
    if h.gs.gep0 == 0usize {
        z.org[2usize * pi] = mulfix14(dist, h.gs.free_x)
        z.org[2usize * pi + 1usize] = mulfix14(dist, h.gs.free_y)
        z.cur[2usize * pi] = z.org[2usize * pi]
        z.cur[2usize * pi + 1usize] = z.org[2usize * pi + 1usize]
    }
    let org = vm_project(h, z.cur[2usize * pi], z.cur[2usize * pi + 1usize])
    if round {
        if abs64(dist - org) > vm_cutin(h) { dist = org }
        dist = vm_round(h, dist)
    }
    vm_move(h, h.gs.gep0, pi, dist - org)
    h.gs.rp0 = p
    h.gs.rp1 = p
}

fn vm_mdap(h: *Hinter, round: bool) {
    let p = vm_pop(h)
    if h.fail { ret }
    if !vm_pt(h, h.gs.gep0, p) { ret }
    let pi = usize(p)
    let z = &h.zone[h.gs.gep0]
    var d = 0i64
    if round {
        let cur = vm_project(h, z.cur[2usize * pi], z.cur[2usize * pi + 1usize])
        d = vm_round(h, cur) - cur
    }
    vm_move(h, h.gs.gep0, pi, d)
    h.gs.rp0 = p
    h.gs.rp1 = p
}

// Whether ClearType's backward compatible mode drops a delta (DELTAP, SHPIX) on point `p`: a delta along x is dropped, and in the
// other direction one on a point no instruction touched along y, because a delta there digs a dent in the outline where bilevel
// rendering meant to flip a pixel. A composite glyph keeps its deltas along y: they place the accents.
fn vm_delta_skipped(h: *Hinter, zi: usize, p: usize) -> bool {
    if !h.cleartype || h.zone[1usize].n == 0usize { ret false }
    if h.gs.free_x != 0i64 && h.gs.free_y == 0i64 { ret true }
    if h.composite { ret false }
    if h.iup_y { ret true }
    ret (h.zone[zi].tags[p] & 16i64) == 0i64
}

// The step of one DELTA argument: a 64th of a pixel shifted down by the delta shift.
fn vm_delta_unit(h: *Hinter) -> i64 {
    var s = 6i64 - h.gs.delta_shift
    if s < 0i64 || s > 6i64 { s = 0i64 }
    ret 1i64 << u32(s)
}

fn vm_deltap(h: *Hinter, k: i64) {
    let n = vm_pop(h)
    var i = 0i64
    while i < n {
        let p = vm_pop(h)
        let b = vm_pop(h)
        if h.fail { ret }
        var c = (b & 240i64) >> 4u32
        if k == 2i64 { c = c + 16i64 }
        if k == 3i64 { c = c + 32i64 }
        c = c + h.gs.delta_base
        if h.ppem == c {
            var amount = (b & 15i64) - 8i64
            if amount >= 0i64 { amount = amount + 1i64 }
            amount = amount * vm_delta_unit(h)
            if vm_pt(h, h.gs.gep0, p) && !vm_delta_skipped(h, h.gs.gep0, usize(p)) { vm_move(h, h.gs.gep0, usize(p), amount) }
        }
        i += 1i64
    }
}

fn vm_deltac(h: *Hinter, k: i64) {
    let n = vm_pop(h)
    var i = 0i64
    while i < n {
        let ci = vm_pop(h)
        let b = vm_pop(h)
        if h.fail { ret }
        var c = (b & 240i64) >> 4u32
        if k == 2i64 { c = c + 16i64 }
        if k == 3i64 { c = c + 32i64 }
        c = c + h.gs.delta_base
        if h.ppem == c {
            var amount = (b & 15i64) - 8i64
            if amount >= 0i64 { amount = amount + 1i64 }
            amount = amount * vm_delta_unit(h)
            if ci >= 0i64 && ci < i64(h.cvt.len) { h.cvt[usize(ci)] = h.cvt[usize(ci)] + amount }
        }
        i += 1i64
    }
}

fn vm_mdrp(h: *Hinter, flags: i64) {
    let p = vm_pop(h)
    if h.fail { ret }
    if !vm_pt(h, h.gs.gep1, p) || !vm_pt(h, h.gs.gep0, h.gs.rp0) { ret }
    let pi = usize(p)
    let r0 = usize(h.gs.rp0)
    let z0 = &h.zone[h.gs.gep0]
    let z1 = &h.zone[h.gs.gep1]
    var org_dist = 0i64
    if h.gs.gep0 == 0usize || h.gs.gep1 == 0usize {
        org_dist = vm_dualproj(h, z1.org[2usize * pi] - z0.org[2usize * r0], z1.org[2usize * pi + 1usize] - z0.org[2usize * r0 + 1usize])
    } else {
        org_dist = mulfix(vm_dualproj(h, z1.orus[2usize * pi] - z0.orus[2usize * r0], z1.orus[2usize * pi + 1usize] - z0.orus[2usize * r0 + 1usize]), h.xs)
    }
    if h.gs.sw_cut_in != 0i64 && abs64(org_dist - h.gs.sw_value) < h.gs.sw_cut_in {
        if org_dist >= 0i64 {
            org_dist = h.gs.sw_value
        } else {
            org_dist = 0i64 - h.gs.sw_value
        }
    }
    var dist = org_dist
    if (flags & 4i64) != 0i64 { dist = vm_round(h, org_dist) }
    if (flags & 8i64) != 0i64 {
        let md = vm_mind(h)
        if org_dist >= 0i64 {
            if dist < md { dist = md }
        } else if dist > 0i64 - md {
            dist = 0i64 - md
        }
    }
    let cur = vm_project(h, z1.cur[2usize * pi] - z0.cur[2usize * r0], z1.cur[2usize * pi + 1usize] - z0.cur[2usize * r0 + 1usize])
    vm_move(h, h.gs.gep1, pi, dist - cur)
    if vm_is_x(h) && h.gs.gep0 == 1usize && h.gs.gep1 == 1usize && h.ctA != 0i64 {
        ct_derive(h, pi, r0, 0i64)
    } else if h.gs.gep0 == 1usize && h.gs.gep1 == 1usize {
        ct_derive_y(h, pi, r0)
    }
    h.gs.rp1 = h.gs.rp0
    h.gs.rp2 = p
    if (flags & 16i64) != 0i64 { h.gs.rp0 = p }
}

// MIRP. In ClearType along x a stem set between two points that lie within two pixels of each other vertically and are
// no more than two pixels apart is shifted as a whole by the stem's centre times (hinted advance - unhinted advance) / unhinted
// advance, GDI's way of spreading the extra width of a rounded advance over the glyph without thickening a stem. The reference
// point of the next stem is taken without that shift, and a point IP has placed is not shifted.
fn vm_mirp(h: *Hinter, flags: i64) {
    let ci = vm_pop(h)
    let p = vm_pop(h)
    if h.fail { ret }
    if !vm_pt(h, h.gs.gep1, p) || !vm_pt(h, h.gs.gep0, h.gs.rp0) { ret }
    let pi = usize(p)
    let r0 = usize(h.gs.rp0)
    let z0 = &h.zone[h.gs.gep0]
    let z1 = &h.zone[h.gs.gep1]
    var cvt_dist = 0i64
    if ci != -1i64 {
        if ci < 0i64 || ci >= i64(h.cvt.len) {
            h.fail = true
            ret
        }
        cvt_dist = h.cvt[usize(ci)]
    }
    if h.gs.sw_cut_in != 0i64 && abs64(cvt_dist - h.gs.sw_value) < h.gs.sw_cut_in {
        if cvt_dist >= 0i64 {
            cvt_dist = h.gs.sw_value
        } else {
            cvt_dist = 0i64 - h.gs.sw_value
        }
    }
    if h.gs.gep1 == 0usize {
        z1.org[2usize * pi] = z0.org[2usize * r0] + mulfix14(cvt_dist, h.gs.free_x)
        z1.org[2usize * pi + 1usize] = z0.org[2usize * r0 + 1usize] + mulfix14(cvt_dist, h.gs.free_y)
        z1.cur[2usize * pi] = z1.org[2usize * pi]
        z1.cur[2usize * pi + 1usize] = z1.org[2usize * pi + 1usize]
    }
    let org_dist = vm_dualproj(h, z1.org[2usize * pi] - z0.org[2usize * r0], z1.org[2usize * pi + 1usize] - z0.org[2usize * r0 + 1usize])
    let rx = z0.cur[2usize * r0]
    let cur_dist = vm_project(h, z1.cur[2usize * pi] - rx, z1.cur[2usize * pi + 1usize] - z0.cur[2usize * r0 + 1usize])
    if h.gs.auto_flip && ((org_dist ^ cvt_dist) < 0i64) { cvt_dist = 0i64 - cvt_dist }
    if ((flags & 4i64) != 0i64 || (h.cleartype && h.zone[1usize].n != 0usize)) && h.gs.gep0 == h.gs.gep1 {
        if abs64(cvt_dist - org_dist) > vm_cutin(h) { cvt_dist = org_dist }
    }
    var dist = cvt_dist
    if (flags & 4i64) != 0i64 { dist = vm_round(h, cvt_dist) }
    if (flags & 8i64) != 0i64 {
        let md = vm_mind(h)
        if org_dist >= 0i64 {
            if dist < md { dist = md }
        } else if dist > 0i64 - md {
            dist = 0i64 - md
        }
    }
    vm_move(h, h.gs.gep1, pi, dist - cur_dist)
    if vm_is_x(h) && h.gs.gep0 == 1usize && h.gs.gep1 == 1usize && h.ctA != 0i64 {
        ct_derive(h, pi, r0, ct_kind_mirp(h, flags))
    } else if h.gs.gep0 == 1usize && h.gs.gep1 == 1usize {
        ct_derive_y(h, pi, r0)
    }
    h.gs.rp1 = h.gs.rp0
    if (flags & 16i64) != 0i64 { h.gs.rp0 = p }
    h.gs.rp2 = p
}

fn vm_isect(h: *Hinter) {
    let b1 = vm_pop(h)
    let b0 = vm_pop(h)
    let a1 = vm_pop(h)
    let a0 = vm_pop(h)
    let p = vm_pop(h)
    if h.fail { ret }
    if !vm_pt(h, h.gs.gep0, b0) || !vm_pt(h, h.gs.gep0, b1) || !vm_pt(h, h.gs.gep1, a0) || !vm_pt(h, h.gs.gep1, a1) || !vm_pt(h, h.gs.gep2, p) { ret }
    let z0 = &h.zone[h.gs.gep0]
    let z1 = &h.zone[h.gs.gep1]
    let zz = &h.zone[h.gs.gep2]
    let ib0 = 2usize * usize(b0)
    let ib1 = 2usize * usize(b1)
    let ia0 = 2usize * usize(a0)
    let ia1 = 2usize * usize(a1)
    let ip = 2usize * usize(p)
    let dbx = z0.cur[ib1] - z0.cur[ib0]
    let dby = z0.cur[ib1 + 1usize] - z0.cur[ib0 + 1usize]
    let dax = z1.cur[ia1] - z1.cur[ia0]
    let day = z1.cur[ia1 + 1usize] - z1.cur[ia0 + 1usize]
    let dx = z0.cur[ib0] - z1.cur[ia0]
    let dy = z0.cur[ib0 + 1usize] - z1.cur[ia0 + 1usize]
    zz.tags[usize(p)] = zz.tags[usize(p)] | 24i64
    let discriminant = muldiv(dax, 0i64 - dby, 64i64) + muldiv(day, dbx, 64i64)
    let dotproduct = muldiv(dax, dbx, 64i64) + muldiv(day, dby, 64i64)
    if 19i64 * abs64(discriminant) > abs64(dotproduct) {
        let val = muldiv(dx, 0i64 - dby, 64i64) + muldiv(dy, dbx, 64i64)
        zz.cur[ip] = z1.cur[ia0] + muldiv(val, dax, discriminant)
        zz.cur[ip + 1usize] = z1.cur[ia0 + 1usize] + muldiv(val, day, discriminant)
    } else {
        zz.cur[ip] = fdiv(z1.cur[ia0] + z1.cur[ia1] + z0.cur[ib0] + z0.cur[ib1], 4i64)
        zz.cur[ip + 1usize] = fdiv(z1.cur[ia0 + 1usize] + z1.cur[ia1 + 1usize] + z0.cur[ib0 + 1usize] + z0.cur[ib1 + 1usize], 4i64)
    }
}

fn vm_setzp(h: *Hinter, which: i64, v: i64) {
    if v != 0i64 && v != 1i64 {
        h.fail = true
        ret
    }
    if which == 0i64 { h.gs.gep0 = usize(v) }
    if which == 1i64 { h.gs.gep1 = usize(v) }
    if which == 2i64 { h.gs.gep2 = usize(v) }
}

fn vm_instctrl(h: *Hinter) {
    let sel = vm_pop(h)
    let val = vm_pop(h)
    if sel < 1i64 || sel > 3i64 { ret }
    let bit = 1i64 << u32(sel - 1i64)
    if val != 0i64 && val != bit { ret }
    h.gs.instruct_control = (h.gs.instruct_control & (0i64 - bit - 1i64)) | (val & bit)
}

// ClearType's compatibility code finds the functions that apply a delta (SHPIX at one ppem) by their first instructions:
// MPPEM GTEQ SWAP MPPEM LTEQ AND IF SHPIX ELSE POP POP EIF ENDF, or MPPEM EQ IF SHPIX ELSE POP POP EIF ENDF.
fn vm_is_delta_function(h: *Hinter, at: usize, end: usize) -> bool {
    let d = h.data
    if at + 9usize > end || d[at] != 0x4Bu8 { ret false }
    if d[at + 1usize] == 0x54u8 {
        ret d[at + 2usize] == 0x58u8 && d[at + 3usize] == 0x38u8 && d[at + 4usize] == 0x1Bu8 && d[at + 5usize] == 0x21u8 && d[at + 6usize] == 0x21u8 && d[at + 7usize] == 0x59u8 && d[at + 8usize] == 0x2Du8
    }
    ret at + 13usize <= end && d[at + 1usize] == 0x53u8 && d[at + 2usize] == 0x23u8 && d[at + 3usize] == 0x4Bu8 && d[at + 4usize] == 0x51u8 && d[at + 5usize] == 0x5Au8 && d[at + 6usize] == 0x58u8 && d[at + 7usize] == 0x38u8 && d[at + 8usize] == 0x1Bu8 && d[at + 9usize] == 0x21u8 && d[at + 10usize] == 0x21u8 && d[at + 11usize] == 0x59u8 && d[at + 12usize] == 0x2Du8
}

// ClearType bypasses the legacy TypeMan Talk spacing and stroke functions by making their storage switch read zero: a function that
// starts with `SVTCA[x] (RTG) PUSH 24 RS IF` (spacing) or `PUSH 22 RS IF` (DStroke and IStroke). The slot, or -1.
fn vm_bypass_slot(h: *Hinter, at: usize) -> i64 {
    if at + 7usize > h.data.len { ret -1i64 }
    let d = h.data
    var k = at
    if d[k] == 0x01u8 {
        k += 1usize
        if d[k] == 0x18u8 { k += 1usize }
        if d[k] == 0xB0u8 && d[k + 1usize] == 24u8 && d[k + 2usize] == 0x43u8 && d[k + 3usize] == 0x58u8 { ret 24i64 }
        ret -1i64
    }
    if d[k] == 0xB0u8 && d[k + 1usize] == 22u8 && d[k + 2usize] == 0x43u8 && d[k + 3usize] == 0x58u8 { ret 22i64 }
    ret -1i64
}

// Runs the function `f` `count` times.
fn vm_call(h: *Hinter, f: i64, count: i64) {
    if f < 0i64 || usize(f) > h.max_fdefs || h.fdef_hi[usize(f)] == 0usize {
        h.fail = true
        ret
    }
    if h.depth >= MAX_CALL {
        h.fail = true
        ret
    }
    h.depth += 1usize
    let lo = h.fdef_lo[usize(f)]
    let hi = h.fdef_hi[usize(f)]
    let saved_delta = h.in_delta
    let saved_bypass = h.bypass
    if h.fdef_delta[usize(f)] { h.in_delta = true }
    if h.cleartype && h.zone[1usize].n != 0usize && h.fdef_bypass[usize(f)] >= 0i64 { h.bypass = h.fdef_bypass[usize(f)] }
    var k = 0i64
    while k < count {
        let saved_lo = h.code_lo
        let saved_hi = h.code_hi
        let saved_ip = h.ip
        h.code_lo = lo
        h.code_hi = hi
        h.ip = lo
        while h.ip < hi && !h.fail {
            vm_step(h)
            h.steps += 1usize
            if h.steps > MAX_STEPS { h.fail = true }
        }
        h.code_lo = saved_lo
        h.code_hi = saved_hi
        h.ip = saved_ip
        if h.fail { break }
        k += 1i64
    }
    h.in_delta = saved_delta
    h.bypass = saved_bypass
    h.depth = h.depth - 1usize
}

fn vm_jump(h: *Hinter, off: i64, at: usize) {
    if off == 0i64 {
        h.fail = true
        ret
    }
    let to = i64(at) + off
    if to < i64(h.code_lo) || to > i64(h.code_hi) {
        h.fail = true
        ret
    }
    h.ip = usize(to)
}

// ENDIF and NROUND change nothing here.
fn vm_noop(h: *Hinter) {
    h.fail = h.fail
}

fn vm_bool(b: bool) -> i64 {
    if b { ret 1i64 }
    ret 0i64
}

// Tracing of a glyph program (a development aid: set from `ttglyph.set_trace`): every step prints its offset, opcode, the top of the
// stack, the reference points, the vectors and the round state, and the points of the glyph zone it moved.
var cut_ops: i64 = zero

fn set_cut(n: i64) { cut_ops = n }

var cut_iup: bool = zero

fn set_cut_iup(b: bool) { cut_iup = b }

// The probe cuts only the program of the glyph asked for, not those of its components.
var cut_here: bool = zero

fn set_cut_here(b: bool) { cut_here = b }

var trace_on: bool = zero
var trace_before: [800]i64 = zero

fn set_trace(on: bool) { trace_on = on }

fn vm_step(h: *Hinter) {
    if !trace_on {
        vm_step_run(h)
        ret
    }
    let at = h.ip
    let z = &h.zone[1usize]
    var n = z.n
    if n > 400usize { n = 400usize }
    var i = 0usize
    while i < 2usize * n {
        trace_before[i] = z.cur[i]
        i += 1usize
    }
    let sp0 = h.sp
    var t0 = 0i64
    var t1 = 0i64
    var t2 = 0i64
    if sp0 >= 1usize { t0 = h.stack[sp0 - 1usize] }
    if sp0 >= 2usize { t1 = h.stack[sp0 - 2usize] }
    if sp0 >= 3usize { t2 = h.stack[sp0 - 3usize] }
    let opc = i64(h.data[at])
    vm_step_run(h)
    try_trace_print(h, at, opc, sp0, t0, t1, t2, n)
}

fn try_trace_print(h: *Hinter, at: usize, opc: i64, sp0: usize, t0: i64, t1: i64, t2: i64, n: usize) {
    let z = &h.zone[1usize]
    let e1 = io.printf["{} op {} sp {} top {} {} {} | rp {} {} {} gep {} {} {} pv {} {} fv {} {} rs {} md {}"](at, opc, sp0, t0, t1, t2, h.gs.rp0, h.gs.rp1, h.gs.rp2, h.gs.gep0, h.gs.gep1, h.gs.gep2, h.gs.proj_x, h.gs.proj_y, h.gs.free_x, h.gs.free_y, h.gs.round_state, h.gs.min_dist)
    if (opc >= 0xE0i64 || opc == 0x3Ei64 || opc == 0x3Fi64 || opc == 0x45i64) && t0 >= 0i64 && t0 < i64(h.cvt.len) {
        let e4 = io.printf[" | cvt[{}]={}"](t0, h.cvt[usize(t0)])
    }
    var i = 0usize
    while i < n {
        if z.cur[2usize * i] != trace_before[2usize * i] || z.cur[2usize * i + 1usize] != trace_before[2usize * i + 1usize] {
            let e2 = io.printf[" | p{} {},{}->{},{}"](i, trace_before[2usize * i], trace_before[2usize * i + 1usize], z.cur[2usize * i], z.cur[2usize * i + 1usize])
        }
        i += 1usize
    }
    let e3 = io.print("\n")
}

fn vm_step_run(h: *Hinter) {
    let at = h.ip
    if at + 3usize >= h.data.len {
        h.fail = true
        ret
    }
    let op = i64(h.data[at])
    let n = vm_len(h, at)
    h.ip = at + n
    if op == 0x40i64 {
        var c = 0usize
        while c < usize(h.data[at + 1usize]) {
            vm_push(h, i64(h.data[at + 2usize + c]))
            c += 1usize
        }
        ret
    }
    if op == 0x41i64 {
        var c = 0usize
        while c < usize(h.data[at + 1usize]) {
            vm_push(h, rds16(h.data, at + 2usize + 2usize * c))
            c += 1usize
        }
        ret
    }
    if op >= 0xB0i64 && op <= 0xB7i64 {
        var c = 0usize
        while c <= usize(op - 0xB0i64) {
            vm_push(h, i64(h.data[at + 1usize + c]))
            c += 1usize
        }
        ret
    }
    if op >= 0xB8i64 && op <= 0xBFi64 {
        var c = 0usize
        while c <= usize(op - 0xB8i64) {
            vm_push(h, rds16(h.data, at + 1usize + 2usize * c))
            c += 1usize
        }
        ret
    }
    if op >= 0xC0i64 && op <= 0xDFi64 {
        vm_mdrp(h, op - 0xC0i64)
        ret
    }
    if op >= 0xE0i64 && op <= 0xFFi64 {
        vm_mirp(h, op - 0xE0i64)
        ret
    }
    let a = op & 1i64
    switch op {
    case 0x00, 0x01:
        if a == 0i64 {
            h.gs.proj_x = 0i64
            h.gs.proj_y = 16384i64
        } else {
            h.gs.proj_x = 16384i64
            h.gs.proj_y = 0i64
        }
        h.gs.dual_x = h.gs.proj_x
        h.gs.dual_y = h.gs.proj_y
        h.gs.free_x = h.gs.proj_x
        h.gs.free_y = h.gs.proj_y
    case 0x02, 0x03:
        if a == 0i64 {
            h.gs.proj_x = 0i64
            h.gs.proj_y = 16384i64
        } else {
            h.gs.proj_x = 16384i64
            h.gs.proj_y = 0i64
        }
        h.gs.dual_x = h.gs.proj_x
        h.gs.dual_y = h.gs.proj_y
    case 0x04, 0x05:
        if a == 0i64 {
            h.gs.free_x = 0i64
            h.gs.free_y = 16384i64
        } else {
            h.gs.free_x = 16384i64
            h.gs.free_y = 0i64
        }
    case 0x06, 0x07:
        let p1 = vm_pop(h)
        let p2 = vm_pop(h)
        vm_line_vec(h, a != 0i64, false, p1, p2, 0i64)
    case 0x08, 0x09:
        let p1 = vm_pop(h)
        let p2 = vm_pop(h)
        vm_line_vec(h, a != 0i64, false, p1, p2, 1i64)
    case 0x0A:
        let y = vm_pop(h)
        let x = vm_pop(h)
        h.gs.proj_x = x
        h.gs.proj_y = y
        h.gs.dual_x = x
        h.gs.dual_y = y
    case 0x0B:
        let y = vm_pop(h)
        let x = vm_pop(h)
        h.gs.free_x = x
        h.gs.free_y = y
    case 0x0C:
        vm_push(h, h.gs.proj_x)
        vm_push(h, h.gs.proj_y)
    case 0x0D:
        vm_push(h, h.gs.free_x)
        vm_push(h, h.gs.free_y)
    case 0x0E:
        h.gs.free_x = h.gs.proj_x
        h.gs.free_y = h.gs.proj_y
    case 0x0F:
        vm_isect(h)
    case 0x10:
        h.gs.rp0 = vm_pop(h)
    case 0x11:
        h.gs.rp1 = vm_pop(h)
    case 0x12:
        h.gs.rp2 = vm_pop(h)
    case 0x13:
        vm_setzp(h, 0i64, vm_pop(h))
    case 0x14:
        vm_setzp(h, 1i64, vm_pop(h))
    case 0x15:
        vm_setzp(h, 2i64, vm_pop(h))
    case 0x16:
        let v = vm_pop(h)
        vm_setzp(h, 0i64, v)
        vm_setzp(h, 1i64, v)
        vm_setzp(h, 2i64, v)
    case 0x17:
        let v = vm_pop(h)
        if v < 0i64 {
            h.fail = true
        } else {
            h.gs.lp = v
            if v > 65535i64 { h.gs.lp = 65535i64 }
        }
    case 0x18:
        h.gs.round_state = 1i64
    case 0x19:
        h.gs.round_state = 0i64
    case 0x1A:
        h.gs.min_dist = vm_pop(h)
    case 0x1B:
        vm_skip_if(h, false)
    case 0x1C:
        let off = vm_pop(h)
        vm_jump(h, off, at)
    case 0x1D:
        h.gs.cvt_cut_in = vm_pop(h)
    case 0x1E:
        h.gs.sw_cut_in = vm_pop(h)
    case 0x1F:
        h.gs.sw_value = mulfix(vm_pop(h), h.xs)
    case 0x20:
        let v = vm_pop(h)
        vm_push(h, v)
        vm_push(h, v)
    case 0x21:
        let v = vm_pop(h)
    case 0x22:
        h.sp = 0usize
    case 0x23:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, b)
        vm_push(h, c)
    case 0x24:
        vm_push(h, i64(h.sp))
    case 0x25:
        let k = vm_pop(h)
        if k < 1i64 || usize(k) > h.sp {
            h.fail = true
        } else {
            vm_push(h, h.stack[h.sp - usize(k)])
        }
    case 0x26:
        let k = vm_pop(h)
        if k < 1i64 || usize(k) > h.sp {
            h.fail = true
        } else {
            let at_k = h.sp - usize(k)
            let v = h.stack[at_k]
            var i = at_k
            while i + 1usize < h.sp {
                h.stack[i] = h.stack[i + 1usize]
                i += 1usize
            }
            h.stack[h.sp - 1usize] = v
        }
    case 0x27:
        let p2 = vm_pop(h)
        let p1 = vm_pop(h)
        if !h.fail && vm_pt(h, h.gs.gep1, p1) && vm_pt(h, h.gs.gep0, p2) {
            let z1 = &h.zone[h.gs.gep1]
            let z0 = &h.zone[h.gs.gep0]
            let d = vm_project(h, z0.cur[2usize * usize(p2)] - z1.cur[2usize * usize(p1)], z0.cur[2usize * usize(p2) + 1usize] - z1.cur[2usize * usize(p1) + 1usize]) / 2i64
            vm_move(h, h.gs.gep1, usize(p1), d)
            vm_move(h, h.gs.gep0, usize(p2), 0i64 - d)
        }
    case 0x29:
        let p = vm_pop(h)
        if !h.fail && vm_pt(h, h.gs.gep0, p) {
            var mask = 255i64
            if h.gs.free_x != 0i64 { mask = mask & (0i64 - 9i64) }
            if h.gs.free_y != 0i64 { mask = mask & (0i64 - 17i64) }
            let z = &h.zone[h.gs.gep0]
            z.tags[usize(p)] = z.tags[usize(p)] & mask
        }
    case 0x2A:
        let f = vm_pop(h)
        let cnt = vm_pop(h)
        if !h.fail { vm_call(h, f, cnt) }
    case 0x2B:
        let f = vm_pop(h)
        if !h.fail { vm_call(h, f, 1i64) }
    case 0x2C:
        let f = vm_pop(h)
        let start = h.ip
        vm_skip_fdef(h)
        if !h.fail {
            if f < 0i64 || usize(f) > h.max_fdefs {
                h.fail = true
            } else {
                h.fdef_lo[usize(f)] = start
                h.fdef_hi[usize(f)] = h.ip - 1usize
                h.fdef_delta[usize(f)] = vm_is_delta_function(h, start, h.ip)
                h.fdef_bypass[usize(f)] = vm_bypass_slot(h, start)
            }
        }
    case 0x2D:
        h.fail = true
    case 0x2E, 0x2F:
        vm_mdap(h, a != 0i64)
    case 0x30, 0x31:
        vm_iup(h, a != 0i64)
    case 0x32, 0x33:
        vm_shp(h, a != 0i64)
    case 0x34, 0x35:
        vm_shc(h, a != 0i64)
    case 0x36, 0x37:
        vm_shz(h, a != 0i64)
    case 0x38:
        vm_shpix(h)
    case 0x39:
        vm_ip(h)
    case 0x3A, 0x3B:
        vm_msirp(h, a != 0i64)
    case 0x3C:
        vm_alignrp(h)
    case 0x3D:
        h.gs.round_state = 2i64
    case 0x3E, 0x3F:
        vm_miap(h, a != 0i64)
    case 0x42:
        let v = vm_pop(h)
        let i = vm_pop(h)
        if i < 0i64 || i >= i64(h.storage.len) {
            h.fail = true
        } else {
            h.storage[usize(i)] = v
        }
    case 0x43:
        let i = vm_pop(h)
        if i < 0i64 || i >= i64(h.storage.len) {
            h.fail = true
        } else {
            if i == h.bypass {
                vm_push(h, 0i64)
            } else {
                vm_push(h, h.storage[usize(i)])
            }
        }
    case 0x44:
        let v = vm_pop(h)
        let i = vm_pop(h)
        if i < 0i64 || i >= i64(h.cvt.len) {
            h.fail = true
        } else {
            h.cvt[usize(i)] = v
        }
    case 0x45:
        let i = vm_pop(h)
        if i < 0i64 || i >= i64(h.cvt.len) {
            h.fail = true
        } else {
            vm_push(h, h.cvt[usize(i)])
        }
    case 0x46, 0x47:
        let p = vm_pop(h)
        if !h.fail && vm_pt(h, h.gs.gep2, p) {
            let z = &h.zone[h.gs.gep2]
            if a == 0i64 {
                vm_push(h, vm_project(h, z.cur[2usize * usize(p)], z.cur[2usize * usize(p) + 1usize]))
            } else {
                vm_push(h, vm_dualproj(h, z.org[2usize * usize(p)], z.org[2usize * usize(p) + 1usize]))
            }
        }
    case 0x48:
        let v = vm_pop(h)
        let p = vm_pop(h)
        if !h.fail && vm_pt(h, h.gs.gep2, p) {
            let z = &h.zone[h.gs.gep2]
            let cur = vm_project(h, z.cur[2usize * usize(p)], z.cur[2usize * usize(p) + 1usize])
            vm_move(h, h.gs.gep2, usize(p), v - cur)
            if h.gs.gep2 == 0usize {
                z.org[2usize * usize(p)] = z.cur[2usize * usize(p)]
                z.org[2usize * usize(p) + 1usize] = z.cur[2usize * usize(p) + 1usize]
            }
        }
    case 0x49, 0x4A:
        let k = vm_pop(h)
        let l = vm_pop(h)
        if !h.fail && vm_pt(h, h.gs.gep1, k) && vm_pt(h, h.gs.gep0, l) {
            let z0 = &h.zone[h.gs.gep0]
            let z1 = &h.zone[h.gs.gep1]
            let li = 2usize * usize(l)
            let ki = 2usize * usize(k)
            if a != 0i64 {
                vm_push(h, vm_project(h, z0.cur[li] - z1.cur[ki], z0.cur[li + 1usize] - z1.cur[ki + 1usize]))
            } else if h.gs.gep0 == 0usize || h.gs.gep1 == 0usize {
                vm_push(h, vm_dualproj(h, z0.org[li] - z1.org[ki], z0.org[li + 1usize] - z1.org[ki + 1usize]))
            } else {
                vm_push(h, mulfix(vm_dualproj(h, z0.orus[li] - z1.orus[ki], z0.orus[li + 1usize] - z1.orus[ki + 1usize]), h.xs))
            }
        }
    case 0x4B, 0x4C:
        vm_push(h, h.ppem)
    case 0x4D:
        h.gs.auto_flip = true
    case 0x4E:
        h.gs.auto_flip = false
    case 0x4F:
        let v = vm_pop(h)
    case 0x50:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c < b))
    case 0x51:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c <= b))
    case 0x52:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c > b))
    case 0x53:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c >= b))
    case 0x54:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c == b))
    case 0x55:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c != b))
    case 0x56:
        let v = vm_pop(h)
        vm_push(h, vm_bool((vm_round(h, v) & 127i64) == 64i64))
    case 0x57:
        let v = vm_pop(h)
        vm_push(h, vm_bool((vm_round(h, v) & 127i64) == 0i64))
    case 0x58:
        let c = vm_pop(h)
        if c == 0i64 { vm_skip_if(h, true) }
    case 0x59:
        vm_noop(h)
    case 0x5A:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c != 0i64 && b != 0i64))
    case 0x5B:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, vm_bool(c != 0i64 || b != 0i64))
    case 0x5C:
        let v = vm_pop(h)
        vm_push(h, vm_bool(v == 0i64))
    case 0x5D:
        vm_deltap(h, 1i64)
    case 0x5E:
        h.gs.delta_base = vm_pop(h)
    case 0x5F:
        h.gs.delta_shift = vm_pop(h)
    case 0x60:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, c + b)
    case 0x61:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, c - b)
    case 0x62:
        let b = vm_pop(h)
        let c = vm_pop(h)
        if b == 0i64 {
            h.fail = true
        } else {
            vm_push(h, muldiv_nr(c, 64i64, b))
        }
    case 0x63:
        let b = vm_pop(h)
        let c = vm_pop(h)
        vm_push(h, muldiv(c, b, 64i64))
    case 0x64:
        vm_push(h, abs64(vm_pop(h)))
    case 0x65:
        vm_push(h, 0i64 - vm_pop(h))
    case 0x66:
        vm_push(h, pix_floor(vm_pop(h)))
    case 0x67:
        vm_push(h, pix_ceil(vm_pop(h)))
    case 0x68, 0x69, 0x6A, 0x6B:
        vm_push(h, vm_round(h, vm_pop(h)))
    case 0x6C, 0x6D, 0x6E, 0x6F:
        vm_noop(h)
    case 0x70:
        let v = vm_pop(h)
        let i = vm_pop(h)
        if i < 0i64 || i >= i64(h.cvt.len) {
            h.fail = true
        } else {
            h.cvt[usize(i)] = mulfix(v, h.xs)
        }
    case 0x71:
        vm_deltap(h, 2i64)
    case 0x72:
        vm_deltap(h, 3i64)
    case 0x73:
        vm_deltac(h, 1i64)
    case 0x74:
        vm_deltac(h, 2i64)
    case 0x75:
        vm_deltac(h, 3i64)
    case 0x76, 0x77:
        vm_set_super(h, vm_pop(h))
    case 0x78:
        let c = vm_pop(h)
        let off = vm_pop(h)
        if c != 0i64 { vm_jump(h, off, at) }
    case 0x79:
        let c = vm_pop(h)
        let off = vm_pop(h)
        if c == 0i64 { vm_jump(h, off, at) }
    case 0x7A:
        h.gs.round_state = 5i64
    case 0x7C:
        h.gs.round_state = 4i64
    case 0x7D:
        h.gs.round_state = 3i64
    case 0x7E, 0x7F:
        let v = vm_pop(h)
    case 0x80:
        var k = 0i64
        while k < h.gs.lp {
            let p = vm_pop(h)
            if !h.fail && vm_pt(h, 1usize, p) { h.zone[1usize].tags[usize(p)] = h.zone[1usize].tags[usize(p)] ^ 1i64 }
            k += 1i64
        }
        h.gs.lp = 1i64
    case 0x81, 0x82:
        let e = vm_pop(h)
        let s = vm_pop(h)
        if !h.fail && s >= 0i64 && e < i64(h.zone[1usize].n) {
            var p = s
            while p <= e {
                if a == 1i64 {
                    h.zone[1usize].tags[usize(p)] = h.zone[1usize].tags[usize(p)] | 1i64
                } else {
                    h.zone[1usize].tags[usize(p)] = h.zone[1usize].tags[usize(p)] & (0i64 - 2i64)
                }
                p += 1i64
            }
        }
    case 0x85:
        h.gs.scan_control = vm_pop(h)
    case 0x86, 0x87:
        let p1 = vm_pop(h)
        let p2 = vm_pop(h)
        vm_line_vec(h, a != 0i64, true, p1, p2, 2i64)
        vm_line_vec(h, a != 0i64, false, p1, p2, 3i64)
    case 0x88:
        vm_push(h, vm_getinfo(h, vm_pop(h)))
    case 0x89:
        let v = vm_pop(h)
        vm_skip_fdef(h)
    case 0x8A:
        let c = vm_pop(h)
        let b = vm_pop(h)
        let d = vm_pop(h)
        vm_push(h, b)
        vm_push(h, c)
        vm_push(h, d)
    case 0x8B:
        let b = vm_pop(h)
        let c = vm_pop(h)
        if c > b {
            vm_push(h, c)
        } else {
            vm_push(h, b)
        }
    case 0x8C:
        let b = vm_pop(h)
        let c = vm_pop(h)
        if c < b {
            vm_push(h, c)
        } else {
            vm_push(h, b)
        }
    case 0x8D:
        h.gs.scan_type = vm_pop(h)
    case 0x8E:
        vm_instctrl(h)
    default:
        h.fail = true
    }
}

// Runs the code at `lo..hi` of the font data to its end.
fn vm_run(h: *Hinter, lo: usize, hi: usize) -> err {
    h.code_lo = lo
    h.code_hi = hi
    h.ip = lo
    h.fail = false
    h.depth = 0usize
    h.steps = 0usize
    var ops = 0i64
    while h.ip < hi && !h.fail {
        let op = h.data[h.ip]
        if cut_ops < 0i64 && op == 0x31u8 && h.zone[1usize].n > 0usize && h.cleartype && h.depth == 0usize && cut_here { break }
        vm_step(h)
        h.steps += 1usize
        if h.steps > MAX_STEPS { h.fail = true }
        // a probe: stop after `cut_ops` instructions that are not pushes (the glyph program only)
        if cut_ops > 0i64 && h.zone[1usize].n > 0usize && h.cleartype && h.depth == 0usize && cut_here {
            if !(op == 0x40u8 || op == 0x41u8 || (op >= 0xB0u8 && op <= 0xBFu8)) { ops += 1i64 }
            if ops >= cut_ops { break }
        }
    }
    if cut_iup && cut_ops > 0i64 && h.zone[1usize].n > 0usize && h.cleartype && h.depth == 0usize && cut_here && !h.fail { vm_iup(h, true) }
    if h.fail { ret Trap }
    ret ok
}
