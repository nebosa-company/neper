// The outline of a glyph of an OpenType font with CFF outlines, hinted the way FreeType's Adobe CFF engine hints it (`psaux`: pshints.c,
// psblues.c, psintrp.c, psfont.c; the hinted, unstemdarkened case that FT_LOAD_DEFAULT gives, which is what GTK and Cairo ask for): the stem
// hints of the charstring are placed on the pixel grid in y (blue zones first, then the other stems), every point of the glyph is mapped
// through the resulting piecewise linear map, and x is only scaled. Cantarell's text in GTK is exactly this, so a label drawn from this
// outline at an integer pen position under an exact-coverage fill has GTK's pixels. Every number is an `i64` in 16.16 fixed point as in
// the C (coordinates in pixels, or in font units when `hinted` is false); the port was checked against FreeType's own outlines for the
// 94 ASCII glyphs of Cantarell Regular and Bold at eleven sizes, every point equal in 26.6.
//
// Nothing is read from disk and nothing is cached: the caller owns the font bytes and an `Engine` (one is a few tens of kilobytes) and
// asks for one glyph at a time; the result is in the `Outline` it passes.

error Invalid
error TooLarge

const MAX_EDGES: usize = 192usize
const MAX_STEMS: usize = 96usize
const MAX_ZONES: usize = 24usize
const MAX_OPS: usize = 400usize
const MAX_PTS: usize = 1200usize
const MAX_DEPTH: usize = 12usize

const PAIR_BOTTOM: u32 = 1u32
const PAIR_TOP: u32 = 2u32
const GHOST_BOTTOM: u32 = 4u32
const GHOST_TOP: u32 = 8u32
const LOCKED: u32 = 16u32
const SYNTHETIC: u32 = 32u32

const MIN_COUNTER: i64 = 32768i64
const ONE: i64 = 65536i64

// A parsed font: where its CFF pieces are (offsets into `data`).
type Cff = struct {
    data: []const u8,
    upem: i64,
    glyph_count: usize,
    char_at: usize,
    gsubr_at: usize,
    lsubr_at: usize,
    blue_count: usize,
    blue: [24]i64,
    other_count: usize,
    other: [24]i64,
    family_count: usize,
    family: [24]i64,
    family_other_count: usize,
    family_other: [24]i64,
    blue_scale: i64,
    blue_shift: i64,
    blue_fuzz: i64
}

type Hint = struct { flags: u32, index: usize, cs: i64, ds: i64, scale: i64 }
type Zone = struct { bottom: bool, cs_bottom: i64, cs_top: i64, cs_flat: i64, ds_flat: i64 }
type Blues = struct { count: usize, zone: [24]Zone, scale: i64, blue_scale: i64, blue_shift: i64, blue_fuzz: i64, suppress: bool, boost: i64 }
type Stem = struct { low: i64, high: i64, used: bool, low_ds: i64, high_ds: i64 }
type HintMap = struct { count: usize, edge: [192]Hint, scale: i64, valid: bool, last: usize }
type Frame = struct { pos: usize, end: usize }

// The outline of a glyph: ops 0 move (1 point), 1 line (1 point), 2 cubic (3 points); the points are 16.16 pixels (font units unhinted).
type Outline = struct { n: usize, kind: [400]u8, pn: usize, x: [1200]i64, y: [1200]i64, hinted: bool }

type Engine = struct {
    cff: *const Cff,
    blues: Blues,
    scale: i64,
    hinted: bool,
    stem: [96]Stem,
    hn: usize,
    vn: usize,
    mask: [96]bool,
    mask_valid: bool,
    mask_new: bool,
    initial: HintMap,
    first: HintMap,
    cur: HintMap,
    counter: HintMap,
    // glyph path
    ix: i64,
    iy: i64,
    cur_x: i64,
    cur_y: i64,
    start_x: i64,
    start_y: i64,
    move_pending: bool,
    path_open: bool,
    closing: bool,
    queued: bool,
    prev_curve: bool,
    p0x: i64, p0y: i64, p1x: i64, p1y: i64, p2x: i64, p2y: i64, p3x: i64, p3y: i64,
    ds_x: i64,
    ds_y: i64,
    off0_x: i64, off0_y: i64, off1_x: i64, off1_y: i64,
    out: *Outline,
    failed: bool
}

// ---- fixed point, FT_MulFix and friends

fn abs64(x: i64) -> i64 {
    if x < 0i64 { ret 0i64 - x }
    ret x
}

fn mulfix(a: i64, b: i64) -> i64 {
    var x = a
    var y = b
    var negative = false
    if x < 0i64 {
        x = 0i64 - x
        negative = !negative
    }
    if y < 0i64 {
        y = 0i64 - y
        negative = !negative
    }
    let r = (x * y + 32768i64) >> 16u32
    if negative { ret 0i64 - r }
    ret r
}

fn divfix(a: i64, b: i64) -> i64 {
    var x = a
    var y = b
    var negative = false
    if x < 0i64 {
        x = 0i64 - x
        negative = !negative
    }
    if y < 0i64 {
        y = 0i64 - y
        negative = !negative
    }
    if y == 0i64 { ret 2147483647i64 }
    let r = ((x << 16u32) + (y >> 1u32)) / y
    if negative { ret 0i64 - r }
    ret r
}

fn fx_round(x: i64) -> i64 { ret (x + 32768i64) & (0i64 - 65536i64) }
fn fx_floor(x: i64) -> i64 { ret x & (0i64 - 65536i64) }
fn fx_frac(x: i64) -> i64 { ret x - fx_floor(x) }

// ---- reading the font

fn be16(d: []const u8, at: usize) -> i64 {
    if at + 2usize > d.len { ret 0i64 }
    ret i64(d[at]) * 256i64 + i64(d[at + 1usize])
}

fn be32(d: []const u8, at: usize) -> i64 {
    if at + 4usize > d.len { ret 0i64 }
    ret ((i64(d[at]) * 256i64 + i64(d[at + 1usize])) * 256i64 + i64(d[at + 2usize])) * 256i64 + i64(d[at + 3usize])
}

// The table `tag` of the font (offset and length), or 0.
fn table(d: []const u8, tag: i64) -> (usize, usize) {
    let count = usize(be16(d, 4usize))
    var i = 0usize
    while i < count {
        let record = 12usize + 16usize * i
        if be32(d, record) == tag { ret (usize(be32(d, record + 8usize)), usize(be32(d, record + 12usize))) }
        i += 1usize
    }
    ret (0usize, 0usize)
}

