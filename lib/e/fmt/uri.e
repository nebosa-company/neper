// URIs by RFC 3986: a parse that borrows its parts from the source, reference
// resolution with the dot segments removed, the normalisations that preserve meaning
// (a lower-case scheme and host, upper-case hex escapes, unreserved characters
// unescaped), and percent-encoding per component. Nothing here reads `+` as a space;
// that is HTML forms' convention, not a URI's.

use e.mem

type Uri = struct { scheme: str, authority: str, userinfo: str, host: str, port: str, path: str, query: str, fragment: str }
type EncodeSet = enum u8 { Path, PathSegment, Query, QueryComponent, Fragment, UserInfo }
error Invalid

fn is_alpha(c: u8) -> bool {
    let lower = c >= 97u8 && c <= 122u8
    ret lower || (c >= 65u8 && c <= 90u8)
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn is_hex(c: u8) -> bool { ret is_digit(c) || (c >= 97u8 && c <= 102u8) || (c >= 65u8 && c <= 70u8) }

fn hex_value(c: u8) -> u8 {
    if is_digit(c) { ret c - 48u8 }
    if c >= 97u8 { ret c - 87u8 }
    ret c - 55u8
}

// RFC 3986's unreserved set: never needs escaping in any component.
fn is_unreserved(c: u8) -> bool {
    ret is_alpha(c) || is_digit(c) || c == 45u8 || c == 46u8 || c == 95u8 || c == 126u8
}

fn is_sub_delim(c: u8) -> bool {
    ret c == 33u8 || c == 36u8 || c == 38u8 || c == 39u8 || c == 40u8 || c == 41u8 || c == 42u8 || c == 43u8 || c == 44u8 || c == 59u8 || c == 61u8
}

// Splits `scheme://authority/path?query#fragment` with the authority into its three
// parts. Every slice points into `source`. A scheme is required only in its own shape:
// a source without `:` before any `/`, `?` or `#` is a relative reference.
fn parse(source: str) -> (Uri, err) {
    var u: Uri = zero
    var at = 0usize
    // Scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"
    var scheme_end = 0usize
    var has_scheme = false
    while scheme_end < source.len {
        let c = source[scheme_end]
        if c == 58u8 {
            has_scheme = scheme_end > 0usize
            break
        }
        if c == 47u8 || c == 63u8 || c == 35u8 { break }
        if !(is_alpha(c) || (scheme_end > 0usize && (is_digit(c) || c == 43u8 || c == 45u8 || c == 46u8))) { break }
        scheme_end += 1usize
    }
    if has_scheme {
        u.scheme = source[..scheme_end]
        at = scheme_end + 1usize
    }
    // Authority: after "//", up to the next "/", "?" or "#".
    if at + 1usize < source.len && source[at] == 47u8 && source[at + 1usize] == 47u8 {
        at += 2usize
        let authority_start = at
        while at < source.len && source[at] != 47u8 && source[at] != 63u8 && source[at] != 35u8 { at += 1usize }
        u.authority = source[authority_start..at]
        let split_error = split_authority(&u)
        if split_error != ok { ret (zero, split_error) }
    }
    let path_start = at
    while at < source.len && source[at] != 63u8 && source[at] != 35u8 { at += 1usize }
    u.path = source[path_start..at]
    if at < source.len && source[at] == 63u8 {
        at += 1usize
        let query_start = at
        while at < source.len && source[at] != 35u8 { at += 1usize }
        u.query = source[query_start..at]
    }
    if at < source.len && source[at] == 35u8 { u.fragment = source[at + 1usize..] }
    // A percent must start two hex digits, everywhere.
    at = 0usize
    while at < source.len {
        if source[at] == 37u8 {
            if at + 2usize >= source.len || !is_hex(source[at + 1usize]) || !is_hex(source[at + 2usize]) { ret (zero, Invalid) }
        }
        at += 1usize
    }
    ret (u, ok)
}

// `userinfo@host:port`, the host possibly a bracketed IP literal.
fn split_authority(u: *Uri) -> err {
    let authority = u.authority
    var host_start = 0usize
    var at = 0usize
    while at < authority.len {
        if authority[at] == 64u8 {
            u.userinfo = authority[..at]
            host_start = at + 1usize
        }
        at += 1usize
    }
    var host_end = authority.len
    if host_start < authority.len && authority[host_start] == 91u8 {
        var close = host_start
        while close < authority.len && authority[close] != 93u8 { close += 1usize }
        if close >= authority.len { ret Invalid }
        host_end = close + 1usize
        if host_end < authority.len && authority[host_end] != 58u8 { ret Invalid }
    } else {
        at = host_start
        while at < authority.len {
            if authority[at] == 58u8 { host_end = at }
            at += 1usize
        }
    }
    u.host = authority[host_start..host_end]
    if host_end < authority.len {
        let port = authority[host_end + 1usize..]
        at = 0usize
        while at < port.len {
            if !is_digit(port[at]) { ret Invalid }
            at += 1usize
        }
        u.port = port
    }
    ret ok
}

// RFC 3986 5.2.4, written into `out`; returns the length used.
fn remove_dot_segments(path: str, out: []u8) -> usize {
    var written = 0usize
    var at = 0usize
    while at < path.len {
        // Take one segment, including its leading slash if any.
        let segment_start = at
        if path[at] == 47u8 { at += 1usize }
        while at < path.len && path[at] != 47u8 { at += 1usize }
        let segment = path[segment_start..at]
        var name = segment
        if name.len > 0usize && name[0] == 47u8 { name = name[1..] }
        var is_dot = name.len == 1usize && name[0] == 46u8
        var is_dot_dot = name.len == 2usize && name[0] == 46u8 && name[1] == 46u8
        if is_dot_dot {
            // Drop the last complete segment of the output.
            while written > 0usize && out[written - 1usize] != 47u8 { written -= 1usize }
            if written > 0usize { written -= 1usize }
            if at >= path.len && written < out.len {
                out[written] = 47u8
                written += 1usize
            }
        } else {
            if is_dot {
                if at >= path.len && written < out.len {
                    out[written] = 47u8
                    written += 1usize
                }
            } else {
                var copy = 0usize
                while copy < segment.len && written < out.len {
                    out[written] = segment[copy]
                    written += 1usize
                    copy += 1usize
                }
            }
        }
    }
    ret written
}

fn merge_paths(a: *mem.Arena, base: Uri, reference_path: str) -> (str, err) {
    if base.authority.len > 0usize && base.path.len == 0usize {
        let (joined, joined_error) = mem.alloc[u8](a, reference_path.len + 1usize)
        if joined_error != ok { ret ("", joined_error) }
        joined[0] = 47u8
        var at = 0usize
        while at < reference_path.len {
            joined[at + 1usize] = reference_path[at]
            at += 1usize
        }
        ret (joined[0..], ok)
    }
    var cut = base.path.len
    while cut > 0usize && base.path[cut - 1usize] != 47u8 { cut -= 1usize }
    let (joined, joined_error) = mem.alloc[u8](a, cut + reference_path.len)
    if joined_error != ok { ret ("", joined_error) }
    var at = 0usize
    while at < cut {
        joined[at] = base.path[at]
        at += 1usize
    }
    at = 0usize
    while at < reference_path.len {
        joined[cut + at] = reference_path[at]
        at += 1usize
    }
    ret (joined[0..], ok)
}

fn cleaned_path(a: *mem.Arena, path: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, path.len + 1usize)
    if out_error != ok { ret ("", out_error) }
    let used = remove_dot_segments(path, out)
    ret (out[..used], ok)
}

