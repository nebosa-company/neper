// Systat (.sys, .syd) data file reader as foreign::read.systat takes it (R_systat.c). The file is Fortran sequential unformatted records: a header of packets (byte 0x4B 0x06, three
// little-endian shorts nv, mtype and ntype, 0x06; for a later version the shorts are zero and comment records 0x48 + 72 bytes + 0x48 follow until one begins with '$', then the
// shorts again), one 14-byte label packet 0x0C + 12 characters + 0x0C per variable, then the data records. A record of at most 128 bytes is one packet (its length, the bytes, the length);
// a longer one is 130-byte packets of 128 bytes between 0x81 marks and a last packet of the rest. The file ends in 0x82, possibly followed by NULs. A variable whose label (blanks removed)
// has a '$' is a string of 12 characters (all blanks is missing), the others are floats (ntype 1) or doubles, and -1e36 is missing. Names are made as as.data.frame(check.names = TRUE)
// makes them: make.names, then make.unique.
// The reader is the C reader's: its offsets, including the way it places strings across packet bounds, and its errors (every access past the end of the file is one, as is a file that is not
// rectangular, mtype 1). Comments are not kept (read.systat's comment is empty for every file the C reader accepts).

use e.mem
use e.str

error Malformed
error NotRectangular

type Systat = struct { nv: usize, nobs: usize, isstr: []bool, names: []str, num: []f64, sat: []usize, slen: []usize, sna: []bool, sbuf: []u8 }

fn have(b: []const u8, at: usize, n: usize) -> bool { ret at + n <= b.len }

fn i16le(b: []const u8, at: usize) -> i64 {
    var v = i64(b[at]) + 256i64 * i64(b[at + 1usize])
    if v >= 32768i64 { v = v - 65536i64 }
    ret v
}

fn is_alpha(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn reserved(s: str) -> bool {
    if str.eq(s, "if") || str.eq(s, "else") || str.eq(s, "repeat") || str.eq(s, "while") || str.eq(s, "function") || str.eq(s, "for") { ret true }
    if str.eq(s, "next") || str.eq(s, "break") || str.eq(s, "TRUE") || str.eq(s, "FALSE") || str.eq(s, "NULL") || str.eq(s, "Inf") || str.eq(s, "NaN") { ret true }
    if str.eq(s, "NA") || str.eq(s, "NA_integer_") || str.eq(s, "NA_real_") || str.eq(s, "NA_character_") || str.eq(s, "NA_complex_") || str.eq(s, "in") { ret true }
    ret false
}

// make.names (one name, no uniqueness)
fn make_name(a: *mem.Arena, s: str) -> (str, err) {
    let (bb, be) = str.builder(a, s.len + 4usize)
    if be != ok { ret ("", be) }
    var w = bb
    var need_x = false
    if s.len == 0usize { need_x = true } else {
        let c = s[0usize]
        if !is_alpha(c) && c != 46u8 { need_x = true }
        if c == 46u8 && s.len > 1usize && is_digit(s[1usize]) { need_x = true }
    }
    if need_x { let _ = str.push_byte(&w, 88u8) }
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if is_alpha(c) || is_digit(c) || c == 46u8 || c == 95u8 { let _ = str.push_byte(&w, c) } else { let _ = str.push_byte(&w, 46u8) }
        i += 1usize
    }
    let t = str.done(&w)
    if reserved(t) {
        let (b2, e2) = str.builder(a, t.len + 2usize)
        if e2 != ok { ret ("", e2) }
        var w2 = b2
        let _ = str.push(&w2, t)
        let _ = str.push_byte(&w2, 46u8)
        ret (str.done(&w2), ok)
    }
    ret (t, ok)
}

fn taken(names: []str, n: usize, s: str) -> bool {
    var i = 0usize
    while i < n {
        if str.eq(names[i], s) { ret true }
        i += 1usize
    }
    ret false
}