// An INDEX at `at`: its object count.
fn index_count(d: []const u8, at: usize) -> usize { ret usize(be16(d, at)) }

fn index_size(d: []const u8, at: usize) -> usize {
    let count = index_count(d, at)
    if count == 0usize { ret 2usize }
    let off_size = usize(d[at + 2usize])
    var last: i64 = 0i64
    var k = 0usize
    while k < off_size {
        last = last * 256i64 + i64(d[at + 3usize + count * off_size + k])
        k += 1usize
    }
    ret 3usize + (count + 1usize) * off_size + usize(last) - 1usize
}

// Object `i` of the INDEX at `at`: its start and end offsets.
fn index_range(d: []const u8, at: usize, i: usize) -> (usize, usize) {
    let off_size = usize(d[at + 2usize])
    let count = index_count(d, at)
    let base = at + 3usize + (count + 1usize) * off_size - 1usize
    var first: i64 = 0i64
    var second: i64 = 0i64
    var k = 0usize
    while k < off_size {
        first = first * 256i64 + i64(d[at + 3usize + i * off_size + k])
        second = second * 256i64 + i64(d[at + 3usize + (i + 1usize) * off_size + k])
        k += 1usize
    }
    ret (base + usize(first), base + usize(second))
}

// One DICT operand at `at`: its value (a real as value * 65536) and its length; `kind` 0 integer, 1 real.
fn dict_operand(d: []const u8, at: usize) -> (i64, usize, bool) {
    let b0 = i64(d[at])
    if b0 >= 32i64 && b0 <= 246i64 { ret (b0 - 139i64, 1usize, false) }
    if b0 >= 247i64 && b0 <= 250i64 { ret ((b0 - 247i64) * 256i64 + i64(d[at + 1usize]) + 108i64, 2usize, false) }
    if b0 >= 251i64 && b0 <= 254i64 { ret (0i64 - (b0 - 251i64) * 256i64 - i64(d[at + 1usize]) - 108i64, 2usize, false) }
    if b0 == 28i64 {
        var v = be16(d, at + 1usize)
        if v >= 32768i64 { v = v - 65536i64 }
        ret (v, 3usize, false)
    }
    if b0 == 29i64 {
        var v = be32(d, at + 1usize)
        if v >= 2147483648i64 { v = v - 4294967296i64 }
        ret (v, 5usize, false)
    }
    if b0 == 30i64 {
        // a packed decimal: digits, '.', 'E', 'E-', '-', end
        var mantissa: f64 = 0.0
        var scale: f64 = 1.0
        var exponent: i64 = 0i64
        var negative = false
        var negative_exponent = false
        var seen_point = false
        var in_exponent = false
        var pos = at + 1usize
        var done = false
        while !done && pos < d.len {
            var half = 0usize
            while half < 2usize {
                var nibble = i64(d[pos])
                if half == 0usize { nibble = nibble >> 4u32 } else { nibble = nibble & 15i64 }
                if nibble <= 9i64 {
                    if in_exponent {
                        exponent = exponent * 10i64 + nibble
                    } else if seen_point {
                        scale = scale / 10.0
                        mantissa = mantissa + f64(nibble) * scale
                    } else {
                        mantissa = mantissa * 10.0 + f64(nibble)
                    }
                } else if nibble == 10i64 {
                    seen_point = true
                } else if nibble == 11i64 {
                    in_exponent = true
                } else if nibble == 12i64 {
                    in_exponent = true
                    negative_exponent = true
                } else if nibble == 14i64 {
                    negative = true
                } else if nibble == 15i64 {
                    done = true
                    half = 2usize
                    continue
                }
                half += 1usize
            }
            pos += 1usize
        }
        var rest = exponent
        while rest > 0i64 {
            if negative_exponent { mantissa = mantissa / 10.0 } else { mantissa = mantissa * 10.0 }
            rest -= 1i64
        }
        if negative { mantissa = 0.0 - mantissa }
        ret (i64(mantissa * 65536.0 + 0.5), pos - at, true)
    }
    ret (0i64, 1usize, false)
}

fn read_blues(d: []const u8, ops: []const i64, n: usize, out: []i64) -> usize {
    var sum: i64 = 0i64
    var i = 0usize
    while i < n && i < 24usize {
        sum = sum + ops[i]
        out[i] = sum
        i += 1usize
    }
    ret i
}

// Parses the CFF table of an OpenType font; false when the font has none or it is not one this port reads (CID-keyed, CFF2).
fn open(c: *Cff, d: []const u8) -> bool {
    let (cff_at, cff_len) = table(d, 1128678944i64)
    if cff_at == 0usize || cff_len < 4usize { ret false }
    if d[cff_at] != 1u8 { ret false }
    let (head_at, head_len) = table(d, 1751474532i64)
    let (maxp_at, maxp_len) = table(d, 1835104368i64)
    if head_at == 0usize || head_len < 54usize || maxp_at == 0usize || maxp_len < 6usize { ret false }
    c.data = d
    c.upem = be16(d, head_at + 18usize)
    c.glyph_count = usize(be16(d, maxp_at + 4usize))
    if c.upem <= 0i64 { ret false }
    let header_size = usize(d[cff_at + 2usize])
    let names = cff_at + header_size
    let tops = names + index_size(d, names)
    let strings = tops + index_size(d, tops)
    c.gsubr_at = strings + index_size(d, strings)
    if index_count(d, tops) < 1usize { ret false }
    let (top_start, top_end) = index_range(d, tops, 0usize)
    var private_size: usize = 0usize
    var private_at: usize = 0usize
    c.char_at = 0usize
    var ops: [48]i64 = zero
    var n = 0usize
    var pos = top_start
    // the Top DICT
    while pos < top_end {
        let b0 = i64(d[pos])
        if b0 <= 21i64 {
            var op = b0
            pos += 1usize
            if b0 == 12i64 {
                op = 1200i64 + i64(d[pos])
                pos += 1usize
            }
            if op == 17i64 && n >= 1usize { c.char_at = cff_at + usize(ops[0usize] >> 16u32) }
            if op == 18i64 && n >= 2usize {
                private_size = usize(ops[0usize] >> 16u32)
                private_at = cff_at + usize(ops[1usize] >> 16u32)
            }
            if op == 1230i64 { ret false }
            n = 0usize
        } else {
            let (v, used, is_real) = dict_operand(d, pos)
            if n < 48usize {
                if is_real { ops[n] = v } else { ops[n] = v << 16u32 }
                n += 1usize
            }
            pos += used
        }
    }
    if c.char_at == 0usize || private_at == 0usize { ret false }
    // the Private DICT
    c.lsubr_at = 0usize
    c.blue_count = 0usize
    c.other_count = 0usize
    c.family_count = 0usize
    c.family_other_count = 0usize
    c.blue_scale = 0i64
    c.blue_shift = 7i64
    c.blue_fuzz = 1i64
    var vals: [48]i64 = zero
    n = 0usize
    pos = private_at
    while pos < private_at + private_size {
        let b0 = i64(d[pos])
        if b0 <= 21i64 {
            var op = b0
            pos += 1usize
            if b0 == 12i64 {
                op = 1200i64 + i64(d[pos])
                pos += 1usize
            }
            if op == 6i64 { c.blue_count = read_blues(d, vals[0usize..48usize], n, c.blue[0usize..24usize]) }
            if op == 7i64 { c.other_count = read_blues(d, vals[0usize..48usize], n, c.other[0usize..24usize]) }
            if op == 8i64 { c.family_count = read_blues(d, vals[0usize..48usize], n, c.family[0usize..24usize]) }
            if op == 9i64 { c.family_other_count = read_blues(d, vals[0usize..48usize], n, c.family_other[0usize..24usize]) }
            if op == 1209i64 && n >= 1usize { c.blue_scale = vals[0usize] }
            if op == 1210i64 && n >= 1usize { c.blue_shift = vals[0usize] }
            if op == 1211i64 && n >= 1usize { c.blue_fuzz = vals[0usize] }
            if op == 19i64 && n >= 1usize { c.lsubr_at = private_at + usize(vals[0usize]) }
            n = 0usize
        } else {
            let (v, used, is_real) = dict_operand(d, pos)
            if n < 48usize {
                // blue values are integers; BlueScale is kept as a real in 16.16
                if is_real { vals[n] = v } else { vals[n] = v }
                n += 1usize
            }
            pos += used
        }
    }
    ret true
}

