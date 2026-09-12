// XML 1.0 as events: the reader takes the whole source into the arena and walks it
// tag by tag -- Start with its attributes (an empty element is Start with `empty`
// and then its End), End, Text (character data and CDATA, the five named entities
// and numeric references decoded; whitespace outside the root dropped), Comment when
// `preserve_comments`, Processing. The XML declaration is skipped; a DOCTYPE, an
// unknown entity or an external reference is `Unsupported`; a mismatched or missing
// end tag, a malformed tag or a reference is `Invalid`; nesting past `max_depth` is
// `TooDeep`. Names are taken as written, prefix and colon included. The writer
// escapes attribute values and text and refuses `--` in a comment.
use e.io
use e.mem
use e.str

type Attribute = struct { name: str, value: str }
type Event = union enum u8 { Start: StartElement, End: str, Text: str, Comment: str, Processing: Processing }
type StartElement = struct { name: str, attributes: []const Attribute, empty: bool }
type Processing = struct { target: str, data: str }
type Reader = struct { state: *void }
type Writer = struct { sink: io.Writer, depth: u16 }
type Options = struct { max_depth: u16, preserve_comments: bool }
error Invalid
error TooDeep
error Unsupported

// Open element names are kept on a stack of at most `max_depth` entries.
type State = struct { a: *mem.Arena, source: []const u8, at: usize, options: Options, stack: []str, depth: usize, pending_end: str, has_pending: bool, started: bool, finished: bool }