// RFC 3986 5.2.2: the reference's components take over from the first one it has.
fn resolve(a: *mem.Arena, base: Uri, reference: Uri) -> (Uri, err) {
    var result: Uri = zero
    if reference.scheme.len > 0usize {
        result = reference
        let (path, path_error) = cleaned_path(a, reference.path)
        if path_error != ok { ret (zero, path_error) }
        result.path = path
        ret (result, ok)
    }
    result.scheme = base.scheme
    if reference.authority.len > 0usize {
        result.authority = reference.authority
        result.userinfo = reference.userinfo
        result.host = reference.host
        result.port = reference.port
        let (path, path_error) = cleaned_path(a, reference.path)
        if path_error != ok { ret (zero, path_error) }
        result.path = path
        result.query = reference.query
        result.fragment = reference.fragment
        ret (result, ok)
    }
    result.authority = base.authority
    result.userinfo = base.userinfo
    result.host = base.host
    result.port = base.port
    if reference.path.len == 0usize {
        result.path = base.path
        result.query = base.query
        if reference.query.len > 0usize { result.query = reference.query }
    } else {
        if reference.path[0] == 47u8 {
            let (path, path_error) = cleaned_path(a, reference.path)
            if path_error != ok { ret (zero, path_error) }
            result.path = path
        } else {
            let (merged, merge_error) = merge_paths(a, base, reference.path)
            if merge_error != ok { ret (zero, merge_error) }
            let (path, path_error) = cleaned_path(a, merged)
            if path_error != ok { ret (zero, path_error) }
            result.path = path
        }
        result.query = reference.query
    }
    result.fragment = reference.fragment
    ret (result, ok)
}

