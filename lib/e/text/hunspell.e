// Hunspell: spell checking over a MySpell/Hunspell dictionary pair (.aff and .dic text), a
// port of libhunspell as the R package `hunspell` ships it. `load` reads the pair, `spell`
// answers hunspell_check, `analyze` and `stem` answer hunspell_analyze and hunspell_stem,
// `suggest` answers hunspell_suggest, `find` and `find_format` answer hunspell_find (text, man,
// latex, xml and html parsers), `parse_tokens` answers hunspell_parse and `add_words` is the
// add_words of dictionary().
//
// What is ported: SET (UTF-8, the only encoding), FLAG char/long/num/UTF-8, AF and AM aliases,
// TRY, KEY, WORDCHARS, IGNORE, PFX and SFX with cross products, continuation flags and two-level
// suffixes, conditions, strip and morphological fields; REP, MAP, ICONV, OCONV, BREAK,
// NOSPLITSUGS, SUGSWITHDOTS, MAXNGRAMSUGS, MAXDIFF, ONLYMAXDIFF, FULLSTRIP, KEEPCASE,
// FORBIDDENWORD, NOSUGGEST, NEEDAFFIX, ONLYINCOMPOUND, WARN, FORBIDWARN, SUBSTANDARD,
// NONGRAMSUGGEST; compounding with COMPOUNDRULE, COMPOUNDFLAG, COMPOUNDBEGIN, COMPOUNDMIDDLE,
// COMPOUNDEND, COMPOUNDPERMITFLAG, COMPOUNDFORBIDFLAG, COMPOUNDROOT, COMPOUNDMIN,
// COMPOUNDWORDMAX, CHECKCOMPOUNDDUP, CHECKCOMPOUNDREP, CHECKCOMPOUNDTRIPLE, SIMPLIFIEDTRIPLE
// and CHECKCOMPOUNDCASE; the hash table keeps libhunspell's layout and walk order because the
// n-gram suggestion ties are decided by it. Not ported: CHECKCOMPOUNDPATTERN,
// COMPOUNDMORESUFFIXES, COMPOUNDSYLLABLE, FORCEUCASE, PHONE, morphological fields of the .dic
// (st:, ph:, po:), SET encodings other than UTF-8, LANG specific rules, CHECKSHARPS,
// COMPLEXPREFIXES, removing words, and code points above the BMP in case mapping (the case
// table covers ASCII, Latin-1, Latin Extended-A, Greek and Cyrillic). Suggestion time limits
// are not applied. Allocation failure aborts the process.

use e.mem
use e.os
use e.str
use e.data.list as list

error Invalid

const NOCAP: u8 = 0u8
const INITCAP: u8 = 1u8
const ALLCAP: u8 = 2u8
const HUHCAP: u8 = 3u8
const HUHINITCAP: u8 = 4u8

const IN_NOT: u8 = 0u8
const IN_BEGIN: u8 = 1u8
const IN_END: u8 = 2u8
const IN_OTHER: u8 = 3u8

const SP_COMPOUND: u32 = 1u32
const SP_FORBIDDEN: u32 = 2u32
const SP_INITCAP: u32 = 16u32
const SP_ORIGCAP: u32 = 32u32
const SP_WARN: u32 = 64u32

const ONLYUPCASE: u16 = 65535u16
const MAX_SUGS: usize = 15usize
const MAX_ROOTS: usize = 100usize
const MAX_GUESS: usize = 200usize
const MAX_WORDS: usize = 100usize

type Cond = struct { kind: u8, neg: bool, chars: []u32 }

type Aff = struct {
    pfx: bool,
    flag: u16,
    cross: bool,
    strip: str,
    appnd: str,
    key: str,
    conds: []Cond,
    numconds: usize,
    cont: []u16,
    morph: str,
}

type Entry = struct { word: str, flags: []u16, next: usize, homonym: usize, clen: usize, initcap: bool }

type Rep = struct { pattern: str, out: [4]str }

type Dict = struct {
    flag_mode: u8,
    try_chars: []u32,
    key: []u32,
    has_key: bool,
    wordchars: []u32,
    ignore: []u32,
    keepcase: u16,
    forbidden: u16,
    nosuggest: u16,
    needaffix: u16,
    onlyincompound: u16,
    warn: u16,
    substandard: u16,
    nongramsuggest: u16,
    forbidwarn: bool,
    nosplitsugs: bool,
    sugswithdots: bool,
    fullstrip: bool,
    onlymaxdiff: bool,
    aliasf: [][]u16,
    has_aliasf: bool,
    aliasm: []str,
    has_aliasm: bool,
    contflags: []u16,
    havecont: bool,
    cflag: u16,
    cbegin: u16,
    cmiddle: u16,
    cend: u16,
    cpermit: u16,
    cforbid: u16,
    croot: u16,
    cpdwordmax: i32,
    chk_dup: bool,
    chk_rep: bool,
    chk_triple: bool,
    simp_triple: bool,
    chk_case: bool,
    cpdmin: usize,
    maxngramsugs: i32,
    maxdiff: i32,
    maxcpdsugs: i32,
    rep: []Rep,
    iconv: []Rep,
    oconv: []Rep,
    has_iconv: bool,
    has_oconv: bool,
    maps: [][]str,
    breaks: []str,
    defcpd: [][]u16,
    affs: []Aff,
    pfx0: []usize,
    sfx0: []usize,
    pfx_sorted: []usize,
    sfx_sorted: []usize,
    pfx_from: []usize,
    sfx_from: []usize,
    table: []usize,
    entries: []Entry,
    ents: list.List[Entry],
    nentries: usize,
    lang_with_dash: bool,
}

type W = struct { a: *mem.Arena, d: *Dict, pfx: usize, sfx: usize }

// ---- allocation (a failure aborts) ----------------------------------------------------------

fn alloc[T: type](a: *mem.Arena, n: usize) -> []T {
    let (s, e) = mem.alloc[T](a, n)
    if e != ok { os.exit(5) }
    ret s
}

fn push_str(l: *list.List[str], v: str) {
    if list.push[str](l, v) != ok { os.exit(5) }
}

fn push_u32(l: *list.List[u32], v: u32) {
    if list.push[u32](l, v) != ok { os.exit(5) }
}

fn push_u16(l: *list.List[u16], v: u16) {
    if list.push[u16](l, v) != ok { os.exit(5) }
}

fn push_usize(l: *list.List[usize], v: usize) {
    if list.push[usize](l, v) != ok { os.exit(5) }
}

fn new_list[T: type](a: *mem.Arena) -> list.List[T] {
    let (l, e) = list.init[T](a, 8usize)
    if e != ok { os.exit(5) }
    ret l
}

// A byte buffer that grows by doubling.
type Buf = struct { items: []u8, len: usize, a: *mem.Arena }

fn buf_new(a: *mem.Arena) -> Buf {
    ret Buf { items: alloc[u8](a, 32usize), len: 0usize, a: a }
}

fn buf_reserve(b: *Buf, extra: usize) {
    if b.len + extra <= b.items.len { ret }
    var cap = b.items.len * 2usize
    if cap < b.len + extra { cap = b.len + extra }
    let fresh = alloc[u8](b.a, cap)
    var i = 0usize
    while i < b.len {
        fresh[i] = b.items[i]
        i += 1usize
    }
    b.items = fresh
}

fn buf_byte(b: *Buf, c: u8) {
    buf_reserve(b, 1usize)
    b.items[b.len] = c
    b.len += 1usize
}

fn buf_str(b: *Buf, s: str) {
    buf_reserve(b, s.len)
    var i = 0usize
    while i < s.len {
        b.items[b.len + i] = s[i]
        i += 1usize
    }
    b.len += s.len
}

fn buf_done(b: *Buf) -> str { ret b.items[..b.len] }

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    var b = buf_new(a)
    buf_str(&b, x)
    buf_str(&b, y)
    ret buf_done(&b)
}

fn same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// Is `needle` at `at` in `s`?
fn at_str(s: str, at: usize, needle: str) -> bool {
    if at + needle.len > s.len { ret false }
    var i = 0usize
    while i < needle.len {
        if s[at + i] != needle[i] { ret false }
        i += 1usize
    }
    ret true
}

fn find_str(s: str, needle: str, from: usize) -> usize {
    var i = from
    while i + needle.len <= s.len {
        if at_str(s, i, needle) { ret i }
        i += 1usize
    }
    ret s.len + 1usize
}

fn has_byte(s: str, c: u8) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] == c { ret true }
        i += 1usize
    }
    ret false
}

// strcmp on bytes: negative, zero, positive.
fn cmp_str(x: str, y: str) -> i32 {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] {
            if x[i] < y[i] { ret -1i32 }
            ret 1i32
        }
        i += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

fn copy_str(a: *mem.Arena, s: str) -> str {
    let out = alloc[u8](a, s.len)
    var i = 0usize
    while i < s.len {
        out[i] = s[i]
        i += 1usize
    }
    ret out
}

fn rev_bytes(a: *mem.Arena, s: str) -> str {
    let out = alloc[u8](a, s.len)
    var i = 0usize
    while i < s.len {
        out[i] = s[s.len - 1usize - i]
        i += 1usize
    }
    ret out
}

// ---- UTF-8 and case ---------------------------------------------------------------------------

fn cp_decode(a: *mem.Arena, s: str) -> []u32 {
    let out = alloc[u32](a, s.len)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = u32(s[i])
        var cp = c
        var width = 1usize
        if c >= 240u32 && i + 3usize < s.len {
            cp = ((c & 7u32) << 18u32) | ((u32(s[i + 1usize]) & 63u32) << 12u32) | ((u32(s[i + 2usize]) & 63u32) << 6u32) | (u32(s[i + 3usize]) & 63u32)
            width = 4usize
        } else if c >= 224u32 && i + 2usize < s.len {
            cp = ((c & 15u32) << 12u32) | ((u32(s[i + 1usize]) & 63u32) << 6u32) | (u32(s[i + 2usize]) & 63u32)
            width = 3usize
        } else if c >= 192u32 && i + 1usize < s.len {
            cp = ((c & 31u32) << 6u32) | (u32(s[i + 1usize]) & 63u32)
            width = 2usize
        }
        out[n] = cp
        n += 1usize
        i += width
    }
    ret out[..n]
}

fn cp_push(b: *Buf, cp: u32) {
    if cp < 128u32 {
        buf_byte(b, u8(cp))
    } else if cp < 2048u32 {
        buf_byte(b, u8(192u32 | (cp >> 6u32)))
        buf_byte(b, u8(128u32 | (cp & 63u32)))
    } else if cp < 65536u32 {
        buf_byte(b, u8(224u32 | (cp >> 12u32)))
        buf_byte(b, u8(128u32 | ((cp >> 6u32) & 63u32)))
        buf_byte(b, u8(128u32 | (cp & 63u32)))
    } else {
        buf_byte(b, u8(240u32 | (cp >> 18u32)))
        buf_byte(b, u8(128u32 | ((cp >> 12u32) & 63u32)))
        buf_byte(b, u8(128u32 | ((cp >> 6u32) & 63u32)))
        buf_byte(b, u8(128u32 | (cp & 63u32)))
    }
}

fn cp_encode(a: *mem.Arena, cps: []const u32) -> str {
    var b = buf_new(a)
    var i = 0usize
    while i < cps.len {
        cp_push(&b, cps[i])
        i += 1usize
    }
    ret buf_done(&b)
}

fn cp_lower(c: u32) -> u32 {
    if c < 128u32 {
        if c >= 65u32 && c <= 90u32 { ret c + 32u32 }
        ret c
    }
    if c >= 192u32 && c <= 222u32 && c != 215u32 { ret c + 32u32 }
    if c == 376u32 { ret 255u32 }
    if c >= 256u32 && c <= 311u32 && c != 304u32 && c != 305u32 {
        if (c & 1u32) == 0u32 { ret c + 1u32 }
        ret c
    }
    if c >= 313u32 && c <= 328u32 {
        if (c & 1u32) == 1u32 { ret c + 1u32 }
        ret c
    }
    if c >= 330u32 && c <= 375u32 {
        if (c & 1u32) == 0u32 { ret c + 1u32 }
        ret c
    }
    if c >= 377u32 && c <= 382u32 {
        if (c & 1u32) == 1u32 { ret c + 1u32 }
        ret c
    }
    if c >= 913u32 && c <= 939u32 && c != 930u32 { ret c + 32u32 }
    if c >= 1024u32 && c <= 1039u32 { ret c + 80u32 }
    if c >= 1040u32 && c <= 1071u32 { ret c + 32u32 }
    ret c
}

fn cp_upper(c: u32) -> u32 {
    if c < 128u32 {
        if c >= 97u32 && c <= 122u32 { ret c - 32u32 }
        ret c
    }
    if c >= 224u32 && c <= 254u32 && c != 247u32 { ret c - 32u32 }
    if c == 255u32 { ret 376u32 }
    if c >= 256u32 && c <= 311u32 && c != 304u32 && c != 305u32 {
        if (c & 1u32) == 1u32 { ret c - 1u32 }
        ret c
    }
    if c >= 313u32 && c <= 328u32 {
        if (c & 1u32) == 0u32 { ret c - 1u32 }
        ret c
    }
    if c >= 330u32 && c <= 375u32 {
        if (c & 1u32) == 1u32 { ret c - 1u32 }
        ret c
    }
    if c >= 377u32 && c <= 382u32 {
        if (c & 1u32) == 0u32 { ret c - 1u32 }
        ret c
    }
    if c >= 945u32 && c <= 971u32 && c != 962u32 { ret c - 32u32 }
    if c == 962u32 { ret 931u32 }
    if c >= 1104u32 && c <= 1119u32 { ret c - 80u32 }
    if c >= 1072u32 && c <= 1103u32 { ret c - 32u32 }
    ret c
}

fn cp_is_alpha(c: u32) -> bool {
    if c < 128u32 { ret (c >= 65u32 && c <= 90u32) || (c >= 97u32 && c <= 122u32) }
    if c == 170u32 || c == 181u32 || c == 186u32 { ret true }
    if c >= 192u32 && c <= 591u32 && c != 215u32 && c != 247u32 { ret true }
    if c >= 880u32 && c <= 1327u32 { ret true }
    if c >= 1488u32 && c <= 1514u32 { ret true }
    if c >= 1569u32 && c <= 1610u32 { ret true }
    ret false
}

fn all_small(cps: []u32) {
    var i = 0usize
    while i < cps.len {
        cps[i] = cp_lower(cps[i])
        i += 1usize
    }
}

fn all_cap(cps: []u32) {
    var i = 0usize
    while i < cps.len {
        cps[i] = cp_upper(cps[i])
        i += 1usize
    }
}

fn init_cap(cps: []u32) {
    if cps.len > 0usize { cps[0usize] = cp_upper(cps[0usize]) }
}

fn init_small(cps: []u32) {
    if cps.len > 0usize { cps[0usize] = cp_lower(cps[0usize]) }
}

fn str_small(a: *mem.Arena, s: str) -> str {
    let c = cp_decode(a, s)
    all_small(c)
    ret cp_encode(a, c)
}

fn str_cap(a: *mem.Arena, s: str) -> str {
    let c = cp_decode(a, s)
    all_cap(c)
    ret cp_encode(a, c)
}

fn str_initcap(a: *mem.Arena, s: str) -> str {
    let c = cp_decode(a, s)
    init_cap(c)
    ret cp_encode(a, c)
}

fn str_initsmall(a: *mem.Arena, s: str) -> str {
    let c = cp_decode(a, s)
    init_small(c)
    ret cp_encode(a, c)
}

fn captype(c: []const u32) -> u8 {
    var ncap = 0usize
    var nneutral = 0usize
    var i = 0usize
    while i < c.len {
        let low = cp_lower(c[i])
        if c[i] != low { ncap += 1usize }
        if cp_upper(c[i]) == low { nneutral += 1usize }
        i += 1usize
    }
    if ncap == 0usize { ret NOCAP }
    var firstcap = false
    if c[0usize] != cp_lower(c[0usize]) { firstcap = true }
    if ncap == 1usize && firstcap { ret INITCAP }
    if ncap == c.len || ncap + nneutral == c.len { ret ALLCAP }
    if ncap > 1usize && firstcap { ret HUHINITCAP }
    ret HUHCAP
}

fn cp_has(set: []const u32, c: u32) -> bool {
    var i = 0usize
    while i < set.len {
        if set[i] == c { ret true }
        i += 1usize
    }
    ret false
}

// ---- flags ---------------------------------------------------------------------------------

fn has_flag(flags: []const u16, f: u16) -> bool {
    if f == 0u16 { ret false }
    var i = 0usize
    while i < flags.len {
        if flags[i] == f { ret true }
        i += 1usize
    }
    ret false
}

fn atoi_str(s: str) -> i32 {
    var i = 0usize
    var neg = false
    while i < s.len && (s[i] == 32u8 || s[i] == 9u8) { i += 1usize }
    if i < s.len && (s[i] == 45u8 || s[i] == 43u8) {
        if s[i] == 45u8 { neg = true }
        i += 1usize
    }
    var v = 0i32
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        v = v * 10i32 + i32(s[i] - 48u8)
        i += 1usize
    }
    if neg { ret 0i32 - v }
    ret v
}

// FLAG_CHAR 0, FLAG_LONG 1, FLAG_NUM 2, FLAG_UNI 3
fn decode_flag(a: *mem.Arena, d: *Dict, f: str) -> u16 {
    if f.len == 0usize { ret 0u16 }
    if d.flag_mode == 1u8 {
        if f.len < 2usize { ret u16(f[0usize]) }
        ret u16((u32(f[0usize]) << 8u32) + u32(f[1usize]))
    }
    if d.flag_mode == 2u8 { ret u16(atoi_str(f)) }
    if d.flag_mode == 3u8 {
        let c = cp_decode(a, f)
        if c.len == 0usize { ret 0u16 }
        ret u16(c[0usize])
    }
    ret u16(f[0usize])
}

fn decode_flags(a: *mem.Arena, d: *Dict, f: str) -> []u16 {
    var out = new_list[u16](a)
    if f.len == 0usize { ret list.slice[u16](&out) }
    if d.flag_mode == 1u8 {
        var i = 0usize
        while i + 1usize < f.len {
            push_u16(&out, u16((u32(f[i]) << 8u32) + u32(f[i + 1usize])))
            i += 2usize
        }
    } else if d.flag_mode == 2u8 {
        var start = 0usize
        var i = 0usize
        while i <= f.len {
            if i == f.len || f[i] == 44u8 {
                push_u16(&out, u16(atoi_str(f[start..i])))
                start = i + 1usize
            }
            i += 1usize
        }
    } else if d.flag_mode == 3u8 {
        let c = cp_decode(a, f)
        var i = 0usize
        while i < c.len {
            push_u16(&out, u16(c[i]))
            i += 1usize
        }
    } else {
        var i = 0usize
        while i < f.len {
            push_u16(&out, u16(f[i]))
            i += 1usize
        }
    }
    ret list.slice[u16](&out)
}

fn sort_u16(v: []u16) {
    var i = 1usize
    while i < v.len {
        let x = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > x {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = x
        i += 1usize
    }
}

// ---- affix file and dictionary loading ---------------------------------------------------

fn is_sep(c: u8) -> bool { ret c == 32u8 || c == 9u8 }

// mystrsep: the pieces of a line separated by blanks and tabs.
fn pieces(a: *mem.Arena, line: str) -> []str {
    var out = new_list[str](a)
    var i = 0usize
    while i < line.len {
        while i < line.len && is_sep(line[i]) { i += 1usize }
        if i >= line.len { break }
        let start = i
        while i < line.len && !is_sep(line[i]) { i += 1usize }
        push_str(&out, line[start..i])
    }
    ret list.slice[str](&out)
}

// The offset just past the n-th piece of a line (n counts from 1), or the length.
fn piece_end(line: str, n: usize) -> usize {
    var i = 0usize
    var k = 0usize
    while i < line.len {
        while i < line.len && is_sep(line[i]) { i += 1usize }
        if i >= line.len { break }
        while i < line.len && !is_sep(line[i]) { i += 1usize }
        k += 1usize
        if k == n { ret i }
    }
    ret line.len
}

fn lines_of(a: *mem.Arena, text: str) -> []str {
    var out = new_list[str](a)
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 10u8 {
            if i == text.len && start == i { break }
            var end = i
            // mychomp: one CR or LF at the end, and a CR before a LF
            if end > start && text[end - 1usize] == 13u8 { end -= 1usize }
            push_str(&out, text[start..end])
            start = i + 1usize
        }
        i += 1usize
    }
    ret list.slice[str](&out)
}

fn begins(line: str, kw: str) -> bool { ret at_str(line, 0usize, kw) }

// One conv/rep table entry added in sorted position (RepList::add).
fn conv_add(a: *mem.Arena, l: *list.List[Rep], in_pat1: str, pat2: str) {
    if in_pat1.len == 0usize || pat2.len == 0usize { ret }
    var kind = 0usize
    var p1 = in_pat1
    if p1[0usize] == 95u8 {
        p1 = p1[1usize..]
        kind = 1usize
    }
    if p1.len > 0usize && p1[p1.len - 1usize] == 95u8 {
        kind += 2usize
        p1 = p1[..p1.len - 1usize]
    }
    p1 = underscores_to_space(a, p1)
    var i = 0usize
    while i < l.len {
        if same(l.items[i].pattern, p1) {
            l.items[i].out[kind] = underscores_to_space(a, pat2)
            ret
        }
        i += 1usize
    }
    var r: Rep = zero
    r.pattern = p1
    r.out[kind] = underscores_to_space(a, pat2)
    var at = l.len
    var at_found = false
    var j = 0usize
    while j < l.len {
        if !at_found && cmp_str(p1, l.items[j].pattern) < 0i32 {
            at = j
            at_found = true
        }
        j += 1usize
    }
    if list.insert[Rep](l, at, r) != ok { os.exit(5) }
}

fn underscores_to_space(a: *mem.Arena, s: str) -> str {
    let out = alloc[u8](a, s.len)
    var i = 0usize
    while i < s.len {
        out[i] = s[i]
        if s[i] == 95u8 { out[i] = 32u8 }
        i += 1usize
    }
    ret out
}

fn parse_cond(a: *mem.Arena, d: *Dict, text: str) -> ([]Cond, usize) {
    if same(text, ".") { ret (alloc[Cond](a, 0usize), 0usize) }
    let c = cp_decode(a, text)
    var out = new_list[Cond](a)
    var i = 0usize
    while i < c.len {
        var item: Cond = zero
        if c[i] == 91u32 {
            item.kind = 2u8
            i += 1usize
            if i < c.len && c[i] == 94u32 {
                item.neg = true
                i += 1usize
            }
            var set = new_list[u32](a)
            while i < c.len && c[i] != 93u32 {
                push_u32(&set, c[i])
                i += 1usize
            }
            item.chars = list.slice[u32](&set)
            i += 1usize
        } else if c[i] == 46u32 {
            item.kind = 1u8
            i += 1usize
        } else {
            item.kind = 0u8
            let one = alloc[u32](a, 1usize)
            one[0usize] = c[i]
            item.chars = one
            i += 1usize
        }
        if list.push[Cond](&out, item) != ok { os.exit(5) }
    }
    let conds = list.slice[Cond](&out)
    ret (conds, conds.len)
}

