// Inline parsing for e.fmt.commonmark: code spans, emphasis, links, images, autolinks, raw HTML, entities,
// escapes, smart punctuation, and the GFM strikethrough and autolink extensions. A port of cmark-gfm's
// inlines.c with the extension hooks inlined (strikethrough.c, autolink.c); the same order of work, so the
// same tree, including the source positions.

use e.mem
use e.str
use e.fmt.commonmark_text as ct
use e.fmt.commonmark_tree as tr
use e.text.unicode as uni

type Subj = struct {
    input: str, pos: i32, line: i32, block_offset: i32, column_offset: i32, flags: u32,
    backticks: [81]i32, scanned_bt: bool, no_link_openers: bool
}

const FLAG_SKIP_CDATA: u32 = 1u32
const FLAG_SKIP_DECL: u32 = 2u32
const FLAG_SKIP_PI: u32 = 4u32
const FLAG_SKIP_COMMENT: u32 = 8u32


fn emdash() -> str { ret "\xe2\x80\x94" }
fn endash() -> str { ret "\xe2\x80\x93" }
fn ellipses() -> str { ret "\xe2\x80\xa6" }
fn ldq() -> str { ret "\xe2\x80\x9c" }
fn rdq() -> str { ret "\xe2\x80\x9d" }
fn lsq() -> str { ret "\xe2\x80\x98" }
fn rsq() -> str { ret "\xe2\x80\x99" }

fn ix(i: i32) -> usize { ret usize(i) }

// The byte at `i` of the subject, or 0 outside it.
fn at(s: *const Subj, i: i32) -> u8 {
    if i < 0i32 || ix(i) >= s.input.len { ret 0u8 }
    ret s.input[ix(i)]
}

fn peek(s: *const Subj) -> u8 { ret at(s, s.pos) }

fn peek_n(s: *const Subj, n: i32) -> u8 { ret at(s, s.pos + n) }

fn is_eof(s: *const Subj) -> bool { ret ix(s.pos) >= s.input.len }

fn slice(s: *const Subj, from: i32, len: i32) -> str {
    if len <= 0i32 { ret "" }
    ret s.input[ix(from)..ix(from + len)]
}

fn skip_spaces(s: *Subj) -> bool {
    var skipped = false
    while peek(s) == 32u8 || peek(s) == 9u8 {
        s.pos += 1i32
        skipped = true
    }
    ret skipped
}

fn skip_line_end(s: *Subj) -> bool {
    var seen = false
    if peek(s) == 13u8 {
        s.pos += 1i32
        seen = true
    }
    if peek(s) == 10u8 {
        s.pos += 1i32
        seen = true
    }
    ret seen || is_eof(s)
}

fn spnl(s: *Subj) {
    let _ = skip_spaces(s)
    if skip_line_end(s) {
        let _ = skip_spaces(s)
    }
}

fn trim_str(s: str) -> str {
    var a = 0usize
    var b = s.len
    while a < b && ct.is_space(s[a]) { a += 1usize }
    while b > a && ct.is_space(s[b - 1usize]) { b -= 1usize }
    ret s[a..b]
}

fn rtrim_str(s: str) -> str {
    var b = s.len
    while b > 0usize && ct.is_space(s[b - 1usize]) { b -= 1usize }
    ret s[0usize..b]
}

// --- Node makers.

fn make_literal(d: *tr.Doc, s: *const Subj, kind: u8, sc: i32, ec: i32, lit: str) -> i32 {
    let id = tr.new_node(d, kind)
    let n = ix(id)
    d.nodes[n].lit = lit
    d.nodes[n].sl = s.line
    d.nodes[n].el = s.line
    d.nodes[n].sc = sc + 1i32 + s.column_offset + s.block_offset
    d.nodes[n].ec = ec + 1i32 + s.column_offset + s.block_offset
    ret id
}

fn make_str(d: *tr.Doc, s: *const Subj, sc: i32, ec: i32, lit: str) -> i32 {
    ret make_literal(d, s, tr.K_TEXT, sc, ec, lit)
}

fn make_str_with_entities(d: *tr.Doc, s: *const Subj, sc: i32, ec: i32, content: str) -> i32 {
    var amp = false
    var i = 0usize
    while i < content.len {
        if content[i] == 38u8 { amp = true }
        i += 1usize
    }
    if !amp { ret make_str(d, s, sc, ec, content) }
    var b = ct.buf_new(d.a, content.len + 1usize)
    ct.unescape_html(&b, content)
    if b.failed { d.failed = true }
    ret make_str(d, s, sc, ec, ct.view(&b))
}

fn clean_url(d: *tr.Doc, url_in: str) -> str {
    let url = trim_str(url_in)
    if url.len == 0usize { ret "" }
    var b = ct.buf_new(d.a, url.len + 1usize)
    ct.unescape_html(&b, url)
    ct.unescape_backslashes(&b, 0usize)
    if b.failed { d.failed = true }
    ret ct.view(&b)
}

fn clean_title(d: *tr.Doc, title: str) -> str {
    if title.len == 0usize { ret "" }
    let first = title[0usize]
    let last = title[title.len - 1usize]
    var b = ct.buf_new(d.a, title.len + 1usize)
    if title.len >= 2usize && ((first == 39u8 && last == 39u8) || (first == 40u8 && last == 41u8) || (first == 34u8 && last == 34u8)) {
        ct.unescape_html(&b, title[1usize..title.len - 1usize])
    } else {
        ct.unescape_html(&b, title)
    }
    ct.unescape_backslashes(&b, 0usize)
    if b.failed { d.failed = true }
    ret ct.view(&b)
}

fn clean_autolink(d: *tr.Doc, url_in: str, is_email: bool) -> str {
    let url = trim_str(url_in)
    if url.len == 0usize { ret "" }
    var b = ct.buf_new(d.a, url.len + 8usize)
    if is_email { ct.put(&b, "mailto:") }
    ct.unescape_html(&b, url)
    if b.failed { d.failed = true }
    ret ct.view(&b)
}

fn make_autolink(d: *tr.Doc, s: *const Subj, sc: i32, ec: i32, url: str, is_email: bool) -> i32 {
    let link = tr.new_node(d, tr.K_LINK)
    let n = ix(link)
    d.nodes[n].url = clean_autolink(d, url, is_email)
    d.nodes[n].title = ""
    d.nodes[n].sl = s.line
    d.nodes[n].el = s.line
    d.nodes[n].sc = sc + 1i32
    d.nodes[n].ec = ec + 1i32
    let child = make_str_with_entities(d, s, sc + 1i32, ec - 1i32, url)
    tr.append_child(d, link, child)
    ret link
}

// --- Code spans.

fn count_newlines(s: *const Subj, from: i32, len: i32) -> (i32, i32) {
    var nls = 0i32
    var since = 0i32
    var i = 0i32
    while i < len {
        if at(s, from + i) == 10u8 {
            nls += 1i32
            since = 0i32
        } else {
            since += 1i32
        }
        i += 1i32
    }
    ret (nls, since)
}