fn lowered(a: *mem.Arena, text: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, text.len)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    while at < text.len {
        var c = text[at]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[at] = c
        at += 1usize
    }
    ret (out[0..], ok)
}

// Escapes of unreserved characters are decoded and every other escape's hex is
// upper-cased; the text is otherwise as it was.
fn normalized_escapes(a: *mem.Arena, text: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, text.len)
    if out_error != ok { ret ("", out_error) }
    var written = 0usize
    var at = 0usize
    while at < text.len {
        let c = text[at]
        if c == 37u8 && at + 2usize < text.len && is_hex(text[at + 1usize]) && is_hex(text[at + 2usize]) {
            let value = hex_value(text[at + 1usize]) * 16u8 + hex_value(text[at + 2usize])
            if is_unreserved(value) {
                out[written] = value
                written += 1usize
            } else {
                out[written] = 37u8
                out[written + 1usize] = upper_hex(value >> 4u8)
                out[written + 2usize] = upper_hex(value & 15u8)
                written += 3usize
            }
            at += 3usize
        } else {
            out[written] = c
            written += 1usize
            at += 1usize
        }
    }
    ret (out[..written], ok)
}

fn upper_hex(nibble: u8) -> u8 {
    if nibble < 10u8 { ret nibble + 48u8 }
    ret nibble + 55u8
}

fn normalize(a: *mem.Arena, value: Uri) -> (Uri, err) {
    var out = value
    let (scheme, scheme_error) = lowered(a, value.scheme)
    if scheme_error != ok { ret (zero, scheme_error) }
    out.scheme = scheme
    let (host, host_error) = lowered(a, value.host)
    if host_error != ok { ret (zero, host_error) }
    out.host = host
    let (userinfo, userinfo_error) = normalized_escapes(a, value.userinfo)
    if userinfo_error != ok { ret (zero, userinfo_error) }
    out.userinfo = userinfo
    let (escaped_path, path_error) = normalized_escapes(a, value.path)
    if path_error != ok { ret (zero, path_error) }
    var path = escaped_path
    if path.len == 0usize && value.authority.len > 0usize { path = "/" }
    let (clean, clean_error) = cleaned_path(a, path)
    if clean_error != ok { ret (zero, clean_error) }
    out.path = clean
    let (query, query_error) = normalized_escapes(a, value.query)
    if query_error != ok { ret (zero, query_error) }
    out.query = query
    let (fragment, fragment_error) = normalized_escapes(a, value.fragment)
    if fragment_error != ok { ret (zero, fragment_error) }
    out.fragment = fragment
    // The authority is rebuilt from its parts, so it agrees with them.
    let (authority, authority_error) = format_authority(a, out)
    if authority_error != ok { ret (zero, authority_error) }
    out.authority = authority
    ret (out, ok)
}

fn format_authority(a: *mem.Arena, value: Uri) -> (str, err) {
    if value.host.len == 0usize && value.userinfo.len == 0usize && value.port.len == 0usize { ret ("", ok) }
    let (out, out_error) = mem.alloc[u8](a, value.userinfo.len + value.host.len + value.port.len + 2usize)
    if out_error != ok { ret ("", out_error) }
    var written = 0usize
    if value.userinfo.len > 0usize {
        written = append(out, written, value.userinfo)
        out[written] = 64u8
        written += 1usize
    }
    written = append(out, written, value.host)
    if value.port.len > 0usize {
        out[written] = 58u8
        written += 1usize
        written = append(out, written, value.port)
    }
    ret (out[..written], ok)
}

