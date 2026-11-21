// Stata .dta reader for every format haven reads (ReadStat 104 to 119: Stata 4 to 18): the dataset label, variable
// names, labels and formats, the values of every column (numbers as f64 with NaN for a missing code and the
// letter of a tagged missing value in `tags`, 0 for a plain one; strings as text; strLs followed) and the
// value-label tables. Text in formats below 118 is Windows-1252 and comes out as UTF-8. The byte order of the
// file (LSF or MSF) is honoured. Formats 113 to 119 are checked against files haven wrote; 104 to 112 and the
// narrow integer and float types against files built from the format description (scripts/make_haven_dta2.R).
//
// Not here: writing, the characteristics (notes) stored in the file.

use e.mem

error BadFile

type Dta = struct {
    version: i64,
    nvars: usize,
    nobs: usize,
    label: str,
    names: []str,
    varlabels: []str,
    formats: []str,
    types: []u32,
    kind: []u8,
    vlnames: []str,
    num: []f64,
    tags: []u8,
    text: []str,
    lbl_names: []str,
    lbl_first: []usize,
    lbl_count: []usize,
    lbl_codes: []f64,
    lbl_tags: []u8,
    lbl_texts: []str,
}

type Reader = struct { a: *mem.Arena, d: []const u8, big: bool, latin: bool }

// the integer of n bytes written with the file's byte order
fn le_or_be(r: *const Reader, at: usize, n: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < n {
        var idx = i
        if r.big { idx = n - 1usize - i }
        v = v | (u64(r.d[at + idx]) << u64(8usize * i))
        i += 1usize
    }
    ret v
}

fn signed(v: u64, bytes: usize) -> i64 {
    let bits = u64(8usize * bytes)
    let sign = 1u64 << (bits - 1u64)
    if v & sign != 0u64 { ret i64(v) - i64(1u64 << bits) }
    ret i64(v)
}

fn find_tag(d: []const u8, tag: str, from: usize) -> usize {
    var i = from
    while i + tag.len <= d.len {
        var k = 0usize
        while k < tag.len && d[i + k] == tag[k] { k += 1usize }
        if k == tag.len { ret i }
        i += 1usize
    }
    ret d.len
}

fn str_of(b: []const u8) -> str {
    var s: str = zero
    s = b
    ret s
}

fn cp1252_point(b: u8) -> u32 {
    if b < 128u8 || b >= 160u8 { ret u32(b) }
    if b == 128u8 { ret 8364u32 }
    if b == 130u8 { ret 8218u32 }
    if b == 131u8 { ret 402u32 }
    if b == 132u8 { ret 8222u32 }
    if b == 133u8 { ret 8230u32 }
    if b == 134u8 { ret 8224u32 }
    if b == 135u8 { ret 8225u32 }
    if b == 136u8 { ret 710u32 }
    if b == 137u8 { ret 8240u32 }
    if b == 138u8 { ret 352u32 }
    if b == 139u8 { ret 8249u32 }
    if b == 140u8 { ret 338u32 }
    if b == 142u8 { ret 381u32 }
    if b == 145u8 { ret 8216u32 }
    if b == 146u8 { ret 8217u32 }
    if b == 147u8 { ret 8220u32 }
    if b == 148u8 { ret 8221u32 }
    if b == 149u8 { ret 8226u32 }
    if b == 150u8 { ret 8211u32 }
    if b == 151u8 { ret 8212u32 }
    if b == 152u8 { ret 732u32 }
    if b == 153u8 { ret 8482u32 }
    if b == 154u8 { ret 353u32 }
    if b == 155u8 { ret 8250u32 }
    if b == 156u8 { ret 339u32 }
    if b == 158u8 { ret 382u32 }
    if b == 159u8 { ret 376u32 }
    ret u32(b)
}

// the text of b (already cut at its NUL), converted from Windows-1252 when the file is below format 118
fn conv(r: *const Reader, b: []const u8) -> str {
    if !r.latin { ret str_of(b) }
    var high = false
    var i = 0usize
    while i < b.len {
        if b[i] >= 128u8 { high = true }
        i += 1usize
    }
    if !high { ret str_of(b) }
    let (out, oe) = mem.alloc[u8](r.a, b.len * 3usize + 1usize)
    if oe != ok { ret str_of(b) }
    var n = 0usize
    i = 0usize
    while i < b.len {
        let cp = cp1252_point(b[i])
        if cp < 128u32 {
            out[n] = u8(cp)
            n += 1usize
        } else if cp < 2048u32 {
            out[n] = u8(192u32 | (cp >> 6u32))
            out[n + 1usize] = u8(128u32 | (cp & 63u32))
            n += 2usize
        } else {
            out[n] = u8(224u32 | (cp >> 12u32))
            out[n + 1usize] = u8(128u32 | ((cp >> 6u32) & 63u32))
            out[n + 2usize] = u8(128u32 | (cp & 63u32))
            n += 3usize
        }
        i += 1usize
    }
    ret str_of(out[..n])
}

fn c_string(r: *const Reader, at: usize, width: usize) -> str {
    var n = 0usize
    while n < width && r.d[at + n] != 0u8 { n += 1usize }
    ret conv(r, r.d[at..at + n])
}

