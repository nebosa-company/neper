// Formula dialect translation (L028): a competitor's formula text becomes canonical formula text, with a
// machine-readable report, after appdor's `src/formula/compat`. Seven source dialects (Airtable, monday.com,
// ClickUp, Smartsheet, Quickbase, Notion, Google AppSheet) are DATA: `table` below lists, per dialect, how its
// field references are written and which of its functions are renamed, reordered, negated, given an extra
// argument, flagged as a semantic mismatch, needing a migrated relationship, or unsupported. Everything else
// resolves through the function registry's names and aliases. A new dialect or a drifted function is a row of the
// table, not a change to the code that reads it.
//
// `translate` never evaluates the formula: source text -> field-reference normalization (and, for Quickbase, `var`
// declarations and `//` comments) -> `e.algo.formula`'s parser -> a rewritten tree -> canonical text.
// Differences from appdor's: white space in the Quickbase `var` syntax and in `field("...")` is ASCII, and the
// 20,000-character cap counts UTF-8 bytes.

use e.algo.formula as f
use e.mem
use e.str

fn snapshot() -> str { ret "2026-07-17" }

// Diagnostic categories.
fn unknown_function() -> str { ret "unknown-function" }
fn unsupported_feature() -> str { ret "unsupported-feature" }
fn semantic_mismatch() -> str { ret "semantic-mismatch" }
fn cross_record() -> str { ret "cross-record-query-needs-relationship" }
fn unmigrated_column() -> str { ret "references-unmigrated-column" }

fn max_source_length() -> usize { ret 20000usize }

// The mapping tables. `D|id|label|field reference style` opens a dialect; `F|dialect|name|to|reorder|negate arg|
// extra string argument|date-token arg|category|unsupported|note` is one function. `reorder` is a comma list of
// source argument positions; `note` is the warning of a rewritten function or the reason of an unsupported one.
fn row(a: *mem.Arena, s: str, line: str) -> str { ret f.join3(a, s, line, "\n") }

fn table(a: *mem.Arena) -> str {
    var s = ""
    s = row(a, s, "D|airtable|Airtable|brace")
    s = row(a, s, "D|monday|monday.com|brace")
    s = row(a, s, "D|clickup|ClickUp|field")
    s = row(a, s, "D|smartsheet|Smartsheet|bracket")
    s = row(a, s, "D|quickbase|Quickbase|bracket")
    s = row(a, s, "D|notion|Notion|prop")
    s = row(a, s, "D|appsheet|Google AppSheet|bracket")
    s = row(a, s, "F|airtable|RECORD_ID|ROWID|||||context||")
    s = row(a, s, "F|airtable|CREATED_TIME|CREATEDON|||||context||")
    s = row(a, s, "F|airtable|LAST_MODIFIED_TIME|UPDATEDON|||||context||")
    s = row(a, s, "F|airtable|DATETIME_FORMAT|DATETIME_FORMAT||||1|||")
    s = row(a, s, "F|airtable|DATETIME_PARSE|TODATE|||||||")
    s = row(a, s, "F|airtable|WORKDAY_DIFF|NETWORKDAYS|||||||WORKDAY_DIFF maps to NETWORKDAYS; verify holiday handling.")
    s = row(a, s, "F|airtable|ARRAYFLATTEN|FLAT|||||||")
    s = row(a, s, "F|airtable|ENCODE_URL_COMPONENT|URLENCODE|||||||")
    s = row(a, s, "F|airtable|SET_LOCALE|||||||1|Locale coupling has no canonical equivalent; format output via field settings.")
    s = row(a, s, "F|airtable|SET_TIMEZONE|||||||1|Timezone coupling has no canonical equivalent.")
    s = row(a, s, "F|monday|FORMAT_DATE|DATETIME_FORMAT||||1|||")
    s = row(a, s, "F|monday|ADD_DAYS|DATEADD|||days||||")
    s = row(a, s, "F|monday|SUBTRACT_DAYS|DATEADD||1|days||||")
    s = row(a, s, "F|monday|WORKDAYS|NETWORKDAYS|1,0||||||monday WORKDAYS(end, start) reordered to NETWORKDAYS(start, end).")
    s = row(a, s, "F|clickup|DATE_DIFF|DATETIME_DIFF|||||||ClickUp DATE_DIFF signature is documented as approximate; verify units.")
    s = row(a, s, "F|smartsheet|WEEKNUMBER|WEEKNUM|||||||Smartsheet WEEKNUMBER weeks start Monday; canonical WEEKNUM starts Sunday.")
    s = row(a, s, "F|smartsheet|VLOOKUP|LOOKUP|||||||VLOOKUP mapped to LOOKUP; exact-match vs range-match semantics may differ.")
    s = row(a, s, "F|smartsheet|HAS|CONTAINS|||||||")
    s = row(a, s, "F|smartsheet|SUMIFS|||||||1|Multi-criteria SUMIFS has no single-criteria canonical equivalent yet.")
    s = row(a, s, "F|smartsheet|COUNTIFS|||||||1|Multi-criteria COUNTIFS has no single-criteria canonical equivalent yet.")
    s = row(a, s, "F|smartsheet|DESCENDANTS||||||crossrecord||")
    s = row(a, s, "F|smartsheet|PARENT||||||crossrecord||")
    s = row(a, s, "F|quickbase|SEARCHANDREPLACE|SUBSTITUTE|||||||")
    s = row(a, s, "F|quickbase|GETRECORDS|GETRECORDS|||||crossrecord||")
    s = row(a, s, "F|quickbase|GETRECORD|GETRECORDS|||||crossrecord||")
    s = row(a, s, "F|quickbase|GETFIELDVALUES|GETFIELDVALUES|||||crossrecord||")
    s = row(a, s, "F|quickbase|SUMVALUES|SUM|||||crossrecord||")
    s = row(a, s, "F|quickbase|SIZE|COUNTA|||||||")
    s = row(a, s, "F|notion|FORMATDATE|DATETIME_FORMAT||||1|||")
    s = row(a, s, "F|notion|DATEBETWEEN|DATETIME_DIFF|||||||")
    s = row(a, s, "F|notion|DATEADD|DATEADD|||||||")
    s = row(a, s, "F|notion|DATESUBTRACT|DATEADD||1|||||")
    s = row(a, s, "F|notion|TEST|REGEXMATCH|||||||")
    s = row(a, s, "F|notion|REPLACEALL|REGEXREPLACE|||||||")
    s = row(a, s, "F|notion|EMPTY|ISBLANK|||||||")
    s = row(a, s, "F|notion|LENGTH|LEN|||||||")
    s = row(a, s, "F|appsheet|USEREMAIL|USERID|||||context||")
    s = row(a, s, "F|appsheet|USERNAME|USERID|||||context||USERNAME mapped to USERID; canonical exposes an id, not a display name.")
    s = row(a, s, "F|appsheet|USERROLE|USERID|||||context||USERROLE has no canonical equivalent; mapped to USERID.")
    s = row(a, s, "F|appsheet|TEXT_ICON|||||||1|Deliberately unsupported (docs formula.md:29-31): avatar/icon generator is out of scope.")
    s = row(a, s, "F|appsheet|SELECT||||||crossrecord||")
    s = row(a, s, "F|appsheet|FILTER||||||crossrecord||")
    s = row(a, s, "F|appsheet|LOOKUP||||||crossrecord||")
    s = row(a, s, "F|appsheet|EOWEEK|||||||1|No canonical end-of-week function; AppSheet EOWEEK uses Saturday week-end semantics.")
    s = row(a, s, "F|appsheet|OCRTEXT|||||||1|OCR extraction is not a formula function in Neposer.")
    ret s
}

