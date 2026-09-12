// Text over byte streams through `e.text.encoding`: a reader that decodes a source
// into UTF-8 through a raw buffer of `capacity` bytes and a decoded buffer twice
// that, answering whole lines (LF or CRLF stripped, a bare CR kept, an unterminated
// last line delivered) or everything up to a limit; `reader_bom` sniffs the first
// bytes for a byte order mark and falls back to the encoding given. A writer encodes
// UTF-8 into the sink's encoding through a staging buffer, with the newline chosen
// at construction. State lives in the arena and the handles must not be copied.
//
// ponytail: `Newline.Native` resolves to LF -- a portable module cannot learn its
// host (the same gap D97-D132 record for path style); a per-target variant of this
// file is the upgrade.
use e.io
use e.mem
use e.text.encoding as encoding

type Reader = struct { state: *void }
type Writer = struct { state: *void }
type Newline = enum u8 { Lf, CrLf, Native }
error End
error TooLarge
error Invalid

type ReaderState = struct { source: io.Reader, decoder: encoding.Decoder, raw: []u8, raw_at: usize, raw_len: usize, text: []u8, text_at: usize, text_len: usize, source_ended: bool, drained: bool, invalid_ahead: bool }
type WriterState = struct { sink: io.Writer, encoder: encoding.Encoder, staging: []u8, newline: str }

