// SAS7BDAT reader (the layout ReadStat reads for haven): 32 and 64 bit files in either byte order, column
// names, labels and formats from the column subheaders, rows on data and mixed pages, and rows packed in
// subheaders by SAS's RLE ("SASYZCRL") and RDC ("SASYZCR2") compression. A missing number is NaN with its
// tag in `tags` (0 for `.`, else the lower-case letter or `_`). Strings are UTF-8 text (code pages 1252 and
// Latin-1 are converted).
//
// `read_catalog` reads a sas7bcat catalog (value labels, text and numeric codes, tagged missing codes).
//
// Not here: code pages other than UTF-8, ASCII, Latin-1 and 1252, writing. The RLE reader runs on files written by
// ReadStat (tests/data/haven/rle64 and rle32); the RDC reader and the big-endian paths follow ReadStat line for line
// but no file reaches them.

use e.mem

error BadFile
error Unsupported

type Sas = struct {
    nvars: usize,
    nobs: usize,
    table: str,
    names: []str,
    labels: []str,
    formats: []str,
    is_text: []u8,
    kind: []u8,
    num: []f64,
    tags: []u8,
    text: []str,
    compression: i64,
    u64: bool,
    big: bool,
}

type Ctx = struct {
    a: *mem.Arena,
    d: []const u8,
    big: bool,
    wide: bool,
    enc: u8,
    vendor_st: bool,
    page_size: usize,
    page_count: usize,
    header_size: usize,
    phs: usize,
    lshp: usize,
    sigl: usize,
    blob_at: []usize,
    blob_len: []usize,
    nblobs: usize,
    row_length: usize,
    total_rows: usize,
    page_rows: usize,
    parsed: usize,
    ncols: usize,
    cap: usize,
    n_names: usize,
    n_attrs: usize,
    n_fmts: usize,
    c_name: []usize,
    c_fmt: []usize,
    c_lab: []usize,
    c_off: []usize,
    c_width: []usize,
    c_type: []u8,
    c_fw: []usize,
    c_fd: []usize,
    rdc: bool,
    compressed: bool,
    row: []u8,
    ready: bool,
    out_num: []f64,
    out_tag: []u8,
    out_text: []str,
    out_names: []str,
    out_labels: []str,
    out_formats: []str,
    out_kind: []u8,
    out_text_flag: []u8,
    max_width: usize,
    table: str,
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

fn rd16(c: *const Ctx, at: usize) -> usize {
    if c.big { ret (usize(c.d[at]) << 8u32) | usize(c.d[at + 1usize]) }
    ret usize(c.d[at]) | (usize(c.d[at + 1usize]) << 8u32)
}

fn rd32(c: *const Ctx, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 4usize {
        var idx = i
        if c.big { idx = 3usize - i }
        v = v | (u64(c.d[at + idx]) << u64(8usize * i))
        i += 1usize
    }
    ret v
}

fn rd64(c: *const Ctx, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        var idx = i
        if c.big { idx = 7usize - i }
        v = v | (u64(c.d[at + idx]) << u64(8usize * i))
        i += 1usize
    }
    ret v
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

fn kind_of(f: str) -> u8 {
    if has_prefix(f, "DATETIME") || has_prefix(f, "IS8601DT") || has_prefix(f, "E8601DT") || has_prefix(f, "B8601DT") { ret 2u8 }
    if has_prefix(f, "IS8601DA") || has_prefix(f, "E8601DA") || has_prefix(f, "B8601DA") || has_prefix(f, "WEEKDATE") { ret 1u8 }
    if has_prefix(f, "MMDDYY") || has_prefix(f, "DDMMYY") || has_prefix(f, "YYMMDD") || has_prefix(f, "DATE") { ret 1u8 }
    if has_prefix(f, "TIME") || has_prefix(f, "HHMM") || has_prefix(f, "IS8601TM") || has_prefix(f, "E8601TM") || has_prefix(f, "B8601TM") { ret 3u8 }
    ret 0u8
}

// haven's adjustDatetimeToR for SAS: days and seconds from 1960
fn value(s: *const Sas, row: usize, col: usize) -> f64 {
    let x = s.num[row * s.nvars + col]
    if x != x { ret x }
    let k = s.kind[col]
    if k == 2u8 { ret x - 3653.0f64 * 86400.0f64 }
    if k == 1u8 { ret x - 3653.0f64 }
    ret x
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

// the text of a field in the file's code page, as UTF-8 (trailing spaces and NULs dropped)
fn utf8_text(c: *Ctx, b: []const u8) -> (str, err) {
    var blank: str = zero
    let t = trimmed(b)
    if c.enc == 20u8 || c.enc == 28u8 { ret (t, ok) }
    var high = false
    var i = 0usize
    while i < t.len {
        if t[i] >= 128u8 { high = true }
        i += 1usize
    }
    if !high { ret (t, ok) }
    let latin = c.enc == 29u8
    if !(latin || c.enc == 0u8 || c.enc == 62u8 || c.enc == 204u8) { ret (blank, Unsupported) }
    let (out, oe) = mem.alloc[u8](c.a, t.len * 3usize + 1usize)
    if oe != ok { ret (blank, oe) }
    var n = 0usize
    i = 0usize
    while i < t.len {
        var cp = u32(t[i])
        if !latin { cp = cp1252_point(t[i]) }
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
    ret (text_of(out[..n]), ok)
}

// text of a column text reference (index, offset, length as three 16-bit numbers)
fn ref_text(c: *Ctx, r: usize, refs: []const usize) -> (str, err) {
    var blank: str = zero
    let index = refs[r * 3usize]
    let off = refs[r * 3usize + 1usize]
    let len = refs[r * 3usize + 2usize]
    if len == 0usize { ret (blank, ok) }
    if index >= c.nblobs { ret (blank, BadFile) }
    if off + len > c.blob_len[index] { ret (blank, BadFile) }
    let at = c.blob_at[index] + off
    let (t, te) = utf8_text(c, c.d[at..at + len])
    ret (t, te)
}

fn set_ref(c: *Ctx, refs: []usize, r: usize, at: usize) {
    refs[r * 3usize] = rd16(c, at)
    refs[r * 3usize + 1usize] = rd16(c, at + 2usize)
    refs[r * 3usize + 2usize] = rd16(c, at + 4usize)
}

fn rle_unpack(src: []const u8, out: []u8) -> i64 {
    var o = 0usize
    var p = 0usize
    while p < src.len {
        let control = src[p]
        p += 1usize
        let command = usize(control >> 4u8)
        let length = usize(control & 15u8)
        var copy_len = 0usize
        var insert_len = 0usize
        var insert_byte = 0u8
        var need = 0usize
        if command == 0usize || command == 1usize || command == 4usize || command == 5usize || command == 6usize || command == 7usize || command == 12usize { need = 1usize }
        if command == 4usize { need = 2usize }
        if p + need > src.len { ret -1i64 }
        if command == 0usize {
            copy_len = usize(src[p]) + 64usize + length * 256usize
            p += 1usize
        } else if command == 1usize {
            copy_len = usize(src[p]) + 64usize + length * 256usize + 4096usize
            p += 1usize
        } else if command == 2usize {
            copy_len = length + 96usize
        } else if command == 4usize {
            insert_len = usize(src[p]) + 18usize + length * 256usize
            insert_byte = src[p + 1usize]
            p += 2usize
        } else if command == 5usize {
            insert_len = usize(src[p]) + 17usize + length * 256usize
            insert_byte = 64u8
            p += 1usize
        } else if command == 6usize {
            insert_len = usize(src[p]) + 17usize + length * 256usize
            insert_byte = 32u8
            p += 1usize
        } else if command == 7usize {
            insert_len = usize(src[p]) + 17usize + length * 256usize
            insert_byte = 0u8
            p += 1usize
        } else if command == 8usize {
            copy_len = length + 1usize
        } else if command == 9usize {
            copy_len = length + 17usize
        } else if command == 10usize {
            copy_len = length + 33usize
        } else if command == 11usize {
            copy_len = length + 49usize
        } else if command == 12usize {
            insert_byte = src[p]
            insert_len = length + 3usize
            p += 1usize
        } else if command == 13usize {
            insert_byte = 64u8
            insert_len = length + 2usize
        } else if command == 14usize {
            insert_byte = 32u8
            insert_len = length + 2usize
        } else if command == 15usize {
            insert_byte = 0u8
            insert_len = length + 2usize
        }
        if copy_len > 0usize {
            if o + copy_len > out.len { ret -1i64 }
            if p + copy_len > src.len { ret -1i64 }
            var k = 0usize
            while k < copy_len {
                out[o + k] = src[p + k]
                k += 1usize
            }
            p += copy_len
            o += copy_len
        }
        if insert_len > 0usize {
            if o + insert_len > out.len { ret -1i64 }
            var k = 0usize
            while k < insert_len {
                out[o + k] = insert_byte
                k += 1usize
            }
            o += insert_len
        }
    }
    ret i64(o)
}

fn rdc_unpack(src: []const u8, out: []u8) -> i64 {
    var o = 0usize
    var p = 0usize
    while p + 2usize <= src.len {
        let prefix = (usize(src[p]) << 8u32) + usize(src[p + 1usize])
        p += 2usize
        var i = 0usize
        while i < 16usize {
            if (prefix & (1usize << usize(15usize - i))) == 0usize {
                if p + 1usize > src.len { break }
                if o + 1usize > out.len { ret -1i64 }
                out[o] = src[p]
                o += 1usize
                p += 1usize
                i += 1usize
                continue
            }
            if p + 2usize > src.len { ret -1i64 }
            let marker = usize(src[p])
            let next = usize(src[p + 1usize])
            p += 2usize
            var insert_len = 0usize
            var copy_len = 0usize
            var insert_byte = 0u8
            var back = 0usize
            if marker <= 15usize {
                insert_len = 3usize + marker
                insert_byte = u8(next)
            } else if (marker >> 4u32) == 1usize {
                if p + 1usize > src.len { ret -1i64 }
                insert_len = 19usize + (marker & 15usize) + next * 16usize
                insert_byte = src[p]
                p += 1usize
            } else if (marker >> 4u32) == 2usize {
                if p + 1usize > src.len { ret -1i64 }
                copy_len = 16usize + usize(src[p])
                p += 1usize
                back = 3usize + (marker & 15usize) + next * 16usize
            } else {
                copy_len = marker >> 4u32
                back = 3usize + (marker & 15usize) + next * 16usize
            }
            if insert_len > 0usize {
                if o + insert_len > out.len { ret -1i64 }
                var k = 0usize
                while k < insert_len {
                    out[o + k] = insert_byte
                    k += 1usize
                }
                o += insert_len
            } else if copy_len > 0usize {
                if o < back || copy_len > back { ret -1i64 }
                if o + copy_len > out.len { ret -1i64 }
                var k = 0usize
                while k < copy_len {
                    out[o + k] = out[o - back + k]
                    k += 1usize
                }
                o += copy_len
            }
            i += 1usize
        }
    }
    ret i64(o)
}

fn text_subheader(c: *Ctx, at: usize, len: usize) -> err {
    if c.nblobs >= c.blob_at.len { ret BadFile }
    c.blob_at[c.nblobs] = at + c.sigl
    c.blob_len[c.nblobs] = len - c.sigl
    c.nblobs += 1usize
    ret ok
}

// the page's subheader pointers: (offset, length, compression, is_compressed_data) of pointer i
fn pointer_at(c: *Ctx, page: usize, i: usize) -> (usize, usize, u8, u8) {
    let at = page + c.phs + i * c.lshp
    if c.wide { ret (usize(rd64(c, at)), usize(rd64(c, at + 8usize)), c.d[at + 16usize], c.d[at + 17usize]) }
    ret (usize(rd32(c, at)), usize(rd32(c, at + 4usize)), c.d[at + 8usize], c.d[at + 9usize])
}

fn signature_at(c: *Ctx, at: usize) -> u64 {
    var s = rd32(c, at)
    if !c.big { ret s }
    if s == 4294967295u64 && c.wide { s = rd32(c, at + 4usize) }
    ret s
}

fn page_pass1(c: *Ctx, page: usize) -> err {
    let count = rd16(c, page + c.phs - 4usize)
    if c.phs + count * c.lshp > c.page_size { ret BadFile }
    var i = 0usize
    while i < count {
        let (off, len, comp, packed) = pointer_at(c, page, i)
        if len > 0usize && comp != 1u8 {
            if off > c.page_size || len > c.page_size || off + len > c.page_size { ret BadFile }
            if off < c.phs + count * c.lshp { ret BadFile }
            if comp == 0u8 {
                if len < c.sigl { ret BadFile }
                let sig = signature_at(c, page + off)
                if sig == 4294967293u64 {
                    let e = text_subheader(c, page + off, len)
                    if e != ok { ret e }
                }
            } else if comp != 4u8 {
                ret Unsupported
            }
        }
        i += 1usize
    }
    ret ok
}

fn prepare(c: *Ctx) -> err {
    if c.ready { ret ok }
    c.ready = true
    let n = c.ncols
    if n == 0usize { ret ok }
    let (o1, e1) = mem.alloc[f64](c.a, c.total_rows * n + 1usize)
    let (o2, e2) = mem.alloc[u8](c.a, c.total_rows * n + 1usize)
    let (o3, e3) = mem.alloc[str](c.a, c.total_rows * n + 1usize)
    let (o4, e4) = mem.alloc[str](c.a, n)
    let (o5, e5) = mem.alloc[str](c.a, n)
    let (o6, e6) = mem.alloc[str](c.a, n)
    let (o7, e7) = mem.alloc[u8](c.a, n)
    let (o8, e8) = mem.alloc[u8](c.a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    c.out_num = o1
    c.out_tag = o2
    c.out_text = o3
    c.out_names = o4
    c.out_labels = o5
    c.out_formats = o6
    c.out_kind = o7
    c.out_text_flag = o8
    var i = 0usize
    while i < n {
        let (nm, ne) = ref_text(c, i, c.c_name)
        if ne != ok { ret ne }
        let (fm, fe) = ref_text(c, i, c.c_fmt)
        if fe != ok { ret fe }
        let (lb, le) = ref_text(c, i, c.c_lab)
        if le != ok { ret le }
        var w = c.c_width[i]
        if c.c_type[i] == 1u8 {
            if w > 8usize || w < 3usize { ret BadFile }
        } else if c.c_type[i] == 2u8 {
            if w > 32767usize || w == 0usize { ret BadFile }
        } else {
            ret BadFile
        }
        var ft = fm
        if fm.len > 0usize && (c.c_fw[i] != 0usize || c.c_fd[i] != 0usize) {
            let (buf, be) = mem.alloc[u8](c.a, fm.len + 24usize)
            if be != ok { ret be }
            var k = 0usize
            while k < fm.len {
                buf[k] = fm[k]
                k += 1usize
            }
            var m = k
            if c.c_fw[i] != 0usize { m += put_int(buf, m, c.c_fw[i]) }
            if c.c_fd[i] != 0usize {
                buf[m] = 46u8
                m += 1usize
                m += put_int(buf, m, c.c_fd[i])
            }
            ft = text_of(buf[..m])
        }
        c.out_names[i] = nm
        c.out_formats[i] = ft
        c.out_labels[i] = lb
        c.out_text_flag[i] = 0u8
        if c.c_type[i] == 2u8 { c.out_text_flag[i] = 1u8 }
        c.out_kind[i] = 0u8
        if c.c_type[i] == 1u8 { c.out_kind[i] = kind_of(ft) }
        i += 1usize
    }
    ret ok
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

// one decoded row (row_length bytes at `at` in `buf`)
fn single_row(c: *Ctx, buf: []const u8) -> err {
    if c.parsed == c.total_rows { ret ok }
    var j = 0usize
    while j < c.ncols {
        let off = c.c_off[j]
        let w = c.c_width[j]
        if off > c.row_length || off + w > c.row_length { ret BadFile }
        let cell = c.parsed * c.ncols + j
        c.out_tag[cell] = 0u8
        if c.c_type[j] == 2u8 {
            let (t, te) = utf8_text(c, buf[off..off + w])
            if te != ok { ret te }
            // a compressed row is unpacked into one reused buffer, so the text is copied out of it
            let (own, oe) = mem.alloc[u8](c.a, t.len + 1usize)
            if oe != ok { ret oe }
            var q = 0usize
            while q < t.len {
                own[q] = t[q]
                q += 1usize
            }
            c.out_text[cell] = text_of(own[..t.len])
            c.out_num[cell] = 0.0f64 / 0.0f64
        } else {
            var val = 0u64
            var k = 0usize
            while k < w {
                var bt = u64(buf[off + k])
                if !c.big { bt = u64(buf[off + w - 1usize - k]) }
                val = (val << 8u64) | bt
                k += 1usize
            }
            val = val << u64((8usize - w) * 8usize)
            let x = mem.bitcast[f64](val)
            c.out_num[cell] = x
            if x != x {
                var t = u8((~(val >> 40u64)) & 255u64)
                if t == 0u8 { t = 95u8 } else if t >= 2u8 && t < 28u8 { t = 65u8 + (t - 2u8) }
                if t == 95u8 || (t >= 65u8 && t <= 90u8) {
                    if t >= 65u8 { t = t + 32u8 }
                    c.out_tag[cell] = t
                }
            }
        }
        j += 1usize
    }
    c.parsed += 1usize
    ret ok
}

fn parse_rows(c: *Ctx, at: usize, end: usize) -> err {
    var off = 0usize
    var i = 0usize
    while i < c.page_rows && c.parsed < c.total_rows {
        if off + c.row_length > end - at { ret BadFile }
        let e = single_row(c, c.d[at + off..at + off + c.row_length])
        if e != ok { ret e }
        off += c.row_length
        i += 1usize
    }
    ret ok
}

fn subheader(c: *Ctx, sig: u64, at: usize, len: usize) -> err {
    if len < 2usize + c.sigl { ret BadFile }
    if sig == 4160223223u64 {
        // row size
        var minimum = 190usize
        if c.wide { minimum = 250usize }
        if len < minimum { ret BadFile }
        var row_len = 0usize
        var total = 0usize
        var prow = 0usize
        if c.wide {
            row_len = usize(rd64(c, at + 40usize))
            total = usize(rd64(c, at + 48usize))
            prow = usize(rd64(c, at + 120usize))
        } else {
            row_len = usize(rd32(c, at + 20usize))
            total = usize(rd32(c, at + 24usize))
            prow = usize(rd32(c, at + 60usize))
        }
        let (refs, re) = mem.alloc[usize](c.a, 6usize)
        if re != ok { ret re }
        set_ref(c, refs, 0usize, at + len - 130usize)
        set_ref(c, refs, 1usize, at + len - 118usize)
        if refs[2usize] != 0usize {
            let (ct, ce) = ref_text(c, 1usize, refs)
            if ce != ok { ret ce }
            if ct.len == 8usize && has_prefix(ct, "SASYZCR2") { c.rdc = true }
        }
        c.row_length = row_len
        let (rb, rbe) = mem.alloc[u8](c.a, row_len + 8usize)
        if rbe != ok { ret rbe }
        c.row = rb[..row_len]
        c.page_rows = prow
        c.total_rows = total
        ret ok
    } else if sig == 4143380214u64 {
        // column size
        var minimum = 8usize
        if c.wide { minimum = 16usize }
        if len < minimum { ret BadFile }
        if c.ncols != 0usize { ret BadFile }
        if c.wide { c.ncols = usize(rd64(c, at + 8usize)) } else { c.ncols = usize(rd32(c, at + 4usize)) }
        c.cap = c.ncols + 64usize
        let (a1, e1) = mem.alloc[usize](c.a, c.cap * 3usize)
        let (a2, e2) = mem.alloc[usize](c.a, c.cap * 3usize)
        let (a3, e3) = mem.alloc[usize](c.a, c.cap * 3usize)
        let (a4, e4) = mem.alloc[usize](c.a, c.cap)
        let (a5, e5) = mem.alloc[usize](c.a, c.cap)
        let (a6, e6) = mem.alloc[u8](c.a, c.cap)
        let (a7, e7) = mem.alloc[usize](c.a, c.cap)
        let (a8, e8) = mem.alloc[usize](c.a, c.cap)
        if e1 != ok { ret e1 }
        if e2 != ok { ret e2 }
        if e3 != ok { ret e3 }
        if e4 != ok { ret e4 }
        if e5 != ok { ret e5 }
        if e6 != ok { ret e6 }
        if e7 != ok { ret e7 }
        if e8 != ok { ret e8 }
        c.c_name = a1
        c.c_fmt = a2
        c.c_lab = a3
        c.c_off = a4
        c.c_width = a5
        c.c_type = a6
        c.c_fw = a7
        c.c_fd = a8
        var i = 0usize
        while i < c.cap {
            c.c_name[i * 3usize] = 0usize
            c.c_name[i * 3usize + 1usize] = 0usize
            c.c_name[i * 3usize + 2usize] = 0usize
            c.c_fmt[i * 3usize] = 0usize
            c.c_fmt[i * 3usize + 1usize] = 0usize
            c.c_fmt[i * 3usize + 2usize] = 0usize
            c.c_lab[i * 3usize] = 0usize
            c.c_lab[i * 3usize + 1usize] = 0usize
            c.c_lab[i * 3usize + 2usize] = 0usize
            c.c_off[i] = 0usize
            c.c_width[i] = 0usize
            c.c_type[i] = 0u8
            c.c_fw[i] = 0usize
            c.c_fd[i] = 0usize
            i += 1usize
        }
        ret ok
    } else if sig == 4294966272u64 {
        ret ok
    } else if sig == 4294967295u64 {
        // column names
        var cmax = (len - 20usize) / 8usize
        if c.wide { cmax = (len - 28usize) / 8usize }
        c.n_names += cmax
        if c.n_names > c.cap { ret BadFile }
        var p = at + c.sigl + 8usize
        var i = c.n_names - cmax
        while i < c.n_names {
            set_ref(c, c.c_name, i, p)
            p += 8usize
            i += 1usize
        }
        ret ok
    } else if sig == 4294967292u64 {
        // column attributes
        var cmax = (len - 20usize) / 12usize
        if c.wide { cmax = (len - 28usize) / 16usize }
        c.n_attrs += cmax
        if c.n_attrs > c.cap { ret BadFile }
        var p = at + c.sigl + 8usize
        var i = c.n_attrs - cmax
        while i < c.n_attrs {
            var off = 4usize
            if c.wide { off = 8usize }
            if c.wide { c.c_off[i] = usize(rd64(c, p)) } else { c.c_off[i] = usize(rd32(c, p)) }
            c.c_width[i] = usize(rd32(c, p + off))
            if c.c_width[i] > c.max_width { c.max_width = c.c_width[i] }
            let ty = c.d[p + off + 6usize]
            if ty != 1u8 && ty != 2u8 { ret BadFile }
            c.c_type[i] = ty
            p += off + 8usize
            i += 1usize
        }
        ret ok
    } else if sig == 4294966270u64 {
        // column format
        var minimum = 46usize
        if c.wide { minimum = 58usize }
        if len < minimum { ret BadFile }
        c.n_fmts += 1usize
        if c.n_fmts > c.cap { ret BadFile }
        let k = c.n_fmts - 1usize
        if c.wide {
            c.c_fw[k] = rd16(c, at + 24usize)
            c.c_fd[k] = rd16(c, at + 26usize)
            set_ref(c, c.c_fmt, k, at + 46usize)
            set_ref(c, c.c_lab, k, at + 52usize)
        } else {
            set_ref(c, c.c_fmt, k, at + 34usize)
            set_ref(c, c.c_lab, k, at + 40usize)
        }
        ret ok
    } else if sig == 4294967294u64 {
        ret ok
    } else if (sig & 4294967288u64) == 4294967288u64 {
        ret ok
    }
    ret BadFile
}

fn recognized(sig: u64) -> bool {
    if sig == 4160223223u64 || sig == 4143380214u64 || sig == 4294966272u64 || sig == 4294966270u64 { ret true }
    ret (sig & 4294967288u64) == 4294967288u64
}

fn compressed_row(c: *Ctx, at: usize, len: usize) -> err {
    if c.parsed == c.total_rows { ret ok }
    if c.rdc {
        var out = c.row
        let n = rdc_unpack(c.d[at..at + len], out)
        if n != i64(c.row_length) { ret BadFile }
        ret single_row(c, c.row)
    }
    let n = rle_unpack(c.d[at..at + len], c.row)
    if n != i64(c.row_length) { ret BadFile }
    ret single_row(c, c.row)
}

fn page_pass2(c: *Ctx, page: usize) -> err {
    let ptype = rd16(c, page + c.phs - 8usize)
    var data = 0usize
    var have_data = false
    if (ptype & 3840usize) == 256usize {
        c.page_rows = rd16(c, page + c.phs - 6usize)
        data = page + c.phs
        have_data = true
    } else if (ptype & 36864usize) == 0usize {
        let count = rd16(c, page + c.phs - 4usize)
        if c.phs + count * c.lshp > c.page_size { ret BadFile }
        var i = 0usize
        while i < count {
            let (off, len, comp, packed) = pointer_at(c, page, i)
            if len > 0usize && comp != 1u8 {
                if off > c.page_size || len > c.page_size || off + len > c.page_size { ret BadFile }
                if off < c.phs + count * c.lshp { ret BadFile }
                if comp == 0u8 {
                    if len < c.sigl { ret BadFile }
                    let sig = signature_at(c, page + off)
                    if packed != 0u8 && !recognized(sig) {
                        if len != c.row_length { ret BadFile }
                        let pe = prepare(c)
                        if pe != ok { ret pe }
                        let re = single_row(c, c.d[page + off..page + off + len])
                        if re != ok { ret re }
                    } else if sig != 4294967293u64 {
                        let se = subheader(c, sig, page + off, len)
                        if se != ok { ret se }
                    }
                } else if comp == 4u8 {
                    let pe = prepare(c)
                    if pe != ok { ret pe }
                    c.compressed = true
                    let re = compressed_row(c, page + off, len)
                    if re != ok { ret re }
                } else {
                    ret Unsupported
                }
            }
            i += 1usize
        }
        if (ptype & 3840usize) == 512usize {
            let shp = page + c.phs + count * c.lshp
            data = shp
            have_data = true
            if (shp - page) % 8usize == 4usize && shp + 4usize <= page + c.page_size {
                let w = rd32(c, shp)
                if w == 0u64 || w == 538976288u64 || !c.vendor_st { data = shp + 4usize }
            }
        }
    }
    if have_data {
        let pe = prepare(c)
        if pe != ok { ret pe }
        ret parse_rows(c, data, page + c.page_size)
    }
    ret ok
}

fn read(a: *mem.Arena, data: []const u8) -> (Sas, err) {
    var none: Sas = zero
    if data.len < 1024usize { ret (none, BadFile) }
    let magic_a = data[12usize] == 194u8 && data[13usize] == 234u8 && data[14usize] == 129u8 && data[15usize] == 96u8
    let magic_b = data[16usize] == 179u8 && data[17usize] == 20u8 && data[18usize] == 17u8 && data[19usize] == 207u8
    if !(magic_a && magic_b) { ret (none, BadFile) }
    var c: Ctx = zero
    c.a = a
    c.d = data
    c.wide = data[32usize] == 51u8
    var pad = 0usize
    if data[35usize] == 51u8 { pad = 4usize }
    if data[37usize] == 0u8 { c.big = true } else if data[37usize] != 1u8 { ret (none, BadFile) }
    c.enc = data[70usize]
    let table = trimmed(data[92usize..124usize])
    let h = 164usize + pad + 32usize
    c.header_size = usize(rd32(&c, h))
    c.page_size = usize(rd32(&c, h + 4usize))
    if c.header_size < 1024usize || c.page_size < 1024usize { ret (none, BadFile) }
    if c.header_size > 16777216usize || c.page_size > 16777216usize { ret (none, BadFile) }
    var rel = 0usize
    if c.wide {
        c.page_count = usize(rd64(&c, h + 8usize))
        rel = h + 16usize + 8usize
        c.phs = 40usize
        c.lshp = 24usize
        c.sigl = 8usize
    } else {
        c.page_count = usize(rd32(&c, h + 8usize))
        rel = h + 12usize + 8usize
        c.phs = 24usize
        c.lshp = 12usize
        c.sigl = 4usize
    }
    if c.page_count > 16777216usize { ret (none, BadFile) }
    if c.header_size + c.page_count * c.page_size > data.len { ret (none, BadFile) }
    // the release string "9.0000M0" decides whether a Stat/Transfer file is guessed from it
    let major = data[rel]
    let minor = usize(data[rel + 2usize] - 48u8) * 1000usize + usize(data[rel + 3usize] - 48u8) * 100usize + usize(data[rel + 4usize] - 48u8) * 10usize + usize(data[rel + 5usize] - 48u8)
    let rev = data[rel + 7usize]
    c.vendor_st = (major == 56u8 || major == 57u8) && minor == 0usize && rev == 48u8
    let (b1, be1) = mem.alloc[usize](a, 4096usize)
    let (b2, be2) = mem.alloc[usize](a, 4096usize)
    if be1 != ok { ret (none, be1) }
    if be2 != ok { ret (none, be2) }
    c.blob_at = b1
    c.blob_len = b2
    // pass 1: the column text blobs, from the leading meta pages, then from the trailing ones
    var last = 0usize
    var i = 0usize
    var stop = false
    while i < c.page_count && !stop {
        let page = c.header_size + i * c.page_size
        var off = 0usize
        if c.wide { off = 16usize }
        let ptype = rd16(&c, page + off + 16usize)
        if (ptype & 3840usize) == 256usize {
            stop = true
        } else {
            if (ptype & 36864usize) == 0usize {
                let e = page_pass1(&c, page)
                if e != ok { ret (none, e) }
            }
            i += 1usize
        }
    }
    last = i
    var amd = 0usize
    i = c.page_count
    stop = false
    while i > 0usize && !stop {
        i -= 1usize
        if i <= last && !(last == 0usize && i == 0usize && false) { break }
        let page = c.header_size + i * c.page_size
        var off = 0usize
        if c.wide { off = 16usize }
        let ptype = rd16(&c, page + off + 16usize)
        if (ptype & 3840usize) == 256usize {
            if amd > 0usize { stop = true }
        } else if (ptype & 36864usize) == 0usize {
            let e = page_pass1(&c, page)
            if e != ok { ret (none, e) }
            amd += 1usize
        }
    }
    // pass 2: everything in order
    i = 0usize
    while i < c.page_count {
        let e = page_pass2(&c, c.header_size + i * c.page_size)
        if e != ok { ret (none, e) }
        if c.parsed == c.total_rows && c.ready { break }
        i += 1usize
    }
    let pe = prepare(&c)
    if pe != ok { ret (none, pe) }
    if c.parsed != c.total_rows { ret (none, BadFile) }
    if c.ncols == 0usize { ret (none, BadFile) }
    var comp = 0i64
    if c.compressed {
        comp = 1i64
        if c.rdc { comp = 2i64 }
    }
    ret (Sas { nvars: c.ncols, nobs: c.parsed, table: table, names: c.out_names, labels: c.out_labels, formats: c.out_formats, is_text: c.out_text_flag, kind: c.out_kind, num: c.out_num, tags: c.out_tag, text: c.out_text, compression: comp, u64: c.wide, big: c.big }, ok)
}

// ---- the sas7bcat catalog (value labels) ----

// Label sets in the order haven meets them. A set is named like the format that points at it (`$` first for text
// codes); several sets may share a name (haven merges them). `tags` holds the tag of a tagged missing code the way
// the data cells do (the lower-case letter or `_`, 0 for none); its `num` is then NaN.
type Cat = struct {
    nsets: usize,
    nentries: usize,
    fill: bool,
    names: []str,
    is_text: []u8,
    first: []usize,
    count: []usize,
    num: []f64,
    tags: []u8,
    text: []str,
    label: []str,
}

fn catalog_block_labels(bc: *Ctx, vs: usize, vlen: usize, used: usize, cap: usize, name: str, pad1: usize, cat: *Cat) -> err {
    let (voff, ve) = mem.alloc[usize](bc.a, used + 1usize)
    if ve != ok { ret ve }
    var i = 0usize
    while i < used + 1usize {
        voff[i] = 0usize
        i += 1usize
    }
    var lb1 = 0usize
    i = 0usize
    while i < cap {
        if lb1 + 4usize > vlen { ret BadFile }
        if i < used {
            if lb1 + 10usize + pad1 + 4usize > vlen { ret BadFile }
            let lp = usize(rd32(bc, vs + lb1 + 10usize + pad1))
            if lp >= used { ret BadFile }
            voff[lp] = lb1
        }
        lb1 += 6usize + rd16(bc, vs + lb1 + 2usize)
        i += 1usize
    }
    var lb2 = lb1
    let is_text = name.len > 0usize && name[0usize] == 36u8
    var n = used
    if n > cap { n = cap }
    if cat.fill {
        cat.names[cat.nsets] = name
        cat.first[cat.nsets] = cat.nentries
        cat.count[cat.nsets] = n
        if is_text { cat.is_text[cat.nsets] = 1u8 } else { cat.is_text[cat.nsets] = 0u8 }
    }
    i = 0usize
    while i < n {
        let l1 = voff[i]
        if l1 + 30usize > vlen || lb2 + 10usize > vlen { ret BadFile }
        var dval = 0.0f64
        var tag = 0u8
        var key: str = zero
        if is_text {
            let entry_len = 6usize + rd16(bc, vs + l1 + 2usize)
            if entry_len < 16usize || l1 + entry_len > vlen { ret BadFile }
            let (kt, ke) = utf8_text(bc, bc.d[vs + l1 + entry_len - 16usize..vs + l1 + entry_len])
            if ke != ok { ret ke }
            key = kt
        } else {
            // doubles are stored big-endian whatever the file's order
            var val = 0u64
            var k = 0usize
            while k < 8usize {
                val = (val << 8u64) | u64(bc.d[vs + l1 + 22usize + k])
                k += 1usize
            }
            if (val | 280375465082880u64) == 281474976710655u64 {
                var t = u8((val >> 40u64) & 255u64)
                if t == 0u8 { t = 95u8 } else if t >= 2u8 && t < 28u8 { t = 65u8 + (t - 2u8) }
                if t == 95u8 || (t >= 65u8 && t <= 90u8) {
                    if t >= 65u8 { t = t + 32u8 }
                    tag = t
                }
                dval = 0.0f64 / 0.0f64
            } else {
                dval = mem.bitcast[f64](val)
                if dval > 0.0f64 {
                    dval = mem.bitcast[f64](~val)
                } else {
                    dval = dval * -1.0f64
                }
            }
        }
        var label_len = rd16(bc, vs + lb2 + 8usize)
        if vs + lb2 + 10usize > vs + vlen { ret BadFile }
        if label_len > vlen - (lb2 + 10usize) { label_len = vlen - (lb2 + 10usize) }
        let (lt, le) = utf8_text(bc, bc.d[vs + lb2 + 10usize..vs + lb2 + 10usize + label_len])
        if le != ok { ret le }
        if cat.fill {
            cat.num[cat.nentries] = dval
            cat.tags[cat.nentries] = tag
            cat.text[cat.nentries] = key
            cat.label[cat.nentries] = lt
        }
        cat.nentries += 1usize
        lb2 += 8usize + 2usize + label_len + 1usize
        i += 1usize
    }
    cat.nsets += 1usize
    ret ok
}

fn catalog_block(bc: *Ctx, len: usize, wide: bool, pad1: usize, cat: *Cat) -> err {
    var payload = 106usize
    if len < payload { ret ok }
    let flags = rd16(bc, 2usize)
    var pad = 0usize
    if (flags & 8usize) != 0usize { pad = 4usize }
    var cap = 0usize
    var used = 0usize
    if wide {
        cap = usize(rd64(bc, 42usize + pad))
        used = usize(rd64(bc, 50usize + pad))
        payload += 32usize
    } else {
        cap = usize(rd32(bc, 38usize + pad))
        used = usize(rd32(bc, 42usize + pad))
    }
    var name = trimmed(bc.d[8usize..16usize])
    if pad != 0usize { pad += 16usize }
    if ((flags & 128usize) != 0usize && !wide) || ((flags & 32usize) != 0usize && wide) {
        if len < payload + pad + 32usize { ret ok }
        let (nt, ne) = utf8_text(bc, bc.d[payload + pad..payload + pad + 32usize])
        if ne != ok { ret ne }
        name = nt
        pad += 32usize
    } else {
        let (nt, ne) = utf8_text(bc, bc.d[8usize..16usize])
        if ne != ok { ret ne }
        name = nt
    }
    if len < payload + pad { ret ok }
    if used == 0usize { ret ok }
    if used > 1048576usize || cap > 1048576usize { ret BadFile }
    ret catalog_block_labels(bc, payload + pad, len - payload - pad, used, cap, name, pad1, cat)
}

// the pointers (page << 32 | position) of the catalog blocks held by one XLSR index
fn catalog_index(c: *Ctx, at: usize, len: usize, wide: bool, pad1: usize, ptrs: []u64, nptr: *usize) {
    var xsize = 212usize + pad1
    var o_off = 50usize + pad1
    if wide {
        xsize += 72usize
        o_off += 24usize
    }
    var x = at
    let stop = at + len
    while x + xsize <= stop {
        if !(c.d[x] == 88u8 && c.d[x + 1usize] == 76u8 && c.d[x + 2usize] == 83u8 && c.d[x + 3usize] == 82u8) { x += 8usize }
        if x + 4usize > stop { break }
        if !(c.d[x] == 88u8 && c.d[x + 1usize] == 76u8 && c.d[x + 2usize] == 83u8 && c.d[x + 3usize] == 82u8) { break }
        if x + xsize > stop { break }
        if c.d[x + o_off] == 79u8 {
            var page = 0u64
            var pos = 0u64
            if wide {
                page = rd64(c, x + 8usize)
                pos = u64(rd16(c, x + 16usize))
            } else {
                page = rd32(c, x + 4usize)
                pos = u64(rd16(c, x + 8usize))
            }
            if *nptr < ptrs.len {
                ptrs[*nptr] = (page << 32u64) + pos
                *nptr += 1usize
            }
        }
        x += xsize
    }
}

fn catalog_pass(c: *Ctx, ptrs: []const u64, nptr: usize, wide: bool, pad1: usize, cat: *Cat) -> err {
    var p = 0usize
    while p < nptr {
        let start_page = usize(ptrs[p] >> 32u64)
        let start_pos = usize(ptrs[p] & 65535u64)
        // the chain's total length
        var hl = 16usize
        if wide { hl = 32usize }
        var total = 0usize
        var np = start_page
        var npos = start_pos
        var links = 0usize
        while np > 0usize && npos > 0usize && np <= c.page_count && links < c.page_count {
            links += 1usize
            let at = c.header_size + (np - 1usize) * c.page_size + npos
            if at + hl > c.d.len { ret BadFile }
            var nlen = 0usize
            if wide {
                np = usize(rd32(c, at))
                npos = rd16(c, at + 8usize)
                nlen = rd16(c, at + 10usize)
            } else {
                np = usize(rd32(c, at))
                npos = rd16(c, at + 4usize)
                nlen = rd16(c, at + 6usize)
            }
            total += nlen
        }
        if total > 0usize {
            let (buf, be) = mem.alloc[u8](c.a, total + 8usize)
            if be != ok { ret be }
            np = start_page
            npos = start_pos
            links = 0usize
            var got = 0usize
            while np > 0usize && npos > 0usize && np <= c.page_count && links < c.page_count {
                links += 1usize
                let at = c.header_size + (np - 1usize) * c.page_size + npos
                var nlen = 0usize
                if wide {
                    np = usize(rd32(c, at))
                    npos = rd16(c, at + 8usize)
                    nlen = rd16(c, at + 10usize)
                } else {
                    np = usize(rd32(c, at))
                    npos = rd16(c, at + 4usize)
                    nlen = rd16(c, at + 6usize)
                }
                if got + nlen > total || at + hl + nlen > c.d.len { ret BadFile }
                var q = 0usize
                while q < nlen {
                    buf[got + q] = c.d[at + hl + q]
                    q += 1usize
                }
                got += nlen
            }
            var bc: Ctx = zero
            bc.a = c.a
            bc.d = buf[..total]
            bc.big = c.big
            bc.enc = c.enc
            let e = catalog_block(&bc, total, wide, pad1, cat)
            if e != ok { ret e }
        }
        p += 1usize
    }
    ret ok
}

fn read_catalog(a: *mem.Arena, data: []const u8) -> (Cat, err) {
    var none: Cat = zero
    if data.len < 1024usize { ret (none, BadFile) }
    let magic_a = data[12usize] == 194u8 && data[13usize] == 234u8 && data[14usize] == 129u8 && (data[15usize] == 96u8 || data[15usize] == 99u8)
    let magic_b = data[16usize] == 179u8 && data[17usize] == 20u8 && data[18usize] == 17u8 && data[19usize] == 207u8
    if !(magic_a && magic_b) { ret (none, BadFile) }
    var c: Ctx = zero
    c.a = a
    c.d = data
    c.wide = data[32usize] == 51u8
    var pad1 = 0usize
    if data[35usize] == 51u8 { pad1 = 4usize }
    if data[37usize] == 0u8 { c.big = true } else if data[37usize] != 1u8 { ret (none, BadFile) }
    c.enc = data[70usize]
    let h = 164usize + pad1 + 32usize
    c.header_size = usize(rd32(&c, h))
    c.page_size = usize(rd32(&c, h + 4usize))
    if c.header_size < 1024usize || c.page_size < 1024usize { ret (none, BadFile) }
    if c.header_size > 16777216usize || c.page_size > 16777216usize { ret (none, BadFile) }
    if c.wide { c.page_count = usize(rd64(&c, h + 8usize)) } else { c.page_count = usize(rd32(&c, h + 8usize)) }
    if c.page_count > 16777216usize { ret (none, BadFile) }
    if c.header_size + c.page_count * c.page_size > data.len { ret (none, BadFile) }
    let wide = c.wide
    var xlsr_offset = 856usize + 2usize * pad1
    if wide { xlsr_offset += 144usize }
    let (ptrs, pe) = mem.alloc[u64](a, 65536usize)
    if pe != ok { ret (none, pe) }
    var nptr = 0usize
    if c.page_count > 1usize {
        let page = c.header_size + c.page_size
        catalog_index(&c, page + xlsr_offset, c.page_size - xlsr_offset, wide, pad1, ptrs, &nptr)
    }
    var i = 3usize
    while i < c.page_count {
        let page = c.header_size + i * c.page_size
        if data[page + 16usize] == 88u8 && data[page + 17usize] == 76u8 && data[page + 18usize] == 83u8 && data[page + 19usize] == 82u8 {
            catalog_index(&c, page + 16usize, c.page_size - 16usize, wide, pad1, ptrs, &nptr)
        }
        i += 1usize
    }
    // ReadStat sorts only an unsorted list, then drops adjacent repeats
    var sorted = true
    i = 1usize
    while i < nptr {
        if ptrs[i] < ptrs[i - 1usize] { sorted = false }
        i += 1usize
    }
    if !sorted {
        i = 1usize
        while i < nptr {
            let v = ptrs[i]
            var j = i
            while j > 0usize && ptrs[j - 1usize] > v {
                ptrs[j] = ptrs[j - 1usize]
                j -= 1usize
            }
            ptrs[j] = v
            i += 1usize
        }
    }
    var out_n = 0usize
    if nptr > 0usize { out_n = 1usize }
    i = 1usize
    while i < nptr {
        if ptrs[i] != ptrs[i - 1usize] {
            ptrs[out_n] = ptrs[i]
            out_n += 1usize
        }
        i += 1usize
    }
    var cat: Cat = zero
    cat.fill = false
    let e1 = catalog_pass(&c, ptrs, out_n, wide, pad1, &cat)
    if e1 != ok { ret (none, e1) }
    let ns = cat.nsets
    let ne = cat.nentries
    var cat2: Cat = zero
    let (n1, f1) = mem.alloc[str](a, ns + 1usize)
    let (n2, f2) = mem.alloc[u8](a, ns + 1usize)
    let (n3, f3) = mem.alloc[usize](a, ns + 1usize)
    let (n4, f4) = mem.alloc[usize](a, ns + 1usize)
    let (n5, f5) = mem.alloc[f64](a, ne + 1usize)
    let (n6, f6) = mem.alloc[u8](a, ne + 1usize)
    let (n7, f7) = mem.alloc[str](a, ne + 1usize)
    let (n8, f8) = mem.alloc[str](a, ne + 1usize)
    if f1 != ok { ret (none, f1) }
    if f2 != ok { ret (none, f2) }
    if f3 != ok { ret (none, f3) }
    if f4 != ok { ret (none, f4) }
    if f5 != ok { ret (none, f5) }
    if f6 != ok { ret (none, f6) }
    if f7 != ok { ret (none, f7) }
    if f8 != ok { ret (none, f8) }
    cat2.fill = true
    cat2.names = n1
    cat2.is_text = n2
    cat2.first = n3
    cat2.count = n4
    cat2.num = n5
    cat2.tags = n6
    cat2.text = n7
    cat2.label = n8
    let e2 = catalog_pass(&c, ptrs, out_n, wide, pad1, &cat2)
    if e2 != ok { ret (none, e2) }
    ret (cat2, ok)
}
