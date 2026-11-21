// R tm DocumentTermMatrix / TermDocumentMatrix construction from text (termFreq with the default whitespace tokeniser and the control
// options tolower, removePunctuation, removeNumbers, stopwords("english"), stemming ("english"), wordLengths and bounds$local, applied in
// a caller-chosen order), weightBin, and tidytext unnest_tokens for sentences and regex. ASCII text.
//
// Terms come back in byte order; tm sorts with the locale collation, which agrees on terms of lower-case letters and digits.

use e.algo.stat.tmstop as ts
use e.mem
use e.text.regex as rx
use e.str
use e.text.stem as stem

type Dtm = struct { nd: usize, nt: usize, terms: []str, counts: []f64 }

fn is_space(b: u8) -> bool { ret b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8 }

fn lower_byte(b: u8) -> u8 {
    if b >= 65u8 && b <= 90u8 { ret b + 32u8 }
    ret b
}

fn lower_str(a: *mem.Arena, s: str) -> (str, err) {
    let (bld, eb) = str.builder(a, s.len + 1usize)
    if eb != ok { ret ("", eb) }
    var bd = bld
    var i = 0usize
    while i < s.len {
        if str.push_byte(&bd, lower_byte(s[i])) != ok { ret ("", mem.Full) }
        i += 1usize
    }
    ret (str.done(&bd), ok)
}

fn remove_numbers(a: *mem.Arena, s: str) -> (str, err) {
    let (bld, eb) = str.builder(a, s.len + 1usize)
    if eb != ok { ret ("", eb) }
    var bd = bld
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 {
            if str.push_byte(&bd, s[i]) != ok { ret ("", mem.Full) }
        }
        i += 1usize
    }
    ret (str.done(&bd), ok)
}

// tm weightBin on a count matrix: every non-zero entry becomes 1
fn weight_bin(m: []const f64, out: []f64) {
    var i = 0usize
    while i < m.len {
        var v = 0.0f64
        if m[i] != 0.0f64 { v = 1.0f64 }
        out[i] = v
        i += 1usize
    }
}