fn make_reader(a: *mem.Arena, source: io.Reader, decoder: encoding.Decoder, capacity: usize, raw: []u8, raw_len: usize) -> (Reader, err) {
    if capacity < 8usize { ret (zero, Invalid) }
    let (storage, storage_error) = mem.alloc[ReaderState](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (text, text_error) = mem.alloc[u8](a, capacity * 2usize)
    if text_error != ok { ret (zero, text_error) }
    let s = &storage[0]
    s.source = source
    s.decoder = decoder
    s.raw = raw
    s.raw_at = 0usize
    s.raw_len = raw_len
    s.text = text
    s.text_at = 0usize
    s.text_len = 0usize
    s.source_ended = false
    s.drained = false
    s.invalid_ahead = false
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

fn reader(a: *mem.Arena, source: io.Reader, source_encoding: encoding.Encoding, policy: encoding.InvalidPolicy, capacity: usize) -> (Reader, err) {
    if capacity < 8usize { ret (zero, Invalid) }
    let (raw, raw_error) = mem.alloc[u8](a, capacity)
    if raw_error != ok { ret (zero, raw_error) }
    let (r, make_error) = make_reader(a, source, encoding.decoder(source_encoding, policy, true), capacity, raw, 0usize)
    ret (r, make_error)
}

// The first bytes are read before the decoder is chosen, so the mark is seen whole.
fn reader_bom(a: *mem.Arena, source: io.Reader, fallback: encoding.Encoding, policy: encoding.InvalidPolicy, capacity: usize) -> (Reader, err) {
    if capacity < 8usize { ret (zero, Invalid) }
    let (raw, raw_error) = mem.alloc[u8](a, capacity)
    if raw_error != ok { ret (zero, raw_error) }
    var input = source
    var filled = 0usize
    while filled < 4usize {
        let (count, read_error) = io.read(&input, raw[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        if count == 0usize { break }
        filled += count
    }
    let (found, bom_len, has_bom) = encoding.detect_bom(raw[..filled])
    var chosen = fallback
    if has_bom { chosen = found }
    let (r, make_error) = make_reader(a, source, encoding.decoder(chosen, policy, true), capacity, raw, filled)
    ret (r, make_error)
}

// Decodes more of the source into the text buffer; false when nothing more will come.
fn fill(s: *ReaderState) -> (bool, err) {
    if s.drained { ret (false, ok) }
    // Shift the unread text down, then top up the raw bytes.
    if s.text_at > 0usize {
        var i = 0usize
        while i < s.text_len - s.text_at {
            s.text[i] = s.text[s.text_at + i]
            i += 1usize
        }
        s.text_len -= s.text_at
        s.text_at = 0usize
    }
    if s.raw_at == s.raw_len && !s.source_ended {
        let (count, read_error) = io.read(&s.source, s.raw)
        if read_error == io.End || (read_error == ok && count == 0usize) {
            s.source_ended = true
        } else {
            if read_error != ok { ret (false, read_error) }
            s.raw_at = 0usize
            s.raw_len = count
        }
    }
    if s.text_len == s.text.len { ret (false, TooLarge) }
    // A bad byte is reported once the text before it has been handed out.
    if s.invalid_ahead { ret (false, Invalid) }
    let (consumed, written, decode_error) = encoding.decode(&s.decoder, s.raw[s.raw_at..s.raw_len], s.text[s.text_len..], s.source_ended)
    if decode_error == encoding.TooSmall {
        if written == 0usize && consumed == 0usize { ret (false, TooLarge) }
    } else {
        if decode_error != ok {
            if written == 0usize { ret (false, Invalid) }
            s.invalid_ahead = true
        }
    }
    s.raw_at += consumed
    s.text_len += written
    if s.source_ended && s.raw_at == s.raw_len && written == 0usize {
        s.drained = true
        ret (false, ok)
    }
    ret (true, ok)
}

fn copy_out(a: *mem.Arena, s: *ReaderState, from: usize, to: usize, drop_cr: bool) -> (str, err) {
    var stop = to
    if drop_cr && stop > from && s.text[stop - 1usize] == 13u8 { stop -= 1usize }
    let (out, out_error) = mem.alloc[u8](a, stop - from)
    if out_error != ok { ret ("", out_error) }
    mem.copy[u8](out, s.text[from..stop])
    ret (out, ok)
}

// The next line without its LF or CRLF; the last line without one; `End` after it.
fn read_line(a: *mem.Arena, r: *Reader, limit: usize) -> (str, err) {
    let s = mem.cast[*ReaderState](r.state)
    var scanned = 0usize
    while true {
        var i = s.text_at + scanned
        while i < s.text_len {
            if s.text[i] == 10u8 {
                if i - s.text_at > limit { ret ("", TooLarge) }
                let (line, copy_error) = copy_out(a, s, s.text_at, i, true)
                if copy_error != ok { ret ("", copy_error) }
                s.text_at = i + 1usize
                ret (line, ok)
            }
            i += 1usize
        }
        scanned = s.text_len - s.text_at
        if scanned > limit { ret ("", TooLarge) }
        let (more, fill_error) = fill(s)
        if fill_error != ok { ret ("", fill_error) }
        if !more {
            if s.text_at == s.text_len { ret ("", End) }
            let (line, copy_error) = copy_out(a, s, s.text_at, s.text_len, false)
            if copy_error != ok { ret ("", copy_error) }
            s.text_at = s.text_len
            ret (line, ok)
        }
    }
}

fn read_all(a: *mem.Arena, r: *Reader, limit: usize) -> (str, err) {
    let s = mem.cast[*ReaderState](r.state)
    var capacity = 256usize
    let (first, first_error) = mem.alloc[u8](a, capacity)
    if first_error != ok { ret ("", first_error) }
    var out = first
    var used = 0usize
    while true {
        let chunk = s.text_len - s.text_at
        if used + chunk > limit { ret ("", TooLarge) }
        while used + chunk > capacity {
            let (bigger, bigger_error) = mem.alloc[u8](a, capacity * 2usize)
            if bigger_error != ok { ret ("", bigger_error) }
            mem.copy[u8](bigger[..used], out[..used])
            out = bigger
            capacity = capacity * 2usize
        }
        mem.copy[u8](out[used..used + chunk], s.text[s.text_at..s.text_len])
        used += chunk
        s.text_at = s.text_len
        let (more, fill_error) = fill(s)
        if fill_error != ok { ret ("", fill_error) }
        if !more { break }
    }
    ret (out[..used], ok)
}

fn writer(a: *mem.Arena, sink: io.Writer, source_encoding: encoding.Encoding, emit_bom: bool, newline: Newline, capacity: usize) -> (Writer, err) {
    if capacity < 8usize { ret (zero, Invalid) }
    let (storage, storage_error) = mem.alloc[WriterState](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (staging, staging_error) = mem.alloc[u8](a, capacity)
    if staging_error != ok { ret (zero, staging_error) }
    let s = &storage[0]
    s.sink = sink
    s.encoder = encoding.encoder(source_encoding, emit_bom)
    s.staging = staging
    s.newline = "\n"
    if newline == .CrLf { s.newline = "\r\n" }
    var w: Writer = zero
    w.state = mem.cast[*void](s)
    ret (w, ok)
}

fn write(w: *Writer, text: str) -> err {
    let s = mem.cast[*WriterState](w.state)
    var at = 0usize
    while at < text.len {
        let (consumed, written, encode_error) = encoding.encode(&s.encoder, text[at..], s.staging, true)
        if encode_error != ok && encode_error != encoding.TooSmall { ret Invalid }
        if consumed == 0usize && written == 0usize { ret TooLarge }
        if written > 0usize { try io.write_all(&s.sink, s.staging[..written]) }
        at += consumed
    }
    ret ok
}

fn write_line(w: *Writer, text: str) -> err {
    try write(w, text)
    let s = mem.cast[*WriterState](w.state)
    ret write(w, s.newline)
}

fn flush(w: *Writer) -> err {
    let s = mem.cast[*WriterState](w.state)
    ret io.flush(&s.sink)
}