// column kinds: 0 string, 1 byte, 2 int, 3 long, 4 float, 5 double, 6 strL, 255 unknown
fn kind_of(version: i64, t: u32) -> u8 {
    if version >= 117i64 {
        if t <= 2045u32 { ret 0u8 }
        if t == 32768u32 { ret 6u8 }
        if t == 65530u32 { ret 1u8 }
        if t == 65529u32 { ret 2u8 }
        if t == 65528u32 { ret 3u8 }
        if t == 65527u32 { ret 4u8 }
        if t == 65526u32 { ret 5u8 }
        ret 255u8
    }
    if version >= 111i64 {
        if t == 251u32 { ret 1u8 }
        if t == 252u32 { ret 2u8 }
        if t == 253u32 { ret 3u8 }
        if t == 254u32 { ret 4u8 }
        if t == 255u32 { ret 5u8 }
        if t >= 1u32 && t <= 244u32 { ret 0u8 }
        ret 255u8
    }
    if t == 98u32 { ret 1u8 }
    if t == 105u32 { ret 2u8 }
    if t == 108u32 { ret 3u8 }
    if t == 102u32 { ret 4u8 }
    if t == 100u32 { ret 5u8 }
    if t >= 127u32 { ret 0u8 }
    ret 255u8
}

fn width_of(version: i64, t: u32, kind: u8) -> usize {
    if kind == 1u8 { ret 1usize }
    if kind == 2u8 { ret 2usize }
    if kind == 3u8 || kind == 4u8 { ret 4usize }
    if kind == 5u8 || kind == 6u8 { ret 8usize }
    if version >= 111i64 { ret usize(t) }
    ret usize(t - 127u32)
}

// an integer cell: values above `top` are missing; from format 113 the values above `miss` are tagged .a to .z
fn int_cell(v: i64, top: i64, miss: i64, tagged: bool) -> (f64, u8) {
    var tag = 0u8
    if v > top {
        if tagged && v > miss { tag = u8(97i64 + (v - miss - 1i64)) }
        ret (0.0f64 / 0.0f64, tag)
    }
    ret (f64(v), tag)
}

// one numeric cell of the given kind at `at`; `new` is format 113 and later
fn num_cell(r: *const Reader, kind: u8, at: usize, new: bool) -> (f64, u8) {
    var top = 0i64
    var miss = 0i64
    if kind == 1u8 {
        top = 126i64
        miss = 127i64
        if new { top = 100i64 }
        if new { miss = 101i64 }
        let v = signed(le_or_be(r, at, 1usize), 1usize)
        let (rv, rt) = int_cell(v, top, miss, new)
        ret (rv, rt)
    }
    if kind == 2u8 {
        top = 32766i64
        miss = 32767i64
        if new { top = 32740i64 }
        if new { miss = 32741i64 }
        let v = signed(le_or_be(r, at, 2usize), 2usize)
        let (rv, rt) = int_cell(v, top, miss, new)
        ret (rv, rt)
    }
    if kind == 3u8 {
        top = 2147483646i64
        miss = 2147483647i64
        if new { top = 2147483620i64 }
        if new { miss = 2147483621i64 }
        let v = signed(le_or_be(r, at, 4usize), 4usize)
        let (rv, rt) = int_cell(v, top, miss, new)
        ret (rv, rt)
    }
    if kind == 4u8 {
        let bits = le_or_be(r, at, 4usize)
        let v = signed(bits, 4usize)
        if v > 2130706431i64 {
            var tag = 0u8
            if new && v > 2130706432i64 {
                let k = (v - 2130708480i64) >> 11u32
                if k >= 0i64 && k < 26i64 { tag = u8(97i64 + k) }
            }
            ret (0.0f64 / 0.0f64, tag)
        }
        ret (f64(mem.bitcast[f32](u32(bits))), 0u8)
    }
    let bits = le_or_be(r, at, 8usize)
    let v = mem.bitcast[i64](bits)
    if v > 9214364837600034815i64 {
        var tag = 0u8
        if new && v > 9214364837600034816i64 {
            let k = (v - 9214364837600034816i64 - 1099511627776i64) >> 40u32
            if k >= 0i64 && k < 26i64 { tag = u8(97i64 + k) }
        }
        ret (0.0f64 / 0.0f64, tag)
    }
    ret (mem.bitcast[f64](bits), 0u8)
}

type Strl = struct { count: usize, v: []u64, o: []u64, at: []usize, len: []usize }

// the GSO entries of the strL section (only the text ones, type 130)
fn strl_table(a: *mem.Arena, r: *const Reader, version: i64, from: usize) -> (Strl, err) {
    var none: Strl = zero
    let d = r.d
    var hdr = 11usize
    var ow = 4usize
    if version >= 118i64 {
        hdr = 15usize
        ow = 8usize
    }
    var n = 0usize
    var pass = 0usize
    var sv: []u64 = zero
    var so: []u64 = zero
    var sa: []usize = zero
    var sl: []usize = zero
    while pass < 2usize {
        var p = from
        var k = 0usize
        while p + hdr + 5usize <= d.len && d[p] == 71u8 && d[p + 1usize] == 83u8 && d[p + 2usize] == 79u8 {
            let ty = d[p + hdr]
            let ln = usize(le_or_be(r, p + hdr + 1usize, 4usize))
            if ty == 130u8 {
                if pass == 0usize { n += 1usize } else {
                    sv[k] = le_or_be(r, p + 3usize, 4usize) & 65535u64
                    so[k] = le_or_be(r, p + 7usize, ow)
                    sa[k] = p + hdr + 5usize
                    sl[k] = ln
                    k += 1usize
                }
            }
            p += hdr + 5usize + ln
        }
        if pass == 0usize {
            let (a1, e1) = mem.alloc[u64](a, n)
            let (a2, e2) = mem.alloc[u64](a, n)
            let (a3, e3) = mem.alloc[usize](a, n)
            let (a4, e4) = mem.alloc[usize](a, n)
            if e1 != ok { ret (none, e1) }
            if e2 != ok { ret (none, e2) }
            if e3 != ok { ret (none, e3) }
            if e4 != ok { ret (none, e4) }
            sv = a1
            so = a2
            sa = a3
            sl = a4
        }
        pass += 1usize
    }
    ret (Strl { count: n, v: sv, o: so, at: sa, len: sl }, ok)
}

