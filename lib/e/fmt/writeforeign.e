// foreign::write.foreign for SPSS and Stata: the data file write.table writes and the code file that reads it back. A column is a double, an integer, a
// factor (plain or ordered), a character or a logical vector; a missing value is NaN in `values`. Names are taken as they are when abbreviate would leave them
// alone (32 characters or fewer, unique) and only ASCII is handled.
//
// Not here: write.foreign for SAS (its code file carries the deparsed call), dates and times, names that abbreviate() must shorten, and a variable whose
// name ends in "." followed by a variable with a double blank (strwrap would then add a blank).

use e.fmt.arff as arff
use e.mem
use e.str

// kind: 0 double, 1 factor, 2 character, 3 logical, 4 integer, 5 ordered factor. Column-major values (a factor holds its 1-based code, a character its
// text in txt[column * nrows + row]; NaN is NA); levels holds nlev[j] levels for each factor column in column order.
type Frame = struct { ncols: usize, nrows: usize, kind: []u8, nlev: []usize, levels: []str, values: []f64, txt: []str }

fn is_factor(k: u8) -> bool { ret k == 1u8 || k == 5u8 }

// write.table(quote = FALSE, sep = ","): a factor as its label, or its code when as_code; a double with up to 15 significant digits
fn table(a: *mem.Arena, f: *const Frame, as_code: bool, na: str, eol: str) -> (str, err) {
    let (sig, se) = mem.alloc[u8](a, 16usize)
    if se != ok { ret ("", se) }
    let (lbase, le) = mem.alloc[usize](a, f.ncols + 1usize)
    if le != ok { ret ("", le) }
    var acc = 0usize
    var j = 0usize
    while j < f.ncols {
        lbase[j] = acc
        acc += f.nlev[j]
        j += 1usize
    }
    let (b0, e0) = str.builder(a, 4096usize)
    if e0 != ok { ret ("", e0) }
    var b = b0
    var r = 0usize
    while r < f.nrows {
        j = 0usize
        while j < f.ncols {
            if j > 0usize { let _ = str.push_byte(&b, 44u8) }
            let v = f.values[j * f.nrows + r]
            let k = f.kind[j]
            if v != v {
                let _ = str.push(&b, na)
            } else if k == 0u8 {
                let pe = arff.push_r15(a, &b, sig, v)
                if pe != ok { ret ("", pe) }
            } else if k == 4u8 {
                let _ = str.push_i64(&b, i64(v))
            } else if k == 3u8 {
                if v != 0.0f64 { let _ = str.push(&b, "TRUE") } else { let _ = str.push(&b, "FALSE") }
            } else if k == 2u8 {
                let _ = str.push(&b, f.txt[j * f.nrows + r])
            } else if as_code {
                let _ = str.push_i64(&b, i64(v))
            } else {
                let _ = str.push(&b, f.levels[lbase[j] + usize(v) - 1usize])
            }
            j += 1usize
        }
        let _ = str.push(&b, eol)
        r += 1usize
    }
    ret (str.done(&b), ok)
}

// strwrap(text, width = 70) pasted with "\n" and written by cat: every line as " <line> \n"
fn push_wrapped(b: *str.Builder, text: str) {
    var linelen = 0usize
    var p = 0usize
    while p < text.len {
        while p < text.len && (text[p] == 32u8 || text[p] == 9u8 || text[p] == 10u8) { p += 1usize }
        var q = p
        while q < text.len && text[q] != 32u8 && text[q] != 9u8 && text[q] != 10u8 { q += 1usize }
        if q > p {
            let wl = q - p
            if linelen > 0usize && linelen + 1usize + wl > 69usize {
                let _ = str.push(b, " \n")
                linelen = 0usize
            }
            if linelen == 0usize {
                let _ = str.push_byte(b, 32u8)
            } else {
                let _ = str.push_byte(b, 32u8)
                linelen += 1usize
            }
            let _ = str.push(b, text[p..q])
            linelen += wl
        }
        p = q
    }
    if linelen > 0usize { let _ = str.push(b, " \n") }
}

