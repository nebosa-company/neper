// RFC 4180 delimiter-separated records, read as a stream and written a row at a time.
//
// The reader is bounded rather than growing: both limits are given once, at construction, and
// buy a byte buffer and a field table that every row is then parsed into. A `Row` borrows
// those, so it is valid until the next call and nothing is allocated per record -- which is
// what lets a file larger than memory go through an arena that never moves.
//
// What the format leaves open, this resolves toward tolerance on the way in and toward the
// strictest spelling on the way out: both line endings are accepted and the one the dialect
// names is written; a quote inside an unquoted field is data, because that is the only thing
// it can be; a quoted field that ends and then continues is refused, because whoever wrote it
// meant something this reader would have to guess at.

use e.io
use e.mem
use e.meta
use e.str

type Dialect = struct {
    delimiter: u8,
    quote: u8,
    crlf: bool,
    header: bool,
}

type Row = struct {
    fields: []const str,
}

type Reader = struct {
    state: *void,
}

error Invalid
error TooLarge

const COMMA: u8 = 44u8
const TAB: u8 = 9u8
const QUOTE: u8 = 34u8
const CR: u8 = 13u8
const LF: u8 = 10u8

// Zero means the default for both limits, the way a zero `Options` does in `e.fmt.json`: a
// caller who has not thought about the bound is asking for a reasonable one, not for none.
// A field table of a thousand is wider than any hand-made sheet, and 64 KiB is a row far
// past what a delimited record is for.
const DEFAULT_FIELD_LIMIT: usize = 1024usize
const DEFAULT_ROW_LIMIT: usize = 65536usize

// The read granularity, which is not a bound on anything: a row longer than this spans as
// many reads as it needs.
const INPUT_CAPACITY: usize = 4096usize

type ReaderState = struct {
    source: io.Reader,
    dialect: Dialect,
    input: []u8,
    input_at: usize,
    input_len: usize,
    row: []u8,
    fields: []str,
    ended: bool,
}

fn csv() -> Dialect {
    ret Dialect { delimiter: COMMA, quote: QUOTE, crlf: false, header: false }
}

fn tsv() -> Dialect {
    ret Dialect { delimiter: TAB, quote: QUOTE, crlf: false, header: false }
}

// A delimiter that is also the quote, or either of them a line ending, describes a format
// with no unambiguous reading. A `zero` Dialect is caught by the first of these -- there is
// no default dialect to invent when `csv()` is one call away.
fn usable(dialect: Dialect) -> bool {
    if dialect.delimiter == dialect.quote { ret false }
    if dialect.delimiter == CR || dialect.delimiter == LF { ret false }
    if dialect.quote == CR || dialect.quote == LF { ret false }
    ret true
}

// One byte, or `false` at the end of the source. Every byte a record is built from comes
// from here and from nowhere else, which is what makes `unread` below a subtraction.
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

// The one byte of lookahead a CRLF needs. It is only ever called on a byte `take` just
// returned, so the position it goes back to is still inside the buffer that byte came from.
fn unread(s: *ReaderState) {
    s.input_at -= 1usize
}

fn keep(s: *ReaderState, row_at: usize, byte: u8) -> (usize, err) {
    if row_at == s.row.len { ret (row_at, TooLarge) }
    s.row[row_at] = byte
    ret (row_at + 1usize, ok)
}

fn close_field(s: *ReaderState, field_count: usize, field_start: usize, row_at: usize) -> (usize, err) {
    if field_count == s.fields.len { ret (field_count, TooLarge) }
    s.fields[field_count] = s.row[field_start..row_at]
    ret (field_count + 1usize, ok)
}