// Decode the code point starting at byte i; (code point, width).
fn cp_at(s: str, i: usize) -> (u32, usize) {
    let c = u32(s[i])
    if c >= 240u32 && i + 3usize < s.len {
        ret (((c & 7u32) << 18u32) | ((u32(s[i + 1usize]) & 63u32) << 12u32) | ((u32(s[i + 2usize]) & 63u32) << 6u32) | (u32(s[i + 3usize]) & 63u32), 4usize)
    }
    if c >= 224u32 && i + 2usize < s.len {
        ret (((c & 15u32) << 12u32) | ((u32(s[i + 1usize]) & 63u32) << 6u32) | (u32(s[i + 2usize]) & 63u32), 3usize)
    }
    if c >= 192u32 && i + 1usize < s.len {
        ret (((c & 31u32) << 6u32) | (u32(s[i + 1usize]) & 63u32), 2usize)
    }
    ret (c, 1usize)
}

// The start of the code point that ends just before byte `end`.
fn cp_start_before(s: str, end: usize) -> usize {
    var i = end - 1usize
    while i > 0usize && (s[i] & 192u8) == 128u8 { i -= 1usize }
    ret i
}

fn cond_item_matches(item: *const Cond, c: u32) -> bool {
    if item.kind == 1u8 { ret true }
    if item.kind == 0u8 { ret item.chars[0usize] == c }
    let found = cp_has(item.chars, c)
    if item.neg { ret !found }
    ret found
}

// Do the conditions hold at the start of `word` (a prefix)?
fn cond_prefix(af: *const Aff, word: str) -> bool {
    if af.conds.len == 0usize { ret true }
    var at = 0usize
    var k = 0usize
    while k < af.conds.len {
        if at >= word.len { ret false }
        let (c, width) = cp_at(word, at)
        if !cond_item_matches(&af.conds[k], c) { ret false }
        at += width
        k += 1usize
    }
    ret true
}

// Do the conditions hold at the end of `word` (a suffix)?
fn cond_suffix(af: *const Aff, word: str) -> bool {
    if af.conds.len == 0usize { ret true }
    var end = word.len
    var k = af.conds.len
    while k > 0usize {
        k -= 1usize
        if end == 0usize { ret false }
        let at = cp_start_before(word, end)
        let (c, width) = cp_at(word, at)
        if !cond_item_matches(&af.conds[k], c) { ret false }
        end = at
    }
    ret true
}

fn hash_word(d: *const Dict, word: str) -> usize {
    var hv = 0u32
    var i = 0usize
    while i < 4usize && i < word.len {
        hv = (hv << 8u32) | sign_ext(word[i])
        i += 1usize
    }
    while i < word.len {
        hv = (hv << 5u32) | ((hv >> 27u32) & 31u32)
        hv = hv ^ sign_ext(word[i])
        i += 1usize
    }
    ret usize(hv) % d.table.len
}

// A char read as a signed byte, widened to 32 bits.
fn sign_ext(b: u8) -> u32 {
    if b >= 128u8 { ret 4294967040u32 | u32(b) }
    ret u32(b)
}

fn lookup(d: *const Dict, word: str) -> usize {
    var e = d.table[hash_word(d, word)]
    while e != 0usize {
        if same(word, d.entries[e].word) { ret e }
        e = d.entries[e].next
    }
    ret 0usize
}

type Table = struct { entries: list.List[Entry] }

// HashMgr::add_word
fn add_word(a: *mem.Arena, d: *Dict, ents: *list.List[Entry], word: str, clen: usize, flags: []u16, onlyupcase: bool, cap: u8) {
    var upcasehomonym = false
    let hp = ents.len
    var ent: Entry = zero
    ent.word = word
    ent.flags = flags
    ent.clen = clen
    if cap == INITCAP { ent.initcap = true }
    if list.push[Entry](ents, ent) != ok { os.exit(5) }
    let slot = hash_word(d, word)
    var dp = d.table[slot]
    if dp == 0usize {
        d.table[slot] = hp
        ret
    }
    while ents.items[dp].next != 0usize {
        if ents.items[dp].homonym == 0usize && same(word, ents.items[dp].word) {
            if !onlyupcase {
                if has_flag(ents.items[dp].flags, ONLYUPCASE) {
                    ents.items[dp].flags = flags
                    ents.len -= 1usize
                    ret
                } else {
                    ents.items[dp].homonym = hp
                }
            } else {
                upcasehomonym = true
            }
        }
        dp = ents.items[dp].next
    }
    if same(word, ents.items[dp].word) {
        if !onlyupcase {
            if has_flag(ents.items[dp].flags, ONLYUPCASE) {
                ents.items[dp].flags = flags
                ents.len -= 1usize
                ret
            } else {
                ents.items[dp].homonym = hp
            }
        } else {
            upcasehomonym = true
        }
    }
    if !upcasehomonym {
        ents.items[dp].next = hp
    } else {
        ents.len -= 1usize
    }
}

fn str_has_ignored(d: *const Dict, s: str) -> bool {
    ret d.ignore.len > 0usize
}

fn strip_ignored(a: *mem.Arena, d: *const Dict, s: str) -> str {
    if d.ignore.len == 0usize { ret s }
    let c = cp_decode(a, s)
    var out = new_list[u32](a)
    var i = 0usize
    while i < c.len {
        if !cp_has(d.ignore, c[i]) { push_u32(&out, c[i]) }
        i += 1usize
    }
    ret cp_encode(a, list.slice[u32](&out))
}

// Load a dictionary pair from the text of its .aff and .dic files.
fn load(a: *mem.Arena, aff_text: str, dic_text: str) -> (Dict, err) {
    var d: Dict = zero
    d.cpdmin = 3usize
    d.cpdwordmax = -1i32
    d.maxngramsugs = -1i32
    d.maxdiff = -1i32
    d.maxcpdsugs = -1i32
    let lines = lines_of(a, aff_text)
    // first pass: FLAG (the affix flags of later lines depend on it)
    var li = 0usize
    while li < lines.len {
        let ln = lines[li]
        if begins(ln, "FLAG") && ln.len > 4usize && is_sep(ln[4usize]) {
            if str.contains(ln, "long") { d.flag_mode = 1u8 }
            if str.contains(ln, "num") { d.flag_mode = 2u8 }
            if str.contains(ln, "UTF-8") { d.flag_mode = 3u8 }
        }
        li += 1usize
    }
    // alias tables (AF flag vectors, AM morphological fields): later lines refer to them by number
    var aflist = new_list[[]u16](a)
    var amlist = new_list[str](a)
    li = 0usize
    while li < lines.len {
        let ln = lines[li]
        li += 1usize
        if begins(ln, "AF") && ln.len > 2usize && is_sep(ln[2usize]) && !d.has_aliasf {
            let pc = pieces(a, ln)
            d.has_aliasf = true
            var n = 0i32
            if pc.len >= 2usize { n = atoi_str(pc[1usize]) }
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                var fl = alloc[u16](a, 0usize)
                if tl.len >= 2usize {
                    fl = decode_flags(a, &d, tl[1usize])
                    sort_u16(fl)
                }
                if list.push[[]u16](&aflist, fl) != ok { os.exit(5) }
            }
        } else if begins(ln, "AM") && ln.len > 2usize && is_sep(ln[2usize]) && !d.has_aliasm {
            let pc = pieces(a, ln)
            d.has_aliasm = true
            var n = 0i32
            if pc.len >= 2usize { n = atoi_str(pc[1usize]) }
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                if tl.len >= 2usize {
                    push_str(&amlist, morph_rest_from(lines[li - 1usize], 1usize))
                } else {
                    push_str(&amlist, "")
                }
            }
        }
    }
    d.aliasf = list.slice[[]u16](&aflist)
    d.aliasm = list.slice[str](&amlist)
    var reps = new_list[Rep](a)
    var iconv = new_list[Rep](a)
    var oconv = new_list[Rep](a)
    var maps = new_list[[]str](a)
    var breaks = new_list[str](a)
    var defcpd = new_list[[]u16](a)
    var affs = new_list[Aff](a)
    var parsed_break = false
    li = 0usize
    while li < lines.len {
        var ln = lines[li]
        if li == 0usize && ln.len >= 3usize && ln[0usize] == 239u8 && ln[1usize] == 187u8 && ln[2usize] == 191u8 { ln = ln[3usize..] }
        li += 1usize
        let pc = pieces(a, ln)
        if begins(ln, "KEY") && pc.len >= 2usize {
            d.key = cp_decode(a, pc[1usize])
            d.has_key = true
        }
        if begins(ln, "TRY") && pc.len >= 2usize { d.try_chars = cp_decode(a, pc[1usize]) }
        if begins(ln, "WORDCHARS") && pc.len >= 2usize { d.wordchars = cp_decode(a, pc[1usize]) }
        if begins(ln, "IGNORE") && pc.len >= 2usize { d.ignore = cp_decode(a, pc[1usize]) }
        if begins(ln, "COMPOUNDMIN") && pc.len >= 2usize {
            var n = atoi_str(pc[1usize])
            if n < 1i32 { n = 1i32 }
            d.cpdmin = usize(n)
        }
        if begins(ln, "MAXNGRAMSUGS") && pc.len >= 2usize { d.maxngramsugs = atoi_str(pc[1usize]) }
        if begins(ln, "MAXDIFF") && pc.len >= 2usize { d.maxdiff = atoi_str(pc[1usize]) }
        if begins(ln, "MAXCPDSUGS") && pc.len >= 2usize { d.maxcpdsugs = atoi_str(pc[1usize]) }
        if begins(ln, "ONLYMAXDIFF") { d.onlymaxdiff = true }
        if begins(ln, "NOSPLITSUGS") { d.nosplitsugs = true }
        if begins(ln, "SUGSWITHDOTS") { d.sugswithdots = true }
        if begins(ln, "FULLSTRIP") { d.fullstrip = true }
        if begins(ln, "FORBIDWARN") { d.forbidwarn = true }
        if begins(ln, "KEEPCASE") && pc.len >= 2usize { d.keepcase = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "FORBIDDENWORD") && pc.len >= 2usize { d.forbidden = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "NOSUGGEST") && pc.len >= 2usize { d.nosuggest = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "NEEDAFFIX") && pc.len >= 2usize { d.needaffix = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "PSEUDOROOT") && pc.len >= 2usize { d.needaffix = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "ONLYINCOMPOUND") && pc.len >= 2usize { d.onlyincompound = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "WARN") && pc.len >= 2usize { d.warn = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "SUBSTANDARD") && pc.len >= 2usize { d.substandard = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "NONGRAMSUGGEST") && pc.len >= 2usize { d.nongramsuggest = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDFLAG") && pc.len >= 2usize { d.cflag = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDBEGIN") && pc.len >= 2usize { d.cbegin = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDMIDDLE") && pc.len >= 2usize { d.cmiddle = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDEND") && pc.len >= 2usize { d.cend = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDPERMITFLAG") && pc.len >= 2usize { d.cpermit = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDFORBIDFLAG") && pc.len >= 2usize { d.cforbid = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDROOT") && pc.len >= 2usize { d.croot = decode_flag(a, &d, pc[1usize]) }
        if begins(ln, "COMPOUNDWORDMAX") && pc.len >= 2usize { d.cpdwordmax = atoi_str(pc[1usize]) }
        if begins(ln, "CHECKCOMPOUNDDUP") { d.chk_dup = true }
        if begins(ln, "CHECKCOMPOUNDREP") { d.chk_rep = true }
        if begins(ln, "CHECKCOMPOUNDTRIPLE") { d.chk_triple = true }
        if begins(ln, "SIMPLIFIEDTRIPLE") { d.simp_triple = true }
        if begins(ln, "CHECKCOMPOUNDCASE") { d.chk_case = true }
        if begins(ln, "REP") && pc.len >= 2usize && reps.len == 0usize {
            let n = atoi_str(pc[1usize])
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                var r: Rep = zero
                var kind = 0usize
                if tl.len >= 2usize {
                    var pat = tl[1usize]
                    if pat.len > 0usize && pat[0usize] == 94u8 {
                        kind = 1usize
                        pat = pat[1usize..]
                    }
                    pat = underscores_to_space(a, pat)
                    if pat.len > 0usize && pat[pat.len - 1usize] == 36u8 {
                        kind += 2usize
                        pat = pat[..pat.len - 1usize]
                    }
                    r.pattern = pat
                    if tl.len >= 3usize { r.out[kind] = underscores_to_space(a, tl[2usize]) }
                }
                if list.push[Rep](&reps, r) != ok { os.exit(5) }
            }
        } else if begins(ln, "ICONV") && pc.len >= 2usize && iconv.len == 0usize {
            let n = atoi_str(pc[1usize])
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                if tl.len >= 3usize { conv_add(a, &iconv, tl[1usize], tl[2usize]) }
            }
            d.has_iconv = true
        } else if begins(ln, "OCONV") && pc.len >= 2usize && oconv.len == 0usize {
            let n = atoi_str(pc[1usize])
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                if tl.len >= 3usize { conv_add(a, &oconv, tl[1usize], tl[2usize]) }
            }
            d.has_oconv = true
        } else if begins(ln, "MAP") && pc.len >= 2usize {
            let n = atoi_str(pc[1usize])
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                var set = new_list[str](a)
                if tl.len >= 2usize {
                    let body = tl[1usize]
                    var k = 0usize
                    while k < body.len {
                        if body[k] == 40u8 {
                            var close = k + 1usize
                            while close < body.len && body[close] != 41u8 { close += 1usize }
                            if close < body.len {
                                push_str(&set, body[k + 1usize..close])
                                k = close + 1usize
                                continue
                            }
                        }
                        let (c0, width) = cp_at(body, k)
                        push_str(&set, body[k..k + width])
                        k += width
                    }
                }
                if list.push[[]str](&maps, list.slice[str](&set)) != ok { os.exit(5) }
            }
        } else if begins(ln, "BREAK") && pc.len >= 2usize && !parsed_break {
            parsed_break = true
            let n = atoi_str(pc[1usize])
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                if tl.len >= 2usize { push_str(&breaks, tl[1usize]) }
            }
        } else if begins(ln, "COMPOUNDRULE") && pc.len >= 2usize {
            let n = atoi_str(pc[1usize])
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                if tl.len >= 2usize {
                    var rule = new_list[u16](a)
                    let body = tl[1usize]
                    if has_byte(body, 40u8) {
                        // parenthesised flags: one chunk per character or per (group)
                        var k = 0usize
                        while k < body.len {
                            var chb = k
                            var che = k + 1usize
                            if body[k] == 40u8 {
                                var close = k + 1usize
                                while close < body.len && body[close] != 41u8 { close += 1usize }
                                if close < body.len {
                                    chb = k + 1usize
                                    che = close
                                    k = close
                                }
                            }
                            if chb < body.len && (body[chb] == 42u8 || body[chb] == 63u8) {
                                push_u16(&rule, u16(body[chb]))
                            } else {
                                let fl = decode_flags(a, &d, body[chb..che])
                                var q = 0usize
                                while q < fl.len {
                                    push_u16(&rule, fl[q])
                                    q += 1usize
                                }
                            }
                            k += 1usize
                        }
                    } else {
                        // the whole text is decoded as a flag vector of the dictionary's FLAG type
                        let fl = decode_flags(a, &d, body)
                        var q = 0usize
                        while q < fl.len {
                            push_u16(&rule, fl[q])
                            q += 1usize
                        }
                    }
                    if list.push[[]u16](&defcpd, list.slice[u16](&rule)) != ok { os.exit(5) }
                }
            }
        } else if (begins(ln, "PFX") || begins(ln, "SFX")) && pc.len >= 4usize {
            let is_pfx = begins(ln, "PFX")
            let flag = decode_flag(a, &d, pc[1usize])
            var cross = false
            if pc[2usize].len > 0usize && pc[2usize][0usize] == 89u8 { cross = true }
            let n = atoi_str(pc[3usize])
            var j = 0i32
            while j < n && li < lines.len {
                let tl = pieces(a, lines[li])
                li += 1usize
                j += 1i32
                if tl.len < 4usize { continue }
                var af: Aff = zero
                af.pfx = is_pfx
                af.flag = flag
                af.cross = cross
                var strip = tl[2usize]
                if same(strip, "0") { strip = "" }
                af.strip = strip
                var appnd = tl[3usize]
                var slash = appnd.len
                var q = 0usize
                while q < appnd.len {
                    if appnd[q] == 47u8 {
                        slash = q
                        break
                    }
                    q += 1usize
                }
                if slash < appnd.len {
                    if d.has_aliasf {
                        let idx = atoi_str(appnd[slash + 1usize..])
                        if idx >= 1i32 && usize(idx) <= d.aliasf.len { af.cont = d.aliasf[usize(idx) - 1usize] }
                    } else {
                        let cont = decode_flags(a, &d, appnd[slash + 1usize..])
                        sort_u16(cont)
                        af.cont = cont
                    }
                    appnd = appnd[..slash]
                }
                appnd = strip_ignored(a, &d, appnd)
                if same(appnd, "0") { appnd = "" }
                af.appnd = appnd
                if is_pfx {
                    af.key = appnd
                } else {
                    af.key = rev_bytes(a, appnd)
                }
                var cond = "."
                if tl.len >= 5usize { cond = tl[4usize] }
                let (conds, numconds) = parse_cond(a, &d, cond)
                af.conds = conds
                af.numconds = numconds
                if tl.len >= 6usize {
                    if d.has_aliasm {
                        let idx = atoi_str(tl[5usize])
                        if idx >= 1i32 && usize(idx) <= d.aliasm.len { af.morph = d.aliasm[usize(idx) - 1usize] }
                    } else {
                        af.morph = morph_rest(a, lines[li - 1usize])
                    }
                }
                if list.push[Aff](&affs, af) != ok { os.exit(5) }
            }
        }
    }
    if !parsed_break {
        push_str(&breaks, "-")
        push_str(&breaks, "^-")
        push_str(&breaks, "-$")
    }
    d.rep = list.slice[Rep](&reps)
    d.iconv = list.slice[Rep](&iconv)
    d.oconv = list.slice[Rep](&oconv)
    d.maps = list.slice[[]str](&maps)
    d.breaks = list.slice[str](&breaks)
    d.defcpd = list.slice[[]u16](&defcpd)
    d.affs = list.slice[Aff](&affs)
    var cf = new_list[u16](a)
    var ci = 0usize
    while ci < d.affs.len {
        var cj = 0usize
        while cj < d.affs[ci].cont.len {
            push_u16(&cf, d.affs[ci].cont[cj])
            d.havecont = true
            cj += 1usize
        }
        ci += 1usize
    }
    d.contflags = list.slice[u16](&cf)
    index_affixes(a, &d)
    d.lang_with_dash = has_cp(d.try_chars, 45u32) || has_cp(d.try_chars, 97u32)
    try load_dic(a, &d, dic_text)
    ret (d, ok)
}

fn has_cp(set: []const u32, c: u32) -> bool { ret cp_has(set, c) }

// The text of an affix line from its sixth piece on (the morphological field).
fn morph_rest(a: *mem.Arena, line: str) -> str { ret morph_rest_from(line, 5usize) }

// The rest of a line from its piece number `from` (counting from 0).
fn morph_rest_from(line: str, from: usize) -> str {
    var i = 0usize
    var k = 0usize
    while i < line.len {
        while i < line.len && is_sep(line[i]) { i += 1usize }
        if i >= line.len { break }
        if k == from { ret line[i..] }
        while i < line.len && !is_sep(line[i]) { i += 1usize }
        k += 1usize
    }
    ret ""
}

// The null-key lists and the key-sorted lists with their first-byte ranges
// (build_pfxtree / build_sfxtree / process_*_order, flattened).
fn index_affixes(a: *mem.Arena, d: *Dict) {
    var p0 = new_list[usize](a)
    var s0 = new_list[usize](a)
    var ps = new_list[usize](a)
    var ss = new_list[usize](a)
    var i = 0usize
    while i < d.affs.len {
        let af = &d.affs[i]
        if af.key.len == 0usize {
            // inserted at the head: the later definition comes first
            if af.pfx {
                if list.insert[usize](&p0, 0usize, i + 1usize) != ok { os.exit(5) }
            } else {
                if list.insert[usize](&s0, 0usize, i + 1usize) != ok { os.exit(5) }
            }
        } else {
            var dest_ix = &ss
            if af.pfx { dest_ix = &ps }
            // the new entry goes before the first one whose key is not smaller
            var at = dest_ix.len
            var j = 0usize
            while j < dest_ix.len {
                if cmp_str(af.key, d.affs[dest_ix.items[j] - 1usize].key) <= 0i32 {
                    at = j
                    break
                }
                j += 1usize
            }
            if list.insert[usize](dest_ix, at, i + 1usize) != ok { os.exit(5) }
        }
        i += 1usize
    }
    d.pfx0 = list.slice[usize](&p0)
    d.sfx0 = list.slice[usize](&s0)
    d.pfx_sorted = list.slice[usize](&ps)
    d.sfx_sorted = list.slice[usize](&ss)
    d.pfx_from = first_byte_ranges(a, d, d.pfx_sorted)
    d.sfx_from = first_byte_ranges(a, d, d.sfx_sorted)
}

fn first_byte_ranges(a: *mem.Arena, d: *const Dict, sorted: []const usize) -> []usize {
    let from = alloc[usize](a, 257usize)
    var b = 0usize
    while b <= 256usize {
        from[b] = sorted.len
        b += 1usize
    }
    var i = sorted.len
    while i > 0usize {
        i -= 1usize
        from[usize(d.affs[sorted[i] - 1usize].key[0usize])] = i
    }
    // fill the gaps so range [from[b], from[b+1]) works for every byte
    var k = 255usize
    while true {
        if from[k] > from[k + 1usize] { from[k] = from[k + 1usize] }
        if k == 0usize { break }
        k -= 1usize
    }
    ret from
}

