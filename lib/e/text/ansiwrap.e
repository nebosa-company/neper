// R's `strwrap` over plain text, and the three cli functions that rest on it and on regular
// expressions: `ansi_strwrap` (R's line breaks mapped back onto the styled string, with form
// feeds, sentence-end double spaces, `indent` and `exdent`), `ansi_strsplit` (a regular
// expression or a fixed string, or "" for single characters) and `ansi_strtrim` (a width, with an
// ellipsis). Widths are cli's (e.text.ansi), which is what cli hands R's strwrap after its
// width workaround.
//
// Not here: `prefix` and `initial` of strwrap, `simplify` to a list of vectors other than by
// calling `ansi_strwrap_one` per element, `perl = TRUE` regular expressions for strsplit beyond
// what e.text.regex runs, NA elements.

use e.mem
use e.str
use e.text.ansi as ansi
use e.text.regex as re

error Unsupported

fn is_ws(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 }

fn one(a: *mem.Arena, s: str) -> ([]str, err) {
    let (v, e) = mem.alloc[str](a, 1usize)
    if e != ok { ret (v, e) }
    v[0usize] = s
    ret (v, ok)
}

fn strip1(a: *mem.Arena, s: str) -> (str, err) {
    let (v, e) = one(a, s)
    if e != ok { ret ("", e) }
    let (r, re2) = ansi.strip(a, v, true, true, true)
    if re2 != ok { ret ("", re2) }
    ret (r[0usize], ok)
}

fn width_of(s: str) -> i64 { ret ansi.display_width(s) }

// strsplit(x, "\n[ \t\n]*\n", perl = TRUE): the pieces; a trailing empty piece is not one.
fn split_paragraphs(a: *mem.Arena, x: str) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, x.len + 1usize)
    if e != ok { ret (out, e) }
    var n = 0usize
    var from = 0usize
    var i = 0usize
    while i < x.len {
        var matched = false
        if x[i] == 10u8 {
            var j = i + 1usize
            while j < x.len && is_ws(x[j]) { j += 1usize }
            var k = j
            while k > i + 1usize && !matched {
                k -= 1usize
                if x[k] == 10u8 { matched = true }
            }
            if matched {
                out[n] = x[from..i]
                n += 1usize
                from = k + 1usize
                i = from
            }
        }
        if !matched { i += 1usize }
    }
    if from < x.len {
        out[n] = x[from..x.len]
        n += 1usize
    }
    ret (out[0usize..n], ok)
}

// strsplit(x, "[ \t\n]", perl = TRUE).
fn split_words(a: *mem.Arena, x: str) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, x.len + 1usize)
    if e != ok { ret (out, e) }
    var n = 0usize
    var from = 0usize
    var i = 0usize
    while i < x.len {
        if is_ws(x[i]) {
            out[n] = x[from..i]
            n += 1usize
            from = i + 1usize
        }
        i += 1usize
    }
    if from < x.len {
        out[n] = x[from..x.len]
        n += 1usize
    }
    ret (out[0usize..n], ok)
}

// grep("[.?!][)\"']{0,1}$", word)
fn sentence_end(w: str) -> bool {
    if w.len == 0usize { ret false }
    let c = w[w.len - 1usize]
    if c == 46u8 || c == 63u8 || c == 33u8 { ret true }
    if (c == 41u8 || c == 34u8 || c == 39u8) && w.len >= 2usize {
        let p = w[w.len - 2usize]
        ret p == 46u8 || p == 63u8 || p == 33u8
    }
    ret false
}

fn spaces(a: *mem.Arena, n: i64) -> (str, err) {
    var m = n
    if m < 0i64 { m = 0i64 }
    let (initial, e) = str.builder(a, usize(m) + 1usize)
    if e != ok { ret ("", e) }
    var b = initial
    var i = 0i64
    while i < m {
        let _ = str.push_byte(&b, 32u8)
        i += 1i64
    }
    ret (str.done(&b), ok)
}