// docs are separated by byte 1; ops lists the transformations in order (1 removePunctuation, 2 removeNumbers, 3 stopwords, 4 stemming)
fn dtm_build(a: *mem.Arena, text: str, lowercase: bool, ops: []const u8, wl_lo: usize, wl_hi: usize, bound_lo: f64, bound_hi: f64) -> (Dtm, err) {
    var empty: Dtm = zero
    var nd = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == 1u8 { nd += 1usize }
        i += 1usize
    }
    let cap = text.len + 2usize
    let (toks, e1) = mem.alloc[str](a, cap)
    let (docof, e2) = mem.alloc[usize](a, cap)
    if e1 != ok || e2 != ok { ret (empty, mem.Full) }
    var nk = 0usize
    var d = 0usize
    i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 1u8 || is_space(text[i]) {
            i += 1usize
            if i <= text.len && text[i - 1usize] == 1u8 { d += 1usize }
            continue
        }
        var j = i
        while j < text.len && text[j] != 1u8 && !is_space(text[j]) { j += 1usize }
        var t = text[i..j]
        var dropped = false
        if lowercase {
            let (lt, el) = lower_str(a, t)
            if el != ok { ret (empty, el) }
            t = lt
        }
        var k = 0usize
        while k < ops.len && !dropped {
            if ops[k] == 1u8 {
                let (r, er) = ts.remove_punctuation(a, t)
                if er != ok { ret (empty, er) }
                t = r
            }
            if ops[k] == 2u8 {
                let (r, er) = remove_numbers(a, t)
                if er != ok { ret (empty, er) }
                t = r
            }
            if ops[k] == 3u8 {
                if ts.is_stopword_en(t) { dropped = true }
            }
            if ops[k] == 4u8 {
                let (ob, eo) = mem.alloc[u8](a, t.len + 8usize)
                if eo != ok { ret (empty, eo) }
                let (r, er) = stem.snowball_exact(t, ob)
                if er != ok { ret (empty, er) }
                t = r
            }
            k += 1usize
        }
        if !dropped {
            toks[nk] = t
            docof[nk] = d
            nk += 1usize
        }
        i = j
    }
    // per-document counts, filtered by bounds and word length, over the distinct tokens
    let (counts, e3) = mem.alloc[f64](a, nk * nd + 1usize)
    let (terms, e4) = mem.alloc[str](a, nk + 1usize)
    if e3 != ok || e4 != ok { ret (empty, mem.Full) }
    var nt = 0usize
    var q = 0usize
    while q < nk {
        var seen = false
        var r = 0usize
        while r < q && !seen {
            if str.eq(toks[r], toks[q]) { seen = true }
            r += 1usize
        }
        if !seen {
            terms[nt] = toks[q]
            nt += 1usize
        }
        q += 1usize
    }
    // insertion sort of the distinct terms in byte order
    var x = 1usize
    while x < nt {
        let v = terms[x]
        var y = x
        while y > 0usize && str.compare(terms[y - 1usize], v) > 0i32 {
            terms[y] = terms[y - 1usize]
            y -= 1usize
        }
        terms[y] = v
        x += 1usize
    }
    let (full, e5) = mem.alloc[f64](a, nd * nt + 1usize)
    if e5 != ok { ret (empty, mem.Full) }
    var zi = 0usize
    while zi < nd * nt + 1usize {
        full[zi] = 0.0f64
        zi += 1usize
    }
    var z = 0usize
    while z < nk {
        var col = 0usize
        while !str.eq(terms[col], toks[z]) { col += 1usize }
        full[docof[z] * nt + col] += 1.0f64
        z += 1usize
    }
    // bounds and word lengths act per (document, term); a term nobody keeps leaves the matrix
    var keep_t = 0usize
    var c = 0usize
    while c < nt {
        var any = false
        var dd = 0usize
        while dd < nd {
            let v = full[dd * nt + c]
            if v > 0.0f64 && (v < bound_lo || v > bound_hi || terms[c].len < wl_lo || terms[c].len > wl_hi) { full[dd * nt + c] = 0.0f64 }
            if full[dd * nt + c] > 0.0f64 { any = true }
            dd += 1usize
        }
        if any {
            var dk = 0usize
            while dk < nd {
                counts[dk * nt + keep_t] = full[dk * nt + c]
                dk += 1usize
            }
            terms[keep_t] = terms[c]
            keep_t += 1usize
        }
        c += 1usize
    }
    // repack rows to the kept width
    var out_counts = counts
    var r2 = 0usize
    while r2 < nd {
        var c2 = 0usize
        while c2 < keep_t {
            out_counts[r2 * keep_t + c2] = counts[r2 * nt + c2]
            c2 += 1usize
        }
        r2 += 1usize
    }
    ret (Dtm { nd: nd, nt: keep_t, terms: terms[..keep_t], counts: out_counts[..nd * keep_t] }, ok)
}

fn is_close_byte(b: u8) -> bool { ret b == 34u8 || b == 39u8 || b == 40u8 || b == 41u8 || b == 91u8 || b == 93u8 || b == 123u8 || b == 125u8 }
fn is_sterm_byte(b: u8) -> bool { ret b == 33u8 || b == 63u8 }
fn is_scontinue_byte(b: u8) -> bool { ret b == 44u8 || b == 45u8 || b == 58u8 }
fn is_upper_byte(b: u8) -> bool { ret b >= 65u8 && b <= 90u8 }
fn is_lower_byte(b: u8) -> bool { ret b >= 97u8 && b <= 122u8 }
fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