// ---- the blue zones (psblues.c)

fn blues_init(b: *Blues, c: *const Cff, scale: i64) {
    b.count = 0usize
    b.scale = scale
    // BlueScale in the DICT is a real kept here as value * 65536; FreeType keeps it times 1000, then divides by 1000
    b.blue_scale = divfix(c.blue_scale * 1000i64, 65536i64 * 1000i64)
    if c.blue_scale == 0i64 { b.blue_scale = divfix(2597i64 * 1000i64, 65536i64 * 1000i64) }
    b.blue_shift = c.blue_shift << 16u32
    b.blue_fuzz = c.blue_fuzz << 16u32
    b.suppress = false
    b.boost = 0i64
    var max_height: i64 = 0i64
    var i = 0usize
    while i + 1usize < c.blue_count {
        let bottom = c.blue[i] << 16u32
        let top = c.blue[i + 1usize] << 16u32
        let height = top - bottom
        if height >= 0i64 && b.count < 24usize {
            if height > max_height { max_height = height }
            var z: Zone = zero
            z.cs_bottom = bottom
            z.cs_top = top
            if i == 0usize {
                z.bottom = true
                z.cs_flat = top
            } else {
                z.bottom = false
                z.cs_flat = bottom
            }
            b.zone[b.count] = z
            b.count += 1usize
        }
        i += 2usize
    }
    i = 0usize
    while i + 1usize < c.other_count {
        let bottom = c.other[i] << 16u32
        let top = c.other[i + 1usize] << 16u32
        let height = top - bottom
        if height >= 0i64 && b.count < 24usize {
            if height > max_height { max_height = height }
            var z: Zone = zero
            z.cs_bottom = bottom
            z.cs_top = top
            z.bottom = true
            z.cs_flat = top
            b.zone[b.count] = z
            b.count += 1usize
        }
        i += 2usize
    }
    // FamilyBlues: a flat edge within a pixel of a family edge takes it
    let per_pixel = divfix(ONE, scale)
    var k = 0usize
    while k < b.count {
        let flat = b.zone[k].cs_flat
        if b.zone[k].bottom {
            var min_diff: i64 = 2147483647i64
            var j = 0usize
            while j + 1usize < c.family_other_count {
                let edge = c.family_other[j + 1usize] << 16u32
                let diff = abs64(flat - edge)
                if diff < min_diff && diff < per_pixel {
                    b.zone[k].cs_flat = edge
                    min_diff = diff
                    if diff == 0i64 { break }
                }
                j += 2usize
            }
            if c.family_count >= 2usize {
                let edge = c.family[1usize] << 16u32
                let diff = abs64(flat - edge)
                if diff < min_diff && diff < per_pixel { b.zone[k].cs_flat = edge }
            }
        } else {
            var min_diff: i64 = 2147483647i64
            var j = 2usize
            while j < c.family_count {
                let edge = c.family[j] << 16u32
                let diff = abs64(flat - edge)
                if diff < min_diff && diff < per_pixel {
                    b.zone[k].cs_flat = edge
                    min_diff = diff
                    if diff == 0i64 { break }
                }
                j += 2usize
            }
        }
        k += 1usize
    }
    if max_height > 0i64 {
        let limit = divfix(ONE, max_height)
        if b.blue_scale > limit { b.blue_scale = limit }
    }
    // overshoot is suppressed and the zones boosted below the BlueScale size
    if b.scale < b.blue_scale {
        b.suppress = true
        let six = 39322i64
        b.boost = six - (six * b.scale + b.blue_scale / 2i64) / b.blue_scale
        if b.boost > 32767i64 { b.boost = 32767i64 }
    }
    k = 0usize
    while k < b.count {
        if b.zone[k].bottom {
            b.zone[k].ds_flat = fx_round(mulfix(b.zone[k].cs_flat, b.scale) - b.boost)
        } else {
            b.zone[k].ds_flat = fx_round(mulfix(b.zone[k].cs_flat, b.scale) + b.boost)
        }
        k += 1usize
    }
}

fn hint_is_top(h: *const Hint) -> bool { ret h.flags & (PAIR_TOP | GHOST_TOP) != 0u32 }
fn hint_is_bottom(h: *const Hint) -> bool { ret h.flags & (PAIR_BOTTOM | GHOST_BOTTOM) != 0u32 }
fn hint_is_pair(h: *const Hint) -> bool { ret h.flags & (PAIR_BOTTOM | PAIR_TOP) != 0u32 }
fn hint_locked(h: *const Hint) -> bool { ret h.flags & LOCKED != 0u32 }