// One record. The state machine is small because only two things are remembered across a
// byte: whether a quoted field is open, and whether the quote that closed one was the byte
// before -- everything else is decided where it is read.
fn read_record(s: *ReaderState) -> (Row, bool, err) {
    var empty: Row = zero
    if s.ended { ret (empty, false, ok) }
    var row_at = 0usize
    var field_start = 0usize
    var field_count = 0usize
    var in_quotes = false
    var quoted_field = false
    var after_quote = false
    var saw_any = false
    while true {
        let (byte, more, take_error) = take(s)
        if take_error != ok { ret (empty, false, take_error) }
        if !more {
            s.ended = true
            // A quoted field the source ended in the middle of is the one thing that cannot
            // be repaired: its terminator was going to say where the field ends.
            if in_quotes { ret (empty, false, Invalid) }
            // Nothing at all was read, so there is no last record -- a source that ended with
            // a line ending ends here, and does not yield an empty row for the ending.
            if !saw_any { ret (empty, false, ok) }
            break
        }
        saw_any = true
        if in_quotes {
            if byte == s.dialect.quote {
                in_quotes = false
                after_quote = true
                continue
            }
            let (kept, keep_error) = keep(s, row_at, byte)
            if keep_error != ok { ret (empty, false, keep_error) }
            row_at = kept
            continue
        }
        if after_quote {
            after_quote = false
            // A doubled quote is one quote of data, and the field is open again.
            if byte == s.dialect.quote {
                let (kept, keep_error) = keep(s, row_at, byte)
                if keep_error != ok { ret (empty, false, keep_error) }
                row_at = kept
                in_quotes = true
                continue
            }
            if byte != s.dialect.delimiter && byte != CR && byte != LF {
                ret (empty, false, Invalid)
            }
        }
        if byte == s.dialect.delimiter {
            let (closed, close_error) = close_field(s, field_count, field_start, row_at)
            if close_error != ok { ret (empty, false, close_error) }
            field_count = closed
            field_start = row_at
            quoted_field = false
            continue
        }
        if byte == CR {
            let (next, next_more, next_error) = take(s)
            if next_error != ok { ret (empty, false, next_error) }
            if next_more && next == LF { break }
            if next_more {
                unread(s)
            } else {
                s.ended = true
            }
            // Not a terminator, so it is data: this format has no other reading for a CR that
            // no LF follows.
            let (kept, keep_error) = keep(s, row_at, CR)
            if keep_error != ok { ret (empty, false, keep_error) }
            row_at = kept
            continue
        }
        if byte == LF { break }
        if byte == s.dialect.quote {
            // A quote opens a field only where a field starts. Anywhere else the field is
            // already unquoted, and a quote inside one is a byte like any other.
            if row_at == field_start && !quoted_field {
                quoted_field = true
                in_quotes = true
                continue
            }
            let (kept, keep_error) = keep(s, row_at, byte)
            if keep_error != ok { ret (empty, false, keep_error) }
            row_at = kept
            continue
        }
        let (kept, keep_error) = keep(s, row_at, byte)
        if keep_error != ok { ret (empty, false, keep_error) }
        row_at = kept
    }
    let (closed, close_error) = close_field(s, field_count, field_start, row_at)
    if close_error != ok { ret (empty, false, close_error) }
    ret (Row { fields: s.fields[0usize..closed] }, true, ok)
}

fn reader(a: *mem.Arena, source: io.Reader, dialect: Dialect, field_limit: usize, row_limit: usize) -> (Reader, err) {
    var handle: Reader = zero
    if !usable(dialect) { ret (handle, Invalid) }
    var fields = field_limit
    if fields == 0usize { fields = DEFAULT_FIELD_LIMIT }
    var bytes = row_limit
    if bytes == 0usize { bytes = DEFAULT_ROW_LIMIT }
    let (state, state_error) = mem.alloc[ReaderState](a, 1usize)
    if state_error != ok { ret (handle, state_error) }
    let (input, input_error) = mem.alloc[u8](a, INPUT_CAPACITY)
    if input_error != ok { ret (handle, input_error) }
    let (row, row_error) = mem.alloc[u8](a, bytes)
    if row_error != ok { ret (handle, row_error) }
    let (table, table_error) = mem.alloc[str](a, fields)
    if table_error != ok { ret (handle, table_error) }
    state[0usize].source = source
    state[0usize].dialect = dialect
    state[0usize].input = input
    state[0usize].input_at = 0usize
    state[0usize].input_len = 0usize
    state[0usize].row = row
    state[0usize].fields = table
    state[0usize].ended = false
    // A caller who said the first record is a header is asking not to be handed it. Reading
    // it here rather than on the first `reader_next_err` keeps that out of the loop, and a
    // caller who wants the header asks for a dialect that does not claim one.
    if dialect.header {
        let (header_row, header_more, header_error) = read_record(&state[0usize])
        if header_error != ok { ret (handle, header_error) }
    }
    handle.state = mem.cast[*void](&state[0usize])
    ret (handle, ok)
}

