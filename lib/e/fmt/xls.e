// The legacy Excel workbook format (BIFF8, .xls): the compound file container (FAT, mini FAT,
// directory), the Workbook stream's records, and the cells of every worksheet -- shared strings
// across CONTINUE records, LABEL, NUMBER, RK and MULRK numbers, BLANK and MULBLANK, BOOLERR,
// FORMULA with its cached result (and the STRING record behind a text result), merged ranges,
// the 1900 and 1904 date systems and which number formats make a number a date. What
// readxl::read_excel reads from a .xls through libxls.
//
// A cell is blank, text, number, boolean, date (the serial number, to be read with `date_serial`)
// or error. Rows and columns are 0-based. Hidden sheets are listed with their state.
//
// Not here: BIFF5 and earlier (ANSI strings, a different BOUNDSHEET), encrypted workbooks, charts
// and macro sheets, rich-text runs and phonetic text (skipped), array and shared formula text,
// and the names of cell styles.

use e.mem
use e.str

error NotACompoundFile
error NoWorkbook
error Corrupt
error Unsupported

const BLANK: u8 = 0u8
const TEXT: u8 = 1u8
const NUMBER: u8 = 2u8
const BOOL: u8 = 3u8
const DATE: u8 = 4u8
const ERROR: u8 = 5u8

type Cell = struct { row: u32, col: u32, kind: u8, num: f64, text: str }

// `merged` holds four numbers per range: first row, last row, first column, last column.
type Sheet = struct { name: str, hidden: u8, cells: []Cell, merged: []u32 }

type Workbook = struct { sheets: []Sheet, date1904: bool }

fn no_bounds() -> []usize {
    var none: []usize = zero
    ret none
}

fn u16_at(d: []const u8, i: usize) -> u32 {
    if i + 2usize > d.len { ret 0u32 }
    ret u32(d[i]) | (u32(d[i + 1usize]) << 8u32)
}

fn u32_at(d: []const u8, i: usize) -> u32 {
    if i + 4usize > d.len { ret 0u32 }
    ret u32(d[i]) | (u32(d[i + 1usize]) << 8u32) | (u32(d[i + 2usize]) << 16u32) | (u32(d[i + 3usize]) << 24u32)
}

fn f64_at(d: []const u8, i: usize) -> f64 {
    if i + 8usize > d.len { ret 0.0f64 }
    var v = 0u64
    var k = 0usize
    while k < 8usize {
        v = v | (u64(d[i + k]) << u64(8usize * k))
        k += 1usize
    }
    ret mem.bitcast[f64](v)
}

// --- The compound file

type Cfb = struct { data: []const u8, sector: usize, mini_sector: usize, fat: []u32, minifat: []u32, ministream: []const u8, cutoff: u32 }

fn sector_offset(c: *const Cfb, s: u32) -> usize { ret (usize(s) + 1usize) * c.sector }

// The chain of sectors from `start` as one byte string, `size` bytes (or the whole chain when size is 0xFFFFFFFF).
fn read_chain(a: *mem.Arena, c: *const Cfb, start: u32, size: usize) -> ([]u8, err) {
    var none: []u8 = zero
    let nsec = c.fat.len
    let (out, e) = mem.alloc[u8](a, (nsec + 1usize) * c.sector + 1usize)
    if e != ok { ret (none, e) }
    var n = 0usize
    var s = start
    var guard = 0usize
    while s < 4294967290u32 && guard <= nsec {
        let off = sector_offset(c, s)
        if off + c.sector > c.data.len { ret (none, Corrupt) }
        var k = 0usize
        while k < c.sector {
            out[n + k] = c.data[off + k]
            k += 1usize
        }
        n += c.sector
        if usize(s) >= c.fat.len { ret (none, Corrupt) }
        s = c.fat[usize(s)]
        guard += 1usize
    }
    if size != 4294967295usize && size < n { n = size }
    ret (out[0usize..n], ok)
}