// Whether a blue zone captures the stem (bottom, top edges): positions both edges and locks them (cf2_blues_capture).
fn blues_capture(b: *const Blues, bottom: *Hint, top: *Hint) -> bool {
    let fuzz = b.blue_fuzz
    var captured = false
    var move: i64 = 0i64
    var i = 0usize
    while i < b.count {
        let z = b.zone[i]
        if z.bottom && hint_is_bottom(bottom) {
            if z.cs_bottom - fuzz <= bottom.cs && bottom.cs <= z.cs_top + fuzz {
                var fresh: i64 = 0i64
                if b.suppress {
                    fresh = z.ds_flat
                } else if z.cs_top - bottom.cs >= b.blue_shift {
                    fresh = fx_round(bottom.ds)
                    if z.ds_flat - ONE < fresh { fresh = z.ds_flat - ONE }
                } else {
                    fresh = fx_round(bottom.ds)
                }
                move = fresh - bottom.ds
                captured = true
                break
            }
        }
        if !z.bottom && hint_is_top(top) {
            if z.cs_bottom - fuzz <= top.cs && top.cs <= z.cs_top + fuzz {
                var fresh: i64 = 0i64
                if b.suppress {
                    fresh = z.ds_flat
                } else if top.cs - z.cs_bottom >= b.blue_shift {
                    fresh = fx_round(top.ds)
                    if z.ds_flat + ONE > fresh { fresh = z.ds_flat + ONE }
                } else {
                    fresh = fx_round(top.ds)
                }
                move = fresh - top.ds
                captured = true
                break
            }
        }
        i += 1usize
    }
    if captured {
        if bottom.flags != 0u32 {
            bottom.ds = bottom.ds + move
            bottom.flags = bottom.flags | LOCKED
        }
        if top.flags != 0u32 {
            top.ds = top.ds + move
            top.flags = top.flags | LOCKED
        }
    }
    ret captured
}

// ---- hints and hint maps (pshints.c)

// The bottom or top edge of stem `i` as a hint (cf2_hint_init).
fn hint_init(e: *const Engine, i: usize, bottom: bool) -> Hint {
    var h: Hint = zero
    let s = e.stem[i]
    let width = s.high - s.low
    if width == 0i64 - 21i64 * ONE {
        if bottom {
            h.cs = s.high
            h.flags = GHOST_BOTTOM
        } else {
            h.flags = 0u32
        }
    } else if width == 0i64 - 20i64 * ONE {
        if bottom {
            h.flags = 0u32
        } else {
            h.cs = s.low
            h.flags = GHOST_TOP
        }
    } else if width < 0i64 {
        if bottom {
            h.cs = s.high
            h.flags = PAIR_BOTTOM
        } else {
            h.cs = s.low
            h.flags = PAIR_TOP
        }
    } else {
        if bottom {
            h.cs = s.low
            h.flags = PAIR_BOTTOM
        } else {
            h.cs = s.high
            h.flags = PAIR_TOP
        }
    }
    h.scale = e.scale
    h.index = i
    if h.flags != 0u32 && s.used {
        if hint_is_top(&h) { h.ds = s.high_ds } else { h.ds = s.low_ds }
        h.flags = h.flags | LOCKED
    } else {
        h.ds = mulfix(h.cs, e.scale)
    }
    ret h
}

// The device space position of a character space coordinate under the map (cf2_hintmap_map).
fn map_y(m: *HintMap, cs: i64) -> i64 {
    if m.count == 0usize { ret mulfix(cs, m.scale) }
    var i = m.last
    if i >= m.count { i = m.count - 1usize }
    while i < m.count - 1usize && cs >= m.edge[i + 1usize].cs { i += 1usize }
    while i > 0usize && cs < m.edge[i].cs { i -= 1usize }
    m.last = i
    if i == 0usize && cs < m.edge[0usize].cs { ret mulfix(cs - m.edge[0usize].cs, m.scale) + m.edge[0usize].ds }
    ret mulfix(cs - m.edge[i].cs, m.edge[i].scale) + m.edge[i].ds
}

// Moves the unlocked hints to pixel boundaries without overlap (cf2_hintmap_adjustHints).
fn adjust_hints(m: *HintMap) {
    var saved_j: [96]usize = zero
    var saved_up: [96]i64 = zero
    var saved = 0usize
    var i = 0usize
    while i < m.count {
        let pair = hint_is_pair(&m.edge[i])
        var move: i64 = 0i64
        var j = i
        if pair { j = i + 1usize }
        let ds_i = m.edge[i].ds
        let ds_j = m.edge[j].ds
        if !hint_locked(&m.edge[i]) {
            let frac_down = fx_frac(ds_i)
            let frac_up = fx_frac(ds_j)
            let down_move_down = 0i64 - frac_down
            let up_move_down = 0i64 - frac_up
            var down_move_up: i64 = 0i64
            if frac_down != 0i64 { down_move_up = ONE - frac_down }
            var up_move_up: i64 = 0i64
            if frac_up != 0i64 { up_move_up = ONE - frac_up }
            var move_up = up_move_up
            if down_move_up < up_move_up { move_up = down_move_up }
            var move_down = up_move_down
            if down_move_down > up_move_down { move_down = down_move_down }
            var save = false
            if j >= m.count - 1usize || m.edge[j + 1usize].ds >= ds_j + move_up + MIN_COUNTER {
                if i == 0usize || m.edge[i - 1usize].ds <= ds_i + move_down - MIN_COUNTER {
                    if 0i64 - move_down < move_up { move = move_down } else { move = move_up }
                } else {
                    move = move_up
                }
            } else {
                if i == 0usize || m.edge[i - 1usize].ds <= ds_i + move_down - MIN_COUNTER {
                    move = move_down
                    save = move_up < 0i64 - move_down
                } else {
                    move = 0i64
                    save = true
                }
            }
            if save && j < m.count - 1usize && !hint_locked(&m.edge[j + 1usize]) && saved < 96usize {
                saved_j[saved] = j
                saved_up[saved] = move_up - move
                saved += 1usize
            }
            m.edge[i].ds = ds_i + move
            if pair { m.edge[j].ds = ds_j + move }
        }
        if i > 0usize {
            if m.edge[i].cs != m.edge[i - 1usize].cs {
                m.edge[i - 1usize].scale = divfix(m.edge[i].ds - m.edge[i - 1usize].ds, m.edge[i].cs - m.edge[i - 1usize].cs)
            }
        }
        if pair {
            if m.edge[j].cs != m.edge[j - 1usize].cs {
                m.edge[j - 1usize].scale = divfix(m.edge[j].ds - m.edge[j - 1usize].ds, m.edge[j].cs - m.edge[j - 1usize].cs)
            }
            i += 1usize
        }
        i += 1usize
    }
    // the second pass moves what was left non-optimal up, from the last saved to the first
    var k = saved
    while k > 0usize {
        k -= 1usize
        let sj = saved_j[k]
        let up = saved_up[k]
        if m.edge[sj + 1usize].ds >= m.edge[sj].ds + up + MIN_COUNTER {
            m.edge[sj].ds = m.edge[sj].ds + up
            if hint_is_pair(&m.edge[sj]) { m.edge[sj - 1usize].ds = m.edge[sj - 1usize].ds + up }
        }
    }
}