fn adjust_newlines(d: *tr.Doc, s: *Subj, node: i32, matchlen: i32, extra: i32) {
    if !d.sourcepos { ret }
    let (nls, since) = count_newlines(s, s.pos - matchlen - extra, matchlen)
    if nls > 0i32 {
        s.line += nls
        d.nodes[ix(node)].el += nls
        d.nodes[ix(node)].ec = since
        s.column_offset = 0i32 - s.pos + since + extra
    }
}

fn scan_to_closing_backticks(s: *Subj, open_len: i32) -> i32 {
    if open_len > 80i32 { ret 0i32 }
    if s.scanned_bt && s.backticks[ix(open_len)] <= s.pos { ret 0i32 }
    while true {
        while peek(s) != 0u8 && peek(s) != 96u8 { s.pos += 1i32 }
        if is_eof(s) { break }
        var numticks = 0i32
        while peek(s) == 96u8 {
            s.pos += 1i32
            numticks += 1i32
        }
        if numticks <= 80i32 { s.backticks[ix(numticks)] = s.pos - numticks }
        if numticks == open_len { ret s.pos }
    }
    s.scanned_bt = true
    ret 0i32
}

fn normalize_code(d: *tr.Doc, raw: str) -> str {
    var b = ct.buf_new(d.a, raw.len + 1usize)
    var contains_nonspace = false
    var r = 0usize
    while r < raw.len {
        let c = raw[r]
        if c == 13u8 {
            if pk_str(raw, r + 1usize) != 10u8 { ct.putc(&b, 32u8) }
        } else {
            if c == 10u8 { ct.putc(&b, 32u8) } else { ct.putc(&b, c) }
        }
        if c != 32u8 && c != 10u8 && c != 13u8 { contains_nonspace = true }
        r += 1usize
    }
    if b.failed { d.failed = true }
    let w = ct.view(&b)
    if contains_nonspace && w.len >= 2usize && w[0usize] == 32u8 && w[w.len - 1usize] == 32u8 {
        ret w[1usize..w.len - 1usize]
    }
    ret w
}

fn pk_str(s: str, i: usize) -> u8 {
    if i >= s.len { ret 0u8 }
    ret s[i]
}

fn handle_backticks(d: *tr.Doc, s: *Subj) -> i32 {
    let start0 = s.pos
    while peek(s) == 96u8 { s.pos += 1i32 }
    let open_len = s.pos - start0
    let openticks = slice(s, start0, open_len)
    let startpos = s.pos
    let endpos = scan_to_closing_backticks(s, open_len)
    if endpos == 0i32 {
        s.pos = startpos
        ret make_str(d, s, s.pos, s.pos, openticks)
    }
    let raw = slice(s, startpos, endpos - startpos - open_len)
    let code = normalize_code(d, raw)
    let node = make_literal(d, s, tr.K_CODE, startpos, endpos - open_len - 1i32, code)
    adjust_newlines(d, s, node, endpos - startpos, open_len)
    ret node
}

// --- Delimiters and brackets.

fn skip_char(d: *const tr.Doc, c: u8) -> bool { ret d.x_strike && c == 126u8 }

// Flanking: answers (number of delimiters, can open, can close), and moves past them.
fn scan_delims(d: *const tr.Doc, s: *Subj, c: u8) -> (i32, bool, bool) {
    var before_char = 10u32
    var after_char = 10u32
    if s.pos != 0i32 {
        var bp = s.pos - 1i32
        while bp > 0i32 && ((at(s, bp) >> 6u8) == 2u8 || skip_char(d, at(s, bp))) { bp -= 1i32 }
        let (cp, w) = uni.read_utf8(s.input, ix(bp))
        before_char = cp
        if bp + i32(w) != s.pos { before_char = 10u32 }
        if before_char < 256u32 && skip_char(d, u8(before_char)) { before_char = 10u32 }
    }
    var numdelims = 0i32
    if c == 39u8 || c == 34u8 {
        numdelims = 1i32
        s.pos += 1i32
    } else {
        while peek(s) == c {
            numdelims += 1i32
            s.pos += 1i32
        }
    }
    if ix(s.pos) < s.input.len {
        var ap = s.pos
        while ix(ap) < s.input.len && skip_char(d, at(s, ap)) { ap += 1i32 }
        if ix(ap) < s.input.len {
            let (cp2, w2) = uni.read_utf8(s.input, ix(ap))
            after_char = cp2
            if ap + i32(w2) > i32(s.input.len) { after_char = 10u32 }
            if after_char < 256u32 && skip_char(d, u8(after_char)) { after_char = 10u32 }
        }
    }
    let sp_after = ct.is_uspace(after_char)
    let sp_before = ct.is_uspace(before_char)
    let pu_after = ct.is_upunct(after_char)
    let pu_before = ct.is_upunct(before_char)
    let left = numdelims > 0i32 && !sp_after && (!pu_after || sp_before || pu_before)
    let right = numdelims > 0i32 && !sp_before && (!pu_before || sp_after || pu_after)
    var can_open = left
    var can_close = right
    if c == 95u8 {
        can_open = left && (!right || pu_before)
        can_close = right && (!left || pu_after)
    } else {
        if c == 39u8 || c == 34u8 {
            can_open = left && !right && before_char != 93u32 && before_char != 41u32
            can_close = right
        }
    }
    ret (numdelims, can_open, can_close)
}

fn remove_delimiter(d: *tr.Doc, idx: i32) {
    if idx == tr.NIL { ret }
    let nx = d.delims[ix(idx)].next
    let pv = d.delims[ix(idx)].prev
    if nx == tr.NIL {
        d.last_delim = pv
    } else {
        d.delims[ix(nx)].prev = pv
    }
    if pv != tr.NIL { d.delims[ix(pv)].next = nx }
}

fn pop_bracket(d: *tr.Doc) {
    if d.last_bracket == tr.NIL { ret }
    d.last_bracket = d.brackets[ix(d.last_bracket)].prev
}

fn push_delimiter(d: *tr.Doc, s: *const Subj, c: u8, can_open: bool, can_close: bool, inl: i32) {
    if d.nd >= d.delims.len {
        var cap = d.delims.len * 2usize
        if cap < 32usize { cap = 32usize }
        let (t, e) = mem.alloc[tr.Delim](d.a, cap)
        if e != ok {
            d.failed = true
            ret
        }
        var i = 0usize
        while i < d.nd {
            t[i] = d.delims[i]
            i += 1usize
        }
        d.delims = t
    }
    let id = i32(d.nd)
    d.nd += 1usize
    var dl: tr.Delim = zero
    dl.ch = c
    dl.can_open = can_open
    dl.can_close = can_close
    dl.inl = inl
    dl.position = s.pos
    dl.length = i32(d.nodes[ix(inl)].lit.len)
    dl.prev = d.last_delim
    dl.next = tr.NIL
    d.delims[ix(id)] = dl
    if dl.prev != tr.NIL { d.delims[ix(dl.prev)].next = id }
    d.last_delim = id
}