fn append(out: []u8, at: usize, text: str) -> usize {
    var copy = 0usize
    while copy < text.len {
        out[at + copy] = text[copy]
        copy += 1usize
    }
    ret at + text.len
}

// RFC 3986 5.3, from the parts: the authority's presence is the authority's, not
// the host's, so an empty authority with `//` written is kept as written.
fn format(a: *mem.Arena, value: Uri) -> (str, err) {
    let (authority, authority_error) = format_authority(a, value)
    if authority_error != ok { ret ("", authority_error) }
    var shown = authority
    if value.authority.len > 0usize && authority.len == 0usize { shown = value.authority }
    let (out, out_error) = mem.alloc[u8](a, value.scheme.len + shown.len + value.path.len + value.query.len + value.fragment.len + 5usize)
    if out_error != ok { ret ("", out_error) }
    var written = 0usize
    if value.scheme.len > 0usize {
        written = append(out, written, value.scheme)
        out[written] = 58u8
        written += 1usize
    }
    if shown.len > 0usize || value.authority.len > 0usize {
        out[written] = 47u8
        out[written + 1usize] = 47u8
        written += 2usize
        written = append(out, written, shown)
    }
    written = append(out, written, value.path)
    if value.query.len > 0usize {
        out[written] = 63u8
        written += 1usize
        written = append(out, written, value.query)
    }
    if value.fragment.len > 0usize {
        out[written] = 35u8
        written += 1usize
        written = append(out, written, value.fragment)
    }
    ret (out[..written], ok)
}

// Whether `c` may stand unescaped in the component the set names.
fn allowed(c: u8, set: EncodeSet) -> bool {
    if is_unreserved(c) { ret true }
    if set == .Path { ret is_sub_delim(c) || c == 58u8 || c == 64u8 || c == 47u8 }
    if set == .PathSegment { ret is_sub_delim(c) || c == 58u8 || c == 64u8 }
    if set == .Query { ret is_sub_delim(c) || c == 58u8 || c == 64u8 || c == 47u8 || c == 63u8 }
    if set == .QueryComponent { ret c == 33u8 || c == 36u8 || c == 39u8 || c == 40u8 || c == 41u8 || c == 42u8 || c == 44u8 || c == 59u8 || c == 58u8 || c == 64u8 || c == 47u8 || c == 63u8 }
    if set == .Fragment { ret is_sub_delim(c) || c == 58u8 || c == 64u8 || c == 47u8 || c == 63u8 }
    ret is_sub_delim(c) || c == 58u8
}

fn percent_encode(a: *mem.Arena, source: []const u8, set: EncodeSet) -> (str, err) {
    var needed = 0usize
    var at = 0usize
    while at < source.len {
        if allowed(source[at], set) { needed += 1usize } else { needed += 3usize }
        at += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, needed)
    if out_error != ok { ret ("", out_error) }
    var written = 0usize
    at = 0usize
    while at < source.len {
        let c = source[at]
        if allowed(c, set) {
            out[written] = c
            written += 1usize
        } else {
            out[written] = 37u8
            out[written + 1usize] = upper_hex(c >> 4u8)
            out[written + 2usize] = upper_hex(c & 15u8)
            written += 3usize
        }
        at += 1usize
    }
    ret (out[0..], ok)
}

fn percent_decode(a: *mem.Arena, source: str) -> ([]u8, err) {
    let (out, out_error) = mem.alloc[u8](a, source.len)
    if out_error != ok { ret (zero, out_error) }
    var written = 0usize
    var at = 0usize
    while at < source.len {
        let c = source[at]
        if c == 37u8 {
            if at + 2usize >= source.len || !is_hex(source[at + 1usize]) || !is_hex(source[at + 2usize]) { ret (zero, Invalid) }
            out[written] = hex_value(source[at + 1usize]) * 16u8 + hex_value(source[at + 2usize])
            at += 3usize
        } else {
            out[written] = c
            at += 1usize
        }
        written += 1usize
    }
    ret (out[..written], ok)
}

