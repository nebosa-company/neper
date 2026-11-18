// Token counting for language-model text. `load` reads a tiktoken vocabulary file
// (one `base64(token) rank` line per token; cl100k_base and o200k_base are those
// files) into the caller's arena, and `count` returns how many tokens `text` encodes
// to: the text is cut into pieces by the cl100k or o200k split pattern, written as
// code below because the patterns need lookahead, and each piece is merged
// by lowest rank as tiktoken does. `piece_end` exposes the split. `estimate` is the
// vocabulary-free count for models whose tokenizer is not public, Claude's among
// them.
//
// ponytail: the split reads UTF-8 without validating continuation bytes, special
// tokens such as <|endoftext|> count as the text they spell, and a piece's merge is
// quadratic in the piece length; `estimate` is a rough chars-per-token ratio, not
// Anthropic's tokenizer, and the count_tokens API is the exact answer for Claude.

use e.mem
use e.text.unicode

type Kind = enum u8 { Cl100k, O200k }
type Vocab = struct { bytes: []u8, off: []u32, rank: []u32, slots: []u32, mask: usize, count: usize }
error Invalid
error TooSmall

const NONE: u32 = 4294967295u32

fn b64(c: u8) -> u32 {
    if c >= 65u8 && c <= 90u8 { ret u32(c) - 65u32 }
    if c >= 97u8 && c <= 122u8 { ret u32(c) - 71u32 }
    if c >= 48u8 && c <= 57u8 { ret u32(c) + 4u32 }
    if c == 43u8 { ret 62u32 }
    if c == 47u8 { ret 63u32 }
    ret NONE
}

fn hash_bytes(b: []const u8, lo: usize, hi: usize) -> usize {
    var h = 2166136261u64
    var i = lo
    while i < hi {
        h = ((h ^ u64(b[i])) * 16777619u64) & 4294967295u64
        i += 1usize
    }
    ret usize(h)
}

fn hash_str(s: str, lo: usize, hi: usize) -> usize {
    var h = 2166136261u64
    var i = lo
    while i < hi {
        h = ((h ^ u64(s[i])) * 16777619u64) & 4294967295u64
        i += 1usize
    }
    ret usize(h)
}

// A tiktoken vocabulary read from `text`.
fn load(a: *mem.Arena, text: str) -> (Vocab, err) {
    if text.len == 0usize { ret (zero, Invalid) }
    var lines = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 { lines += 1usize }
        i += 1usize
    }
    let (bytes, bytes_error) = mem.alloc[u8](a, text.len)
    if bytes_error != ok { ret (zero, bytes_error) }
    let (off, off_error) = mem.alloc[u32](a, lines + 1usize)
    if off_error != ok { ret (zero, off_error) }
    let (rank, rank_error) = mem.alloc[u32](a, lines)
    if rank_error != ok { ret (zero, rank_error) }
    var size = 16usize
    while size < lines * 2usize { size = size * 2usize }
    let (slots, slots_error) = mem.alloc[u32](a, size)
    if slots_error != ok { ret (zero, slots_error) }
    i = 0usize
    while i < size {
        slots[i] = 0u32
        i += 1usize
    }
    var n = 0usize
    var used = 0usize
    off[0usize] = 0u32
    i = 0usize
    while i < text.len {
        if text[i] == 10u8 || text[i] == 13u8 {
            i += 1usize
        } else {
            var acc = 0u32
            var bits = 0u32
            while i < text.len && text[i] != 32u8 {
                let d = b64(text[i])
                if d != NONE {
                    acc = (acc << 6u32) | d
                    bits += 6u32
                    if bits >= 8u32 {
                        bits = bits - 8u32
                        bytes[used] = u8((acc >> bits) & 255u32)
                        used += 1usize
                        acc = acc & ((1u32 << bits) - 1u32)
                    }
                } else if text[i] != 61u8 {
                    ret (zero, Invalid)
                }
                i += 1usize
            }
            if i >= text.len || used == usize(off[n]) { ret (zero, Invalid) }
            i += 1usize
            var r = 0u32
            var seen = 0usize
            while i < text.len && text[i] >= 48u8 && text[i] <= 57u8 {
                r = r * 10u32 + (u32(text[i]) - 48u32)
                seen += 1usize
                i += 1usize
            }
            if seen == 0usize { ret (zero, Invalid) }
            rank[n] = r
            off[n + 1usize] = u32(used)
            var slot = hash_bytes(bytes, usize(off[n]), used) & (size - 1usize)
            while slots[slot] != 0u32 { slot = (slot + 1usize) & (size - 1usize) }
            slots[slot] = u32(n + 1usize)
            n += 1usize
        }
    }
    ret (Vocab { bytes: bytes, off: off, rank: rank, slots: slots, mask: size - 1usize, count: n }, ok)
}