fn strl_text(r: *const Reader, t: *const Strl, version: i64, at: usize) -> str {
    var v = 0u64
    var o = 0u64
    if version >= 118i64 {
        v = le_or_be(r, at, 2usize)
        o = le_or_be(r, at + 2usize, 6usize)
    } else {
        v = le_or_be(r, at, 4usize) & 65535u64
        o = le_or_be(r, at + 4usize, 4usize)
    }
    var i = 0usize
    while i < t.count {
        if t.v[i] == v && t.o[i] == o {
            var n = 0usize
            while n < t.len[i] && r.d[t.at[i] + n] != 0u8 { n += 1usize }
            ret conv(r, r.d[t.at[i]..t.at[i] + n])
        }
        i += 1usize
    }
    var blank: str = zero
    ret blank
}

// the table of value labels at p: its header size, body length and entry count, or valid = false at the end
type Table = struct { hdr: usize, len: usize, n: usize, txtlen: usize, valid: bool }

fn table_at(rd: *const Reader, version: i64, p: usize) -> Table {
    let data = rd.d
    var t = Table { hdr: 0usize, len: 0usize, n: 0usize, txtlen: 0usize, valid: false }
    var nw = 33usize
    if version >= 118i64 { nw = 129usize }
    if version < 105i64 {
        if p + 16usize > data.len { ret t }
        t.len = usize(le_or_be(rd, p, 2usize))
        t.hdr = 16usize
        t.n = t.len / 8usize
        if p + t.hdr + t.len > data.len { ret t }
        t.valid = true
        ret t
    }
    if version >= 117i64 {
        if p + 9usize > data.len { ret t }
        if !(data[p] == 60u8 && data[p + 1usize] == 108u8 && data[p + 2usize] == 98u8 && data[p + 3usize] == 108u8) { ret t }
        t.len = usize(le_or_be(rd, p + 5usize, 4usize))
        t.hdr = 9usize + nw + 3usize
    } else {
        if p + 4usize + nw + 3usize > data.len { ret t }
        t.len = usize(le_or_be(rd, p, 4usize))
        t.hdr = 4usize + nw + 3usize
    }
    if p + t.hdr + t.len > data.len { ret t }
    if t.len < 8usize { ret t }
    t.n = usize(le_or_be(rd, p + t.hdr, 4usize))
    t.txtlen = usize(le_or_be(rd, p + t.hdr + 4usize, 4usize))
    if t.txtlen > t.len - 8usize { ret t }
    if t.n > (t.len - 8usize - t.txtlen) / 8usize { ret t }
    t.valid = true
    ret t
}

fn next_table(version: i64, p: usize, t: *const Table) -> usize {
    var q = p + t.hdr + t.len
    if version >= 117i64 { q += 6usize }
    ret q
}