fn cdiv(a: i64, b: i64) -> i64 { ret a / b }

// Inserts the edges of a stem (a pair, or a single edge when one is invalid) into the map sorted by character space coordinate
// (cf2_hintmap_insertHint); the initial map positions the ones that are not locked.
fn insert_hint(e: *Engine, m: *HintMap, bottom_in: Hint, top_in: Hint) {
    var bottom = bottom_in
    var top = top_in
    var pair = true
    var first = bottom
    var second = top
    if bottom.flags == 0u32 {
        first = top
        pair = false
    } else if top.flags == 0u32 {
        pair = false
    }
    if pair && top.cs < bottom.cs { ret }
    var at_index = 0usize
    while at_index < m.count {
        if m.edge[at_index].cs >= first.cs { break }
        at_index += 1usize
    }
    if at_index < m.count {
        if m.edge[at_index].cs == first.cs { ret }
        if pair && m.edge[at_index].cs <= second.cs { ret }
        if m.edge[at_index].flags & PAIR_TOP != 0u32 { ret }
    }
    if e.initial.valid && !hint_locked(&first) {
        if pair {
            let half_span = cdiv(second.cs - first.cs, 2i64)
            let mid = map_y(&e.initial, first.cs + half_span)
            let half = mulfix(half_span, m.scale)
            first.ds = mid - half
            second.ds = mid + half
        } else {
            first.ds = map_y(&e.initial, first.cs)
        }
    }
    if at_index > 0usize {
        if first.ds < m.edge[at_index - 1usize].ds { ret }
    }
    if at_index < m.count {
        if pair {
            if second.ds > m.edge[at_index].ds { ret }
        } else {
            if first.ds > m.edge[at_index].ds { ret }
        }
    }
    var need = 1usize
    if pair { need = 2usize }
    if m.count + need > MAX_EDGES { ret }
    // make room
    var k = m.count
    while k > at_index {
        k -= 1usize
        m.edge[k + need] = m.edge[k]
    }
    m.edge[at_index] = first
    m.count += 1usize
    if pair {
        m.edge[at_index + 1usize] = second
        m.count += 1usize
    }
}

// Builds a hint map from the active stems of `e.mask` (cf2_hintmap_build). `initial_map` builds the initial map (captured stems and a
// baseline lock); `mask_all` ignores the mask and takes every stem.
fn build_map(e: *Engine, m: *HintMap, mask: [96]bool, initial_map: bool, glyph_mask: bool) {
    if !initial_map && !e.initial.valid {
        var all: [96]bool = zero
        var j = 0usize
        while j < 96usize {
            all[j] = true
            j += 1usize
        }
        build_map(e, &e.initial, all, true, false)
    }
    m.count = 0usize
    m.last = 0usize
    var active = mask
    var i = 0usize
    if !e.hinted {
        m.valid = true
        if glyph_mask { e.mask_new = false }
        ret
    }
    i = 0usize
    while i < e.hn {
        if active[i] {
            var bottom = hint_init(e, i, true)
            var top = hint_init(e, i, false)
            if hint_locked(&bottom) || hint_locked(&top) || blues_capture(&e.blues, &bottom, &top) {
                insert_hint(e, m, bottom, top)
                active[i] = false
            }
        }
        i += 1usize
    }
    if initial_map {
        // a locked edge at 0 when nothing covers it keeps the baseline
        if m.count == 0usize || m.edge[0usize].cs > 0i64 || m.edge[m.count - 1usize].cs < 0i64 {
            var edge: Hint = zero
            edge.flags = GHOST_BOTTOM | LOCKED | SYNTHETIC
            edge.scale = m.scale
            var none: Hint = zero
            insert_hint(e, m, edge, none)
        }
    } else {
        i = 0usize
        while i < e.hn {
            if active[i] {
                let bottom = hint_init(e, i, true)
                let top = hint_init(e, i, false)
                insert_hint(e, m, bottom, top)
            }
            i += 1usize
        }
    }
    adjust_hints(m)
    if !initial_map {
        i = 0usize
        while i < m.count {
            if m.edge[i].flags & SYNTHETIC == 0u32 {
                let s = m.edge[i].index
                if hint_is_top(&m.edge[i]) { e.stem[s].high_ds = m.edge[i].ds } else { e.stem[s].low_ds = m.edge[i].ds }
                e.stem[s].used = true
            }
            i += 1usize
        }
    }
    m.valid = true
    if glyph_mask { e.mask_new = false }
}

// ---- the glyph path (pshints.c): elements are mapped one element late, by the map in force when the next one arrives

fn out_op(e: *Engine, kind: u8, n: usize, x0: i64, y0: i64, x1: i64, y1: i64, x2: i64, y2: i64) {
    let o = e.out
    if o.n >= 400usize || o.pn + n > 1200usize {
        e.failed = true
        ret
    }
    o.kind[o.n] = kind
    o.n += 1usize
    o.x[o.pn] = x0
    o.y[o.pn] = y0
    o.pn += 1usize
    if n == 3usize {
        o.x[o.pn] = x1
        o.y[o.pn] = y1
        o.pn += 1usize
        o.x[o.pn] = x2
        o.y[o.pn] = y2
        o.pn += 1usize
    }
}

fn dev_x(e: *const Engine, x: i64) -> i64 { ret mulfix(e.scale, x) }

fn push_move(e: *Engine, sx: i64, sy: i64) {
    if !e.cur.valid { path_move_to(e, e.start_x, e.start_y) }
    let px = dev_x(e, sx)
    let py = map_y(&e.cur, sy)
    out_op(e, 0u8, 1usize, px, py, 0i64, 0i64, 0i64, 0i64)
    e.ds_x = px
    e.ds_y = py
    e.off0_x = sx
    e.off0_y = sy
}

