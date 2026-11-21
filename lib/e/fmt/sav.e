// SPSS .sav and .zsav reader (the layout ReadStat reads for haven): the header, variable records with
// long names, very long strings (255-byte segments), formats, display widths, user-missing values, value
// labels (short and long strings), uncompressed, bytecode-compressed and zlib-compressed data, both byte
// orders. Numbers come back as the raw f64 (NaN for system missing, also for the highest and lowest
// sentinels) and `value` applies haven's date and time shift; strings come back as UTF-8 text.
//
// Not here: character sets other than UTF-8 (bytes above 0x7f pass through), multiple response sets,
// document and attribute records. `write` is ReadStat's writer (what haven's write_sav runs), plain, bytecode
// or zlib, little-endian; it equals haven's bytes for the files tests/data/haven/s1.sav, s2.sav and s3.zsav.

use e.algo.deflate as deflate
use e.mem

error BadFile
error Unsupported

const SYSMIS: u64 = 18442240474082181119u64
const HIGHEST: u64 = 9218868437227405311u64
const LOWEST: u64 = 18442240474082181118u64
const HEADER: usize = 176usize

type Sav = struct {
    nvars: usize,
    nobs: usize,
    compression: i64,
    big: bool,
    weight: i64,
    label: str,
    names: []str,
    varlabels: []str,
    formats: []str,
    is_text: []u8,
    kind: []u8,
    display_width: []i64,
    miss_count: []u8,
    miss_range: []u8,
    miss_num: []f64,
    miss_text: []str,
    label_set: []i64,
    num: []f64,
    text: []str,
    set_first: []usize,
    set_count: []usize,
    entry_num: []f64,
    entry_text: []str,
    entry_label: []str,
    fcode: []i64,
    uwidth: []i64,
    measure: []i64,
    align: []i64,
    dwraw: []i64,
    stamp: str,
}

type Rd = struct { d: []const u8, big: bool }

fn u32_at(r: *const Rd, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 4usize {
        var idx = i
        if r.big { idx = 3usize - i }
        v = v | (u64(r.d[at + idx]) << u64(8usize * i))
        i += 1usize
    }
    ret v
}

fn u64_at(r: *const Rd, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        var idx = i
        if r.big { idx = 7usize - i }
        v = v | (u64(r.d[at + idx]) << u64(8usize * i))
        i += 1usize
    }
    ret v
}

fn i32_at(r: *const Rd, at: usize) -> i64 {
    let v = u32_at(r, at)
    if v >= 2147483648u64 { ret i64(v) - 4294967296i64 }
    ret i64(v)
}

fn text_of(b: []const u8) -> str {
    var s: str = zero
    s = b
    ret s
}

// the bytes with trailing spaces and NULs dropped (ReadStat's readstat_convert)
fn trimmed(b: []const u8) -> str {
    var n = b.len
    while n > 0usize && (b[n - 1usize] == 32u8 || b[n - 1usize] == 0u8) { n -= 1usize }
    ret text_of(b[..n])
}

fn same_ci(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        var p = x[i]
        var q = y[i]
        if p >= 97u8 && p <= 122u8 { p = p - 32u8 }
        if q >= 97u8 && q <= 122u8 { q = q - 32u8 }
        if p != q { ret false }
        i += 1usize
    }
    ret true
}

fn same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// strcmp order of two byte strings
fn cmp_text(x: str, y: str) -> i64 {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] {
            if x[i] < y[i] { ret -1i64 }
            ret 1i64
        }
        i += 1usize
    }
    if x.len < y.len { ret -1i64 }
    if x.len > y.len { ret 1i64 }
    ret 0i64
}

fn bits_to_f64(bits: u64) -> f64 { ret mem.bitcast[f64](bits) }

fn put_cell(buf: []u8, at: usize, bits: u64, big: bool) {
    var i = 0usize
    while i < 8usize {
        var idx = i
        if big { idx = 7usize - i }
        buf[at + idx] = u8((bits >> u64(8usize * i)) & 255u64)
        i += 1usize
    }
}

fn run_deflate(a: *mem.Arena, input: []const u8, out_size: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let (storage_size, storage_error) = deflate.decoder_storage(32768usize)
    if storage_error != ok { ret (nothing, storage_error) }
    let (storage, alloc_error) = mem.alloc[u8](a, storage_size)
    if alloc_error != ok { ret (nothing, alloc_error) }
    let (dec, dec_error) = deflate.decoder(storage, 32768usize)
    if dec_error != ok { ret (nothing, dec_error) }
    var decoder = dec
    let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
    if out_error != ok { ret (nothing, out_error) }
    let (consumed, written, status, decode_error) = deflate.decode(&decoder, input, out[..out_size + 1usize], true)
    if decode_error != ok { ret (nothing, BadFile) }
    if written != out_size { ret (nothing, BadFile) }
    ret (out[..out_size], ok)
}

// the bytecode stream as `cells` eight-byte cells in the file's byte order
fn unpack_rows(a: *mem.Arena, src: []const u8, cells: usize, bias: f64, big: bool) -> ([]u8, err) {
    var nothing: []u8 = zero
    let (out, out_error) = mem.alloc[u8](a, cells * 8usize + 8usize)
    if out_error != ok { ret (nothing, out_error) }
    var o = 0usize
    var p = 0usize
    while o < cells {
        if p + 8usize > src.len { ret (nothing, BadFile) }
        let ctl = p
        p += 8usize
        var i = 0usize
        while i < 8usize && o < cells {
            let c = src[ctl + i]
            if c == 252u8 { ret (nothing, BadFile) }
            if c == 253u8 {
                if p + 8usize > src.len { ret (nothing, BadFile) }
                var k = 0usize
                while k < 8usize {
                    out[o * 8usize + k] = src[p + k]
                    k += 1usize
                }
                p += 8usize
                o += 1usize
            } else if c == 254u8 {
                var k = 0usize
                while k < 8usize {
                    out[o * 8usize + k] = 32u8
                    k += 1usize
                }
                o += 1usize
            } else if c == 255u8 {
                put_cell(out, o * 8usize, SYSMIS, big)
                o += 1usize
            } else if c != 0u8 {
                put_cell(out, o * 8usize, mem.bitcast[u64](f64(c) - bias), big)
                o += 1usize
            }
            i += 1usize
        }
    }
    ret (out[..cells * 8usize], ok)
}

fn f_name(code: i64) -> str {
    if code == 1i64 { ret "A" }
    if code == 2i64 { ret "AHEX" }
    if code == 3i64 { ret "COMMA" }
    if code == 4i64 { ret "DOLLAR" }
    if code == 5i64 { ret "F" }
    if code == 6i64 { ret "IB" }
    if code == 7i64 { ret "PIBHEX" }
    if code == 8i64 { ret "P" }
    if code == 9i64 { ret "PIB" }
    if code == 10i64 { ret "PK" }
    if code == 11i64 { ret "RB" }
    if code == 12i64 { ret "RBHEX" }
    if code == 15i64 { ret "Z" }
    if code == 16i64 { ret "N" }
    if code == 17i64 { ret "E" }
    if code == 20i64 { ret "DATE" }
    if code == 21i64 { ret "TIME" }
    if code == 22i64 { ret "DATETIME" }
    if code == 23i64 { ret "ADATE" }
    if code == 24i64 { ret "JDATE" }
    if code == 25i64 { ret "DTIME" }
    if code == 26i64 { ret "WKDAY" }
    if code == 27i64 { ret "MONTH" }
    if code == 28i64 { ret "MOYR" }
    if code == 29i64 { ret "QYR" }
    if code == 30i64 { ret "WKYR" }
    if code == 31i64 { ret "PCT" }
    if code == 32i64 { ret "DOT" }
    if code == 33i64 { ret "CCA" }
    if code == 34i64 { ret "CCB" }
    if code == 35i64 { ret "CCC" }
    if code == 36i64 { ret "CCD" }
    if code == 37i64 { ret "CCE" }
    if code == 38i64 { ret "EDATE" }
    if code == 39i64 { ret "SDATE" }
    if code == 40i64 { ret "MTIME" }
    if code == 41i64 { ret "YMDHMS" }
    ret ""
}