fn push_bracket(d: *tr.Doc, s: *Subj, image: bool, inl: i32) {
    if d.nb >= d.brackets.len {
        var cap = d.brackets.len * 2usize
        if cap < 16usize { cap = 16usize }
        let (t, e) = mem.alloc[tr.Bracket](d.a, cap)
        if e != ok {
            d.failed = true
            ret
        }
        var i = 0usize
        while i < d.nb {
            t[i] = d.brackets[i]
            i += 1usize
        }
        d.brackets = t
    }
    let id = i32(d.nb)
    d.nb += 1usize
    var b: tr.Bracket = zero
    if d.last_bracket != tr.NIL {
        d.brackets[ix(d.last_bracket)].bracket_after = true
        b.in0 = d.brackets[ix(d.last_bracket)].in0
        b.in1 = d.brackets[ix(d.last_bracket)].in1
    }
    b.image = image
    b.active = true
    b.inl = inl
    b.prev = d.last_bracket
    b.position = s.pos
    b.bracket_after = false
    if image { b.in1 = true } else { b.in0 = true }
    d.brackets[ix(id)] = b
    d.last_bracket = id
    if !image { s.no_link_openers = false }
}

fn handle_delim(d: *tr.Doc, s: *Subj, c: u8) -> i32 {
    let (numdelims, can_open, can_close) = scan_delims(d, s, c)
    var contents = slice(s, s.pos - numdelims, numdelims)
    if c == 39u8 && d.smart {
        contents = rsq()
    } else {
        if c == 34u8 && d.smart {
            if can_close { contents = rdq() } else { contents = ldq() }
        }
    }
    let inl = make_str(d, s, s.pos - numdelims, s.pos - 1i32, contents)
    if (can_open || can_close) && (!(c == 39u8 || c == 34u8) || d.smart) {
        push_delimiter(d, s, c, can_open, can_close, inl)
    }
    ret inl
}

fn handle_hyphen(d: *tr.Doc, s: *Subj) -> i32 {
    let startpos = s.pos
    s.pos += 1i32
    if !d.smart || peek(s) != 45u8 { ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, "-") }
    while d.smart && peek(s) == 45u8 { s.pos += 1i32 }
    let numhyphens = s.pos - startpos
    var en_count = 0i32
    var em_count = 0i32
    if numhyphens % 3i32 == 0i32 {
        em_count = numhyphens / 3i32
    } else {
        if numhyphens % 2i32 == 0i32 {
            en_count = numhyphens / 2i32
        } else {
            if numhyphens % 3i32 == 2i32 {
                en_count = 1i32
                em_count = (numhyphens - 2i32) / 3i32
            } else {
                en_count = 2i32
                em_count = (numhyphens - 4i32) / 3i32
            }
        }
    }
    var b = ct.buf_new(d.a, 16usize)
    var i = 0i32
    while i < em_count {
        ct.put(&b, emdash())
        i += 1i32
    }
    i = 0i32
    while i < en_count {
        ct.put(&b, endash())
        i += 1i32
    }
    if b.failed { d.failed = true }
    ret make_str(d, s, startpos, s.pos - 1i32, ct.view(&b))
}

fn handle_period(d: *tr.Doc, s: *Subj) -> i32 {
    s.pos += 1i32
    if d.smart && peek(s) == 46u8 {
        s.pos += 1i32
        if peek(s) == 46u8 {
            s.pos += 1i32
            ret make_str(d, s, s.pos - 3i32, s.pos - 1i32, ellipses())
        }
        ret make_str(d, s, s.pos - 2i32, s.pos - 1i32, "..")
    }
    ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, ".")
}

// The extension that owns a delimiter character: only strikethrough does.
fn ext_delim(d: *const tr.Doc, c: u8) -> bool { ret d.x_strike && c == 126u8 }

fn insert_emph(d: *tr.Doc, opener: i32, closer: i32) -> i32 {
    let opener_inl = d.delims[ix(opener)].inl
    let closer_inl = d.delims[ix(closer)].inl
    var opener_num = i32(d.nodes[ix(opener_inl)].lit.len)
    var closer_num = i32(d.nodes[ix(closer_inl)].lit.len)
    var use_delims = 1i32
    if closer_num >= 2i32 && opener_num >= 2i32 { use_delims = 2i32 }
    opener_num -= use_delims
    closer_num -= use_delims
    d.nodes[ix(opener_inl)].lit = d.nodes[ix(opener_inl)].lit[0usize..ix(opener_num)]
    d.nodes[ix(closer_inl)].lit = d.nodes[ix(closer_inl)].lit[0usize..ix(closer_num)]
    var dl = d.delims[ix(closer)].prev
    while dl != tr.NIL && dl != opener {
        let t = d.delims[ix(dl)].prev
        remove_delimiter(d, dl)
        dl = t
    }
    var emph = 0i32
    if use_delims == 1i32 { emph = tr.new_node(d, tr.K_EMPH) } else { emph = tr.new_node(d, tr.K_STRONG) }
    var tmp = d.nodes[ix(opener_inl)].next
    while tmp != tr.NIL && tmp != closer_inl {
        let nx = d.nodes[ix(tmp)].next
        tr.unlink(d, tmp)
        tr.append_child(d, emph, tmp)
        tmp = nx
    }
    tr.insert_after(d, opener_inl, emph)
    d.nodes[ix(emph)].sl = d.nodes[ix(opener_inl)].sl
    d.nodes[ix(emph)].el = d.nodes[ix(closer_inl)].el
    d.nodes[ix(emph)].sc = d.nodes[ix(opener_inl)].sc
    d.nodes[ix(emph)].ec = d.nodes[ix(closer_inl)].ec
    if opener_num == 0i32 {
        tr.unlink(d, opener_inl)
        remove_delimiter(d, opener)
    }
    var res = closer
    if closer_num == 0i32 {
        tr.unlink(d, closer_inl)
        let t = d.delims[ix(closer)].next
        remove_delimiter(d, closer)
        res = t
    }
    ret res
}

// strikethrough.c insert: the opener's text node becomes the strikethrough node.
fn insert_strike(d: *tr.Doc, opener: i32, closer: i32) -> i32 {
    let res = d.delims[ix(closer)].next
    let st = d.delims[ix(opener)].inl
    let cl = d.delims[ix(closer)].inl
    if d.nodes[ix(st)].lit.len == d.nodes[ix(cl)].lit.len {
        let par = d.nodes[ix(st)].parent
        if par != tr.NIL && tr.can_contain(d, par, tr.K_STRIKE) {
            d.nodes[ix(st)].kind = tr.K_STRIKE
            var tmp = d.nodes[ix(st)].next
            while tmp != tr.NIL {
                if tmp == cl { break }
                let nx = d.nodes[ix(tmp)].next
                tr.unlink(d, tmp)
                tr.append_child(d, st, tmp)
                tmp = nx
            }
            d.nodes[ix(st)].ec = d.nodes[ix(cl)].sc + i32(d.nodes[ix(cl)].lit.len) - 1i32
            tr.unlink(d, cl)
        }
    }
    var dl = closer
    while dl != tr.NIL && dl != opener {
        let t = d.delims[ix(dl)].prev
        remove_delimiter(d, dl)
        dl = t
    }
    remove_delimiter(d, opener)
    ret res
}

