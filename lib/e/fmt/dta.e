// Stata .dta reader for formats 117, 118 and 119 (Stata 13 to 18): the dataset label, variable names, labels and
// formats, the values of every column (numbers as f64 with NaN for the missing codes, strings as text; strLs
// are not followed) and the value-label tables. The byte order of the file (LSF or MSF) is honoured.
//
// Not here: formats 102 to 116, strL contents, tagged missing values (they read as NaN), writing.

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
    vlnames: []str,
    num: []f64,
    text: []str,
    lbl_names: []str,
    lbl_first: []usize,
    lbl_count: []usize,
    lbl_codes: []i32,
    lbl_texts: []str,
}

type Reader = struct { d: []const u8, big: bool }

fn u8_at(r: *const Reader, at: usize) -> u64 { ret u64(r.d[at]) }

fn uint(r: *const Reader, at: usize, n: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < n {
        var b = r.d[at + i]
        if r.big { b = r.d[at + n - 1usize - i] }
        v = v | (u64(b) << u64(8usize * (n - 1usize - i)))
        i += 1usize
    }
    ret v
}

// the integer of n bytes written with the file's byte order, little first when i counts from 0
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

fn c_string(d: []const u8, at: usize, width: usize) -> str {
    var n = 0usize
    while n < width && d[at + n] != 0u8 { n += 1usize }
    ret str_of(d[at..at + n])
}

fn str_of(b: []const u8) -> str { ret str_from_bytes(b) }

fn str_from_bytes(b: []const u8) -> str {
    var s: str = zero
    s = b
    ret s
}

fn f64_bits_ok(bits: u64) -> f64 { ret mem.bitcast[f64](bits) }

fn f32_from_bits(bits: u64) -> f64 { ret f64(mem.bitcast[f32](u32(bits))) }

fn width_of(t: u32) -> usize {
    if t <= 2045u32 { ret usize(t) }
    if t == 32768u32 { ret 8usize }
    if t == 65526u32 { ret 8usize }
    if t == 65527u32 { ret 4usize }
    if t == 65528u32 { ret 4usize }
    if t == 65529u32 { ret 2usize }
    ret 1usize
}