// base::strwrap(x, width, indent, exdent) for one string: the lines.
fn strwrap_one(a: *mem.Arena, x: str, width: i64, indent: i64, exdent: i64) -> ([]str, err) {
    let (pars, pe) = split_paragraphs(a, x)
    if pe != ok { ret (pars, pe) }
    let (lines, le) = mem.alloc[str](a, 2usize * x.len + 8usize)
    if le != ok { ret (lines, le) }
    var nl = 0usize
    let (indent_s, ie) = spaces(a, indent)
    let (exdent_s, xe) = spaces(a, exdent)
    if ie != ok { ret (lines, ie) }
    if xe != ok { ret (lines, xe) }
    var p = 0usize
    while p < pars.len {
        let (raw, we) = split_words(a, pars[p])
        if we != ok { ret (lines, we) }
        let (words, ne) = mem.alloc[str](a, raw.len + 1usize)
        let (nc, ce) = mem.alloc[i64](a, raw.len + 1usize)
        if ne != ok { ret (lines, ne) }
        if ce != ok { ret (lines, ce) }
        var n = 0usize
        var q = 0usize
        while q < raw.len {
            let w = raw[q]
            var keep = true
            if w.len == 0usize {
                keep = q > 0usize && sentence_end(raw[q - 1usize])
            }
            if keep {
                words[n] = w
                nc[n] = width_of(w)
                n += 1usize
            }
            q += 1usize
        }
        if n == 0usize {
            lines[nl] = ""
            lines[nl + 1usize] = ""
            nl += 2usize
        } else {
            let (lens, lne) = mem.alloc[i64](a, n)
            let (lower, lwe) = mem.alloc[i64](a, n + 1usize)
            let (upper, ue) = mem.alloc[i64](a, n + 1usize)
            if lne != ok { ret (lines, lne) }
            if lwe != ok { ret (lines, lwe) }
            if ue != ok { ret (lines, ue) }
            var total = 0i64
            var t = 0usize
            while t < n {
                total = total + nc[t] + 1i64
                lens[t] = total
                t += 1usize
            }
            var nb = 0usize
            lower[0usize] = 1i64
            var nlow = 1usize
            var first = true
            var max_length = width - indent
            var cur = 0usize
            while cur < n {
                var base = 0i64
                if cur > 0usize { base = lens[cur - 1usize] }
                var k = 0usize
                while cur + k < n && lens[cur + k] - base <= max_length { k += 1usize }
                if k < 1usize { k = 1usize }
                if first {
                    first = false
                    max_length = width - exdent
                }
                cur += k
                if nc[cur - 1usize] == 0i64 { upper[nb] = i64(cur) - 1i64 } else { upper[nb] = i64(cur) }
                nb += 1usize
                if cur < n {
                    if nc[cur] == 0i64 { cur += 1usize }
                    lower[nlow] = i64(cur) + 1i64
                    nlow += 1usize
                }
            }
            var blk = 0usize
            while blk < nb {
                let (initial, be) = str.builder(a, x.len + 16usize)
                if be != ok { ret (lines, be) }
                var b = initial
                if blk == 0usize { let _ = str.push(&b, indent_s) } else { let _ = str.push(&b, exdent_s) }
                var w = lower[blk]
                var firstw = true
                while w <= upper[blk] {
                    if !firstw { let _ = str.push_byte(&b, 32u8) }
                    firstw = false
                    let _ = str.push(&b, words[usize(w) - 1usize])
                    w += 1i64
                }
                lines[nl] = str.done(&b)
                nl += 1usize
                blk += 1usize
            }
            lines[nl] = ""
            nl += 1usize
        }
        p += 1usize
    }
    if nl == 0usize {
        lines[0usize] = ""
        ret (lines[0usize..1usize], ok)
    }
    ret (lines[0usize..nl - 1usize], ok)
}