// everything after the descriptors is shared: the data rows at `ds` and the value labels at `vs`
fn finish(a: *mem.Arena, rd: *const Reader, version: i64, nvars: usize, nobs: usize, label: str, names: []str, fmts: []str, vln: []str, vlab: []str, types: []u32, kind: []u8, ds: usize, vs: usize, strls: *const Strl) -> (Dta, err) {
    var none: Dta = zero
    let data = rd.d
    let new = version >= 113i64
    var rowbytes = 0usize
    var i = 0usize
    while i < nvars {
        rowbytes += width_of(version, types[i], kind[i])
        i += 1usize
    }
    if ds + rowbytes * nobs > data.len { ret (none, BadFile) }
    let (num, nume) = mem.alloc[f64](a, nobs * nvars)
    let (tg, tge) = mem.alloc[u8](a, nobs * nvars)
    let (txt, txte) = mem.alloc[str](a, nobs * nvars)
    if nume != ok { ret (none, nume) }
    if tge != ok { ret (none, tge) }
    if txte != ok { ret (none, txte) }
    var r = 0usize
    while r < nobs {
        var off = ds + r * rowbytes
        var c = 0usize
        while c < nvars {
            let k = kind[c]
            let w = width_of(version, types[c], k)
            var v = 0.0f64 / 0.0f64
            var tag = 0u8
            var s: str = zero
            if k == 0u8 {
                s = c_string(rd, off, w)
            } else if k == 6u8 {
                s = strl_text(rd, strls, version, off)
            } else {
                let (rv, rt) = num_cell(rd, k, off, new)
                v = rv
                tag = rt
            }
            num[r * nvars + c] = v
            tg[r * nvars + c] = tag
            txt[r * nvars + c] = s
            off += w
            c += 1usize
        }
        r += 1usize
    }
    // value labels: count the tables and entries, then fill
    var nw = 33usize
    if version >= 118i64 { nw = 129usize }
    var nl = 0usize
    var total = 0usize
    var p = vs
    var go = true
    while go {
        let t = table_at(rd, version, p)
        if !t.valid { go = false } else {
            nl += 1usize
            total += t.n
            p = next_table(version, p, &t)
        }
    }
    let (ln_names, lne) = mem.alloc[str](a, nl)
    let (lfirst, lfe) = mem.alloc[usize](a, nl)
    let (lcount, lce) = mem.alloc[usize](a, nl)
    let (codes, ce) = mem.alloc[f64](a, total)
    let (ltags, lte) = mem.alloc[u8](a, total)
    let (texts, tx) = mem.alloc[str](a, total)
    if lne != ok { ret (none, lne) }
    if lfe != ok { ret (none, lfe) }
    if lce != ok { ret (none, lce) }
    if ce != ok { ret (none, ce) }
    if lte != ok { ret (none, lte) }
    if tx != ok { ret (none, tx) }
    p = vs
    var k = 0usize
    var at2 = 0usize
    while k < nl {
        let t = table_at(rd, version, p)
        let body = p + t.hdr
        lfirst[k] = at2
        lcount[k] = t.n
        var j = 0usize
        if version < 105i64 {
            ln_names[k] = c_string(rd, p + 2usize, 12usize)
            while j < t.n {
                codes[at2 + j] = f64(j)
                ltags[at2 + j] = 0u8
                texts[at2 + j] = c_string(rd, body + 8usize * j, 8usize)
                j += 1usize
            }
        } else {
            ln_names[k] = c_string(rd, p + t.hdr - 3usize - nw, nw)
            let offs = body + 8usize
            let vals = offs + 4usize * t.n
            let tbase = vals + 4usize * t.n
            while j < t.n {
                let o = usize(le_or_be(rd, offs + 4usize * j, 4usize))
                let (rv, rt) = num_cell(rd, 3u8, vals + 4usize * j, new)
                codes[at2 + j] = rv
                ltags[at2 + j] = rt
                if o < t.txtlen { texts[at2 + j] = c_string(rd, tbase + o, t.txtlen - o) }
                j += 1usize
            }
        }
        at2 += t.n
        p = next_table(version, p, &t)
        k += 1usize
    }
    ret (Dta { version: version, nvars: nvars, nobs: nobs, label: label, names: names, varlabels: vlab, formats: fmts, types: types, kind: kind, vlnames: vln, num: num, tags: tg, text: txt, lbl_names: ln_names, lbl_first: lfirst, lbl_count: lcount, lbl_codes: codes, lbl_tags: ltags, lbl_texts: texts }, ok)
}

type Cols = struct { types: []u32, kind: []u8, names: []str, fmts: []str, vln: []str, vlab: []str }

fn cols_alloc(a: *mem.Arena, nvars: usize) -> (Cols, err) {
    var none: Cols = zero
    let (types, te) = mem.alloc[u32](a, nvars)
    let (kind, ke) = mem.alloc[u8](a, nvars)
    let (names, ne) = mem.alloc[str](a, nvars)
    let (fmts, fe) = mem.alloc[str](a, nvars)
    let (vln, vle) = mem.alloc[str](a, nvars)
    let (vlab, vlae) = mem.alloc[str](a, nvars)
    if te != ok { ret (none, te) }
    if ke != ok { ret (none, ke) }
    if ne != ok { ret (none, ne) }
    if fe != ok { ret (none, fe) }
    if vle != ok { ret (none, vle) }
    if vlae != ok { ret (none, vlae) }
    ret (Cols { types: types, kind: kind, names: names, fmts: fmts, vln: vln, vlab: vlab }, ok)
}

// formats 117 to 119: tagged sections
fn read_xml(a: *mem.Arena, data: []const u8) -> (Dta, err) {
    var none: Dta = zero
    var rd = Reader { a: a, d: data, big: false, latin: false }
    var at = find_tag(data, "<release>", 0usize)
    if at >= data.len { ret (none, BadFile) }
    at += 9usize
    let version = i64(data[at] - 48u8) * 100i64 + i64(data[at + 1usize] - 48u8) * 10i64 + i64(data[at + 2usize] - 48u8)
    if version != 117i64 && version != 118i64 && version != 119i64 { ret (none, BadFile) }
    rd.latin = version < 118i64
    let bo = find_tag(data, "<byteorder>", at)
    if bo >= data.len { ret (none, BadFile) }
    rd.big = data[bo + 11usize] == 77u8
    let kt = find_tag(data, "<K>", bo)
    var kw = 2usize
    if version == 119i64 { kw = 4usize }
    let nvars = usize(le_or_be(&rd, kt + 3usize, kw))
    let nt = find_tag(data, "<N>", kt)
    var nobs = 0usize
    var lt = 0usize
    if version >= 118i64 {
        nobs = usize(le_or_be(&rd, nt + 3usize, 8usize))
        lt = nt + 3usize + 8usize
    } else {
        nobs = usize(le_or_be(&rd, nt + 3usize, 4usize))
        lt = nt + 3usize + 4usize
    }
    let lbl = find_tag(data, "<label>", lt)
    var label: str = zero
    if version >= 118i64 {
        let ln = usize(le_or_be(&rd, lbl + 7usize, 2usize))
        label = conv(&rd, data[lbl + 9usize..lbl + 9usize + ln])
    } else {
        let ln = usize(data[lbl + 7usize])
        label = conv(&rd, data[lbl + 8usize..lbl + 8usize + ln])
    }
    var nw = 33usize
    var fw = 49usize
    var vw = 81usize
    if version >= 118i64 {
        nw = 129usize
        fw = 57usize
        vw = 321usize
    }
    let (cl, ce) = cols_alloc(a, nvars)
    if ce != ok { ret (none, ce) }
    let tt = find_tag(data, "<variable_types>", 0usize) + 16usize
    let nm = find_tag(data, "<varnames>", 0usize) + 10usize
    let fm = find_tag(data, "<formats>", 0usize) + 9usize
    let vn = find_tag(data, "<value_label_names>", 0usize) + 19usize
    let vl = find_tag(data, "<variable_labels>", 0usize) + 17usize
    var i = 0usize
    while i < nvars {
        cl.types[i] = u32(le_or_be(&rd, tt + 2usize * i, 2usize))
        cl.kind[i] = kind_of(version, cl.types[i])
        if cl.kind[i] == 255u8 { ret (none, BadFile) }
        cl.names[i] = c_string(&rd, nm + nw * i, nw)
        cl.fmts[i] = c_string(&rd, fm + fw * i, fw)
        cl.vln[i] = c_string(&rd, vn + nw * i, nw)
        cl.vlab[i] = c_string(&rd, vl + vw * i, vw)
        i += 1usize
    }
    let ds = find_tag(data, "<data>", 0usize) + 6usize
    var vs = find_tag(data, "<value_labels>", 0usize)
    if vs >= data.len { ret (none, BadFile) }
    vs += 14usize
    var strls: Strl = zero
    let sp = find_tag(data, "<strls>", ds)
    if sp < data.len {
        let (st, se) = strl_table(a, &rd, version, sp + 7usize)
        if se != ok { ret (none, se) }
        strls = st
    }
    let (dd, de) = finish(a, &rd, version, nvars, nobs, label, cl.names, cl.fmts, cl.vln, cl.vlab, cl.types, cl.kind, ds, vs, &strls)
    ret (dd, de)
}