// is there a sentence break after the terminator at i (UAX 29 SB6 to SB11 over ASCII), and where does the broken-off text end
fn sentence_end(s: str, i: usize) -> (usize, bool) {
    let aterm = s[i] == 46u8
    var j = i + 1usize
    if aterm && j < s.len && is_digit(s[j]) { ret (j, false) }
    if aterm && i > 0usize && j < s.len && (is_upper_byte(s[i - 1usize]) || is_lower_byte(s[i - 1usize])) && is_upper_byte(s[j]) { ret (j, false) }
    while j < s.len && is_close_byte(s[j]) { j += 1usize }
    while j < s.len && s[j] == 32u8 { j += 1usize }
    if j >= s.len { ret (j, true) }
    if is_scontinue_byte(s[j]) || s[j] == 46u8 || is_sterm_byte(s[j]) { ret (j, false) }
    if aterm {
        var k = j
        while k < s.len && !(is_upper_byte(s[k]) || is_lower_byte(s[k]) || s[k] == 46u8 || is_sterm_byte(s[k])) { k += 1usize }
        if k < s.len && is_lower_byte(s[k]) { ret (j, false) }
    }
    ret (j, true)
}

// tokenizers::tokenize_sentences, lower-cased (unnest_tokens(token = "sentences")): whitespace becomes a space, the text breaks per UAX 29,
// each sentence is trimmed; the sentences come back separated by byte 1
fn tokenize_sentences(a: *mem.Arena, s0: str) -> (str, err) {
    let (sb, e0) = str.builder(a, s0.len + 1usize)
    if e0 != ok { ret ("", e0) }
    var sbd = sb
    var q = 0usize
    while q < s0.len {
        var c = s0[q]
        if is_space(c) || c == 11u8 || c == 12u8 { c = 32u8 }
        if str.push_byte(&sbd, c) != ok { ret ("", mem.Full) }
        q += 1usize
    }
    let s = str.done(&sbd)
    let (bld, eb) = str.builder(a, s0.len * 2usize + 2usize)
    if eb != ok { ret ("", eb) }
    var bd = bld
    var first = true
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        var cut = false
        var next = i
        if i == s.len {
            cut = true
        } else if s[i] == 46u8 || is_sterm_byte(s[i]) {
            let (j, br) = sentence_end(s, i)
            if br {
                cut = true
                next = j
            }
        }
        if cut {
            var b = start
            var e = i
            if i < s.len { e = next }
            while b < e && s[b] == 32u8 { b += 1usize }
            while e > b && s[e - 1usize] == 32u8 { e -= 1usize }
            if e > b {
                if !first {
                    if str.push_byte(&bd, 1u8) != ok { ret ("", mem.Full) }
                }
                first = false
                var k = b
                while k < e {
                    if str.push_byte(&bd, lower_byte(s[k])) != ok { ret ("", mem.Full) }
                    k += 1usize
                }
            }
            start = e
            if i < s.len { start = next }
            if next > i { i = next } else { i += 1usize }
            continue
        }
        i += 1usize
    }
    ret (str.done(&bd), ok)
}

// tokenizers::tokenize_regex (stri_split_regex, empty pieces omitted), lower-cased; the pieces come back separated by byte 1
fn tokenize_regex(a: *mem.Arena, s: str, pattern: str) -> (str, err) {
    let (re, er) = rx.compile(a, pattern, rx.Options { case_insensitive: false, multiline: false, dot_matches_newline: true })
    if er != ok { ret ("", er) }
    let (bld, eb) = str.builder(a, s.len * 2usize + 2usize)
    if eb != ok { ret ("", eb) }
    var bd = bld
    var first = true
    var from = 0usize
    var pos = 0usize
    var going = true
    while going {
        var stop = s.len
        var nxt = s.len
        let (m, found) = rx.find(&re, s, pos)
        if found && m.end > m.start {
            stop = m.start
            nxt = m.end
        } else if found {
            // an empty match: step one byte so the search moves on
            pos += 1usize
            if pos > s.len { going = false }
            continue
        } else {
            going = false
        }
        if stop > from {
            if !first {
                if str.push_byte(&bd, 1u8) != ok { ret ("", mem.Full) }
            }
            first = false
            var k = from
            while k < stop {
                if str.push_byte(&bd, lower_byte(s[k])) != ok { ret ("", mem.Full) }
                k += 1usize
            }
        }
        from = nxt
        pos = nxt
        if pos > s.len { going = false }
    }
    ret (str.done(&bd), ok)
}