// One record per call, `false` when the source is spent. The `Row` borrows the reader's own
// buffers and is valid until the next call.
fn reader_next_err(r: *Reader) -> (Row, bool, err) {
    let state = mem.cast[*ReaderState](r.state)
    let (row, more, next_error) = read_record(state)
    ret (row, more, next_error)
}

// A field is quoted only when leaving it bare would change what it says.
fn needs_quote(field: str, dialect: Dialect) -> bool {
    var at = 0usize
    while at < field.len {
        let byte = field[at]
        if byte == dialect.delimiter || byte == dialect.quote { ret true }
        if byte == CR || byte == LF { ret true }
        at += 1usize
    }
    ret false
}

// One field, quoted if it has to be. Shared, because `encode_rows` writes the same field from a
// struct and has nowhere to build a `Row` it would only take apart again.
fn write_field(writer: *io.Writer, field: str, dialect: Dialect) -> err {
    var mark: [1]u8 = zero
    mark[0usize] = dialect.quote
    if !needs_quote(field, dialect) { ret io.write_all(writer, field) }
    try io.write_all(writer, mark[..])
    var start = 0usize
    var at = 0usize
    while at < field.len {
        // The quote itself is doubled, so the run up to and including it is written and then
        // the quote once more.
        if field[at] == dialect.quote {
            try io.write_all(writer, field[start..at + 1usize])
            try io.write_all(writer, mark[..])
            start = at + 1usize
        }
        at += 1usize
    }
    try io.write_all(writer, field[start..field.len])
    ret io.write_all(writer, mark[..])
}

fn write_ending(writer: *io.Writer, dialect: Dialect) -> err {
    if dialect.crlf { ret io.write_all(writer, "\r\n") }
    ret io.write_all(writer, "\n")
}

fn write_row(writer: *io.Writer, row: Row, dialect: Dialect) -> err {
    if !usable(dialect) { ret Invalid }
    var separator: [1]u8 = zero
    separator[0usize] = dialect.delimiter
    var index = 0usize
    while index < row.fields.len {
        if index != 0usize { try io.write_all(writer, separator[..]) }
        try write_field(writer, row.fields[index], dialect)
        index += 1usize
    }
    ret write_ending(writer, dialect)
}
// --- The typed codec.
//
// A struct is a row and its fields are columns, in declaration order. Columns are matched by
// position and not by name: that is what a delimited file is, and it is why a header is written
// when the dialect claims one but never read back for meaning -- `reader` has already consumed
// it by the time a row arrives.
//
// The walk over `meta.fields` is unrolled, so each copy sees one concrete field type and the arm
// chosen by `meta.kind[f.ty]()` is the only one that has to check (D138).

const MINUS: u8 = 45u8

// Enough for any integer or float `e.str` will render, with room for the builder's own claim.
const FIELD_TEXT: usize = 128usize

// Where a decode starts, and how it grows. An arena gives back nothing, so a claim that outgrows
// itself is copied into a larger one and the old one is left behind.
// ponytail: doubling wastes under half the arena a decode uses. A reader that knew its row count
// in advance would not need it, and a delimited stream does not.
const FIRST_ROWS: usize = 16usize

// A `Row` borrows the reader's own buffers and the next call overwrites them, so a `str` field
// that is going to outlive the row it came from has to be copied. Everything else a field holds
// is a value and travels by itself.
fn copy_text(a: *mem.Arena, text: str) -> (str, err) {
    if text.len == 0usize { ret ("", ok) }
    let (buffer, allocation_error) = mem.alloc[u8](a, text.len)
    if allocation_error != ok { ret ("", allocation_error) }
    mem.copy[u8](buffer, text)
    ret (buffer, ok)
}