fn slurp(a: *mem.Arena, source: io.Reader) -> ([]u8, err) {
    var capacity = 4096usize
    let (first, first_error) = mem.alloc[u8](a, capacity)
    if first_error != ok { ret (zero, first_error) }
    var buffer = first
    var filled = 0usize
    var input = source
    while true {
        if filled == capacity {
            let (bigger, bigger_error) = mem.alloc[u8](a, capacity * 2usize)
            if bigger_error != ok { ret (zero, bigger_error) }
            mem.copy[u8](bigger[..filled], buffer[..filled])
            buffer = bigger
            capacity = capacity * 2usize
        }
        let (count, read_error) = io.read(&input, buffer[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        if count == 0usize { break }
        filled += count
    }
    ret (buffer[..filled], ok)
}

fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (contents, slurp_error) = slurp(a, source)
    if slurp_error != ok { ret (zero, slurp_error) }
    let (stack, stack_error) = mem.alloc[str](a, usize(options.max_depth) + 1usize)
    if stack_error != ok { ret (zero, stack_error) }
    let s = &storage[0]
    s.a = a
    s.source = contents
    s.at = 0usize
    s.options = options
    s.stack = stack
    s.depth = 0usize
    s.has_pending = false
    s.started = false
    s.finished = false
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn is_name_byte(c: u8) -> bool {
    ret str.is_ascii_alnum(c) || c == 95u8 || c == 45u8 || c == 46u8 || c == 58u8 || c >= 128u8
}

fn name_end(source: []const u8, at: usize) -> usize {
    var stop = at
    while stop < source.len && is_name_byte(source[stop]) { stop += 1usize }
    ret stop
}

fn skip_space(source: []const u8, at: usize) -> usize {
    var stop = at
    while stop < source.len && is_space(source[stop]) { stop += 1usize }
    ret stop
}

// Appends the UTF-8 of `scalar` to `out`.
fn push_scalar(out: []u8, at: usize, scalar: u32) -> usize {
    if scalar < 128u32 {
        out[at] = u8(scalar)
        ret at + 1usize
    }
    if scalar < 2048u32 {
        out[at] = u8(192u32 | (scalar >> 6u32))
        out[at + 1usize] = u8(128u32 | (scalar & 63u32))
        ret at + 2usize
    }
    if scalar < 65536u32 {
        out[at] = u8(224u32 | (scalar >> 12u32))
        out[at + 1usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
        out[at + 2usize] = u8(128u32 | (scalar & 63u32))
        ret at + 3usize
    }
    out[at] = u8(240u32 | (scalar >> 18u32))
    out[at + 1usize] = u8(128u32 | ((scalar >> 12u32) & 63u32))
    out[at + 2usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
    out[at + 3usize] = u8(128u32 | (scalar & 63u32))
    ret at + 4usize
}

// Decodes the references in `raw`; borrowed back when it holds none.
fn decode(a: *mem.Arena, raw: []const u8) -> (str, err) {
    let (amp, has_amp) = str.find(raw, "&")
    if !has_amp { ret (raw, ok) }
    let (out, out_error) = mem.alloc[u8](a, raw.len)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    var used = 0usize
    while at < raw.len {
        if raw[at] != 38u8 {
            out[used] = raw[at]
            used += 1usize
            at += 1usize
            continue
        }
        let (semi, has_semi) = str.find_from(raw, ";", at)
        if !has_semi { ret ("", Invalid) }
        let name = raw[at + 1usize..semi]
        if str.eq(name, "lt") {
            out[used] = 60u8
            used += 1usize
        } else {
        if str.eq(name, "gt") {
            out[used] = 62u8
            used += 1usize
        } else {
        if str.eq(name, "amp") {
            out[used] = 38u8
            used += 1usize
        } else {
        if str.eq(name, "apos") {
            out[used] = 39u8
            used += 1usize
        } else {
        if str.eq(name, "quot") {
            out[used] = 34u8
            used += 1usize
        } else {
        if name.len > 1usize && name[0] == 35u8 {
            var scalar = 0u64
            var parse_error = ok
            if name[1] == 120u8 {
                let (hex, hex_error) = str.parse_u64_radix(name[2usize..], 16u8)
                scalar = hex
                parse_error = hex_error
            } else {
                let (dec, dec_error) = str.parse_u64(name[1usize..])
                scalar = dec
                parse_error = dec_error
            }
            if parse_error != ok || scalar > 1114111u64 || scalar == 0u64 { ret ("", Invalid) }
            used = push_scalar(out, used, u32(scalar))
        } else {
            ret ("", Unsupported)
        }
        }
        }
        }
        }
        }
        at = semi + 1usize
    }
    ret (out[..used], ok)
}

fn reader_next_err(r: *Reader) -> (Event, bool, err) {
    let s = mem.cast[*State](r.state)
    if s.has_pending {
        s.has_pending = false
        ret (Event{ End: s.pending_end }, true, ok)
    }
    while true {
        if s.at >= s.source.len {
            if s.depth != 0usize { ret (zero, false, Invalid) }
            if !s.started { ret (zero, false, Invalid) }
            ret (zero, false, ok)
        }
        let source = s.source
        if source[s.at] != 60u8 {
            // Character data up to the next tag.
            let (lt, has_lt) = str.find_from(source, "<", s.at)
            var stop = source.len
            if has_lt { stop = lt }
            let raw = source[s.at..stop]
            s.at = stop
            if s.depth == 0usize {
                if str.trim(raw).len != 0usize { ret (zero, false, Invalid) }
                continue
            }
            let (decoded, decode_error) = decode(s.a, raw)
            if decode_error != ok { ret (zero, false, decode_error) }
            ret (Event{ Text: decoded }, true, ok)
        }
        if str.starts_with(source[s.at..], "<!--") {
            let (close, has_close) = str.find_from(source, "-->", s.at + 4usize)
            if !has_close { ret (zero, false, Invalid) }
            let body = source[s.at + 4usize..close]
            s.at = close + 3usize
            if s.options.preserve_comments { ret (Event{ Comment: body }, true, ok) }
            continue
        }
        if str.starts_with(source[s.at..], "<![CDATA[") {
            if s.depth == 0usize { ret (zero, false, Invalid) }
            let (close, has_close) = str.find_from(source, "]]>", s.at + 9usize)
            if !has_close { ret (zero, false, Invalid) }
            let body = source[s.at + 9usize..close]
            s.at = close + 3usize
            ret (Event{ Text: body }, true, ok)
        }
        if str.starts_with(source[s.at..], "<!") { ret (zero, false, Unsupported) }
        if str.starts_with(source[s.at..], "<?") {
            let (close, has_close) = str.find_from(source, "?>", s.at + 2usize)
            if !has_close { ret (zero, false, Invalid) }
            let target_end = name_end(source, s.at + 2usize)
            if target_end == s.at + 2usize { ret (zero, false, Invalid) }
            let target_name = source[s.at + 2usize..target_end]
            let data = str.trim(source[target_end..close])
            s.at = close + 2usize
            if str.eq(target_name, "xml") { continue }
            ret (Event{ Processing: Processing { target: target_name, data: data } }, true, ok)
        }
        if str.starts_with(source[s.at..], "</") {
            let stop = name_end(source, s.at + 2usize)
            let name = source[s.at + 2usize..stop]
            let close = skip_space(source, stop)
            if name.len == 0usize || close >= source.len || source[close] != 62u8 { ret (zero, false, Invalid) }
            if s.depth == 0usize || !str.eq(s.stack[s.depth - 1usize], name) { ret (zero, false, Invalid) }
            s.depth -= 1usize
            s.at = close + 1usize
            ret (Event{ End: name }, true, ok)
        }
        // A start tag.
        let stop = name_end(source, s.at + 1usize)
        let name = source[s.at + 1usize..stop]
        if name.len == 0usize { ret (zero, false, Invalid) }
        if s.started && s.depth == 0usize { ret (zero, false, Invalid) }
        var at = stop
        var count = 0usize
        // Count the attributes, then fill them.
        var probe = at
        while true {
            probe = skip_space(source, probe)
            if probe >= source.len { ret (zero, false, Invalid) }
            if source[probe] == 62u8 || source[probe] == 47u8 { break }
            let attribute_end = name_end(source, probe)
            if attribute_end == probe { ret (zero, false, Invalid) }
            var eq = skip_space(source, attribute_end)
            if eq >= source.len || source[eq] != 61u8 { ret (zero, false, Invalid) }
            eq = skip_space(source, eq + 1usize)
            if eq >= source.len || (source[eq] != 34u8 && source[eq] != 39u8) { ret (zero, false, Invalid) }
            let quote = source[eq]
            var value_end = eq + 1usize
            while value_end < source.len && source[value_end] != quote && source[value_end] != 60u8 { value_end += 1usize }
            if value_end >= source.len || source[value_end] != quote { ret (zero, false, Invalid) }
            count += 1usize
            probe = value_end + 1usize
        }
        let (attributes, attributes_error) = mem.alloc[Attribute](s.a, count)
        if attributes_error != ok { ret (zero, false, attributes_error) }
        var index = 0usize
        while index < count {
            at = skip_space(source, at)
            let attribute_end = name_end(source, at)
            var eq = skip_space(source, attribute_end)
            eq = skip_space(source, eq + 1usize)
            let quote = source[eq]
            var value_end = eq + 1usize
            while source[value_end] != quote { value_end += 1usize }
            let (value, value_error) = decode(s.a, source[eq + 1usize..value_end])
            if value_error != ok { ret (zero, false, value_error) }
            attributes[index].name = source[at..attribute_end]
            attributes[index].value = value
            var j = 0usize
            while j < index {
                if str.eq(attributes[j].name, attributes[index].name) { ret (zero, false, Invalid) }
                j += 1usize
            }
            index += 1usize
            at = value_end + 1usize
        }
        at = skip_space(source, at)
        var empty = false
        if source[at] == 47u8 {
            empty = true
            at += 1usize
            if at >= source.len || source[at] != 62u8 { ret (zero, false, Invalid) }
        }
        s.at = at + 1usize
        s.started = true
        if empty {
            s.pending_end = name
            s.has_pending = true
        } else {
            if s.depth >= usize(s.options.max_depth) { ret (zero, false, TooDeep) }
            s.stack[s.depth] = name
            s.depth += 1usize
        }
        ret (Event{ Start: StartElement { name: name, attributes: attributes, empty: empty } }, true, ok)
    }
}

fn writer(sink: io.Writer) -> Writer {
    ret Writer { sink: sink, depth: 0u16 }
}

fn write_escaped(sink: *io.Writer, value: str, in_attribute: bool) -> err {
    var at = 0usize
    var from = 0usize
    while at < value.len {
        let c = value[at]
        var replacement = ""
        if c == 60u8 { replacement = "&lt;" }
        if c == 62u8 { replacement = "&gt;" }
        if c == 38u8 { replacement = "&amp;" }
        if in_attribute && c == 34u8 { replacement = "&quot;" }
        if replacement.len > 0usize {
            try io.write_all(sink, value[from..at])
            try io.write_all(sink, replacement)
            from = at + 1usize
        }
        at += 1usize
    }
    ret io.write_all(sink, value[from..])
}

fn start(w: *Writer, name: str, attributes: []const Attribute) -> err {
    if name.len == 0usize { ret Invalid }
    try io.write_all(&w.sink, "<")
    try io.write_all(&w.sink, name)
    var i = 0usize
    while i < attributes.len {
        try io.write_all(&w.sink, " ")
        try io.write_all(&w.sink, attributes[i].name)
        try io.write_all(&w.sink, "=\"")
        try write_escaped(&w.sink, attributes[i].value, true)
        try io.write_all(&w.sink, "\"")
        i += 1usize
    }
    try io.write_all(&w.sink, ">")
    if w.depth == 65535u16 { ret TooDeep }
    w.depth += 1u16
    ret ok
}

fn text(w: *Writer, value: str) -> err {
    ret write_escaped(&w.sink, value, false)
}

fn comment(w: *Writer, value: str) -> err {
    if str.contains(value, "--") { ret Invalid }
    try io.write_all(&w.sink, "<!--")
    try io.write_all(&w.sink, value)
    ret io.write_all(&w.sink, "-->")
}

fn end(w: *Writer, name: str) -> err {
    if w.depth == 0u16 { ret Invalid }
    try io.write_all(&w.sink, "</")
    try io.write_all(&w.sink, name)
    try io.write_all(&w.sink, ">")
    w.depth -= 1u16
    ret ok
}