fn process_emphasis(d: *tr.Doc, stack_bottom: i32) {
    var bottoms: [384]i32 = zero
    var k = 0usize
    while k < 3usize {
        bottoms[k * 128usize + 42usize] = stack_bottom
        bottoms[k * 128usize + 95usize] = stack_bottom
        bottoms[k * 128usize + 39usize] = stack_bottom
        bottoms[k * 128usize + 34usize] = stack_bottom
        k += 1usize
    }
    var closer = tr.NIL
    var candidate = d.last_delim
    while candidate != tr.NIL && d.delims[ix(candidate)].position >= stack_bottom {
        closer = candidate
        candidate = d.delims[ix(candidate)].prev
    }
    while closer != tr.NIL {
        let cdl = d.delims[ix(closer)]
        let is_ext = ext_delim(d, cdl.ch)
        var old_closer = closer
        var opener_found = false
        var opener = tr.NIL
        if cdl.can_close {
            opener = cdl.prev
            let bslot = ix(cdl.length % 3i32) * 128usize + usize(cdl.ch)
            while opener != tr.NIL && d.delims[ix(opener)].position >= stack_bottom && d.delims[ix(opener)].position >= bottoms[bslot] {
                let od = d.delims[ix(opener)]
                if od.can_open && od.ch == cdl.ch {
                    if !(cdl.can_open || od.can_close) || cdl.length % 3i32 == 0i32 || (od.length + cdl.length) % 3i32 != 0i32 {
                        opener_found = true
                        break
                    }
                }
                opener = od.prev
            }
            old_closer = closer
            if is_ext {
                if opener_found { closer = insert_strike(d, opener, closer) } else { closer = d.delims[ix(closer)].next }
            } else {
                if cdl.ch == 42u8 || cdl.ch == 95u8 {
                    if opener_found { closer = insert_emph(d, opener, closer) } else { closer = d.delims[ix(closer)].next }
                } else {
                    if cdl.ch == 39u8 || cdl.ch == 34u8 {
                        let cin = d.delims[ix(closer)].inl
                        if cdl.ch == 39u8 { d.nodes[ix(cin)].lit = rsq() } else { d.nodes[ix(cin)].lit = rdq() }
                        closer = d.delims[ix(closer)].next
                        if opener_found {
                            let oin = d.delims[ix(opener)].inl
                            if cdl.ch == 39u8 { d.nodes[ix(oin)].lit = lsq() } else { d.nodes[ix(oin)].lit = ldq() }
                            remove_delimiter(d, opener)
                            remove_delimiter(d, old_closer)
                        }
                    }
                }
            }
            if !opener_found {
                bottoms[ix(cdl.length % 3i32) * 128usize + usize(cdl.ch)] = cdl.position
                if !cdl.can_open { remove_delimiter(d, old_closer) }
            }
        } else {
            closer = d.delims[ix(closer)].next
        }
    }
    while d.last_delim != tr.NIL && d.delims[ix(d.last_delim)].position >= stack_bottom {
        remove_delimiter(d, d.last_delim)
    }
}

// --- Escapes, entities, raw HTML.

fn handle_backslash(d: *tr.Doc, s: *Subj) -> i32 {
    s.pos += 1i32
    let nextchar = peek(s)
    if ct.is_punct(nextchar) {
        s.pos += 1i32
        ret make_str(d, s, s.pos - 2i32, s.pos - 1i32, slice(s, s.pos - 1i32, 1i32))
    }
    if !is_eof(s) && skip_line_end(s) { ret tr.new_node(d, tr.K_LINEBREAK) }
    ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, "\\")
}

fn handle_entity(d: *tr.Doc, s: *Subj) -> i32 {
    s.pos += 1i32
    var b = ct.buf_new(d.a, 8usize)
    let n = ct.entity_at(s.input, ix(s.pos), &b)
    if b.failed { d.failed = true }
    if n == 0usize { ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, "&") }
    s.pos += i32(n)
    ret make_str(d, s, s.pos - 1i32 - i32(n), s.pos - 1i32, ct.view(&b))
}

fn handle_pointy_brace(d: *tr.Doc, s: *Subj) -> i32 {
    s.pos += 1i32
    var matchlen = i32(ct.scan_autolink_uri(s.input, ix(s.pos)))
    if matchlen > 0i32 {
        let contents = slice(s, s.pos, matchlen - 1i32)
        s.pos += matchlen
        ret make_autolink(d, s, s.pos - 1i32 - matchlen, s.pos - 1i32, contents, false)
    }
    matchlen = i32(ct.scan_autolink_email(s.input, ix(s.pos)))
    if matchlen > 0i32 {
        let contents = slice(s, s.pos, matchlen - 1i32)
        s.pos += matchlen
        ret make_autolink(d, s, s.pos - 1i32 - matchlen, s.pos - 1i32, contents, true)
    }
    let len = i32(s.input.len)
    if s.pos + 2i32 <= len {
        let c = at(s, s.pos)
        if c == 33u8 && (s.flags & FLAG_SKIP_COMMENT) == 0u32 {
            let c1 = at(s, s.pos + 1i32)
            if c1 == 45u8 && at(s, s.pos + 2i32) == 45u8 {
                if at(s, s.pos + 3i32) == 62u8 {
                    matchlen = 4i32
                } else {
                    if at(s, s.pos + 3i32) == 45u8 && at(s, s.pos + 4i32) == 62u8 {
                        matchlen = 5i32
                    } else {
                        matchlen = i32(ct.scan_html_comment(s.input, ix(s.pos + 1i32)))
                        if matchlen > 0i32 {
                            matchlen += 1i32
                        } else {
                            s.flags = s.flags | FLAG_SKIP_COMMENT
                        }
                    }
                }
            } else {
                if c1 == 91u8 {
                    if (s.flags & FLAG_SKIP_CDATA) == 0u32 {
                        matchlen = i32(ct.scan_html_cdata(s.input, ix(s.pos + 2i32)))
                        if matchlen > 0i32 {
                            matchlen += 5i32
                            if s.pos + matchlen > len {
                                s.flags = s.flags | FLAG_SKIP_CDATA
                                matchlen = 0i32
                            }
                        }
                    }
                } else {
                    if (s.flags & FLAG_SKIP_DECL) == 0u32 {
                        matchlen = i32(ct.scan_html_declaration(s.input, ix(s.pos + 1i32)))
                        if matchlen > 0i32 {
                            matchlen += 2i32
                            if s.pos + matchlen > len {
                                s.flags = s.flags | FLAG_SKIP_DECL
                                matchlen = 0i32
                            }
                        }
                    }
                }
            }
        } else {
            if c == 63u8 {
                if (s.flags & FLAG_SKIP_PI) == 0u32 {
                    matchlen = i32(ct.scan_html_pi(s.input, ix(s.pos + 1i32)))
                    matchlen += 3i32
                    if s.pos + matchlen > len {
                        s.flags = s.flags | FLAG_SKIP_PI
                        matchlen = 0i32
                    }
                }
            } else {
                matchlen = i32(ct.scan_html_tag(s.input, ix(s.pos)))
            }
        }
    }
    if matchlen > 0i32 {
        let contents = slice(s, s.pos - 1i32, matchlen + 1i32)
        s.pos += matchlen
        let node = make_literal(d, s, tr.K_HTML_INLINE, s.pos - matchlen - 1i32, s.pos - 1i32, contents)
        adjust_newlines(d, s, node, matchlen, 1i32)
        ret node
    }
    ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, "<")
}

// --- Links and images.