// Emits the queued element, then the line to the start of the next if the points do not join.
fn push_prev(e: *Engine, close: bool, nx: i64, ny: i64) {
    if !e.prev_curve {
        var py: i64 = 0i64
        if close { py = map_y(&e.first, e.p1y) } else { py = map_y(&e.cur, e.p1y) }
        let px = dev_x(e, e.p1x)
        if px != e.ds_x || py != e.ds_y {
            out_op(e, 1u8, 1usize, px, py, 0i64, 0i64, 0i64, 0i64)
            e.ds_x = px
            e.ds_y = py
        }
    } else {
        let ax = dev_x(e, e.p1x)
        let ay = map_y(&e.cur, e.p1y)
        let bx = dev_x(e, e.p2x)
        let by = map_y(&e.cur, e.p2y)
        let cx = dev_x(e, e.p3x)
        let cy = map_y(&e.cur, e.p3y)
        out_op(e, 2u8, 3usize, ax, ay, bx, by, cx, cy)
        e.ds_x = cx
        e.ds_y = cy
    }
    var ty: i64 = 0i64
    if close { ty = map_y(&e.first, ny) } else { ty = map_y(&e.cur, ny) }
    let tx = dev_x(e, nx)
    if tx != e.ds_x || ty != e.ds_y {
        out_op(e, 1u8, 1usize, tx, ty, 0i64, 0i64, 0i64, 0i64)
        e.ds_x = tx
        e.ds_y = ty
    }
}

// A glyph without a hintmask operator has every stem active (cf2_hintmask_setAll): taken when the first map is built.
fn ensure_mask(e: *Engine) {
    if e.mask_valid { ret }
    let total = e.hn + e.vn
    var k = 0usize
    while k < 96usize {
        e.mask[k] = k < total
        k += 1usize
    }
    e.mask_valid = true
    e.mask_new = true
}

fn path_move_to(e: *Engine, x: i64, y: i64) {
    path_close(e)
    e.cur_x = x
    e.cur_y = y
    e.start_x = x
    e.start_y = y
    e.move_pending = true
    if !e.cur.valid || e.mask_new {
        ensure_mask(e)
        build_map(e, &e.cur, e.mask, false, true)
    }
    e.first = e.cur
}

fn path_line_to(e: *Engine, x: i64, y: i64) {
    let new_map = e.mask_new && !e.closing
    if e.cur_x == x && e.cur_y == y && !new_map { ret }
    let p0x = e.cur_x
    let p0y = e.cur_y
    if e.move_pending {
        push_move(e, p0x, p0y)
        e.move_pending = false
        e.path_open = true
        e.off1_x = x
        e.off1_y = y
    }
    if e.queued { push_prev(e, false, p0x, p0y) }
    e.queued = true
    e.prev_curve = false
    e.p0x = p0x
    e.p0y = p0y
    e.p1x = x
    e.p1y = y
    if new_map { build_map(e, &e.cur, e.mask, false, true) }
    e.cur_x = x
    e.cur_y = y
}

fn path_curve_to(e: *Engine, x1: i64, y1: i64, x2: i64, y2: i64, x3: i64, y3: i64) {
    let p0x = e.cur_x
    let p0y = e.cur_y
    if e.move_pending {
        push_move(e, p0x, p0y)
        e.move_pending = false
        e.path_open = true
        e.off1_x = x1
        e.off1_y = y1
    }
    if e.queued { push_prev(e, false, p0x, p0y) }
    e.queued = true
    e.prev_curve = true
    e.p0x = p0x
    e.p0y = p0y
    e.p1x = x1
    e.p1y = y1
    e.p2x = x2
    e.p2y = y2
    e.p3x = x3
    e.p3y = y3
    if e.mask_new { build_map(e, &e.cur, e.mask, false, true) }
    e.cur_x = x3
    e.cur_y = y3
}

fn path_close(e: *Engine) {
    if e.path_open {
        e.closing = true
        path_line_to(e, e.start_x, e.start_y)
        if e.queued { push_prev(e, true, e.off0_x, e.off0_y) }
        e.move_pending = true
        e.path_open = false
        e.closing = false
        e.queued = false
    }
}

// ---- the Type 2 charstring interpreter (psintrp.c)

fn bias_of(n: usize) -> usize {
    if n < 1240usize { ret 107usize }
    if n < 33900usize { ret 1131usize }
    ret 32768usize
}

// Takes the stem hints off the stack into the h (or v) list; `horizontal` for hstem.
fn do_stems(e: *Engine, st: []i64, count: usize, horizontal: bool) {
    var start = 0usize
    if count & 1usize == 1usize { start = 1usize }
    var pos: i64 = 0i64
    var i = start
    while i + 1usize < count {
        pos = pos + st[i]
        let low = pos
        pos = pos + st[i + 1usize]
        let high = pos
        if horizontal {
            if e.hn < MAX_STEMS {
                e.stem[e.hn] = Stem { low: low, high: high, used: false, low_ds: 0i64, high_ds: 0i64 }
                e.hn += 1usize
            }
        } else {
            e.vn += 1usize
        }
        i += 2usize
    }
}

fn rr_curve(e: *Engine, st: []i64, at_index: usize) {
    let x1 = e.ix + st[at_index]
    let y1 = e.iy + st[at_index + 1usize]
    let x2 = x1 + st[at_index + 2usize]
    let y2 = y1 + st[at_index + 3usize]
    let x3 = x2 + st[at_index + 4usize]
    let y3 = y2 + st[at_index + 5usize]
    path_curve_to(e, x1, y1, x2, y2, x3, y3)
    e.ix = x3
    e.iy = y3
}

