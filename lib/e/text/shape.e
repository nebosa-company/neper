// OpenType shaping over caller-provided font bytes: characters become glyph ids through
// `cmap`, GSUB substitutes (single and ligature lookups, reached through an extension
// where the font uses one), `hmtx` supplies the advances and GPOS pair adjustment (or a
// format 0 `kern` table when the font has no GPOS) moves them. Everything is read from
// the bytes as given and the toolchain's pinned Unicode tables, so two shapings of the
// same text over the same font agree everywhere; nothing is discovered, cached or read
// from disk.
//
// Advances and offsets are in em units, the font unit divided by `unitsPerEm`, so a
// caller multiplies by its point size once. `cluster` is the byte offset in `source` of
// the character a glyph came from, a ligature keeping its first component's. Lookup
// types other than single, ligature and pair adjustment (contextual, mark attachment)
// are skipped rather than refused: the run is still right for every glyph they would
// not have touched. `Unsupported` is a `cmap` with no format 4 or 12 subtable.
//
// Features: `ccmp`, `locl`, `rlig`, `liga`, `clig` and `kern` are on for the whole run,
// as is the script's required feature; a `Feature` in `Options` with a nonzero `value`
// enables its tag over `[start, end)` and with `value` 0 turns it off. The script is
// looked up by `options.script` and falls back to `DFLT`; `language` selects a LangSys
// only when it is a four-byte tag the script lists.
//
// A malformed table never traps: every read past a table's end answers zero, which can
// only mislead a shaping, not crash it. `validate_font` is the caller's guard before
// that: it demands a well-formed table directory and the five tables shaping needs.

use e.mem
use e.text.unicode
use e.text.utf8

type FontId = u32
type Direction = enum u8 { LeftToRight, RightToLeft }
type Font = struct { id: FontId, data: []const u8, face_index: u32 }
type Feature = struct { tag: u32, value: u32, start: usize, end: usize }
type Glyph = struct { id: u32, cluster: usize, advance_x: f32, advance_y: f32, offset_x: f32, offset_y: f32 }
type Run = struct { font: FontId, direction: Direction, script: u32, language: str, glyphs: []const Glyph }
type Options = struct { direction: Direction, script: u32, language: str, features: []const Feature }
error InvalidFont
error InvalidText
error Unsupported
error TooLarge

const MAX_SOURCE: usize = 16777216usize
const NONE: usize = 18446744073709551615usize
const TAG_HEAD: u32 = 1751474532u32
const TAG_HHEA: u32 = 1751672161u32
const TAG_HMTX: u32 = 1752003704u32
const TAG_MAXP: u32 = 1835104368u32
const TAG_CMAP: u32 = 1668112752u32
const TAG_GSUB: u32 = 1196643650u32
const TAG_GPOS: u32 = 1196445523u32
const TAG_KERN: u32 = 1801810542u32
const TAG_DFLT: u32 = 1145457748u32
const TAG_TTCF: u32 = 1953784678u32
const TAG_CCMP: u32 = 1663443056u32
const TAG_LOCL: u32 = 1819239276u32
const TAG_RLIG: u32 = 1919707495u32
const TAG_LIGA: u32 = 1818847073u32
const TAG_CLIG: u32 = 1668049255u32

type Table = struct { at: usize, len: usize }

// The glyphs of a run while lookups still change them, with positions in font units.
type Buffer = struct { gid: []u32, cluster: []usize, adv_x: []i32, adv_y: []i32, off_x: []i32, off_y: []i32, count: usize }

fn u16_at(d: []const u8, at: usize) -> u32 {
    if at + 2usize > d.len { ret 0u32 }
    ret (u32(d[at]) << 8u32) | u32(d[at + 1usize])
}

fn i16_at(d: []const u8, at: usize) -> i32 {
    let v = u16_at(d, at)
    if v >= 32768u32 { ret i32(v) - 65536i32 }
    ret i32(v)
}