fn read_mini_chain(a: *mem.Arena, c: *const Cfb, start: u32, size: usize) -> ([]u8, err) {
    var none: []u8 = zero
    let (out, e) = mem.alloc[u8](a, size + c.mini_sector + 1usize)
    if e != ok { ret (none, e) }
    var n = 0usize
    var s = start
    var guard = 0usize
    while s < 4294967290u32 && n < size && guard <= c.minifat.len {
        let off = usize(s) * c.mini_sector
        if off + c.mini_sector > c.ministream.len { ret (none, Corrupt) }
        var k = 0usize
        while k < c.mini_sector {
            out[n + k] = c.ministream[off + k]
            k += 1usize
        }
        n += c.mini_sector
        if usize(s) >= c.minifat.len { ret (none, Corrupt) }
        s = c.minifat[usize(s)]
        guard += 1usize
    }
    if n > size { n = size }
    ret (out[0usize..n], ok)
}

fn name_is(entry: []const u8, name: str) -> bool {
    let len = usize(u16_at(entry, 64usize))
    if len < 2usize { ret false }
    let chars = len / 2usize - 1usize
    if chars != name.len { ret false }
    var i = 0usize
    while i < chars {
        if entry[2usize * i] != name[i] || entry[2usize * i + 1usize] != 0u8 { ret false }
        i += 1usize
    }
    ret true
}

// The bytes of the Workbook (or Book) stream.
fn workbook_stream(a: *mem.Arena, data: []const u8) -> ([]u8, err) {
    var none: []u8 = zero
    if data.len < 512usize { ret (none, NotACompoundFile) }
    if data[0usize] != 208u8 || data[1usize] != 207u8 || data[2usize] != 17u8 || data[3usize] != 224u8 { ret (none, NotACompoundFile) }
    let sector_shift2 = u16_at(data, 0x1Eusize)
    let mini_shift = u16_at(data, 0x20usize)
    let ssize = usize(1u32 << sector_shift2)
    let msize = usize(1u32 << mini_shift)
    let nfat = usize(u32_at(data, 0x2Cusize))
    let dir_start = u32_at(data, 0x30usize)
    let cutoff = u32_at(data, 0x38usize)
    let minifat_start = u32_at(data, 0x3Cusize)
    let nminifat = usize(u32_at(data, 0x40usize))
    let difat_start = u32_at(data, 0x44usize)
    let ndifat = usize(u32_at(data, 0x48usize))
    // the FAT sector numbers
    let per = ssize / 4usize
    let (fatsecs, fe) = mem.alloc[u32](a, nfat + 109usize + ndifat * per + 1usize)
    if fe != ok { ret (none, fe) }
    var nf = 0usize
    var i = 0usize
    while i < 109usize && nf < nfat {
        fatsecs[nf] = u32_at(data, 0x4Cusize + 4usize * i)
        nf += 1usize
        i += 1usize
    }
    var ds = difat_start
    var dn = 0usize
    while dn < ndifat && ds < 4294967290u32 && nf < nfat {
        let off = (usize(ds) + 1usize) * ssize
        if off + ssize > data.len { ret (none, Corrupt) }
        var k = 0usize
        while k < per - 1usize && nf < nfat {
            fatsecs[nf] = u32_at(data, off + 4usize * k)
            nf += 1usize
            k += 1usize
        }
        ds = u32_at(data, off + 4usize * (per - 1usize))
        dn += 1usize
    }
    let (fat, fate) = mem.alloc[u32](a, nf * per + 1usize)
    if fate != ok { ret (none, fate) }
    var q = 0usize
    while q < nf {
        let off = (usize(fatsecs[q]) + 1usize) * ssize
        if off + ssize > data.len { ret (none, Corrupt) }
        var k = 0usize
        while k < per {
            fat[q * per + k] = u32_at(data, off + 4usize * k)
            k += 1usize
        }
        q += 1usize
    }
    var cfb = Cfb { data: data, sector: ssize, mini_sector: msize, fat: fat[0usize..nf * per], minifat: fat[0usize..0usize], ministream: data[0usize..0usize], cutoff: cutoff }
    let (dir, de) = read_chain(a, &cfb, dir_start, 4294967295usize)
    if de != ok { ret (none, de) }
    // the root entry holds the mini stream
    var root_start = 0u32
    var root_size = 0usize
    var found = false
    var wb_start = 0u32
    var wb_size = 0usize
    var e = 0usize
    while e + 128usize <= dir.len {
        let entry = dir[e..e + 128usize]
        let typ = entry[66usize]
        if typ == 5u8 {
            root_start = u32_at(entry, 0x74usize)
            root_size = usize(u32_at(entry, 0x78usize))
        }
        if typ == 2u8 && (name_is(entry, "Workbook") || name_is(entry, "Book")) {
            wb_start = u32_at(entry, 0x74usize)
            wb_size = usize(u32_at(entry, 0x78usize))
            found = true
        }
        e += 128usize
    }
    if !found { ret (none, NoWorkbook) }
    if u32(wb_size) >= cutoff {
        let (r, re) = read_chain(a, &cfb, wb_start, wb_size)
        ret (r, re)
    }
    // small stream: through the mini FAT
    let (mf, mfe) = read_chain(a, &cfb, minifat_start, 4294967295usize)
    if mfe != ok { ret (none, mfe) }
    let (minifat, mine) = mem.alloc[u32](a, mf.len / 4usize + 1usize)
    if mine != ok { ret (none, mine) }
    var t = 0usize
    while t < mf.len / 4usize {
        minifat[t] = u32_at(mf, 4usize * t)
        t += 1usize
    }
    let _ = nminifat
    let (ms, mse) = read_chain(a, &cfb, root_start, root_size)
    if mse != ok { ret (none, mse) }
    cfb.minifat = minifat[0usize..mf.len / 4usize]
    cfb.ministream = ms
    let (r, re) = read_mini_chain(a, &cfb, wb_start, wb_size)
    ret (r, re)
}