// The rank of `s[lo..hi]` as a token, or NONE.
fn lookup(v: *const Vocab, s: str, lo: usize, hi: usize) -> u32 {
    var slot = hash_str(s, lo, hi) & v.mask
    var found = NONE
    var searching = true
    while searching {
        let t = v.slots[slot]
        if t == 0u32 {
            searching = false
        } else {
            let k = usize(t - 1u32)
            let o = usize(v.off[k])
            let len = usize(v.off[k + 1usize]) - o
            if len == hi - lo {
                var same = true
                var j = 0usize
                while same && j < len {
                    if v.bytes[o + j] != s[lo + j] { same = false }
                    j += 1usize
                }
                if same {
                    found = v.rank[k]
                    searching = false
                }
            }
            slot = (slot + 1usize) & v.mask
        }
    }
    ret found
}

// Tokens in the piece `s[lo..hi]`: repeatedly merge the adjacent pair whose
// concatenation has the lowest rank. `parts` holds the boundaries.
fn merge_count(v: *const Vocab, s: str, lo: usize, hi: usize, parts: []usize) -> usize {
    let n = hi - lo
    if n == 1usize || lookup(v, s, lo, hi) != NONE { ret 1usize }
    var i = 0usize
    while i <= n {
        parts[i] = lo + i
        i += 1usize
    }
    var live = n
    var merging = true
    while merging && live > 1usize {
        var best = NONE
        var at = 0usize
        i = 0usize
        while i + 2usize <= live {
            let r = lookup(v, s, parts[i], parts[i + 2usize])
            if r < best {
                best = r
                at = i
            }
            i += 1usize
        }
        if best == NONE {
            merging = false
        } else {
            i = at + 1usize
            while i < live {
                parts[i] = parts[i + 1usize]
                i += 1usize
            }
            live = live - 1usize
        }
    }
    ret live
}

// The scalar at byte `i` and its encoded width.
fn rune(s: str, i: usize) -> (u32, usize) {
    let b = u32(s[i])
    if b < 128u32 { ret (b, 1usize) }
    if b >= 192u32 && b < 224u32 && i + 1usize < s.len {
        ret (((b & 31u32) << 6u32) | (u32(s[i + 1usize]) & 63u32), 2usize)
    }
    if b >= 224u32 && b < 240u32 && i + 2usize < s.len {
        ret (((b & 15u32) << 12u32) | ((u32(s[i + 1usize]) & 63u32) << 6u32) | (u32(s[i + 2usize]) & 63u32), 3usize)
    }
    if b >= 240u32 && b < 248u32 && i + 3usize < s.len {
        ret (((b & 7u32) << 18u32) | ((u32(s[i + 1usize]) & 63u32) << 12u32) | ((u32(s[i + 2usize]) & 63u32) << 6u32) | (u32(s[i + 3usize]) & 63u32), 4usize)
    }
    ret (65533u32, 1usize)
}

fn is_letter(c: u32) -> bool {
    let k = unicode.category(c)
    ret k == .Lu || k == .Ll || k == .Lt || k == .Lm || k == .Lo
}

fn is_number(c: u32) -> bool {
    let k = unicode.category(c)
    ret k == .Nd || k == .Nl || k == .No
}

fn is_mark(c: u32) -> bool {
    let k = unicode.category(c)
    ret k == .Mn || k == .Mc || k == .Me
}

fn is_newline(c: u32) -> bool { ret c == 10u32 || c == 13u32 }

// o200k's two word classes: [\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}] and [\p{Ll}\p{Lm}\p{Lo}\p{M}].
fn is_upperish(c: u32) -> bool {
    let k = unicode.category(c)
    ret k == .Lu || k == .Lt || k == .Lm || k == .Lo || k == .Mn || k == .Mc || k == .Me
}

fn is_lowerish(c: u32) -> bool {
    let k = unicode.category(c)
    ret k == .Ll || k == .Lm || k == .Lo || k == .Mn || k == .Mc || k == .Me
}

// (?i:'s|'t|'re|'ve|'m|'ll|'d) at `i`: the end of the match, or 0.
fn contraction(s: str, i: usize) -> usize {
    if i + 1usize >= s.len || s[i] != 39u8 { ret 0usize }
    let c = s[i + 1usize] | 32u8
    if c == 115u8 || c == 116u8 || c == 109u8 || c == 100u8 { ret i + 2usize }
    if i + 2usize >= s.len { ret 0usize }
    let d = s[i + 2usize] | 32u8
    if (c == 114u8 && d == 101u8) || (c == 118u8 && d == 101u8) || (c == 108u8 && d == 108u8) { ret i + 3usize }
    ret 0usize
}

// Skip `n` scalars from `j`.
fn skip(s: str, j: usize, n: usize) -> usize {
    var p = j
    var t = 0usize
    while t < n && p < s.len {
        let (c, w) = rune(s, p)
        p += w
        t += 1usize
    }
    ret p
}