// A label starts at `[`; answers the raw label (trimmed) or fails and leaves the position alone.
fn link_label(s: *Subj) -> (str, bool) {
    let startpos = s.pos
    var length = 0i32
    if peek(s) == 91u8 { s.pos += 1i32 } else { ret ("", false) }
    var c = peek(s)
    while c != 0u8 && c != 91u8 && c != 93u8 {
        if c == 92u8 {
            s.pos += 1i32
            length += 1i32
            if ct.is_punct(peek(s)) {
                s.pos += 1i32
                length += 1i32
            }
        } else {
            s.pos += 1i32
            length += 1i32
        }
        if length > 1000i32 {
            s.pos = startpos
            ret ("", false)
        }
        c = peek(s)
    }
    if c == 93u8 {
        let raw = trim_str(slice(s, startpos + 1i32, s.pos - (startpos + 1i32)))
        s.pos += 1i32
        ret (raw, true)
    }
    s.pos = startpos
    ret ("", false)
}

// A link destination at `offset`: the length consumed or -1, and the destination text.
fn scan_link_url(s: *const Subj, offset: i32) -> (i32, str) {
    var i = offset
    let len = i32(s.input.len)
    if i < len && at(s, i) == 60u8 {
        i += 1i32
        while i < len {
            let c = at(s, i)
            if c == 62u8 {
                i += 1i32
                break
            } else {
                if c == 92u8 {
                    i += 2i32
                } else {
                    if c == 10u8 || c == 60u8 { ret (-1i32, "") }
                    i += 1i32
                }
            }
        }
        if i >= len { ret (-1i32, "") }
        ret (i - offset, slice(s, offset + 1i32, i - 2i32 - offset))
    }
    var nb_p = 0i32
    while i < len {
        let c = at(s, i)
        if c == 92u8 && i + 1i32 < len && ct.is_punct(at(s, i + 1i32)) {
            i += 2i32
        } else {
            if c == 40u8 {
                nb_p += 1i32
                i += 1i32
                if nb_p > 32i32 { ret (-1i32, "") }
            } else {
                if c == 41u8 {
                    if nb_p == 0i32 { break }
                    nb_p -= 1i32
                    i += 1i32
                } else {
                    if ct.is_space(c) {
                        if i == offset { ret (-1i32, "") }
                        break
                    }
                    i += 1i32
                }
            }
        }
    }
    if i >= len { ret (-1i32, "") }
    ret (i - offset, slice(s, offset, i - offset))
}

// Reference labels are compared case-folded with white space collapsed.
fn normalize_label(d: *tr.Doc, label: str) -> str {
    if label.len == 0usize { ret "" }
    let (folded, e) = uni.casefold(d.a, label)
    if e != ok {
        d.failed = true
        ret ""
    }
    var b = ct.buf_new(d.a, folded.len + 1usize)
    let t = trim_str(folded)
    var last_space = false
    var i = 0usize
    while i < t.len {
        if ct.is_space(t[i]) {
            if !last_space {
                ct.putc(&b, 32u8)
                last_space = true
            }
        } else {
            ct.putc(&b, t[i])
            last_space = false
        }
        i += 1usize
    }
    if b.failed { d.failed = true }
    ret ct.view(&b)
}

fn ref_find(d: *tr.Doc, label: str) -> i32 {
    let norm = normalize_label(d, label)
    if norm.len == 0usize { ret tr.NIL }
    var i = 0usize
    while i < d.nrefs {
        if str.eq(d.refs[i].label, norm) { ret i32(i) }
        i += 1usize
    }
    ret tr.NIL
}

fn ref_create(d: *tr.Doc, label: str, url: str, title: str) {
    let norm = normalize_label(d, label)
    if norm.len == 0usize { ret }
    if d.nrefs >= d.refs.len {
        var cap = d.refs.len * 2usize
        if cap < 16usize { cap = 16usize }
        let (t, e) = mem.alloc[tr.Ref](d.a, cap)
        if e != ok {
            d.failed = true
            ret
        }
        var i = 0usize
        while i < d.nrefs {
            t[i] = d.refs[i]
            i += 1usize
        }
        d.refs = t
    }
    var r: tr.Ref = zero
    r.label = norm
    r.url = clean_url(d, url)
    r.title = clean_title(d, title)
    d.refs[d.nrefs] = r
    d.nrefs += 1usize
}

fn handle_close_bracket(d: *tr.Doc, s: *Subj) -> i32 {
    s.pos += 1i32
    let initial_pos = s.pos
    let opener_idx = d.last_bracket
    if opener_idx == tr.NIL { ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, "]") }
    let opener = d.brackets[ix(opener_idx)]
    let is_image = opener.image
    if !is_image && s.no_link_openers {
        pop_bracket(d)
        ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, "]")
    }
    let after_link_text_pos = s.pos
    var matched = false
    var url = ""
    var title = ""
    if peek(s) == 40u8 {
        let sps = i32(ct.scan_spacechars(s.input, ix(s.pos + 1i32)))
        let (n, url_chunk) = scan_link_url(s, s.pos + 1i32 + sps)
        if n > -1i32 {
            let endurl = s.pos + 1i32 + sps + n
            let starttitle = endurl + i32(ct.scan_spacechars(s.input, ix(endurl)))
            var endtitle = starttitle
            if starttitle != endurl { endtitle = starttitle + i32(ct.scan_link_title(s.input, ix(starttitle))) }
            let endall = endtitle + i32(ct.scan_spacechars(s.input, ix(endtitle)))
            if at(s, endall) == 41u8 {
                s.pos = endall + 1i32
                let title_chunk = slice(s, starttitle, endtitle - starttitle)
                url = clean_url(d, url_chunk)
                title = clean_title(d, title_chunk)
                matched = true
            } else {
                s.pos = after_link_text_pos
            }
        }
    }
    if !matched {
        let (lab, found0) = link_label(s)
        var found_label = found0
        var raw_label = lab
        if !found_label { s.pos = initial_pos }
        if (!found_label || raw_label.len == 0usize) && !opener.bracket_after {
            raw_label = slice(s, opener.position, initial_pos - opener.position - 1i32)
            found_label = true
        }
        var rf = tr.NIL
        if found_label { rf = ref_find(d, raw_label) }
        if rf != tr.NIL {
            url = d.refs[ix(rf)].url
            title = d.refs[ix(rf)].title
            matched = true
        }
    }
    if !matched {
        pop_bracket(d)
        s.pos = initial_pos
        ret make_str(d, s, s.pos - 1i32, s.pos - 1i32, "]")
    }
    var kind = tr.K_LINK
    if is_image { kind = tr.K_IMAGE }
    let inl = tr.new_node(d, kind)
    d.nodes[ix(inl)].url = url
    d.nodes[ix(inl)].title = title
    d.nodes[ix(inl)].sl = s.line
    d.nodes[ix(inl)].el = s.line
    d.nodes[ix(inl)].sc = d.nodes[ix(opener.inl)].sc
    d.nodes[ix(inl)].ec = s.pos + s.column_offset + s.block_offset
    tr.insert_before(d, opener.inl, inl)
    var tmp = d.nodes[ix(opener.inl)].next
    while tmp != tr.NIL {
        let nx = d.nodes[ix(tmp)].next
        tr.unlink(d, tmp)
        tr.append_child(d, inl, tmp)
        tmp = nx
    }
    tr.unlink(d, opener.inl)
    process_emphasis(d, opener.position)
    pop_bracket(d)
    if !is_image { s.no_link_openers = true }
    ret tr.NIL
}