// make.unique(names, "."): the later copies get .1, .2, ... skipping any name in use
fn make_unique(a: *mem.Arena, names: []str, n: usize) -> err {
    var i = 1usize
    while i < n {
        var dup = false
        var j = 0usize
        while j < i {
            if str.eq(names[j], names[i]) { dup = true }
            j += 1usize
        }
        if dup {
            var cnt = 1u64
            var done = false
            while !done {
                let (bb, be) = str.builder(a, names[i].len + 24usize)
                if be != ok { ret be }
                var w = bb
                let _ = str.push(&w, names[i])
                let _ = str.push_byte(&w, 46u8)
                let _ = str.push_u64(&w, cnt)
                let cand = str.done(&w)
                var clash = false
                var m = 0usize
                while m < n {
                    if m != i && str.eq(names[m], cand) { clash = true }
                    m += 1usize
                }
                if !clash {
                    names[i] = cand
                    done = true
                }
                cnt += 1u64
            }
        }
        i += 1usize
    }
    ret ok
}

fn parse(a: *mem.Arena, b: []const u8) -> (Systat, err) {
    let (t, e) = parse_opt(a, b, true)
    ret (t, e)
}

// read.systat(to.data.frame = FALSE): the list the C reader builds, its names the labels as they stand (no make.names, no make.unique)
fn parse_list(a: *mem.Arena, b: []const u8) -> (Systat, err) {
    let (t, e) = parse_opt(a, b, false)
    ret (t, e)
}