// formats 104 to 116: a fixed header and sequential sections
fn read_bin(a: *mem.Arena, data: []const u8) -> (Dta, err) {
    var none: Dta = zero
    var rd = Reader { a: a, d: data, big: false, latin: true }
    if data.len < 10usize { ret (none, BadFile) }
    let version = i64(data[0usize])
    if version < 104i64 || version > 116i64 { ret (none, BadFile) }
    if data[1usize] == 1u8 { rd.big = true } else if data[1usize] != 2u8 { ret (none, BadFile) }
    let nvars = usize(le_or_be(&rd, 4usize, 2usize))
    let nobs = usize(le_or_be(&rd, 6usize, 4usize))
    var p = 10usize
    var lablen = 32usize
    if version >= 108i64 { lablen = 81usize }
    var nw = 9usize
    if version >= 110i64 { nw = 33usize }
    var fw = 7usize
    if version >= 114i64 { fw = 49usize } else if version >= 105i64 { fw = 12usize }
    if p + lablen > data.len { ret (none, BadFile) }
    let label = c_string(&rd, p, lablen)
    p += lablen
    if version >= 105i64 { p += 18usize }
    let (cl, ce) = cols_alloc(a, nvars)
    if ce != ok { ret (none, ce) }
    if p + nvars + nvars * nw + 2usize * (nvars + 1usize) + nvars * fw + nvars * nw + nvars * lablen > data.len { ret (none, BadFile) }
    let tt = p
    p += nvars
    let nm = p
    p += nvars * nw
    p += 2usize * (nvars + 1usize)
    let fm = p
    p += nvars * fw
    let vn = p
    p += nvars * nw
    let vl = p
    p += nvars * lablen
    var i = 0usize
    while i < nvars {
        cl.types[i] = u32(data[tt + i])
        cl.kind[i] = kind_of(version, cl.types[i])
        if cl.kind[i] == 255u8 { ret (none, BadFile) }
        cl.names[i] = c_string(&rd, nm + nw * i, nw)
        cl.fmts[i] = c_string(&rd, fm + fw * i, fw)
        cl.vln[i] = c_string(&rd, vn + nw * i, nw)
        cl.vlab[i] = c_string(&rd, vl + lablen * i, lablen)
        i += 1usize
    }
    // the characteristics: (type, length, bytes) until a zero type and length
    if version >= 105i64 {
        var elen = 4usize
        if version < 110i64 { elen = 2usize }
        var go = true
        while go {
            if p + 1usize + elen > data.len { ret (none, BadFile) }
            let ty = data[p]
            let ln = usize(le_or_be(&rd, p + 1usize, elen))
            p += 1usize + elen
            if ty == 0u8 && ln == 0usize { go = false } else {
                if ty != 1u8 { ret (none, BadFile) }
                p += ln
            }
        }
    }
    var rowbytes = 0usize
    i = 0usize
    while i < nvars {
        rowbytes += width_of(version, cl.types[i], cl.kind[i])
        i += 1usize
    }
    let ds = p
    let vs = ds + rowbytes * nobs
    var strls: Strl = zero
    let (dd, de) = finish(a, &rd, version, nvars, nobs, label, cl.names, cl.fmts, cl.vln, cl.vlab, cl.types, cl.kind, ds, vs, &strls)
    ret (dd, de)
}

fn read(a: *mem.Arena, data: []const u8) -> (Dta, err) {
    var none: Dta = zero
    if data.len < 10usize { ret (none, BadFile) }
    if data[0usize] == 60u8 {
        let (xd, xe) = read_xml(a, data)
        ret (xd, xe)
    }
    let (bd, be) = read_bin(a, data)
    ret (bd, be)
}

// ---- writing ----

fn put_n(b: []u8, p: usize, v: u64, n: usize) -> usize {
    var i = 0usize
    while i < n {
        b[p + i] = u8((v >> u64(8usize * i)) & 255u64)
        i += 1usize
    }
    ret p + n
}