fn handle_newline(d: *tr.Doc, s: *Subj) -> i32 {
    let nlpos = s.pos
    if at(s, s.pos) == 13u8 { s.pos += 1i32 }
    if at(s, s.pos) == 10u8 { s.pos += 1i32 }
    s.line += 1i32
    s.column_offset = 0i32 - s.pos
    let _ = skip_spaces(s)
    if nlpos > 1i32 && at(s, nlpos - 1i32) == 32u8 && at(s, nlpos - 2i32) == 32u8 { ret tr.new_node(d, tr.K_LINEBREAK) }
    ret tr.new_node(d, tr.K_SOFTBREAK)
}

// --- Extension inlines: strikethrough and autolinks.

// Delimiter scanning for extensions (cmark_inline_parser_scan_delimiters): (count, left, right).
fn scan_ext_delims(s: *Subj, max_delims: i32, c: u8) -> (i32, bool, bool) {
    var before_char = 10u32
    var after_char = 10u32
    if s.pos != 0i32 {
        var bp = s.pos - 1i32
        while bp > 0i32 && (at(s, bp) >> 6u8) == 2u8 { bp -= 1i32 }
        let (cp, w) = uni.read_utf8(s.input, ix(bp))
        before_char = cp
        if bp + i32(w) != s.pos { before_char = 10u32 }
    }
    var numdelims = 0i32
    while peek(s) == c && numdelims < max_delims {
        numdelims += 1i32
        s.pos += 1i32
    }
    if ix(s.pos) < s.input.len {
        let (cp2, w2) = uni.read_utf8(s.input, ix(s.pos))
        after_char = cp2
        if ix(s.pos) + w2 > s.input.len { after_char = 10u32 }
    }
    let pu_before = ct.is_upunct(before_char)
    let pu_after = ct.is_upunct(after_char)
    let sp_before = ct.is_uspace(before_char)
    let sp_after = ct.is_uspace(after_char)
    let left = numdelims > 0i32 && !sp_after && !(pu_after && !sp_before && !pu_before)
    let right = numdelims > 0i32 && !sp_before && !(pu_before && !sp_after && !pu_after)
    ret (numdelims, left, right)
}

fn strike_match(d: *tr.Doc, s: *Subj) -> i32 {
    let (delims, left, right) = scan_ext_delims(s, 100i32, 126u8)
    let res = tr.new_node(d, tr.K_TEXT)
    d.nodes[ix(res)].lit = slice(s, s.pos - delims, delims)
    d.nodes[ix(res)].sl = s.line
    d.nodes[ix(res)].el = s.line
    d.nodes[ix(res)].sc = s.pos + 1i32 + s.column_offset + s.block_offset - delims
    if (left || right) && delims == 2i32 { push_delimiter(d, s, 126u8, left, right, res) }
    ret res
}

fn in_bracket(d: *const tr.Doc, image: bool) -> bool {
    if d.last_bracket == tr.NIL { ret false }
    if image { ret d.brackets[ix(d.last_bracket)].in1 }
    ret d.brackets[ix(d.last_bracket)].in0
}

fn is_valid_hostchar(s: str, at_: usize) -> bool {
    if at_ >= s.len { ret false }
    let (cp, w) = uni.read_utf8(s, at_)
    ret !ct.is_uspace(cp) && !ct.is_upunct(cp)
}

fn autolink_delim(data: str, link_end_in: usize) -> usize {
    var link_end = link_end_in
    var closing = 0usize
    var opening = 0usize
    var i = 0usize
    while i < link_end {
        let c = data[i]
        if c == 60u8 {
            link_end = i
            break
        } else {
            if c == 40u8 {
                opening += 1usize
            } else {
                if c == 41u8 { closing += 1usize }
            }
        }
        i += 1usize
    }
    while link_end > 0usize {
        let c = data[link_end - 1usize]
        if c == 41u8 {
            if closing <= opening { ret link_end }
            closing -= 1usize
            link_end -= 1usize
        } else {
            if c == 63u8 || c == 33u8 || c == 46u8 || c == 44u8 || c == 58u8 || c == 42u8 || c == 95u8 || c == 126u8 || c == 39u8 || c == 34u8 {
                link_end -= 1usize
            } else {
                if c == 59u8 {
                    var new_end = 0usize
                    if link_end >= 2usize { new_end = link_end - 2usize }
                    while new_end > 0usize && ct.is_alpha(data[new_end]) { new_end -= 1usize }
                    if link_end >= 2usize && new_end < link_end - 2usize && data[new_end] == 38u8 {
                        link_end = new_end
                    } else {
                        link_end -= 1usize
                    }
                } else {
                    ret link_end
                }
            }
        }
    }
    ret link_end
}

fn check_domain(data: str, allow_short: bool) -> usize {
    let size = data.len
    var np = 0usize
    var uscore1 = 0usize
    var uscore2 = 0usize
    var i = 1usize
    while i + 1usize < size {
        if data[i] == 92u8 && i + 2usize < size { i += 1usize }
        if data[i] == 95u8 {
            uscore2 += 1usize
        } else {
            if data[i] == 46u8 {
                uscore1 = uscore2
                uscore2 = 0usize
                np += 1usize
            } else {
                if !is_valid_hostchar(data, i) && data[i] != 45u8 { break }
            }
        }
        i += 1usize
    }
    if uscore1 > 0usize || uscore2 > 0usize {
        if np <= 10usize { ret 0usize }
    }
    if allow_short { ret i }
    if np > 0usize { ret i }
    ret 0usize
}

fn autolink_safe(link: str) -> bool {
    var k = 0usize
    while k < 3usize {
        var word = "http://"
        if k == 1usize { word = "https://" }
        if k == 2usize { word = "ftp://" }
        if link.len > word.len && ct.starts_with_fold(link, 0usize, word) && is_valid_hostchar(link, word.len) { ret true }
        k += 1usize
    }
    ret false
}

fn www_match(d: *tr.Doc, s: *Subj) -> i32 {
    let max_rewind = ix(s.pos)
    if max_rewind > s.input.len { ret tr.NIL }
    let data = s.input[max_rewind..s.input.len]
    let size = data.len
    let start = s.pos + 1i32 + s.column_offset + s.block_offset
    if max_rewind > 0usize {
        let pc = s.input[max_rewind - 1usize]
        if pc != 42u8 && pc != 95u8 && pc != 126u8 && pc != 40u8 && !ct.is_space(pc) { ret tr.NIL }
    }
    if size < 4usize || !str.starts_with(data, "www.") { ret tr.NIL }
    var link_end = check_domain(data, false)
    if link_end == 0usize { ret tr.NIL }
    while link_end < size && !ct.is_space(data[link_end]) && data[link_end] != 60u8 { link_end += 1usize }
    link_end = autolink_delim(data, link_end)
    if link_end == 0usize { ret tr.NIL }
    s.pos = i32(max_rewind + link_end)
    let node = tr.new_node(d, tr.K_LINK)
    var b = ct.buf_new(d.a, link_end + 8usize)
    ct.put(&b, "http://")
    ct.put(&b, data[0usize..link_end])
    if b.failed { d.failed = true }
    d.nodes[ix(node)].url = ct.view(&b)
    let text = tr.new_node(d, tr.K_TEXT)
    d.nodes[ix(text)].lit = data[0usize..link_end]
    tr.append_child(d, node, text)
    d.nodes[ix(node)].sl = s.line
    d.nodes[ix(node)].el = s.line
    d.nodes[ix(text)].sl = s.line
    d.nodes[ix(text)].el = s.line
    d.nodes[ix(node)].sc = start - 1i32
    d.nodes[ix(text)].sc = start - 1i32
    let ecol = s.pos + 1i32 + s.column_offset + s.block_offset - 1i32
    d.nodes[ix(node)].ec = ecol
    d.nodes[ix(text)].ec = ecol
    ret node
}

