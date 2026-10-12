// Just enough JSON for a device's own protocols (C151): the value of a top-level-looking key in an object's text,
// as a string or as a number, without building a tree. A key is found where `"key":` appears, so a nested object
// with the same key name can answer first; the protocols that use this have flat objects.
use httpstream

fn hex4(body_text: str, at: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < 4usize && at + i < body_text.len {
        let d = httpstream.hex_value(body_text[at + i])
        if d == 99usize { ret 0usize }
        v = v * 16usize + d
        i += 1usize
    }
    ret v
}

// Whether `body_text` holds `"key":` at `at`.
fn key_at(body_text: str, at: usize, key: str) -> bool {
    if at + key.len + 3usize > body_text.len { ret false }
    if body_text[at] != 34u8 || body_text[at + 1usize + key.len] != 34u8 || body_text[at + 2usize + key.len] != 58u8 { ret false }
    var i = 0usize
    while i < key.len {
        if body_text[at + 1usize + i] != key[i] { ret false }
        i += 1usize
    }
    ret true
}

// The position after `"key":` and any spaces, or `body_text.len` when the key is absent.
fn value_at(body_text: str, key: str) -> usize {
    var at = 0usize
    while at + key.len + 3usize <= body_text.len {
        if key_at(body_text, at, key) {
            var v = at + 3usize + key.len
            while v < body_text.len && body_text[v] == 32u8 { v += 1usize }
            ret v
        }
        at += 1usize
    }
    ret body_text.len
}

// The string value of `key` into `out` (escapes undone, \u00XX to its byte); its length, 0 when absent.
fn string_of(body_text: str, key: str, out: []u8) -> usize {
    var at = value_at(body_text, key)
    if at >= body_text.len || body_text[at] != 34u8 { ret 0usize }
    at += 1usize
    var n = 0usize
    var done = false
    while at < body_text.len && !done && n + 4usize < out.len {
        let c = body_text[at]
        if c == 34u8 {
            done = true
        } else if c == 92u8 && at + 1usize < body_text.len {
            let e = body_text[at + 1usize]
            at += 2usize
            if e == 110u8 {
                out[n] = 10u8
                n += 1usize
            } else if e == 117u8 && at + 4usize <= body_text.len {
                let cp = hex4(body_text, at)
                at += 4usize
                if cp < 128usize {
                    out[n] = u8(cp)
                    n += 1usize
                } else {
                    out[n] = 63u8
                    n += 1usize
                }
            } else {
                out[n] = e
                n += 1usize
            }
        } else {
            out[n] = c
            n += 1usize
            at += 1usize
        }
    }
    ret n
}

// The unsigned number value of `key`, 0 when absent or not a number.
fn number_of(body_text: str, key: str) -> usize {
    var at = value_at(body_text, key)
    var n = 0usize
    var seen = 0usize
    while at < body_text.len && body_text[at] >= 48u8 && body_text[at] <= 57u8 && seen < 12usize {
        n = n * 10usize + usize(body_text[at] - 48u8)
        at += 1usize
        seen += 1usize
    }
    ret n
}
