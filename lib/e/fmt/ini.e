// INI: sections, `key=value`, line comments, quoted values with backslash escapes. No
// interpolation and no includes, which the fence excludes on purpose -- both turn a
// configuration file into a program, and a reader of one should not have to be an interpreter.
//
// The format has no standard, so every choice here is one. Two shape the rest:
//
// A comment starts a line and nothing else. `;` and `#` are ordinary bytes anywhere after the
// first, including inside an unquoted value and after a closing quote. The alternative -- a
// trailing comment -- means a value silently loses everything past a `;` someone meant as data,
// and no spelling of the value can be read back without knowing which rule was in force.
//
// `case_sensitive: false` **folds** the section and the key as they are stored, rather than
// comparing loosely later. `get` takes no options and a `Document` carries none, so identity has
// to be a property of what was stored: after folding, two names that differ only in case are the
// same bytes, duplicate detection is plain equality, and `get` needs no rule of its own. What a
// caller gives up is the spelling, which `write` then emits folded -- honestly, since they asked
// for the distinction not to matter.

use e.io
use e.mem
use e.meta
use e.str

type Entry = struct {
    section: str,
    key: str,
    value: str,
}

type Document = struct {
    entries: []const Entry,
}

type Reader = struct {
    state: *void,
}

type Options = struct {
    case_sensitive: bool,
    allow_duplicate_keys: bool,
}

error Invalid
error DuplicateKey
error TooLarge

const TAB: u8 = 9u8
const LF: u8 = 10u8
const CR: u8 = 13u8
const SPACE: u8 = 32u8
const HASH: u8 = 35u8
const DQUOTE: u8 = 34u8
const SEMI: u8 = 59u8
const EQUALS: u8 = 61u8
const LBRACKET: u8 = 91u8
const RBRACKET: u8 = 93u8
const BACKSLASH: u8 = 92u8
const UPPER_A: u8 = 65u8
const UPPER_Z: u8 = 90u8
const CASE_GAP: u8 = 32u8

// The streaming reader's bounds. `parse` has the whole source already and needs neither.
const MAX_LINE: usize = 4096usize
const INPUT_CAPACITY: usize = 4096usize
// ponytail: duplicate detection over a stream is a linear scan of what has been seen, so it is
// O(n^2) in entries and capped rather than unbounded. A set keyed by hash is the upgrade, and
// `e.data.map` is where it would come from once that module exists.
const MAX_SEEN: usize = 1024usize

const LINE_BLANK: u8 = 0u8
const LINE_SECTION: u8 = 1u8
const LINE_ENTRY: u8 = 2u8

// What one line turned out to be. Every byte of it borrows the line it was read from; nothing
// here is unescaped yet, because only the caller has somewhere to put the result.
type Line = struct {
    kind: u8,
    name: str,
    key: str,
    value: str,
    quoted: bool,
}

type ReaderState = struct {
    source: io.Reader,
    options: Options,
    arena: *mem.Arena,
    input: []u8,
    input_at: usize,
    input_len: usize,
    line: []u8,
    key: []u8,
    key_len: usize,
    value: []u8,
    value_len: usize,
    section: []u8,
    section_len: usize,
    seen_section: []str,
    seen_key: []str,
    seen_count: usize,
    ended: bool,
}

fn is_space(byte: u8) -> bool {
    ret byte == SPACE || byte == TAB
}

fn trim(text: str) -> str {
    var start = 0usize
    while start < text.len && is_space(text[start]) { start += 1usize }
    var stop = text.len
    while stop > start && is_space(text[stop - 1usize]) { stop -= 1usize }
    ret text[start..stop]
}

fn lower(byte: u8) -> u8 {
    if byte >= UPPER_A && byte <= UPPER_Z { ret byte + CASE_GAP }
    ret byte
}

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

// The escapes this accepts, and no others: an unknown one is a mistake worth reporting rather
// than a byte to pass through, since passing it through makes `\n` in a path silently a newline
// on one reader and two characters on the next.
fn escape_byte(byte: u8) -> (u8, bool) {
    if byte == 110u8 { ret (LF, true) }
    if byte == 116u8 { ret (TAB, true) }
    if byte == 114u8 { ret (CR, true) }
    if byte == 48u8 { ret (0u8, true) }
    if byte == BACKSLASH { ret (BACKSLASH, true) }
    if byte == DQUOTE { ret (DQUOTE, true) }
    if byte == SEMI { ret (SEMI, true) }
    if byte == HASH { ret (HASH, true) }
    if byte == EQUALS { ret (EQUALS, true) }
    ret (0u8, false)
}