fn unput(d: *tr.Doc, parent: i32, n_in: usize) {
    var n = n_in
    var node = d.nodes[ix(parent)].last
    while n > 0usize && node != tr.NIL && d.nodes[ix(node)].kind == tr.K_TEXT {
        let l = d.nodes[ix(node)].lit.len
        if l < n {
            n -= l
            d.nodes[ix(node)].lit = ""
        } else {
            d.nodes[ix(node)].lit = d.nodes[ix(node)].lit[0usize..l - n]
            n = 0usize
        }
        node = d.nodes[ix(node)].prev
    }
}

fn url_match(d: *tr.Doc, s: *Subj, parent: i32) -> i32 {
    let max_rewind = ix(s.pos)
    if max_rewind > s.input.len { ret tr.NIL }
    let data = s.input[max_rewind..s.input.len]
    let size = data.len
    if size < 4usize || data[1usize] != 47u8 || data[2usize] != 47u8 { ret tr.NIL }
    var rewind = 0usize
    while rewind < max_rewind && ct.is_alpha(s.input[max_rewind - rewind - 1usize]) { rewind += 1usize }
    if !autolink_safe(s.input[max_rewind - rewind..s.input.len]) { ret tr.NIL }
    var link_end = 3usize
    let domain_len = check_domain(data[link_end..size], true)
    if domain_len == 0usize { ret tr.NIL }
    link_end += domain_len
    while link_end < size && !ct.is_space(data[link_end]) && data[link_end] != 60u8 { link_end += 1usize }
    link_end = autolink_delim(data, link_end)
    if link_end == 0usize { ret tr.NIL }
    s.pos = i32(max_rewind + link_end)
    unput(d, parent, rewind)
    let node = tr.new_node(d, tr.K_LINK)
    let url = s.input[max_rewind - rewind..max_rewind + link_end]
    d.nodes[ix(node)].url = url
    let text = tr.new_node(d, tr.K_TEXT)
    d.nodes[ix(text)].lit = url
    tr.append_child(d, node, text)
    d.nodes[ix(node)].sl = s.line
    d.nodes[ix(node)].el = s.line
    d.nodes[ix(text)].sl = s.line
    d.nodes[ix(text)].el = s.line
    d.nodes[ix(node)].sc = i32(max_rewind - rewind)
    d.nodes[ix(text)].sc = i32(max_rewind - rewind)
    let ecol = s.pos + 1i32 + s.column_offset + s.block_offset - 1i32
    d.nodes[ix(node)].ec = ecol
    d.nodes[ix(text)].ec = ecol
    ret node
}

// An inline an extension recognises at the current character, or none.
fn try_extensions(d: *tr.Doc, s: *Subj, parent: i32, c: u8) -> i32 {
    if d.x_strike && c == 126u8 { ret strike_match(d, s) }
    if d.x_autolink {
        if in_bracket(d, false) || in_bracket(d, true) { ret tr.NIL }
        if c == 58u8 { ret url_match(d, s, parent) }
        if c == 119u8 { ret www_match(d, s) }
    }
    ret tr.NIL
}

// --- The inline loop.

fn special_char(d: *const tr.Doc, c: u8) -> bool {
    if c == 10u8 || c == 13u8 || c == 92u8 || c == 96u8 || c == 38u8 || c == 95u8 || c == 42u8 || c == 91u8 || c == 93u8 || c == 60u8 || c == 33u8 { ret true }
    if d.smart && (c == 34u8 || c == 39u8 || c == 46u8 || c == 45u8) { ret true }
    if d.x_strike && c == 126u8 { ret true }
    if d.x_autolink && (c == 58u8 || c == 119u8) { ret true }
    ret false
}

fn find_special(d: *const tr.Doc, s: *const Subj) -> i32 {
    var n = s.pos + 1i32
    while ix(n) < s.input.len {
        if special_char(d, s.input[ix(n)]) { ret n }
        n += 1i32
    }
    ret i32(s.input.len)
}