fn alnum_like(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c == 36u8 || c == 64u8 || c == 35u8
}

fn quoted(b: *str.Builder, s: str) {
    let _ = str.push_byte(b, 34u8)
    let _ = str.push(b, s)
    let _ = str.push_byte(b, 34u8)
}

// the data file and the code file of writeForeignSPSS
fn spss(a: *mem.Arena, f: *const Frame, names: []const str, datafile: str) -> (str, str, err) {
    let (vs, e1) = mem.alloc[usize](a, f.ncols + 1usize)
    if e1 != ok { ret ("", "", e1) }
    let (ve, e2) = mem.alloc[usize](a, f.ncols + 1usize)
    if e2 != ok { ret ("", "", e2) }
    let (lbase, e3) = mem.alloc[usize](a, f.ncols + 1usize)
    if e3 != ok { ret ("", "", e3) }
    let (data, de) = table(a, f, true, "", ",\n")
    if de != ok { ret ("", "", de) }
    // the variable names with every character outside [A-Za-z0-9_$@#] turned into a point
    let (nb0, e4) = str.builder(a, 512usize)
    if e4 != ok { ret ("", "", e4) }
    var nb = nb0
    var j = 0usize
    var acc = 0usize
    while j < f.ncols {
        vs[j] = nb.len
        var i = 0usize
        while i < names[j].len {
            var c = names[j][i]
            if !alnum_like(c) { c = 46u8 }
            let _ = str.push_byte(&nb, c)
            i += 1usize
        }
        ve[j] = nb.len
        lbase[j] = acc
        acc += f.nlev[j]
        j += 1usize
    }
    let nbuf = str.done(&nb)
    // the DATA LIST names: a character as (A<width>), a factor as (F8.0), a star in front of a declared name after an undeclared one
    let (db0, e5) = str.builder(a, 512usize)
    if e5 != ok { ret ("", "", e5) }
    var db = db0
    j = 0usize
    while j < f.ncols {
        if j > 0usize { let _ = str.push_byte(&db, 32u8) }
        let declared = f.kind[j] == 2u8 || is_factor(f.kind[j])
        if declared && j > 0usize && f.kind[j - 1usize] != 2u8 && !is_factor(f.kind[j - 1usize]) { let _ = str.push(&db, "* ") }
        let _ = str.push(&db, nbuf[vs[j]..ve[j]])
        if f.kind[j] == 2u8 {
            var w = 8usize
            var r = 0usize
            while r < f.nrows {
                let v = f.values[j * f.nrows + r]
                if v == v && f.txt[j * f.nrows + r].len > w { w = f.txt[j * f.nrows + r].len }
                r += 1usize
            }
            let _ = str.push(&db, " (A")
            let _ = str.push_i64(&db, i64(w))
            let _ = str.push_byte(&db, 41u8)
        } else if declared {
            let _ = str.push(&db, " (F8.0)")
        }
        j += 1usize
    }
    let dltext = str.done(&db)
    // the ordinal and scale name lists, joined with ", "
    var any_ord = false
    var any_num = false
    j = 0usize
    while j < f.ncols {
        if f.kind[j] == 5u8 { any_ord = true }
        if f.kind[j] == 0u8 || f.kind[j] == 4u8 { any_num = true }
        j += 1usize
    }
    let (ob0, e6) = str.builder(a, 256usize)
    if e6 != ok { ret ("", "", e6) }
    var ob = ob0
    var first = true
    j = 0usize
    while j < f.ncols {
        if f.kind[j] == 5u8 {
            if !first { let _ = str.push(&ob, ", ") }
            first = false
            let _ = str.push(&ob, nbuf[vs[j]..ve[j]])
        }
        j += 1usize
    }
    let ordtext = str.done(&ob)
    let (sb0, e7) = str.builder(a, 256usize)
    if e7 != ok { ret ("", "", e7) }
    var sb = sb0
    first = true
    j = 0usize
    while j < f.ncols {
        if f.kind[j] == 0u8 || f.kind[j] == 4u8 {
            if !first { let _ = str.push(&sb, ", ") }
            first = false
            let _ = str.push(&sb, nbuf[vs[j]..ve[j]])
        }
        j += 1usize
    }
    let numtext = str.done(&sb)
    let (cb0, e8) = str.builder(a, 2048usize)
    if e8 != ok { ret ("", "", e8) }
    var c = cb0
    let _ = str.push(&c, "SET DECIMAL=DOT.\n\n")
    let _ = str.push(&c, "DATA LIST FILE= ")
    quoted(&c, datafile)
    let _ = str.push(&c, "  free (\",\")\n")
    let _ = str.push(&c, "ENCODING=\"UTF8\"\n")
    let _ = str.push(&c, "/")
    push_wrapped(&c, dltext)
    let _ = str.push(&c, "  .\n\n")
    let _ = str.push(&c, "VARIABLE LABELS\n")
    j = 0usize
    while j < f.ncols {
        if j > 0usize { let _ = str.push_byte(&c, 32u8) }
        let _ = str.push(&c, nbuf[vs[j]..ve[j]])
        let _ = str.push_byte(&c, 32u8)
        quoted(&c, names[j])
        let _ = str.push(&c, " \n")
        j += 1usize
    }
    let _ = str.push(&c, " .\n")
    var any_fac = false
    j = 0usize
    while j < f.ncols {
        if is_factor(f.kind[j]) { any_fac = true }
        j += 1usize
    }
    if any_fac {
        let _ = str.push(&c, "\nVALUE LABELS\n")
        j = 0usize
        while j < f.ncols {
            if is_factor(f.kind[j]) {
                let _ = str.push(&c, "/\n")
                let _ = str.push(&c, nbuf[vs[j]..ve[j]])
                let _ = str.push(&c, " \n")
                var l = 0usize
                while l < f.nlev[j] {
                    if l > 0usize { let _ = str.push_byte(&c, 32u8) }
                    let _ = str.push_i64(&c, i64(l + 1usize))
                    let _ = str.push_byte(&c, 32u8)
                    quoted(&c, f.levels[lbase[j] + l])
                    let _ = str.push(&c, " \n")
                    l += 1usize
                }
            }
            j += 1usize
        }
        let _ = str.push(&c, ".\n")
    }
    if any_ord {
        let _ = str.push(&c, "VARIABLE LEVEL")
        push_wrapped(&c, ordtext)
        let _ = str.push(&c, " (ordinal).\n")
    }
    if any_num {
        let _ = str.push(&c, "VARIABLE LEVEL")
        push_wrapped(&c, numtext)
        let _ = str.push(&c, " (scale).\n")
    }
    let _ = str.push(&c, "\nEXECUTE.\n")
    ret (data, str.done(&c), ok)
}

// the data file and the code file of writeForeignStata
fn stata(a: *mem.Arena, f: *const Frame, names: []const str, datafile: str) -> (str, str, err) {
    let (data, de) = table(a, f, false, ".", "\n")
    if de != ok { ret ("", "", de) }
    let (cb0, e1) = str.builder(a, 1024usize)
    if e1 != ok { ret ("", "", e1) }
    var c = cb0
    let _ = str.push(&c, "infile")
    var j = 0usize
    while j < f.ncols {
        let _ = str.push_byte(&c, 32u8)
        let _ = str.push(&c, names[j])
        if f.kind[j] == 2u8 || is_factor(f.kind[j]) {
            let _ = str.push_byte(&c, 58u8)
            let _ = str.push(&c, names[j])
            let _ = str.push(&c, "_fmt")
        }
        j += 1usize
    }
    let _ = str.push(&c, "  using  ")
    let _ = str.push(&c, datafile)
    let _ = str.push(&c, " , automatic\n")
    ret (data, str.done(&c), ok)
}