fn put_int(out: []u8, at: usize, v: i64) -> usize {
    var digits: [24]u8 = zero
    var n = 0usize
    var x = v
    if x == 0i64 {
        digits[0usize] = 48u8
        n = 1usize
    }
    while x > 0i64 {
        digits[n] = u8(48i64 + x % 10i64)
        x = x / 10i64
        n += 1usize
    }
    var i = 0usize
    while i < n {
        out[at + i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret n
}

// ReadStat's spss_format: NAME width.decimals, NAME width, NAME, or empty for a type it has no name for
fn format_text(a: *mem.Arena, code: i64, width: i64, decimals: i64) -> (str, err) {
    var blank: str = zero
    let nm = f_name(code)
    if nm.len == 0usize { ret (blank, ok) }
    let (out, out_error) = mem.alloc[u8](a, nm.len + 48usize)
    if out_error != ok { ret (blank, out_error) }
    var n = 0usize
    while n < nm.len {
        out[n] = nm[n]
        n += 1usize
    }
    if decimals != 0i64 || code == 5i64 {
        n += put_int(out, n, width)
        out[n] = 46u8
        n += 1usize
        n += put_int(out, n, decimals)
    } else if width != 0i64 {
        n += put_int(out, n, width)
    }
    ret (text_of(out[..n]), ok)
}

fn has_prefix(s: str, p: str) -> bool {
    if s.len < p.len { ret false }
    var i = 0usize
    while i < p.len {
        if s[i] != p[i] { ret false }
        i += 1usize
    }
    ret true
}

// 0 plain, 1 date, 2 datetime, 3 time (haven's numType for SPSS)
fn kind_of(f: str) -> u8 {
    if has_prefix(f, "DATETIME") { ret 2u8 }
    if has_prefix(f, "DATE") || has_prefix(f, "ADATE") || has_prefix(f, "EDATE") || has_prefix(f, "JDATE") || has_prefix(f, "SDATE") { ret 1u8 }
    if has_prefix(f, "TIME") || has_prefix(f, "DTIME") { ret 3u8 }
    ret 0u8
}

// haven's adjustDatetimeToR for SPSS
fn value(s: *const Sav, row: usize, col: usize) -> f64 {
    let x = s.num[row * s.nvars + col]
    if x != x { ret x }
    let k = s.kind[col]
    if k == 2u8 { ret x - 141428.0f64 * 86400.0f64 }
    if k == 1u8 { ret x / 86400.0f64 - 141428.0f64 }
    ret x
}

// true when v falls in one of the column's user-missing values or ranges (numeric columns)
fn num_user_missing(s: *const Sav, col: usize, v: f64) -> bool {
    let n = usize(s.miss_count[col])
    if n == 0usize { ret false }
    var k = 0usize
    if s.miss_range[col] != 0u8 {
        if v >= s.miss_num[col * 3usize] && v <= s.miss_num[col * 3usize + 1usize] { ret true }
        if n == 3usize && v >= s.miss_num[col * 3usize + 2usize] && v <= s.miss_num[col * 3usize + 2usize] { ret true }
        ret false
    }
    while k < n {
        if v >= s.miss_num[col * 3usize + k] && v <= s.miss_num[col * 3usize + k] { ret true }
        k += 1usize
    }
    ret false
}

fn text_user_missing(s: *const Sav, col: usize, v: str) -> bool {
    let n = usize(s.miss_count[col])
    if n == 0usize { ret false }
    var k = 0usize
    if s.miss_range[col] != 0u8 {
        if cmp_text(v, s.miss_text[col * 3usize]) >= 0i64 && cmp_text(v, s.miss_text[col * 3usize + 1usize]) <= 0i64 { ret true }
        if n == 3usize && same(v, s.miss_text[col * 3usize + 2usize]) { ret true }
        ret false
    }
    while k < n {
        if same(v, s.miss_text[col * 3usize + k]) { ret true }
        k += 1usize
    }
    ret false
}

fn read(a: *mem.Arena, data: []const u8) -> (Sav, err) {
    var none: Sav = zero
    if data.len < HEADER + 8usize { ret (none, BadFile) }
    var rd = Rd { d: data, big: false }
    var version_ok = data[0usize] == 36u8 && data[1usize] == 70u8 && data[2usize] == 76u8
    if !version_ok { ret (none, BadFile) }
    if data[3usize] != 50u8 && data[3usize] != 51u8 { ret (none, BadFile) }
    let layout = u32_at(&rd, 64usize)
    if layout != 2u64 && layout != 3u64 { rd.big = true }
    let comp = i32_at(&rd, 72usize)
    let weight_at = i32_at(&rd, 76usize)
    let ncases = i32_at(&rd, 80usize)
    let bias = bits_to_f64(u64_at(&rd, 84usize))
    if ncases < 0i64 { ret (none, BadFile) }
    if comp < 0i64 || comp > 2i64 { ret (none, Unsupported) }

    // pass 1: count the records and entries so the arrays can be sized
    var at = HEADER
    var nvi = 0usize
    var nslots = 0usize
    var nsets = 0usize
    var nentries = 0usize
    var done = false
    while !done {
        if at + 4usize > data.len { ret (none, BadFile) }
        let rt = i64(u32_at(&rd, at))
        at += 4usize
        if rt == 2i64 {
            if at + 28usize > data.len { ret (none, BadFile) }
            let ty = i32_at(&rd, at)
            let has_label = i32_at(&rd, at + 4usize)
            var nm = i32_at(&rd, at + 8usize)
            if nm < 0i64 { nm = -nm }
            at += 28usize
            if has_label != 0i64 {
                let ll = usize(u32_at(&rd, at))
                at += 4usize + (ll + 3usize) / 4usize * 4usize
            }
            at += usize(nm) * 8usize
            nslots += 1usize
            if ty >= 0i64 { nvi += 1usize }
        } else if rt == 3i64 {
            let cnt = usize(u32_at(&rd, at))
            at += 4usize
            var j = 0usize
            while j < cnt {
                if at + 9usize > data.len { ret (none, BadFile) }
                let ul = usize(data[at + 8usize])
                at += 8usize + (ul + 8usize) / 8usize * 8usize
                j += 1usize
            }
            nsets += 1usize
            nentries += cnt
            if i64(u32_at(&rd, at)) != 4i64 { ret (none, BadFile) }
            let vc = usize(u32_at(&rd, at + 4usize))
            at += 8usize + vc * 4usize
        } else if rt == 6i64 {
            let nl = usize(u32_at(&rd, at))
            at += 4usize + nl * 80usize
        } else if rt == 7i64 {
            if at + 12usize > data.len { ret (none, BadFile) }
            let sub = i64(u32_at(&rd, at))
            let sz = usize(u32_at(&rd, at + 4usize))
            let cn = usize(u32_at(&rd, at + 8usize))
            at += 12usize
            if sub == 21i64 {
                // entries of the long-string value labels: name, width, count, then pairs
                var p = at
                let stop = at + sz * cn
                while p < stop {
                    let nl = usize(u32_at(&rd, p))
                    p += 4usize + nl + 4usize
                    let lc = usize(u32_at(&rd, p))
                    p += 4usize
                    nsets += 1usize
                    nentries += lc
                    var j = 0usize
                    while j < lc {
                        let vl = usize(u32_at(&rd, p))
                        p += 4usize + vl
                        let ll = usize(u32_at(&rd, p))
                        p += 4usize + ll
                        j += 1usize
                    }
                }
            }
            at += sz * cn
        } else if rt == 999i64 {
            at += 4usize
            done = true
        } else {
            ret (none, BadFile)
        }
    }
    let dstart = at
    if nvi == 0usize { ret (none, BadFile) }

    // per variable record (continuations excluded) arrays
    let (v_text, e1) = mem.alloc[u8](a, nvi)
    let (v_width, e2) = mem.alloc[usize](a, nvi)
    let (v_off, e3) = mem.alloc[usize](a, nvi)
    let (v_nseg, e4) = mem.alloc[usize](a, nvi)
    let (v_slen, e5) = mem.alloc[usize](a, nvi)
    let (v_pt, e6) = mem.alloc[i64](a, nvi * 3usize)
    let (v_name, e7) = mem.alloc[str](a, nvi)
    let (v_long, e8) = mem.alloc[str](a, nvi)
    let (v_label, e9) = mem.alloc[str](a, nvi)
    let (v_set, e10) = mem.alloc[i64](a, nvi)
    let (v_mc, e11) = mem.alloc[u8](a, nvi)
    let (v_mr, e12) = mem.alloc[u8](a, nvi)
    let (v_mnum, e13) = mem.alloc[f64](a, nvi * 3usize)
    let (v_mtxt, e14) = mem.alloc[str](a, nvi * 3usize)
    let (v_ty, e15) = mem.alloc[i64](a, nvi)
    if e15 != ok { ret (none, e15) }
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    if e5 != ok { ret (none, e5) }
    if e6 != ok { ret (none, e6) }
    if e7 != ok { ret (none, e7) }
    if e8 != ok { ret (none, e8) }
    if e9 != ok { ret (none, e9) }
    if e10 != ok { ret (none, e10) }
    if e11 != ok { ret (none, e11) }
    if e12 != ok { ret (none, e12) }
    if e13 != ok { ret (none, e13) }
    if e14 != ok { ret (none, e14) }
    let (s_first, f1) = mem.alloc[usize](a, nsets + 1usize)
    let (s_count, f2) = mem.alloc[usize](a, nsets + 1usize)
    let (s_num, f3) = mem.alloc[f64](a, nentries + 1usize)
    let (s_code, f4) = mem.alloc[str](a, nentries + 1usize)
    let (s_lab, f5) = mem.alloc[str](a, nentries + 1usize)
    if f1 != ok { ret (none, f1) }
    if f2 != ok { ret (none, f2) }
    if f3 != ok { ret (none, f3) }
    if f4 != ok { ret (none, f4) }
    if f5 != ok { ret (none, f5) }

    // pass 2
    var nv = 0usize
    var slot = 0usize
    var setn = 0usize
    var entn = 0usize
    var utf8 = false
    var disp_at = 0usize
    var disp_n = 0usize
    at = HEADER
    done = false
    while !done {
        let rt = i64(u32_at(&rd, at))
        at += 4usize
        if rt == 2i64 {
            let ty = i32_at(&rd, at)
            let has_label = i32_at(&rd, at + 4usize)
            let nm = i32_at(&rd, at + 8usize)
            let pr = u64(u32_at(&rd, at + 12usize))
            let wr = u64(u32_at(&rd, at + 16usize))
            let nm_at = at + 20usize
            at += 28usize
            if ty < 0i64 {
                if nv == 0usize { ret (none, BadFile) }
                v_width[nv - 1usize] += 1usize
                slot += 1usize
                if has_label != 0i64 {
                    let ll = usize(u32_at(&rd, at))
                    at += 4usize + (ll + 3usize) / 4usize * 4usize
                }
                var an = nm
                if an < 0i64 { an = -an }
                at += usize(an) * 8usize
            } else {
                let i = nv
                v_width[i] = 1usize
                v_nseg[i] = 1usize
                v_off[i] = slot
                v_slen[i] = 0usize
                v_ty[i] = ty
                v_set[i] = -1i64
                v_pt[i * 3usize] = i64((pr >> 16u64) & 255u64)
                v_pt[i * 3usize + 1usize] = i64((pr >> 8u64) & 255u64)
                v_pt[i * 3usize + 2usize] = i64(pr & 255u64)
                v_name[i] = trimmed(data[nm_at..nm_at + 8usize])
                v_long[i] = v_name[i]
                var wt = i64((wr >> 16u64) & 255u64)
                v_text[i] = 0u8
                if ty > 0i64 || i64((pr >> 16u64) & 255u64) == 1i64 || wt == 1i64 { v_text[i] = 1u8 }
                v_label[i] = text_of(data[0usize..0usize])
                if has_label != 0i64 {
                    let ll = usize(u32_at(&rd, at))
                    if ll > 0usize { v_label[i] = trimmed(data[at + 4usize..at + 4usize + ll]) }
                    at += 4usize + (ll + 3usize) / 4usize * 4usize
                }
                v_mc[i] = 0u8
                v_mr[i] = 0u8
                if nm != 0i64 {
                    if nm > 3i64 || nm < -3i64 { ret (none, BadFile) }
                    var cnt = nm
                    if nm < 0i64 {
                        v_mr[i] = 1u8
                        cnt = -nm
                    }
                    v_mc[i] = u8(cnt)
                    var j = 0usize
                    while j < usize(cnt) {
                        if v_text[i] == 0u8 {
                            let bits = u64_at(&rd, at + 8usize * j)
                            var mv = bits_to_f64(bits)
                            if bits == SYSMIS { mv = 0.0f64 / 0.0f64 }
                            if bits == LOWEST { mv = bits_to_f64(18442240474082181120u64) }
                            if bits == HIGHEST { mv = bits_to_f64(9218868437227405312u64) }
                            v_mnum[i * 3usize + j] = mv
                        } else {
                            v_mtxt[i * 3usize + j] = trimmed(data[at + 8usize * j..at + 8usize * j + 8usize])
                        }
                        j += 1usize
                    }
                    at += usize(cnt) * 8usize
                }
                nv += 1usize
                slot += 1usize
            }
        } else if rt == 3i64 {
            let cnt = usize(u32_at(&rd, at))
            at += 4usize
            let first_entry = entn
            var j = 0usize
            while j < cnt {
                let raw_at = at
                let ul = usize(data[at + 8usize])
                let padded = (ul + 8usize) / 8usize * 8usize - 1usize
                s_code[entn] = trimmed(data[raw_at..raw_at + 8usize])
                s_num[entn] = bits_to_f64(u64_at(&rd, raw_at))
                s_lab[entn] = trimmed(data[raw_at + 9usize..raw_at + 9usize + padded])
                at += 8usize + 1usize + padded
                entn += 1usize
                j += 1usize
            }
            at += 4usize
            let vc = usize(u32_at(&rd, at))
            at += 4usize
            var is_text = false
            j = 0usize
            while j < vc {
                let want = usize(u32_at(&rd, at + 4usize * j)) - 1usize
                var k = 0usize
                while k < nv {
                    if v_off[k] == want {
                        v_set[k] = i64(setn)
                        is_text = v_text[k] != 0u8
                    }
                    k += 1usize
                }
                j += 1usize
            }
            at += vc * 4usize
            // numeric labels hold doubles; a text set keeps its 8-byte text
            if !is_text {
                j = first_entry
                while j < entn {
                    let bits = mem.bitcast[u64](s_num[j])
                    if bits == SYSMIS || bits == LOWEST || bits == HIGHEST { s_num[j] = 0.0f64 / 0.0f64 }
                    j += 1usize
                }
            }
            s_first[setn] = first_entry
            s_count[setn] = cnt
            setn += 1usize
        } else if rt == 6i64 {
            let nl = usize(u32_at(&rd, at))
            at += 4usize + nl * 80usize
        } else if rt == 7i64 {
            let sub = i64(u32_at(&rd, at))
            let sz = usize(u32_at(&rd, at + 4usize))
            let cn = usize(u32_at(&rd, at + 8usize))
            at += 12usize
            let body = at
            let stop = at + sz * cn
            if sub == 3i64 {
                let cc = u32_at(&rd, body + 28usize)
                if cc == 65001u64 { utf8 = true }
            } else if sub == 11i64 {
                disp_at = body
                disp_n = cn
            } else if sub == 13i64 {
                // SHORT=Long names, tab separated
                var p = body
                while p < stop {
                    var e = p
                    while e < stop && data[e] != 61u8 { e += 1usize }
                    let key = trimmed(data[p..e])
                    var f = e + 1usize
                    while f < stop && data[f] != 9u8 { f += 1usize }
                    var vend = f
                    if vend > stop { vend = stop }
                    var vs = e + 1usize
                    if vs > vend { vs = vend }
                    let val = trimmed(data[vs..vend])
                    var k = 0usize
                    while k < nv {
                        if same_ci(v_name[k], key) { v_long[k] = val }
                        k += 1usize
                    }
                    p = f + 1usize
                }
            } else if sub == 14i64 {
                var p = body
                while p < stop {
                    var e = p
                    while e < stop && data[e] != 61u8 { e += 1usize }
                    let key = trimmed(data[p..e])
                    var q = e + 1usize
                    var w = 0usize
                    while q < stop && data[q] >= 48u8 && data[q] <= 57u8 {
                        w = w * 10usize + usize(data[q] - 48u8)
                        q += 1usize
                    }
                    var k = 0usize
                    while k < nv {
                        if same_ci(v_name[k], key) {
                            v_slen[k] = w
                            v_pt[k * 3usize + 1usize] = i64(w)
                        }
                        k += 1usize
                    }
                    while q < stop && (data[q] == 0u8 || data[q] == 9u8) { q += 1usize }
                    p = q
                }
            } else if sub == 21i64 {
                var p = body
                while p < stop {
                    let nl = usize(u32_at(&rd, p))
                    let vname = trimmed(data[p + 4usize..p + 4usize + nl])
                    p += 4usize + nl + 4usize
                    let lc = usize(u32_at(&rd, p))
                    p += 4usize
                    var k = 0usize
                    while k < nv {
                        if v_nseg[k] > 0usize && same(v_long[k], vname) { v_set[k] = i64(setn) }
                        k += 1usize
                    }
                    s_first[setn] = entn
                    s_count[setn] = lc
                    var j = 0usize
                    while j < lc {
                        let vl = usize(u32_at(&rd, p))
                        s_code[entn] = trimmed(data[p + 4usize..p + 4usize + vl])
                        p += 4usize + vl
                        let ll = usize(u32_at(&rd, p))
                        s_lab[entn] = trimmed(data[p + 4usize..p + 4usize + ll])
                        p += 4usize + ll
                        entn += 1usize
                        j += 1usize
                    }
                    setn += 1usize
                }
            } else if sub == 22i64 {
                var p = body
                while p < stop {
                    let nl = usize(u32_at(&rd, p))
                    let vname = trimmed(data[p + 4usize..p + 4usize + nl])
                    p += 4usize + nl
                    let cnt = usize(data[p])
                    p += 1usize
                    let vl = usize(u32_at(&rd, p))
                    p += 4usize
                    var k = 0usize
                    while k < nv {
                        if same(v_long[k], vname) {
                            v_mc[k] = u8(cnt)
                            var j = 0usize
                            while j < cnt {
                                v_mtxt[k * 3usize + j] = trimmed(data[p + vl * j..p + vl * j + vl])
                                j += 1usize
                            }
                        }
                        k += 1usize
                    }
                    p += vl * cnt
                }
            }
            at = stop
        } else if rt == 999i64 {
            at += 4usize
            done = true
        } else {
            ret (none, BadFile)
        }
    }

    // segments and real variables
    var nreal = 0usize
    var i = 0usize
    while i < nv {
        if v_slen[i] > 0usize { v_nseg[i] = (v_slen[i] + 251usize) / 252usize }
        nreal += 1usize
        i += v_nseg[i]
    }
    if nreal == 0usize { ret (none, BadFile) }
    let (r_vi, g1) = mem.alloc[usize](a, nreal)
    let (v_real, g2) = mem.alloc[usize](a, nv)
    if g1 != ok { ret (none, g1) }
    if g2 != ok { ret (none, g2) }
    let (names, g3) = mem.alloc[str](a, nreal)
    let (labels, g4) = mem.alloc[str](a, nreal)
    let (fmts, g5) = mem.alloc[str](a, nreal)
    let (is_text, g6) = mem.alloc[u8](a, nreal)
    let (kinds, g7) = mem.alloc[u8](a, nreal)
    let (dwidth, g8) = mem.alloc[i64](a, nreal)
    let (m_count, g9) = mem.alloc[u8](a, nreal)
    let (m_range, g10) = mem.alloc[u8](a, nreal)
    let (m_num, g11) = mem.alloc[f64](a, nreal * 3usize)
    let (m_text, g12) = mem.alloc[str](a, nreal * 3usize)
    let (c_set, g13) = mem.alloc[i64](a, nreal)
    let (o_fcode, h1) = mem.alloc[i64](a, nreal * 3usize)
    let (o_uw, h2) = mem.alloc[i64](a, nreal)
    let (o_meas, h3) = mem.alloc[i64](a, nreal)
    let (o_al, h4) = mem.alloc[i64](a, nreal)
    let (o_dw, h5) = mem.alloc[i64](a, nreal)
    if h1 != ok { ret (none, h1) }
    if h2 != ok { ret (none, h2) }
    if h3 != ok { ret (none, h3) }
    if h4 != ok { ret (none, h4) }
    if h5 != ok { ret (none, h5) }
    if g3 != ok { ret (none, g3) }
    if g4 != ok { ret (none, g4) }
    if g5 != ok { ret (none, g5) }
    if g6 != ok { ret (none, g6) }
    if g7 != ok { ret (none, g7) }
    if g8 != ok { ret (none, g8) }
    if g9 != ok { ret (none, g9) }
    if g10 != ok { ret (none, g10) }
    if g11 != ok { ret (none, g11) }
    if g12 != ok { ret (none, g12) }
    if g13 != ok { ret (none, g13) }
    var has_width = false
    var hw = 0usize
    if disp_n > 0usize {
        if disp_n != 2usize * nv && disp_n != 3usize * nv { ret (none, BadFile) }
        has_width = disp_n / nv == 3usize
        if has_width { hw = 1usize }
    }
    var weight_var = -1i64
    i = 0usize
    var k = 0usize
    while i < nv {
        r_vi[k] = i
        v_real[i] = k
        names[k] = v_long[i]
        labels[k] = v_label[i]
        is_text[k] = v_text[i]
        c_set[k] = v_set[i]
        m_count[k] = v_mc[i]
        m_range[k] = v_mr[i]
        var j = 0usize
        while j < 3usize {
            m_num[k * 3usize + j] = v_mnum[i * 3usize + j]
            m_text[k * 3usize + j] = v_mtxt[i * 3usize + j]
            j += 1usize
        }
        let (ft, fe) = format_text(a, v_pt[i * 3usize], v_pt[i * 3usize + 1usize], v_pt[i * 3usize + 2usize])
        if fe != ok { ret (none, fe) }
        fmts[k] = ft
        kinds[k] = 0u8
        if is_text[k] == 0u8 { kinds[k] = kind_of(ft) }
        dwidth[k] = v_pt[i * 3usize + 1usize]
        o_fcode[k * 3usize] = v_pt[i * 3usize]
        o_fcode[k * 3usize + 1usize] = v_pt[i * 3usize + 1usize]
        o_fcode[k * 3usize + 2usize] = v_pt[i * 3usize + 2usize]
        o_uw[k] = 0i64
        if v_text[i] != 0u8 {
            o_uw[k] = v_ty[i]
            if v_slen[i] > 0usize { o_uw[k] = i64(v_slen[i]) }
        }
        o_meas[k] = 0i64
        o_al[k] = 0i64
        o_dw[k] = 0i64
        if disp_n > 0usize {
            let o = (2usize + hw) * i
            o_meas[k] = i64(u32_at(&rd, disp_at + 4usize * o))
            o_al[k] = i64(u32_at(&rd, disp_at + 4usize * (o + 1usize + hw)))
            if has_width {
                let dw = i64(u32_at(&rd, disp_at + 4usize * (o + 1usize)))
                o_dw[k] = dw
                if dw != 0i64 { dwidth[k] = dw }
            }
        }
        if weight_at > 0i64 && v_off[i] == usize(weight_at - 1i64) { weight_var = i64(k) }
        k += 1usize
        i += v_nseg[i]
    }
    // the file label
    let label = trimmed(data[109usize..173usize])

    // the data cells
    let row_cells = slot
    var buf: []const u8 = data[dstart..]
    if comp == 1i64 {
        let (cells, ce) = unpack_rows(a, data[dstart..], usize(ncases) * row_cells, bias, rd.big)
        if ce != ok { ret (none, ce) }
        buf = cells
    } else if comp == 2i64 {
        if dstart + 24usize > data.len { ret (none, BadFile) }
        let tr_at = usize(u64_at(&rd, dstart + 8usize))
        let tr_len = usize(u64_at(&rd, dstart + 16usize))
        let nblocks = (tr_len - 24usize) / 24usize
        if tr_at + 24usize + nblocks * 24usize > data.len { ret (none, BadFile) }
        var total = 0usize
        var b = 0usize
        while b < nblocks {
            total += usize(u32_at(&rd, tr_at + 24usize + b * 24usize + 16usize))
            b += 1usize
        }
        let (joined, je) = mem.alloc[u8](a, total + 1usize)
        if je != ok { ret (none, je) }
        var jo = 0usize
        b = 0usize
        while b < nblocks {
            let ent = tr_at + 24usize + b * 24usize
            let c_ofs = usize(u64_at(&rd, ent + 8usize))
            let u_size = usize(u32_at(&rd, ent + 16usize))
            let c_size = usize(u32_at(&rd, ent + 20usize))
            if c_ofs + c_size > data.len || c_size < 2usize { ret (none, BadFile) }
            let (plain, pe) = run_deflate(a, data[c_ofs + 2usize..c_ofs + c_size], u_size)
            if pe != ok { ret (none, pe) }
            var q = 0usize
            while q < u_size {
                joined[jo + q] = plain[q]
                q += 1usize
            }
            jo += u_size
            b += 1usize
        }
        let (cells, ce) = unpack_rows(a, joined[..total], usize(ncases) * row_cells, bias, rd.big)
        if ce != ok { ret (none, ce) }
        buf = cells
    } else {
        if dstart + usize(ncases) * row_cells * 8usize > data.len { ret (none, BadFile) }
    }

    let (num, n1) = mem.alloc[f64](a, usize(ncases) * nreal + 1usize)
    let (txt, n2) = mem.alloc[str](a, usize(ncases) * nreal + 1usize)
    if n1 != ok { ret (none, n1) }
    if n2 != ok { ret (none, n2) }
    var longest = 256usize
    i = 0usize
    while i < nv {
        if v_slen[i] > longest { longest = v_slen[i] }
        i += v_nseg[i]
    }
    let raw_cap = longest + 7usize
    let (raw, n3) = mem.alloc[u8](a, raw_cap + 8usize)
    if n3 != ok { ret (none, n3) }
    let rdb = Rd { d: buf, big: rd.big }
    var r = 0usize
    while r < usize(ncases) {
        let base = r * row_cells * 8usize
        var offset = 0usize
        var col = 0usize
        var vidx = 0usize
        var seg = 0usize
        var used = 0usize
        var cell = 0usize
        while cell < row_cells && col < nv && vidx < nv {
            if offset > 31usize { ret (none, BadFile) }
            let cb = base + cell * 8usize
            if v_text[vidx] != 0u8 {
                var rl = 8usize
                if offset == 31usize { rl = 7usize }
                if used + rl <= raw_cap {
                    var q = 0usize
                    while q < rl {
                        let ch = buf[cb + q]
                        if utf8 {
                            if ch != 0u8 {
                                raw[used] = ch
                                used += 1usize
                            }
                        } else {
                            raw[used] = ch
                            used += 1usize
                        }
                        q += 1usize
                    }
                }
                offset += 1usize
                if offset == v_width[col] {
                    offset = 0usize
                    col += 1usize
                    seg += 1usize
                }
                if seg == v_nseg[vidx] {
                    var n = used
                    while n > 0usize && (raw[n - 1usize] == 32u8 || raw[n - 1usize] == 0u8) { n -= 1usize }
                    let (own, oe) = mem.alloc[u8](a, n + 1usize)
                    if oe != ok { ret (none, oe) }
                    var q = 0usize
                    while q < n {
                        own[q] = raw[q]
                        q += 1usize
                    }
                    txt[r * nreal + v_real[vidx]] = text_of(own[..n])
                    used = 0usize
                    seg = 0usize
                    vidx += v_nseg[vidx]
                }
            } else {
                let bits = u64_at(&rdb, cb)
                var x = bits_to_f64(bits)
                if bits == SYSMIS || bits == LOWEST || bits == HIGHEST || x != x { x = 0.0f64 / 0.0f64 }
                num[r * nreal + v_real[vidx]] = x
                vidx += v_nseg[vidx]
                col += 1usize
            }
            cell += 1usize
        }
        r += 1usize
    }
    ret (Sav { nvars: nreal, nobs: usize(ncases), compression: comp, big: rd.big, weight: weight_var, label: label, names: names, varlabels: labels, formats: fmts, is_text: is_text, kind: kinds, display_width: dwidth, miss_count: m_count, miss_range: m_range, miss_num: m_num, miss_text: m_text, label_set: c_set, num: num, text: txt, set_first: s_first, set_count: s_count, entry_num: s_num, entry_text: s_code, entry_label: s_lab, fcode: o_fcode, uwidth: o_uw, measure: o_meas, align: o_al, dwraw: o_dw, stamp: text_of(data[92usize..109usize]) }, ok)
}

// ---- writing: ReadStat's readstat_sav_write.c, little-endian, UTF-8 ----

type Wr = struct { b: []u8, n: usize, a: *mem.Arena, bad: bool }

fn w_need(w: *Wr, extra: usize) {
    if w.bad { ret }
    if w.n + extra <= w.b.len { ret }
    var cap = w.b.len * 2usize
    if cap < w.n + extra + 4096usize { cap = w.n + extra + 4096usize }
    let (nb, e) = mem.alloc[u8](w.a, cap)
    if e != ok {
        w.bad = true
        ret
    }
    var i = 0usize
    while i < w.n {
        nb[i] = w.b[i]
        i += 1usize
    }
    w.b = nb
}

fn w_n(w: *Wr, v: u64, n: usize) {
    w_need(w, n)
    if w.bad { ret }
    var i = 0usize
    while i < n {
        w.b[w.n + i] = u8((v >> u64(8usize * i)) & 255u64)
        i += 1usize
    }
    w.n += n
}

fn w_i32(w: *Wr, v: i64) { w_n(w, mem.bitcast[u64](v) & 4294967295u64, 4usize) }

fn w_str(w: *Wr, s: str) {
    w_need(w, s.len)
    if w.bad { ret }
    var i = 0usize
    while i < s.len {
        w.b[w.n + i] = s[i]
        i += 1usize
    }
    w.n += s.len
}

fn w_fill(w: *Wr, c: u8, n: usize) {
    w_need(w, n)
    if w.bad { ret }
    var i = 0usize
    while i < n {
        w.b[w.n + i] = c
        i += 1usize
    }
    w.n += n
}

// s cut or space padded to `width` bytes
fn w_pad(w: *Wr, s: str, width: usize) {
    var cut = s.len
    if cut > width { cut = width }
    w_str(w, s[..cut])
    w_fill(w, 32u8, width - cut)
}

// a continuation record of a wide string: type -1, blank name
fn w_blank_records(w: *Wr, count: usize) {
    var x = 0usize
    while x < count {
        w_i32(w, 2i64)
        w_i32(w, -1i64)
        w_i32(w, 0i64)
        w_i32(w, 0i64)
        w_i32(w, 72961i64)
        w_i32(w, 72961i64)
        w_fill(w, 32u8, 8usize)
        x += 1usize
    }
}

fn segments_of(uw: i64, text: bool) -> usize {
    if text && uw > 255i64 { ret usize((uw + 251i64) / 252i64) }
    ret 1usize
}

// sav_variable_width: bytes one value takes in a row
fn storage_of(uw: i64, text: bool) -> usize {
    if !text { ret 8usize }
    if uw > 255i64 {
        let n = segments_of(uw, true)
        ret (n - 1usize) * 256usize + usize((uw - i64(n - 1usize) * 252i64 + 7i64) / 8i64 * 8i64)
    }
    if uw == 0i64 { ret 8usize }
    ret usize((uw + 7i64) / 8i64 * 8i64)
}

fn bits_of_num(x: f64) -> u64 {
    if x != x { ret SYSMIS }
    ret mem.bitcast[u64](x)
}

// spss_64bit_value for a missing-value entry: NaN is system-missing, the infinities the extremes
fn miss_bits(x: f64) -> u64 {
    if x != x { ret SYSMIS }
    let b = mem.bitcast[u64](x)
    if b == 18442240474082181120u64 { ret LOWEST }
    if b == 9218868437227405312u64 { ret HIGHEST }
    ret b
}

fn up_char(c: u8) -> u8 {
    if c >= 97u8 && c <= 122u8 { ret c - 32u8 }
    ret c
}

fn write_label(w: *Wr, label: str) {
    var n = label.len
    if n > 256usize { n = 256usize }
    w_i32(w, i64(n))
    w_str(w, label[..n])
    w_fill(w, 0u8, (n + 3usize) / 4usize * 4usize - n)
}

fn adler32(d: []const u8) -> u32 {
    var x = 1u32
    var y = 0u32
    var i = 0usize
    while i < d.len {
        x = (x + u32(d[i])) % 65521u32
        y = (y + x) % 65521u32
        i += 1usize
    }
    ret (y << 16u32) | x
}

// one zlib stream (default level, as zlib's deflateInit with Z_DEFAULT_COMPRESSION) of `input`
fn zlib_block(a: *mem.Arena, input: []const u8) -> ([]u8, err) {
    var nothing: []u8 = zero
    let need = deflate.encoder_storage(.Balanced)
    let (storage, se) = mem.alloc[u8](a, need)
    if se != ok { ret (nothing, se) }
    let (enc, ee) = deflate.encoder(storage, .Balanced)
    if ee != ok { ret (nothing, ee) }
    var e = enc
    let cap = input.len + input.len / 100usize + 1024usize
    let (out, oe) = mem.alloc[u8](a, cap)
    if oe != ok { ret (nothing, oe) }
    out[0usize] = 120u8
    out[1usize] = 156u8
    var at = 0usize
    var o = 2usize
    var finished = false
    while !finished {
        if o + 64usize > cap { ret (nothing, BadFile) }
        let (consumed, written, status, de) = deflate.encode(&e, input[at..], out[o..], true)
        if de != ok { ret (nothing, de) }
        at += consumed
        o += written
        if status == .Finished { finished = true }
    }
    if o + 4usize > cap { ret (nothing, BadFile) }
    let ad = adler32(input)
    out[o] = u8(ad >> 24u32)
    out[o + 1usize] = u8((ad >> 16u32) & 255u32)
    out[o + 2usize] = u8((ad >> 8u32) & 255u32)
    out[o + 3usize] = u8(ad & 255u32)
    ret (out[..o + 4usize], ok)
}

fn put_row_bytes(w: *Wr, src: []const u8, n: usize) {
    w_need(w, n)
    if w.bad { ret }
    var q = 0usize
    while q < n {
        w.b[w.n + q] = src[q]
        q += 1usize
    }
    w.n += n
}

// the file for `s` (little-endian, UTF-8) with the 17 bytes of creation date and time `stamp` (e.g. "21 Nov 2621:43:39")
fn write(a: *mem.Arena, s: *const Sav, stamp: str) -> ([]u8, err) {
    var none: []u8 = zero
    let nv = s.nvars
    if s.big || nv == 0usize || stamp.len != 17usize { ret (none, Unsupported) }
    let (swb, g1) = mem.alloc[usize](a, nv)
    let (off, g2) = mem.alloc[usize](a, nv)
    let (shorts, g3) = mem.alloc[str](a, nv)
    let (sbuf, g4) = mem.alloc[u8](a, nv * 16usize)
    if g1 != ok { ret (none, g1) }
    if g2 != ok { ret (none, g2) }
    if g3 != ok { ret (none, g3) }
    if g4 != ok { ret (none, g4) }
    var row_len = 0usize
    var total_segs = 0usize
    var k = 0usize
    while k < nv {
        let text = s.is_text[k] != 0u8
        swb[k] = storage_of(s.uwidth[k], text)
        off[k] = row_len
        row_len += swb[k]
        total_segs += segments_of(s.uwidth[k], text)
        var n = s.names[k].len
        if n > 8usize { n = 8usize }
        var q = 0usize
        while q < n {
            sbuf[k * 16usize + q] = up_char(s.names[k][q])
            q += 1usize
        }
        var sh = text_of(sbuf[k * 16usize..k * 16usize + n])
        var dup = false
        var p = 0usize
        while p < k {
            if same(shorts[p], sh) { dup = true }
            p += 1usize
        }
        if dup {
            // "V%d_A" of the 1-based position
            sbuf[k * 16usize] = 86u8
            let dn = put_int(sbuf[k * 16usize..k * 16usize + 16usize], 1usize, i64((k + 1usize) % 100000usize))
            sbuf[k * 16usize + 1usize + dn] = 95u8
            sbuf[k * 16usize + 2usize + dn] = 65u8
            sh = text_of(sbuf[k * 16usize..k * 16usize + 3usize + dn])
        }
        shorts[k] = sh
        k += 1usize
    }
    var w = Wr { b: zero, n: 0usize, a: a, bad: false }
    w_need(&w, 65536usize)

    // header
    w_str(&w, "$FL2")
    if s.compression == 2i64 { w.b[3usize] = 51u8 }
    w_pad(&w, "@(#) SPSS DATA FILE - https://github.com/WizardMac/ReadStat", 60usize)
    w_i32(&w, 2i64)
    w_i32(&w, i64(row_len / 8usize))
    w_i32(&w, s.compression)
    var wi = 0i64
    if s.weight >= 0i64 { wi = 1i64 + i64(off[usize(s.weight)] / 8usize) }
    w_i32(&w, wi)
    w_i32(&w, i64(s.nobs))
    w_n(&w, mem.bitcast[u64](100.0f64), 8usize)
    w_str(&w, stamp)
    w_pad(&w, s.label, 64usize)
    w_fill(&w, 0u8, 3usize)

    // variable records
    k = 0usize
    while k < nv {
        let text = s.is_text[k] != 0u8
        let uw = s.uwidth[k]
        let storage = swb[k]
        w_i32(&w, 2i64)
        var ty = 0i64
        if text {
            ty = uw
            if ty > 255i64 { ty = 255i64 }
        }
        w_i32(&w, ty)
        var has_label = 0i64
        if s.varlabels[k].len > 0usize { has_label = 1i64 }
        w_i32(&w, has_label)
        var nm = 0i64
        if !text || storage <= 8usize {
            nm = i64(s.miss_count[k])
            if s.miss_range[k] != 0u8 { nm = -nm }
        }
        w_i32(&w, nm)
        var fw = s.fcode[k * 3usize + 1usize]
        if fw > 255i64 { fw = 255i64 }
        let print = s.fcode[k * 3usize] * 65536i64 + fw * 256i64 + s.fcode[k * 3usize + 2usize]
        w_i32(&w, print)
        w_i32(&w, print)
        w_pad(&w, shorts[k], 8usize)
        if has_label != 0i64 { write_label(&w, s.varlabels[k]) }
        if !text || storage <= 8usize {
            var j = 0usize
            while j < usize(s.miss_count[k]) {
                if text { w_pad(&w, s.miss_text[k * 3usize + j], 8usize) } else { w_n(&w, miss_bits(s.miss_num[k * 3usize + j]), 8usize) }
                j += 1usize
            }
        }
        var extra = storage / 8usize - 1usize
        if extra > 31usize { extra = 31usize }
        w_blank_records(&w, extra)
        let nseg = segments_of(uw, text)
        var sg = 1usize
        while sg < nseg {
            var ss = 255i64
            if sg == nseg - 1usize { ss = uw - i64(nseg - 1usize) * 252i64 }
            w_i32(&w, 2i64)
            w_i32(&w, ss)
            w_i32(&w, 0i64)
            w_i32(&w, 0i64)
            var gw = ss
            if gw > 255i64 { gw = 255i64 }
            let gp = s.fcode[k * 3usize] * 65536i64 + gw * 256i64
            w_i32(&w, gp)
            w_i32(&w, gp)
            var stem = shorts[k]
            if stem.len > 5usize { stem = stem[..5usize] }
            var letter = u8(48usize + sg % 36usize)
            if sg % 36usize >= 10usize { letter = u8(65usize + sg % 36usize - 10usize) }
            w_str(&w, stem)
            w_n(&w, u64(letter), 1usize)
            w_fill(&w, 32u8, 7usize - stem.len)
            var ge = (usize(ss) + 7usize) / 8usize - 1usize
            if ge > 31usize { ge = 31usize }
            w_blank_records(&w, ge)
            sg += 1usize
        }
        k += 1usize
    }

    // short value labels: one record per labelled column of storage 8 or less
    k = 0usize
    while k < nv {
        if s.label_set[k] >= 0i64 && swb[k] <= 8usize {
            let st = usize(s.label_set[k])
            let cnt = s.set_count[st]
            if cnt > 0usize {
                w_i32(&w, 3i64)
                w_i32(&w, i64(cnt))
                var e = 0usize
                while e < cnt {
                    let ei = s.set_first[st] + e
                    if s.is_text[k] != 0u8 { w_pad(&w, s.entry_text[ei], 8usize) } else { w_n(&w, bits_of_num(s.entry_num[ei]), 8usize) }
                    var ll = s.entry_label[ei].len
                    if ll > 120usize { ll = 120usize }
                    w_n(&w, u64(ll), 1usize)
                    w_pad(&w, s.entry_label[ei][..ll], (ll + 1usize + 7usize) / 8usize * 8usize - 1usize)
                    e += 1usize
                }
                w_i32(&w, 4i64)
                w_i32(&w, 1i64)
                w_i32(&w, i64(1usize + off[k] / 8usize))
            }
        }
        k += 1usize
    }

    // integer and floating-point info
    w_i32(&w, 7i64)
    w_i32(&w, 3i64)
    w_i32(&w, 4i64)
    w_i32(&w, 8i64)
    w_i32(&w, 20i64)
    w_i32(&w, 0i64)
    w_i32(&w, 0i64)
    w_i32(&w, -1i64)
    w_i32(&w, 1i64)
    w_i32(&w, 1i64)
    w_i32(&w, 2i64)
    w_i32(&w, 65001i64)
    w_i32(&w, 7i64)
    w_i32(&w, 4i64)
    w_i32(&w, 8i64)
    w_i32(&w, 3i64)
    w_n(&w, SYSMIS, 8usize)
    w_n(&w, HIGHEST, 8usize)
    w_n(&w, LOWEST, 8usize)

    // display
    w_i32(&w, 7i64)
    w_i32(&w, 11i64)
    w_i32(&w, 4i64)
    w_i32(&w, i64(3usize * total_segs))
    k = 0usize
    while k < nv {
        var dw = s.dwraw[k]
        if dw <= 0i64 { dw = 8i64 }
        var sg = segments_of(s.uwidth[k], s.is_text[k] != 0u8)
        while sg > 0usize {
            w_i32(&w, s.measure[k])
            w_i32(&w, dw)
            w_i32(&w, s.align[k])
            sg -= 1usize
        }
        k += 1usize
    }

    // long names
    var cnt = 0usize
    k = 0usize
    while k < nv {
        var nl = s.names[k].len
        if nl > 64usize { nl = 64usize }
        if nl > 0usize && shorts[k].len > 0usize { cnt += shorts[k].len + 1usize + nl + 1usize }
        k += 1usize
    }
    if cnt > 0usize {
        w_i32(&w, 7i64)
        w_i32(&w, 13i64)
        w_i32(&w, 1i64)
        w_i32(&w, i64(cnt - 1usize))
        var first = true
        k = 0usize
        while k < nv {
            var nl = s.names[k].len
            if nl > 64usize { nl = 64usize }
            if nl > 0usize {
                if !first { w_n(&w, 9u64, 1usize) }
                w_str(&w, shorts[k])
                w_n(&w, 61u64, 1usize)
                w_str(&w, s.names[k][..nl])
                first = false
            }
            k += 1usize
        }
    }

    // very long strings
    var vcount = 0usize
    var kv: [16]u8 = zero
    k = 0usize
    while k < nv {
        if s.is_text[k] != 0u8 && s.uwidth[k] > 255i64 {
            vcount += shorts[k].len + 1usize + put_int(kv[..], 0usize, s.uwidth[k] % 100000i64) + 2usize
        }
        k += 1usize
    }
    if vcount > 0usize {
        w_i32(&w, 7i64)
        w_i32(&w, 14i64)
        w_i32(&w, 1i64)
        w_i32(&w, i64(vcount))
        k = 0usize
        while k < nv {
            if s.is_text[k] != 0u8 && s.uwidth[k] > 255i64 {
                w_str(&w, shorts[k])
                w_n(&w, 61u64, 1usize)
                let dn = put_int(kv[..], 0usize, s.uwidth[k] % 100000i64)
                w_str(&w, text_of(kv[..dn]))
                w_n(&w, 0u64, 1usize)
                w_n(&w, 9u64, 1usize)
            }
            k += 1usize
        }
    }

    // long-string value labels
    var lcount = 0usize
    k = 0usize
    while k < nv {
        if s.label_set[k] >= 0i64 && swb[k] > 8usize {
            let st = usize(s.label_set[k])
            lcount += 4usize + s.names[k].len + 4usize + 4usize
            var e = 0usize
            while e < s.set_count[st] {
                var ll = s.entry_label[s.set_first[st] + e].len
                if ll > 120usize { ll = 120usize }
                lcount += 4usize + swb[k] + 4usize + ll
                e += 1usize
            }
        }
        k += 1usize
    }
    if lcount > 0usize {
        w_i32(&w, 7i64)
        w_i32(&w, 21i64)
        w_i32(&w, 1i64)
        w_i32(&w, i64(lcount))
        k = 0usize
        while k < nv {
            if s.label_set[k] >= 0i64 && swb[k] > 8usize {
                let st = usize(s.label_set[k])
                w_i32(&w, i64(s.names[k].len))
                w_str(&w, s.names[k])
                w_i32(&w, i64(swb[k]))
                w_i32(&w, i64(s.set_count[st]))
                var e = 0usize
                while e < s.set_count[st] {
                    let ei = s.set_first[st] + e
                    var ll = s.entry_label[ei].len
                    if ll > 120usize { ll = 120usize }
                    w_i32(&w, i64(swb[k]))
                    w_pad(&w, s.entry_text[ei], swb[k])
                    w_i32(&w, i64(ll))
                    w_str(&w, s.entry_label[ei][..ll])
                    e += 1usize
                }
            }
            k += 1usize
        }
    }

    // long-string missing values
    var mcount = 0usize
    k = 0usize
    while k < nv {
        if s.is_text[k] != 0u8 && swb[k] > 8usize && s.miss_count[k] > 0u8 {
            mcount += 4usize + s.names[k].len + 1usize + 4usize + 8usize * usize(s.miss_count[k])
        }
        k += 1usize
    }
    if mcount > 0usize {
        w_i32(&w, 7i64)
        w_i32(&w, 22i64)
        w_i32(&w, 1i64)
        w_i32(&w, i64(mcount))
        k = 0usize
        while k < nv {
            if s.is_text[k] != 0u8 && swb[k] > 8usize && s.miss_count[k] > 0u8 {
                w_i32(&w, i64(s.names[k].len))
                w_str(&w, s.names[k])
                w_n(&w, u64(s.miss_count[k]), 1usize)
                w_i32(&w, 8i64)
                var j = 0usize
                while j < usize(s.miss_count[k]) {
                    w_pad(&w, s.miss_text[k * 3usize + j], 8usize)
                    j += 1usize
                }
            }
            k += 1usize
        }
    }

    // number of cases, termination
    w_i32(&w, 7i64)
    w_i32(&w, 16i64)
    w_i32(&w, 8i64)
    w_i32(&w, 2i64)
    w_n(&w, 1u64, 8usize)
    w_n(&w, u64(s.nobs), 8usize)
    w_i32(&w, 999i64)
    w_i32(&w, 0i64)

    // rows
    let (row, r1) = mem.alloc[u8](a, row_len + 8usize)
    let (packed, r2) = mem.alloc[u8](a, row_len * 2usize + 64usize)
    if r1 != ok { ret (none, r1) }
    if r2 != ok { ret (none, r2) }
    var stream = Wr { b: zero, n: 0usize, a: a, bad: false }
    var r = 0usize
    while r < s.nobs {
        k = 0usize
        while k < nv {
            let at = off[k]
            if s.is_text[k] != 0u8 {
                var q = 0usize
                while q < swb[k] {
                    row[at + q] = 32u8
                    q += 1usize
                }
                let v = s.text[r * nv + k]
                if v.len > swb[k] { ret (none, BadFile) }
                var ro = 0usize
                var vo = 0usize
                while v.len - vo > 255usize {
                    q = 0usize
                    while q < 255usize {
                        row[at + ro + q] = v[vo + q]
                        q += 1usize
                    }
                    ro += 256usize
                    vo += 255usize
                }
                q = 0usize
                while q < v.len - vo {
                    row[at + ro + q] = v[vo + q]
                    q += 1usize
                }
            } else {
                let bits = bits_of_num(s.num[r * nv + k])
                var q = 0usize
                while q < 8usize {
                    row[at + q] = u8((bits >> u64(8usize * q)) & 255u64)
                    q += 1usize
                }
            }
            k += 1usize
        }
        if s.compression == 0i64 {
            put_row_bytes(&w, row, row_len)
        } else {
            var ctl = 0usize
            var outp = 8usize
            var q = 0usize
            while q < 8usize {
                packed[q] = 0u8
                q += 1usize
            }
            var ip = 0usize
            k = 0usize
            while k < nv {
                var cells = 1usize
                if s.is_text[k] != 0u8 { cells = swb[k] / 8usize }
                var c = 0usize
                while c < cells {
                    var raw = false
                    if s.is_text[k] != 0u8 {
                        var blank = true
                        q = 0usize
                        while q < 8usize {
                            if row[ip + q] != 32u8 { blank = false }
                            q += 1usize
                        }
                        if blank { packed[ctl] = 254u8 } else {
                            packed[ctl] = 253u8
                            raw = true
                        }
                    } else {
                        var bits = 0u64
                        q = 0usize
                        while q < 8usize {
                            bits = bits | (u64(row[ip + q]) << u64(8usize * q))
                            q += 1usize
                        }
                        let fv = mem.bitcast[f64](bits)
                        var small = false
                        if bits != SYSMIS && fv > -100.0f64 && fv < 152.0f64 {
                            if f64(i64(fv)) == fv { small = true }
                        }
                        if bits == SYSMIS {
                            packed[ctl] = 255u8
                        } else if small {
                            packed[ctl] = u8(i64(fv) + 100i64)
                        } else {
                            packed[ctl] = 253u8
                            raw = true
                        }
                    }
                    if raw {
                        q = 0usize
                        while q < 8usize {
                            packed[outp + q] = row[ip + q]
                            q += 1usize
                        }
                        outp += 8usize
                    }
                    ctl += 1usize
                    if ctl % 8usize == 0usize {
                        ctl = outp
                        q = 0usize
                        while q < 8usize {
                            packed[ctl + q] = 0u8
                            q += 1usize
                        }
                        outp += 8usize
                    }
                    ip += 8usize
                    c += 1usize
                }
                k += 1usize
            }
            if r + 1usize == s.nobs { packed[ctl] = 252u8 }
            if s.compression == 1i64 { put_row_bytes(&w, packed, outp) } else { put_row_bytes(&stream, packed, outp) }
        }
        r += 1usize
    }

    if s.compression == 2i64 {
        let block = 4190208usize
        let nblocks = (stream.n + block - 1usize) / block
        let zhead = w.n
        let (zb, z1) = mem.alloc[[]u8](a, nblocks + 1usize)
        if z1 != ok { ret (none, z1) }
        var ctotal = 0usize
        var bi = 0usize
        while bi < nblocks {
            var hi = (bi + 1usize) * block
            if hi > stream.n { hi = stream.n }
            let (blk, be) = zlib_block(a, stream.b[bi * block..hi])
            if be != ok { ret (none, be) }
            zb[bi] = blk
            ctotal += blk.len
            bi += 1usize
        }
        w_n(&w, u64(zhead), 8usize)
        w_n(&w, u64(zhead + 24usize + ctotal), 8usize)
        w_n(&w, u64(24usize + nblocks * 24usize), 8usize)
        bi = 0usize
        while bi < nblocks {
            put_row_bytes(&w, zb[bi], zb[bi].len)
            bi += 1usize
        }
        w_n(&w, mem.bitcast[u64](-100i64), 8usize)
        w_n(&w, 0u64, 8usize)
        w_i32(&w, i64(block))
        w_i32(&w, i64(nblocks))
        var uo = zhead
        var co = zhead + 24usize
        bi = 0usize
        while bi < nblocks {
            var us = block
            if (bi + 1usize) * block > stream.n { us = stream.n - bi * block }
            w_n(&w, u64(uo), 8usize)
            w_n(&w, u64(co), 8usize)
            w_i32(&w, i64(us))
            w_i32(&w, i64(zb[bi].len))
            uo += us
            co += zb[bi].len
            bi += 1usize
        }
    }
    if w.bad || stream.bad { ret (none, BadFile) }
    ret (w.b[..w.n], ok)
}