fn load_dic(a: *mem.Arena, d: *Dict, text: str) -> err {
    let lines = lines_of(a, text)
    if lines.len == 0usize { ret Invalid }
    var first = lines[0usize]
    if first.len >= 3usize && first[0usize] == 239u8 && first[1usize] == 187u8 && first[2usize] == 191u8 { first = first[3usize..] }
    let count = atoi_str(first)
    if count <= 0i32 { ret Invalid }
    var size = usize(count) + 1005usize
    if (size % 2usize) == 0usize { size += 1usize }
    d.table = alloc[usize](a, size)
    var z = 0usize
    while z < size {
        d.table[z] = 0usize
        z += 1usize
    }
    var ents = new_list[Entry](a)
    var dummy: Entry = zero
    if list.push[Entry](&ents, dummy) != ok { os.exit(5) }
    var li = 1usize
    while li < lines.len {
        var ts = lines[li]
        li += 1usize
        // a morphological field starts at a tab or at ` xx:`
        var dp = ts.len + 1usize
        var q = 0usize
        while q < ts.len {
            if ts[q] == 58u8 && q > 3usize && (ts[q - 3usize] == 32u8 || ts[q - 3usize] == 9u8) {
                var p = q - 3usize
                while p > 0usize && (ts[p - 1usize] == 32u8 || ts[p - 1usize] == 9u8) { p -= 1usize }
                if p != 0usize { dp = p + 1usize }
                break
            }
            q += 1usize
        }
        var tab = ts.len + 1usize
        q = 0usize
        while q < ts.len {
            if ts[q] == 9u8 {
                tab = q
                break
            }
            q += 1usize
        }
        if tab < ts.len && (dp > ts.len || tab < dp) { dp = tab + 1usize }
        if dp <= ts.len { ts = ts[..dp - 1usize] }
        // the slash that separates the flags ("\/" is a slash in the word)
        var word_buf = buf_new(a)
        var ap = ts.len
        var k = 0usize
        while k < ts.len {
            if ts[k] == 92u8 && k + 1usize < ts.len && ts[k + 1usize] == 47u8 {
                buf_byte(&word_buf, 47u8)
                k += 2usize
                continue
            }
            if ts[k] == 47u8 && k != 0usize {
                ap = k
                break
            }
            buf_byte(&word_buf, ts[k])
            k += 1usize
        }
        var word = buf_done(&word_buf)
        var flags: []u16 = alloc[u16](a, 0usize)
        if ap < ts.len {
            if d.has_aliasf {
                let idx = atoi_str(ts[ap + 1usize..])
                if idx >= 1i32 && usize(idx) <= d.aliasf.len { flags = d.aliasf[usize(idx) - 1usize] }
            } else {
                flags = decode_flags(a, d, ts[ap + 1usize..])
                sort_u16(flags)
            }
        }
        word = strip_ignored(a, d, word)
        let cps = cp_decode(a, word)
        let cap = captype(cps)
        add_word(a, d, &ents, word, cps.len, flags, false, cap)
        // add_hidden_capitalized_word
        if (cap == HUHCAP || cap == HUHINITCAP || (cap == ALLCAP && flags.len != 0usize)) && !has_flag(flags, d.forbidden) {
            let f2 = alloc[u16](a, flags.len + 1usize)
            var m = 0usize
            while m < flags.len {
                f2[m] = flags[m]
                m += 1usize
            }
            f2[flags.len] = ONLYUPCASE
            let low = cp_decode(a, word)
            all_small(low)
            init_cap(low)
            add_word(a, d, &ents, cp_encode(a, low), cps.len, f2, true, INITCAP)
        }
    }
    d.entries = list.slice[Entry](&ents)
    d.ents = ents
    d.nentries = ents.len
    ret ok
}

// ---- affix checking ---------------------------------------------------------------------------

fn aff_at(d: *const Dict, pi: usize) -> *const Aff { ret &d.affs[pi - 1usize] }

fn tail(s: str, n: usize) -> str { ret s[s.len - n..] }

// isSubset: is `key` a leading part of `word` (a dot in the key matches any byte)?
fn key_is_subset(key: str, word: str) -> bool {
    var i = 0usize
    while i < key.len {
        if i >= word.len { ret false }
        if key[i] != word[i] && key[i] != 46u8 { ret false }
        i += 1usize
    }
    ret true
}

// isRevSubset: is `key` (a reversed suffix) the end of `word`, read backwards?
fn key_is_rev_subset(key: str, word: str) -> bool {
    if key.len > word.len { ret false }
    var i = 0usize
    while i < key.len {
        if key[i] != word[word.len - 1usize - i] && key[i] != 46u8 { ret false }
        i += 1usize
    }
    ret true
}

fn pfx_allowed(d: *const Dict, af: *const Aff, in_cpd: u8) -> bool {
    if in_cpd == IN_NOT && has_flag(af.cont, d.onlyincompound) { ret false }
    if in_cpd == IN_END && !has_flag(af.cont, d.cpermit) { ret false }
    ret true
}

// PfxEntry::checkword
fn pfx_checkword(w: *W, pi: usize, word: str, in_cpd: u8, needflag: u16) -> usize {
    let d = w.d
    let af = aff_at(d, pi)
    if word.len < af.appnd.len { ret 0usize }
    let tmpl = word.len - af.appnd.len
    if tmpl > 0usize || (tmpl == 0usize && d.fullstrip) {
        let tmpword = cat(w.a, af.strip, word[af.appnd.len..])
        if cond_prefix(af, tmpword) {
            var he = lookup(d, tmpword)
            while he != 0usize {
                let flags = d.entries[he].flags
                if has_flag(flags, af.flag) && !has_flag(af.cont, d.needaffix) && (needflag == 0u16 || has_flag(flags, needflag) || has_flag(af.cont, needflag)) { ret he }
                he = d.entries[he].homonym
            }
            if af.cross {
                let r = suffix_check(w, tmpword, 1u32, pi, 0u16, needflag, in_cpd)
                if r != 0usize { ret r }
            }
        }
    }
    ret 0usize
}

// AffixMgr::prefix_check
fn prefix_check(w: *W, word: str, in_cpd: u8, needflag: u16) -> usize {
    let d = w.d
    w.pfx = 0usize
    var i = 0usize
    while i < d.pfx0.len {
        let pi = d.pfx0[i]
        if pfx_allowed(d, aff_at(d, pi), in_cpd) {
            let r = pfx_checkword(w, pi, word, in_cpd, needflag)
            if r != 0usize {
                w.pfx = pi
                ret r
            }
        }
        i += 1usize
    }
    if word.len == 0usize { ret 0usize }
    let sp = usize(word[0usize])
    var k = d.pfx_from[sp]
    let stop = d.pfx_from[sp + 1usize]
    while k < stop {
        let pi = d.pfx_sorted[k]
        let af = aff_at(d, pi)
        if key_is_subset(af.key, word) && pfx_allowed(d, af, in_cpd) {
            let r = pfx_checkword(w, pi, word, in_cpd, needflag)
            if r != 0usize {
                w.pfx = pi
                ret r
            }
        }
        k += 1usize
    }
    ret 0usize
}

// Does the entry `he` satisfy this suffix (SfxEntry::checkword's per-homonym test)?
fn sfx_he_ok(d: *const Dict, af: *const Aff, ep: usize, he: usize, optflags: u32, cclass: u16, needflag: u16, badflag: u16) -> bool {
    let flags = d.entries[he].flags
    var pcont: []u16 = zero
    var pflag = 0u16
    if ep != 0usize {
        pcont = aff_at(d, ep).cont
        pflag = aff_at(d, ep).flag
    }
    if !(has_flag(flags, af.flag) || (ep != 0usize && has_flag(pcont, af.flag))) { ret false }
    if (optflags & 1u32) != 0u32 {
        if !((ep != 0usize && has_flag(flags, pflag)) || (ep != 0usize && has_flag(af.cont, pflag))) { ret false }
    }
    if cclass != 0u16 && !has_flag(af.cont, cclass) { ret false }
    if badflag != 0u16 && has_flag(flags, badflag) { ret false }
    if needflag != 0u16 && !(has_flag(flags, needflag) || has_flag(af.cont, needflag)) { ret false }
    ret true
}

// The word minus the suffix, with the stripped characters put back; (ok, text).
fn sfx_root(w: *W, af: *const Aff, word: str) -> (bool, str) {
    let d = w.d
    if word.len < af.appnd.len { ret (false, "") }
    let tmpl = word.len - af.appnd.len
    if !(tmpl > 0usize || (tmpl == 0usize && d.fullstrip)) { ret (false, "") }
    if tmpl + af.strip.len < af.numconds { ret (false, "") }
    let tmpword = cat(w.a, word[..tmpl], af.strip)
    if !cond_suffix(af, tmpword) { ret (false, "") }
    ret (true, tmpword)
}

// SfxEntry::checkword
fn sfx_checkword(w: *W, si: usize, word: str, optflags: u32, ppfx: usize, cclass: u16, needflag: u16, badflag: u16) -> usize {
    let d = w.d
    let af = aff_at(d, si)
    if (optflags & 1u32) != 0u32 && !af.cross { ret 0usize }
    let (good, tmpword) = sfx_root(w, af, word)
    if !good { ret 0usize }
    var he = lookup(d, tmpword)
    while he != 0usize {
        if sfx_he_ok(d, af, ppfx, he, optflags, cclass, needflag, badflag) { ret he }
        he = d.entries[he].homonym
    }
    ret 0usize
}

fn sfx_allowed(d: *const Dict, af: *const Aff, ppfx: usize, cclass: u16, in_cpd: u8, first_only: bool) -> bool {
    if in_cpd == IN_BEGIN && !has_flag(af.cont, d.cpermit) { ret false }
    if in_cpd == IN_NOT && has_flag(af.cont, d.onlyincompound) { ret false }
    if cclass == 0u16 && has_flag(af.cont, d.needaffix) {
        if first_only { ret false }
        if !(ppfx != 0usize && !has_flag(aff_at(d, ppfx).cont, d.needaffix)) { ret false }
    }
    ret true
}

// AffixMgr::suffix_check
fn suffix_check(w: *W, word: str, sfxopts: u32, ppfx: usize, cclass: u16, needflag: u16, in_cpd: u8) -> usize {
    let d = w.d
    var badflag = d.onlyincompound
    if in_cpd != IN_NOT { badflag = 0u16 }
    var i = 0usize
    while i < d.sfx0.len {
        let si = d.sfx0[i]
        let af = aff_at(d, si)
        if cclass == 0u16 || af.cont.len > 0usize {
            if sfx_allowed(d, af, ppfx, cclass, in_cpd, false) {
                let r = sfx_checkword(w, si, word, sfxopts, ppfx, cclass, needflag, badflag)
                if r != 0usize {
                    w.sfx = si
                    ret r
                }
            }
        }
        i += 1usize
    }
    if word.len == 0usize { ret 0usize }
    let sp = usize(word[word.len - 1usize])
    var k = d.sfx_from[sp]
    let stop = d.sfx_from[sp + 1usize]
    while k < stop {
        let si = d.sfx_sorted[k]
        let af = aff_at(d, si)
        if key_is_rev_subset(af.key, word) && sfx_allowed(d, af, ppfx, cclass, in_cpd, false) {
            if in_cpd != IN_END || ppfx != 0usize || !has_flag(af.cont, d.onlyincompound) {
                let r = sfx_checkword(w, si, word, sfxopts, ppfx, cclass, needflag, badflag)
                if r != 0usize {
                    w.sfx = si
                    ret r
                }
            }
        }
        k += 1usize
    }
    ret 0usize
}

// AffixMgr::affix_check
fn affix_check(w: *W, word: str, needflag: u16, in_cpd: u8) -> usize {
    var rv = prefix_check(w, word, in_cpd, needflag)
    if rv != 0usize { ret rv }
    rv = suffix_check(w, word, 0u32, 0usize, 0u16, needflag, in_cpd)
    if w.d.havecont {
        w.sfx = 0usize
        w.pfx = 0usize
        if rv != 0usize { ret rv }
        rv = suffix_check_twosfx(w, word, 0u32, 0usize, needflag)
        if rv != 0usize { ret rv }
        rv = prefix_check_twosfx(w, word, IN_NOT, needflag)
    }
    ret rv
}

// ---- morphological analysis ----------------------------------------------------------------------

fn flag_text(a: *mem.Arena, d: *const Dict, f: u16) -> str {
    var b = buf_new(a)
    if d.flag_mode == 2u8 {
        var digits: [8]u8 = zero
        var n = 0usize
        var v = u32(f)
        if v == 0u32 {
            buf_byte(&b, 48u8)
        } else {
            while v > 0u32 {
                digits[n] = u8(48u32 + v % 10u32)
                v = v / 10u32
                n += 1usize
            }
            while n > 0usize {
                n -= 1usize
                buf_byte(&b, digits[n])
            }
        }
    } else if d.flag_mode == 1u8 {
        buf_byte(&b, u8(u32(f) >> 8u32))
        buf_byte(&b, u8(u32(f) & 255u32))
    } else if d.flag_mode == 3u8 {
        cp_push(&b, u32(f))
    } else {
        buf_byte(&b, u8(f))
    }
    ret buf_done(&b)
}

// result += " fl:X"
fn debugflag(w: *W, out: *Buf, f: u16) {
    buf_str(out, " fl:")
    buf_str(out, flag_text(w.a, w.d, f))
}

fn sfx_morph_for(w: *W, si: usize, ppfx: usize, optflags: u32, cclass: u16, needflag: u16, word: str, out: *Buf, badflag: u16) {
    let d = w.d
    let af = aff_at(d, si)
    if (optflags & 1u32) != 0u32 && !af.cross { ret }
    let (good, tmpword) = sfx_root(w, af, word)
    if !good { ret }
    var he = lookup(d, tmpword)
    var first = true
    while he != 0usize {
        if sfx_he_ok(d, af, ppfx, he, optflags, cclass, needflag, badflag) {
            if ppfx != 0usize {
                let pf = aff_at(d, ppfx)
                if pf.morph.len > 0usize {
                    buf_str(out, pf.morph)
                    buf_byte(out, 32u8)
                } else {
                    debugflag(w, out, pf.flag)
                }
            }
            buf_str(out, " st:")
            buf_str(out, d.entries[he].word)
            if af.morph.len > 0usize {
                buf_byte(out, 32u8)
                buf_str(out, af.morph)
            } else {
                debugflag(w, out, af.flag)
            }
            buf_byte(out, 10u8)
        }
        he = d.entries[he].homonym
        first = false
    }
}

// AffixMgr::suffix_check_morph
fn suffix_check_morph(w: *W, word: str, sfxopts: u32, ppfx: usize, cclass: u16, needflag: u16, in_cpd: u8, out: *Buf) {
    let d = w.d
    var i = 0usize
    while i < d.sfx0.len {
        let si = d.sfx0[i]
        let af = aff_at(d, si)
        if cclass == 0u16 || af.cont.len > 0usize {
            if sfx_allowed(d, af, ppfx, cclass, in_cpd, false) {
                sfx_morph_for(w, si, ppfx, sfxopts, cclass, needflag, word, out, 0u16)
            }
        }
        i += 1usize
    }
    if word.len == 0usize { ret }
    let sp = usize(word[word.len - 1usize])
    var k = d.sfx_from[sp]
    let stop = d.sfx_from[sp + 1usize]
    while k < stop {
        let si = d.sfx_sorted[k]
        let af = aff_at(d, si)
        if key_is_rev_subset(af.key, word) && sfx_allowed(d, af, ppfx, cclass, in_cpd, true) {
            sfx_morph_for(w, si, ppfx, sfxopts, cclass, needflag, word, out, 0u16)
        }
        k += 1usize
    }
}

// PfxEntry::check_morph
fn pfx_check_morph(w: *W, pi: usize, word: str, in_cpd: u8, needflag: u16, out: *Buf) {
    let d = w.d
    let af = aff_at(d, pi)
    if word.len < af.appnd.len { ret }
    let tmpl = word.len - af.appnd.len
    if !(tmpl > 0usize || (tmpl == 0usize && d.fullstrip)) { ret }
    if tmpl + af.strip.len < af.numconds { ret }
    let tmpword = cat(w.a, af.strip, word[af.appnd.len..])
    if !cond_prefix(af, tmpword) { ret }
    var he = lookup(d, tmpword)
    while he != 0usize {
        let flags = d.entries[he].flags
        if has_flag(flags, af.flag) && !has_flag(af.cont, d.needaffix) && (needflag == 0u16 || has_flag(flags, needflag) || has_flag(af.cont, needflag)) {
            if af.morph.len > 0usize {
                buf_byte(out, 32u8)
                buf_str(out, af.morph)
            } else {
                buf_str(out, af.key)
            }
            buf_str(out, " st:")
            buf_str(out, d.entries[he].word)
            debugflag(w, out, af.flag)
            buf_byte(out, 10u8)
        }
        he = d.entries[he].homonym
    }
    if af.cross && in_cpd != IN_BEGIN {
        suffix_check_morph(w, tmpword, 1u32, pi, 0u16, needflag, IN_NOT, out)
    }
}

// AffixMgr::prefix_check_morph
fn prefix_check_morph(w: *W, word: str, in_cpd: u8, out: *Buf) {
    let d = w.d
    var i = 0usize
    while i < d.pfx0.len {
        pfx_check_morph(w, d.pfx0[i], word, in_cpd, 0u16, out)
        i += 1usize
    }
    if word.len == 0usize { ret }
    let sp = usize(word[0usize])
    var k = d.pfx_from[sp]
    let stop = d.pfx_from[sp + 1usize]
    while k < stop {
        let pi = d.pfx_sorted[k]
        let af = aff_at(d, pi)
        if key_is_subset(af.key, word) {
            var piece = buf_new(w.a)
            pfx_check_morph(w, pi, word, in_cpd, 0u16, &piece)
            if piece.len > 0usize {
                if in_cpd != IN_NOT || !has_flag(af.cont, d.onlyincompound) { buf_str(out, buf_done(&piece)) }
            }
        }
        k += 1usize
    }
}

fn affix_check_morph(w: *W, word: str, out: *Buf) {
    affix_check_morph_n(w, word, 0u16, out)
}

fn affix_check_morph_n(w: *W, word: str, needflag: u16, out: *Buf) {
    prefix_check_morph(w, word, IN_NOT, out)
    suffix_check_morph(w, word, 0u32, 0usize, 0u16, needflag, IN_NOT, out)
    if w.d.havecont {
        w.sfx = 0usize
        w.pfx = 0usize
        suffix_check_twosfx_morph(w, word, 0u32, 0usize, needflag, out)
        prefix_check_twosfx_morph(w, word, IN_NOT, needflag, out)
    }
}

// ---- compounds (COMPOUNDRULE) ------------------------------------------------------------------

type Bt = struct { btpp: i32, btwp: i32, btnum: i32 }

fn rule_meta(f: u16) -> bool { ret f == 42u16 || f == 63u16 }

// AffixMgr::defcpd_check
fn defcpd_check(w: *W, wactive: *bool, wnum: usize, rv: usize, rwords: []usize, all: bool) -> bool {
    let d = w.d
    var wset = false
    if !*wactive {
        wset = true
        *wactive = true
    }
    rwords[wnum] = rv
    if d.entries[rv].flags.len == 0usize {
        rwords[wnum] = 0usize
        if wset { *wactive = false }
        ret false
    }
    var any = false
    var ri = 0usize
    while ri < d.defcpd.len {
        var rj = 0usize
        while rj < d.defcpd[ri].len {
            let f = d.defcpd[ri][rj]
            if !rule_meta(f) && has_flag(d.entries[rv].flags, f) {
                any = true
                break
            }
            rj += 1usize
        }
        ri += 1usize
    }
    if !any {
        rwords[wnum] = 0usize
        if wset { *wactive = false }
        ret false
    }
    let wn = i32(wnum)
    var i = 0usize
    while i < d.defcpd.len {
        let rule = d.defcpd[i]
        let rl = i32(rule.len)
        var pp = 0i32
        var wp = 0i32
        var good = true
        var good2 = true
        var bt = 0i32
        var bts: [64]Bt = zero
        while true {
            while pp < rl && wp <= wn {
                if pp + 1i32 < rl && rule_meta(rule[usize(pp + 1i32)]) {
                    var wend = wn
                    if rule[usize(pp + 1i32)] == 63u16 { wend = wp }
                    good2 = true
                    pp += 2i32
                    bts[usize(bt)].btpp = pp
                    bts[usize(bt)].btwp = wp
                    while wp <= wend {
                        let ew = rwords[usize(wp)]
                        if ew == 0usize || d.entries[ew].flags.len == 0usize || !has_flag(d.entries[ew].flags, rule[usize(pp - 2i32)]) {
                            good2 = false
                            break
                        }
                        wp += 1i32
                    }
                    if wp <= wn { good2 = false }
                    bts[usize(bt)].btnum = wp - bts[usize(bt)].btwp
                    if bts[usize(bt)].btnum > 0i32 { bt += 1i32 }
                    if good2 { break }
                } else {
                    good2 = true
                    let ew = rwords[usize(wp)]
                    if ew == 0usize || d.entries[ew].flags.len == 0usize || !has_flag(d.entries[ew].flags, rule[usize(pp)]) {
                        good = false
                        break
                    }
                    pp += 1i32
                    wp += 1i32
                    if rl == pp && !(wp > wn) { good = false }
                }
            }
            if good && good2 {
                var r = pp
                while rl > r && r + 1i32 < rl && rule_meta(rule[usize(r + 1i32)]) { r += 2i32 }
                if rl <= r { ret true }
            }
            if bt > 0i32 {
                while true {
                    good = true
                    bts[usize(bt - 1i32)].btnum -= 1i32
                    pp = bts[usize(bt - 1i32)].btpp
                    wp = bts[usize(bt - 1i32)].btwp + bts[usize(bt - 1i32)].btnum
                    if !(bts[usize(bt - 1i32)].btnum < 0i32) { break }
                    bt -= 1i32
                    if bt == 0i32 { break }
                }
            }
            if bt == 0i32 { break }
        }
        if good && good2 && (!all || rl <= pp) { ret true }
        while good && good2 && rl > pp && pp + 1i32 < rl && rule_meta(rule[usize(pp + 1i32)]) { pp += 2i32 }
        if good && good2 && rl <= pp { ret true }
        i += 1usize
    }
    rwords[wnum] = 0usize
    if wset { *wactive = false }
    ret false
}

fn setcminmax(d: *const Dict, word: str) -> (usize, usize) {
    var cmin = 0usize
    var i = 0usize
    while i < d.cpdmin && cmin < word.len {
        cmin += 1usize
        while cmin < word.len && (word[cmin] & 192u8) == 128u8 { cmin += 1usize }
        i += 1usize
    }
    var cmax = word.len
    i = 0usize
    while i + 1usize < d.cpdmin && cmax > 0usize {
        cmax -= 1usize
        while cmax > 0usize && (word[cmax] & 192u8) == 128u8 { cmax -= 1usize }
        i += 1usize
    }
    ret (cmin, cmax)
}

fn has_compound(d: *const Dict) -> bool { ret d.cflag != 0u16 || d.cbegin != 0u16 || d.defcpd.len > 0usize }

fn cont_has(w: *W, ai: usize, f: u16) -> bool {
    if ai == 0usize || f == 0u16 { ret false }
    ret has_flag(aff_at(w.d, ai).cont, f)
}