// strwrap over a vector, simplified.
fn strwrap(a: *mem.Arena, x: []const str, width: i64, indent: i64, exdent: i64) -> ([]str, err) {
    var cap = 0usize
    var i = 0usize
    while i < x.len {
        cap += 2usize * x.len + x[i].len + 8usize
        i += 1usize
    }
    let (out, e) = mem.alloc[str](a, cap)
    if e != ok { ret (out, e) }
    var n = 0usize
    i = 0usize
    while i < x.len {
        let (ls, le) = strwrap_one(a, x[i], width, indent, exdent)
        if le != ok { ret (out, le) }
        var k = 0usize
        while k < ls.len {
            out[n] = ls[k]
            n += 1usize
            k += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// The three gsubs cli runs on a paragraph: a run of blanks becomes one space, except after
// . ! ? where a run of two or more becomes two spaces and a single blank becomes a space.
fn collapse_spaces(a: *mem.Arena, s: str) -> (str, err) {
    let (initial, e) = str.builder(a, s.len + 8usize)
    if e != ok { ret ("", e) }
    var b = initial
    var i = 0usize
    while i < s.len {
        if is_ws(s[i]) {
            var j = i
            while j < s.len && is_ws(s[j]) { j += 1usize }
            var after = false
            if i > 0usize {
                let c = s[i - 1usize]
                after = c == 46u8 || c == 33u8 || c == 63u8
            }
            if after && j - i >= 2usize {
                let _ = str.push(&b, "  ")
            } else {
                let _ = str.push_byte(&b, 32u8)
            }
            i = j
        } else {
            let _ = str.push_byte(&b, s[i])
            i += 1usize
        }
    }
    ret (str.done(&b), ok)
}

fn replace_ff(a: *mem.Arena, x: str, mark: str) -> (str, err) {
    let (initial, e) = str.builder(a, x.len + 16usize * (x.len + 1usize))
    if e != ok { ret ("", e) }
    var b = initial
    var i = 0usize
    while i < x.len {
        if x[i] == 12u8 {
            let _ = str.push(&b, "\n\n")
            let _ = str.push(&b, mark)
            let _ = str.push(&b, "\n\n")
        } else {
            let _ = str.push_byte(&b, x[i])
        }
        i += 1usize
    }
    ret (str.done(&b), ok)
}

// cli's fix_ff: the marker lines stand for form feeds.
fn fix_ff(a: *mem.Arena, x: []str, mark: str) -> ([]str, err) {
    let n = x.len
    let (xs, ce) = mem.alloc[str](a, n + 2usize)
    let (xv, ve) = mem.alloc[str](a, n + 2usize)
    let (drop, de) = mem.alloc[bool](a, n + 2usize)
    if ce != ok { ret (x, ce) }
    if ve != ok { ret (x, ve) }
    if de != ok { ret (x, de) }
    var any = false
    var i = 0usize
    while i < n {
        let (s, se) = strip1(a, x[i])
        if se != ok { ret (x, se) }
        xs[i] = s
        xv[i] = x[i]
        drop[i] = false
        if str.eq(s, mark) { any = true }
        i += 1usize
    }
    if !any { ret (x, ok) }
    // x <- x[-c(rem - 1, rem + 1)]
    i = 0usize
    while i < n {
        if str.eq(xs[i], mark) {
            if i > 0usize { drop[i - 1usize] = true }
            if i + 1usize < n { drop[i + 1usize] = true }
        }
        i += 1usize
    }
    let (ox, oe) = mem.alloc[str](a, n + 2usize)
    let (os2, ose) = mem.alloc[str](a, n + 2usize)
    if oe != ok { ret (x, oe) }
    if ose != ok { ret (x, ose) }
    var m = 0usize
    i = 0usize
    while i < n {
        if !drop[i] {
            ox[m] = xv[i]
            os2[m] = xs[i]
            m += 1usize
        }
        i += 1usize
    }
    if m > 0usize && str.eq(os2[m - 1usize], mark) {
        ox[m] = mark
        os2[m] = mark
        m += 1usize
    }
    var start = 0usize
    if m >= 2usize && ox[0usize].len == 0usize && str.eq(os2[1usize], mark) { start = 1usize }
    let (fx, fe) = mem.alloc[str](a, m + 1usize)
    if fe != ok { ret (x, fe) }
    var cnt = 0usize
    i = start
    while i < m {
        var del = false
        if i > start && str.eq(os2[i], mark) && !str.eq(os2[i - 1usize], mark) { del = true }
        if !del {
            if str.eq(os2[i], mark) { fx[cnt] = "" } else { fx[cnt] = ox[i] }
            cnt += 1usize
        }
        i += 1usize
    }
    ret (fx[0usize..cnt], ok)
}

fn decode(a: *mem.Arena, s: str) -> ([]i64, err) {
    let (out, e) = mem.alloc[i64](a, s.len + 1usize)
    if e != ok { ret (out, e) }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var cp = i64(c)
        var len = 1usize
        if c >= 240u8 {
            len = 4usize
            cp = i64(c & 7u8)
        } else if c >= 224u8 {
            len = 3usize
            cp = i64(c & 15u8)
        } else if c >= 192u8 {
            len = 2usize
            cp = i64(c & 31u8)
        }
        var k = 1usize
        while k < len && i + k < s.len {
            cp = cp * 64i64 + i64(s[i + k] & 63u8)
            k += 1usize
        }
        out[n] = cp
        n += 1usize
        i += len
    }
    ret (out[0usize..n], ok)
}

// cli's ansi_strwrap for one string.
fn ansi_strwrap_one(a: *mem.Arena, x0: str, width: i64, indent: i64, exdent: i64) -> ([]str, err) {
    let mark = "yShtnpteEk"
    let (x, re0) = replace_ff(a, x0, mark)
    if re0 != ok { ret (no_lines(), re0) }
    let (pars0, pe) = split_paragraphs(a, x)
    if pe != ok { ret (pars0, pe) }
    let (pars, te) = ansi.trimws(a, pars0, 0u8)
    if te != ok { ret (pars, te) }
    let (cols, ce) = mem.alloc[str](a, pars.len + 1usize)
    if ce != ok { ret (cols, ce) }
    var total = 0usize
    var i = 0usize
    while i < pars.len {
        let (c, ke) = collapse_spaces(a, pars[i])
        if ke != ok { ret (cols, ke) }
        cols[i] = c
        total += c.len + 2usize
        i += 1usize
    }
    let (joined, je) = str.builder(a, total + 4usize)
    if je != ok { ret (cols, je) }
    var jb = joined
    i = 0usize
    while i < pars.len {
        if i > 0usize { let _ = str.push(&jb, "\n\n") }
        let _ = str.push(&jb, cols[i])
        i += 1usize
    }
    let xx = str.done(&jb)
    let (xs, se) = strip1(a, xx)
    if se != ok { ret (no_lines(), se) }
    let (xw0, we) = strwrap_one(a, xs, width, indent, exdent)
    if we != ok { ret (xw0, we) }
    if str.eq(xs, xx) {
        let (fixed0, fe0) = fix_ff(a, xw0, mark)
        ret (fixed0, fe0)
    }

    // xw <- trimws(xw0, "left"); indent <- nchar(xw0) - nchar(xw)
    let (xw, xwe) = mem.alloc[[]i64](a, xw0.len + 1usize)
    let (lead, le) = mem.alloc[i64](a, xw0.len + 1usize)
    if xwe != ok { ret (xw0, xwe) }
    if le != ok { ret (xw0, le) }
    var l = 0usize
    while l < xw0.len {
        var f = 0usize
        while f < xw0[l].len && (xw0[l][f] == 32u8 || xw0[l][f] == 9u8 || xw0[l][f] == 13u8 || xw0[l][f] == 10u8) { f += 1usize }
        let (cp, de) = decode(a, xw0[l][f..xw0[l].len])
        if de != ok { ret (xw0, de) }
        xw[l] = cp
        lead[l] = i64(f)
        l += 1usize
    }
    let (xsc, xe) = decode(a, xs)
    if xe != ok { ret (xw0, xe) }
    let xslen = i64(xsc.len)
    let (splits, spe) = mem.alloc[i64](a, xsc.len + xw0.len + 4usize)
    let (dropped, dre) = mem.alloc[i64](a, xsc.len + 2usize)
    if spe != ok { ret (xw0, spe) }
    if dre != ok { ret (xw0, dre) }
    var nsplit = 1usize
    splits[0usize] = 1i64
    var ndrop = 0usize
    var xsidx = 1i64
    var line = 0usize
    var xwlen = 0i64
    if xw.len > 0usize { xwlen = i64(xw[0usize].len) }
    var col = 1i64
    while xsidx <= xslen {
        let xsc_c = xsc[usize(xsidx) - 1usize]
        var have = false
        var xwc = 0i64
        if line < xw.len && col >= 1i64 && col <= i64(xw[line].len) {
            have = true
            xwc = xw[line][usize(col) - 1usize]
        }
        if !have {
            xsidx += 1i64
        } else if xsc_c == xwc {
            xsidx += 1i64
            col += 1i64
        } else if xsc_c == 32i64 || xsc_c == 10i64 || xsc_c == 9i64 {
            dropped[ndrop] = xsidx
            ndrop += 1usize
            xsidx += 1i64
        } else if xwc == 32i64 {
            col += 1i64
        } else {
            ret (xw0, Unsupported)
        }
        while xsidx <= xslen && line < xw.len && col > xwlen {
            splits[nsplit] = xsidx
            nsplit += 1usize
            line += 1usize
            col = 1i64
            if line < xw.len { xwlen = i64(xw[line].len) }
        }
    }
    splits[nsplit] = xsidx
    nsplit += 1usize
    let (out, oe) = mem.alloc[str](a, nsplit)
    if oe != ok { ret (xw0, oe) }
    var n = 0usize
    var s = 0usize
    while s + 1usize < nsplit {
        var from = splits[s]
        let to = splits[s + 1usize] - 1i64
        var again = true
        while again {
            again = false
            var d = 0usize
            while d < ndrop {
                if dropped[d] == from { again = true }
                d += 1usize
            }
            if again { from += 1i64 }
        }
        let (xv, xve) = one(a, xx)
        let (fv, fve) = mem.alloc[i64](a, 1usize)
        let (tv, tve) = mem.alloc[i64](a, 1usize)
        if xve != ok { ret (xw0, xve) }
        if fve != ok { ret (xw0, fve) }
        if tve != ok { ret (xw0, tve) }
        fv[0usize] = from
        tv[0usize] = to
        let (piece, pe2) = ansi.substr(a, xv, fv, tv)
        if pe2 != ok { ret (xw0, pe2) }
        let (ind, ine) = spaces(a, lead[s])
        if ine != ok { ret (xw0, ine) }
        let (jb2, jbe) = str.builder(a, ind.len + piece[0usize].len + 1usize)
        if jbe != ok { ret (xw0, jbe) }
        var b2 = jb2
        let _ = str.push(&b2, ind)
        let _ = str.push(&b2, piece[0usize])
        out[n] = str.done(&b2)
        n += 1usize
        s += 1usize
    }
    let (fixed1, fe1) = fix_ff(a, out[0usize..n], mark)
    ret (fixed1, fe1)
}

fn no_lines() -> []str {
    var none: []str = zero
    ret none
}

// ansi_strwrap(x, simplify = TRUE): every element's lines in one vector.
fn ansi_strwrap(a: *mem.Arena, x: []const str, width: i64, indent: i64, exdent: i64) -> ([]str, err) {
    var cap = 0usize
    var i = 0usize
    while i < x.len {
        cap += 2usize * x[i].len + 8usize
        i += 1usize
    }
    let (out, e) = mem.alloc[str](a, cap)
    if e != ok { ret (out, e) }
    var n = 0usize
    i = 0usize
    while i < x.len {
        let (ls, le) = ansi_strwrap_one(a, x[i], width, indent, exdent)
        if le != ok { ret (out, le) }
        var k = 0usize
        while k < ls.len {
            out[n] = ls[k]
            n += 1usize
            k += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// --- ansi_strsplit

fn cp_index(s: str, byte: usize) -> i64 {
    var n = 0i64
    var i = 0usize
    while i < byte && i < s.len {
        if (s[i] & 192u8) != 128u8 { n += 1i64 }
        i += 1usize
    }
    ret n
}

fn next_boundary(s: str, at: usize) -> usize {
    var i = at + 1usize
    while i < s.len && (s[i] & 192u8) == 128u8 { i += 1usize }
    ret i
}

// ansi_strsplit(x, split, fixed): the styled pieces.
fn ansi_strsplit(a: *mem.Arena, x: str, split: str, fixed: bool) -> ([]str, err) {
    let (plain, pe) = strip1(a, x)
    if pe != ok { ret (no_lines(), pe) }
    let nchars = cp_index(plain, plain.len)
    // matches as (start, end) 1-based character positions, end = start + length - 1
    let (ms, me) = mem.alloc[i64](a, 2usize * (plain.len + 2usize))
    if me != ok { ret (no_lines(), me) }
    var nm = 0usize
    var pos = 0usize
    if split.len == 0usize {
        while pos < plain.len {
            let c = cp_index(plain, pos) + 1i64
            ms[2usize * nm] = c
            ms[2usize * nm + 1usize] = c - 1i64
            nm += 1usize
            pos = next_boundary(plain, pos)
        }
    } else if fixed {
        while pos + split.len <= plain.len {
            if str.eq(plain[pos..pos + split.len], split) {
                let c = cp_index(plain, pos) + 1i64
                ms[2usize * nm] = c
                ms[2usize * nm + 1usize] = c + cp_index(split, split.len) - 1i64
                nm += 1usize
                pos += split.len
            } else {
                pos = next_boundary(plain, pos)
            }
        }
    } else {
        let (rx, ce) = re.compile(a, split, re.Options { case_insensitive: false, multiline: false, dot_matches_newline: true })
        if ce != ok { ret (no_lines(), ce) }
        while pos <= plain.len {
            let (m, found) = re.find(&rx, plain, pos)
            if !found { break }
            let c = cp_index(plain, m.start) + 1i64
            let len = cp_index(plain[m.start..m.end], m.end - m.start)
            ms[2usize * nm] = c
            ms[2usize * nm + 1usize] = c + len - 1i64
            nm += 1usize
            if m.end > m.start { pos = m.end } else { pos = next_boundary(plain, m.end) }
            if m.end == plain.len && m.end == m.start { break }
        }
    }
    // the chunks between matches, and cli's two drops
    let (cs, cse) = mem.alloc[i64](a, 2usize * (nm + 2usize))
    if cse != ok { ret (no_lines(), cse) }
    var nc = 0usize
    if nm == 0usize {
        cs[0usize] = 1i64
        cs[1usize] = nchars
        nc = 1usize
    } else {
        var k = 0usize
        while k <= nm {
            var st = 1i64
            var en = nchars
            if k > 0usize { st = ms[2usize * (k - 1usize) + 1usize] + 1i64 }
            if k < nm { en = ms[2usize * k] - 1i64 }
            cs[2usize * nc] = st
            cs[2usize * nc + 1usize] = en
            nc += 1usize
            k += 1usize
        }
    }
    var first = 0usize
    var last = nc
    if nc > 0usize && split.len == 0usize && cs[1usize] - cs[0usize] + 1i64 == 0i64 { first = 1usize }
    if last > first && cs[2usize * (last - 1usize) + 1usize] - cs[2usize * (last - 1usize)] + 1i64 == 0i64 { last -= 1usize }
    if last <= first { ret (no_lines(), ok) }
    let (out, oe) = mem.alloc[str](a, last - first)
    if oe != ok { ret (no_lines(), oe) }
    var q = first
    while q < last {
        let (xv, xve) = one(a, x)
        let (fv, fve) = mem.alloc[i64](a, 1usize)
        let (tv, tve) = mem.alloc[i64](a, 1usize)
        if xve != ok { ret (out, xve) }
        if fve != ok { ret (out, fve) }
        if tve != ok { ret (out, tve) }
        fv[0usize] = cs[2usize * q]
        tv[0usize] = cs[2usize * q + 1usize]
        let (r, se) = ansi.substr(a, xv, fv, tv)
        if se != ok { ret (out, se) }
        out[q - first] = r[0usize]
        q += 1usize
    }
    ret (out, ok)
}

// --- ansi_strtrim

fn substr_to(a: *mem.Arena, x: str, last: i64) -> (str, err) {
    let (xv, xe) = one(a, x)
    let (fv, fe) = mem.alloc[i64](a, 1usize)
    let (tv, te) = mem.alloc[i64](a, 1usize)
    if xe != ok { ret ("", xe) }
    if fe != ok { ret ("", fe) }
    if te != ok { ret ("", te) }
    fv[0usize] = 1i64
    tv[0usize] = last
    let (r, e) = ansi.substr(a, xv, fv, tv)
    if e != ok { ret ("", e) }
    ret (r[0usize], ok)
}

fn nchar_of(a: *mem.Arena, x: str, typ: u8) -> (i64, err) {
    let (xv, xe) = one(a, x)
    if xe != ok { ret (0i64, xe) }
    let (r, e) = ansi.nchar(a, xv, typ)
    if e != ok { ret (0i64, e) }
    ret (r[0usize], ok)
}

fn concat(a: *mem.Arena, x: str, y: str) -> (str, err) {
    let (initial, e) = str.builder(a, x.len + y.len + 1usize)
    if e != ok { ret ("", e) }
    var b = initial
    let _ = str.push(&b, x)
    let _ = str.push(&b, y)
    ret (str.done(&b), ok)
}

// ansi_strtrim(x, width, ellipsis). Like cli, a vector shares the loop: once any element is too
// wide, every element wider than width - ellipsis is cut.
fn ansi_strtrim(a: *mem.Arena, x: []const str, width: i64, ellipsis: str) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, x.len)
    if e != ok { ret (out, e) }
    let (tw, tre) = nchar_of(a, ellipsis, 2u8)
    if tre != ok { ret (out, tre) }
    var i = 0usize
    if tw == width {
        while i < x.len {
            out[i] = ellipsis
            i += 1usize
        }
        ret (out, ok)
    }
    if tw > width {
        let (cut, ce) = ansi_strtrim_one(a, ellipsis, width)
        if ce != ok { ret (out, ce) }
        while i < x.len {
            out[i] = cut
            i += 1usize
        }
        ret (out, ok)
    }
    let (ps, pe) = strip1(a, ellipsis)
    if pe != ok { ret (out, pe) }
    let (bad, be) = mem.alloc[bool](a, x.len)
    let (bad0, b0e) = mem.alloc[bool](a, x.len)
    if be != ok { ret (out, be) }
    if b0e != ok { ret (out, b0e) }
    var any = false
    i = 0usize
    while i < x.len {
        let (cut, ce) = substr_to(a, x[i], width)
        if ce != ok { ret (out, ce) }
        out[i] = cut
        let (px, pxe) = strip1(a, x[i])
        if pxe != ok { ret (out, pxe) }
        let (pxt, pxte) = strip1(a, cut)
        if pxte != ok { ret (out, pxte) }
        let (wxt, wxe) = nchar_of(a, cut, 2u8)
        if wxe != ok { ret (out, wxe) }
        if ps.len > 0usize { bad[i] = !str.eq(pxt, px) || wxt > width } else { bad[i] = wxt > width }
        bad0[i] = bad[i]
        if bad[i] { any = true }
        i += 1usize
    }
    while any {
        i = 0usize
        while i < x.len {
            if bad[i] {
                let (n1, ne) = nchar_of(a, out[i], 0u8)
                if ne != ok { ret (out, ne) }
                let (shorter, se) = substr_to(a, out[i], n1 - 1i64)
                if se != ok { ret (out, se) }
                out[i] = shorter
            }
            i += 1usize
        }
        any = false
        i = 0usize
        while i < x.len {
            let (w2, w2e) = nchar_of(a, out[i], 2u8)
            if w2e != ok { ret (out, w2e) }
            bad[i] = w2 > width - tw
            if bad[i] { any = true }
            i += 1usize
        }
    }
    i = 0usize
    while i < x.len {
        if bad0[i] {
            let (c2, c2e) = concat(a, out[i], ellipsis)
            if c2e != ok { ret (out, c2e) }
            out[i] = c2
        }
        i += 1usize
    }
    ret (out, ok)
}

fn ansi_strtrim_one(a: *mem.Arena, x: str, width: i64) -> (str, err) {
    let (v, e) = one(a, x)
    if e != ok { ret ("", e) }
    let (r, re2) = ansi_strtrim(a, v, width, "")
    if re2 != ok { ret ("", re2) }
    ret (r[0usize], ok)
}