// o200k's word alternatives from `j`: upper* lower+ or upper+ lower*, then an optional contraction.
fn word_o200k(s: str, j: usize) -> usize {
    var p = j
    var cnt = 0usize
    var scanning = true
    while scanning && p < s.len {
        let (c, w) = rune(s, p)
        if is_upperish(c) {
            p += w
            cnt += 1usize
        } else {
            scanning = false
        }
    }
    var end = 0usize
    var t = cnt + 1usize
    while end == 0usize && t > 0usize {
        t = t - 1usize
        let q = skip(s, j, t)
        if q < s.len {
            let (c, w) = rune(s, q)
            if is_lowerish(c) {
                var e = q + w
                var more = true
                while more && e < s.len {
                    let (d, dw) = rune(s, e)
                    if is_lowerish(d) { e += dw } else { more = false }
                }
                end = e
            }
        }
    }
    if end == 0usize && cnt > 0usize {
        end = p
        var more = true
        while more && end < s.len {
            let (d, dw) = rune(s, end)
            if is_lowerish(d) { end += dw } else { more = false }
        }
    }
    if end > 0usize {
        let tail = contraction(s, end)
        if tail > 0usize { end = tail }
    }
    ret end
}

fn word_cl100k(s: str, j: usize) -> usize {
    var e = j
    var more = true
    while more && e < s.len {
        let (c, w) = rune(s, e)
        if is_letter(c) { e += w } else { more = false }
    }
    if e > j { ret e }
    ret 0usize
}

// The word alternatives at `i`: an optional one-scalar prefix, tried with and without.
fn word(kind: Kind, s: str, i: usize) -> usize {
    let (c, w) = rune(s, i)
    var e = 0usize
    if !is_newline(c) && !is_letter(c) && !is_number(c) {
        if kind == .Cl100k { e = word_cl100k(s, i + w) } else { e = word_o200k(s, i + w) }
    }
    if e == 0usize {
        if kind == .Cl100k { e = word_cl100k(s, i) } else { e = word_o200k(s, i) }
    }
    ret e
}

fn digits(s: str, i: usize) -> usize {
    var e = i
    var t = 0usize
    var more = true
    while more && t < 3usize && e < s.len {
        let (c, w) = rune(s, e)
        if is_number(c) {
            e += w
            t += 1usize
        } else {
            more = false
        }
    }
    if e == i { ret 0usize }
    ret e
}

// ` ?[^\s\p{L}\p{N}]+[\r\n]*` (o200k also takes `/` in the tail).
fn symbols(kind: Kind, s: str, i: usize) -> usize {
    var j = i
    if s[j] == 32u8 { j += 1usize }
    var e = j
    var more = true
    while more && e < s.len {
        let (c, w) = rune(s, e)
        if !unicode.is_whitespace(c) && !is_letter(c) && !is_number(c) { e += w } else { more = false }
    }
    if e == j { ret 0usize }
    while e < s.len && (s[e] == 10u8 || s[e] == 13u8 || (kind == .O200k && s[e] == 47u8)) { e += 1usize }
    ret e
}

// `\s*[\r\n]+`, then `\s+(?!\S)`, then `\s+`.
fn spaces(s: str, i: usize) -> usize {
    var j = i
    var last = i
    var newline_end = 0usize
    var more = true
    while more && j < s.len {
        let (c, w) = rune(s, j)
        if unicode.is_whitespace(c) {
            last = j
            j += w
            if is_newline(c) { newline_end = j }
        } else {
            more = false
        }
    }
    if j == i { ret 0usize }
    if newline_end > 0usize { ret newline_end }
    if j == s.len || last == i { ret j }
    ret last
}

// The end of the piece that starts at byte `i` of `text` under `kind`'s split pattern.
fn piece_end(kind: Kind, text: str, i: usize) -> usize {
    var e = 0usize
    if kind == .Cl100k { e = contraction(text, i) }
    if e == 0usize { e = word(kind, text, i) }
    if e == 0usize { e = digits(text, i) }
    if e == 0usize { e = symbols(kind, text, i) }
    if e == 0usize { e = spaces(text, i) }
    if e == 0usize {
        let (c, w) = rune(text, i)
        e = i + w
    }
    ret e
}

// How many tokens `text` encodes to. `parts` needs one more entry than the longest piece.
fn count(v: *const Vocab, kind: Kind, text: str, parts: []usize) -> (usize, err) {
    var total = 0usize
    var i = 0usize
    while i < text.len {
        let e = piece_end(kind, text, i)
        if e - i + 1usize > parts.len { ret (0usize, TooSmall) }
        total += merge_count(v, text, i, e, parts)
        i = e
    }
    ret (total, ok)
}

// A vocabulary-free token count: ASCII at 3.5 bytes a token, two-byte scalars at 1.5,
// three-byte scalars (CJK and the like) at one each, four-byte scalars at two.
fn estimate(text: str) -> usize {
    var ascii = 0usize
    var two = 0usize
    var three = 0usize
    var four = 0usize
    var i = 0usize
    while i < text.len {
        let (c, w) = rune(text, i)
        if w == 1usize { ascii += 1usize }
        if w == 2usize { two += 1usize }
        if w == 3usize { three += 1usize }
        if w == 4usize { four += 1usize }
        i += w
    }
    let tenths = ascii * 20usize / 7usize + two * 20usize / 3usize + three * 10usize + four * 20usize
    ret (tenths + 9usize) / 10usize
}