fn candidate_check(w: *W, s: str) -> bool {
    if lookup(w.d, s) != 0usize { ret true }
    ret affix_check(w, s, 0u16, IN_NOT) != 0usize
}

fn cpdrep_check(w: *W, word: str) -> bool {
    let d = w.d
    if word.len < 2usize || d.rep.len == 0usize { ret false }
    var i = 0usize
    while i < d.rep.len {
        let r = &d.rep[i]
        if r.out[0usize].len > 0usize && r.pattern.len > 0usize {
            var at = 0usize
            while true {
                let f = find_str(word, r.pattern, at)
                if f > word.len { break }
                let cand = cat(w.a, cat(w.a, word[..f], r.out[0usize]), word[f + r.pattern.len..])
                if candidate_check(w, cand) { ret true }
                at = f + 1usize
            }
        }
        i += 1usize
    }
    ret false
}

fn cpdwordpair_check(w: *W, word: str) -> bool {
    if word.len <= 2usize { ret false }
    var i = 1usize
    while i < word.len {
        if (word[i] & 192u8) == 128u8 {
            i += 1usize
            continue
        }
        let cand = cat(w.a, cat(w.a, word[..i], " "), word[i..])
        if candidate_check(w, cand) { ret true }
        i += 1usize
    }
    ret false
}

fn cpdcase_check(w: *W, word: str, pos: usize) -> bool {
    var p = pos - 1usize
    while p > 0usize && (word[p] & 192u8) == 128u8 { p -= 1usize }
    let pair = cp_decode(w.a, word[p..])
    var a = 0u32
    var b = 0u32
    if pair.len > 1usize { a = pair[1usize] }
    if pair.len > 0usize { b = pair[0usize] }
    ret (cp_upper(a) == a || cp_upper(b) == b) && a != 45u32 && b != 45u32
}

fn entry_bad_in_compound(w: *W, rv: usize, is_sug: bool) -> bool {
    let d = w.d
    let fl = d.entries[rv].flags
    ret has_flag(fl, d.forbidden) || has_flag(fl, ONLYUPCASE) || (is_sug && has_flag(fl, d.nosuggest))
}

// The homonym of `rv` the first-word loop settles on.
fn first_word_entry(w: *W, st: str, onlycpdrule: bool, wactive: *bool, wordnum: i32, wnum: usize, rwords: []usize) -> usize {
    let d = w.d
    var rv = lookup(d, st)
    while rv != 0usize {
        let fl = d.entries[rv].flags
        var keep = false
        if !has_flag(fl, d.needaffix) {
            if d.cflag != 0u16 && !*wactive && !onlycpdrule && has_flag(fl, d.cflag) {
                keep = true
            } else if d.cbegin != 0u16 && wordnum == 0i32 && !onlycpdrule && has_flag(fl, d.cbegin) {
                keep = true
            } else if d.cmiddle != 0u16 && wordnum != 0i32 && !*wactive && !onlycpdrule && has_flag(fl, d.cmiddle) {
                keep = true
            } else if d.defcpd.len > 0usize && onlycpdrule {
                if !*wactive && wordnum == 0i32 {
                    keep = defcpd_check(w, wactive, wnum, rv, rwords, false)
                } else if *wactive {
                    keep = defcpd_check(w, wactive, wnum, rv, rwords, false)
                }
            }
        }
        if keep { ret rv }
        rv = d.entries[rv].homonym
    }
    ret 0usize
}

fn second_word_entry(w: *W, rest: str, wactive: *bool, wnum: usize, rwords: []usize) -> usize {
    let d = w.d
    var rv = lookup(d, rest)
    while rv != 0usize {
        let fl = d.entries[rv].flags
        var keep = false
        if !has_flag(fl, d.needaffix) {
            if d.cflag != 0u16 && !*wactive && has_flag(fl, d.cflag) {
                keep = true
            } else if d.cend != 0u16 && !*wactive && has_flag(fl, d.cend) {
                keep = true
            } else if d.defcpd.len > 0usize && *wactive {
                keep = defcpd_check(w, wactive, wnum + 1usize, rv, rwords, true)
            }
        }
        if keep { ret rv }
        rv = d.entries[rv].homonym
    }
    ret 0usize
}

// The first word of a compound found through the compound flags and affixes; (entry, checked_prefix).
fn first_word_flagged(w: *W, st: str, wordnum: i32) -> (usize, bool) {
    let d = w.d
    var rv = 0usize
    if d.cflag != 0u16 {
        rv = prefix_check(w, st, IN_BEGIN, d.cflag)
        if rv == 0usize {
            rv = suffix_check(w, st, 0u32, 0usize, 0u16, d.cflag, IN_BEGIN)
            if rv != 0usize && w.sfx != 0usize {
                let sc = aff_at(d, w.sfx).cont
                if sc.len > 0usize && ((d.cforbid != 0u16 && has_flag(sc, d.cforbid)) || (d.cend != 0u16 && has_flag(sc, d.cend))) { rv = 0usize }
            }
        }
    }
    if rv != 0usize { ret (rv, true) }
    if wordnum == 0i32 && d.cbegin != 0u16 {
        rv = suffix_check(w, st, 0u32, 0usize, 0u16, d.cbegin, IN_BEGIN)
        if rv == 0usize { rv = prefix_check(w, st, IN_BEGIN, d.cbegin) }
        if rv != 0usize { ret (rv, true) }
    } else if wordnum > 0i32 && d.cmiddle != 0u16 {
        rv = suffix_check(w, st, 0u32, 0usize, 0u16, d.cmiddle, IN_BEGIN)
        if rv == 0usize { rv = prefix_check(w, st, IN_BEGIN, d.cmiddle) }
        if rv != 0usize { ret (rv, true) }
    }
    ret (0usize, false)
}

// Is the first word acceptable in a compound (the long condition of compound_check)?
fn first_word_ok(w: *W, rv: usize, checked_prefix: bool, wactive: bool, rwords: []usize, wnum: usize, oldwordnum: i32, word: str, i: usize) -> bool {
    let d = w.d
    let fl = d.entries[rv].flags
    let accept = checked_prefix || (wactive && rwords[wnum] != 0usize) || (d.cflag != 0u16 && has_flag(fl, d.cflag)) || (oldwordnum == 0i32 && d.cbegin != 0u16 && has_flag(fl, d.cbegin)) || (oldwordnum > 0i32 && d.cmiddle != 0u16 && has_flag(fl, d.cmiddle))
    if !accept { ret false }
    if d.chk_triple && !wactive && i >= 1usize && word[i - 1usize] == word[i] {
        if (i > 1usize && word[i - 1usize] == word[i - 2usize]) || (i + 1usize < word.len && word[i - 1usize] == word[i + 1usize]) { ret false }
    }
    if d.chk_case && !wactive && cpdcase_check(w, word, i) { ret false }
    ret true
}

// AffixMgr::compound_check. The entry of the first word, or 0.
fn compound_check(w: *W, word: str, wordnum_in: i32, maxwordnum: i32, wnum: usize, words_in: bool, rwords: []usize, is_sug: bool) -> usize {
    let d = w.d
    var wordnum = wordnum_in
    let (cmin, cmax) = setcminmax(d, word)
    var striple = false
    var checkedstriple = false
    var i = cmin
    while i < cmax {
        while i < word.len && (word[i] & 192u8) == 128u8 { i += 1usize }
        if i >= cmax { ret 0usize }
        var wactive = words_in
        var onlycpdrule = 0i32
        if wactive { onlycpdrule = 1i32 }
        while true {
            let oldwordnum = wordnum
            var checked_prefix = false
            let st = word[..i]
            w.sfx = 0usize
            w.pfx = 0usize
            let stem0 = lookup(d, st)
            var proceed = true
            var rv = 0usize
            if stem0 != 0usize && d.cforbid != 0u16 && has_flag(d.entries[stem0].flags, d.cforbid) {
                proceed = false
            } else {
                rv = first_word_entry(w, st, onlycpdrule != 0i32, &wactive, wordnum, wnum, rwords)
            }
            if proceed && rv == 0usize {
                if onlycpdrule != 0i32 {
                    proceed = false
                } else {
                    let (r1, cp1) = first_word_flagged(w, st, wordnum)
                    rv = r1
                    checked_prefix = cp1
                }
            } else if proceed && (has_flag(d.entries[rv].flags, d.forbidden) || has_flag(d.entries[rv].flags, d.needaffix) || has_flag(d.entries[rv].flags, ONLYUPCASE) || (is_sug && has_flag(d.entries[rv].flags, d.nosuggest))) {
                proceed = false
            }
            if proceed {
                if rv != 0usize && (cont_has(w, w.pfx, d.cforbid) || cont_has(w, w.sfx, d.cforbid)) { rv = 0usize }
                if rv != 0usize && !checked_prefix && d.cend != 0u16 && (cont_has(w, w.pfx, d.cend) || cont_has(w, w.sfx, d.cend)) { rv = 0usize }
                if rv != 0usize && !checked_prefix && wordnum == 0i32 && d.cmiddle != 0u16 && (cont_has(w, w.pfx, d.cmiddle) || cont_has(w, w.sfx, d.cmiddle)) { rv = 0usize }
                if rv != 0usize && entry_bad_in_compound(w, rv, is_sug) { ret 0usize }
                if rv != 0usize && d.croot != 0u16 && has_flag(d.entries[rv].flags, d.croot) { wordnum += 1i32 }
                if rv != 0usize && first_word_ok(w, rv, checked_prefix, wactive, rwords, wnum, oldwordnum, word, i) {
                    let rv_first = rv
                    while true {
                        if d.simp_triple {
                            if striple {
                                checkedstriple = true
                                i -= 1usize
                            } else if i > 2usize && word[i - 1usize] == word[i - 2usize] {
                                striple = true
                            }
                        }
                        let rest = word[i..]
                        var r2 = second_word_entry(w, rest, &wactive, wnum, rwords)
                        if r2 != 0usize && wactive && rwords[wnum + 1usize] != 0usize { ret rv_first }
                        let oldwordnum2 = wordnum
                        if r2 != 0usize && d.croot != 0u16 && has_flag(d.entries[r2].flags, d.croot) { wordnum += 1i32 }
                        if r2 != 0usize && entry_bad_in_compound(w, r2, is_sug) { ret 0usize }
                        if r2 != 0usize && ((d.cflag != 0u16 && has_flag(d.entries[r2].flags, d.cflag)) || (d.cend != 0u16 && has_flag(d.entries[r2].flags, d.cend))) && (d.cpdwordmax == -1i32 || wordnum + 1i32 < d.cpdwordmax) && (!d.chk_dup || r2 != rv_first) {
                            if (d.chk_rep && cpdrep_check(w, word)) || cpdwordpair_check(w, word) { ret 0usize }
                            ret rv_first
                        }
                        wordnum = oldwordnum2
                        w.sfx = 0usize
                        r2 = 0usize
                        if d.cflag != 0u16 && onlycpdrule == 0i32 { r2 = affix_check(w, rest, d.cflag, IN_END) }
                        if r2 == 0usize && d.cend != 0u16 && onlycpdrule == 0i32 {
                            w.sfx = 0usize
                            w.pfx = 0usize
                            r2 = affix_check(w, rest, d.cend, IN_END)
                        }
                        if r2 == 0usize && d.defcpd.len > 0usize && wactive {
                            r2 = affix_check(w, rest, 0u16, IN_END)
                            if r2 != 0usize && defcpd_check(w, &wactive, wnum + 1usize, r2, rwords, true) { ret rv_first }
                            r2 = 0usize
                        }
                        if r2 != 0usize && (cont_has(w, w.pfx, d.cforbid) || cont_has(w, w.sfx, d.cforbid)) { r2 = 0usize }
                        if r2 != 0usize && entry_bad_in_compound(w, r2, is_sug) { ret 0usize }
                        if r2 != 0usize && d.croot != 0u16 && has_flag(d.entries[r2].flags, d.croot) { wordnum += 1i32 }
                        if r2 != 0usize && (d.cpdwordmax == -1i32 || wordnum + 1i32 < d.cpdwordmax) && (!d.chk_dup || r2 != rv_first) {
                            if (d.chk_rep && cpdrep_check(w, word)) || cpdwordpair_check(w, word) { ret 0usize }
                            ret rv_first
                        }
                        wordnum = oldwordnum2
                        var r3 = 0usize
                        if wordnum + 2i32 < maxwordnum { r3 = compound_check(w, word[i..], wordnum + 1i32, maxwordnum, wnum + 1usize, wactive, rwords, is_sug) }
                        var skip = false
                        if r3 != 0usize {
                            if cpdwordpair_check(w, word) { ret 0usize }
                            if d.chk_rep || d.forbidden != 0u16 {
                                if d.chk_rep && cpdrep_check(w, word) { ret 0usize }
                                let rw = d.entries[r3].word
                                if at_str(word, i, rw) {
                                    let part = word[..i + rw.len]
                                    if (d.chk_rep && cpdrep_check(w, part)) || cpdwordpair_check(w, part) {
                                        skip = true
                                    } else if d.forbidden != 0u16 {
                                        var rv2 = lookup(d, word)
                                        if rv2 == 0usize { rv2 = affix_check(w, word, 0u16, IN_NOT) }
                                        if rv2 != 0usize && has_flag(d.entries[rv2].flags, d.forbidden) && at_str(d.entries[rv2].word, 0usize, part) { ret 0usize }
                                    }
                                }
                            }
                            if !skip { ret rv_first }
                        }
                        if !(striple && !checkedstriple) { break }
                    }
                    if checkedstriple {
                        i += 1usize
                        checkedstriple = false
                        striple = false
                    }
                }
            }
            wordnum = oldwordnum
            if d.defcpd.len > 0usize && oldwordnum == 0i32 && onlycpdrule < 1i32 {
                onlycpdrule += 1i32
            } else {
                break
            }
        }
        i += 1usize
    }
    ret 0usize
}

// line_uniq_app: a text of newline separated lines becomes one line, or a ( a | b ) group.
fn line_uniq_app(a: *mem.Arena, text: str) -> str {
    if !has_byte(text, 10u8) { ret text }
    let lines = split_lines(a, text, 10u8)
    if lines.len == 0usize { ret "" }
    var uniq = new_list[str](a)
    var i = 0usize
    while i < lines.len {
        var dup = false
        var j = 0usize
        while j < uniq.len {
            if same(uniq.items[j], lines[i]) { dup = true }
            j += 1usize
        }
        if !dup { push_str(&uniq, lines[i]) }
        i += 1usize
    }
    if lines.len == 1usize { ret lines[0usize] }
    var b = buf_new(a)
    buf_str(&b, " ( ")
    i = 0usize
    while i < lines.len {
        buf_str(&b, lines[i])
        if i + 1usize < lines.len {
            buf_str(&b, " | ")
        } else {
            buf_str(&b, " ) ")
        }
        i += 1usize
    }
    ret buf_done(&b)
}

fn affix_check_morph_flag(w: *W, word: str, needflag: u16) -> str {
    var out = buf_new(w.a)
    affix_check_morph_n(w, word, needflag, &out)
    ret buf_done(&out)
}

// The morphological text of a compound's last part (compound flag, else compound end flag).
fn last_part_morph(w: *W, rest: str) -> str {
    let d = w.d
    var m = ""
    if d.cflag != 0u16 { m = affix_check_morph_flag(w, rest, d.cflag) }
    if m.len == 0usize && d.cend != 0u16 { m = affix_check_morph_flag(w, rest, d.cend) }
    ret m
}

// AffixMgr::compound_check_morph.
fn compound_check_morph(w: *W, word: str, wordnum_in: i32, maxwordnum: i32, wnum: usize, words_in: bool, rwords: []usize, result: *Buf, partresult: str) {
    let d = w.d
    var wordnum = wordnum_in
    var found_ok = false
    let (cmin, cmax) = setcminmax(d, word)
    var i = cmin
    while i < cmax {
        while i < word.len && (word[i] & 192u8) == 128u8 { i += 1usize }
        if i >= cmax { ret }
        var wactive = words_in
        var onlycpdrule = 0i32
        if wactive { onlycpdrule = 1i32 }
        while true {
            let oldwordnum = wordnum
            var checked_prefix = false
            let st = word[..i]
            w.sfx = 0usize
            var presult = buf_new(w.a)
            buf_str(&presult, partresult)
            let stem0 = lookup(d, st)
            var proceed = true
            var rv = 0usize
            if stem0 != 0usize && d.cforbid != 0u16 && has_flag(d.entries[stem0].flags, d.cforbid) {
                proceed = false
            } else {
                rv = first_word_entry(w, st, onlycpdrule != 0i32, &wactive, wordnum, wnum, rwords)
            }
            if proceed && rv != 0usize {
                buf_str(&presult, " pa:")
                buf_str(&presult, st)
                buf_str(&presult, " st:")
                buf_str(&presult, st)
            }
            if proceed && rv == 0usize {
                let (r1, cp1) = first_word_flagged(w, st, wordnum)
                rv = r1
                if rv != 0usize {
                    var p = ""
                    if d.cflag != 0u16 { p = affix_check_morph_flag(w, st, d.cflag) }
                    if p.len == 0usize {
                        if wordnum == 0i32 && d.cbegin != 0u16 {
                            p = affix_check_morph_flag(w, st, d.cbegin)
                        } else if wordnum > 0i32 && d.cmiddle != 0u16 {
                            p = affix_check_morph_flag(w, st, d.cmiddle)
                        }
                    }
                    if p.len > 0usize {
                        buf_str(&presult, " pa:")
                        buf_str(&presult, st)
                        buf_str(&presult, line_uniq_app(w.a, p))
                    }
                    checked_prefix = true
                }
            } else if proceed && (has_flag(d.entries[rv].flags, d.forbidden) || has_flag(d.entries[rv].flags, ONLYUPCASE) || has_flag(d.entries[rv].flags, d.needaffix)) {
                proceed = false
            }
            if proceed && rv != 0usize {
                if cont_has(w, w.pfx, d.cforbid) || cont_has(w, w.sfx, d.cforbid) { proceed = false }
                if proceed && !checked_prefix && d.cend != 0u16 && (cont_has(w, w.pfx, d.cend) || cont_has(w, w.sfx, d.cend)) { proceed = false }
                if proceed && !checked_prefix && wordnum == 0i32 && d.cmiddle != 0u16 && (cont_has(w, w.pfx, d.cmiddle) || cont_has(w, w.sfx, d.cmiddle)) { rv = 0usize }
                if proceed && rv != 0usize && (has_flag(d.entries[rv].flags, d.forbidden) || has_flag(d.entries[rv].flags, ONLYUPCASE)) { proceed = false }
                if proceed && rv != 0usize && d.croot != 0u16 && has_flag(d.entries[rv].flags, d.croot) { wordnum += 1i32 }
            }
            if proceed && rv != 0usize && first_word_ok(w, rv, checked_prefix, wactive, rwords, wnum, oldwordnum, word, i) {
                let rv_first = rv
                let rest = word[i..]
                var r2 = second_word_entry(w, rest, &wactive, wnum, rwords)
                if r2 != 0usize && wactive && rwords[wnum + 1usize] != 0usize {
                    buf_str(result, buf_done(&presult))
                    buf_str(result, " pa:")
                    buf_str(result, rest)
                    buf_str(result, " st:")
                    buf_str(result, d.entries[r2].word)
                    buf_byte(result, 10u8)
                    ret
                }
                let oldwordnum2 = wordnum
                if r2 != 0usize && d.croot != 0u16 && has_flag(d.entries[r2].flags, d.croot) { wordnum += 1i32 }
                if r2 != 0usize && (has_flag(d.entries[r2].flags, d.forbidden) || has_flag(d.entries[r2].flags, ONLYUPCASE)) { proceed = false }
                if proceed {
                    if r2 != 0usize && ((d.cflag != 0u16 && has_flag(d.entries[r2].flags, d.cflag)) || (d.cend != 0u16 && has_flag(d.entries[r2].flags, d.cend))) && (d.cpdwordmax == -1i32 || wordnum + 1i32 < d.cpdwordmax) && (!d.chk_dup || r2 != rv_first) {
                        buf_str(result, buf_done(&presult))
                        buf_str(result, " pa:")
                        buf_str(result, rest)
                        buf_byte(result, 10u8)
                        found_ok = true
                    }
                    wordnum = oldwordnum2
                    w.sfx = 0usize
                    r2 = 0usize
                    if d.cflag != 0u16 && onlycpdrule == 0i32 { r2 = affix_check(w, rest, d.cflag, IN_NOT) }
                    if r2 == 0usize && d.cend != 0u16 && onlycpdrule == 0i32 {
                        w.sfx = 0usize
                        w.pfx = 0usize
                        r2 = affix_check(w, rest, d.cend, IN_NOT)
                    }
                    if r2 == 0usize && d.defcpd.len > 0usize && wactive {
                        r2 = affix_check(w, rest, 0u16, IN_END)
                        if r2 != 0usize && defcpd_check(w, &wactive, wnum + 1usize, r2, rwords, true) {
                            let m = last_part_morph(w, rest)
                            buf_str(result, buf_done(&presult))
                            if m.len > 0usize {
                                buf_str(result, " pa:")
                                buf_str(result, rest)
                                buf_str(result, line_uniq_app(w.a, m))
                            }
                            buf_byte(result, 10u8)
                            found_ok = true
                        }
                    }
                    if r2 != 0usize && (cont_has(w, w.pfx, d.cforbid) || cont_has(w, w.sfx, d.cforbid)) { r2 = 0usize }
                    if r2 != 0usize && (has_flag(d.entries[r2].flags, d.forbidden) || has_flag(d.entries[r2].flags, ONLYUPCASE)) && !has_flag(d.entries[r2].flags, d.needaffix) { proceed = false }
                }
                if proceed {
                    if r2 != 0usize && d.croot != 0u16 && has_flag(d.entries[r2].flags, d.croot) { wordnum += 1i32 }
                    if r2 != 0usize && (d.cpdwordmax == -1i32 || wordnum + 1i32 < d.cpdwordmax) && (!d.chk_dup || r2 != rv_first) {
                        let m = last_part_morph(w, rest)
                        buf_str(result, buf_done(&presult))
                        if m.len > 0usize {
                            buf_str(result, " pa:")
                            buf_str(result, rest)
                            buf_byte(result, 32u8)
                            buf_str(result, line_uniq_app(w.a, m))
                        }
                        buf_byte(result, 10u8)
                        found_ok = true
                    }
                    wordnum = oldwordnum2
                    if wordnum + 2i32 < maxwordnum && !found_ok {
                        compound_check_morph(w, rest, wordnum + 1i32, maxwordnum, wnum + 1usize, wactive, rwords, result, buf_done(&presult))
                    }
                }
            }
            wordnum = oldwordnum
            if d.defcpd.len > 0usize && oldwordnum == 0i32 && onlycpdrule < 1i32 {
                onlycpdrule += 1i32
            } else {
                break
            }
        }
        i += 1usize
    }
}