fn parse_inline(d: *tr.Doc, s: *Subj, parent: i32) -> bool {
    let c = peek(s)
    if c == 0u8 { ret false }
    var new_inl = tr.NIL
    if c == 13u8 || c == 10u8 {
        new_inl = handle_newline(d, s)
    } else {
    if c == 96u8 {
        new_inl = handle_backticks(d, s)
    } else {
    if c == 92u8 {
        new_inl = handle_backslash(d, s)
    } else {
    if c == 38u8 {
        new_inl = handle_entity(d, s)
    } else {
    if c == 60u8 {
        new_inl = handle_pointy_brace(d, s)
    } else {
    if c == 42u8 || c == 95u8 || c == 39u8 || c == 34u8 {
        new_inl = handle_delim(d, s, c)
    } else {
    if c == 45u8 {
        new_inl = handle_hyphen(d, s)
    } else {
    if c == 46u8 {
        new_inl = handle_period(d, s)
    } else {
    if c == 91u8 {
        s.pos += 1i32
        new_inl = make_str(d, s, s.pos - 1i32, s.pos - 1i32, "[")
        push_bracket(d, s, false, new_inl)
    } else {
    if c == 93u8 {
        new_inl = handle_close_bracket(d, s)
    } else {
    if c == 33u8 {
        s.pos += 1i32
        if peek(s) == 91u8 && peek_n(s, 1i32) != 94u8 {
            s.pos += 1i32
            new_inl = make_str(d, s, s.pos - 2i32, s.pos - 1i32, "![")
            push_bracket(d, s, true, new_inl)
        } else {
            new_inl = make_str(d, s, s.pos - 1i32, s.pos - 1i32, "!")
        }
    } else {
        new_inl = try_extensions(d, s, parent, c)
        if new_inl == tr.NIL {
            let endpos = find_special(d, s)
            var contents = slice(s, s.pos, endpos - s.pos)
            let startpos = s.pos
            s.pos = endpos
            if ct.is_line_end(peek(s)) { contents = rtrim_str(contents) }
            new_inl = make_str(d, s, startpos, endpos - 1i32, contents)
        }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    if new_inl != tr.NIL { tr.append_child(d, parent, new_inl) }
    ret true
}

// Parses the pending content of `parent` into inline children.
fn parse_inlines(d: *tr.Doc, parent: i32) {
    var s: Subj = zero
    s.input = rtrim_str(tr.content(d, parent))
    s.line = d.nodes[ix(parent)].sl
    s.block_offset = d.nodes[ix(parent)].sc - 1i32 + d.nodes[ix(parent)].internal_off
    s.no_link_openers = true
    d.nd = 0usize
    d.nb = 0usize
    d.last_delim = tr.NIL
    d.last_bracket = tr.NIL
    while !is_eof(&s) && parse_inline(d, &s, parent) { }
    process_emphasis(d, 0i32)
    d.last_delim = tr.NIL
    d.last_bracket = tr.NIL
}

// Parses a link reference definition at the start of `input`; answers the bytes it covers, or 0.
fn parse_reference(d: *tr.Doc, input: str) -> usize {
    var s: Subj = zero
    s.input = input
    s.line = -1i32
    let (_, found) = link_label(&s)
    if !found { ret 0usize }
    let lab = trim_str(input[1usize..ix(s.pos) - 1usize])
    if lab.len == 0usize { ret 0usize }
    if peek(&s) == 58u8 { s.pos += 1i32 } else { ret 0usize }
    spnl(&s)
    let urlstart = ix(s.pos)
    let (matchlen, _) = scan_link_url(&s, s.pos)
    if matchlen > -1i32 { s.pos += matchlen } else { ret 0usize }
    var url = input[urlstart..urlstart + usize(matchlen)]
    if matchlen > 0i32 && input[urlstart] == 60u8 { url = input[urlstart + 1usize..urlstart + usize(matchlen) - 1usize] }
    let beforetitle = s.pos
    spnl(&s)
    var tlen = 0i32
    if s.pos != beforetitle { tlen = i32(ct.scan_link_title(input, ix(s.pos))) }
    var title = ""
    if tlen > 0i32 {
        title = input[ix(s.pos)..ix(s.pos) + usize(tlen)]
        s.pos += tlen
    } else {
        s.pos = beforetitle
    }
    let _ = skip_spaces(&s)
    if !skip_line_end(&s) {
        if tlen > 0i32 {
            s.pos = beforetitle
            let _ = skip_spaces(&s)
            if !skip_line_end(&s) { ret 0usize }
        } else {
            ret 0usize
        }
    }
    ref_create(d, lab, url, title)
    ret ix(s.pos)
}

// --- Autolink postprocessing (bare e-mail addresses in text).

fn validate_protocol(protocol: str, data: str, rewind: usize, max_rewind: usize, base: usize) -> bool {
    let len = protocol.len
    if len > max_rewind - rewind { ret false }
    let from = base - rewind - len
    var i = 0usize
    while i < len {
        if data[from + i] != protocol[i] { ret false }
        i += 1usize
    }
    if len == max_rewind - rewind { ret true }
    let prev = data[from - 1usize]
    ret !ct.is_alnum(prev)
}

fn postprocess_text(d: *tr.Doc, text_in: i32) {
    var text = text_in
    let detached = d.nodes[ix(text)].lit
    var start = 0usize
    var offset = 0usize
    var remaining = detached.len
    while true {
        if offset >= remaining { break }
        // memchr for '@'
        var at_pos = start + offset
        let stop = start + remaining
        while at_pos < stop && detached[at_pos] != 64u8 { at_pos += 1usize }
        if at_pos >= stop { break }
        var max_rewind = at_pos - (start + offset)
        var auto_mailto = true
        var is_xmpp = false
        var rewind = 0usize
        var link_end = 0usize
        var np = 0usize
        var restart = true
        while restart {
            restart = false
            rewind = 0usize
            while rewind < max_rewind {
                let c = detached[start + offset + max_rewind - rewind - 1usize]
                if ct.is_alnum(c) {
                    rewind += 1usize
                    continue
                }
                if c == 46u8 || c == 43u8 || c == 45u8 || c == 95u8 {
                    rewind += 1usize
                    continue
                }
                if c == 58u8 {
                    if validate_protocol("mailto:", detached, rewind, max_rewind, start + offset + max_rewind) {
                        auto_mailto = false
                        rewind += 1usize
                        continue
                    }
                    if validate_protocol("xmpp:", detached, rewind, max_rewind, start + offset + max_rewind) {
                        auto_mailto = false
                        is_xmpp = true
                        rewind += 1usize
                        continue
                    }
                }
                break
            }
            if rewind == 0usize { break }
            np = 0usize
            link_end = 1usize
            while link_end < remaining - offset - max_rewind {
                let c = detached[start + offset + max_rewind + link_end]
                if ct.is_alnum(c) {
                    link_end += 1usize
                    continue
                }
                if c == 64u8 {
                    offset += max_rewind + 1usize
                    max_rewind = link_end - 1usize
                    restart = true
                    break
                } else {
                    if c == 46u8 && link_end < remaining - offset - max_rewind - 1usize && ct.is_alnum(detached[start + offset + max_rewind + link_end + 1usize]) {
                        np += 1usize
                    } else {
                        if c == 47u8 && is_xmpp {
                            link_end += 1usize
                            continue
                        } else {
                            if c != 45u8 && c != 95u8 { break }
                        }
                    }
                }
                link_end += 1usize
            }
        }
        if rewind == 0usize {
            offset += max_rewind + 1usize
            continue
        }
        let lastc = detached[start + offset + max_rewind + link_end - 1usize]
        if link_end < 2usize || np == 0usize || (!ct.is_alpha(lastc) && lastc != 46u8) {
            offset += max_rewind + link_end
            continue
        }
        let base = start + offset + max_rewind
        link_end = autolink_delim(detached[base..start + remaining], link_end)
        if link_end == 0usize {
            offset += max_rewind + 1usize
            continue
        }
        let link_node = tr.new_node(d, tr.K_LINK)
        var b = ct.buf_new(d.a, link_end + rewind + 8usize)
        if auto_mailto { ct.put(&b, "mailto:") }
        ct.put(&b, detached[base - rewind..base + link_end])
        if b.failed { d.failed = true }
        d.nodes[ix(link_node)].url = ct.view(&b)
        let link_text = tr.new_node(d, tr.K_TEXT)
        d.nodes[ix(link_text)].lit = detached[base - rewind..base + link_end]
        tr.append_child(d, link_node, link_text)
        tr.insert_after(d, text, link_node)
        let post = tr.new_node(d, tr.K_TEXT)
        d.nodes[ix(post)].lit = detached[base + link_end..start + remaining]
        tr.insert_after(d, link_node, post)
        d.nodes[ix(text)].lit = detached[start..base - rewind]
        text = post
        start += offset + max_rewind + link_end
        remaining -= offset + max_rewind + link_end
        offset = 0usize
    }
}

fn autolink_postprocess(d: *tr.Doc) {
    tr.consolidate_text(d, d.root)
    var it = tr.iter_new(d.root)
    var in_link = false
    while tr.iter_next(d, &it) {
        let node = it.node
        if in_link {
            if !it.enter && d.nodes[ix(node)].kind == tr.K_LINK { in_link = false }
            continue
        }
        if it.enter && d.nodes[ix(node)].kind == tr.K_LINK {
            in_link = true
            continue
        }
        if it.enter && d.nodes[ix(node)].kind == tr.K_TEXT { postprocess_text(d, node) }
    }
}
