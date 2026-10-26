// The WebAssembly back end's source map (C211, D5683): a Source Map v3 file whose one
// generated line has the byte offset in the module file as its column, and the custom
// section that names it. The entries are made while the bodies are written (wasm_code.e).
use wasm_code as w

// One base64 VLQ of the difference `now` - `before`.
fn put_delta(o: *w.Out, now: usize, before: usize) {
    let digits = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var value = 0usize
    if now < before { value = ((before - now) << 1usize) | 1usize } else { value = (now - before) << 1usize }
    var more = true
    while more {
        var digit = value & 31usize
        value = value >> 5usize
        if value != 0usize { digit = digit | 32usize }
        w.put(o, usize(digits[digit]))
        more = value != 0usize
    }
}

fn put_json_text(o: *w.Out, text: str) {
    var at = 0usize
    while at < text.len {
        let c = usize(text[at])
        if c == 34usize || c == 92usize { w.put(o, 92usize) }
        w.put(o, c)
        at += 1usize
    }
}

// The map's text; `bodies_start` is where the code section's bodies begin in the file.
fn map_text(gen: *w.Gen, bodies_start: usize) -> ([]u8, err) {
    var out: w.Out = zero
    var capacity = 256usize + gen.map_count * 40usize
    var path_at = 0usize
    while path_at < gen.map_path_count {
        capacity += gen.map_paths[path_at].len * 2usize + 8usize
        path_at += 1usize
    }
    let init_error = w.init_out(gen.a, &out, capacity)
    if init_error != ok { ret (out.bytes, init_error) }
    w.put_text(&out, "{\"version\":3,\"sources\":[")
    path_at = 0usize
    while path_at < gen.map_path_count {
        if path_at != 0usize { w.put(&out, 44usize) }
        w.put(&out, 34usize)
        put_json_text(&out, gen.map_paths[path_at])
        w.put(&out, 34usize)
        path_at += 1usize
    }
    w.put_text(&out, "],\"names\":[],\"mappings\":\"")
    var column = 0usize
    var source = 0usize
    var line = 0usize
    var source_column = 0usize
    var at = 0usize
    while at < gen.map_count {
        if at != 0usize { w.put(&out, 44usize) }
        let file_offset = bodies_start + gen.map_offset[at]
        put_delta(&out, file_offset, column)
        put_delta(&out, gen.map_source[at], source)
        put_delta(&out, gen.map_line[at] - 1usize, line)
        var entry_column = 0usize
        if gen.map_column[at] != 0usize { entry_column = gen.map_column[at] - 1usize }
        put_delta(&out, entry_column, source_column)
        column = file_offset
        source = gen.map_source[at]
        line = gen.map_line[at] - 1usize
        source_column = entry_column
        at += 1usize
    }
    w.put_text(&out, "\"}\n")
    if out.full { ret (out.bytes, w.Unsupported) }
    ret (out.bytes[0usize..out.count], ok)
}

// The custom section's body: the map's file name beside the module.
fn write_url(body: *w.Out, name: str) {
    w.put_name(body, "sourceMappingURL")
    w.put_name(body, name)
}