// Runs the glyph's charstring; false when it uses something this port does not read.
fn run(e: *Engine, gid: usize) -> bool {
    let c = e.cff
    let d = c.data
    if gid >= c.glyph_count { ret false }
    var st: [96]i64 = zero
    var sp = 0usize
    var frames: [14]Frame = zero
    var depth = 0usize
    let (start, finish) = index_range(d, c.char_at, gid)
    frames[0usize] = Frame { pos: start, end: finish }
    var steps = 0usize
    while steps < 200000usize {
        steps += 1usize
        if e.failed { ret false }
        var op: i64 = 0i64
        if frames[depth].pos >= frames[depth].end {
            if depth == 0usize { op = 14i64 } else { op = 11i64 }
        } else {
            op = i64(d[frames[depth].pos])
            frames[depth].pos += 1usize
        }
        if op >= 32i64 || op == 28i64 {
            // an operand
            var v: i64 = 0i64
            if op >= 32i64 && op <= 246i64 {
                v = (op - 139i64) << 16u32
            } else if op >= 247i64 && op <= 250i64 {
                let b1 = i64(d[frames[depth].pos])
                frames[depth].pos += 1usize
                v = ((op - 247i64) * 256i64 + b1 + 108i64) << 16u32
            } else if op >= 251i64 && op <= 254i64 {
                let b1 = i64(d[frames[depth].pos])
                frames[depth].pos += 1usize
                v = (0i64 - (op - 251i64) * 256i64 - b1 - 108i64) << 16u32
            } else if op == 28i64 {
                var w = be16(d, frames[depth].pos)
                frames[depth].pos += 2usize
                if w >= 32768i64 { w = w - 65536i64 }
                v = w << 16u32
            } else {
                var w = be32(d, frames[depth].pos)
                frames[depth].pos += 4usize
                if w >= 2147483648i64 { w = w - 4294967296i64 }
                v = w
            }
            if sp >= 96usize { ret false }
            st[sp] = v
            sp += 1usize
            continue
        }
        if op == 1i64 || op == 18i64 {
            if !e.mask_valid { do_stems(e, st[0usize..96usize], sp, true) }
            sp = 0usize
        } else if op == 3i64 || op == 23i64 {
            if !e.mask_valid { do_stems(e, st[0usize..96usize], sp, false) }
            sp = 0usize
        } else if op == 19i64 || op == 20i64 {
            if sp > 1usize && e.mask_valid {
                // hints are never added after the mask is read (the C leaves the mask bytes unread here; real fonts do not do this)
                sp = 0usize
            } else {
                do_stems(e, st[0usize..96usize], sp, false)
                sp = 0usize
                let total = e.hn + e.vn
                let bytes = (total + 7usize) / 8usize
                let at_mask = frames[depth].pos
                frames[depth].pos += bytes
                var bits: [96]bool = zero
                var k = 0usize
                while k < total && k < 96usize {
                    let byte = d[at_mask + k / 8usize]
                    bits[k] = (byte & u8(128u32 >> u32(k % 8usize))) != 0u8
                    k += 1usize
                }
                if op == 19i64 {
                    e.mask = bits
                    e.mask_valid = true
                    e.mask_new = true
                } else {
                    // a counter mask places and locks the stems it names in a map of its own; the positions stay on the stems
                    e.counter.scale = e.scale
                    e.counter.valid = false
                    build_map(e, &e.counter, bits, false, false)
                }
            }
        } else if op == 21i64 {
            if sp < 2usize { ret false }
            e.ix = e.ix + st[sp - 2usize]
            e.iy = e.iy + st[sp - 1usize]
            path_move_to(e, e.ix, e.iy)
            sp = 0usize
        } else if op == 22i64 {
            if sp < 1usize { ret false }
            e.ix = e.ix + st[sp - 1usize]
            path_move_to(e, e.ix, e.iy)
            sp = 0usize
        } else if op == 4i64 {
            if sp < 1usize { ret false }
            e.iy = e.iy + st[sp - 1usize]
            path_move_to(e, e.ix, e.iy)
            sp = 0usize
        } else if op == 5i64 {
            var k = 0usize
            while k + 1usize < sp {
                e.ix = e.ix + st[k]
                e.iy = e.iy + st[k + 1usize]
                path_line_to(e, e.ix, e.iy)
                k += 2usize
            }
            sp = 0usize
        } else if op == 6i64 || op == 7i64 {
            var along_x = op == 6i64
            var k = 0usize
            while k < sp {
                if along_x { e.ix = e.ix + st[k] } else { e.iy = e.iy + st[k] }
                path_line_to(e, e.ix, e.iy)
                along_x = !along_x
                k += 1usize
            }
            sp = 0usize
        } else if op == 8i64 {
            var k = 0usize
            while k + 6usize <= sp {
                rr_curve(e, st[0usize..96usize], k)
                k += 6usize
            }
            sp = 0usize
        } else if op == 27i64 {
            var k = 0usize
            var dy1: i64 = 0i64
            if sp & 1usize == 1usize {
                dy1 = st[0usize]
                k = 1usize
            }
            while k + 4usize <= sp {
                let x1 = e.ix + st[k]
                let y1 = e.iy + dy1
                let x2 = x1 + st[k + 1usize]
                let y2 = y1 + st[k + 2usize]
                let x3 = x2 + st[k + 3usize]
                path_curve_to(e, x1, y1, x2, y2, x3, y2)
                e.ix = x3
                e.iy = y2
                dy1 = 0i64
                k += 4usize
            }
            sp = 0usize
        } else if op == 26i64 {
            var k = 0usize
            var dx1: i64 = 0i64
            if sp & 1usize == 1usize {
                dx1 = st[0usize]
                k = 1usize
            }
            while k + 4usize <= sp {
                let x1 = e.ix + dx1
                let y1 = e.iy + st[k]
                let x2 = x1 + st[k + 1usize]
                let y2 = y1 + st[k + 2usize]
                let y3 = y2 + st[k + 3usize]
                path_curve_to(e, x1, y1, x2, y2, x2, y3)
                e.ix = x2
                e.iy = y3
                dx1 = 0i64
                k += 4usize
            }
            sp = 0usize
        } else if op == 30i64 || op == 31i64 {
            var horizontal = op == 31i64
            var k = 0usize
            while k + 4usize <= sp {
                let last = (sp - k) == 5usize
                var x1: i64 = 0i64
                var y1: i64 = 0i64
                var x2: i64 = 0i64
                var y2: i64 = 0i64
                var x3: i64 = 0i64
                var y3: i64 = 0i64
                if horizontal {
                    x1 = e.ix + st[k]
                    y1 = e.iy
                    x2 = x1 + st[k + 1usize]
                    y2 = y1 + st[k + 2usize]
                    y3 = y2 + st[k + 3usize]
                    x3 = x2
                    if last { x3 = x2 + st[k + 4usize] }
                } else {
                    x1 = e.ix
                    y1 = e.iy + st[k]
                    x2 = x1 + st[k + 1usize]
                    y2 = y1 + st[k + 2usize]
                    x3 = x2 + st[k + 3usize]
                    y3 = y2
                    if last { y3 = y2 + st[k + 4usize] }
                }
                path_curve_to(e, x1, y1, x2, y2, x3, y3)
                e.ix = x3
                e.iy = y3
                horizontal = !horizontal
                k += 4usize
            }
            sp = 0usize
        } else if op == 24i64 {
            var k = 0usize
            while k + 6usize + 2usize <= sp {
                rr_curve(e, st[0usize..96usize], k)
                k += 6usize
            }
            e.ix = e.ix + st[k]
            e.iy = e.iy + st[k + 1usize]
            path_line_to(e, e.ix, e.iy)
            sp = 0usize
        } else if op == 25i64 {
            var k = 0usize
            while k + 2usize + 6usize <= sp {
                e.ix = e.ix + st[k]
                e.iy = e.iy + st[k + 1usize]
                path_line_to(e, e.ix, e.iy)
                k += 2usize
            }
            rr_curve(e, st[0usize..96usize], k)
            sp = 0usize
        } else if op == 10i64 || op == 29i64 {
            if sp < 1usize || depth + 1usize >= 12usize { ret false }
            sp -= 1usize
            let n = i64(st[sp] >> 16u32)
            var at_subr = c.lsubr_at
            if op == 29i64 { at_subr = c.gsubr_at }
            if at_subr == 0usize { ret false }
            let count = index_count(d, at_subr)
            let want = n + i64(bias_of(count))
            if want < 0i64 || usize(want) >= count { ret false }
            let (s0, s1) = index_range(d, at_subr, usize(want))
            depth += 1usize
            frames[depth] = Frame { pos: s0, end: s1 }
        } else if op == 11i64 {
            if depth == 0usize { ret true }
            depth -= 1usize
        } else if op == 14i64 {
            path_close(e)
            ret !e.failed
        } else if op == 12i64 {
            let sub = i64(d[frames[depth].pos])
            frames[depth].pos += 1usize
            if sub == 34i64 || sub == 35i64 || sub == 36i64 || sub == 37i64 {
                if !flex(e, st[0usize..96usize], sp, sub) { ret false }
                sp = 0usize
            } else {
                ret false
            }
        } else {
            ret false
        }
    }
    ret false
}