fn read(a: *mem.Arena, data: []const u8) -> (Dta, err) {
    var none: Dta = zero
    var rd = Reader { d: data, big: false }
    var at = find_tag(data, "<release>", 0usize)
    if at >= data.len { ret (none, BadFile) }
    at += 9usize
    let version = i64(data[at] - 48u8) * 100i64 + i64(data[at + 1usize] - 48u8) * 10i64 + i64(data[at + 2usize] - 48u8)
    if version != 117i64 && version != 118i64 && version != 119i64 { ret (none, BadFile) }
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
        label = str_of(data[lbl + 9usize..lbl + 9usize + ln])
    } else {
        let ln = usize(data[lbl + 7usize])
        label = str_of(data[lbl + 8usize..lbl + 8usize + ln])
    }
    var nw = 33usize
    var fw = 49usize
    var vw = 81usize
    if version >= 118i64 {
        nw = 129usize
        fw = 57usize
        vw = 321usize
    }
    let (types, te) = mem.alloc[u32](a, nvars)
    let (names, ne) = mem.alloc[str](a, nvars)
    let (fmts, fe) = mem.alloc[str](a, nvars)
    let (vln, vle) = mem.alloc[str](a, nvars)
    let (vlab, vlae) = mem.alloc[str](a, nvars)
    if te != ok { ret (none, te) }
    if ne != ok { ret (none, ne) }
    if fe != ok { ret (none, fe) }
    if vle != ok { ret (none, vle) }
    if vlae != ok { ret (none, vlae) }
    let tt = find_tag(data, "<variable_types>", 0usize) + 16usize
    let nm = find_tag(data, "<varnames>", 0usize) + 10usize
    let fm = find_tag(data, "<formats>", 0usize) + 9usize
    let vn = find_tag(data, "<value_label_names>", 0usize) + 19usize
    let vl = find_tag(data, "<variable_labels>", 0usize) + 17usize
    var i = 0usize
    while i < nvars {
        types[i] = u32(le_or_be(&rd, tt + 2usize * i, 2usize))
        names[i] = c_string(data, nm + nw * i, nw)
        fmts[i] = c_string(data, fm + fw * i, fw)
        vln[i] = c_string(data, vn + nw * i, nw)
        vlab[i] = c_string(data, vl + vw * i, vw)
        i += 1usize
    }
    var rowbytes = 0usize
    i = 0usize
    while i < nvars {
        rowbytes += width_of(types[i])
        i += 1usize
    }
    let ds = find_tag(data, "<data>", 0usize) + 6usize
    let (num, nume) = mem.alloc[f64](a, nobs * nvars)
    let (txt, txte) = mem.alloc[str](a, nobs * nvars)
    if nume != ok { ret (none, nume) }
    if txte != ok { ret (none, txte) }
    var r = 0usize
    while r < nobs {
        var off = ds + r * rowbytes
        var c = 0usize
        while c < nvars {
            let t = types[c]
            let w = width_of(t)
            var v = 0.0f64 / 0.0f64
            var s: str = zero
            if t <= 2045u32 {
                s = c_string(data, off, w)
            } else if t == 65526u32 {
                let bits = le_or_be(&rd, off, 8usize)
                if bits < 9214364837600034816u64 || (bits >> 63u64) == 1u64 { v = f64_bits_ok(bits) }
                if (bits >> 63u64) == 0u64 && bits >= 9214364837600034816u64 { v = 0.0f64 / 0.0f64 }
            } else if t == 65527u32 {
                let bits = le_or_be(&rd, off, 4usize)
                if bits < 2130706432u64 || (bits >> 31u64) == 1u64 { v = f32_from_bits(bits) }
            } else if t == 65528u32 {
                let iv = signed(le_or_be(&rd, off, 4usize), 4usize)
                if iv <= 2147483620i64 { v = f64(iv) }
            } else if t == 65529u32 {
                let iv = signed(le_or_be(&rd, off, 2usize), 2usize)
                if iv <= 32740i64 { v = f64(iv) }
            } else if t == 65530u32 {
                let iv = signed(le_or_be(&rd, off, 1usize), 1usize)
                if iv <= 100i64 { v = f64(iv) }
            }
            num[r * nvars + c] = v
            txt[r * nvars + c] = s
            off += w
            c += 1usize
        }
        r += 1usize
    }
    // value labels
    var nl = 0usize
    let vs = find_tag(data, "<value_labels>", 0usize)
    var p = vs + 14usize
    while p + 5usize <= data.len && data[p] == 60u8 && data[p + 1usize] == 108u8 {
        let ln = usize(le_or_be(&rd, p + 5usize, 4usize))
        nl += 1usize
        p += 5usize + 4usize + ln + 6usize
    }
    let (ln_names, lne) = mem.alloc[str](a, nl)
    let (lfirst, lfe) = mem.alloc[usize](a, nl)
    let (lcount, lce) = mem.alloc[usize](a, nl)
    if lne != ok { ret (none, lne) }
    if lfe != ok { ret (none, lfe) }
    if lce != ok { ret (none, lce) }
    // first pass for the entry total
    var total = 0usize
    p = vs + 14usize
    var k = 0usize
    while k < nl {
        let ln = usize(le_or_be(&rd, p + 5usize, 4usize))
        let body = p + 9usize
        total += usize(le_or_be(&rd, body + nw + 3usize, 4usize))
        p += 5usize + 4usize + ln + 6usize
        k += 1usize
    }
    let (codes, ce) = mem.alloc[i32](a, total)
    let (texts, tx) = mem.alloc[str](a, total)
    if ce != ok { ret (none, ce) }
    if tx != ok { ret (none, tx) }
    p = vs + 14usize
    k = 0usize
    var at2 = 0usize
    while k < nl {
        let ln = usize(le_or_be(&rd, p + 5usize, 4usize))
        let body = p + 9usize
        ln_names[k] = c_string(data, body, nw)
        let n = usize(le_or_be(&rd, body + nw + 3usize, 4usize))
        let txtlen = usize(le_or_be(&rd, body + nw + 7usize, 4usize))
        let offs = body + nw + 11usize
        let vals = offs + 4usize * n
        let tbase = vals + 4usize * n
        lfirst[k] = at2
        lcount[k] = n
        var j = 0usize
        while j < n {
            let o = usize(le_or_be(&rd, offs + 4usize * j, 4usize))
            codes[at2 + j] = i32(signed(le_or_be(&rd, vals + 4usize * j, 4usize), 4usize))
            texts[at2 + j] = c_string(data, tbase + o, txtlen - o)
            j += 1usize
        }
        at2 += n
        p += 5usize + 4usize + ln + 6usize
        k += 1usize
    }
    ret (Dta { version: version, nvars: nvars, nobs: nobs, label: label, names: names, varlabels: vlab, formats: fmts, types: types, vlnames: vln, num: num, text: txt, lbl_names: ln_names, lbl_first: lfirst, lbl_count: lcount, lbl_codes: codes, lbl_texts: texts }, ok)
}

