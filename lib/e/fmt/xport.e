// SAS XPORT (transport) reader for versions 5 and 8 (the layout ReadStat reads for haven): the table name,
// every variable (type, length, label, format, and for version 8 the long name, long label and format), and
// the observations. Numbers are IBM floats of 3 to 8 bytes converted to f64; a missing value is NaN with its
// tag in `tags` (0 for the plain `.`, else the lower-case letter, `_` for the underscore). A row of only
// spaces before the last real row is a row; trailing ones are padding.
//
// Not here: character sets other than ASCII and UTF-8, and writing.

use e.mem

error BadFile
error Unsupported

type Xpt = struct {
    version: i64,
    nvars: usize,
    nobs: usize,
    table: str,
    names: []str,
    labels: []str,
    formats: []str,
    is_text: []u8,
    kind: []u8,
    width: []usize,
    decimals: []i64,
    num: []f64,
    tags: []u8,
    text: []str,
    file_label: str,
    stamp: str,
    fname: []str,
    fwidth: []usize,
}

fn text_of(b: []const u8) -> str {
    var s: str = zero
    s = b
    ret s
}

fn trimmed(b: []const u8) -> str {
    var n = b.len
    while n > 0usize && (b[n - 1usize] == 32u8 || b[n - 1usize] == 0u8) { n -= 1usize }
    ret text_of(b[..n])
}

fn be16(d: []const u8, at: usize) -> usize { ret (usize(d[at]) << 8u32) | usize(d[at + 1usize]) }

fn be32(d: []const u8, at: usize) -> u64 {
    ret (u64(d[at]) << 24u64) | (u64(d[at + 1usize]) << 16u64) | (u64(d[at + 2usize]) << 8u64) | u64(d[at + 3usize])
}

fn digits(d: []const u8, at: usize, n: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < n {
        if d[at + i] < 48u8 || d[at + i] > 57u8 { ret v }
        v = v * 10usize + usize(d[at + i] - 48u8)
        i += 1usize
    }
    ret v
}

