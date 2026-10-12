// TLS trust-root provisioning (L109), the portable half: turn PEM text into the DER bundle `tls.ClientConfig.trust_roots`
// takes (certificates back to back, each a self-delimiting SEQUENCE). Only CERTIFICATE blocks count; a block that does
// not parse as an X.509 certificate is skipped and counted, a certificate seen twice is kept once, and text between
// blocks (the comments of a distribution bundle) is ignored. `e.net.tls.hoststore` reads what a host provides and
// `e.net.tls.mozilla` carries a bundled set; both answer a `Bundle`, and `merge` unions bundles, so a caller writes
// `merge(host, bundled)` or passes its own pinned roots alone.
//
// Memory: `a` holds the result, sized to the input; scratch for each block is reset before the next.
use e.crypto.x509 as x509
use e.fmt.asn1 as asn1
use e.fmt.pem as pem
use e.fs
use e.mem
use e.str

// `der` is the concatenated certificates, `count` how many, `skipped` how many CERTIFICATE blocks were dropped
// (unparsable) and `duplicates` how many repeated one already kept.
type Bundle = struct { der: []const u8, count: usize, skipped: usize, duplicates: usize }

error Empty
error TooLarge

// A certificate DER already present in the concatenated bundle.
fn contains(bundle: []const u8, certificate: []const u8) -> bool {
    var walk = asn1.reader(bundle, 16u16)
    while walk.off < walk.data.len {
        let (value, present, walk_error) = asn1.reader_next_err(&walk)
        if walk_error != ok || !present { ret false }
        if x509.same_der(value.encoded, certificate) { ret true }
    }
    ret false
}

// How many certificates a DER bundle holds, or `Empty` when it is not a run of certificate SEQUENCEs that parse.
fn count_der(a: *mem.Arena, bundle: []const u8) -> (usize, err) {
    var walk = asn1.reader(bundle, 16u16)
    var count = 0usize
    while walk.off < walk.data.len {
        let (value, present, walk_error) = asn1.reader_next_err(&walk)
        if walk_error != ok || !present || !asn1.is_universal(value, 16u32, true) { ret (0usize, Empty) }
        let mark = mem.mark(a)
        let (certificate, parse_error) = x509.parse(a, value.encoded)
        mem.reset(a, mark)
        if parse_error != ok { ret (0usize, Empty) }
        count += 1usize
    }
    ret (count, ok)
}

// The certificates of PEM text. `limit` bounds the input; `Empty` when no certificate survives.
fn from_pem(a: *mem.Arena, source: str, limit: usize) -> (Bundle, err) {
    var out: Bundle = zero
    if source.len > limit { ret (out, TooLarge) }
    let (buffer, buffer_error) = mem.alloc[u8](a, source.len + 1usize)
    if buffer_error != ok { ret (out, buffer_error) }
    var used = 0usize
    var count = 0usize
    var skipped = 0usize
    var duplicates = 0usize
    var rest = source
    while true {
        let mark = mem.mark(a)
        let (block, after, decode_error) = pem.decode(a, rest, 1048576usize)
        if decode_error != ok {
            mem.reset(a, mark)
            break
        }
        rest = after
        if str.eq(block.label, "CERTIFICATE") {
            let (certificate, parse_error) = x509.parse(a, block.bytes)
            if parse_error != ok {
                skipped += 1usize
            } else if contains(buffer[0usize..used], block.bytes) {
                duplicates += 1usize
            } else if used + block.bytes.len > buffer.len {
                mem.reset(a, mark)
                ret (out, TooLarge)
            } else {
                mem.copy[u8](buffer[used..], block.bytes)
                used += block.bytes.len
                count += 1usize
            }
        }
        mem.reset(a, mark)
    }
    if count == 0usize { ret (out, Empty) }
    out = Bundle { der: buffer[0usize..used], count: count, skipped: skipped, duplicates: duplicates }
    ret (out, ok)
}

// Read a PEM file (a distribution's `ca-certificates.crt`) and answer its certificates.
fn from_pem_file(a: *mem.Arena, path_text: str, limit: usize) -> (Bundle, err) {
    var out: Bundle = zero
    let (data, read_error) = fs.read_file(a, path_text, limit)
    if read_error != ok { ret (out, read_error) }
    let (bundle, bundle_error) = from_pem(a, data, limit)
    ret (bundle, bundle_error)
}

// A DER bundle (as handed back by a host store or written by `tls.ClientConfig`): validated and deduplicated.
fn from_der(a: *mem.Arena, source: []const u8) -> (Bundle, err) {
    var out: Bundle = zero
    let (buffer, buffer_error) = mem.alloc[u8](a, source.len + 1usize)
    if buffer_error != ok { ret (out, buffer_error) }
    var walk = asn1.reader(source, 16u16)
    var used = 0usize
    var count = 0usize
    var skipped = 0usize
    var duplicates = 0usize
    while walk.off < walk.data.len {
        let (value, present, walk_error) = asn1.reader_next_err(&walk)
        if walk_error != ok || !present || !asn1.is_universal(value, 16u32, true) { break }
        let mark = mem.mark(a)
        let (certificate, parse_error) = x509.parse(a, value.encoded)
        mem.reset(a, mark)
        if parse_error != ok {
            skipped += 1usize
        } else if contains(buffer[0usize..used], value.encoded) {
            duplicates += 1usize
        } else {
            mem.copy[u8](buffer[used..], value.encoded)
            used += value.encoded.len
            count += 1usize
        }
    }
    if count == 0usize { ret (out, Empty) }
    out = Bundle { der: buffer[0usize..used], count: count, skipped: skipped, duplicates: duplicates }
    ret (out, ok)
}

// The union of two DER bundles, `left`'s certificates first, each once.
fn merge(a: *mem.Arena, left: []const u8, right: []const u8) -> (Bundle, err) {
    var out: Bundle = zero
    let (buffer, buffer_error) = mem.alloc[u8](a, left.len + right.len + 1usize)
    if buffer_error != ok { ret (out, buffer_error) }
    mem.copy[u8](buffer[0usize..], left)
    var used = left.len
    var count = 0usize
    var duplicates = 0usize
    var walk = asn1.reader(left, 16u16)
    while walk.off < walk.data.len {
        let (value, present, walk_error) = asn1.reader_next_err(&walk)
        if walk_error != ok || !present { break }
        count += 1usize
    }
    var other = asn1.reader(right, 16u16)
    while other.off < other.data.len {
        let (value, present, walk_error) = asn1.reader_next_err(&other)
        if walk_error != ok || !present { break }
        if contains(buffer[0usize..used], value.encoded) {
            duplicates += 1usize
        } else {
            mem.copy[u8](buffer[used..], value.encoded)
            used += value.encoded.len
            count += 1usize
        }
    }
    if count == 0usize { ret (out, Empty) }
    out = Bundle { der: buffer[0usize..used], count: count, skipped: 0usize, duplicates: duplicates }
    ret (out, ok)
}