// SuggestMgr::suggest_morph: the analyses of one form, lines joined by a newline.
fn suggest_morph(w: *W, word: str) -> str {
    let d = w.d
    var out = buf_new(w.a)
    var he = lookup(d, word)
    while he != 0usize {
        let flags = d.entries[he].flags
        if !(has_flag(flags, d.forbidden) || has_flag(flags, d.needaffix) || has_flag(flags, d.onlyincompound)) {
            buf_str(&out, " st:")
            buf_str(&out, word)
            buf_byte(&out, 10u8)
        }
        he = d.entries[he].homonym
    }
    affix_check_morph(w, word, &out)
    if has_compound(d) && out.len == 0usize {
        let rwords = alloc[usize](w.a, 101usize)
        var z = 0usize
        while z < rwords.len {
            rwords[z] = 0usize
            z += 1usize
        }
        compound_check_morph(w, word, 0i32, 100i32, 0usize, false, rwords, &out, "")
    }
    ret line_uniq(w.a, buf_done(&out))
}

// line_tok then line_uniq: the non-empty lines without repeats, joined by newlines.
fn line_uniq(a: *mem.Arena, text: str) -> str {
    let lines = split_lines(a, text, 10u8)
    var out = buf_new(a)
    var i = 0usize
    while i < lines.len {
        var dup = false
        var j = 0usize
        while j < i {
            if same(lines[i], lines[j]) {
                dup = true
                break
            }
            j += 1usize
        }
        if !dup {
            if out.len > 0usize { buf_byte(&out, 10u8) }
            buf_str(&out, lines[i])
        }
        i += 1usize
    }
    ret buf_done(&out)
}

// line_tok: the non-empty pieces between `sep`.
fn split_lines(a: *mem.Arena, text: str, sep: u8) -> []str {
    var out = new_list[str](a)
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == sep {
            if i > start { push_str(&out, text[start..i]) }
            start = i + 1usize
        }
        i += 1usize
    }
    ret list.slice[str](&out)
}

// ---- conversion tables (ICONV, OCONV) -------------------------------------------------------

// strncmp of `pat` against the text of `s` from `at`.
fn ncmp(s: str, at: usize, pat: str) -> i32 {
    var k = 0usize
    while k < pat.len {
        var c = 0u8
        if at + k < s.len { c = s[at + k] }
        if c != pat[k] {
            if c < pat[k] { ret -1i32 }
            ret 1i32
        }
        k += 1usize
    }
    ret 0i32
}

fn conv_find(rl: []const Rep, s: str, at: usize) -> i32 {
    var p1 = 0i32
    var p2 = i32(rl.len) - 1i32
    var found = -1i32
    while p1 <= p2 {
        let m = (p1 + p2) / 2i32
        let c = ncmp(s, at, rl[usize(m)].pattern)
        if c < 0i32 {
            p2 = m - 1i32
        } else if c > 0i32 {
            p1 = m + 1i32
        } else {
            found = m
            p1 = m + 1i32
        }
    }
    ret found
}

fn conv_replace(rl: []const Rep, s: str, at: usize, ind: i32, atstart: bool) -> str {
    if ind < 0i32 { ret "" }
    let r = &rl[usize(ind)]
    var kind = 0usize
    if atstart { kind = 1usize }
    if s.len - at == r.pattern.len {
        if atstart {
            kind = 3usize
        } else {
            kind = 2usize
        }
    }
    while kind != 0usize && r.out[kind].len == 0usize {
        if kind == 2usize && !atstart {
            kind = 0usize
        } else {
            kind -= 1usize
        }
    }
    ret r.out[kind]
}

// RepList::conv: (converted text, whether anything changed).
fn conv(a: *mem.Arena, rl: []const Rep, s: str) -> (str, bool) {
    var b = buf_new(a)
    var change = false
    var i = 0usize
    while i < s.len {
        let n = conv_find(rl, s, i)
        let l = conv_replace(rl, s, i, n, i == 0usize)
        if l.len > 0usize {
            buf_str(&b, l)
            i += rl[usize(n)].pattern.len - 1usize
            change = true
        } else {
            buf_byte(&b, s[i])
        }
        i += 1usize
    }
    ret (buf_done(&b), change)
}

// ---- spelling --------------------------------------------------------------------------------

fn is_keepcase(d: *const Dict, he: usize) -> bool { ret has_flag(d.entries[he].flags, d.keepcase) }

// HunspellImpl::checkword: the entry that makes `word0` correct, or 0; `info` collects the
// forbidden, compound and capitalisation facts.
fn checkword(w: *W, word0: str, info: *u32) -> usize {
    let d = w.d
    let word = strip_ignored(w.a, d, word0)
    if word.len == 0usize { ret 0usize }
    var he = lookup(d, word)
    if he != 0usize && has_flag(d.entries[he].flags, d.forbidden) {
        *info = *info + SP_FORBIDDEN
        ret 0usize
    }
    while he != 0usize {
        let flags = d.entries[he].flags
        if has_flag(flags, d.needaffix) || has_flag(flags, d.onlyincompound) || ((*info & SP_INITCAP) != 0u32 && has_flag(flags, ONLYUPCASE)) {
            he = d.entries[he].homonym
        } else {
            break
        }
    }
    if he == 0usize {
        he = affix_check(w, word, 0u16, IN_NOT)
        if he != 0usize {
            let flags = d.entries[he].flags
            if has_flag(flags, d.onlyincompound) || ((*info & SP_INITCAP) != 0u32 && has_flag(flags, ONLYUPCASE)) { he = 0usize }
        }
        if he != 0usize {
            if has_flag(d.entries[he].flags, d.forbidden) {
                *info = *info + SP_FORBIDDEN
                ret 0usize
            }
        } else if has_compound(d) {
            let rwords = alloc[usize](w.a, 101usize)
            var z = 0usize
            while z < rwords.len {
                rwords[z] = 0usize
                z += 1usize
            }
            he = compound_check(w, word, 0i32, 100i32, 0usize, false, rwords, false)
            if he != 0usize { *info = *info + SP_COMPOUND }
        }
    }
    ret he
}

fn trailing_dots(s: str) -> usize {
    var n = 0usize
    while n < s.len && s[s.len - 1usize - n] == 46u8 { n += 1usize }
    ret n
}

type Cleaned = struct { word: str, cap: u8, abbv: usize }

// HunspellImpl::cleanword2
fn cleanword2(w: *W, src: str) -> Cleaned {
    let d = w.d
    let w2 = strip_ignored(w.a, d, src)
    var start = 0usize
    while start < w2.len && w2[start] == 32u8 { start += 1usize }
    let body = w2[start..]
    let abbv = trailing_dots(body)
    let nl = body.len - abbv
    if nl == 0usize { ret Cleaned { word: "", cap: NOCAP, abbv: abbv } }
    let dest = body[..nl]
    ret Cleaned { word: dest, cap: captype(cp_decode(w.a, dest)), abbv: abbv }
}

fn convert_in(w: *W, word: str) -> str {
    if !w.d.has_iconv { ret word }
    let (out, changed) = conv(w.a, w.d.iconv, word)
    if changed { ret out }
    ret word
}