fn u32_at(d: []const u8, at: usize) -> u32 {
    if at + 4usize > d.len { ret 0u32 }
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

// The offset table of the face: the file's start, or the collection's entry for it.
fn face_offset(font: Font) -> (usize, err) {
    if u32_at(font.data, 0usize) == TAG_TTCF {
        if font.face_index >= u32_at(font.data, 8usize) { ret (0usize, InvalidFont) }
        ret (usize(u32_at(font.data, 12usize + 4usize * usize(font.face_index))), ok)
    }
    if font.face_index != 0u32 { ret (0usize, InvalidFont) }
    ret (0usize, ok)
}

fn find_table(font: Font, tag: u32) -> (Table, bool) {
    let (base, base_error) = face_offset(font)
    if base_error != ok { ret (zero, false) }
    let count = usize(u16_at(font.data, base + 4usize))
    var i = 0usize
    while i < count {
        let record = base + 12usize + 16usize * i
        if u32_at(font.data, record) == tag {
            let at = usize(u32_at(font.data, record + 8usize))
            let len = usize(u32_at(font.data, record + 12usize))
            if at + len > font.data.len { ret (zero, false) }
            ret (Table { at: at, len: len }, true)
        }
        i += 1usize
    }
    ret (zero, false)
}

fn validate_font(font: Font) -> err {
    if font.data.len < 12usize { ret InvalidFont }
    let (base, base_error) = face_offset(font)
    if base_error != ok { ret base_error }
    let magic = u32_at(font.data, base)
    if magic != 65536u32 && magic != 1330926671u32 && magic != 1953658213u32 { ret InvalidFont }
    let count = usize(u16_at(font.data, base + 4usize))
    if base + 12usize + 16usize * count > font.data.len { ret InvalidFont }
    var i = 0usize
    while i < count {
        let record = base + 12usize + 16usize * i
        if usize(u32_at(font.data, record + 8usize)) + usize(u32_at(font.data, record + 12usize)) > font.data.len { ret InvalidFont }
        i += 1usize
    }
    let (head, has_head) = find_table(font, TAG_HEAD)
    let (hhea, has_hhea) = find_table(font, TAG_HHEA)
    let (_, has_hmtx) = find_table(font, TAG_HMTX)
    let (maxp, has_maxp) = find_table(font, TAG_MAXP)
    let (cmap, has_cmap) = find_table(font, TAG_CMAP)
    if !has_head || !has_hhea || !has_hmtx || !has_maxp || !has_cmap { ret InvalidFont }
    if head.len < 54usize || hhea.len < 36usize || maxp.len < 6usize || cmap.len < 4usize { ret InvalidFont }
    if u16_at(font.data, head.at + 18usize) == 0u32 { ret InvalidFont }
    ret ok
}

// The best Unicode subtable: a full-repertoire one over a BMP one, format 4 or 12 only.
fn cmap_subtable(d: []const u8, cmap: Table) -> (usize, bool) {
    let count = usize(u16_at(d, cmap.at + 2usize))
    var best = 0usize
    var best_score = 0u32
    var i = 0usize
    while i < count {
        let record = cmap.at + 4usize + 8usize * i
        let platform = u16_at(d, record)
        let encoding = u16_at(d, record + 2usize)
        let at = cmap.at + usize(u32_at(d, record + 4usize))
        let format = u16_at(d, at)
        var score = 0u32
        if platform == 3u32 && encoding == 10u32 { score = 4u32 }
        if platform == 0u32 && (encoding == 4u32 || encoding == 6u32) { score = 3u32 }
        if platform == 3u32 && encoding == 1u32 { score = 2u32 }
        if platform == 0u32 && encoding < 4u32 { score = 1u32 }
        if (format == 4u32 || format == 12u32) && score > best_score {
            best = at
            best_score = score
        }
        i += 1usize
    }
    ret (best, best_score != 0u32)
}

fn glyph_of(d: []const u8, sub: usize, scalar: u32) -> u32 {
    let format = u16_at(d, sub)
    if format == 12u32 {
        let groups = usize(u32_at(d, sub + 12usize))
        var g = 0usize
        while g < groups {
            let record = sub + 16usize + 12usize * g
            let start = u32_at(d, record)
            let end = u32_at(d, record + 4usize)
            if scalar >= start && scalar <= end { ret u32_at(d, record + 8usize) + (scalar - start) }
            g += 1usize
        }
        ret 0u32
    }
    if scalar > 65535u32 { ret 0u32 }
    let seg_x2 = usize(u16_at(d, sub + 6usize))
    let ends = sub + 14usize
    let starts = sub + 16usize + seg_x2
    let deltas = sub + 16usize + 2usize * seg_x2
    let range_offsets = sub + 16usize + 3usize * seg_x2
    var i = 0usize
    while i * 2usize < seg_x2 {
        if scalar <= u16_at(d, ends + 2usize * i) {
            let start = u16_at(d, starts + 2usize * i)
            if scalar < start { ret 0u32 }
            let delta = u16_at(d, deltas + 2usize * i)
            let range_at = range_offsets + 2usize * i
            let range = usize(u16_at(d, range_at))
            if range == 0usize { ret (scalar + delta) & 65535u32 }
            let glyph = u16_at(d, range_at + range + 2usize * usize(scalar - start))
            if glyph == 0u32 { ret 0u32 }
            ret (glyph + delta) & 65535u32
        }
        i += 1usize
    }
    ret 0u32
}

// The position of `gid` in a coverage table, NONE when absent.
fn coverage_index(d: []const u8, cov: usize, gid: u32) -> usize {
    let format = u16_at(d, cov)
    let count = usize(u16_at(d, cov + 2usize))
    if format == 1u32 {
        var lo = 0usize
        var hi = count
        while lo < hi {
            let mid = (lo + hi) / 2usize
            let here = u16_at(d, cov + 4usize + 2usize * mid)
            if here == gid { ret mid }
            if here < gid { lo = mid + 1usize } else { hi = mid }
        }
        ret NONE
    }
    if format != 2u32 { ret NONE }
    var r = 0usize
    while r < count {
        let record = cov + 4usize + 6usize * r
        let start = u16_at(d, record)
        let end = u16_at(d, record + 2usize)
        if gid >= start && gid <= end { ret usize(u16_at(d, record + 4usize) + (gid - start)) }
        r += 1usize
    }
    ret NONE
}

fn class_of(d: []const u8, def: usize, gid: u32) -> u32 {
    let format = u16_at(d, def)
    if format == 1u32 {
        let start = u16_at(d, def + 2usize)
        let count = u16_at(d, def + 4usize)
        if gid < start || gid - start >= count { ret 0u32 }
        ret u16_at(d, def + 6usize + 2usize * usize(gid - start))
    }
    if format != 2u32 { ret 0u32 }
    let ranges = usize(u16_at(d, def + 2usize))
    var r = 0usize
    while r < ranges {
        let record = def + 4usize + 6usize * r
        if gid >= u16_at(d, record) && gid <= u16_at(d, record + 2usize) { ret u16_at(d, record + 4usize) }
        r += 1usize
    }
    ret 0u32
}

// The LangSys the options select in a GSUB or GPOS table, and its feature list.
fn langsys_of(d: []const u8, table: Table, options: Options) -> (usize, usize, bool) {
    let scripts = table.at + usize(u16_at(d, table.at + 4usize))
    let features = table.at + usize(u16_at(d, table.at + 6usize))
    let count = usize(u16_at(d, scripts))
    var script = 0usize
    var i = 0usize
    while i < count {
        let record = scripts + 2usize + 6usize * i
        let tag = u32_at(d, record)
        if tag == options.script || (tag == TAG_DFLT && script == 0usize) { script = scripts + usize(u16_at(d, record + 4usize)) }
        if tag == options.script { break }
        i += 1usize
    }
    if script == 0usize { ret (0usize, features, false) }
    var langsys = 0usize
    if options.language.len == 4usize {
        let wanted = u32_at(options.language, 0usize)
        let langs = usize(u16_at(d, script + 2usize))
        var l = 0usize
        while l < langs {
            let record = script + 4usize + 6usize * l
            if u32_at(d, record) == wanted { langsys = script + usize(u16_at(d, record + 4usize)) }
            l += 1usize
        }
    }
    if langsys == 0usize {
        let default_at = usize(u16_at(d, script))
        if default_at == 0usize { ret (0usize, features, false) }
        langsys = script + default_at
    }
    ret (langsys, features, true)
}

fn default_feature(tag: u32, positioning: bool) -> bool {
    if positioning { ret tag == TAG_KERN }
    ret tag == TAG_CCMP || tag == TAG_LOCL || tag == TAG_RLIG || tag == TAG_LIGA || tag == TAG_CLIG
}

// Widens the range `lo[index]..hi[index]` over which a lookup applies.
fn enable_lookup(lo: []usize, hi: []usize, index: usize, start: usize, end: usize) {
    if index >= lo.len { ret }
    if lo[index] == NONE {
        lo[index] = start
        hi[index] = end
        ret
    }
    if start < lo[index] { lo[index] = start }
    if end > hi[index] { hi[index] = end }
}

// Every lookup an enabled feature names, with the byte range it applies to.
fn mark_lookups(d: []const u8, table: Table, options: Options, positioning: bool, source_len: usize, lo: []usize, hi: []usize) {
    let (langsys, features, found) = langsys_of(d, table, options)
    if !found { ret }
    let required = usize(u16_at(d, langsys + 2usize))
    let count = usize(u16_at(d, langsys + 4usize))
    var i = 0usize
    while i <= count {
        var feature_index = required
        if i < count { feature_index = usize(u16_at(d, langsys + 6usize + 2usize * i)) }
        i += 1usize
        if feature_index == 65535usize { continue }
        let record = features + 2usize + 6usize * feature_index
        let tag = u32_at(d, record)
        var enabled = default_feature(tag, positioning) || feature_index == required
        var start = 0usize
        var end = source_len
        var f = 0usize
        while f < options.features.len {
            let request = options.features[f]
            if request.tag == tag {
                if request.value == 0u32 {
                    enabled = false
                } else if !enabled {
                    enabled = true
                    start = request.start
                    end = request.end
                } else {
                    if request.start < start { start = request.start }
                    if request.end > end { end = request.end }
                }
            }
            f += 1usize
        }
        if !enabled { continue }
        let feature = features + usize(u16_at(d, record + 4usize))
        let lookups = usize(u16_at(d, feature + 2usize))
        var l = 0usize
        while l < lookups {
            enable_lookup(lo, hi, usize(u16_at(d, feature + 4usize + 2usize * l)), start, end)
            l += 1usize
        }
    }
}

fn in_range(b: *Buffer, i: usize, lo: usize, hi: usize) -> bool {
    ret b.cluster[i] >= lo && b.cluster[i] < hi
}

fn single_subst(d: []const u8, sat: usize, b: *Buffer, lo: usize, hi: usize) {
    let format = u16_at(d, sat)
    let cov = sat + usize(u16_at(d, sat + 2usize))
    var i = 0usize
    while i < b.count {
        if in_range(b, i, lo, hi) {
            let ci = coverage_index(d, cov, b.gid[i])
            if ci != NONE {
                if format == 1u32 {
                    b.gid[i] = (b.gid[i] + u16_at(d, sat + 4usize)) & 65535u32
                } else if ci < usize(u16_at(d, sat + 4usize)) {
                    b.gid[i] = u16_at(d, sat + 6usize + 2usize * ci)
                }
            }
        }
        i += 1usize
    }
}

// The components after `i` match a ligature's; the ligature takes the first slot.
fn ligate(d: []const u8, lig: usize, b: *Buffer, i: usize) -> bool {
    let components = usize(u16_at(d, lig + 2usize))
    if components == 0usize || i + components > b.count { ret false }
    var k = 1usize
    while k < components {
        if b.gid[i + k] != u16_at(d, lig + 4usize + 2usize * (k - 1usize)) { ret false }
        k += 1usize
    }
    b.gid[i] = u16_at(d, lig)
    var m = i + 1usize
    while m + components - 1usize < b.count {
        b.gid[m] = b.gid[m + components - 1usize]
        b.cluster[m] = b.cluster[m + components - 1usize]
        m += 1usize
    }
    b.count -= components - 1usize
    ret true
}

fn ligature_subst(d: []const u8, sat: usize, b: *Buffer, lo: usize, hi: usize) {
    if u16_at(d, sat) != 1u32 { ret }
    let cov = sat + usize(u16_at(d, sat + 2usize))
    let sets = usize(u16_at(d, sat + 4usize))
    var i = 0usize
    while i < b.count {
        if in_range(b, i, lo, hi) {
            let ci = coverage_index(d, cov, b.gid[i])
            if ci != NONE && ci < sets {
                let set = sat + usize(u16_at(d, sat + 6usize + 2usize * ci))
                let ligatures = usize(u16_at(d, set))
                var j = 0usize
                while j < ligatures {
                    if ligate(d, set + usize(u16_at(d, set + 2usize + 2usize * j)), b, i) { break }
                    j += 1usize
                }
            }
        }
        i += 1usize
    }
}

fn value_size(format: u32) -> usize {
    var size = 0usize
    var bit = 0u32
    while bit < 8u32 {
        if ((format >> bit) & 1u32) != 0u32 { size += 2usize }
        bit += 1u32
    }
    ret size
}

// Applies a ValueRecord at `at` to glyph `i`; device offsets are counted, not used.
fn apply_value(d: []const u8, at: usize, format: u32, b: *Buffer, i: usize) {
    var here = at
    if (format & 1u32) != 0u32 {
        b.off_x[i] += i16_at(d, here)
        here += 2usize
    }
    if (format & 2u32) != 0u32 {
        b.off_y[i] += i16_at(d, here)
        here += 2usize
    }
    if (format & 4u32) != 0u32 {
        b.adv_x[i] += i16_at(d, here)
        here += 2usize
    }
    if (format & 8u32) != 0u32 { b.adv_y[i] += i16_at(d, here) }
}

fn pair_pos(d: []const u8, sat: usize, b: *Buffer, lo: usize, hi: usize) {
    let format = u16_at(d, sat)
    let cov = sat + usize(u16_at(d, sat + 2usize))
    let vf1 = u16_at(d, sat + 4usize)
    let vf2 = u16_at(d, sat + 6usize)
    let s1 = value_size(vf1)
    let s2 = value_size(vf2)
    var i = 0usize
    while i + 1usize < b.count {
        let ci = coverage_index(d, cov, b.gid[i])
        if ci == NONE || !in_range(b, i, lo, hi) {
            i += 1usize
            continue
        }
        let second = b.gid[i + 1usize]
        if format == 1u32 {
            if ci < usize(u16_at(d, sat + 8usize)) {
                let set = sat + usize(u16_at(d, sat + 10usize + 2usize * ci))
                let pairs = usize(u16_at(d, set))
                var r = 0usize
                while r < pairs {
                    let record = set + 2usize + r * (2usize + s1 + s2)
                    if u16_at(d, record) == second {
                        apply_value(d, record + 2usize, vf1, b, i)
                        apply_value(d, record + 2usize + s1, vf2, b, i + 1usize)
                        break
                    }
                    r += 1usize
                }
            }
        } else if format == 2u32 {
            let c1 = class_of(d, sat + usize(u16_at(d, sat + 8usize)), b.gid[i])
            let c2 = class_of(d, sat + usize(u16_at(d, sat + 10usize)), second)
            let c2_count = u16_at(d, sat + 14usize)
            if c1 < u16_at(d, sat + 12usize) && c2 < c2_count {
                let record = sat + 16usize + usize(c1 * c2_count + c2) * (s1 + s2)
                apply_value(d, record, vf1, b, i)
                apply_value(d, record + s1, vf2, b, i + 1usize)
            }
        }
        i += 1usize
    }
}

// One lookup's subtables, an extension unwrapped to the type it carries.
fn apply_lookup(d: []const u8, lookup: usize, positioning: bool, b: *Buffer, lo: usize, hi: usize) {
    let kind = u16_at(d, lookup)
    let subtables = usize(u16_at(d, lookup + 4usize))
    var s = 0usize
    while s < subtables {
        var sat = lookup + usize(u16_at(d, lookup + 6usize + 2usize * s))
        var here = kind
        let extension = (positioning && kind == 9u32) || (!positioning && kind == 7u32)
        if extension && u16_at(d, sat) == 1u32 {
            here = u16_at(d, sat + 2usize)
            sat = sat + usize(u32_at(d, sat + 4usize))
        }
        if positioning {
            if here == 2u32 { pair_pos(d, sat, b, lo, hi) }
        } else if here == 1u32 {
            single_subst(d, sat, b, lo, hi)
        } else if here == 4u32 {
            ligature_subst(d, sat, b, lo, hi)
        }
        s += 1usize
    }
}

// Every enabled lookup of a GSUB or GPOS table, in lookup order.
fn apply_table(a: *mem.Arena, d: []const u8, table: Table, options: Options, positioning: bool, source_len: usize, b: *Buffer) -> err {
    let list = table.at + usize(u16_at(d, table.at + 8usize))
    let count = usize(u16_at(d, list))
    let (lo, lo_error) = mem.alloc[usize](a, count)
    if lo_error != ok { ret lo_error }
    let (hi, hi_error) = mem.alloc[usize](a, count)
    if hi_error != ok { ret hi_error }
    var i = 0usize
    while i < count {
        lo[i] = NONE
        i += 1usize
    }
    mark_lookups(d, table, options, positioning, source_len, lo, hi)
    i = 0usize
    while i < count {
        if lo[i] != NONE { apply_lookup(d, list + usize(u16_at(d, list + 2usize + 2usize * i)), positioning, b, lo[i], hi[i]) }
        i += 1usize
    }
    ret ok
}

// A format 0 horizontal `kern` subtable, for a font with no GPOS.
fn legacy_kern(d: []const u8, kern: Table, b: *Buffer) {
    let tables = usize(u16_at(d, kern.at + 2usize))
    var at = kern.at + 4usize
    var t = 0usize
    while t < tables {
        let length = usize(u16_at(d, at + 2usize))
        let coverage = u16_at(d, at + 4usize)
        if (coverage >> 8u32) == 0u32 && (coverage & 1u32) != 0u32 {
            let pairs = usize(u16_at(d, at + 6usize))
            var i = 0usize
            while i + 1usize < b.count {
                var p = 0usize
                while p < pairs {
                    let record = at + 14usize + 6usize * p
                    if u16_at(d, record) == b.gid[i] && u16_at(d, record + 2usize) == b.gid[i + 1usize] {
                        b.adv_x[i] += i16_at(d, record + 4usize)
                        break
                    }
                    p += 1usize
                }
                i += 1usize
            }
        }
        if length == 0usize { break }
        at += length
        t += 1usize
    }
}

fn buffer(a: *mem.Arena, capacity: usize) -> (Buffer, err) {
    let (gid, gid_error) = mem.alloc[u32](a, capacity)
    if gid_error != ok { ret (zero, gid_error) }
    let (cluster, cluster_error) = mem.alloc[usize](a, capacity)
    if cluster_error != ok { ret (zero, cluster_error) }
    let (adv_x, adv_x_error) = mem.alloc[i32](a, capacity)
    if adv_x_error != ok { ret (zero, adv_x_error) }
    let (adv_y, adv_y_error) = mem.alloc[i32](a, capacity)
    if adv_y_error != ok { ret (zero, adv_y_error) }
    let (off_x, off_x_error) = mem.alloc[i32](a, capacity)
    if off_x_error != ok { ret (zero, off_x_error) }
    let (off_y, off_y_error) = mem.alloc[i32](a, capacity)
    if off_y_error != ok { ret (zero, off_y_error) }
    ret (Buffer { gid: gid, cluster: cluster, adv_x: adv_x, adv_y: adv_y, off_x: off_x, off_y: off_y, count: 0usize }, ok)
}

fn shape(a: *mem.Arena, font: Font, source: str, options: Options) -> (Run, err) {
    let font_error = validate_font(font)
    if font_error != ok { ret (zero, font_error) }
    if !utf8.validate(source) { ret (zero, InvalidText) }
    if source.len > MAX_SOURCE { ret (zero, TooLarge) }
    let d = font.data
    let (cmap, _) = find_table(font, TAG_CMAP)
    let (sub, has_sub) = cmap_subtable(d, cmap)
    if !has_sub { ret (zero, Unsupported) }
    let (made, buffer_error) = buffer(a, source.len)
    if buffer_error != ok { ret (zero, buffer_error) }
    var b = made
    var at = 0usize
    while at < source.len {
        let (scalar, width) = unicode.read_utf8(source, at)
        b.gid[b.count] = glyph_of(d, sub, scalar)
        b.cluster[b.count] = at
        b.count += 1usize
        at += width
    }
    let (gsub, has_gsub) = find_table(font, TAG_GSUB)
    if has_gsub && gsub.len >= 10usize {
        let gsub_error = apply_table(a, d, gsub, options, false, source.len, &b)
        if gsub_error != ok { ret (zero, gsub_error) }
    }
    let (head, _) = find_table(font, TAG_HEAD)
    let (hhea, _) = find_table(font, TAG_HHEA)
    let (hmtx, _) = find_table(font, TAG_HMTX)
    let metrics = usize(u16_at(d, hhea.at + 34usize))
    var i = 0usize
    while i < b.count {
        var row = usize(b.gid[i])
        if row >= metrics && metrics > 0usize { row = metrics - 1usize }
        var advance = 0i32
        if metrics > 0usize { advance = i32(u16_at(d, hmtx.at + 4usize * row)) }
        b.adv_x[i] = advance
        b.adv_y[i] = 0i32
        b.off_x[i] = 0i32
        b.off_y[i] = 0i32
        i += 1usize
    }
    let (gpos, has_gpos) = find_table(font, TAG_GPOS)
    if has_gpos && gpos.len >= 10usize {
        let gpos_error = apply_table(a, d, gpos, options, true, source.len, &b)
        if gpos_error != ok { ret (zero, gpos_error) }
    } else {
        let (kern, has_kern) = find_table(font, TAG_KERN)
        if has_kern { legacy_kern(d, kern, &b) }
    }
    let (glyphs, glyphs_error) = mem.alloc[Glyph](a, b.count)
    if glyphs_error != ok { ret (zero, glyphs_error) }
    let em = f32(i32(u16_at(d, head.at + 18usize)))
    i = 0usize
    while i < b.count {
        var from = i
        if options.direction == .RightToLeft { from = b.count - 1usize - i }
        glyphs[i] = Glyph {
            id: b.gid[from],
            cluster: b.cluster[from],
            advance_x: f32(b.adv_x[from]) / em,
            advance_y: f32(b.adv_y[from]) / em,
            offset_x: f32(b.off_x[from]) / em,
            offset_y: f32(b.off_y[from]) / em,
        }
        i += 1usize
    }
    ret (Run { font: font.id, direction: options.direction, script: options.script, language: options.language, glyphs: glyphs }, ok)
}