// One line, already stripped of its ending. What it is, and where its parts are.
fn classify(text: str) -> (Line, err) {
    var out: Line = zero
    let line = trim(text)
    if line.len == 0usize { ret (out, ok) }
    if line[0usize] == SEMI || line[0usize] == HASH { ret (out, ok) }
    if line[0usize] == LBRACKET {
        if line[line.len - 1usize] != RBRACKET { ret (out, Invalid) }
        let name = trim(line[1usize..line.len - 1usize])
        if name.len == 0usize { ret (out, Invalid) }
        out.kind = LINE_SECTION
        out.name = name
        ret (out, ok)
    }
    var at = 0usize
    var found = false
    while at < line.len {
        if line[at] == EQUALS {
            found = true
            break
        }
        at += 1usize
    }
    if !found { ret (out, Invalid) }
    let key = trim(line[0usize..at])
    if key.len == 0usize { ret (out, Invalid) }
    out.kind = LINE_ENTRY
    out.key = key
    out.value = trim(line[at + 1usize..line.len])
    if out.value.len != 0usize && out.value[0usize] == DQUOTE { out.quoted = true }
    ret (out, ok)
}

// A quoted value into `out`, unescaped. The opening quote is `raw[0]`; what follows the closing
// one may only be whitespace, because a comment is a line and this line has already begun.
fn unescape(raw: str, out: []u8) -> (usize, err) {
    if raw.len < 2usize { ret (0usize, Invalid) }
    var at = 1usize
    var written = 0usize
    var closed = false
    while at < raw.len {
        let byte = raw[at]
        if byte == DQUOTE {
            closed = true
            at += 1usize
            break
        }
        if byte == BACKSLASH {
            at += 1usize
            if at >= raw.len { ret (0usize, Invalid) }
            let (decoded, known) = escape_byte(raw[at])
            if !known { ret (0usize, Invalid) }
            if written == out.len { ret (0usize, TooLarge) }
            out[written] = decoded
            written += 1usize
            at += 1usize
            continue
        }
        if written == out.len { ret (0usize, TooLarge) }
        out[written] = byte
        written += 1usize
        at += 1usize
    }
    if !closed { ret (0usize, Invalid) }
    if trim(raw[at..raw.len]).len != 0usize { ret (0usize, Invalid) }
    ret (written, ok)
}

// An unquoted value is its own bytes, so both kinds reach the caller the same way: as a count
// of bytes written into a buffer it owns.
fn place_value(line: Line, out: []u8) -> (usize, err) {
    if line.quoted {
        let (written, unescape_error) = unescape(line.value, out)
        ret (written, unescape_error)
    }
    if line.value.len > out.len { ret (0usize, TooLarge) }
    var at = 0usize
    while at < line.value.len {
        out[at] = line.value[at]
        at += 1usize
    }
    ret (line.value.len, ok)
}

fn place_name(text: str, out: []u8, case_sensitive: bool) -> (usize, err) {
    if text.len > out.len { ret (0usize, TooLarge) }
    var at = 0usize
    while at < text.len {
        if case_sensitive {
            out[at] = text[at]
        } else {
            out[at] = lower(text[at])
        }
        at += 1usize
    }
    ret (text.len, ok)
}

// A name as it will be stored. When it is already what it should be, it is borrowed rather than
// copied -- which is every name of a case-sensitive parse, and most of the others.
fn stored_name(a: *mem.Arena, text: str, case_sensitive: bool) -> (str, err) {
    if case_sensitive { ret (text, ok) }
    var at = 0usize
    var differs = false
    while at < text.len {
        if text[at] != lower(text[at]) {
            differs = true
            break
        }
        at += 1usize
    }
    if !differs { ret (text, ok) }
    let (buffer, allocation_error) = mem.alloc[u8](a, text.len)
    if allocation_error != ok { ret ("", allocation_error) }
    at = 0usize
    while at < text.len {
        buffer[at] = lower(text[at])
        at += 1usize
    }
    ret (buffer, ok)
}