fn is_digit_byte(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// HunspellImpl::spell_internal
fn spell_info(w: *W, word: str, info: *u32) -> bool {
    let d = w.d
    *info = 0u32
    if word.len >= 300usize { ret false }
    let cl = cleanword2(w, convert_in(w, word))
    var scw = cl.word
    let cap = cl.cap
    let abbv = cl.abbv
    if scw.len == 0usize { ret true }
    // numbers with dots, dashes and commas
    var nstate = 0i32
    var i = 0usize
    while i < scw.len {
        if is_digit_byte(scw[i]) {
            nstate = 1i32
        } else if scw[i] == 44u8 || scw[i] == 46u8 || scw[i] == 45u8 {
            if nstate == 2i32 || i == 0usize { break }
            nstate = 2i32
        } else {
            break
        }
        i += 1usize
    }
    if i == scw.len && nstate == 1i32 { ret true }

    var rv = 0usize
    var done = false
    if cap == HUHCAP || cap == HUHINITCAP || cap == NOCAP {
        if cap != NOCAP { *info = *info + SP_ORIGCAP }
        rv = checkword(w, scw, info)
        if abbv > 0usize && rv == 0usize { rv = checkword(w, cat(w.a, scw, "."), info) }
        done = true
    }
    if !done && cap == ALLCAP {
        *info = *info + SP_ORIGCAP
        rv = checkword(w, scw, info)
        if rv == 0usize && abbv > 0usize { rv = checkword(w, cat(w.a, scw, "."), info) }
        if rv == 0usize {
            let apos = find_str(scw, "'", 0usize)
            if apos < scw.len {
                scw = str_small(w.a, scw)
                if apos + 1usize < scw.len {
                    let part1 = scw[..apos + 1usize]
                    let part2 = str_initcap(w.a, scw[apos + 1usize..])
                    scw = cat(w.a, part1, part2)
                    rv = checkword(w, scw, info)
                    if rv == 0usize {
                        scw = str_initcap(w.a, scw)
                        rv = checkword(w, scw, info)
                    }
                }
            }
        }
        if rv != 0usize { done = true }
    }
    if !done {
        // INITCAP, and ALLCAP falling through
        *info = *info + SP_ORIGCAP
        if cap == ALLCAP { scw = str_initcap(w.a, str_small(w.a, scw)) }
        if cap == INITCAP { *info = *info + SP_INITCAP }
        rv = checkword(w, scw, info)
        if cap == INITCAP { *info = *info - SP_INITCAP }
        if (*info & SP_FORBIDDEN) != 0u32 {
            rv = 0usize
            done = true
        } else {
            if rv != 0usize && is_keepcase(d, rv) && cap == ALLCAP { rv = 0usize }
            if rv != 0usize {
                done = true
            } else {
                let lowered = str_small(w.a, scw)
                scw = str_initcap(w.a, lowered)
                var buffer = lowered
                var skip_final = false
                rv = checkword(w, buffer, info)
                if abbv > 0usize && rv == 0usize {
                    buffer = cat(w.a, buffer, ".")
                    rv = checkword(w, buffer, info)
                    if rv == 0usize {
                        buffer = cat(w.a, scw, ".")
                        if cap == INITCAP { *info = *info + SP_INITCAP }
                        rv = checkword(w, buffer, info)
                        if cap == INITCAP { *info = *info - SP_INITCAP }
                        if rv != 0usize && is_keepcase(d, rv) && cap == ALLCAP { rv = 0usize }
                        skip_final = true
                    }
                }
                if !skip_final && rv != 0usize && is_keepcase(d, rv) { rv = 0usize }
            }
        }
    }
    if rv != 0usize {
        if d.warn != 0u16 && has_flag(d.entries[rv].flags, d.warn) {
            *info = *info + SP_WARN
            if d.forbidwarn { ret false }
            ret true
        }
        ret true
    }
    // recursive breaking at break points
    if d.breaks.len > 0usize && (*info & SP_FORBIDDEN) == 0u32 {
        var nbr = 0usize
        var j = 0usize
        while j < d.breaks.len {
            var pos = 0usize
            while true {
                let f = find_str(scw, d.breaks[j], pos)
                if f > scw.len || d.breaks[j].len == 0usize { break }
                nbr += 1usize
                pos = f + d.breaks[j].len
            }
            j += 1usize
        }
        if nbr >= 10usize { ret false }
        var wl = scw.len
        // boundary patterns
        j = 0usize
        while j < d.breaks.len {
            let br = d.breaks[j]
            let plen = br.len
            if plen == 1usize || plen > wl {
                j += 1usize
                continue
            }
            if br[0usize] == 94u8 && at_str(scw, 0usize, br[1usize..]) {
                if spell_sub(w, scw[plen - 1usize..]) { ret true }
            }
            if br[plen - 1usize] == 36u8 && at_str(scw, wl - plen + 1usize, br[..plen - 1usize]) {
                if spell_sub(w, scw[..wl - plen + 1usize]) { ret true }
            }
            j += 1usize
        }
        // other patterns, at the second occurrence then at the first
        var pass = 0usize
        while pass < 2usize {
            j = 0usize
            while j < d.breaks.len {
                let br = d.breaks[j]
                let plen = br.len
                var found = find_str(scw, br, 0usize)
                if found > 0usize && found < scw.len && found + plen < wl {
                    if pass == 0usize {
                        let found2 = find_str(scw, br, found + 1usize)
                        if found2 > 0usize && found2 < scw.len && found2 + plen < wl { found = found2 }
                    }
                    if spell_sub(w, scw[found + plen..]) {
                        if spell_sub(w, scw[..found]) { ret true }
                    }
                }
                j += 1usize
            }
            pass += 1usize
        }
    }
    ret false
}

fn spell_sub(w: *W, word: str) -> bool {
    var info = 0u32
    ret spell_info(w, word, &info)
}

// ---- public entry points ----------------------------------------------------------------------

// hunspell_check for one word.
fn spell(a: *mem.Arena, d: *Dict, word: str) -> bool {
    var wk = W { a: a, d: d, pfx: 0usize, sfx: 0usize }
    ret spell_sub(&wk, word)
}

fn conv_out_lines(w: *W, text: str) -> str {
    if !w.d.has_oconv { ret text }
    let lines = split_lines(w.a, text, 10u8)
    var out = buf_new(w.a)
    var i = 0usize
    while i < lines.len {
        if i > 0usize { buf_byte(&out, 10u8) }
        let (c, changed) = conv(w.a, w.d.oconv, lines[i])
        if changed {
            buf_str(&out, c)
        } else {
            buf_str(&out, lines[i])
        }
        i += 1usize
    }
    ret buf_done(&out)
}

fn cat_result(a: *mem.Arena, result: str, st: str) -> str {
    if st.len == 0usize { ret result }
    if result.len == 0usize { ret st }
    var b = buf_new(a)
    buf_str(&b, result)
    buf_byte(&b, 10u8)
    buf_str(&b, st)
    ret buf_done(&b)
}

// hunspell_analyze for one word: the analyses, one per line.
fn analyze(a: *mem.Arena, d: *Dict, word: str) -> str {
    var wk = W { a: a, d: d, pfx: 0usize, sfx: 0usize }
    let w = &wk
    if word.len >= 300usize { ret "" }
    let cl = cleanword2(w, convert_in(w, word))
    var scw = cl.word
    let cap = cl.cap
    var abbv = cl.abbv
    if scw.len == 0usize {
        if abbv > 0usize {
            var b = buf_new(a)
            var k = 0usize
            while k < abbv {
                buf_byte(&b, 46u8)
                k += 1usize
            }
            scw = buf_done(&b)
            abbv = 0usize
        } else {
            ret ""
        }
    }
    var result = ""
    if cap == HUHCAP || cap == HUHINITCAP || cap == NOCAP {
        result = cat_result(a, result, suggest_morph(w, scw))
        if abbv > 0usize { result = cat_result(a, result, suggest_morph(w, cat(a, scw, "."))) }
    } else if cap == INITCAP {
        let low = str_small(a, scw)
        let capd = str_initcap(a, low)
        result = cat_result(a, result, suggest_morph(w, low))
        result = cat_result(a, result, suggest_morph(w, capd))
        if abbv > 0usize {
            result = cat_result(a, result, suggest_morph(w, cat(a, low, ".")))
            result = cat_result(a, result, suggest_morph(w, cat(a, capd, ".")))
        }
    } else {
        result = cat_result(a, result, suggest_morph(w, scw))
        if abbv > 0usize { result = cat_result(a, result, suggest_morph(w, cat(a, scw, "."))) }
        let low = str_small(a, scw)
        let capd = str_initcap(a, low)
        result = cat_result(a, result, suggest_morph(w, low))
        result = cat_result(a, result, suggest_morph(w, capd))
        if abbv > 0usize {
            result = cat_result(a, result, suggest_morph(w, cat(a, low, ".")))
            result = cat_result(a, result, suggest_morph(w, cat(a, capd, ".")))
        }
    }
    if result.len == 0usize { ret "" }
    ret conv_out_lines(w, join_lines(a, split_lines(a, result, 10u8)))
}

fn join_lines(a: *mem.Arena, lines: []const str) -> str {
    var out = buf_new(a)
    var i = 0usize
    while i < lines.len {
        if i > 0usize { buf_byte(&out, 10u8) }
        buf_str(&out, lines[i])
        i += 1usize
    }
    ret buf_done(&out)
}

// The value of the field `tag` (such as "st:") in a morphological line, or "" when absent.
fn field(s: str, tag: str) -> (str, bool) {
    let at = find_str(s, tag, 0usize)
    if at > s.len { ret ("", false) }
    var i = at + tag.len
    let start = i
    while i < s.len && s[i] != 32u8 && s[i] != 9u8 && s[i] != 10u8 { i += 1usize }
    ret (s[start..i], true)
}

// hunspell_stem for one word: the distinct stems, one per line.
fn stem(a: *mem.Arena, d: *Dict, word: str) -> str {
    let lines = split_lines(a, analyze(a, d, word), 10u8)
    var out = new_list[str](a)
    var i = 0usize
    while i < lines.len {
        var s = lines[i]
        var prefix = ""
        // compound word parts but the last
        var part = find_str(s, "pa:", 0usize)
        if part < s.len {
            var next_part = find_str(s, "pa:", part + 1usize)
            while next_part < s.len {
                let (f, found) = field(s[part..], "pa:")
                if found { prefix = cat(a, prefix, f) }
                part = next_part
                next_part = find_str(s, "pa:", part + 1usize)
            }
            s = s[part..]
        }
        var piece = prefix
        let (sp, has_sp) = field(s, "sp:")
        if has_sp { piece = cat(a, piece, sp) }
        let (st, has_st) = field(s, "st:")
        if has_st { piece = cat(a, piece, st) }
        if piece.len > 0usize {
            var dup = false
            var j = 0usize
            while j < out.len {
                if same(out.items[j], piece) { dup = true }
                j += 1usize
            }
            if !dup { push_str(&out, piece) }
        }
        i += 1usize
    }
    ret join_lines(a, list.slice[str](&out))
}
// ---- two-level (continuation class) affixes ---------------------------------------------------

fn iscont(d: *const Dict, f: u16) -> bool { ret has_flag(d.contflags, f) }

// SfxEntry::check_twosfx
fn sfx_twosfx_entry(w: *W, si: usize, word: str, optflags: u32, ppfx: usize, needflag: u16) -> usize {
    let d = w.d
    let af = aff_at(d, si)
    if (optflags & 1u32) != 0u32 && !af.cross { ret 0usize }
    let (good, tmpword) = sfx_root(w, af, word)
    if !good { ret 0usize }
    if ppfx != 0usize {
        if has_flag(af.cont, aff_at(d, ppfx).flag) { ret suffix_check(w, tmpword, 0u32, 0usize, af.flag, needflag, IN_NOT) }
        ret suffix_check(w, tmpword, optflags, ppfx, af.flag, needflag, IN_NOT)
    }
    ret suffix_check(w, tmpword, 0u32, 0usize, af.flag, needflag, IN_NOT)
}

// AffixMgr::suffix_check_twosfx
fn suffix_check_twosfx(w: *W, word: str, sfxopts: u32, ppfx: usize, needflag: u16) -> usize {
    let d = w.d
    var i = 0usize
    while i < d.sfx0.len {
        let si = d.sfx0[i]
        if iscont(d, aff_at(d, si).flag) {
            let r = sfx_twosfx_entry(w, si, word, sfxopts, ppfx, needflag)
            if r != 0usize { ret r }
        }
        i += 1usize
    }
    if word.len == 0usize { ret 0usize }
    let sp = usize(word[word.len - 1usize])
    var k = d.sfx_from[sp]
    let stop = d.sfx_from[sp + 1usize]
    while k < stop {
        let si = d.sfx_sorted[k]
        let af = aff_at(d, si)
        if key_is_rev_subset(af.key, word) && iscont(d, af.flag) {
            let r = sfx_twosfx_entry(w, si, word, sfxopts, ppfx, needflag)
            if r != 0usize { ret r }
        }
        k += 1usize
    }
    ret 0usize
}

// PfxEntry::check_twosfx
fn pfx_twosfx_entry(w: *W, pi: usize, word: str, in_cpd: u8, needflag: u16) -> usize {
    let d = w.d
    let af = aff_at(d, pi)
    if word.len < af.appnd.len { ret 0usize }
    let tmpl = word.len - af.appnd.len
    if !(tmpl > 0usize || (tmpl == 0usize && d.fullstrip)) || tmpl + af.strip.len < af.numconds { ret 0usize }
    let tmpword = cat(w.a, af.strip, word[af.appnd.len..])
    if !cond_prefix(af, tmpword) { ret 0usize }
    if af.cross && in_cpd != IN_BEGIN { ret suffix_check_twosfx(w, tmpword, 1u32, pi, needflag) }
    ret 0usize
}

// AffixMgr::prefix_check_twosfx
fn prefix_check_twosfx(w: *W, word: str, in_cpd: u8, needflag: u16) -> usize {
    let d = w.d
    w.pfx = 0usize
    var i = 0usize
    while i < d.pfx0.len {
        let r = pfx_twosfx_entry(w, d.pfx0[i], word, in_cpd, needflag)
        if r != 0usize { ret r }
        i += 1usize
    }
    if word.len == 0usize { ret 0usize }
    let sp = usize(word[0usize])
    var k = d.pfx_from[sp]
    let stop = d.pfx_from[sp + 1usize]
    while k < stop {
        let pi = d.pfx_sorted[k]
        if key_is_subset(aff_at(d, pi).key, word) {
            let r = pfx_twosfx_entry(w, pi, word, in_cpd, needflag)
            if r != 0usize {
                w.pfx = pi
                ret r
            }
        }
        k += 1usize
    }
    ret 0usize
}

// mychomp: one trailing newline off.
fn chomp1(s: str) -> str {
    if s.len > 0usize && (s[s.len - 1usize] == 10u8 || s[s.len - 1usize] == 13u8) { ret s[..s.len - 1usize] }
    ret s
}

// SfxEntry::check_twosfx_morph
fn sfx_twosfx_morph_entry(w: *W, si: usize, word: str, optflags: u32, ppfx: usize, needflag: u16) -> str {
    let d = w.d
    let af = aff_at(d, si)
    if (optflags & 1u32) != 0u32 && !af.cross { ret "" }
    let (good, tmpword) = sfx_root(w, af, word)
    if !good { ret "" }
    var out = buf_new(w.a)
    var st = buf_new(w.a)
    if ppfx != 0usize && has_flag(af.cont, aff_at(d, ppfx).flag) {
        suffix_check_morph(w, tmpword, 0u32, 0usize, af.flag, needflag, IN_NOT, &st)
        if st.len > 0usize {
            let pf = aff_at(d, ppfx)
            if pf.morph.len > 0usize {
                buf_str(&out, pf.morph)
                buf_byte(&out, 32u8)
            }
            buf_str(&out, buf_done(&st))
            ret chomp1(buf_done(&out))
        }
        ret ""
    }
    if ppfx != 0usize {
        suffix_check_morph(w, tmpword, optflags, ppfx, af.flag, needflag, IN_NOT, &st)
    } else {
        suffix_check_morph(w, tmpword, 0u32, 0usize, af.flag, needflag, IN_NOT, &st)
    }
    if st.len > 0usize {
        buf_str(&out, buf_done(&st))
        ret chomp1(buf_done(&out))
    }
    ret ""
}

fn sfx_label(w: *W, af: *const Aff) -> str {
    var b = buf_new(w.a)
    if af.morph.len > 0usize {
        buf_byte(&b, 32u8)
        buf_str(&b, af.morph)
    } else {
        debugflag(w, &b, af.flag)
    }
    ret buf_done(&b)
}

// strlinecat: `apd` before every newline of `s` and at its end.
fn strlinecat(a: *mem.Arena, s: str, apd: str) -> str {
    var b = buf_new(a)
    var i = 0usize
    while i < s.len {
        if s[i] == 10u8 { buf_str(&b, apd) }
        buf_byte(&b, s[i])
        i += 1usize
    }
    buf_str(&b, apd)
    ret buf_done(&b)
}

// AffixMgr::suffix_check_twosfx_morph
fn suffix_check_twosfx_morph(w: *W, word: str, sfxopts: u32, ppfx: usize, needflag: u16, out: *Buf) {
    let d = w.d
    var i = 0usize
    while i < d.sfx0.len {
        let si = d.sfx0[i]
        let af = aff_at(d, si)
        if iscont(d, af.flag) {
            let st = sfx_twosfx_morph_entry(w, si, word, sfxopts, ppfx, needflag)
            if st.len > 0usize {
                if ppfx != 0usize {
                    let pf = aff_at(d, ppfx)
                    if pf.morph.len > 0usize {
                        buf_str(out, pf.morph)
                        buf_byte(out, 32u8)
                    } else {
                        debugflag(w, out, pf.flag)
                    }
                }
                buf_str(out, st)
                buf_str(out, sfx_label(w, af))
                buf_byte(out, 10u8)
            }
        }
        i += 1usize
    }
    if word.len == 0usize { ret }
    let sp = usize(word[word.len - 1usize])
    var k = d.sfx_from[sp]
    let stop = d.sfx_from[sp + 1usize]
    while k < stop {
        let si = d.sfx_sorted[k]
        let af = aff_at(d, si)
        if key_is_rev_subset(af.key, word) && iscont(d, af.flag) {
            let st = sfx_twosfx_morph_entry(w, si, word, sfxopts, ppfx, needflag)
            if st.len > 0usize {
                buf_str(out, strlinecat(w.a, st, sfx_label(w, af)))
                buf_byte(out, 10u8)
            }
        }
        k += 1usize
    }
}

// PfxEntry::check_twosfx_morph
fn pfx_twosfx_morph_entry(w: *W, pi: usize, word: str, in_cpd: u8, needflag: u16, out: *Buf) {
    let d = w.d
    let af = aff_at(d, pi)
    if word.len < af.appnd.len { ret }
    let tmpl = word.len - af.appnd.len
    if !(tmpl > 0usize || (tmpl == 0usize && d.fullstrip)) || tmpl + af.strip.len < af.numconds { ret }
    let tmpword = cat(w.a, af.strip, word[af.appnd.len..])
    if !cond_prefix(af, tmpword) { ret }
    if af.cross && in_cpd != IN_BEGIN { suffix_check_twosfx_morph(w, tmpword, 1u32, pi, needflag, out) }
}

// AffixMgr::prefix_check_twosfx_morph
fn prefix_check_twosfx_morph(w: *W, word: str, in_cpd: u8, needflag: u16, out: *Buf) {
    let d = w.d
    var i = 0usize
    while i < d.pfx0.len {
        pfx_twosfx_morph_entry(w, d.pfx0[i], word, in_cpd, needflag, out)
        i += 1usize
    }
    if word.len == 0usize { ret }
    let sp = usize(word[0usize])
    var k = d.pfx_from[sp]
    let stop = d.pfx_from[sp + 1usize]
    while k < stop {
        let pi = d.pfx_sorted[k]
        if key_is_subset(aff_at(d, pi).key, word) { pfx_twosfx_morph_entry(w, pi, word, in_cpd, needflag, out) }
        k += 1usize
    }
}


// ---- suggestions -----------------------------------------------------------------------------

const NG_LONGER_WORSE: u32 = 1u32
const NG_ANY_MISMATCH: u32 = 2u32
const NG_WEIGHTED: u32 = 8u32
fn default_key() -> str { ret "qwertyuiop|asdfghjkl|zxcvbnm" }

fn iabs(x: i32) -> i32 {
    if x < 0i32 { ret 0i32 - x }
    ret x
}

// SuggestMgr::checkword
fn sm_checkword(w: *W, word: str, cpd: i32) -> i32 {
    let d = w.d
    let mk = mem.mark(w.a)
    let r = sm_checkword_inner(w, word, cpd)
    mem.reset(w.a, mk)
    ret r
}

fn sm_checkword_inner(w: *W, word: str, cpd: i32) -> i32 {
    let d = w.d
    if cpd == 1i32 {
        if has_compound(d) {
            let rwords = alloc[usize](w.a, 101usize)
            var z = 0usize
            while z < rwords.len {
                rwords[z] = 0usize
                z += 1usize
            }
            let rv = compound_check(w, word, 0i32, 100i32, 0usize, false, rwords, true)
            if rv != 0usize {
                let rv2 = lookup(d, word)
                if rv2 == 0usize || d.entries[rv2].flags.len == 0usize || !(has_flag(d.entries[rv2].flags, d.forbidden) || has_flag(d.entries[rv2].flags, d.nosuggest)) { ret 3i32 }
            }
        }
        ret 0i32
    }
    var rv = lookup(d, word)
    if rv != 0usize {
        let flags = d.entries[rv].flags
        if has_flag(flags, d.forbidden) || has_flag(flags, d.nosuggest) || has_flag(flags, d.substandard) { ret 0i32 }
        while rv != 0usize {
            let f2 = d.entries[rv].flags
            if has_flag(f2, d.needaffix) || has_flag(f2, ONLYUPCASE) || has_flag(f2, d.onlyincompound) {
                rv = d.entries[rv].homonym
            } else {
                break
            }
        }
    } else {
        rv = prefix_check(w, word, IN_NOT, 0u16)
    }
    if rv == 0usize { rv = suffix_check(w, word, 0u32, 0usize, 0u16, 0u16, IN_NOT) }
    if rv == 0usize && d.havecont {
        rv = suffix_check_twosfx(w, word, 0u32, 0usize, 0u16)
        if rv == 0usize { rv = prefix_check_twosfx(w, word, IN_NOT, 0u16) }
    }
    if rv != 0usize {
        let flags = d.entries[rv].flags
        if has_flag(flags, d.forbidden) || has_flag(flags, ONLYUPCASE) || has_flag(flags, d.nosuggest) || has_flag(flags, d.onlyincompound) { ret 0i32 }
        ret 1i32
    }
    ret 0i32
}

fn max_sug() -> usize { ret MAX_SUGS }

fn in_list(l: *const list.List[str], s: str) -> bool {
    var k = 0usize
    while k < l.len {
        if same(l.items[k], s) { ret true }
        k += 1usize
    }
    ret false
}

// SuggestMgr::testsug
fn testsug(w: *W, wl: *list.List[str], cand: str, cpd: i32) {
    if wl.len == max_sug() { ret }
    if in_list(wl, cand) { ret }
    if sm_checkword(w, cand, cpd) != 0i32 { push_str(wl, copy_str(w.a, cand)) }
}

fn testsug_cp(w: *W, wl: *list.List[str], cps: []const u32, cpd: i32) {
    if wl.len == max_sug() { ret }
    let mk = mem.mark(w.a)
    let cand = cp_encode(w.a, cps)
    if !in_list(wl, cand) {
        if sm_checkword(w, cand, cpd) != 0i32 {
            push_str(wl, cand)
            ret
        }
    }
    mem.reset(w.a, mk)
}

fn copy_cps(a: *mem.Arena, c: []const u32) -> []u32 {
    let out = alloc[u32](a, c.len)
    var i = 0usize
    while i < c.len {
        out[i] = c[i]
        i += 1usize
    }
    ret out
}

fn capchars(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    let c = copy_cps(w.a, word)
    all_cap(c)
    testsug_cp(w, wl, c, cpd)
}

fn replchars(w: *W, wl: *list.List[str], word: str, cpd: i32) {
    let d = w.d
    if word.len < 2usize { ret }
    var i = 0usize
    while i < d.rep.len {
        let r = &d.rep[i]
        var at = 0usize
        while r.pattern.len > 0usize {
            let f = find_str(word, r.pattern, at)
            if f > word.len { break }
            var kind = 0usize
            if f == 0usize { kind = 1usize }
            if f + r.pattern.len == word.len { kind += 2usize }
            while kind != 0usize && r.out[kind].len == 0usize {
                if kind == 2usize && f != 0usize {
                    kind = 0usize
                } else {
                    kind -= 1usize
                }
            }
            let outs = r.out[kind]
            if outs.len == 0usize {
                at = f + 1usize
                continue
            }
            var b = buf_new(w.a)
            buf_str(&b, word[..f])
            buf_str(&b, outs)
            buf_str(&b, word[f + r.pattern.len..])
            let cand = buf_done(&b)
            testsug(w, wl, cand, cpd)
            // REP suggestions with a space
            var sp = find_str(cand, " ", 0usize)
            if sp <= cand.len {
                var prev = 0usize
                while sp <= cand.len {
                    let chunk = cand[prev..sp]
                    if sm_checkword(w, chunk, 0i32) != 0i32 {
                        let oldns = wl.len
                        testsug(w, wl, cand[sp + 1usize..], cpd)
                        if oldns < wl.len { wl.items[wl.len - 1usize] = cand }
                    }
                    prev = sp + 1usize
                    sp = find_str(cand, " ", prev)
                }
            }
            at = f + 1usize
        }
        i += 1usize
    }
}

// map_related
fn map_related(w: *W, wl: *list.List[str], word: str, cand: str, wn: usize, cpd: i32) {
    let d = w.d
    if wn >= word.len {
        if !in_list(wl, cand) && sm_checkword(w, cand, cpd) != 0i32 {
            if wl.len < max_sug() { push_str(wl, copy_str(w.a, cand)) }
        }
        ret
    }
    var in_map = false
    var j = 0usize
    while j < d.maps.len {
        var k = 0usize
        while k < d.maps[j].len {
            let item = d.maps[j][k]
            if at_str(word, wn, item) {
                in_map = true
                var l = 0usize
                while l < d.maps[j].len {
                    map_related(w, wl, word, cat(w.a, cand, d.maps[j][l]), wn + item.len, cpd)
                    l += 1usize
                }
            }
            k += 1usize
        }
        j += 1usize
    }
    if !in_map { map_related(w, wl, word, cat(w.a, cand, word[wn..wn + 1usize]), wn + 1usize, cpd) }
}

fn mapchars(w: *W, wl: *list.List[str], word: str, cpd: i32) {
    if word.len < 2usize || w.d.maps.len == 0usize { ret }
    map_related(w, wl, word, "", 0usize, cpd)
}

fn swap_cp(c: []u32, i: usize, j: usize) {
    let t = c[i]
    c[i] = c[j]
    c[j] = t
}

fn swapchar(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    if word.len < 2usize { ret }
    let c = copy_cps(w.a, word)
    var i = 0usize
    while i + 1usize < c.len {
        swap_cp(c, i, i + 1usize)
        testsug_cp(w, wl, c, cpd)
        swap_cp(c, i, i + 1usize)
        i += 1usize
    }
    if c.len == 4usize || c.len == 5usize {
        c[0usize] = word[1usize]
        c[1usize] = word[0usize]
        c[2usize] = word[2usize]
        c[c.len - 2usize] = word[c.len - 1usize]
        c[c.len - 1usize] = word[c.len - 2usize]
        testsug_cp(w, wl, c, cpd)
        if c.len == 5usize {
            c[0usize] = word[0usize]
            c[1usize] = word[2usize]
            c[2usize] = word[1usize]
            testsug_cp(w, wl, c, cpd)
        }
    }
}

fn longswapchar(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    let c = copy_cps(w.a, word)
    var p = 0usize
    while p < c.len {
        var q = 0usize
        while q < c.len {
            var dist = 0usize
            if q > p {
                dist = q - p
            } else {
                dist = p - q
            }
            if dist > 1usize && dist <= 4usize {
                swap_cp(c, p, q)
                testsug_cp(w, wl, c, cpd)
                swap_cp(c, p, q)
            }
            q += 1usize
        }
        p += 1usize
    }
}

fn restore_cps(c: []u32, word: []const u32) {
    var i = 0usize
    while i < c.len {
        c[i] = word[i]
        i += 1usize
    }
}

fn movechar(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    if word.len < 2usize { ret }
    let c = copy_cps(w.a, word)
    let n = c.len
    // forward: move the character at p to the right
    var p = 0usize
    while p < n {
        var q = p + 1usize
        while q < n && q - p <= 4usize {
            swap_cp(c, q, q - 1usize)
            if q - p >= 2usize { testsug_cp(w, wl, c, cpd) }
            q += 1usize
        }
        restore_cps(c, word)
        p += 1usize
    }
    // backward: move the character at p to the left (p counts from the end)
    var rp = 0usize
    while rp < n {
        var rq = rp + 1usize
        while rq < n && rq - rp <= 4usize {
            // reverse iterator positions rp, rq map to indexes n-1-rp, n-1-rq; swap(*q, *(q-1)) in
            // reverse terms exchanges index n-1-rq with n-rq
            swap_cp(c, n - 1usize - rq, n - rq)
            if rq - rp >= 2usize { testsug_cp(w, wl, c, cpd) }
            rq += 1usize
        }
        restore_cps(c, word)
        rp += 1usize
    }
}

fn badcharkey(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    let d = w.d
    var key = d.key
    if !d.has_key { key = cp_decode(w.a, default_key()) }
    let c = copy_cps(w.a, word)
    var i = 0usize
    while i < c.len {
        let tmpc = c[i]
        c[i] = cp_upper(c[i])
        if tmpc != c[i] {
            testsug_cp(w, wl, c, cpd)
            c[i] = tmpc
        }
        var loc = 0usize
        while loc < key.len && key[loc] != tmpc { loc += 1usize }
        while loc < key.len {
            if loc > 0usize && key[loc - 1usize] != 124u32 {
                c[i] = key[loc - 1usize]
                testsug_cp(w, wl, c, cpd)
            }
            if loc + 1usize < key.len && key[loc + 1usize] != 124u32 {
                c[i] = key[loc + 1usize]
                testsug_cp(w, wl, c, cpd)
            }
            loc += 1usize
            while loc < key.len && key[loc] != tmpc { loc += 1usize }
        }
        c[i] = tmpc
        i += 1usize
    }
}

fn extrachar(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    if word.len < 2usize { ret }
    var i = 0usize
    while i < word.len {
        let index = word.len - 1usize - i
        let c = alloc[u32](w.a, word.len - 1usize)
        var k = 0usize
        var m = 0usize
        while k < word.len {
            if k != index {
                c[m] = word[k]
                m += 1usize
            }
            k += 1usize
        }
        testsug_cp(w, wl, c, cpd)
        i += 1usize
    }
}

fn forgotchar(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    let d = w.d
    var k = 0usize
    while k < d.try_chars.len {
        var i = 0usize
        while i <= word.len {
            let index = word.len - i
            let c = alloc[u32](w.a, word.len + 1usize)
            var m = 0usize
            var q = 0usize
            while q <= word.len {
                if q == index {
                    c[m] = d.try_chars[k]
                    m += 1usize
                }
                if q < word.len {
                    c[m] = word[q]
                    m += 1usize
                }
                q += 1usize
            }
            testsug_cp(w, wl, c, cpd)
            i += 1usize
        }
        k += 1usize
    }
}

fn badchar(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    let d = w.d
    let c = copy_cps(w.a, word)
    var j = 0usize
    while j < d.try_chars.len {
        var i = c.len
        while i > 0usize {
            i -= 1usize
            let tmpc = c[i]
            if tmpc == d.try_chars[j] { continue }
            c[i] = d.try_chars[j]
            testsug_cp(w, wl, c, cpd)
            c[i] = tmpc
        }
        j += 1usize
    }
}

fn doubletwochars(w: *W, wl: *list.List[str], word: []const u32, cpd: i32) {
    if word.len < 5usize { ret }
    var state = 0i32
    var i = 2usize
    while i < word.len {
        if word[i] == word[i - 2usize] {
            state += 1i32
            if state == 3i32 || (state == 2i32 && i >= 4usize) {
                let c = alloc[u32](w.a, word.len - 2usize)
                var m = 0usize
                var k = 0usize
                while k < word.len {
                    if k != i - 1usize && k != i {
                        c[m] = word[k]
                        m += 1usize
                    }
                    k += 1usize
                }
                testsug_cp(w, wl, c, cpd)
                state = 0i32
            }
        } else {
            state = 0i32
        }
        i += 1usize
    }
}

// SuggestMgr::twowords
fn twowords(w: *W, wl: *list.List[str], word: str, cpd: i32, good_in: bool) -> bool {
    let d = w.d
    var good = good_in
    if word.len < 3usize { ret false }
    var cwrd = true
    var at = 0usize
    while true {
        // the next character boundary
        var next = at + 1usize
        while next < word.len && (word[next] & 192u8) == 128u8 { next += 1usize }
        if next >= word.len { break }
        let first = word[..next]
        let second = word[next..]
        let spaced = cat(w.a, cat(w.a, first, " "), second)
        if cpd == 0i32 && sm_checkword(w, spaced, cpd) != 0i32 {
            if !good {
                good = true
                wl.len = 0usize
            }
            if list.insert[str](wl, 0usize, copy_str(w.a, spaced)) != ok { os.exit(5) }
        }
        if d.lang_with_dash {
            let dashed = cat(w.a, cat(w.a, first, "-"), second)
            if cpd == 0i32 && sm_checkword(w, dashed, cpd) != 0i32 {
                if !good {
                    good = true
                    wl.len = 0usize
                }
                if list.insert[str](wl, 0usize, copy_str(w.a, dashed)) != ok { os.exit(5) }
            }
        }
        if wl.len < max_sug() && !d.nosplitsugs && !good {
            let c1 = sm_checkword(w, first, cpd)
            if c1 != 0i32 {
                let c2 = sm_checkword(w, second, cpd)
                if c2 != 0i32 {
                    let spaced2 = cat(w.a, cat(w.a, first, " "), second)
                    cwrd = !in_list(wl, spaced2)
                    if cwrd && wl.len < max_sug() { push_str(wl, copy_str(w.a, spaced2)) }
                    if !d.nosplitsugs && d.lang_with_dash && cp_decode(w.a, second).len > 1usize && cp_decode(w.a, first).len > 1usize {
                        let dashed2 = cat(w.a, cat(w.a, first, "-"), second)
                        if in_list(wl, dashed2) { cwrd = false }
                        if wl.len < max_sug() && cwrd { push_str(wl, copy_str(w.a, dashed2)) }
                    }
                }
            }
        }
        at = next
    }
    ret good
}

// SuggestMgr::suggest: true when there is a good suggestion.
fn sm_suggest(w: *W, wl: *list.List[str], word: str, onlycpd: *bool) -> bool {
    let d = w.d
    var maxcpd = 3usize
    if d.maxcpdsugs >= 0i32 { maxcpd = usize(d.maxcpdsugs) }
    let cps = cp_decode(w.a, word)
    var nocompoundtwowords = false
    let nsugorig = wl.len
    var oldsug = 0usize
    var good = false
    var cpd = 0i32
    while cpd < 2i32 && !nocompoundtwowords && !good {
        if cpd > 0i32 { oldsug = wl.len }
        if wl.len < max_sug() {
            let i = wl.len
            capchars(w, wl, cps, cpd)
            if wl.len > i { good = true }
        }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) {
            let i = wl.len
            replchars(w, wl, word, cpd)
            if wl.len > i { good = true }
        }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { mapchars(w, wl, word, cpd) }
        if cpd == 0i32 && wl.len > nsugorig { nocompoundtwowords = true }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { swapchar(w, wl, cps, cpd) }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { longswapchar(w, wl, cps, cpd) }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { badcharkey(w, wl, cps, cpd) }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { extrachar(w, wl, cps, cpd) }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { forgotchar(w, wl, cps, cpd) }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { movechar(w, wl, cps, cpd) }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { badchar(w, wl, cps, cpd) }
        if wl.len < max_sug() && (cpd == 0i32 || wl.len < oldsug + maxcpd) { doubletwochars(w, wl, cps, cpd) }
        if cpd == 0i32 || (!d.nosplitsugs && wl.len < oldsug + maxcpd) { good = twowords(w, wl, word, cpd, good) }
        cpd += 1i32
    }
    if !nocompoundtwowords && wl.len > 0usize { *onlycpd = true }
    ret good
}

// ---- n-gram suggestions ----------------------------------------------------------------------

fn ngram(n: usize, s1: []const u32, s2: []const u32, opt: u32) -> i32 {
    let l1 = i32(s1.len)
    let l2 = i32(s2.len)
    if l2 == 0i32 { ret 0i32 }
    var nscore = 0i32
    var j = 1i32
    while j <= i32(n) {
        var ns = 0i32
        var i = 0i32
        while i <= l1 - j {
            var found = false
            var l = 0i32
            while l <= l2 - j && !found {
                var k = 0i32
                while k < j {
                    if s1[usize(i + k)] != s2[usize(l + k)] { break }
                    k += 1i32
                }
                if k == j { found = true }
                l += 1i32
            }
            if found {
                ns += 1i32
            } else if (opt & NG_WEIGHTED) != 0u32 {
                ns -= 1i32
                if i == 0i32 || i == l1 - j { ns -= 1i32 }
            }
            i += 1i32
        }
        nscore += ns
        if ns < 2i32 && (opt & NG_WEIGHTED) == 0u32 { break }
        j += 1i32
    }
    var ns = 0i32
    if (opt & NG_LONGER_WORSE) != 0u32 { ns = (l2 - l1) - 2i32 }
    if (opt & NG_ANY_MISMATCH) != 0u32 { ns = iabs(l2 - l1) - 2i32 }
    var cut = 0i32
    if ns > 0i32 { cut = ns }
    ret nscore - cut
}