fn put_int(out: []u8, at: usize, v: usize) -> usize {
    var tmp: [24]u8 = zero
    var n = 0usize
    var x = v
    if x == 0usize {
        tmp[0usize] = 48u8
        n = 1usize
    }
    while x > 0usize {
        tmp[n] = u8(48usize + x % 10usize)
        x = x / 10usize
        n += 1usize
    }
    var i = 0usize
    while i < n {
        out[at + i] = tmp[n - 1usize - i]
        i += 1usize
    }
    ret n
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

// 0 plain, 1 date, 2 datetime, 3 time (haven's numType for SAS)
fn kind_of(f: str) -> u8 {
    if has_prefix(f, "DATETIME") || has_prefix(f, "IS8601DT") || has_prefix(f, "E8601DT") || has_prefix(f, "B8601DT") { ret 2u8 }
    if has_prefix(f, "IS8601DA") || has_prefix(f, "E8601DA") || has_prefix(f, "B8601DA") || has_prefix(f, "WEEKDATE") { ret 1u8 }
    if has_prefix(f, "MMDDYY") || has_prefix(f, "DDMMYY") || has_prefix(f, "YYMMDD") || has_prefix(f, "DATE") { ret 1u8 }
    if has_prefix(f, "TIME") || has_prefix(f, "HHMM") || has_prefix(f, "IS8601TM") || has_prefix(f, "E8601TM") || has_prefix(f, "B8601TM") { ret 3u8 }
    ret 0u8
}

// haven's adjustDatetimeToR for SAS: days and seconds from 1960
fn value(s: *const Xpt, row: usize, col: usize) -> f64 {
    let x = s.num[row * s.nvars + col]
    if x != x { ret x }
    let k = s.kind[col]
    if k == 2u8 { ret x - 3653.0f64 * 86400.0f64 }
    if k == 1u8 { ret x - 3653.0f64 }
    ret x
}

// IBM 64-bit float (3 to 8 bytes, zero padded) to the IEEE bits (ReadStat's xpt2ieee)
fn ibm_to_ieee(b: []const u8) -> u64 {
    var raw: [8]u8 = zero
    var i = 0usize
    while i < b.len && i < 8usize {
        raw[i] = b[i]
        i += 1usize
    }
    let x1 = be32(raw[..], 0usize)
    let x2 = be32(raw[..], 4usize)
    if (x1 & 2147483647u64) == 2147483647u64 && x2 == 4294967295u64 { ret ((x1 & 2147483648u64) | 2146435072u64) << 32u64 }
    if x1 == 0u64 && x2 == 0u64 { ret 0u64 }
    var ieee1 = x1 & 16777215u64
    var ieee2 = x2
    var shift = 0u64
    if (x1 & 8388608u64) != 0u64 {
        shift = 3u64
    } else if (x1 & 4194304u64) != 0u64 {
        shift = 2u64
    } else if (x1 & 2097152u64) != 0u64 {
        shift = 1u64
    }
    if shift != 0u64 {
        ieee1 = ieee1 >> shift
        ieee2 = ((x2 >> shift) | ((x1 & 7u64) << (29u64 + (3u64 - shift)))) & 4294967295u64
    }
    ieee1 = ieee1 & 4293918719u64
    let ex = i64(raw[0usize] & 127u8) - 65i64
    let e11 = (ex * 4i64 + i64(shift) + 1023i64) & 2047i64
    ieee1 = ieee1 | (u64(e11) << 20u64) | (x1 & 2147483648u64)
    ret (ieee1 << 32u64) | ieee2
}

fn header_name(d: []const u8, at: usize) -> str { ret trimmed(d[at + 20usize..at + 28usize]) }

fn read(a: *mem.Arena, data: []const u8) -> (Xpt, err) {
    var none: Xpt = zero
    if data.len < 80usize * 9usize { ret (none, BadFile) }
    let lib = header_name(data, 0usize)
    var version = 0i64
    if lib.len == 7usize && has_prefix(lib, "LIBRARY") { version = 5i64 }
    if lib.len == 5usize && has_prefix(lib, "LIBV8") { version = 8i64 }
    if version == 0i64 { ret (none, Unsupported) }
    if !has_prefix(text_of(data[0usize..20usize]), "HEADER RECORD*******") { ret (none, BadFile) }
    // records: 0 library, 1 skipped, 2 timestamp, 3 member, 4 descriptor, 5 table name, 6 file label, 7 namestr header
    let tn = 5usize * 80usize
    var tw = 8usize
    if version == 8i64 { tw = 32usize }
    let table = trimmed(data[tn + 8usize..tn + 8usize + tw])
    let stamp = text_of(data[160usize..176usize])
    let file_label = trimmed(data[6usize * 80usize + 32usize..6usize * 80usize + 72usize])
    let nh = 7usize * 80usize
    let nvars = digits(data, nh + 53usize, 5usize)
    if nvars == 0usize { ret (none, BadFile) }
    var at = 8usize * 80usize
    if at + nvars * 140usize > data.len { ret (none, BadFile) }
    let (names, e1) = mem.alloc[str](a, nvars)
    let (labels, e2) = mem.alloc[str](a, nvars)
    let (fmts, e3) = mem.alloc[str](a, nvars)
    let (is_text, e4) = mem.alloc[u8](a, nvars)
    let (kinds, e5) = mem.alloc[u8](a, nvars)
    let (widths, e6) = mem.alloc[usize](a, nvars)
    let (decs, e7) = mem.alloc[i64](a, nvars)
    let (fname, e8) = mem.alloc[str](a, nvars)
    let (fwidth, e9) = mem.alloc[usize](a, nvars)
    if e8 != ok { ret (none, e8) }
    if e9 != ok { ret (none, e9) }
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    if e5 != ok { ret (none, e5) }
    if e6 != ok { ret (none, e6) }
    if e7 != ok { ret (none, e7) }
    var i = 0usize
    while i < nvars {
        let p = at + i * 140usize
        is_text[i] = 0u8
        if be16(data, p) == 2usize { is_text[i] = 1u8 }
        widths[i] = be16(data, p + 4usize)
        let nfl = be16(data, p + 64usize)
        decs[i] = i64(be16(data, p + 66usize))
        if version == 5i64 {
            names[i] = trimmed(data[p + 8usize..p + 16usize])
        } else {
            names[i] = trimmed(data[p + 88usize..p + 120usize])
        }
        labels[i] = trimmed(data[p + 16usize..p + 56usize])
        let nm = trimmed(data[p + 56usize..p + 64usize])
        fname[i] = nm
        fwidth[i] = nfl
        let (txt, te) = mem.alloc[u8](a, nm.len + 24usize)
        if te != ok { ret (none, te) }
        var n = 0usize
        while n < nm.len {
            txt[n] = nm[n]
            n += 1usize
        }
        if nfl != 0usize { n += put_int(txt, n, nfl) }
        if decs[i] != 0i64 {
            txt[n] = 46u8
            n += 1usize
            n += put_int(txt, n, usize(decs[i]))
        }
        fmts[i] = text_of(txt[..n])
        i += 1usize
    }
    at += nvars * 140usize
    if at % 80usize != 0usize { at += 80usize - at % 80usize }
    // the next header: the observations, or the version 8 label definitions
    if at + 80usize > data.len { ret (none, BadFile) }
    var nm_hdr = header_name(data, at)
    if version == 8i64 && (has_prefix(nm_hdr, "LABELV8") || has_prefix(nm_hdr, "LABELV9")) {
        let nl = digits(data, at + 48usize, 5usize)
        let nine = has_prefix(nm_hdr, "LABELV9")
        at += 80usize
        var j = 0usize
        while j < nl {
            let idx = be16(data, at)
            let name_len = be16(data, at + 2usize)
            let label_len = be16(data, at + 4usize)
            var fl = 0usize
            var il = 0usize
            var hdr = 6usize
            if nine {
                fl = be16(data, at + 6usize)
                il = be16(data, at + 8usize)
                hdr = 10usize
            }
            if idx == 0usize || idx > nvars { ret (none, BadFile) }
            let k = idx - 1usize
            let ns = at + hdr
            names[k] = trimmed(data[ns..ns + name_len])
            labels[k] = trimmed(data[ns + name_len..ns + name_len + label_len])
            if nine { fmts[k] = trimmed(data[ns + name_len + label_len..ns + name_len + label_len + fl]) }
            at = ns + name_len + label_len + fl + il
            j += 1usize
        }
        if at % 80usize != 0usize { at += 80usize - at % 80usize }
        if at + 80usize > data.len { ret (none, BadFile) }
    }
    at += 80usize
    i = 0usize
    var row_len = 0usize
    while i < nvars {
        row_len += widths[i]
        i += 1usize
        }
    if row_len == 0usize { ret (none, BadFile) }
    // count the rows: complete rows, minus the trailing all-blank ones
    var nrows = (data.len - at) / row_len
    var last = nrows
    while last > 0usize {
        var blank = true
        var q = 0usize
        while q < row_len && blank {
            if data[at + (last - 1usize) * row_len + q] != 32u8 { blank = false }
            q += 1usize
        }
        if blank { last -= 1usize } else { break }
    }
    nrows = last
    i = 0usize
    while i < nvars {
        if is_text[i] == 0u8 { kinds[i] = kind_of(fmts[i]) } else { kinds[i] = 0u8 }
        i += 1usize
    }
    let (num, n1) = mem.alloc[f64](a, nrows * nvars + 1usize)
    let (tags, n2) = mem.alloc[u8](a, nrows * nvars + 1usize)
    let (txt, n3) = mem.alloc[str](a, nrows * nvars + 1usize)
    if n1 != ok { ret (none, n1) }
    if n2 != ok { ret (none, n2) }
    if n3 != ok { ret (none, n3) }
    var r = 0usize
    while r < nrows {
        var pos = at + r * row_len
        var c = 0usize
        while c < nvars {
            let w = widths[c]
            let cell = r * nvars + c
            tags[cell] = 0u8
            num[cell] = 0.0f64 / 0.0f64
            if is_text[c] != 0u8 {
                txt[cell] = trimmed(data[pos..pos + w])
            } else if w >= 3usize && w <= 8usize {
                var rest_zero = true
                var q = 1usize
                while q < w {
                    if data[pos + q] != 0u8 { rest_zero = false }
                    q += 1usize
                }
                let first = data[pos]
                if rest_zero && (first == 46u8 || first == 95u8 || (first >= 65u8 && first <= 90u8)) {
                    if first != 46u8 {
                        var t = first
                        if t >= 65u8 && t <= 90u8 { t = t + 32u8 }
                        tags[cell] = t
                    }
                } else {
                    num[cell] = mem.bitcast[f64](ibm_to_ieee(data[pos..pos + w]))
                }
            }
            pos += w
            c += 1usize
        }
        r += 1usize
    }
    ret (Xpt { version: version, nvars: nvars, nobs: nrows, table: table, names: names, labels: labels, formats: fmts, is_text: is_text, kind: kinds, width: widths, decimals: decs, num: num, tags: tags, text: txt, file_label: file_label, stamp: stamp, fname: fname, fwidth: fwidth }, ok)
}

// ---- writing ----

fn put_pad(b: []u8, p: usize, s: str, w: usize) -> usize {
    var i = 0usize
    while i < w {
        if i < s.len { b[p + i] = s[i] } else { b[p + i] = 32u8 }
        i += 1usize
    }
    ret p + w
}

fn put_zero(b: []u8, p: usize, n: usize) -> usize {
    var i = 0usize
    while i < n {
        b[p + i] = 0u8
        i += 1usize
    }
    ret p + n
}

fn put_be(b: []u8, p: usize, v: usize, n: usize) -> usize {
    var i = 0usize
    while i < n {
        b[p + i] = u8((v >> u64(8usize * (n - 1usize - i))) & 255usize)
        i += 1usize
    }
    ret p + n
}

// a decimal number, zero padded to n digits
fn put_dec(b: []u8, p: usize, v: usize, n: usize) -> usize {
    var x = v
    var i = n
    while i > 0usize {
        b[p + i - 1usize] = u8(48usize + x % 10usize)
        x = x / 10usize
        i -= 1usize
    }
    ret p + n
}

fn put_text(b: []u8, p: usize, s: str) -> usize {
    var i = 0usize
    while i < s.len {
        b[p + i] = s[i]
        i += 1usize
    }
    ret p + s.len
}

// "HEADER RECORD*******" + name (8) + "HEADER RECORD!!!!!!!" + six 5-digit numbers (or two 15-digit ones when wide)
fn put_header(b: []u8, p: usize, name: str, n1: usize, n2: usize, n3: usize, n4: usize, n5: usize, n6: usize, wide: bool) -> usize {
    var q = put_text(b, p, "HEADER RECORD*******")
    q = put_pad(b, q, name, 8usize)
    q = put_text(b, q, "HEADER RECORD!!!!!!!")
    if wide {
        q = put_dec(b, q, n1, 15usize)
        q = put_dec(b, q, n2, 15usize)
        // "%15d": the leading zeros are spaces
        var w = 0usize
        while w < 2usize {
            var z = 0usize
            while z < 14usize && b[q - 30usize + 15usize * w + z] == 48u8 {
                b[q - 30usize + 15usize * w + z] = 32u8
                z += 1usize
            }
            w += 1usize
        }
        ret q
    }
    q = put_dec(b, q, n1, 5usize)
    q = put_dec(b, q, n2, 5usize)
    q = put_dec(b, q, n3, 5usize)
    q = put_dec(b, q, n4, 5usize)
    q = put_dec(b, q, n5, 5usize)
    q = put_dec(b, q, n6, 5usize)
    ret q
}

// pads the current record out to 80 bytes with spaces
fn put_end(b: []u8, p: usize) -> usize {
    var q = p
    while q % 80usize != 0usize {
        b[q] = 32u8
        q += 1usize
    }
    ret q
}

// IEEE bits to the IBM float, `w` bytes of it (ReadStat's ieee2xpt)
fn put_ibm(b: []u8, p: usize, bits: u64, w: usize) -> usize {
    var raw: [8]u8 = zero
    let exp = i64((bits >> 52u64) & 2047u64)
    let frac = bits & 4503599627370495u64
    if exp != 0i64 || frac != 0u64 {
        let m = frac | 4503599627370496u64
        let e2 = exp - 1022i64
        var k = (e2 + 3i64) / 4i64
        if e2 + 3i64 < 0i64 { k = 0i64 - (0i64 - e2) / 4i64 }
        let s = u64(4i64 * k - e2)
        let f56 = m << (3u64 - s)
        raw[0usize] = u8(((bits >> 63u64) << 7u64) | u64((k + 64i64) & 127i64))
        var i = 1usize
        while i < 8usize {
            raw[i] = u8((f56 >> u64(8usize * (7usize - i))) & 255u64)
            i += 1usize
        }
    }
    var j = 0usize
    while j < w {
        b[p + j] = raw[j]
        j += 1usize
    }
    ret p + w
}

// the transport file for `x`, the version and timestamps it was read with
fn write(a: *mem.Arena, x: *const Xpt) -> ([]u8, err) {
    var none: []u8 = zero
    let v8 = x.version == 8i64
    var rowlen = 0usize
    var extra = 0usize
    var i = 0usize
    while i < x.nvars {
        rowlen += x.width[i]
        extra += x.names[i].len + x.labels[i].len + x.formats[i].len * 2usize + 16usize
        i += 1usize
    }
    let cap = 1600usize + x.nvars * 140usize + extra + 80usize + rowlen * x.nobs + 160usize
    let (b, be) = mem.alloc[u8](a, cap)
    if be != ok { ret (none, be) }
    var p = 0usize
    if v8 { p = put_header(b, p, "LIBV8", 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, false) } else { p = put_header(b, p, "LIBRARY", 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, false) }
    p = put_end(b, p)
    p = put_pad(b, p, "SAS", 8usize)
    p = put_pad(b, p, "SAS", 8usize)
    p = put_pad(b, p, "SASLIB", 8usize)
    p = put_pad(b, p, "6.06", 8usize)
    p = put_pad(b, p, "bsd4.2", 8usize)
    p = put_pad(b, p, "", 24usize)
    p = put_text(b, p, x.stamp)
    p = put_end(b, p)
    p = put_text(b, p, x.stamp)
    p = put_end(b, p)
    if v8 { p = put_header(b, p, "MEMBV8", 0usize, 0usize, 0usize, 160usize, 0usize, 140usize, false) } else { p = put_header(b, p, "MEMBER", 0usize, 0usize, 0usize, 160usize, 0usize, 140usize, false) }
    p = put_end(b, p)
    if v8 { p = put_header(b, p, "DSCPTV8", 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, false) } else { p = put_header(b, p, "DSCRPTR", 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, false) }
    p = put_end(b, p)
    p = put_pad(b, p, "SAS", 8usize)
    if v8 { p = put_pad(b, p, x.table, 32usize) } else { p = put_pad(b, p, x.table, 8usize) }
    p = put_pad(b, p, "SASDATA", 8usize)
    p = put_pad(b, p, "6.06", 8usize)
    p = put_pad(b, p, "bsd4.2", 8usize)
    if !v8 { p = put_pad(b, p, "", 24usize) }
    p = put_text(b, p, x.stamp)
    p = put_end(b, p)
    p = put_text(b, p, x.stamp)
    p = put_pad(b, p, "", 16usize)
    p = put_pad(b, p, x.file_label, 40usize)
    p = put_pad(b, p, "", 8usize)
    p = put_end(b, p)
    if v8 { p = put_header(b, p, "NAMSTV8", 0usize, x.nvars, 0usize, 0usize, 0usize, 0usize, false) } else { p = put_header(b, p, "NAMESTR", 0usize, x.nvars, 0usize, 0usize, 0usize, 0usize, false) }
    p = put_end(b, p)
    var offset = 0usize
    var nlong = 0usize
    var any_long_format = false
    i = 0usize
    while i < x.nvars {
        var ntype = 1usize
        if x.is_text[i] != 0u8 { ntype = 2usize }
        p = put_be(b, p, ntype, 2usize)
        p = put_be(b, p, 0usize, 2usize)
        p = put_be(b, p, x.width[i], 2usize)
        p = put_be(b, p, i + 1usize, 2usize)
        p = put_pad(b, p, x.names[i], 8usize)
        p = put_pad(b, p, x.labels[i], 40usize)
        p = put_pad(b, p, x.fname[i], 8usize)
        p = put_be(b, p, x.fwidth[i], 2usize)
        p = put_be(b, p, usize(x.decimals[i]), 2usize)
        p = put_be(b, p, 2usize - ntype, 2usize)
        p = put_be(b, p, 0usize, 2usize)
        p = put_pad(b, p, x.fname[i], 8usize)
        p = put_be(b, p, x.fwidth[i], 2usize)
        p = put_be(b, p, usize(x.decimals[i]), 2usize)
        p = put_be(b, p, offset, 4usize)
        if v8 {
            p = put_pad(b, p, x.names[i], 32usize)
            p = put_be(b, p, x.labels[i].len, 2usize)
            p = put_zero(b, p, 18usize)
        } else {
            p = put_zero(b, p, 52usize)
        }
        var long_one = false
        if x.formats[i].len > 8usize && x.fname[i].len > 8usize { long_one = true }
        if long_one { any_long_format = true }
        if v8 && (x.labels[i].len > 40usize || long_one) { nlong += 1usize }
        offset += x.width[i]
        i += 1usize
    }
    p = put_end(b, p)
    if v8 && nlong > 0usize {
        var nm = "LABELV8"
        if any_long_format { nm = "LABELV9" }
        p = put_header(b, p, nm, nlong, 0usize, 0usize, 0usize, 0usize, 0usize, true)
        p = put_end(b, p)
        i = 0usize
        while i < x.nvars {
            if x.labels[i].len > 40usize {
                p = put_be(b, p, i + 1usize, 2usize)
                p = put_be(b, p, x.names[i].len, 2usize)
                p = put_be(b, p, x.labels[i].len, 2usize)
                p = put_text(b, p, x.names[i])
                p = put_text(b, p, x.labels[i])
            }
            i += 1usize
        }
        p = put_end(b, p)
    }
    if v8 { p = put_header(b, p, "OBSV8", x.nobs, 0usize, 0usize, 0usize, 0usize, 0usize, true) } else { p = put_header(b, p, "OBS", 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, false) }
    p = put_end(b, p)
    var r = 0usize
    while r < x.nobs {
        i = 0usize
        while i < x.nvars {
            let at = r * x.nvars + i
            if x.is_text[i] != 0u8 {
                p = put_pad(b, p, x.text[at], x.width[i])
            } else if x.num[at] == x.num[at] {
                p = put_ibm(b, p, mem.bitcast[u64](x.num[at]), x.width[i])
            } else {
                p = put_zero(b, p, x.width[i])
                var first = 46u8
                if x.tags[at] == 95u8 { first = 95u8 }
                if x.tags[at] >= 97u8 && x.tags[at] <= 122u8 { first = x.tags[at] - 32u8 }
                b[p - x.width[i]] = first
            }
            i += 1usize
        }
        r += 1usize
    }
    p = put_end(b, p)
    ret (b[..p], ok)
}