// The value of the first `name=value` pair in `&`-separated form, still encoded;
// `false` when no pair has the name. A pair without `=` has the empty value.
fn query_get(query: str, name: str) -> (str, bool, err) {
    var at = 0usize
    while at <= query.len {
        let pair_start = at
        while at < query.len && query[at] != 38u8 { at += 1usize }
        let pair = query[pair_start..at]
        var split = pair.len
        var k = 0usize
        while k < pair.len {
            if pair[k] == 61u8 {
                split = k
                break
            }
            k += 1usize
        }
        let key = pair[..split]
        if key.len == name.len {
            var same = true
            k = 0usize
            while k < key.len {
                if key[k] != name[k] { same = false }
                k += 1usize
            }
            if same {
                if split < pair.len { ret (pair[split + 1usize..], true, ok) }
                ret ("", true, ok)
            }
        }
        at += 1usize
    }
    ret ("", false, ok)
}

// --- application/x-www-form-urlencoded.

error TooSmall

// One form-encoded component decoded: `+` is a space, `%XX` a byte.
fn form_decode(a: *mem.Arena, source: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, source.len)
    if out_error != ok { ret ("", out_error) }
    var written = 0usize
    var at = 0usize
    while at < source.len {
        let c = source[at]
        if c == 37u8 {
            if at + 2usize >= source.len || !is_hex(source[at + 1usize]) || !is_hex(source[at + 2usize]) { ret ("", Invalid) }
            out[written] = hex_value(source[at + 1usize]) * 16u8 + hex_value(source[at + 2usize])
            at += 3usize
        } else {
            if c == 43u8 { out[written] = 32u8 } else { out[written] = c }
            at += 1usize
        }
        written += 1usize
    }
    ret (out[..written], ok)
}

// The `&`-separated pairs of `query` decoded into `keys` and `values`, in order and with
// repeats kept: the count, or `Invalid` for a bad escape, or `TooSmall` when the slices
// fill. A pair without `=` has the empty value; an empty pair (`a&&b`) is skipped.
fn query_parse(a: *mem.Arena, query: str, keys: []str, values: []str) -> (usize, err) {
    var count = 0usize
    var at = 0usize
    while at <= query.len {
        let pair_start = at
        while at < query.len && query[at] != 38u8 { at += 1usize }
        let pair = query[pair_start..at]
        at += 1usize
        if pair.len == 0usize { continue }
        if count >= keys.len || count >= values.len { ret (count, TooSmall) }
        var split = pair.len
        var k = 0usize
        while k < pair.len {
            if pair[k] == 61u8 {
                split = k
                break
            }
            k += 1usize
        }
        let (key, key_error) = form_decode(a, pair[..split])
        if key_error != ok { ret (count, key_error) }
        var value = ""
        if split < pair.len {
            let (decoded, value_error) = form_decode(a, pair[split + 1usize..])
            if value_error != ok { ret (count, value_error) }
            value = decoded
        }
        keys[count] = key
        values[count] = value
        count += 1usize
    }
    ret (count, ok)
}

fn form_encoded_len(text: str) -> usize {
    var needed = 0usize
    var at = 0usize
    while at < text.len {
        if is_unreserved(text[at]) || text[at] == 32u8 { needed += 1usize } else { needed += 3usize }
        at += 1usize
    }
    ret needed
}

fn form_encode_into(out: []u8, at: usize, text: str) -> usize {
    var written = at
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_unreserved(c) {
            out[written] = c
            written += 1usize
        } else {
            if c == 32u8 {
                out[written] = 43u8
                written += 1usize
            } else {
                out[written] = 37u8
                out[written + 1usize] = upper_hex(c >> 4u8)
                out[written + 2usize] = upper_hex(c & 15u8)
                written += 3usize
            }
        }
        i += 1usize
    }
    ret written
}

// `keys[i]=values[i]` joined by `&`, each side with only RFC 3986 unreserved bytes left
// bare, a space as `+` and everything else as `%XX`.
fn query_build(a: *mem.Arena, keys: []const str, values: []const str) -> (str, err) {
    if keys.len != values.len { ret ("", Invalid) }
    var needed = 0usize
    var i = 0usize
    while i < keys.len {
        if i > 0usize { needed += 1usize }
        needed += form_encoded_len(keys[i]) + 1usize + form_encoded_len(values[i])
        i += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, needed)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    i = 0usize
    while i < keys.len {
        if i > 0usize {
            out[at] = 38u8
            at += 1usize
        }
        at = form_encode_into(out, at, keys[i])
        out[at] = 61u8
        at += 1usize
        at = form_encode_into(out, at, values[i])
        i += 1usize
    }
    ret (out[..at], ok)
}