fn put_s(b: []u8, p: usize, s: str) -> usize {
    var i = 0usize
    while i < s.len {
        b[p + i] = s[i]
        i += 1usize
    }
    ret p + s.len
}

// s in a field of w bytes, NUL padded (and cut when longer)
fn put_f(b: []u8, p: usize, s: str, w: usize) -> usize {
    var i = 0usize
    while i < w {
        if i < s.len { b[p + i] = s[i] } else { b[p + i] = 0u8 }
        i += 1usize
    }
    ret p + w
}

// the cell of a column kind: a value, or the missing code of its tag (format 113 and later)
fn put_cell(b: []u8, p: usize, kind: u8, v: f64, tag: u8) -> usize {
    var k = 0i64
    if tag >= 97u8 { k = i64(tag) - 96i64 }
    if kind == 1u8 {
        if v == v { ret put_n(b, p, mem.bitcast[u64](i64(v)) & 255u64, 1usize) }
        ret put_n(b, p, u64(101i64 + k), 1usize)
    }
    if kind == 2u8 {
        if v == v { ret put_n(b, p, mem.bitcast[u64](i64(v)) & 65535u64, 2usize) }
        ret put_n(b, p, u64(32741i64 + k), 2usize)
    }
    if kind == 3u8 {
        if v == v { ret put_n(b, p, mem.bitcast[u64](i64(v)) & 4294967295u64, 4usize) }
        ret put_n(b, p, u64(2147483621i64 + k), 4usize)
    }
    if kind == 4u8 {
        if v == v { ret put_n(b, p, u64(mem.bitcast[u32](f32(v))), 4usize) }
        ret put_n(b, p, u64(2130706432i64 + (k << 11u32)), 4usize)
    }
    if v == v { ret put_n(b, p, mem.bitcast[u64](v), 8usize) }
    ret put_n(b, p, u64(9214364837600034816i64 + (k << 40u32)), 8usize)
}