fn decode_rows[T: type](a: *mem.Arena, source: io.Reader, dialect: Dialect) -> ([]T, err) {
    var empty: []T = zero
    let (handle, reader_error) = reader(a, source, dialect, 0usize, 0usize)
    if reader_error != ok { ret (empty, reader_error) }
    var stream = handle
    let (first, first_error) = mem.alloc[T](a, FIRST_ROWS)
    if first_error != ok { ret (empty, first_error) }
    var rows = first
    var count = 0usize
    while true {
        let (row, more, next_error) = reader_next_err(&stream)
        if next_error != ok { ret (empty, next_error) }
        if !more { break }
        if count == rows.len {
            let (larger, larger_error) = mem.alloc[T](a, rows.len * 2usize)
            if larger_error != ok { ret (empty, larger_error) }
            mem.copy[T](larger, rows)
            rows = larger
        }
        var value: T = zero
        var column = 0usize
        for f in meta.fields[T]() {
            // A row with fewer columns than the struct has fields leaves the rest as they are,
            // the way a missing key does in `e.fmt.ini`. A row with more is not an error either:
            // the extra columns are simply not this struct's.
            if column < row.fields.len {
                let text = row.fields[column]
                if meta.kind[f.ty]() == .Slice {
                    let (kept, copy_error) = copy_text(a, text)
                    if copy_error != ok { ret (empty, copy_error) }
                    meta.set[f, T](&value, kept)
                } else {
                if meta.kind[f.ty]() == .Bool {
                    if str.eq(text, "true") {
                        meta.set[f, T](&value, true)
                    } else {
                        if !str.eq(text, "false") { ret (empty, Invalid) }
                        meta.set[f, T](&value, false)
                    }
                } else {
                if meta.kind[f.ty]() == .Int {
                    var slot: f.ty = zero
                    // Whichever of the two the text fits, so a `u64` past the signed maximum and
                    // a negative are both exact and neither takes a floating-point detour.
                    if text.len != 0usize && text[0usize] == MINUS {
                        let (signed, signed_error) = str.parse_i64(text)
                        if signed_error != ok { ret (empty, Invalid) }
                        slot = f.ty(signed)
                    } else {
                        let (unsigned, unsigned_error) = str.parse_u64(text)
                        if unsigned_error != ok { ret (empty, Invalid) }
                        slot = f.ty(unsigned)
                    }
                    meta.set[f, T](&value, slot)
                } else {
                if meta.kind[f.ty]() == .Float {
                    let (number, number_error) = str.parse_f64(text)
                    if number_error != ok { ret (empty, Invalid) }
                    var slot: f.ty = zero
                    slot = f.ty(number)
                    meta.set[f, T](&value, slot)
                } else {
                    ret (empty, Invalid)
                }
                }
                }
                }
            }
            column += 1usize
        }
        rows[count] = value
        count += 1usize
    }
    ret (rows[0usize..count], ok)
}

fn encode_rows[T: type](writer: *io.Writer, rows: []const T, dialect: Dialect) -> err {
    if !usable(dialect) { ret Invalid }
    var separator: [1]u8 = zero
    separator[0usize] = dialect.delimiter
    // A dialect that claims a header gets one, named as the fields are. `reader` consumes it
    // without reading it, so it is for whoever opens the file rather than for the round trip.
    if dialect.header {
        var named = 0usize
        for f in meta.fields[T]() {
            if named != 0usize { try io.write_all(writer, separator[..]) }
            try write_field(writer, f.name, dialect)
            named += 1usize
        }
        try write_ending(writer, dialect)
    }
    var index = 0usize
    while index < rows.len {
        var written = 0usize
        for f in meta.fields[T]() {
            if written != 0usize { try io.write_all(writer, separator[..]) }
            var slot: f.ty = zero
            slot = meta.get[f, T](&rows[index])
            // A buffer per field and an arena over it, so `e.str` does the rendering and this
            // module carries no number formatting of its own.
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
                // Signedness is not a question reflection answers and the value is, so it is
                // asked of the value: only a signed type holds anything below zero.
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
            try write_field(writer, text, dialect)
            written += 1usize
        }
        try write_ending(writer, dialect)
        index += 1usize
    }
    ret ok
}