fn copy_out(a: *mem.Arena, text: str) -> (str, err) {
    if text.len == 0usize { ret ("", ok) }
    let (buffer, allocation_error) = mem.alloc[u8](a, text.len)
    if allocation_error != ok { ret ("", allocation_error) }
    var at = 0usize
    while at < text.len {
        buffer[at] = text[at]
        at += 1usize
    }
    ret (buffer, ok)
}

// The next line of a source held whole, and where the one after it starts. A CR before the LF
// belongs to the ending rather than to the line.
fn slice_line(source: str, from: usize) -> (str, usize) {
    var at = from
    while at < source.len && source[at] != LF { at += 1usize }
    var stop = at
    if stop > from && source[stop - 1usize] == CR { stop -= 1usize }
    if at < source.len { ret (source[from..stop], at + 1usize) }
    ret (source[from..stop], at)
}

fn parse(a: *mem.Arena, source: str, options: Options) -> (Document, err) {
    var document: Document = zero
    // One pass to count, so the entry array is allocated once and exactly. The alternative is a
    // growing claim on the arena, which nothing here can give back.
    var count = 0usize
    var at = 0usize
    while at < source.len {
        let (line, next) = slice_line(source, at)
        at = next
        let (classified, classify_error) = classify(line)
        if classify_error != ok { ret (document, classify_error) }
        if classified.kind == LINE_ENTRY { count += 1usize }
    }
    if count == 0usize { ret (document, ok) }
    let (entries, entries_error) = mem.alloc[Entry](a, count)
    if entries_error != ok { ret (document, entries_error) }
    var filled = 0usize
    var section = ""
    at = 0usize
    while at < source.len {
        let (line, next) = slice_line(source, at)
        at = next
        let (classified, classify_error) = classify(line)
        if classify_error != ok { ret (document, classify_error) }
        if classified.kind == LINE_BLANK { continue }
        if classified.kind == LINE_SECTION {
            let (named, name_error) = stored_name(a, classified.name, options.case_sensitive)
            if name_error != ok { ret (document, name_error) }
            section = named
            continue
        }
        let (key, key_error) = stored_name(a, classified.key, options.case_sensitive)
        if key_error != ok { ret (document, key_error) }
        var value = classified.value
        if classified.quoted {
            // The escaped form is never shorter than what it decodes to, so the raw length is a
            // bound rather than a guess.
            let (buffer, buffer_error) = mem.alloc[u8](a, classified.value.len)
            if buffer_error != ok { ret (document, buffer_error) }
            let (written, unescape_error) = unescape(classified.value, buffer)
            if unescape_error != ok { ret (document, unescape_error) }
            value = buffer[0usize..written]
        }
        if !options.allow_duplicate_keys {
            // ponytail: a linear scan of what is already filled, so O(n^2) in entries. The same
            // upgrade as the reader's: a hashed set, once `e.data.map` exists.
            var seen = 0usize
            while seen < filled {
                if same_text(entries[seen].section, section) && same_text(entries[seen].key, key) {
                    ret (document, DuplicateKey)
                }
                seen += 1usize
            }
        }
        entries[filled].section = section
        entries[filled].key = key
        entries[filled].value = value
        filled += 1usize
    }
    document.entries = entries[0usize..filled]
    ret (document, ok)
}

// Exact bytes, because a case-insensitive parse already folded them and a case-sensitive one
// meant the distinction.
fn get(document: *const Document, section: str, key: str) -> (str, bool) {
    var at = 0usize
    while at < document.entries.len {
        if same_text(document.entries[at].section, section) && same_text(document.entries[at].key, key) {
            ret (document.entries[at].value, true)
        }
        at += 1usize
    }
    ret ("", false)
}

fn take(s: *ReaderState) -> (u8, bool, err) {
    if s.input_at == s.input_len {
        let (count, read_error) = io.read(&s.source, s.input)
        if read_error == io.End { ret (0u8, false, ok) }
        if read_error != ok { ret (0u8, false, read_error) }
        s.input_len = count
        s.input_at = 0usize
    }
    let byte = s.input[s.input_at]
    s.input_at += 1usize
    ret (byte, true, ok)
}