// flex (35), hflex (34), hflex1 (36), flex1 (37): two curves.
fn flex(e: *Engine, d: []i64, sp: usize, sub: i64) -> bool {
    let cx = e.ix
    let cy = e.iy
    var px: [6]i64 = zero
    var py: [6]i64 = zero
    if sub == 35i64 {
        if sp < 12usize { ret false }
        var x = cx
        var y = cy
        var k = 0usize
        while k < 6usize {
            x = x + d[2usize * k]
            y = y + d[2usize * k + 1usize]
            px[k] = x
            py[k] = y
            k += 1usize
        }
    } else if sub == 34i64 {
        if sp < 7usize { ret false }
        px[0usize] = cx + d[0usize]
        py[0usize] = cy
        px[1usize] = px[0usize] + d[1usize]
        py[1usize] = py[0usize] + d[2usize]
        px[2usize] = px[1usize] + d[3usize]
        py[2usize] = py[1usize]
        px[3usize] = px[2usize] + d[4usize]
        py[3usize] = py[1usize]
        px[4usize] = px[3usize] + d[5usize]
        py[4usize] = cy
        px[5usize] = px[4usize] + d[6usize]
        py[5usize] = cy
    } else if sub == 36i64 {
        if sp < 9usize { ret false }
        px[0usize] = cx + d[0usize]
        py[0usize] = cy + d[1usize]
        px[1usize] = px[0usize] + d[2usize]
        py[1usize] = py[0usize] + d[3usize]
        px[2usize] = px[1usize] + d[4usize]
        py[2usize] = py[1usize]
        px[3usize] = px[2usize] + d[5usize]
        py[3usize] = py[1usize]
        px[4usize] = px[3usize] + d[6usize]
        py[4usize] = py[3usize] + d[7usize]
        px[5usize] = px[4usize] + d[8usize]
        py[5usize] = cy
    } else {
        if sp < 11usize { ret false }
        px[0usize] = cx + d[0usize]
        py[0usize] = cy + d[1usize]
        px[1usize] = px[0usize] + d[2usize]
        py[1usize] = py[0usize] + d[3usize]
        px[2usize] = px[1usize] + d[4usize]
        py[2usize] = py[1usize] + d[5usize]
        px[3usize] = px[2usize] + d[6usize]
        py[3usize] = py[2usize] + d[7usize]
        px[4usize] = px[3usize] + d[8usize]
        py[4usize] = py[3usize] + d[9usize]
        if abs64(px[4usize] - cx) > abs64(py[4usize] - cy) {
            px[5usize] = px[4usize] + d[10usize]
            py[5usize] = cy
        } else {
            px[5usize] = cx
            py[5usize] = py[4usize] + d[10usize]
        }
    }
    path_curve_to(e, px[0usize], py[0usize], px[1usize], py[1usize], px[2usize], py[2usize])
    path_curve_to(e, px[3usize], py[3usize], px[4usize], py[4usize], px[5usize], py[5usize])
    e.ix = px[5usize]
    e.iy = py[5usize]
    ret true
}

// The outline of glyph `gid` at `size26` (the size in 26.6 pixels, as FT_Set_Char_Size gets it) hinted, or with `hinted` false in
// unhinted font units (16.16). `e` is scratch; `out` receives the result. False when the glyph cannot be read.
fn outline(e: *Engine, c: *const Cff, gid: usize, size26: i64, hinted: bool, out: *Outline) -> bool {
    var scale = ONE
    if hinted {
        let y_scale = ((size26 << 16u32) + c.upem / 2i64) / c.upem
        scale = (y_scale + 32i64) / 64i64
        if scale < 1i64 { ret false }
    }
    e.cff = c
    e.scale = scale
    e.hinted = hinted
    blues_init(&e.blues, c, scale)
    e.hn = 0usize
    e.vn = 0usize
    e.mask_valid = false
    e.mask_new = false
    e.initial.count = 0usize
    e.initial.valid = false
    e.initial.scale = scale
    e.first.count = 0usize
    e.first.valid = false
    e.first.scale = scale
    e.cur.count = 0usize
    e.cur.valid = false
    e.cur.scale = scale
    e.counter.count = 0usize
    e.counter.valid = false
    e.counter.scale = scale
    e.ix = 0i64
    e.iy = 0i64
    e.cur_x = 0i64
    e.cur_y = 0i64
    e.start_x = 0i64
    e.start_y = 0i64
    e.move_pending = true
    e.path_open = false
    e.closing = false
    e.queued = false
    e.prev_curve = false
    e.ds_x = 0i64
    e.ds_y = 0i64
    e.failed = false
    out.n = 0usize
    out.pn = 0usize
    out.hinted = hinted
    e.out = out
    ret run(e, gid)
}