fn leftcommon(s1: []const u32, s2: []const u32) -> i32 {
    var idx = 0u32
    var other = 0u32
    if s2.len > 0usize { idx = s2[0usize] }
    if s1.len > 0usize { other = s1[0usize] }
    if other != idx && other != cp_lower(idx) { ret 0i32 }
    var i = 1usize
    while i < s1.len && i < s2.len && s1[i] == s2[i] { i += 1usize }
    ret i32(i)
}

fn lcslen(a: *mem.Arena, s: []const u32, s2: []const u32) -> i32 {
    let m = s.len
    let n = s2.len
    let c = alloc[i32](a, (m + 1usize) * (n + 1usize))
    var j = 0usize
    while j <= n {
        c[j] = 0i32
        j += 1usize
    }
    var i = 1usize
    while i <= m {
        c[i * (n + 1usize)] = 0i32
        j = 1usize
        while j <= n {
            if s[i - 1usize] == s2[j - 1usize] {
                c[i * (n + 1usize) + j] = c[(i - 1usize) * (n + 1usize) + j - 1usize] + 1i32
            } else if c[(i - 1usize) * (n + 1usize) + j] >= c[i * (n + 1usize) + j - 1usize] {
                c[i * (n + 1usize) + j] = c[(i - 1usize) * (n + 1usize) + j]
            } else {
                c[i * (n + 1usize) + j] = c[i * (n + 1usize) + j - 1usize]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret c[m * (n + 1usize) + n]
}

// commoncharacterpositions: (count, is_swap)
fn commoncharpos(s1: []const u32, s2raw: []const u32) -> (i32, bool) {
    if s1.len == 0usize || s2raw.len == 0usize { ret (0i32, false) }
    var num = 0i32
    var diff = 0i32
    var dp0 = 0usize
    var dp1 = 0usize
    var i = 0usize
    while i < s1.len && i < s2raw.len {
        var c2 = s2raw[i]
        if i == 0usize { c2 = cp_lower(c2) }
        if s1[i] == c2 {
            num += 1i32
        } else {
            if diff == 0i32 { dp0 = i }
            if diff == 1i32 { dp1 = i }
            diff += 1i32
        }
        i += 1usize
    }
    var is_swap = false
    if diff == 2i32 && s1.len == s2raw.len {
        var a0 = s2raw[dp0]
        var a1 = s2raw[dp1]
        if dp0 == 0usize { a0 = cp_lower(a0) }
        if dp1 == 0usize { a1 = cp_lower(a1) }
        if s1[dp0] == a1 && s1[dp1] == a0 { is_swap = true }
    }
    ret (num, is_swap)
}

type Guess = struct { word: str, orig: str, has_orig: bool, allow: bool }

fn push_guess(l: *list.List[Guess], g: Guess) {
    if list.push[Guess](l, g) != ok { os.exit(5) }
}

// AffixMgr::expand_rootword
fn expand_rootword(w: *W, out: *list.List[Guess], ts: str, flags: []const u16, bad: str) {
    let d = w.d
    let maxn = MAX_WORDS
    if out.len < maxn && !(flags.len > 0usize && (has_flag(flags, d.needaffix) || has_flag(flags, d.onlyincompound))) {
        push_guess(out, Guess { word: ts, orig: "", has_orig: false, allow: false })
    }
    var i = 0usize
    while i < flags.len {
        var ai = d.affs.len
        while ai > 0usize {
            ai -= 1usize
            let af = &d.affs[ai]
            if af.pfx || af.flag != flags[i] { continue }
            if !(af.key.len == 0usize || (bad.len > af.key.len && at_str(bad, bad.len - af.key.len, af.appnd))) { continue }
            if has_flag(af.cont, d.needaffix) || has_flag(af.cont, d.onlyincompound) { continue }
            // SfxEntry::add
            if !(ts.len > af.strip.len || (ts.len == 0usize && d.fullstrip)) { continue }
            if ts.len < af.numconds || !cond_suffix(af, ts) { continue }
            if af.strip.len > 0usize && !at_str(ts, ts.len - af.strip.len, af.strip) { continue }
            let nw = cat(w.a, ts[..ts.len - af.strip.len], af.appnd)
            if nw.len > 0usize && out.len < maxn { push_guess(out, Guess { word: nw, orig: "", has_orig: false, allow: af.cross }) }
        }
        i += 1usize
    }
    let n = out.len
    var j = 1usize
    while j < n {
        if out.items[j].allow {
            var k = 0usize
            while k < flags.len {
                var ai = d.affs.len
                while ai > 0usize {
                    ai -= 1usize
                    let af = &d.affs[ai]
                    if !af.pfx || af.flag != flags[k] || !af.cross { continue }
                    if !(af.key.len == 0usize || (bad.len > af.key.len && at_str(bad, 0usize, af.key))) { continue }
                    let base = out.items[j].word
                    if !(base.len > af.strip.len || (base.len == 0usize && d.fullstrip)) { continue }
                    if base.len < af.numconds || !cond_prefix(af, base) { continue }
                    if af.strip.len > 0usize && !at_str(base, 0usize, af.strip) { continue }
                    let nw = cat(w.a, af.appnd, base[af.strip.len..])
                    if nw.len > 0usize && out.len < maxn { push_guess(out, Guess { word: nw, orig: "", has_orig: false, allow: af.cross }) }
                }
                k += 1usize
            }
        }
        j += 1usize
    }
    var m = 0usize
    while m < flags.len {
        var ai = d.affs.len
        while ai > 0usize {
            ai -= 1usize
            let af = &d.affs[ai]
            if !af.pfx || af.flag != flags[m] { continue }
            if !(af.key.len == 0usize || (bad.len > af.key.len && at_str(bad, 0usize, af.key))) { continue }
            if has_flag(af.cont, d.needaffix) || has_flag(af.cont, d.onlyincompound) { continue }
            if !(ts.len > af.strip.len || (ts.len == 0usize && d.fullstrip)) { continue }
            if ts.len < af.numconds || !cond_prefix(af, ts) { continue }
            if af.strip.len > 0usize && !at_str(ts, 0usize, af.strip) { continue }
            let nw = cat(w.a, af.appnd, ts[af.strip.len..])
            if nw.len > 0usize && out.len < maxn { push_guess(out, Guess { word: nw, orig: "", has_orig: false, allow: af.cross }) }
        }
        m += 1usize
    }
}

fn bubblesort_guess(guess: []Guess, gscore: []i32, hasg: []bool, n: usize) {
    var m = 1usize
    while m < n {
        var j = m
        while j > 0usize {
            if gscore[j - 1usize] < gscore[j] {
                let sc = gscore[j - 1usize]
                gscore[j - 1usize] = gscore[j]
                gscore[j] = sc
                let g = guess[j - 1usize]
                guess[j - 1usize] = guess[j]
                guess[j] = g
                let h = hasg[j - 1usize]
                hasg[j - 1usize] = hasg[j]
                hasg[j] = h
                j -= 1usize
            } else {
                break
            }
        }
        m += 1usize
    }
}

fn ngsuggest(w: *W, wl: *list.List[str], word: str, cap: u8) {
    let d = w.d
    let a = w.a
    let roots = alloc[usize](a, MAX_ROOTS)
    let scores = alloc[i32](a, MAX_ROOTS)
    var i = 0usize
    while i < MAX_ROOTS {
        roots[i] = 0usize
        scores[i] = 0i32 - 100i32 * i32(i)
        i += 1usize
    }
    var lp = MAX_ROOTS - 1usize
    let w_word = cp_decode(a, word)
    let n = i32(w_word.len)
    var col = 0usize
    while col < d.table.len {
        var hp = d.table[col]
        while hp != 0usize {
            let en = &d.entries[hp]
            let nxt = en.next
            var skip = false
            if iabs(n - i32(en.clen)) > 4i32 { skip = true }
            if !skip && cap == NOCAP && en.initcap { skip = true }
            if !skip && en.flags.len > 0usize {
                if has_flag(en.flags, d.forbidden) || has_flag(en.flags, ONLYUPCASE) || has_flag(en.flags, d.nosuggest) || has_flag(en.flags, d.nongramsuggest) || has_flag(en.flags, d.onlyincompound) { skip = true }
            }
            if !skip {
                let mk = mem.mark(a)
                let wf = cp_decode(a, en.word)
                let lc = leftcommon(w_word, wf)
                all_small(wf)
                let sc = ngram(3usize, w_word, wf, NG_LONGER_WORSE) + lc
                mem.reset(a, mk)
                if sc > scores[lp] {
                    scores[lp] = sc
                    roots[lp] = hp
                    var lval = sc
                    var jj = 0usize
                    while jj < MAX_ROOTS {
                        if scores[jj] < lval {
                            lp = jj
                            lval = scores[jj]
                        }
                        jj += 1usize
                    }
                }
            }
            hp = nxt
        }
        col += 1usize
    }
    // the minimum acceptable score
    var thresh = 0i32
    var sp = 1usize
    while sp < 4usize {
        let mw = copy_cps(a, w_word)
        var k = sp
        while k < mw.len {
            mw[k] = 42u32
            k += 4usize
        }
        all_small(mw)
        thresh += ngram(w_word.len, w_word, mw, NG_ANY_MISMATCH)
        sp += 1usize
    }
    thresh = thresh / 3i32
    thresh -= 1i32
    let guess = alloc[Guess](a, MAX_GUESS)
    let hasg = alloc[bool](a, MAX_GUESS)
    let gscore = alloc[i32](a, MAX_GUESS)
    i = 0usize
    while i < MAX_GUESS {
        guess[i] = Guess { word: "", orig: "", has_orig: false, allow: false }
        hasg[i] = false
        gscore[i] = 0i32 - 100i32 * i32(i)
        i += 1usize
    }
    var glp = MAX_GUESS - 1usize
    i = 0usize
    while i < MAX_ROOTS {
        if roots[i] != 0usize {
            let rp = &d.entries[roots[i]]
            var glst = new_list[Guess](a)
            expand_rootword(w, &glst, rp.word, rp.flags, word)
            var k = 0usize
            while k < glst.len {
                let wf = cp_decode(a, glst.items[k].word)
                let lc = leftcommon(w_word, wf)
                all_small(wf)
                let sc = ngram(w_word.len, w_word, wf, NG_ANY_MISMATCH) + lc
                if sc > thresh {
                    if sc > gscore[glp] {
                        gscore[glp] = sc
                        guess[glp] = glst.items[k]
                        hasg[glp] = true
                        var lval = sc
                        var jj = 0usize
                        while jj < MAX_GUESS {
                            if gscore[jj] < lval {
                                glp = jj
                                lval = gscore[jj]
                            }
                            jj += 1usize
                        }
                    }
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    bubblesort_guess(guess, gscore, hasg, MAX_GUESS)
    var fact = 1.0f64
    if d.maxdiff >= 0i32 { fact = (10.0f64 - f64(d.maxdiff)) / 5.0f64 }
    i = 0usize
    while i < MAX_GUESS {
        if hasg[i] {
            let gl = cp_decode(a, guess[i].word)
            all_small(gl)
            let len = i32(gl.len)
            let lcs_len = lcslen(a, w_word, gl)
            if n == len && n == lcs_len {
                gscore[i] += 2000i32
                break
            }
            let wf = copy_cps(a, w_word)
            all_small(wf)
            var re = ngram(2usize, w_word, gl, NG_ANY_MISMATCH + NG_WEIGHTED)
            re += ngram(2usize, gl, wf, NG_ANY_MISMATCH + NG_WEIGHTED)
            let ngram_score = ngram(4usize, w_word, gl, NG_ANY_MISMATCH)
            let lcscore = leftcommon(w_word, gl)
            let (ccp, is_swap) = commoncharpos(w_word, gl)
            var total = 2i32 * lcs_len - iabs(n - len) + lcscore
            if ccp != 0i32 { total += 1i32 }
            if is_swap { total += 10i32 }
            total += ngram_score
            total += re
            if f64(re) < f64(n + len) * fact { total -= 1000i32 }
            gscore[i] = total
        }
        i += 1usize
    }
    bubblesort_guess(guess, gscore, hasg, MAX_GUESS)
    var maxng = 4usize
    if d.maxngramsugs >= 0i32 { maxng = usize(d.maxngramsugs) }
    let oldns = wl.len
    var same_flag = false
    i = 0usize
    while i < MAX_GUESS {
        if hasg[i] {
            if wl.len < oldns + maxng && wl.len < max_sug() && (!same_flag || gscore[i] > 1000i32) {
                var unique = true
                var skip_it = false
                if gscore[i] > 1000i32 {
                    same_flag = true
                } else if gscore[i] < -100i32 {
                    same_flag = true
                    if wl.len > oldns || d.onlymaxdiff { skip_it = true }
                }
                if !skip_it {
                    var j = 0usize
                    while j < wl.len {
                        var contains = false
                        if guess[i].has_orig {
                            contains = find_str(guess[i].orig, wl.items[j], 0usize) <= guess[i].orig.len
                        } else {
                            contains = find_str(guess[i].word, wl.items[j], 0usize) <= guess[i].word.len
                        }
                        if contains || sm_checkword(w, guess[i].word, 0i32) == 0i32 {
                            unique = false
                            break
                        }
                        j += 1usize
                    }
                    if unique {
                        if guess[i].has_orig {
                            push_str(wl, guess[i].orig)
                        } else {
                            push_str(wl, guess[i].word)
                        }
                    }
                }
            }
        }
        i += 1usize
    }
}

// ---- Hunspell::suggest ----------------------------------------------------------------------

fn insert_sug(wl: *list.List[str], s: str) {
    if list.insert[str](wl, 0usize, s) != ok { os.exit(5) }
}

fn suggest_internal(w: *W, word: str, wl: *list.List[str]) -> (bool, usize, u8) {
    let d = w.d
    let a = w.a
    var capwords = false
    if word.len >= 300usize { ret (false, 0usize, NOCAP) }
    let cl = cleanword2(w, convert_in(w, word))
    let scw = cl.word
    let cap = cl.cap
    let abbv = cl.abbv
    if scw.len == 0usize { ret (false, 0usize, cap) }
    var onlycpd = false
    var good = false
    let wl_chars = cp_decode(a, scw).len
    if cap == NOCAP {
        if sm_suggest(w, wl, scw, &onlycpd) { good = true }
        if abbv > 0usize {
            if sm_suggest(w, wl, cat(a, scw, "."), &onlycpd) { good = true }
        }
    } else if cap == INITCAP {
        capwords = true
        if sm_suggest(w, wl, scw, &onlycpd) { good = true }
        if sm_suggest(w, wl, str_small(a, scw), &onlycpd) { good = true }
    } else if cap == HUHCAP || cap == HUHINITCAP {
        if cap == HUHINITCAP { capwords = true }
        if sm_suggest(w, wl, scw, &onlycpd) { good = true }
        let dot = find_str(scw, ".", 0usize)
        if dot < scw.len {
            let postdot = scw[dot + 1usize..]
            if captype(cp_decode(a, postdot)) == INITCAP {
                insert_sug(wl, cat(a, cat(a, scw[..dot + 1usize], " "), postdot))
            }
        }
        if cap == HUHINITCAP {
            if sm_suggest(w, wl, str_initsmall(a, scw), &onlycpd) { good = true }
        }
        var wspace = str_small(a, scw)
        if spell_sub(w, wspace) { insert_sug(wl, wspace) }
        let prevns = wl.len
        if sm_suggest(w, wl, wspace, &onlycpd) { good = true }
        if cap == HUHINITCAP {
            wspace = str_initcap(a, wspace)
            if spell_sub(w, wspace) { insert_sug(wl, wspace) }
            if sm_suggest(w, wl, wspace, &onlycpd) { good = true }
        }
        var j = prevns
        while j < wl.len {
            let sp = find_str(wl.items[j], " ", 0usize)
            if sp < wl.items[j].len {
                let rest = wl.items[j][sp + 1usize..]
                let slen = rest.len
                var diff = false
                if slen < scw.len && !same(scw[scw.len - slen..], rest) { diff = true }
                if diff {
                    let first = wl.items[j][..sp + 1usize]
                    let second = str_initcap(a, rest)
                    // erase j and put the capitalised pair first
                    let removed = list.remove[str](wl, j)
                    insert_sug(wl, cat(a, first, second))
                }
            }
            j += 1usize
        }
    } else {
        var wspace = str_small(a, scw)
        if sm_suggest(w, wl, wspace, &onlycpd) { good = true }
        if d.keepcase != 0u16 && spell_sub(w, wspace) { insert_sug(wl, wspace) }
        wspace = str_initcap(a, wspace)
        if sm_suggest(w, wl, wspace, &onlycpd) { good = true }
        var j = 0usize
        while j < wl.len {
            wl.items[j] = str_cap(a, wl.items[j])
            j += 1usize
        }
    }
    // the n-gram approach when nothing good was found
    if !good && (wl.len == 0usize || onlycpd) && d.maxngramsugs != 0i32 {
        if cap == NOCAP {
            ngsuggest(w, wl, scw, NOCAP)
        } else if cap == HUHINITCAP || cap == HUHCAP {
            if cap == HUHINITCAP { capwords = true }
            ngsuggest(w, wl, str_small(a, scw), HUHCAP)
        } else if cap == INITCAP {
            capwords = true
            ngsuggest(w, wl, str_small(a, scw), INITCAP)
        } else {
            let oldns = wl.len
            ngsuggest(w, wl, str_small(a, scw), ALLCAP)
            var j = oldns
            while j < wl.len {
                wl.items[j] = str_cap(a, wl.items[j])
                j += 1usize
            }
        }
    }
    // dash suggestion (Afo-American -> Afro-American)
    var dash_pos = find_str(scw, "-", 0usize)
    if dash_pos < scw.len {
        var nodashsug = true
        var j = 0usize
        while j < wl.len && nodashsug {
            if has_byte(wl.items[j], 45u8) { nodashsug = false }
            j += 1usize
        }
        var prev_pos = 0usize
        var last = false
        while !good && nodashsug && !last {
            if dash_pos == scw.len { last = true }
            let chunk = scw[prev_pos..dash_pos]
            if !spell_sub(w, chunk) {
                var nl = new_list[str](a)
                let nres = suggest_words(w, chunk, &nl)
                var jj = nl.len
                while jj > 0usize {
                    jj -= 1usize
                    var wsp = cat(a, scw[..prev_pos], nl.items[jj])
                    if !last { wsp = cat(a, cat(a, wsp, "-"), scw[dash_pos + 1usize..]) }
                    var info = 0u32
                    if d.forbidden != 0u16 { let rr = checkword(w, wsp, &info) }
                    if (info & SP_FORBIDDEN) == 0u32 { insert_sug(wl, wsp) }
                }
                nodashsug = false
            }
            if !last {
                prev_pos = dash_pos + 1usize
                dash_pos = find_str(scw, "-", prev_pos)
            }
            if dash_pos > scw.len { dash_pos = scw.len }
        }
    }
    ret (capwords, abbv, cap)
}

// Hunspell::suggest: fills `wl`; the number of suggestions.
fn suggest_words(w: *W, word: str, wl: *list.List[str]) -> usize {
    let d = w.d
    let a = w.a
    let (capwords, abbv, cap) = suggest_internal(w, word, wl)
    if capwords {
        var j = 0usize
        while j < wl.len {
            wl.items[j] = str_initcap(a, wl.items[j])
            j += 1usize
        }
    }
    if abbv > 0usize && d.sugswithdots {
        var j = 0usize
        while j < wl.len {
            wl.items[j] = cat(a, wl.items[j], word[word.len - abbv..])
            j += 1usize
        }
    }
    if d.keepcase != 0u16 || d.forbidden != 0u16 {
        if cap == INITCAP || cap == ALLCAP {
            var l = 0usize
            var j = 0usize
            while j < wl.len {
                let s0 = wl.items[j]
                if !has_byte(s0, 32u8) && !spell_sub(w, s0) {
                    let s1 = str_small(a, s0)
                    if spell_sub(w, s1) {
                        wl.items[l] = s1
                        l += 1usize
                    } else {
                        let s2 = str_initcap(a, s1)
                        if spell_sub(w, s2) {
                            wl.items[l] = s2
                            l += 1usize
                        }
                    }
                } else {
                    wl.items[l] = s0
                    l += 1usize
                }
                j += 1usize
            }
            wl.len = l
        }
    }
    // remove duplications
    var l = 0usize
    var j = 0usize
    while j < wl.len {
        wl.items[l] = wl.items[j]
        var k = 0usize
        while k < l {
            if same(wl.items[k], wl.items[j]) {
                l -= 1usize
                break
            }
            k += 1usize
        }
        l += 1usize
        j += 1usize
    }
    wl.len = l
    if d.has_oconv {
        j = 0usize
        while j < wl.len {
            let (c, changed) = conv(a, d.oconv, wl.items[j])
            if changed { wl.items[j] = c }
            j += 1usize
        }
    }
    ret wl.len
}

// hunspell_suggest for one word: the suggestions, one per line.
fn suggest(a: *mem.Arena, d: *Dict, word: str) -> str {
    var wk = W { a: a, d: d, pfx: 0usize, sfx: 0usize }
    var wl = new_list[str](a)
    let n = suggest_words(&wk, word, &wl)
    ret join_lines(a, list.slice[str](&wl))
}

// ---- hunspell_find (text) ---------------------------------------------------------------------

fn latin1_entities() -> str { ret "&Agrave; &Atilde; &Aring; &AElig; &Egrave; &Ecirc; &Igrave; &Iuml; &ETH; &Ntilde; &Ograve; &Oslash; &Ugrave; &THORN; &agrave; &atilde; &aring; &aelig; &egrave; &ecirc; &igrave; &iuml; &eth; &ntilde; &ograve; &oslash; &ugrave; &thorn; &yuml;" }

// The length of the HTML Latin-1 entity at `at`, or 0.
fn latin1_at(line: str, at: usize) -> usize {
    if at >= line.len || line[at] != 38u8 { ret 0usize }
    let table = latin1_entities()
    var i = 0usize
    while i < table.len {
        while i < table.len && table[i] == 32u8 { i += 1usize }
        let start = i
        while i < table.len && table[i] != 32u8 { i += 1usize }
        let ent = table[start..i]
        if at_str(line, at, ent) { ret ent.len }
    }
    ret 0usize
}

// TextParser::is_wordchar at byte `at`.
fn is_wordchar_at(d: *const Dict, line: str, at: usize) -> bool {
    if at >= line.len { ret false }
    let (c, width) = cp_at(line, at)
    ret cp_is_alpha(c) || cp_has(d.wordchars, c)
}

// The words of a line the text parser yields, in order.
fn text_tokens(a: *mem.Arena, d: *const Dict, line: str) -> []str {
    var out = new_list[str](a)
    var state = 0i32
    var head = 0usize
    var token = 0usize
    let apos_wc = cp_has(d.wordchars, 39u32)
    let uapos_wc = cp_has(d.wordchars, 8217u32)
    while true {
        if state == 0i32 {
            let lat = latin1_at(line, head)
            if is_wordchar_at(d, line, head) {
                state = 1i32
                token = head
            } else if lat > 0usize {
                state = 1i32
                token = head
                head += lat
            }
        } else {
            let lat = latin1_at(line, head)
            if lat > 0usize {
                head += lat
            } else if (apos_wc || uapos_wc) && head < line.len && line[head] == 39u8 && is_wordchar_at(d, line, head + 1usize) {
                head += 1usize
            } else if apos_wc && at_str(line, head, "\xe2\x80\x99") && is_wordchar_at(d, line, head + 3usize) {
                head += 2usize
            } else if !is_wordchar_at(d, line, head) {
                state = 0i32
                var t = line[token..head]
                var emit = true
                if t.len > 0usize && t[t.len - 1usize] == 58u8 {
                    t = t[..t.len - 1usize]
                    if t.len == 0usize { emit = false }
                }
                if emit { push_str(&out, t) }
            }
        }
        // next_char
        if head >= line.len { break }
        if line[head] >= 128u8 {
            head += 1usize
            while head < line.len && (line[head] & 192u8) == 128u8 { head += 1usize }
        } else {
            head += 1usize
        }
    }
    ret list.slice[str](&out)
}

// hunspell_find for one text: the misspelled words, one per line.
fn find(a: *mem.Arena, d: *Dict, text: str) -> str { ret find_format(a, d, text, FMT_TEXT) }

// ---- hunspell_parse / hunspell_find: the text, man, latex, xml and html tokenizers ------------

const FMT_TEXT: u8 = 0u8
const FMT_MAN: u8 = 1u8
const FMT_LATEX: u8 = 2u8
const FMT_XML: u8 = 3u8
const FMT_HTML: u8 = 4u8

type Parser = struct {
    fmt: u8,
    state: i32,
    head: usize,
    token: usize,
    line: str,
    pattern_num: i32,
    pattern2_num: i32,
    checkattr: i32,
    quotmark: u8,
    prevstate: i32,
    depth: i32,
    arg: i32,
    opt: i32,
    pats0: []str,
    pats1: []str,
    args: []i32,
    pats2a: []str,
    pats2b: []str,
}

// The latex pattern table: records end with 0x1e, fields (open, close, arguments) with 0x1f.
fn latex_table() -> str {
    ret "\\(\x1f\\)\x1f0\x1e$$\x1f$$\x1f0\x1e$\x1f$\x1f0\x1e\\begin{math}\x1f\\end{math}\x1f0\x1e\\[\x1f\\]\x1f0\x1e\\begin{displaymath}\x1f\\end{displaymath}\x1f0\x1e\\begin{equation}\x1f\\end{equation}\x1f0\x1e\\begin{equation*}\x1f\\end{equation*}\x1f0\x1e\\cite\x1f\x1f1\x1e\\nocite\x1f\x1f1\x1e\\index\x1f\x1f1\x1e\\label\x1f\x1f1\x1e\\ref\x1f\x1f1\x1e\\pageref\x1f\x1f1\x1e\\autoref\x1f\x1f1\x1e\\parbox\x1f\x1f1\x1e\\begin{verbatim}\x1f\\end{verbatim}\x1f0\x1e\\verb+\x1f+\x1f0\x1e\\verb|\x1f|\x1f0\x1e\\verb#\x1f#\x1f0\x1e\\verb*\x1f*\x1f0\x1e\\documentstyle\x1f\\begin{document}\x1f0\x1e\\documentclass\x1f\\begin{document}\x1f0\x1e\\usepackage\x1f\x1f1\x1e\\includeonly\x1f\x1f1\x1e\\include\x1f\x1f1\x1e\\input\x1f\x1f1\x1e\\vspace\x1f\x1f1\x1e\\setlength\x1f\x1f2\x1e\\addtolength\x1f\x1f2\x1e\\settowidth\x1f\x1f2\x1e\\rule\x1f\x1f2\x1e\\hspace\x1f\x1f1\x1e\\vspace\x1f\x1f1\x1e\\\\[\x1f]\x1f0\x1e\\pagebreak[\x1f]\x1f0\x1e\\nopagebreak[\x1f]\x1f0\x1e\\enlargethispage\x1f\x1f1\x1e\\begin{tabular}\x1f\x1f1\x1e\\addcontentsline\x1f\x1f2\x1e\\begin{thebibliography}\x1f\x1f1\x1e\\bibliography\x1f\x1f1\x1e\\bibliographystyle\x1f\x1f1\x1e\\bibitem\x1f\x1f1\x1e\\begin\x1f\x1f1\x1e\\end\x1f\x1f1\x1e\\pagestyle\x1f\x1f1\x1e\\pagenumbering\x1f\x1f1\x1e\\thispagestyle\x1f\x1f1\x1e\\newtheorem\x1f\x1f2\x1e\\newcommand\x1f\x1f2\x1e\\renewcommand\x1f\x1f2\x1e\\setcounter\x1f\x1f2\x1e\\addtocounter\x1f\x1f1\x1e\\stepcounter\x1f\x1f1\x1e\\selectlanguage\x1f\x1f1\x1e\\inputencoding\x1f\x1f1\x1e\\hyphenation\x1f\x1f1\x1e\\definecolor\x1f\x1f3\x1e\\color\x1f\x1f1\x1e\\textcolor\x1f\x1f1\x1e\\pagecolor\x1f\x1f1\x1e\\colorbox\x1f\x1f2\x1e\\fcolorbox\x1f\x1f2\x1e\\declaregraphicsextensions\x1f\x1f1\x1e\\psfig\x1f\x1f1\x1e\\url\x1f\x1f1\x1e\\eqref\x1f\x1f1\x1e\\vskip\x1f\x1f1\x1e\\vglue\x1f\x1f1\x1e''\x1f\x1f1\x1e"
}

fn html_table() -> str {
    ret "<script\x1f</script>\x1e<style\x1f</style>\x1e<code\x1f</code>\x1e<samp\x1f</samp>\x1e<kbd\x1f</kbd>\x1e<var\x1f</var>\x1e<listing\x1f</listing>\x1e<address\x1f</address>\x1e<pre\x1f</pre>\x1e<!--\x1f-->\x1e<[cdata[\x1f]]>\x1e<\x1f>\x1e"
}

fn xml_table() -> str { ret "<!--\x1f-->\x1e<[cdata[\x1f]]>\x1e<\x1f>\x1e" }

fn html_table2() -> str { ret "<img\x1falt=\x1e<img\x1ftitle=\x1e<a \x1ftitle=\x1e" }

// Fill the pattern arrays from a table string.
fn load_table(a: *mem.Arena, table: str, p0: *list.List[str], p1: *list.List[str], args: *list.List[i32]) {
    var start = 0usize
    var i = 0usize
    while i < table.len {
        if table[i] == 30u8 {
            let rec = table[start..i]
            var f1 = 0usize
            while f1 < rec.len && rec[f1] != 31u8 { f1 += 1usize }
            var f2 = f1 + 1usize
            while f2 < rec.len && rec[f2] != 31u8 { f2 += 1usize }
            push_str(p0, rec[..f1])
            if f2 <= rec.len && f1 < rec.len { push_str(p1, rec[f1 + 1usize..f2]) } else { push_str(p1, "") }
            if f2 < rec.len {
                if list.push[i32](args, atoi_str(rec[f2 + 1usize..])) != ok { os.exit(5) }
            } else {
                if list.push[i32](args, 0i32) != ok { os.exit(5) }
            }
            start = i + 1usize
        }
        i += 1usize
    }
}

fn parser_new(a: *mem.Arena, fmt: u8) -> Parser {
    var p: Parser = zero
    p.fmt = fmt
    p.pattern_num = -1i32
    p.pattern2_num = -1i32
    var l0 = new_list[str](a)
    var l1 = new_list[str](a)
    var la = new_list[i32](a)
    if fmt == FMT_LATEX { load_table(a, latex_table(), &l0, &l1, &la) }
    if fmt == FMT_XML { load_table(a, xml_table(), &l0, &l1, &la) }
    if fmt == FMT_HTML { load_table(a, html_table(), &l0, &l1, &la) }
    p.pats0 = list.slice[str](&l0)
    p.pats1 = list.slice[str](&l1)
    p.args = list.slice[i32](&la)
    var m0 = new_list[str](a)
    var m1 = new_list[str](a)
    var ma = new_list[i32](a)
    if fmt == FMT_HTML { load_table(a, html_table2(), &m0, &m1, &ma) }
    p.pats2a = list.slice[str](&m0)
    p.pats2b = list.slice[str](&m1)
    ret p
}

fn put_line(p: *Parser, line: str) {
    p.line = line
    p.token = 0usize
    p.head = 0usize
}

fn lowc(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// The byte at i, 0 past the end.
fn ch(s: str, i: usize) -> u8 {
    if i >= s.len { ret 0u8 }
    ret s[i]
}

// look_pattern: the first pattern (of `pats`) the line starts with at head, compared in lower case.
fn look_pattern(p: *const Parser, pats: []const str) -> i32 {
    var i = 0usize
    while i < pats.len {
        let k = pats[i]
        if k.len > 0usize {
            var n = 0usize
            while n < k.len && lowc(ch(p.line, p.head + n)) == k[n] { n += 1usize }
            if n == k.len { ret i32(i) }
        }
        i += 1usize
    }
    ret -1i32
}

// TextParser::next_char: step over one character; true at the end of the line.
fn next_char(p: *Parser) -> bool {
    if p.head >= p.line.len { ret true }
    if p.line[p.head] >= 128u8 {
        p.head += 1usize
        while p.head < p.line.len && (p.line[p.head] & 192u8) == 128u8 { p.head += 1usize }
    } else {
        p.head += 1usize
    }
    ret false
}

// alloc_token: the token between `token` and `head`, without a trailing colon; (text, emitted).
fn alloc_token(p: *const Parser) -> (str, bool) {
    var t = p.line[p.token..p.head]
    if t.len > 0usize && t[t.len - 1usize] == 58u8 {
        t = t[..t.len - 1usize]
        if t.len == 0usize { ret ("", false) }
    }
    ret (t, true)
}

fn is_wc(d: *const Dict, p: *const Parser, at: usize) -> bool { ret is_wordchar_at(d, p.line, at) }

// The tokens a text, man, latex, xml or html parser yields next; (token, found).
fn parser_next(d: *const Dict, p: *Parser) -> (str, bool) {
    let apos_wc = cp_has(d.wordchars, 39u32)
    let uapos_wc = cp_has(d.wordchars, 8217u32)
    var slash = 0i32
    while true {
        if p.fmt == FMT_TEXT {
            if p.state == 0i32 {
                let lat = latin1_at(p.line, p.head)
                if is_wc(d, p, p.head) {
                    p.state = 1i32
                    p.token = p.head
                } else if lat > 0usize {
                    p.state = 1i32
                    p.token = p.head
                    p.head += lat
                }
            } else {
                let lat = latin1_at(p.line, p.head)
                if lat > 0usize {
                    p.head += lat
                } else if (apos_wc || uapos_wc) && p.head < p.line.len && p.line[p.head] == 39u8 && is_wc(d, p, p.head + 1usize) {
                    p.head += 1usize
                } else if apos_wc && at_str(p.line, p.head, "\xe2\x80\x99") && is_wc(d, p, p.head + 3usize) {
                    p.head += 2usize
                } else if !is_wc(d, p, p.head) {
                    p.state = 0i32
                    let (t, emit) = alloc_token(p)
                    if emit { ret (t, true) }
                }
            }
        } else if p.fmt == FMT_MAN {
            var handled = false
            if p.state == 1i32 {
                if ch(p.line, p.head) == 32u8 { p.state = 2i32 }
                handled = true
            } else if p.state == 0i32 {
                if ch(p.line, 0usize) == 46u8 {
                    p.state = 1i32
                    handled = true
                } else {
                    p.state = 2i32
                }
            }
            if !handled {
                if p.state == 2i32 {
                    if is_wc(d, p, p.head) {
                        p.state = 3i32
                        p.token = p.head
                    } else if ch(p.line, p.head) == 92u8 && ch(p.line, p.head + 1usize) == 102u8 && ch(p.line, p.head + 2usize) != 0u8 {
                        p.head += 2usize
                    }
                } else if p.state == 3i32 {
                    if !is_wc(d, p, p.head) {
                        p.state = 2i32
                        let (t, emit) = alloc_token(p)
                        if emit { ret (t, true) }
                    }
                }
            }
            if next_char(p) {
                p.state = 0i32
                ret ("", false)
            }
            continue
        } else if p.fmt == FMT_LATEX {
            if p.state == 0i32 {
                p.pattern_num = look_pattern(p, p.pats0)
                if p.pattern_num != -1i32 {
                    if p.pats1[usize(p.pattern_num)].len > 0usize {
                        p.state = 2i32
                    } else {
                        p.state = 4i32
                        p.depth = 0i32
                        p.arg = 0i32
                        p.opt = 1i32
                    }
                    p.head += p.pats0[usize(p.pattern_num)].len - 1usize
                } else if ch(p.line, p.head) == 37u8 {
                    p.state = 5i32
                } else if is_wc(d, p, p.head) {
                    p.state = 1i32
                    p.token = p.head
                } else if ch(p.line, p.head) == 92u8 {
                    let n1 = ch(p.line, p.head + 1usize)
                    if n1 == 92u8 || n1 == 36u8 || n1 == 37u8 {
                        p.head += 1usize
                        if next_char(p) {
                            if p.state == 5i32 { p.state = 0i32 }
                            ret ("", false)
                        }
                        continue
                    }
                    p.state = 3i32
                }
            } else if p.state == 1i32 {
                var apostrophe = false
                if (apos_wc || uapos_wc) && p.head < p.line.len && p.line[p.head] == 39u8 && is_wc(d, p, p.head + 1usize) {
                    p.head += 1usize
                } else if apos_wc && at_str(p.line, p.head, "\xe2\x80\x99") && is_wc(d, p, p.head + 3usize) {
                    p.head += 2usize
                } else if !is_wc(d, p, p.head) || (ch(p.line, p.head) == 39u8 && ch(p.line, p.head + 1usize) == 39u8) {
                    if is_wc(d, p, p.head) { apostrophe = true }
                    p.state = 0i32
                    let (t, emit) = alloc_token(p)
                    if apostrophe { p.head += 2usize }
                    if emit { ret (t, true) }
                }
            } else if p.state == 2i32 {
                let i = look_pattern(p, p.pats1)
                if i != -1i32 && same(p.pats1[usize(i)], p.pats1[usize(p.pattern_num)]) {
                    p.state = 0i32
                    p.head += p.pats1[usize(p.pattern_num)].len - 1usize
                }
            } else if p.state == 3i32 {
                let c = lowc(ch(p.line, p.head))
                if c < 97u8 || c > 122u8 {
                    p.state = 0i32
                    p.head -= 1usize
                }
            } else if p.state == 4i32 {
                let c = ch(p.line, p.head)
                if slash != 0i32 && c != 0u8 {
                    slash = 0i32
                    p.head += 1usize
                    if next_char(p) {
                        if p.state == 5i32 { p.state = 0i32 }
                        ret ("", false)
                    }
                    continue
                } else if c == 92u8 {
                    slash = 1i32
                } else if c == 123u8 || (p.opt != 0i32 && c == 91u8) {
                    p.depth += 1i32
                    p.opt = 0i32
                } else if c == 125u8 {
                    p.depth -= 1i32
                    if p.depth == 0i32 {
                        p.opt = 1i32
                        p.arg += 1i32
                    }
                    if (p.depth == 0i32 && p.arg == p.args[usize(p.pattern_num)]) || p.depth < 0i32 { p.state = 0i32 }
                } else if c == 93u8 {
                    p.depth -= 1i32
                }
            }
        } else {
            // xml and html
            if p.state == 0i32 {
                p.prevstate = 0i32
                p.pattern_num = look_pattern(p, p.pats0)
                if p.pattern_num != -1i32 {
                    p.checkattr = 0i32
                    p.pattern2_num = look_pattern(p, p.pats2a)
                    if p.pattern2_num != -1i32 { p.checkattr = 1i32 }
                    p.state = 2i32
                } else if is_wc(d, p, p.head) {
                    p.state = 1i32
                    p.token = p.head
                } else if latin1_at(p.line, p.head) > 0usize {
                    p.state = 1i32
                    p.token = p.head
                    p.head += latin1_at(p.line, p.head)
                } else if ch(p.line, p.head) == 38u8 {
                    p.state = 3i32
                }
            } else if p.state == 1i32 {
                let lat = latin1_at(p.line, p.head)
                if lat > 0usize {
                    p.head += lat
                } else if (apos_wc || uapos_wc) && at_str(p.line, p.head, "&apos;") && is_wc(d, p, p.head + 6usize) {
                    p.head += 5usize
                } else if apos_wc && at_str(p.line, p.head, "\xe2\x80\x99") && is_wc(d, p, p.head + 3usize) {
                    p.head += 2usize
                } else if !is_wc(d, p, p.head) {
                    p.state = p.prevstate
                    let (t, emit) = alloc_token(p)
                    if emit { ret (t, true) }
                }
            } else if p.state == 2i32 {
                // a tag: comment, label and so on
                var matched = false
                let i2 = look_pattern(p, p.pats2b)
                if p.checkattr == 1i32 && i2 != -1i32 && same(p.pats2a[usize(i2)], p.pats2a[usize(p.pattern2_num)]) {
                    p.checkattr = 2i32
                    matched = true
                } else if p.checkattr > 0i32 && ch(p.line, p.head) == 62u8 {
                    p.state = 0i32
                    matched = true
                }
                if !matched {
                    let i = look_pattern(p, p.pats1)
                    if i != -1i32 && same(p.pats1[usize(i)], p.pats1[usize(p.pattern_num)]) {
                        p.state = 0i32
                        p.head += p.pats1[usize(p.pattern_num)].len - 1usize
                    } else if same(p.pats0[usize(p.pattern_num)], "<") && (ch(p.line, p.head) == 34u8 || ch(p.line, p.head) == 39u8) {
                        p.quotmark = ch(p.line, p.head)
                        p.state = 4i32
                    }
                }
            } else if p.state == 4i32 {
                p.prevstate = 4i32
                if ch(p.line, p.head) == p.quotmark {
                    p.state = 2i32
                    if p.checkattr == 2i32 { p.checkattr = 1i32 }
                } else if is_wc(d, p, p.head) && p.checkattr == 2i32 {
                    p.state = 1i32
                    p.token = p.head
                } else if ch(p.line, p.head) == 38u8 {
                    p.state = 3i32
                }
            } else if p.state == 3i32 {
                if lowc(ch(p.line, p.head)) == 59u8 {
                    p.state = p.prevstate
                    p.head -= 1usize
                }
            }
        }
        if p.fmt != FMT_MAN {
            if next_char(p) {
                if p.fmt == FMT_LATEX && p.state == 5i32 { p.state = 0i32 }
                ret ("", false)
            }
        }
    }
    ret ("", false)
}

// hunspell_parse for one text: every token, one per line.
fn parse_tokens(a: *mem.Arena, d: *Dict, text: str, fmt: u8) -> str {
    var p = parser_new(a, fmt)
    put_line(&p, text)
    var out = new_list[str](a)
    while true {
        let (t, found) = parser_next(d, &p)
        if !found { break }
        push_str(&out, t)
    }
    ret join_lines(a, list.slice[str](&out))
}

// hunspell_find for one text of the given format: the misspelled words, one per line.
fn find_format(a: *mem.Arena, d: *Dict, text: str, fmt: u8) -> str {
    var wk = W { a: a, d: d, pfx: 0usize, sfx: 0usize }
    var p = parser_new(a, fmt)
    put_line(&p, text)
    var out = new_list[str](a)
    while true {
        let (t, found) = parser_next(d, &p)
        if !found { break }
        if !spell_sub(&wk, t) { push_str(&out, t) }
    }
    ret join_lines(a, list.slice[str](&out))
}

// ---- personal words (the add_words of R's dictionary()) ------------------------------------

// HashMgr::remove_forbidden_flag: true when the word is not in the table; a forbidden entry
// loses its flags.
fn remove_forbidden_flag(d: *Dict, word: str) -> bool {
    var dp = lookup(d, word)
    if dp == 0usize { ret true }
    while dp != 0usize {
        if has_flag(d.ents.items[dp].flags, d.forbidden) { d.ents.items[dp].flags = d.ents.items[dp].flags[..0usize] }
        dp = d.ents.items[dp].homonym
    }
    d.entries = list.slice[Entry](&d.ents)
    ret false
}

// Add one word the way the R package does: add_with_affix(word, "a"), then add(word).
fn add_word_public(a: *mem.Arena, d: *Dict, word: str) {
    let example = lookup(d, "a")
    let _unused = remove_forbidden_flag(d, word)
    if example != 0usize && d.ents.items[example].flags.len > 0usize {
        let cps = cp_decode(a, word)
        let cap = captype(cps)
        let src = d.ents.items[example].flags
        let flags = alloc[u16](a, src.len)
        var i = 0usize
        while i < src.len {
            flags[i] = src[i]
            i += 1usize
        }
        add_word(a, d, &d.ents, word, cps.len, flags, false, cap)
        if (cap == HUHCAP || cap == HUHINITCAP || (cap == ALLCAP && flags.len != 0usize)) && !has_flag(flags, d.forbidden) {
            let f2 = alloc[u16](a, flags.len + 1usize)
            var m = 0usize
            while m < flags.len {
                f2[m] = flags[m]
                m += 1usize
            }
            f2[flags.len] = ONLYUPCASE
            let low = cp_decode(a, word)
            all_small(low)
            init_cap(low)
            add_word(a, d, &d.ents, cp_encode(a, low), cps.len, f2, true, INITCAP)
        }
        d.entries = list.slice[Entry](&d.ents)
    }
    if remove_forbidden_flag(d, word) {
        let cps = cp_decode(a, word)
        let cap = captype(cps)
        let none = alloc[u16](a, 0usize)
        add_word(a, d, &d.ents, word, cps.len, none, false, cap)
        if cap == HUHCAP || cap == HUHINITCAP {
            let f2 = alloc[u16](a, 1usize)
            f2[0usize] = ONLYUPCASE
            let low = cp_decode(a, word)
            all_small(low)
            init_cap(low)
            add_word(a, d, &d.ents, cp_encode(a, low), cps.len, f2, true, INITCAP)
        }
        d.entries = list.slice[Entry](&d.ents)
    }
}

// Add personal words (the add_words of R's dictionary()), in the order given.
fn add_words(a: *mem.Arena, d: *Dict, words: []const str) {
    var i = 0usize
    while i < words.len {
        add_word_public(a, d, words[i])
        i += 1usize
    }
}