// One line into the reader's own buffer. `false` means the source is spent and this line is not
// a line; a source that ends without an ending still yields what it had.
fn read_line(s: *ReaderState) -> (str, bool, err) {
    var length = 0usize
    var any = false
    while true {
        let (byte, more, take_error) = take(s)
        if take_error != ok { ret ("", false, take_error) }
        if !more {
            s.ended = true
            if !any { ret ("", false, ok) }
            break
        }
        any = true
        if byte == LF { break }
        if length == s.line.len { ret ("", false, TooLarge) }
        s.line[length] = byte
        length += 1usize
    }
    if length != 0usize && s.line[length - 1usize] == CR { length -= 1usize }
    ret (s.line[0usize..length], true, ok)
}

fn remember(s: *ReaderState, section: str, key: str) -> err {
    var at = 0usize
    while at < s.seen_count {
        if same_text(s.seen_section[at], section) && same_text(s.seen_key[at], key) { ret DuplicateKey }
        at += 1usize
    }
    if s.seen_count == s.seen_section.len { ret TooLarge }
    // The line buffer is overwritten by the next call, so what is remembered has to be a copy.
    let (kept_section, section_error) = copy_out(s.arena, section)
    if section_error != ok { ret section_error }
    let (kept_key, key_error) = copy_out(s.arena, key)
    if key_error != ok { ret key_error }
    s.seen_section[s.seen_count] = kept_section
    s.seen_key[s.seen_count] = kept_key
    s.seen_count += 1usize
    ret ok
}

fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err) {
    var handle: Reader = zero
    let (state, state_error) = mem.alloc[ReaderState](a, 1usize)
    if state_error != ok { ret (handle, state_error) }
    let (input, input_error) = mem.alloc[u8](a, INPUT_CAPACITY)
    if input_error != ok { ret (handle, input_error) }
    let (line, line_error) = mem.alloc[u8](a, MAX_LINE)
    if line_error != ok { ret (handle, line_error) }
    let (key, key_error) = mem.alloc[u8](a, MAX_LINE)
    if key_error != ok { ret (handle, key_error) }
    let (value, value_error) = mem.alloc[u8](a, MAX_LINE)
    if value_error != ok { ret (handle, value_error) }
    let (section, section_error) = mem.alloc[u8](a, MAX_LINE)
    if section_error != ok { ret (handle, section_error) }
    state[0usize].source = source
    state[0usize].options = options
    state[0usize].arena = a
    state[0usize].input = input
    state[0usize].input_at = 0usize
    state[0usize].input_len = 0usize
    state[0usize].line = line
    state[0usize].key = key
    state[0usize].key_len = 0usize
    state[0usize].value = value
    state[0usize].value_len = 0usize
    state[0usize].section = section
    state[0usize].section_len = 0usize
    state[0usize].seen_count = 0usize
    state[0usize].ended = false
    // The table of what has been seen exists only to refuse a duplicate; a caller who allows
    // them pays nothing for the option.
    if !options.allow_duplicate_keys {
        let (seen_section, seen_section_error) = mem.alloc[str](a, MAX_SEEN)
        if seen_section_error != ok { ret (handle, seen_section_error) }
        let (seen_key, seen_key_error) = mem.alloc[str](a, MAX_SEEN)
        if seen_key_error != ok { ret (handle, seen_key_error) }
        state[0usize].seen_section = seen_section
        state[0usize].seen_key = seen_key
    }
    handle.state = mem.cast[*void](&state[0usize])
    ret (handle, ok)
}

// One entry per call, `false` when the source is spent. Section lines and comments are consumed
// here rather than handed over: they say where an entry belongs, and the entry carries that.
// Every string borrows the reader's own buffers and is valid until the next call.
fn reader_next_err(r: *Reader) -> (Entry, bool, err) {
    let s = mem.cast[*ReaderState](r.state)
    var entry: Entry = zero
    if s.ended && s.input_at == s.input_len { ret (entry, false, ok) }
    while true {
        let (line, more, line_error) = read_line(s)
        if line_error != ok { ret (entry, false, line_error) }
        if !more { ret (entry, false, ok) }
        let (classified, classify_error) = classify(line)
        if classify_error != ok { ret (entry, false, classify_error) }
        if classified.kind == LINE_BLANK { continue }
        if classified.kind == LINE_SECTION {
            let (written, name_error) = place_name(classified.name, s.section, s.options.case_sensitive)
            if name_error != ok { ret (entry, false, name_error) }
            s.section_len = written
            continue
        }
        let (key_written, key_error) = place_name(classified.key, s.key, s.options.case_sensitive)
        if key_error != ok { ret (entry, false, key_error) }
        s.key_len = key_written
        let (value_written, value_error) = place_value(classified, s.value)
        if value_error != ok { ret (entry, false, value_error) }
        s.value_len = value_written
        entry.section = s.section[0usize..s.section_len]
        entry.key = s.key[0usize..s.key_len]
        entry.value = s.value[0usize..s.value_len]
        if !s.options.allow_duplicate_keys {
            let remember_error = remember(s, entry.section, entry.key)
            if remember_error != ok { ret (entry, false, remember_error) }
        }
        ret (entry, true, ok)
    }
    ret (entry, false, ok)
}