// the file for `d` in format `version` (113 to 119) with the timestamp text `stamp`, little-endian
fn write_raw(a: *mem.Arena, d: *const Dta, version: i64, stamp: str) -> ([]u8, err) {
    var none: []u8 = zero
    if version < 113i64 || version > 119i64 { ret (none, BadFile) }
    let xml = version >= 117i64
    var nw = 33usize
    var fw = 49usize
    var vw = 81usize
    if version < 114i64 { fw = 12usize }
    if version >= 118i64 {
        nw = 129usize
        fw = 57usize
        vw = 321usize
    }
    let nvars = d.nvars
    let nobs = d.nobs
    var rowbytes = 0usize
    var strl_bytes = 0usize
    var i = 0usize
    while i < nvars {
        let k = d.kind[i]
        if k == 6u8 {
            if !xml { ret (none, BadFile) }
            var r = 0usize
            while r < nobs {
                strl_bytes += d.text[r * nvars + i].len + 25usize
                r += 1usize
            }
        }
        rowbytes += width_of(d.version, d.types[i], k)
        i += 1usize
    }
    var lbytes = 64usize
    var t = 0usize
    while t < d.lbl_names.len {
        lbytes += nw + 48usize
        t += 1usize
    }
    var e = 0usize
    while e < d.lbl_texts.len {
        lbytes += 16usize + d.lbl_texts[e].len
        e += 1usize
    }
    let cap = 2048usize + nvars * (nw * 2usize + fw + vw + 6usize) + rowbytes * nobs + strl_bytes + lbytes + d.label.len + stamp.len
    let (b, be) = mem.alloc[u8](a, cap)
    if be != ok { ret (none, be) }
    let (m, me) = mem.alloc[usize](a, 14usize)
    if me != ok { ret (none, me) }
    var p = 0usize
    var map = 0usize
    if xml {
        p = put_s(b, p, "<stata_dta><header><release>")
        p = put_n(b, p, u64(48i64 + version / 100i64), 1usize)
        p = put_n(b, p, u64(48i64 + (version / 10i64) % 10i64), 1usize)
        p = put_n(b, p, u64(48i64 + version % 10i64), 1usize)
        p = put_s(b, p, "</release><byteorder>LSF</byteorder><K>")
        if version >= 119i64 { p = put_n(b, p, u64(nvars), 4usize) } else { p = put_n(b, p, u64(nvars), 2usize) }
        p = put_s(b, p, "</K><N>")
        if version >= 118i64 { p = put_n(b, p, u64(nobs), 8usize) } else { p = put_n(b, p, u64(nobs), 4usize) }
        p = put_s(b, p, "</N><label>")
        if version >= 118i64 { p = put_n(b, p, u64(d.label.len), 2usize) } else { p = put_n(b, p, u64(d.label.len), 1usize) }
        p = put_s(b, p, d.label)
        p = put_s(b, p, "</label><timestamp>")
        p = put_n(b, p, u64(stamp.len), 1usize)
        p = put_s(b, p, stamp)
        p = put_s(b, p, "</timestamp></header>")
        m[0usize] = 0usize
        m[1usize] = p
        p = put_s(b, p, "<map>")
        map = p
        p += 112usize
        p = put_s(b, p, "</map>")
        m[2usize] = p
        p = put_s(b, p, "<variable_types>")
    } else {
        p = put_n(b, p, u64(version), 1usize)
        p = put_n(b, p, 2u64, 1usize)
        p = put_n(b, p, 1u64, 1usize)
        p = put_n(b, p, 0u64, 1usize)
        p = put_n(b, p, u64(nvars), 2usize)
        p = put_n(b, p, u64(nobs), 4usize)
        p = put_f(b, p, d.label, 81usize)
        p = put_f(b, p, stamp, 18usize)
    }
    i = 0usize
    while i < nvars {
        let k = d.kind[i]
        var tc = 0u64
        if k == 0u8 {
            tc = u64(width_of(d.version, d.types[i], k))
        } else if xml {
            if k == 6u8 { tc = 32768u64 } else { tc = u64(65531usize - usize(k)) }
        } else {
            tc = u64(250usize + usize(k))
        }
        if xml { p = put_n(b, p, tc, 2usize) } else { p = put_n(b, p, tc, 1usize) }
        i += 1usize
    }
    if xml {
        p = put_s(b, p, "</variable_types>")
        m[3usize] = p
        p = put_s(b, p, "<varnames>")
    }
    i = 0usize
    while i < nvars {
        p = put_f(b, p, d.names[i], nw)
        i += 1usize
    }
    if xml {
        p = put_s(b, p, "</varnames>")
        m[4usize] = p
        p = put_s(b, p, "<sortlist>")
    }
    var sl = 2usize * (nvars + 1usize)
    if version >= 119i64 { sl = 4usize * (nvars + 1usize) }
    i = 0usize
    while i < sl {
        b[p + i] = 0u8
        i += 1usize
    }
    p += sl
    if xml {
        p = put_s(b, p, "</sortlist>")
        m[5usize] = p
        p = put_s(b, p, "<formats>")
    }
    i = 0usize
    while i < nvars {
        p = put_f(b, p, d.formats[i], fw)
        i += 1usize
    }
    if xml {
        p = put_s(b, p, "</formats>")
        m[6usize] = p
        p = put_s(b, p, "<value_label_names>")
    }
    i = 0usize
    while i < nvars {
        p = put_f(b, p, d.vlnames[i], nw)
        i += 1usize
    }
    if xml {
        p = put_s(b, p, "</value_label_names>")
        m[7usize] = p
        p = put_s(b, p, "<variable_labels>")
    }
    i = 0usize
    while i < nvars {
        p = put_f(b, p, d.varlabels[i], vw)
        i += 1usize
    }
    if xml {
        p = put_s(b, p, "</variable_labels>")
        m[8usize] = p
        p = put_s(b, p, "<characteristics></characteristics>")
        m[9usize] = p
        p = put_s(b, p, "<data>")
    } else {
        p = put_n(b, p, 0u64, 1usize)
        p = put_n(b, p, 0u64, 4usize)
    }
    var r = 0usize
    while r < nobs {
        i = 0usize
        while i < nvars {
            let k = d.kind[i]
            let at = r * nvars + i
            if k == 0u8 {
                p = put_f(b, p, d.text[at], width_of(d.version, d.types[i], k))
            } else if k == 6u8 {
                if version >= 118i64 {
                    p = put_n(b, p, u64(i + 1usize), 2usize)
                    p = put_n(b, p, u64(r + 1usize), 6usize)
                } else {
                    p = put_n(b, p, u64(i + 1usize), 4usize)
                    p = put_n(b, p, u64(r + 1usize), 4usize)
                }
            } else {
                p = put_cell(b, p, k, d.num[at], d.tags[at])
            }
            i += 1usize
        }
        r += 1usize
    }
    if xml {
        p = put_s(b, p, "</data>")
        m[10usize] = p
        p = put_s(b, p, "<strls>")
        r = 0usize
        while r < nobs {
            i = 0usize
            while i < nvars {
                if d.kind[i] == 6u8 {
                    let s = d.text[r * nvars + i]
                    p = put_s(b, p, "GSO")
                    p = put_n(b, p, u64(i + 1usize), 4usize)
                    if version >= 118i64 { p = put_n(b, p, u64(r + 1usize), 8usize) } else { p = put_n(b, p, u64(r + 1usize), 4usize) }
                    p = put_n(b, p, 130u64, 1usize)
                    p = put_n(b, p, u64(s.len + 1usize), 4usize)
                    p = put_s(b, p, s)
                    p = put_n(b, p, 0u64, 1usize)
                }
                i += 1usize
            }
            r += 1usize
        }
        p = put_s(b, p, "</strls>")
        m[11usize] = p
        p = put_s(b, p, "<value_labels>")
    }
    t = 0usize
    while t < d.lbl_names.len {
        var txtlen = 0usize
        var j = 0usize
        while j < d.lbl_count[t] {
            txtlen += d.lbl_texts[d.lbl_first[t] + j].len + 1usize
            j += 1usize
        }
        let n = d.lbl_count[t]
        if xml { p = put_s(b, p, "<lbl>") }
        p = put_n(b, p, u64(8usize + 8usize * n + txtlen), 4usize)
        p = put_f(b, p, d.lbl_names[t], nw)
        p = put_n(b, p, 0u64, 3usize)
        p = put_n(b, p, u64(n), 4usize)
        p = put_n(b, p, u64(txtlen), 4usize)
        var off = 0usize
        j = 0usize
        while j < n {
            p = put_n(b, p, u64(off), 4usize)
            off += d.lbl_texts[d.lbl_first[t] + j].len + 1usize
            j += 1usize
        }
        j = 0usize
        while j < n {
            p = put_cell(b, p, 3u8, d.lbl_codes[d.lbl_first[t] + j], d.lbl_tags[d.lbl_first[t] + j])
            j += 1usize
        }
        j = 0usize
        while j < n {
            p = put_s(b, p, d.lbl_texts[d.lbl_first[t] + j])
            p = put_n(b, p, 0u64, 1usize)
            j += 1usize
        }
        if xml { p = put_s(b, p, "</lbl>") }
        t += 1usize
    }
    if xml {
        p = put_s(b, p, "</value_labels>")
        m[12usize] = p
        p = put_s(b, p, "</stata_dta>")
        m[13usize] = p
        i = 0usize
        while i < 14usize {
            let _ = put_n(b, map + 8usize * i, u64(m[i]), 8usize)
            i += 1usize
        }
    }
    ret (b[..p], ok)
}