// --- Strings

// A cursor over concatenated record data; `bounds` are the offsets where a CONTINUE record began.
type Reader = struct { d: []const u8, pos: usize, bounds: []usize, high: bool }

fn at_bound(r: *const Reader, pos: usize) -> bool {
    var i = 0usize
    while i < r.bounds.len {
        if r.bounds[i] == pos { ret true }
        i += 1usize
    }
    ret false
}

fn push_utf8(b: *str.Builder, cp: u32) {
    if cp < 128u32 {
        let _ = str.push_byte(b, u8(cp))
    } else if cp < 2048u32 {
        let _ = str.push_byte(b, u8(192u32 | (cp >> 6u32)))
        let _ = str.push_byte(b, u8(128u32 | (cp & 63u32)))
    } else if cp < 65536u32 {
        let _ = str.push_byte(b, u8(224u32 | (cp >> 12u32)))
        let _ = str.push_byte(b, u8(128u32 | ((cp >> 6u32) & 63u32)))
        let _ = str.push_byte(b, u8(128u32 | (cp & 63u32)))
    } else {
        let _ = str.push_byte(b, u8(240u32 | (cp >> 18u32)))
        let _ = str.push_byte(b, u8(128u32 | ((cp >> 12u32) & 63u32)))
        let _ = str.push_byte(b, u8(128u32 | ((cp >> 6u32) & 63u32)))
        let _ = str.push_byte(b, u8(128u32 | (cp & 63u32)))
    }
}

// XLUnicodeRichExtendedString after its character count: flags, optional run and extension sizes,
// the characters (a CONTINUE boundary inside them restates the width flag), then the runs and the
// extension are skipped.
fn read_string(a: *mem.Arena, r: *Reader, cch: usize) -> (str, err) {
    if r.pos >= r.d.len { ret ("", Corrupt) }
    let flags = r.d[r.pos]
    r.pos += 1usize
    var high = (flags & 1u8) != 0u8
    var runs = 0usize
    var ext = 0usize
    if (flags & 8u8) != 0u8 {
        runs = usize(u16_at(r.d, r.pos))
        r.pos += 2usize
    }
    if (flags & 4u8) != 0u8 {
        ext = usize(u32_at(r.d, r.pos))
        r.pos += 4usize
    }
    let (initial, be) = str.builder(a, cch * 3usize + 8usize)
    if be != ok { ret ("", be) }
    var b = initial
    var i = 0usize
    while i < cch {
        if i > 0usize && at_bound(r, r.pos) && r.pos < r.d.len {
            high = (r.d[r.pos] & 1u8) != 0u8
            r.pos += 1usize
        }
        if high {
            if r.pos + 2usize > r.d.len { ret ("", Corrupt) }
            var cp = u16_at(r.d, r.pos)
            r.pos += 2usize
            if cp >= 55296u32 && cp < 56320u32 && i + 1usize < cch {
                // a surrogate pair
                if r.pos + 2usize > r.d.len { ret ("", Corrupt) }
                let lo = u16_at(r.d, r.pos)
                r.pos += 2usize
                i += 1usize
                cp = 65536u32 + ((cp - 55296u32) << 10u32) + (lo - 56320u32)
            }
            push_utf8(&b, cp)
        } else {
            if r.pos + 1usize > r.d.len { ret ("", Corrupt) }
            push_utf8(&b, u32(r.d[r.pos]))
            r.pos += 1usize
        }
        i += 1usize
    }
    r.pos += runs * 4usize + ext
    ret (str.done(&b), ok)
}

