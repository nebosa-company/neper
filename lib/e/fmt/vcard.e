// vCards (C127): `parse` reads the cards of a .vcf text (versions 2.1, 3.0 and 4.0 as phones write them) into
// `Card` values and `write` writes cards as vCard 3.0. A card keeps the display name (FN), the structured name
// (N: family and given), up to four telephone numbers with their first TYPE, up to two e-mail addresses, the
// organisation (the first ORG component) and a note. Lines are unfolded (a line that starts with a space or a tab
// continues the one before), property groups ("item1.TEL") and parameters are read, values are unescaped
// (\n \N \, \; \\); everything else (photos, addresses, extended properties) is skipped. A text that has no
// BEGIN:VCARD is `Malformed`.
//
// Memory: the strings of a card are copies in the arena passed in.
use e.mem

error Malformed
error TooLong

type Card = struct {
    name: str,
    family: str,
    given: str,
    org: str,
    note: str,
    tel: [4]str,
    tel_type: [4]str,
    tel_count: usize,
    email: [2]str,
    email_count: usize,
}

fn upper(c: u8) -> u8 {
    if c >= 97u8 && c <= 122u8 { ret c - 32u8 }
    ret c
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn equals_fold(a: []const u8, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if upper(a[i]) != upper(b[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn empty_card() -> Card {
    let none = ""
    ret Card { name: none, family: none, given: none, org: none, note: none, tel: [4]str{ none, none, none, none }, tel_type: [4]str{ none, none, none, none }, tel_count: 0usize, email: [2]str{ none, none }, email_count: 0usize }
}

fn lower_text(a: *mem.Arena, value: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, value.len + 1usize)
    if out_error != ok { ret ("", out_error) }
    var i = 0usize
    while i < value.len {
        out[i] = lower(value[i])
        i += 1usize
    }
    ret (out[0usize..value.len], ok)
}

// The value of one logical line `value` unescaped into the arena.
fn unescape(a: *mem.Arena, value: []const u8) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, value.len + 1usize)
    if out_error != ok { ret ("", out_error) }
    var n = 0usize
    var i = 0usize
    while i < value.len {
        let c = value[i]
        if c == 92u8 && i + 1usize < value.len {
            let d = value[i + 1usize]
            if d == 110u8 || d == 78u8 {
                out[n] = 10u8
            } else {
                out[n] = d
            }
            n += 1usize
            i += 2usize
        } else {
            out[n] = c
            n += 1usize
            i += 1usize
        }
    }
    ret (out[0usize..n], ok)
}

// A copy of `value` in the arena up to the first unescaped `;` (the first component of a structured value),
// unescaped.
fn first_component(a: *mem.Arena, value: []const u8) -> (str, err) {
    var end = 0usize
    while end < value.len {
        if value[end] == 92u8 { end += 2usize } else if value[end] == 59u8 { break } else { end += 1usize }
    }
    if end > value.len { end = value.len }
    let (text_out, text_error) = unescape(a, value[0usize..end])
    ret (text_out, text_error)
}

// Handle one logical line of a card.
fn property(a: *mem.Arena, card: *Card, line: []const u8) -> err {
    // name[;params]:value, the first colon outside quotes.
    var colon = 0usize
    var quoted = false
    var found = false
    while colon < line.len && !found {
        if line[colon] == 34u8 { quoted = !quoted }
        if line[colon] == 58u8 && !quoted { found = true } else { colon += 1usize }
    }
    if !found { ret ok }
    let head = line[0usize..colon]
    let value = line[colon + 1usize..line.len]
    // The property name (after a group dot), then the parameters.
    var start = 0usize
    var i = 0usize
    while i < head.len && head[i] != 59u8 {
        if head[i] == 46u8 { start = i + 1usize }
        i += 1usize
    }
    let name = head[start..i]
    let params = head[i..head.len]
    if equals_fold(name, "FN") {
        let (v, e) = unescape(a, value)
        if e != ok { ret e }
        card.name = v
    } else if equals_fold(name, "N") {
        let (family, family_error) = first_component(a, value)
        if family_error != ok { ret family_error }
        card.family = family
        // The given name is the second component.
        var k = 0usize
        var semis = 0usize
        while k < value.len && semis < 1usize {
            if value[k] == 92u8 {
                k += 2usize
            } else if value[k] == 59u8 {
                semis += 1usize
                k += 1usize
            } else {
                k += 1usize
            }
        }
        if k <= value.len {
            let (given, given_error) = first_component(a, value[k..value.len])
            if given_error != ok { ret given_error }
            card.given = given
        }
    } else if equals_fold(name, "TEL") {
        if card.tel_count < 4usize {
            let (v, e) = unescape(a, value)
            if e != ok { ret e }
            card.tel[card.tel_count] = v
            // The first type: TYPE=cell, TYPE="cell,voice", or a bare parameter (2.1: TEL;CELL;VOICE).
            var type_value = ""
            var p = 0usize
            while p < params.len {
                if params[p] == 59u8 {
                    var q = p + 1usize
                    while q < params.len && params[q] != 59u8 { q += 1usize }
                    let param = params[p + 1usize..q]
                    var eq = 0usize
                    while eq < param.len && param[eq] != 61u8 { eq += 1usize }
                    var raw = param
                    var is_type = true
                    if eq < param.len {
                        is_type = equals_fold(param[0usize..eq], "TYPE")
                        raw = param[eq + 1usize..param.len]
                    }
                    if is_type && type_value.len == 0usize {
                        var cut = 0usize
                        while cut < raw.len && raw[cut] != 44u8 && raw[cut] != 34u8 { cut += 1usize }
                        if cut > 0usize {
                            let (t, te) = unescape(a, raw[0usize..cut])
                            if te != ok { ret te }
                            type_value = t
                        } else if raw.len > 1usize && raw[0usize] == 34u8 {
                            var cut2 = 1usize
                            while cut2 < raw.len && raw[cut2] != 44u8 && raw[cut2] != 34u8 { cut2 += 1usize }
                            let (t2, te2) = unescape(a, raw[1usize..cut2])
                            if te2 != ok { ret te2 }
                            type_value = t2
                        }
                    }
                    p = q
                } else {
                    p += 1usize
                }
            }
            // Types are case-insensitive; they are kept in lower case.
            let (lowered, lowered_error) = lower_text(a, type_value)
            if lowered_error != ok { ret lowered_error }
            card.tel_type[card.tel_count] = lowered
            card.tel_count += 1usize
        }
    } else if equals_fold(name, "EMAIL") {
        if card.email_count < 2usize {
            let (v, e) = unescape(a, value)
            if e != ok { ret e }
            card.email[card.email_count] = v
            card.email_count += 1usize
        }
    } else if equals_fold(name, "ORG") {
        let (v, e) = first_component(a, value)
        if e != ok { ret e }
        card.org = v
    } else if equals_fold(name, "NOTE") {
        let (v, e) = unescape(a, value)
        if e != ok { ret e }
        card.note = v
    }
    ret ok
}

// The cards of `data`, at most `out.len`, and how many.
fn parse(a: *mem.Arena, data: []const u8, out: []Card) -> (usize, err) {
    // Unfold into one buffer: CRLF (or LF) followed by a space or tab is removed.
    let (flat, flat_error) = mem.alloc[u8](a, data.len + 1usize)
    if flat_error != ok { ret (0usize, flat_error) }
    var n = 0usize
    var i = 0usize
    while i < data.len {
        let c = data[i]
        if c == 13u8 || c == 10u8 {
            var j = i
            if c == 13u8 && j + 1usize < data.len && data[j + 1usize] == 10u8 { j += 1usize }
            if j + 1usize < data.len && (data[j + 1usize] == 32u8 || data[j + 1usize] == 9u8) {
                i = j + 2usize
            } else {
                flat[n] = 10u8
                n += 1usize
                i = j + 1usize
            }
        } else {
            flat[n] = c
            n += 1usize
            i += 1usize
        }
    }
    var count = 0usize
    var card = empty_card()
    var inside = false
    var seen = false
    var line_start = 0usize
    var k = 0usize
    while k <= n {
        if k == n || flat[k] == 10u8 {
            let line = flat[line_start..k]
            if equals_fold(line, "BEGIN:VCARD") {
                card = empty_card()
                inside = true
                seen = true
            } else if equals_fold(line, "END:VCARD") {
                if inside && count < out.len {
                    out[count] = card
                    count += 1usize
                }
                inside = false
            } else if inside && line.len > 0usize {
                let e = property(a, &card, line)
                if e != ok { ret (count, e) }
            }
            line_start = k + 1usize
        }
        k += 1usize
    }
    if !seen { ret (0usize, Malformed) }
    ret (count, ok)
}

// ---- writing --------------------------------------------------------------------------------------

type Out = struct { buf: []u8, len: usize, column: usize, over: bool }

fn out_byte(o: *Out, b: u8) {
    // Lines are folded at 75 octets: a CRLF and a space.
    if o.column >= 75usize && b != 13u8 && b != 10u8 {
        if o.len + 3usize > o.buf.len {
            o.over = true
            ret
        }
        o.buf[o.len] = 13u8
        o.buf[o.len + 1usize] = 10u8
        o.buf[o.len + 2usize] = 32u8
        o.len += 3usize
        o.column = 1usize
    }
    if o.len >= o.buf.len {
        o.over = true
        ret
    }
    o.buf[o.len] = b
    o.len += 1usize
    o.column += 1usize
}

fn out_raw(o: *Out, s: str) {
    var i = 0usize
    while i < s.len {
        out_byte(o, s[i])
        i += 1usize
    }
}

fn out_value(o: *Out, s: str) {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 10u8 {
            out_byte(o, 92u8)
            out_byte(o, 110u8)
        } else if c == 92u8 || c == 59u8 || c == 44u8 {
            out_byte(o, 92u8)
            out_byte(o, c)
        } else if c != 13u8 {
            out_byte(o, c)
        }
        i += 1usize
    }
}