fn latin_byte(cp: u32) -> u8 {
    if cp < 128u32 || (cp >= 160u32 && cp < 256u32) { ret u8(cp) }
    var b = 128u8
    while b < 160u8 {
        if cp1252_point(b) == cp { ret b }
        b += 1u8
    }
    ret 63u8
}

// UTF-8 text as Windows-1252 bytes (what formats below 118 store); text without high bytes is returned as is
fn to_latin(a: *mem.Arena, s: str) -> str {
    var high = false
    var i = 0usize
    while i < s.len {
        if s[i] >= 128u8 { high = true }
        i += 1usize
    }
    if !high { ret s }
    let (out, oe) = mem.alloc[u8](a, s.len)
    if oe != ok { ret s }
    var n = 0usize
    i = 0usize
    while i < s.len {
        let c = u32(s[i])
        var cp = c
        var step = 1usize
        if c >= 240u32 && i + 3usize < s.len {
            cp = ((c & 7u32) << 18u32) | (u32(s[i + 1usize] & 63u8) << 12u32) | (u32(s[i + 2usize] & 63u8) << 6u32) | u32(s[i + 3usize] & 63u8)
            step = 4usize
        } else if c >= 224u32 && i + 2usize < s.len {
            cp = ((c & 15u32) << 12u32) | (u32(s[i + 1usize] & 63u8) << 6u32) | u32(s[i + 2usize] & 63u8)
            step = 3usize
        } else if c >= 192u32 && i + 1usize < s.len {
            cp = ((c & 31u32) << 6u32) | u32(s[i + 1usize] & 63u8)
            step = 2usize
        }
        out[n] = latin_byte(cp)
        n += 1usize
        i += step
    }
    ret str_of(out[..n])
}

// the file for `d` in format `version` (113 to 119) with the timestamp text `stamp`, little-endian; formats below 118
// store Windows-1252, so the text is converted back from UTF-8 (what the reader gave) first
fn write(a: *mem.Arena, d: *const Dta, version: i64, stamp: str) -> ([]u8, err) {
    var none: []u8 = zero
    if version >= 118i64 {
        let (o1, e1) = write_raw(a, d, version, stamp)
        ret (o1, e1)
    }
    let (names, e1) = mem.alloc[str](a, d.nvars)
    let (vlab, e2) = mem.alloc[str](a, d.nvars)
    let (fmts, e3) = mem.alloc[str](a, d.nvars)
    let (vln, e4) = mem.alloc[str](a, d.nvars)
    let (txt, e5) = mem.alloc[str](a, d.nobs * d.nvars)
    let (lt, e6) = mem.alloc[str](a, d.lbl_texts.len)
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    if e5 != ok { ret (none, e5) }
    if e6 != ok { ret (none, e6) }
    var i = 0usize
    while i < d.nvars {
        names[i] = to_latin(a, d.names[i])
        vlab[i] = to_latin(a, d.varlabels[i])
        fmts[i] = to_latin(a, d.formats[i])
        vln[i] = to_latin(a, d.vlnames[i])
        i += 1usize
    }
    i = 0usize
    while i < txt.len {
        txt[i] = to_latin(a, d.text[i])
        i += 1usize
    }
    i = 0usize
    while i < lt.len {
        lt[i] = to_latin(a, d.lbl_texts[i])
        i += 1usize
    }
    let dd = Dta { version: d.version, nvars: d.nvars, nobs: d.nobs, label: to_latin(a, d.label), names: names, varlabels: vlab, formats: fmts, types: d.types, kind: d.kind, vlnames: vln, num: d.num, tags: d.tags, text: txt, lbl_names: d.lbl_names, lbl_first: d.lbl_first, lbl_count: d.lbl_count, lbl_codes: d.lbl_codes, lbl_tags: d.lbl_tags, lbl_texts: lt }
    let (o2, e7) = write_raw(a, &dd, version, stamp)
    ret (o2, e7)
}

fn starts_with(s: str, p: str) -> bool {
    if s.len < p.len { ret false }
    var i = 0usize
    while i < p.len {
        if s[i] != p[i] { ret false }
        i += 1usize
    }
    ret true
}

// haven's adjustDatetimeToR for Stata: %td and %d are days since 1960 (R: days since 1970), %tc and %tC milliseconds since 1960
// (R: seconds since 1970); every other format, and a missing value, is the raw number
fn value(d: *const Dta, row: usize, col: usize) -> f64 {
    let x = d.num[row * d.nvars + col]
    if x != x { ret x }
    let f = d.formats[col]
    if starts_with(f, "%tC") || starts_with(f, "%tc") { ret x / 1000.0f64 - 3653.0f64 * 86400.0f64 }
    if starts_with(f, "%td") || starts_with(f, "%d") { ret x - 3653.0f64 }
    ret x
}