// A value is quoted when leaving it bare would not read back as itself: an ending or a quote
// inside it, whitespace at either edge that `trim` would take, a leading byte that would make
// the line a comment or a section, or nothing at all.
fn needs_quote(value: str) -> bool {
    if value.len == 0usize { ret true }
    if is_space(value[0usize]) || is_space(value[value.len - 1usize]) { ret true }
    if value[0usize] == SEMI || value[0usize] == HASH || value[0usize] == LBRACKET { ret true }
    if value[0usize] == DQUOTE { ret true }
    var at = 0usize
    while at < value.len {
        let byte = value[at]
        if byte == LF || byte == CR || byte == TAB { ret true }
        if byte == DQUOTE || byte == BACKSLASH { ret true }
        at += 1usize
    }
    ret false
}

fn write_escaped(writer: *io.Writer, value: str) -> err {
    try io.write_all(writer, "\"")
    var at = 0usize
    while at < value.len {
        let byte = value[at]
        if byte == LF {
            try io.write_all(writer, "\\n")
        } else {
        if byte == CR {
            try io.write_all(writer, "\\r")
        } else {
        if byte == TAB {
            try io.write_all(writer, "\\t")
        } else {
        if byte == 0u8 {
            try io.write_all(writer, "\\0")
        } else {
        if byte == DQUOTE {
            try io.write_all(writer, "\\\"")
        } else {
        if byte == BACKSLASH {
            try io.write_all(writer, "\\\\")
        } else {
            try io.write_all(writer, value[at..at + 1usize])
        }
        }
        }
        }
        }
        }
        at += 1usize
    }
    ret io.write_all(writer, "\"")
}

// Entries in the order they are held, with a header wherever the section changes. An entry whose
// section is empty belongs before any header, which is where `parse` puts one.
fn write(writer: *io.Writer, document: *const Document) -> err {
    var current = ""
    var started = false
    var at = 0usize
    while at < document.entries.len {
        let entry = document.entries[at]
        if !started || !same_text(entry.section, current) {
            if entry.section.len != 0usize {
                try io.write_all(writer, "[")
                try io.write_all(writer, entry.section)
                try io.write_all(writer, "]\n")
            }
            current = entry.section
            started = true
        }
        try io.write_all(writer, entry.key)
        try io.write_all(writer, "=")
        if needs_quote(entry.value) {
            try write_escaped(writer, entry.value)
        } else {
            try io.write_all(writer, entry.value)
        }
        try io.write_all(writer, "\n")
        at += 1usize
    }
    ret ok
}
// --- The typed codec.
//
// A struct is a flat document: one key per field, in the empty section, named as the field is
// named. Nesting would be sections, and a section is a struct inside a struct -- which is the
// recursion this cannot do, so a field that is not a number, a bool or a `str` is `Invalid`
// rather than quietly skipped.
//
// The walk over `meta.fields` is unrolled, so each copy below sees one concrete field type. The
// arms are chosen by `meta.kind[f.ty]()`, and only the chosen one is checked -- an arm written
// for an integer never has to be valid for the iteration whose field is a `str` (D138).

const MINUS: u8 = 45u8

// Enough for any integer or float `e.str` will render, with room for the builder's own claim.
const FIELD_TEXT: usize = 128usize

fn matches(stored: str, name: str, case_sensitive: bool) -> bool {
    if case_sensitive { ret same_text(stored, name) }
    if stored.len != name.len { ret false }
    var at = 0usize
    while at < name.len {
        if stored[at] != lower(name[at]) { ret false }
        at += 1usize
    }
    ret true
}