type Dialect = struct { id: str, label: str, refs: str, snapshot: str }

// One function's mapping: `negate` and `date_token` are -1 when absent.
type Mapping = struct {
    dialect: str,
    name: str,
    key: str,
    to: str,
    reorder: str,
    negate: i64,
    add: str,
    date_token: i64,
    category: str,
    unsupported: bool,
    note: str,
}

type Diagnostic = struct { category: str, message: str, function: str, has_function: bool }

// The outcome: status is `converted`, `converted-with-warnings` or `failed`; `canonical` is empty unless
// `has_canonical`; `warnings` are the diagnostics that are not fatal.
type Result = struct {
    status: str,
    canonical: str,
    has_canonical: bool,
    diagnostics: []const Diagnostic,
    warnings: []const Diagnostic,
    source: str,
    dialect: str,
    snapshot: str,
}

type Ranked = struct { dialect: str, score: i64 }

// --- the table ----------------------------------------------------------------------------------------------------

fn count_lines(s: str, tag: u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if (i == 0usize || s[i - 1usize] == 10u8) && s[i] == tag && i + 1usize < s.len && s[i + 1usize] == 124u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

// The `|` separated cells of a line, empty cells kept.
fn cells(a: *mem.Arena, line: str, out: []str) -> usize {
    var n = 0usize
    var from = 0usize
    var i = 0usize
    while i <= line.len {
        if i == line.len || line[i] == 124u8 {
            if n < out.len { out[n] = line[from..i] }
            n += 1usize
            from = i + 1usize
        }
        i += 1usize
    }
    ret n
}

fn parse_index(s: str) -> i64 {
    if s.len == 0usize { ret -1i64 }
    var v = 0i64
    var i = 0usize
    while i < s.len {
        v = v * 10i64 + i64(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

fn dialects(a: *mem.Arena) -> []Dialect {
    let src = table(a)
    let count = count_lines(src, 68u8)
    var none: []Dialect = zero
    let (out, e) = mem.alloc[Dialect](a, count)
    if e != ok { ret none }
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i < src.len {
        if src[i] == 10u8 {
            let line = src[start..i]
            if line.len > 2usize && line[0usize] == 68u8 {
                var c: [8]str = zero
                let k = cells(a, line, c[0..])
                if k >= 4usize {
                    out[n] = Dialect { id: c[1usize], label: c[2usize], refs: c[3usize], snapshot: snapshot() }
                    n += 1usize
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn mappings(a: *mem.Arena, dialect: str) -> []Mapping {
    let src = table(a)
    var none: []Mapping = zero
    let (out, e) = mem.alloc[Mapping](a, count_lines(src, 70u8))
    if e != ok { ret none }
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i < src.len {
        if src[i] == 10u8 {
            let line = src[start..i]
            if line.len > 2usize && line[0usize] == 70u8 {
                var c: [12]str = zero
                let k = cells(a, line, c[0..])
                if k >= 11usize && str.eq(c[1usize], dialect) {
                    out[n] = Mapping {
                        dialect: c[1usize], name: c[2usize], key: f.normalize_name(a, c[2usize]), to: c[3usize], reorder: c[4usize],
                        negate: parse_index(c[5usize]), add: c[6usize], date_token: parse_index(c[7usize]), category: c[8usize],
                        unsupported: str.eq(c[9usize], "1"), note: c[10usize],
                    }
                    n += 1usize
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn find_mapping(entries: []const Mapping, key: str) -> (usize, bool) {
    var i = 0usize
    while i < entries.len {
        if str.eq(entries[i].key, key) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// --- text scanning ------------------------------------------------------------------------------------------------

fn is_word(b: u8) -> bool { ret (b >= 48u8 && b <= 57u8) || (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) || b == 95u8 }

fn is_letter(b: u8) -> bool { ret (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) }

fn is_space(b: u8) -> bool { ret b == 32u8 || (b >= 9u8 && b <= 13u8) }

fn fold(b: u8) -> u8 {
    if b >= 65u8 && b <= 90u8 { ret b + 32u8 }
    ret b
}

// JavaScript's `trim` for the ASCII white space this module reads.
fn trim(s: str) -> str { ret str.trim(s) }

fn starts_fold(s: str, at: usize, word: str) -> bool {
    if at + word.len > s.len { ret false }
    var i = 0usize
    while i < word.len {
        if fold(s[at + i]) != fold(word[i]) { ret false }
        i += 1usize
    }
    ret true
}

// `/\bWORD\(\s*["']([^"']+)["']\s*\)/gi` replaced by `{$1}`.
fn replace_call_refs(a: *mem.Arena, text: str, word: str) -> str {
    let (out, e) = mem.alloc[u8](a, text.len + 1usize)
    if e != ok { ret text }
    var n = 0usize
    var i = 0usize
    while i < text.len {
        var matched = false
        var end = 0usize
        var name_from = 0usize
        var name_to = 0usize
        if (i == 0usize || !is_word(text[i - 1usize])) && starts_fold(text, i, word) {
            var p = i + word.len
            if p < text.len && text[p] == 40u8 {
                p += 1usize
                while p < text.len && is_space(text[p]) { p += 1usize }
                if p < text.len && (text[p] == 34u8 || text[p] == 39u8) {
                    p += 1usize
                    name_from = p
                    while p < text.len && text[p] != 34u8 && text[p] != 39u8 { p += 1usize }
                    name_to = p
                    if p > name_from && p < text.len {
                        p += 1usize
                        while p < text.len && is_space(text[p]) { p += 1usize }
                        if p < text.len && text[p] == 41u8 {
                            matched = true
                            end = p + 1usize
                        }
                    }
                }
            }
        }
        if matched {
            // `{name}` is never longer than the call it replaces
            out[n] = 123u8
            n += 1usize
            var k = name_from
            while k < name_to {
                out[n] = text[k]
                n += 1usize
                k += 1usize
            }
            out[n] = 125u8
            n += 1usize
            i = end
        } else {
            out[n] = text[i]
            n += 1usize
            i += 1usize
        }
    }
    ret out[0usize..n]
}

// Every `[Name]` outside a string literal becomes `{Name}`; a bracket must start with a letter so array literals
// stay. Escapes inside a literal are honoured.
fn replace_brackets(a: *mem.Arena, text: str) -> str {
    let (out, e) = mem.alloc[u8](a, text.len + 1usize)
    if e != ok { ret text }
    var n = 0usize
    var i = 0usize
    var quote = 0u8
    while i < text.len {
        let ch = text[i]
        if quote != 0u8 {
            if ch == 92u8 && i + 1usize < text.len {
                out[n] = ch
                out[n + 1usize] = text[i + 1usize]
                n += 2usize
                i += 2usize
            } else {
                if ch == quote { quote = 0u8 }
                out[n] = ch
                n += 1usize
                i += 1usize
            }
        } else if ch == 34u8 || ch == 39u8 {
            quote = ch
            out[n] = ch
            n += 1usize
            i += 1usize
        } else {
            var matched = false
            var close = 0usize
            if ch == 91u8 && i + 1usize < text.len && is_letter(text[i + 1usize]) {
                var p = i + 2usize
                while p < text.len && text[p] != 93u8 { p += 1usize }
                if p < text.len {
                    matched = true
                    close = p
                }
            }
            if matched {
                let name = trim(text[i + 1usize..close])
                out[n] = 123u8
                n += 1usize
                var k = 0usize
                while k < name.len {
                    out[n] = name[k]
                    n += 1usize
                    k += 1usize
                }
                out[n] = 125u8
                n += 1usize
                i = close + 1usize
            } else {
                out[n] = ch
                n += 1usize
                i += 1usize
            }
        }
    }
    ret out[0usize..n]
}

fn normalize_refs(a: *mem.Arena, text: str, refs: str) -> str {
    if str.eq(refs, "field") { ret replace_call_refs(a, text, "field") }
    if str.eq(refs, "prop") { ret replace_call_refs(a, text, "prop") }
    if str.eq(refs, "bracket") { ret replace_brackets(a, text) }
    ret text
}

// --- Quickbase `var` declarations and comments ---------------------------------------------------------------------

// `var [type] name = expression` over a trimmed statement.
fn match_var(p: str) -> (str, str, bool) {
    if p.len < 4usize || !starts_fold(p, 0usize, "var") || !is_space(p[3usize]) { ret ("", "", false) }
    var i = 3usize
    while i < p.len && is_space(p[i]) { i += 1usize }
    // with an optional type word first
    if i < p.len && is_letter(p[i]) {
        var j = i
        while j < p.len && is_word(p[j]) { j += 1usize }
        var k = j
        while k < p.len && is_space(p[k]) { k += 1usize }
        if k > j && k < p.len && (is_letter(p[k]) || p[k] == 95u8) {
            var m = k
            while m < p.len && is_word(p[m]) { m += 1usize }
            let name = p[k..m]
            var q = m
            while q < p.len && is_space(p[q]) { q += 1usize }
            if q < p.len && p[q] == 61u8 {
                q += 1usize
                while q < p.len && is_space(p[q]) { q += 1usize }
                if q < p.len { ret (name, p[q..p.len], true) }
            }
        }
    }
    if i < p.len && (is_letter(p[i]) || p[i] == 95u8) {
        var m = i
        while m < p.len && is_word(p[m]) { m += 1usize }
        let name = p[i..m]
        var q = m
        while q < p.len && is_space(p[q]) { q += 1usize }
        if q < p.len && p[q] == 61u8 {
            q += 1usize
            while q < p.len && is_space(p[q]) { q += 1usize }
            if q < p.len { ret (name, p[q..p.len], true) }
        }
    }
    ret ("", "", false)
}

// The formula text with its declarations folded into `lets(...)` and its comments set aside.
fn quickbase_text(a: *mem.Arena, text: str, comments: []str, comment_count: []usize) -> str {
    // comments are stripped line by line
    let (clean, ce) = mem.alloc[u8](a, text.len + 1usize)
    if ce != ok { ret text }
    var w = 0usize
    var line_start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 10u8 {
            let line = text[line_start..i]
            let (cut, found) = str.find(line, "//")
            var keep = line
            if found {
                let c = trim(line[cut + 2usize..line.len])
                if c.len > 0usize {
                    comments[comment_count[0usize]] = c
                    comment_count[0usize] = comment_count[0usize] + 1usize
                }
                keep = line[0usize..cut]
            }
            var k = 0usize
            while k < keep.len {
                clean[w] = keep[k]
                w += 1usize
                k += 1usize
            }
            if i < text.len {
                clean[w] = 10u8
                w += 1usize
            }
            line_start = i + 1usize
        }
        i += 1usize
    }
    let no_comments: str = clean[0usize..w]
    // statements split on `;`
    var names: []str = zero
    var exprs: []str = zero
    let (name_cells, ne) = mem.alloc[str](a, no_comments.len + 2usize)
    let (expr_cells, xe) = mem.alloc[str](a, no_comments.len + 2usize)
    if ne != ok || xe != ok { ret text }
    names = name_cells
    exprs = expr_cells
    var vars = 0usize
    var body = ""
    var has_body = false
    var from = 0usize
    var p = 0usize
    while p <= no_comments.len {
        if p == no_comments.len || no_comments[p] == 59u8 {
            let part = trim(no_comments[from..p])
            if part.len > 0usize {
                let (name, expr, is_var) = match_var(part)
                if is_var {
                    names[vars] = name
                    exprs[vars] = trim(expr)
                    vars += 1usize
                } else {
                    body = part
                    has_body = true
                }
            }
            from = p + 1usize
        }
        p += 1usize
    }
    if !has_body && vars > 0usize {
        body = names[vars - 1usize]
        has_body = true
    }
    if vars == 0usize {
        if has_body { ret body }
        ret no_comments
    }
    var out = "lets("
    var k = 0usize
    while k < vars {
        if k > 0usize { out = f.join(a, out, ", ") }
        out = f.join(a, f.join(a, f.join(a, out, names[k]), ", "), exprs[k])
        k += 1usize
    }
    ret f.join(a, f.join(a, f.join(a, out, ", "), body), ")")
}

// --- the tree transform --------------------------------------------------------------------------------------------

type Work = struct {
    a: *mem.Arena,
    reg: *const f.Registry,
    dialect: str,
    entries: []const Mapping,
    columns: []const str,
    diags: []Diagnostic,
    count: usize,
}

fn report(w: *Work, category: str, message: str, function: str, has_function: bool) {
    if w.count < w.diags.len {
        w.diags[w.count] = Diagnostic { category: category, message: message, function: function, has_function: has_function }
        w.count += 1usize
    }
}

// The seam for dialects whose date-format tokens diverge from the canonical (moment-style) set; today the identity.
fn translate_date_tokens(value: str, dialect: str) -> str { ret value }

fn kids_of(a: *mem.Arena, n: usize) -> []f.Node {
    var none: []f.Node = zero
    if n == 0usize { ret none }
    let (k, e) = mem.alloc[f.Node](a, n)
    if e != ok { ret none }
    ret k
}


fn number_at(s: str, from: usize) -> (usize, usize) {
    var to = from
    while to < s.len && s[to] >= 48u8 && s[to] <= 57u8 { to += 1usize }
    ret (from, to)
}

fn apply_rewrites(w: *Work, node: f.Node, m: Mapping) -> f.Node {
    var args = node.kids
    if m.reorder.len > 0usize {
        let out = kids_of(w.a, args.len + 8usize)
        var n = 0usize
        var i = 0usize
        while i <= m.reorder.len {
            if i == m.reorder.len || m.reorder[i] == 44u8 {
                i += 1usize
            } else {
                let (from, to) = number_at(m.reorder, i)
                let idx = usize(parse_index(m.reorder[from..to]))
                if idx < args.len && n < out.len {
                    out[n] = args[idx]
                    n += 1usize
                }
                i = to
            }
        }
        args = out[0usize..n]
    }
    if m.negate >= 0i64 && usize(m.negate) < args.len {
        let out = kids_of(w.a, args.len)
        var i = 0usize
        while i < args.len {
            out[i] = args[i]
            i += 1usize
        }
        var negated = f.leaf(.Unary)
        negated.op = "-"
        let operand = kids_of(w.a, 1usize)
        operand[0usize] = args[usize(m.negate)]
        negated.kids = operand
        out[usize(m.negate)] = negated
        args = out[0usize..args.len]
    }
    if m.date_token >= 0i64 && usize(m.date_token) < args.len && args[usize(m.date_token)].kind == .String {
        let out = kids_of(w.a, args.len)
        var i = 0usize
        while i < args.len {
            out[i] = args[i]
            i += 1usize
        }
        var s = f.leaf(.String)
        s.s = translate_date_tokens(args[usize(m.date_token)].s, w.dialect)
        out[usize(m.date_token)] = s
        args = out[0usize..args.len]
    }
    if m.add.len > 0usize {
        let out = kids_of(w.a, args.len + 1usize)
        var i = 0usize
        while i < args.len {
            out[i] = args[i]
            i += 1usize
        }
        var s = f.leaf(.String)
        s.s = m.add
        out[args.len] = s
        args = out[0usize..args.len + 1usize]
    }
    var result = node
    result.kids = args
    ret result
}

fn map_call(w: *Work, node: f.Node) -> f.Node {
    let key = f.normalize_name(w.a, node.s)
    let (at, found) = find_mapping(w.entries, key)
    if found {
        let m = w.entries[at]
        if m.unsupported {
            report(w, unsupported_feature(), f.join3(w.a, node.s, ": ", m.note), node.s, true)
            ret node
        }
        if str.eq(m.category, "crossrecord") {
            report(w, cross_record(), f.join(w.a, node.s, " aggregates across records and needs a migrated relationship."), node.s, true)
        }
        if m.note.len > 0usize {
            report(w, semantic_mismatch(), f.join3(w.a, node.s, ": ", m.note), node.s, true)
        }
        var result = apply_rewrites(w, node, m)
        if m.to.len > 0usize { result.s = m.to }
        ret result
    }
    let (index, known) = f.resolve(w.a, w.reg, node.s)
    if known {
        var result = node
        result.s = f.entry_at(w.reg, index).name
        ret result
    }
    report(w, unknown_function(), f.join(w.a, f.join(w.a, f.join(w.a, "Unknown function \"", node.s), "\" in dialect "), f.join(w.a, w.dialect, ".")), node.s, true)
    ret node
}

fn column_known(a: *mem.Arena, columns: []const str, name: str) -> bool {
    let want = f.lower_text(a, name)
    var i = 0usize
    while i < columns.len {
        if str.eq(f.lower_text(a, columns[i]), want) { ret true }
        i += 1usize
    }
    ret false
}

fn transform(w: *Work, node: f.Node) -> f.Node {
    if node.kind == .Field {
        if w.columns.len > 0usize && !column_known(w.a, w.columns, node.s) {
            report(w, unmigrated_column(), f.join3(w.a, "Column \"", node.s, "\" was not found in the migrated table."), node.s, true)
        }
        ret node
    }
    if node.kind == .Array || node.kind == .Unary || node.kind == .Binary || node.kind == .Ternary || node.kind == .Call {
        var result = node
        if node.kids.len > 0usize {
            let out = kids_of(w.a, node.kids.len)
            var i = 0usize
            while i < node.kids.len {
                out[i] = transform(w, node.kids[i])
                i += 1usize
            }
            result.kids = out[0usize..node.kids.len]
        }
        if node.kind == .Call { ret map_call(w, result) }
        ret result
    }
    ret node
}

// --- canonical text ------------------------------------------------------------------------------------------------

fn op_prec(op: str) -> i32 {
    if str.eq(op, "||") { ret 2i32 }
    if str.eq(op, "&&") { ret 3i32 }
    if str.eq(op, "&") { ret 5i32 }
    if str.eq(op, "+") || str.eq(op, "-") { ret 6i32 }
    if str.eq(op, "*") || str.eq(op, "/") || str.eq(op, "%") { ret 7i32 }
    if str.eq(op, "^") { ret 8i32 }
    ret 4i32
}

fn node_prec(node: f.Node) -> i32 {
    if node.kind == .Ternary { ret 1i32 }
    if node.kind == .Binary { ret op_prec(node.op) }
    if node.kind == .Unary { ret 9i32 }
    ret 10i32
}

fn quote_text(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 2usize + 2usize)
    if e != ok { ret "\"\"" }
    var n = 0usize
    out[n] = 34u8
    n += 1usize
    var i = 0usize
    while i < s.len {
        let b = s[i]
        if b == 92u8 || b == 34u8 {
            out[n] = 92u8
            out[n + 1usize] = b
            n += 2usize
        } else if b == 10u8 {
            out[n] = 92u8
            out[n + 1usize] = 110u8
            n += 2usize
        } else if b == 9u8 {
            out[n] = 92u8
            out[n + 1usize] = 116u8
            n += 2usize
        } else if b == 13u8 {
            out[n] = 92u8
            out[n + 1usize] = 114u8
            n += 2usize
        } else {
            out[n] = b
            n += 1usize
        }
        i += 1usize
    }
    out[n] = 34u8
    n += 1usize
    ret out[0usize..n]
}

fn is_simple_name(s: str) -> bool {
    if s.len == 0usize { ret false }
    if !(is_letter(s[0usize]) || s[0usize] == 95u8 || s[0usize] == 36u8) { ret false }
    var i = 1usize
    while i < s.len {
        if !(is_word(s[i]) || s[i] == 36u8) { ret false }
        i += 1usize
    }
    ret true
}

fn upper_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn wrapped(a: *mem.Arena, child: f.Node, parent_prec: i32, right_side: bool, parent_op: str, check_side: bool) -> str {
    let cp = node_prec(child)
    var need = cp < parent_prec
    if cp == parent_prec && child.kind == .Binary && check_side {
        if str.eq(parent_op, "^") { need = !right_side } else { need = right_side }
    }
    if child.kind == .Ternary { need = true }
    let text = stringify(a, child)
    if need { ret f.join3(a, "(", text, ")") }
    ret text
}

// The canonical text of a tree; precedence-aware so it re-parses to the same tree.
fn stringify(a: *mem.Arena, node: f.Node) -> str {
    if node.kind == .Number { ret f.number_text(a, node.n) }
    if node.kind == .String { ret quote_text(a, node.s) }
    if node.kind == .Bool {
        if node.b { ret "true" }
        ret "false"
    }
    if node.kind == .Null { ret "BLANK()" }
    if node.kind == .Field { ret f.join3(a, "{", node.s, "}") }
    if node.kind == .Name {
        if is_simple_name(node.s) { ret node.s }
        ret f.join3(a, "{", node.s, "}")
    }
    if node.kind == .Array || node.kind == .Call {
        var out = ""
        var i = 0usize
        while i < node.kids.len {
            if i > 0usize { out = f.join(a, out, ", ") }
            out = f.join(a, out, stringify(a, node.kids[i]))
            i += 1usize
        }
        if node.kind == .Array { ret f.join3(a, "[", out, "]") }
        ret f.join(a, f.join3(a, upper_ascii(a, node.s), "(", out), ")")
    }
    if node.kind == .Unary {
        let operand = wrapped(a, node.kids[0usize], 9i32, false, node.op, false)
        ret f.join(a, node.op, operand)
    }
    if node.kind == .Binary {
        let p = op_prec(node.op)
        var op = node.op
        if str.eq(op, "==") { op = "=" }
        if str.eq(op, "<>") { op = "!=" }
        let left = wrapped(a, node.kids[0usize], p, false, node.op, true)
        let right = wrapped(a, node.kids[1usize], p, true, node.op, true)
        ret f.join(a, f.join3(a, left, " ", op), f.join(a, " ", right))
    }
    if node.kind == .Ternary {
        var cond = stringify(a, node.kids[0usize])
        if node.kids[0usize].kind == .Ternary { cond = f.join3(a, "(", cond, ")") }
        ret f.join(a, f.join3(a, cond, " ? ", stringify(a, node.kids[1usize])), f.join(a, " : ", stringify(a, node.kids[2usize])))
    }
    ret ""
}

// --- the public surface ---------------------------------------------------------------------------------------------

fn is_fatal(category: str) -> bool { ret str.eq(category, unknown_function()) || str.eq(category, unsupported_feature()) }

fn finish(a: *mem.Arena, source: str, dialect: str, diags: []Diagnostic, count: usize, canonical: str, has_canonical: bool) -> Result {
    var warnings: []Diagnostic = zero
    let (w, e) = mem.alloc[Diagnostic](a, count + 1usize)
    var wn = 0usize
    if e == ok {
        var i = 0usize
        while i < count {
            if !is_fatal(diags[i].category) {
                w[wn] = diags[i]
                wn += 1usize
            }
            i += 1usize
        }
        warnings = w[0usize..wn]
    }
    var status = "failed"
    if has_canonical {
        status = "converted"
        if count > 0usize { status = "converted-with-warnings" }
    }
    ret Result { status: status, canonical: canonical, has_canonical: has_canonical, diagnostics: diags[0usize..count], warnings: warnings, source: source, dialect: dialect, snapshot: snapshot() }
}

// Translate `source` from `dialect`'s syntax to canonical formula text. `columns` are the migrated table's column
// names (empty to skip the unmigrated-column check) and `reg` resolves function names and aliases.
fn translate(a: *mem.Arena, reg: *const f.Registry, source: str, dialect: str, columns: []const str) -> Result {
    let (diags, de) = mem.alloc[Diagnostic](a, source.len + 16usize)
    var none: []Diagnostic = zero
    if de != ok { ret finish(a, source, dialect, none, 0usize, "", false) }
    var w = Work { a: a, reg: reg, dialect: dialect, entries: zero_mappings(), columns: columns, diags: diags, count: 0usize }
    let known = dialects(a)
    var refs = ""
    var found = false
    var i = 0usize
    while i < known.len {
        if str.eq(known[i].id, dialect) {
            refs = known[i].refs
            found = true
        }
        i += 1usize
    }
    if !found {
        report(&w, unsupported_feature(), f.join3(a, "Unknown dialect \"", dialect, "\"."), "", false)
        ret finish(a, source, dialect, diags, w.count, "", false)
    }
    if source.len > max_source_length() {
        report(&w, unsupported_feature(), "Formula is empty or exceeds the maximum supported length.", "", false)
        ret finish(a, source, dialect, diags, w.count, "", false)
    }
    w.entries = mappings(a, dialect)
    let (comments_buffer, comments_error) = mem.alloc[str](a, source.len / 2usize + 2usize)
    if comments_error != ok { ret finish(a, source, dialect, diags, w.count, "", false) }
    var comment_count = 0usize
    var prepared = ""
    if str.eq(dialect, "quickbase") {
        var counter: [1]usize = zero
        let text = quickbase_text(a, source, comments_buffer, counter[0..])
        comment_count = counter[0usize]
        prepared = normalize_refs(a, text, refs)
    } else {
        prepared = normalize_refs(a, source, refs)
    }
    let (tree, diag) = f.parse(a, prepared, 0usize)
    if !diag.good {
        report(&w, unsupported_feature(), f.join(a, f.join3(a, "Could not parse ", dialect, " formula: "), diag.message), "", false)
        ret finish(a, source, dialect, diags, w.count, "", false)
    }
    let out = transform(&w, tree)
    var fatal = false
    i = 0usize
    while i < w.count {
        if is_fatal(diags[i].category) { fatal = true }
        i += 1usize
    }
    if fatal { ret finish(a, source, dialect, diags, w.count, "", false) }
    var canonical = stringify(a, out)
    i = 0usize
    while i < comment_count {
        canonical = f.join(a, f.join(a, canonical, "\n// "), comments_buffer[i])
        i += 1usize
    }
    ret finish(a, source, dialect, diags, w.count, canonical, true)
}

fn zero_mappings() -> []const Mapping {
    var none: []const Mapping = zero
    ret none
}

// How likely each dialect wrote the pasted text: the dialects by descending score (ties in table order).
fn detect(a: *mem.Arena, source: str) -> []Ranked {
    let known = dialects(a)
    var none: []Ranked = zero
    let (out, e) = mem.alloc[Ranked](a, known.len)
    if e != ok { ret none }
    // which reference styles the text shows
    var has_field = false
    var has_prop = false
    var has_bracket = false
    var has_brace = false
    var has_var = false
    var notion_hint = false
    var i = 0usize
    while i < source.len {
        if (i == 0usize || !is_word(source[i - 1usize])) && starts_fold(source, i, "field") {
            var p = i + 5usize
            if p < source.len && source[p] == 40u8 {
                p += 1usize
                while p < source.len && is_space(source[p]) { p += 1usize }
                if p < source.len && (source[p] == 34u8 || source[p] == 39u8) { has_field = true }
            }
        }
        if (i == 0usize || !is_word(source[i - 1usize])) && starts_fold(source, i, "prop") {
            var p = i + 4usize
            if p < source.len && source[p] == 40u8 {
                p += 1usize
                while p < source.len && is_space(source[p]) { p += 1usize }
                if p < source.len && (source[p] == 34u8 || source[p] == 39u8) { has_prop = true }
            }
        }
        if source[i] == 91u8 && i + 1usize < source.len && is_letter(source[i + 1usize]) {
            var p = i + 2usize
            while p < source.len && source[p] != 93u8 { p += 1usize }
            if p < source.len { has_bracket = true }
        }
        if source[i] == 123u8 {
            var p = i + 1usize
            while p < source.len && source[p] != 125u8 { p += 1usize }
            if p < source.len && p > i + 1usize { has_brace = true }
        }
        if (i == 0usize || !is_word(source[i - 1usize])) && starts_fold(source, i, "var") && i + 3usize < source.len && is_space(source[i + 3usize]) {
            var p = i + 3usize
            while p < source.len && is_space(source[p]) { p += 1usize }
            if p < source.len && is_letter(source[p]) { has_var = true }
        }
        i += 1usize
    }
    // `(prop|lets?|formatDate|dateBetween)\s*\(` as written
    i = 0usize
    while i < source.len {
        if i == 0usize || !is_word(source[i - 1usize]) {
            var word = 0usize
            if i + 4usize <= source.len && str.eq(source[i..i + 4usize], "prop") { word = 4usize }
            if i + 3usize <= source.len && str.eq(source[i..i + 3usize], "let") { word = 3usize }
            if i + 4usize <= source.len && str.eq(source[i..i + 4usize], "lets") { word = 4usize }
            if i + 10usize <= source.len && str.eq(source[i..i + 10usize], "formatDate") { word = 10usize }
            if i + 11usize <= source.len && str.eq(source[i..i + 11usize], "dateBetween") { word = 11usize }
            if word > 0usize {
                var p = i + word
                while p < source.len && is_space(source[p]) { p += 1usize }
                if p < source.len && source[p] == 40u8 { notion_hint = true }
            }
        }
        i += 1usize
    }
    var d = 0usize
    while d < known.len {
        var score = 0i64
        let refs = known[d].refs
        if str.eq(refs, "field") && has_field { score += 2i64 }
        if str.eq(refs, "prop") && has_prop { score += 2i64 }
        if str.eq(refs, "bracket") && has_bracket { score += 2i64 }
        if str.eq(refs, "brace") && has_brace { score += 2i64 }
        let entries = mappings(a, known[d].id)
        // every `identifier(` in the text that the dialect maps
        var p = 0usize
        while p < source.len {
            if is_letter(source[p]) || source[p] == 95u8 {
                var q = p
                while q < source.len && is_word(source[q]) { q += 1usize }
                var r = q
                while r < source.len && is_space(source[r]) { r += 1usize }
                if r < source.len && source[r] == 40u8 {
                    let (at, hit) = find_mapping(entries, f.normalize_name(a, source[p..q]))
                    if hit { score += 1i64 }
                    p = r + 1usize
                } else {
                    p += 1usize
                }
            } else {
                p += 1usize
            }
        }
        if str.eq(known[d].id, "quickbase") && has_var { score += 3i64 }
        if str.eq(known[d].id, "notion") && notion_hint { score += 1i64 }
        out[d] = Ranked { dialect: known[d].id, score: score }
        d += 1usize
    }
    // stable by descending score
    var x = 1usize
    while x < out.len {
        let item = out[x]
        var y = x
        while y > 0usize && out[y - 1usize].score < item.score {
            out[y] = out[y - 1usize]
            y -= 1usize
        }
        out[y] = item
        x += 1usize
    }
    ret out
}