// --- Number formats that make a date

fn builtin_date(id: u32) -> bool {
    if id >= 14u32 && id <= 22u32 { ret true }
    if id >= 27u32 && id <= 36u32 { ret true }
    if id >= 45u32 && id <= 47u32 { ret true }
    if id >= 50u32 && id <= 58u32 { ret true }
    ret false
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// Whether a custom format string shows a date or time: a y, m, d, h or s outside quotes and brackets.
fn format_is_date(f: str) -> bool {
    var i = 0usize
    while i < f.len {
        let c = f[i]
        if c == 34u8 {
            i += 1usize
            while i < f.len && f[i] != 34u8 { i += 1usize }
        } else if c == 91u8 {
            // [h] [mm] [ss] elapsed time counts, the others (colours, conditions, locales) do not
            var j = i + 1usize
            var elapsed = false
            if j < f.len {
                let d = lower(f[j])
                if d == 104u8 || d == 109u8 || d == 115u8 { elapsed = true }
            }
            while j < f.len && f[j] != 93u8 { j += 1usize }
            if elapsed { ret true }
            i = j
        } else if c == 92u8 || c == 95u8 || c == 42u8 {
            i += 1usize
        } else {
            let d = lower(c)
            if d == 121u8 || d == 100u8 || d == 104u8 || d == 115u8 { ret true }
            if d == 109u8 { ret true }
            // "General" and "E+" contain none of the date letters except through 'e' and 'g'
        }
        i += 1usize
    }
    ret false
}

// --- The workbook

type Xf = struct { fmt: u32 }

fn rk_value(rk: u32) -> f64 {
    var v = 0.0f64
    if (rk & 2u32) != 0u32 {
        var signed = i64(rk)
        if signed >= 2147483648i64 { signed = signed - 4294967296i64 }
        v = f64((signed - i64(rk & 3u32)) / 4i64)
    } else {
        let bits = u64(rk & 4294967292u32) << 32u64
        v = mem.bitcast[f64](bits)
    }
    if (rk & 1u32) != 0u32 { v = v / 100.0f64 }
    ret v
}

type Recs = struct { id: []u32, start: []usize, len: []usize, n: usize }

// The record boundaries of a stream.
fn scan(a: *mem.Arena, d: []const u8) -> (Recs, err) {
    var empty: Recs = zero
    let cap = d.len / 4usize + 1usize
    let (ids, ie) = mem.alloc[u32](a, cap)
    let (starts, se) = mem.alloc[usize](a, cap)
    let (lens, le) = mem.alloc[usize](a, cap)
    if ie != ok { ret (empty, ie) }
    if se != ok { ret (empty, se) }
    if le != ok { ret (empty, le) }
    var n = 0usize
    var p = 0usize
    while p + 4usize <= d.len {
        let id = u16_at(d, p)
        let len = usize(u16_at(d, p + 2usize))
        if p + 4usize + len > d.len { break }
        ids[n] = id
        starts[n] = p + 4usize
        lens[n] = len
        n += 1usize
        p += 4usize + len
    }
    ret (Recs { id: ids, start: starts, len: lens, n: n }, ok)
}

fn error_text(code: u8) -> str {
    if code == 0u8 { ret "#NULL!" }
    if code == 7u8 { ret "#DIV/0!" }
    if code == 15u8 { ret "#VALUE!" }
    if code == 23u8 { ret "#REF!" }
    if code == 29u8 { ret "#NAME?" }
    if code == 36u8 { ret "#NUM!" }
    if code == 42u8 { ret "#N/A" }
    ret "#ERR"
}

fn is_date_xf(xfs: []const u32, formats_start: []const u32, formats_text: []const str, ixfe: u32) -> bool {
    if usize(ixfe) >= xfs.len { ret false }
    let id = xfs[usize(ixfe)]
    if builtin_date(id) { ret true }
    var i = 0usize
    while i < formats_start.len {
        if formats_start[i] == id { ret format_is_date(formats_text[i]) }
        i += 1usize
    }
    ret false
}

// Reads every worksheet of an .xls file.
fn read(a: *mem.Arena, data: []const u8) -> (Workbook, err) {
    var empty: Workbook = zero
    let (wb, we) = workbook_stream(a, data)
    if we != ok { ret (empty, we) }
    let (recs, re) = scan(a, wb)
    if re != ok { ret (empty, re) }
    // globals: the first BOF to its EOF
    let (names, ne) = mem.alloc[str](a, recs.n + 1usize)
    let (hidden, he) = mem.alloc[u8](a, recs.n + 1usize)
    let (offsets, oe) = mem.alloc[u32](a, recs.n + 1usize)
    let (xfs, xe) = mem.alloc[u32](a, recs.n + 1usize)
    let (fmt_id, fie) = mem.alloc[u32](a, recs.n + 1usize)
    let (fmt_text, fte) = mem.alloc[str](a, recs.n + 1usize)
    let (sst, sste) = mem.alloc[str](a, wb.len / 2usize + 8usize)
    if ne != ok { ret (empty, ne) }
    if he != ok { ret (empty, he) }
    if oe != ok { ret (empty, oe) }
    if xe != ok { ret (empty, xe) }
    if fie != ok { ret (empty, fie) }
    if fte != ok { ret (empty, fte) }
    if sste != ok { ret (empty, sste) }
    var nsheets = 0usize
    var nxf = 0usize
    var nfmt = 0usize
    var nsst = 0usize
    var date1904 = false
    var i = 0usize
    var seen_bof = false
    var done = false
    while i < recs.n && !done {
        let id = recs.id[i]
        let d = wb[recs.start[i]..recs.start[i] + recs.len[i]]
        if id == 2057u32 {
            if seen_bof { done = true }
            seen_bof = true
        } else if id == 10u32 {
            done = true
        } else if id == 34u32 {
            date1904 = u16_at(d, 0usize) == 1u32
        } else if id == 133u32 {
            offsets[nsheets] = u32_at(d, 0usize)
            hidden[nsheets] = d[4usize] & 3u8
            let cch = usize(d[6usize])
            var rd = Reader { d: d, pos: 7usize, bounds: no_bounds(), high: false }
            let (s, se) = read_string(a, &rd, cch)
            if se != ok { ret (empty, se) }
            names[nsheets] = s
            nsheets += 1usize
        } else if id == 224u32 {
            xfs[nxf] = u16_at(d, 2usize)
            nxf += 1usize
        } else if id == 1054u32 {
            fmt_id[nfmt] = u16_at(d, 0usize)
            let cch = usize(u16_at(d, 2usize))
            var rd = Reader { d: d, pos: 4usize, bounds: no_bounds(), high: false }
            let (s, se) = read_string(a, &rd, cch)
            if se != ok { ret (empty, se) }
            fmt_text[nfmt] = s
            nfmt += 1usize
        } else if id == 252u32 {
            // SST with its CONTINUE records, boundaries kept
            var total = recs.len[i]
            var j = i + 1usize
            while j < recs.n && recs.id[j] == 60u32 {
                total += recs.len[j]
                j += 1usize
            }
            let (buf, be) = mem.alloc[u8](a, total + 1usize)
            let (bounds, boe) = mem.alloc[usize](a, j - i + 1usize)
            if be != ok { ret (empty, be) }
            if boe != ok { ret (empty, boe) }
            var at = 0usize
            var nb = 0usize
            var q = i
            while q < j {
                var k = 0usize
                if q > i {
                    bounds[nb] = at
                    nb += 1usize
                }
                while k < recs.len[q] {
                    buf[at + k] = wb[recs.start[q] + k]
                    k += 1usize
                }
                at += recs.len[q]
                q += 1usize
            }
            let unique = usize(u32_at(buf, 4usize))
            var rd = Reader { d: buf[0usize..total], pos: 8usize, bounds: bounds[0usize..nb], high: false }
            var s = 0usize
            while s < unique && rd.pos + 3usize <= total {
                let cch = usize(u16_at(rd.d, rd.pos))
                rd.pos += 2usize
                let (text, te) = read_string(a, &rd, cch)
                if te != ok { ret (empty, te) }
                sst[nsst] = text
                nsst += 1usize
                s += 1usize
            }
            i = j - 1usize
        }
        i += 1usize
    }
    let (sheets, shE) = mem.alloc[Sheet](a, nsheets + 1usize)
    if shE != ok { ret (empty, shE) }
    var si = 0usize
    while si < nsheets {
        let (sheet, sre) = read_sheet(a, wb, recs, usize(offsets[si]), names[si], hidden[si], xfs[0usize..nxf], fmt_id[0usize..nfmt], fmt_text[0usize..nfmt], sst[0usize..nsst])
        if sre != ok { ret (empty, sre) }
        sheets[si] = sheet
        si += 1usize
    }
    ret (Workbook { sheets: sheets[0usize..nsheets], date1904: date1904 }, ok)
}

fn find_record_at(recs: Recs, offset: usize) -> usize {
    // the record whose header starts at `offset` (its data at offset + 4)
    var i = 0usize
    while i < recs.n {
        if recs.start[i] == offset + 4usize { ret i }
        i += 1usize
    }
    ret recs.n
}

fn read_sheet(a: *mem.Arena, wb: []const u8, recs: Recs, offset: usize, name: str, hidden: u8, xfs: []const u32, fmt_id: []const u32, fmt_text: []const str, sst: []const str) -> (Sheet, err) {
    var empty: Sheet = zero
    let first = find_record_at(recs, offset)
    if first >= recs.n { ret (empty, Corrupt) }
    var cap = 64usize
    var i = first + 1usize
    while i < recs.n && recs.id[i] != 10u32 {
        cap += usize(recs.len[i]) / 2usize + 2usize
        i += 1usize
    }
    let (cells, ce) = mem.alloc[Cell](a, cap)
    let (merged, me) = mem.alloc[u32](a, cap)
    if ce != ok { ret (empty, ce) }
    if me != ok { ret (empty, me) }
    var n = 0usize
    var nm = 0usize
    i = first + 1usize
    var pending_row = 0u32
    var pending_col = 0u32
    var pending = false
    while i < recs.n && recs.id[i] != 10u32 {
        let id = recs.id[i]
        let d = wb[recs.start[i]..recs.start[i] + recs.len[i]]
        let row = u16_at(d, 0usize)
        let col = u16_at(d, 2usize)
        if id == 253u32 {
            let idx = usize(u32_at(d, 6usize))
            var t = ""
            if idx < sst.len { t = sst[idx] }
            cells[n] = Cell { row: row, col: col, kind: TEXT, num: 0.0f64, text: t }
            n += 1usize
        } else if id == 516u32 {
            let cch = usize(u16_at(d, 6usize))
            var rd = Reader { d: d, pos: 8usize, bounds: no_bounds(), high: false }
            let (s, se) = read_string(a, &rd, cch)
            if se != ok { ret (empty, se) }
            cells[n] = Cell { row: row, col: col, kind: TEXT, num: 0.0f64, text: s }
            n += 1usize
        } else if id == 515u32 || id == 638u32 {
            var v = 0.0f64
            if id == 515u32 { v = f64_at(d, 6usize) } else { v = rk_value(u32_at(d, 6usize)) }
            var kind = NUMBER
            if is_date_xf(xfs, fmt_id, fmt_text, u16_at(d, 4usize)) { kind = DATE }
            cells[n] = Cell { row: row, col: col, kind: kind, num: v, text: "" }
            n += 1usize
        } else if id == 189u32 {
            // MULRK: row, first column, (xf, rk) pairs, last column
            let last = usize(u16_at(d, d.len - 2usize))
            var k = 0usize
            while usize(col) + k <= last && 4usize + 6usize * (k + 1usize) <= d.len - 2usize + 0usize {
                let off = 4usize + 6usize * k
                var kind = NUMBER
                if is_date_xf(xfs, fmt_id, fmt_text, u16_at(d, off)) { kind = DATE }
                cells[n] = Cell { row: row, col: col + u32(k), kind: kind, num: rk_value(u32_at(d, off + 2usize)), text: "" }
                n += 1usize
                k += 1usize
            }
        } else if id == 513u32 {
            cells[n] = Cell { row: row, col: col, kind: BLANK, num: 0.0f64, text: "" }
            n += 1usize
        } else if id == 190u32 {
            let last = usize(u16_at(d, d.len - 2usize))
            var k = 0usize
            while usize(col) + k <= last {
                cells[n] = Cell { row: row, col: col + u32(k), kind: BLANK, num: 0.0f64, text: "" }
                n += 1usize
                k += 1usize
            }
        } else if id == 517u32 {
            if d[7usize] != 0u8 {
                cells[n] = Cell { row: row, col: col, kind: ERROR, num: 0.0f64, text: error_text(d[6usize]) }
            } else {
                cells[n] = Cell { row: row, col: col, kind: BOOL, num: f64(d[6usize]), text: "" }
            }
            n += 1usize
        } else if id == 6u32 {
            // FORMULA: the cached result
            let b6 = d[12usize]
            let b7 = d[13usize]
            if b6 == 255u8 && b7 == 255u8 {
                let t = d[6usize]
                if t == 0u8 {
                    pending = true
                    pending_row = row
                    pending_col = col
                } else if t == 1u8 {
                    cells[n] = Cell { row: row, col: col, kind: BOOL, num: f64(d[8usize]), text: "" }
                    n += 1usize
                } else if t == 2u8 {
                    cells[n] = Cell { row: row, col: col, kind: ERROR, num: 0.0f64, text: error_text(d[8usize]) }
                    n += 1usize
                } else {
                    cells[n] = Cell { row: row, col: col, kind: TEXT, num: 0.0f64, text: "" }
                    n += 1usize
                }
            } else {
                var kind = NUMBER
                if is_date_xf(xfs, fmt_id, fmt_text, u16_at(d, 4usize)) { kind = DATE }
                cells[n] = Cell { row: row, col: col, kind: kind, num: f64_at(d, 6usize), text: "" }
                n += 1usize
            }
        } else if id == 519u32 {
            if pending {
                let cch = usize(u16_at(d, 0usize))
                var rd = Reader { d: d, pos: 2usize, bounds: no_bounds(), high: false }
                let (s, se) = read_string(a, &rd, cch)
                if se != ok { ret (empty, se) }
                cells[n] = Cell { row: pending_row, col: pending_col, kind: TEXT, num: 0.0f64, text: s }
                n += 1usize
                pending = false
            }
        } else if id == 229u32 {
            let count = usize(u16_at(d, 0usize))
            var k = 0usize
            while k < count && 2usize + 8usize * (k + 1usize) <= d.len {
                let off = 2usize + 8usize * k
                merged[nm] = u16_at(d, off)
                merged[nm + 1usize] = u16_at(d, off + 2usize)
                merged[nm + 2usize] = u16_at(d, off + 4usize)
                merged[nm + 3usize] = u16_at(d, off + 6usize)
                nm += 4usize
                k += 1usize
            }
        }
        i += 1usize
    }
    ret (Sheet { name: name, hidden: hidden, cells: cells[0usize..n], merged: merged[0usize..nm] }, ok)
}

// The cell at (row, col), or a blank.
fn cell_at(s: *const Sheet, row: u32, col: u32) -> Cell {
    var i = 0usize
    while i < s.cells.len {
        if s.cells[i].row == row && s.cells[i].col == col { ret s.cells[i] }
        i += 1usize
    }
    ret Cell { row: row, col: col, kind: BLANK, num: 0.0f64, text: "" }
}

// A date cell's value as a 1900-system serial number whichever system the workbook uses.
fn date_serial(w: *const Workbook, v: f64) -> f64 {
    if w.date1904 { ret v + 1462.0f64 }
    ret v
}