// A field's entry: the empty section only, since that is where `encode` puts them and what a
// flat struct means.
fn field_entry(document: *const Document, name: str, case_sensitive: bool) -> (str, bool) {
    var at = 0usize
    while at < document.entries.len {
        let entry = document.entries[at]
        if entry.section.len == 0usize && matches(entry.key, name, case_sensitive) { ret (entry.value, true) }
        at += 1usize
    }
    ret ("", false)
}

fn decode[T: type](a: *mem.Arena, source: str, options: Options) -> (T, err) {
    var out: T = zero
    let (document, parse_error) = parse(a, source, options)
    if parse_error != ok { ret (out, parse_error) }
    for f in meta.fields[T]() {
        let (text, present) = field_entry(&document, f.name, options.case_sensitive)
        // A key the source does not carry leaves its field as it was. A configuration file is
        // partial by nature, and a decoder that insisted on every key would make adding a field
        // to a program break every file already written for it.
        if present {
            if meta.kind[f.ty]() == .Slice {
                meta.set[f, T](&out, text)
            } else {
            if meta.kind[f.ty]() == .Bool {
                if same_text(text, "true") {
                    meta.set[f, T](&out, true)
                } else {
                    if !same_text(text, "false") { ret (out, Invalid) }
                    meta.set[f, T](&out, false)
                }
            } else {
            if meta.kind[f.ty]() == .Int {
                var slot: f.ty = zero
                // Read through whichever of the two the text fits, so a `u64` past the signed
                // maximum and a negative are both exact. Neither takes a floating-point detour.
                if text.len != 0usize && text[0usize] == MINUS {
                    let (signed, signed_error) = str.parse_i64(text)
                    if signed_error != ok { ret (out, Invalid) }
                    slot = f.ty(signed)
                } else {
                    let (unsigned, unsigned_error) = str.parse_u64(text)
                    if unsigned_error != ok { ret (out, Invalid) }
                    slot = f.ty(unsigned)
                }
                meta.set[f, T](&out, slot)
            } else {
            if meta.kind[f.ty]() == .Float {
                let (number, number_error) = str.parse_f64(text)
                if number_error != ok { ret (out, Invalid) }
                var slot: f.ty = zero
                slot = f.ty(number)
                meta.set[f, T](&out, slot)
            } else {
                ret (out, Invalid)
            }
            }
            }
            }
        }
    }
    ret (out, ok)
}

fn encode[T: type](writer: *io.Writer, value: *const T) -> err {
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        // A buffer per field, and an arena over it, so `e.str` does the rendering and this
        // module carries no number formatting of its own. `encode` is given no arena and needs
        // none: nothing it builds outlives the field it was built for.
        var scratch: [FIELD_TEXT]u8 = zero
        var holder = mem.arena_from(scratch[..])
        var text = ""
        if meta.kind[f.ty]() == .Slice {
            text = slot
        } else {
        if meta.kind[f.ty]() == .Bool {
            if slot {
                text = "true"
            } else {
                text = "false"
            }
        } else {
        if meta.kind[f.ty]() == .Int {
            let (rendered, builder_error) = str.builder(&holder, FIELD_TEXT / 2usize)
            if builder_error != ok { ret builder_error }
            var built = rendered
            // Signedness is not a question reflection answers, and the value is, so it is asked
            // of the value: only a signed type holds anything below zero.
            if slot < 0 {
                try str.push_i64(&built, i64(slot))
            } else {
                try str.push_u64(&built, u64(slot))
            }
            text = str.done(&built)
        } else {
        if meta.kind[f.ty]() == .Float {
            let (rendered, builder_error) = str.builder(&holder, FIELD_TEXT / 2usize)
            if builder_error != ok { ret builder_error }
            var built = rendered
            try str.push_f64(&built, f64(slot))
            text = str.done(&built)
        } else {
            ret Invalid
        }
        }
        }
        }
        try io.write_all(writer, f.name)
        try io.write_all(writer, "=")
        if needs_quote(text) {
            try write_escaped(writer, text)
        } else {
            try io.write_all(writer, text)
        }
        try io.write_all(writer, "\n")
    }
    ret ok
}