fn parse_opt(a: *mem.Arena, b: []const u8, to_df: bool) -> (Systat, err) {
    var out: Systat = zero
    // header packets
    if !have(b, 0usize, 10usize) { ret (out, Malformed) }
    if b[0usize] != 75u8 || b[1usize] != 6u8 { ret (out, Malformed) }
    var nv = i16le(b, 2usize)
    var mtype = i16le(b, 4usize)
    var ntype = i16le(b, 6usize)
    if b[8usize] != 6u8 { ret (out, Malformed) }
    var p = 9usize
    if ntype != 1i64 && ntype != 2i64 {
        var is_dollar = false
        var more = true
        while more {
            is_dollar = false
            if !have(b, p, 74usize) || b[p] != 72u8 { ret (out, Malformed) }
            if b[p + 1usize] == 36u8 { is_dollar = true }
            p += 73usize
            if b[p] != 72u8 { ret (out, Malformed) }
            p += 1usize
            more = !is_dollar
        }
        if !have(b, p, 8usize) || b[p] != 6u8 { ret (out, Malformed) }
        nv = i16le(b, p + 1usize)
        mtype = i16le(b, p + 3usize)
        ntype = i16le(b, p + 5usize)
        if b[p + 7usize] != 6u8 { ret (out, Malformed) }
        p += 8usize
    }
    if nv > 8192i64 || nv < 0i64 { ret (out, Malformed) }
    let n = usize(nv)
    let (lab, e1) = mem.alloc[str](a, n + 1usize)
    let (isstr, e2) = mem.alloc[bool](a, n + 1usize)
    let (ithdb, e3) = mem.alloc[usize](a, n + 1usize)
    let (ithstr, e4) = mem.alloc[usize](a, n + 1usize)
    let (stroff, e5) = mem.alloc[i64](a, n + 1usize)
    let (loc, e6) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, mem.Full) }
    var nd = 0usize
    var nk = 0usize
    var j = 0usize
    while j < n + 1usize {
        stroff[j] = 0i64
        ithdb[j] = 0usize
        ithstr[j] = 0usize
        j += 1usize
    }
    j = 0usize
    while j < n {
        if !have(b, p, 14usize) || b[p] != 12u8 || b[p + 13usize] != 12u8 { ret (out, Malformed) }
        // label of 12 bytes: nk when the ninth is '$' or any is, nd otherwise; the name is the non-blanks up to the first NUL
        var any_dollar = b[p + 9usize] == 36u8
        var q = 0usize
        while q < 12usize && b[p + 1usize + q] != 0u8 {
            if b[p + 1usize + q] == 36u8 { any_dollar = true }
            q += 1usize
        }
        if any_dollar { nk += 1usize } else { nd += 1usize }
        let (nb, ne) = str.builder(a, 16usize)
        if ne != ok { ret (out, ne) }
        var w = nb
        q = 0usize
        while q < 12usize && b[p + 1usize + q] != 0u8 {
            if b[p + 1usize + q] != 32u8 { let _ = str.push_byte(&w, b[p + 1usize + q]) }
            q += 1usize
        }
        lab[j] = str.done(&w)
        p += 14usize
        j += 1usize
    }
    let pos = p
    // the numbering by a '$' in the name as left after blanks are removed
    var dj = 0usize
    var kj = 0usize
    j = 0usize
    while j < n {
        var has = false
        var q = 0usize
        while q < lab[j].len {
            if lab[j][q] == 36u8 { has = true }
            q += 1usize
        }
        isstr[j] = has
        if has {
            ithstr[j] = kj
            kj += 1usize
        } else {
            ithdb[j] = dj
            dj += 1usize
        }
        j += 1usize
    }
    if nd != dj || nk != kj { ret (out, Malformed) }
    if !have(b, pos, 1usize) { ret (out, Malformed) }
    var k = usize(b[pos])
    var offset = 0usize
    var tsz = 8usize
    if ntype == 1i64 { tsz = 4usize }
    if k < 129usize {
        offset = k + 2usize
    } else if k == 129usize {
        var i = 0usize
        var at = pos
        while k == 129usize {
            at += 130usize
            if !have(b, at, 1usize) { ret (out, Malformed) }
            k = usize(b[at])
            i += 1usize
        }
        offset = k + 2usize + i * 130usize
        if nk > 0usize {
            var dbrec = (nd % (128usize / tsz)) * tsz
            var s = 0usize
            while s < nk {
                dbrec += 12usize
                stroff[s] = 0i64
                if dbrec > 128usize {
                    stroff[s] = i64(dbrec % 128usize)
                    dbrec = dbrec % 128usize
                } else if dbrec == 128usize {
                    stroff[s] = 0i64 - 1i64
                    dbrec = 0usize
                }
                s += 1usize
            }
        }
    } else {
        ret (out, Malformed)
    }
    // the end of the file: back over NULs (at most 511) to the final 0x82
    if b.len == 0usize { ret (out, Malformed) }
    var endp = b.len
    var i2 = 0usize
    var qpos = b.len - 1usize
    var kk = 0usize
    var more2 = true
    while more2 {
        endp -= 1usize
        i2 += 1usize
        kk = usize(b[qpos])
        if qpos < 1usize { ret (out, Malformed) }
        qpos -= 1usize
        more2 = i2 < 512usize && kk == 0usize
    }
    if i2 >= 512usize { ret (out, Malformed) }
    if kk != 130usize { ret (out, Malformed) }
    if endp < pos { ret (out, Malformed) }
    if (endp - pos) % offset != 0usize { ret (out, Malformed) }
    let nobs = (endp - pos) / offset
    // local offsets
    var ks = 0usize
    j = 0usize
    let pv = 128usize / tsz
    while j < n {
        if !isstr[j] {
            loc[j] = ithdb[j] * tsz + (ithdb[j] / pv) * 2usize
        } else {
            loc[j] = nd * tsz + (nd / pv) * 2usize + ithstr[j] * 12usize + ks * 2usize
            if stroff[ithstr[j]] != 0i64 { ks += 1usize }
        }
        j += 1usize
    }
    if mtype != 1i64 { ret (out, NotRectangular) }
    if nd + nk != n { ret (out, Malformed) }
    // names as as.data.frame makes them
    let (names, e7) = mem.alloc[str](a, n + 1usize)
    if e7 != ok { ret (out, e7) }
    j = 0usize
    while j < n {
        names[j] = lab[j]
        if to_df {
            let (nm, me) = make_name(a, lab[j])
            if me != ok { ret (out, me) }
            names[j] = nm
        }
        j += 1usize
    }
    if to_df {
        let ue = make_unique(a, names, n)
        if ue != ok { ret (out, ue) }
    }
    let (num, e8) = mem.alloc[f64](a, n * nobs + 1usize)
    let (sat, e9) = mem.alloc[usize](a, n * nobs + 1usize)
    let (slen, e10) = mem.alloc[usize](a, n * nobs + 1usize)
    let (sna, e11) = mem.alloc[bool](a, n * nobs + 1usize)
    let (sbuf, e12) = mem.alloc[u8](a, n * nobs * 12usize + 1usize)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (out, mem.Full) }
    var sused = 0usize
    j = 0usize
    while j < n {
        if !isstr[j] {
            var o = 0usize
            if nobs == 0usize {
                if !have(b, pos + loc[j] + 1usize, tsz) { ret (out, Malformed) }
            }
            while o < nobs {
                let at = pos + loc[j] + 1usize + o * offset
                if !have(b, at, tsz) { ret (out, Malformed) }
                var v = 0.0f64
                if tsz == 4usize {
                    let bits = u32(b[at]) | (u32(b[at + 1usize]) << 8u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 3usize]) << 24u32)
                    v = f64(mem.bitcast[f32](bits))
                } else {
                    var bits = 0u64
                    var t = 0usize
                    while t < 8usize {
                        bits = bits | (u64(b[at + t]) << u64(8usize * t))
                        t += 1usize
                    }
                    v = mem.bitcast[f64](bits)
                }
                if v == 0.0f64 - 1.0e36f64 { v = 0.0f64 / 0.0f64 }
                num[j * nobs + o] = v
                o += 1usize
            }
        } else {
            var o = 0usize
            while o < nobs {
                let at = pos + 1usize + offset * o + loc[j]
                let pb = stroff[ithstr[j]]
                // the C string: bytes up to the first NUL
                let start = sused
                var cut = false
                var cnt = 0usize
                if pb <= 0i64 {
                    if !have(b, at, 12usize) { ret (out, Malformed) }
                    var t = 0usize
                    while t < 12usize {
                        if b[at + t] == 0u8 { cut = true }
                        if !cut {
                            sbuf[sused] = b[at + t]
                            sused += 1usize
                            cnt += 1usize
                        }
                        t += 1usize
                    }
                } else {
                    let p1 = 12usize - usize(pb)
                    let p2 = usize(pb)
                    if !have(b, at, p1 + 2usize + p2) { ret (out, Malformed) }
                    var t = 0usize
                    while t < p1 {
                        if b[at + t] == 0u8 { cut = true }
                        if !cut {
                            sbuf[sused] = b[at + t]
                            sused += 1usize
                            cnt += 1usize
                        }
                        t += 1usize
                    }
                    // strcpy stops at a NUL of the first part; strcat then appends the second from that point
                    t = 0usize
                    var cut2 = false
                    while t < p2 {
                        if b[at + p1 + 2usize + t] == 0u8 { cut2 = true }
                        if !cut2 {
                            sbuf[sused] = b[at + p1 + 2usize + t]
                            sused += 1usize
                            cnt += 1usize
                        }
                        t += 1usize
                    }
                }
                var blank = cnt == 12usize
                var t2 = 0usize
                while blank && t2 < 12usize {
                    if sbuf[start + t2] != 32u8 { blank = false }
                    t2 += 1usize
                }
                sat[j * nobs + o] = start
                slen[j * nobs + o] = cnt
                sna[j * nobs + o] = blank
                o += 1usize
            }
        }
        j += 1usize
    }
    out.nv = n
    out.nobs = nobs
    out.isstr = isstr
    out.names = names
    out.num = num
    out.sat = sat
    out.slen = slen
    out.sna = sna
    out.sbuf = sbuf
    ret (out, ok)
}