fn out_end(o: *Out) {
    if o.len + 2usize > o.buf.len {
        o.over = true
        ret
    }
    o.buf[o.len] = 13u8
    o.buf[o.len + 1usize] = 10u8
    o.len += 2usize
    o.column = 0usize
}

// The cards as vCard 3.0 into `buf`: the length written.
fn write(cards: []const Card, buf: []u8) -> (usize, err) {
    var o = Out { buf: buf, len: 0usize, column: 0usize, over: false }
    var i = 0usize
    while i < cards.len {
        let card = cards[i]
        out_raw(&o, "BEGIN:VCARD")
        out_end(&o)
        out_raw(&o, "VERSION:3.0")
        out_end(&o)
        out_raw(&o, "FN:")
        out_value(&o, card.name)
        out_end(&o)
        out_raw(&o, "N:")
        out_value(&o, card.family)
        out_raw(&o, ";")
        out_value(&o, card.given)
        out_raw(&o, ";;;")
        out_end(&o)
        var t = 0usize
        while t < card.tel_count {
            out_raw(&o, "TEL")
            if card.tel_type[t].len > 0usize {
                out_raw(&o, ";TYPE=")
                out_value(&o, card.tel_type[t])
            }
            out_raw(&o, ":")
            out_value(&o, card.tel[t])
            out_end(&o)
            t += 1usize
        }
        var m = 0usize
        while m < card.email_count {
            out_raw(&o, "EMAIL:")
            out_value(&o, card.email[m])
            out_end(&o)
            m += 1usize
        }
        if card.org.len > 0usize {
            out_raw(&o, "ORG:")
            out_value(&o, card.org)
            out_end(&o)
        }
        if card.note.len > 0usize {
            out_raw(&o, "NOTE:")
            out_value(&o, card.note)
            out_end(&o)
        }
        out_raw(&o, "END:VCARD")
        out_end(&o)
        i += 1usize
    }
    if o.over { ret (0usize, TooLong) }
    ret (o.len, ok)
}
