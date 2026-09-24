// X.509 certificates over DER through `e.fmt.asn1`, with Ed25519 (RFC 8410) and
// ECDSA P-256/SHA-256 (RFC 5480/RFC 5758): `parse` reads names, validity,
// subject public key, the subjectAltName DNS names and basicConstraints; `parse_pem`
// takes every CERTIFICATE block of a PEM text; `verify_signature` checks a
// certificate's signature over its TBSCertificate bytes with its issuer's key; and
// `verify` builds the chain from a leaf through the intermediates to a root by name,
// checking each signature, each validity window against the caller's `now`, each
// intermediate's CA bit, the leaf's DNS name (a leftmost wildcard allowed) and its
// extended key usage. A name is written `CN=x, O=y` from its attributes in order.
// Unsupported algorithms parse so an unused server-supplied chain suffix is harmless,
// but verification through one is `InvalidCertificate`. Nothing here reads host state.
use e.mem
use e.str
use e.time
use e.crypto.sign as sign
use e.fmt.asn1 as asn1
use e.fmt.pem as pem

type PublicKey = union enum u8 { Ed25519: sign.Ed25519PublicKey, P256: sign.P256PublicKey, Unsupported: []const u8 }
type Certificate = struct { der: []const u8, subject: str, issuer: str, dns_names: []const str, not_before: time.Instant, not_after: time.Instant, public_key: PublicKey, is_ca: bool, has_path_len: bool, path_len: u16, has_key_usage: bool, key_cert_sign: bool, unhandled_critical: bool }
type Pool = struct { certificates: []const Certificate }
type VerifyOptions = struct { roots: Pool, intermediates: Pool, dns_name: str, now: time.Instant, usage: KeyUsage, max_depth: u16 }
type KeyUsage = enum u8 { ServerAuth, ClientAuth, CodeSigning, EmailProtection, Any }
type Chain = struct { certificates: []const Certificate }
error InvalidCertificate
error UnknownAuthority
error Expired
error NameMismatch
error InvalidUsage
error TooDeep

const DEPTH: u16 = 16u16
type SignatureAlgorithm = enum u8 { Ed25519, EcdsaSha256, Unsupported }

// The next value of a reader, or `InvalidCertificate` when there is none.
fn next(r: *asn1.Reader) -> (asn1.Value, err) {
    let (value, present, next_error) = asn1.reader_next_err(r)
    if next_error != ok { ret (zero, InvalidCertificate) }
    if !present { ret (zero, InvalidCertificate) }
    ret (value, ok)
}

fn expect(r: *asn1.Reader, number: u32, constructed: bool) -> (asn1.Value, err) {
    let (value, next_error) = next(r)
    if next_error != ok { ret (zero, next_error) }
    if value.tag.class != .Universal || value.tag.number != number || value.tag.constructed != constructed { ret (zero, InvalidCertificate) }
    ret (value, ok)
}

fn inside(value: asn1.Value) -> (asn1.Reader, err) {
    let (r, children_error) = asn1.children(value, DEPTH)
    if children_error != ok { ret (zero, InvalidCertificate) }
    ret (r, ok)
}

fn oid_equal(content: []const u8, expected: []const u8) -> bool {
    if content.len != expected.len { ret false }
    var i = 0usize
    while i < content.len {
        if content[i] != expected[i] { ret false }
        i += 1usize
    }
    ret true
}

fn attribute_name(oid: []const u8) -> str {
    if oid.len == 3usize && oid[0] == 85u8 && oid[1] == 4u8 {
        if oid[2] == 3u8 { ret "CN" }
        if oid[2] == 6u8 { ret "C" }
        if oid[2] == 7u8 { ret "L" }
        if oid[2] == 8u8 { ret "ST" }
        if oid[2] == 10u8 { ret "O" }
        if oid[2] == 11u8 { ret "OU" }
    }
    if oid.len == 9usize && oid[0] == 42u8 && oid[8] == 1u8 { ret "emailAddress" }
    ret "OID"
}

// A Name as `CN=x, O=y`, the attributes in the order they are written.
fn render_name(a: *mem.Arena, name: asn1.Value) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 256usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    let (rdns0, rdns_error) = inside(name)
    if rdns_error != ok { ret ("", rdns_error) }
    var rdns = rdns0
    var first = true
    while true {
        let (rdn, present, rdn_error) = asn1.reader_next_err(&rdns)
        if rdn_error != ok { ret ("", InvalidCertificate) }
        if !present { break }
        let (attributes0, attributes_error) = inside(rdn)
        if attributes_error != ok { ret ("", attributes_error) }
        var attributes = attributes0
        while true {
            let (attribute, has_attribute, attribute_error) = asn1.reader_next_err(&attributes)
            if attribute_error != ok { ret ("", InvalidCertificate) }
            if !has_attribute { break }
            let (pair0, pair_error) = inside(attribute)
            if pair_error != ok { ret ("", pair_error) }
            var pair = pair0
            let (oid, oid_error) = expect(&pair, 6u32, false)
            if oid_error != ok { ret ("", oid_error) }
            let (value, value_error) = next(&pair)
            if value_error != ok { ret ("", value_error) }
            if !first {
                let separator_error = str.push(&b, ", ")
                if separator_error != ok { ret ("", separator_error) }
            }
            first = false
            let name_error = str.push(&b, attribute_name(oid.content))
            if name_error != ok { ret ("", name_error) }
            let equals_error = str.push(&b, "=")
            if equals_error != ok { ret ("", equals_error) }
            let text_error = str.push(&b, value.content)
            if text_error != ok { ret ("", text_error) }
        }
    }
    ret (str.done(&b), ok)
}

fn two_digits(text: []const u8, at: usize) -> (i64, bool) {
    if at + 2usize > text.len { ret (0i64, false) }
    if !str.is_ascii_digit(text[at]) || !str.is_ascii_digit(text[at + 1usize]) { ret (0i64, false) }
    ret (i64(text[at] - 48u8) * 10i64 + i64(text[at + 1usize] - 48u8), true)
}

// UTCTime `YYMMDDHHMMSSZ` or GeneralizedTime `YYYYMMDDHHMMSSZ` as an instant.
fn parse_time(value: asn1.Value) -> (time.Instant, err) {
    let text = value.content
    var at = 0usize
    var year = 0i64
    if value.tag.number == 23u32 {
        let (yy, yy_ok) = two_digits(text, 0usize)
        if !yy_ok { ret (zero, InvalidCertificate) }
        year = 2000i64 + yy
        if yy >= 50i64 { year = 1900i64 + yy }
        at = 2usize
    } else {
        if value.tag.number != 24u32 { ret (zero, InvalidCertificate) }
        let (high, high_ok) = two_digits(text, 0usize)
        let (low, low_ok) = two_digits(text, 2usize)
        if !high_ok || !low_ok { ret (zero, InvalidCertificate) }
        year = high * 100i64 + low
        at = 4usize
    }
    let (month, month_ok) = two_digits(text, at)
    let (day, day_ok) = two_digits(text, at + 2usize)
    let (hour, hour_ok) = two_digits(text, at + 4usize)
    let (minute, minute_ok) = two_digits(text, at + 6usize)
    let (second, second_ok) = two_digits(text, at + 8usize)
    if !month_ok || !day_ok || !hour_ok || !minute_ok || !second_ok { ret (zero, InvalidCertificate) }
    if at + 11usize != text.len || text[at + 10usize] != 90u8 { ret (zero, InvalidCertificate) }
    let date = time.Date { year: i32(year), month: u8(month), day: u8(day) }
    let clock = time.Time { hour: u8(hour), minute: u8(minute), second: u8(second), nanos: 0u32 }
    let (stamp, civil_error) = time.from_civil(date, clock)
    if civil_error != ok { ret (zero, InvalidCertificate) }
    ret (time.Instant { nanos: stamp.nanos }, ok)
}

// The pieces `verify_signature` needs beside the fields: the TBS bytes and the
// signature, found by walking the outer SEQUENCE again.
fn signature_algorithm(value: asn1.Value) -> (SignatureAlgorithm, err) {
    let (parts0, parts_error) = inside(value)
    if parts_error != ok { ret (.Unsupported, parts_error) }
    var parts = parts0
    let (oid, oid_error) = expect(&parts, 6u32, false)
    if oid_error != ok { ret (.Unsupported, oid_error) }
    let ed25519: [3]u8 = [3]u8{ 43, 101, 112 }
    let ecdsa_sha256: [8]u8 = [8]u8{ 42, 134, 72, 206, 61, 4, 3, 2 }
    var algorithm = SignatureAlgorithm.Unsupported
    if oid_equal(oid.content, ed25519[0..]) { algorithm = .Ed25519 }
    if oid_equal(oid.content, ecdsa_sha256[0..]) { algorithm = .EcdsaSha256 }
    if algorithm != .Unsupported {
        let (_, has_parameter, parameter_error) = asn1.reader_next_err(&parts)
        if parameter_error != ok || has_parameter { ret (.Unsupported, InvalidCertificate) }
    }
    ret (algorithm, ok)
}

fn signed_parts(der: []const u8) -> ([]const u8, []const u8, SignatureAlgorithm, []const u8, err) {
    var top = asn1.reader(der, DEPTH)
    let (outer, outer_error) = expect(&top, 16u32, true)
    if outer_error != ok { ret (zero, zero, .Unsupported, zero, outer_error) }
    let (parts0, parts_error) = inside(outer)
    if parts_error != ok { ret (zero, zero, .Unsupported, zero, parts_error) }
    var parts = parts0
    let (tbs, tbs_error) = expect(&parts, 16u32, true)
    if tbs_error != ok { ret (zero, zero, .Unsupported, zero, tbs_error) }
    let (algorithm, algorithm_error) = expect(&parts, 16u32, true)
    if algorithm_error != ok { ret (zero, zero, .Unsupported, zero, algorithm_error) }
    let (algorithm_kind, kind_error) = signature_algorithm(algorithm)
    if kind_error != ok { ret (zero, zero, .Unsupported, zero, kind_error) }
    let (signature, signature_error) = expect(&parts, 3u32, false)
    if signature_error != ok { ret (zero, zero, .Unsupported, zero, signature_error) }
    if signature.content.len < 2usize || signature.content[0] != 0u8 { ret (zero, zero, .Unsupported, zero, InvalidCertificate) }
    if algorithm_kind == .Ed25519 && signature.content.len != 65usize { ret (zero, zero, .Unsupported, zero, InvalidCertificate) }
    ret (tbs.encoded, signature.content[1usize..], algorithm_kind, algorithm.encoded, ok)
}

fn parse(a: *mem.Arena, der: []const u8) -> (Certificate, err) {
    var certificate: Certificate = zero
    certificate.der = der
    let (tbs_bytes, signature, outer_signature_algorithm, outer_algorithm, parts_error) = signed_parts(der)
    if parts_error != ok { ret (zero, parts_error) }
    var top = asn1.reader(tbs_bytes, DEPTH)
    let (tbs, tbs_error) = expect(&top, 16u32, true)
    if tbs_error != ok { ret (zero, tbs_error) }
    let (fields0, fields_error) = inside(tbs)
    if fields_error != ok { ret (zero, fields_error) }
    var fields = fields0
    // version [0] EXPLICIT, present for v2 and v3.
    let (first_item, item_error) = next(&fields)
    if item_error != ok { ret (zero, item_error) }
    var item = first_item
    var version = 0i64
    if item.tag.class == .Context && item.tag.number == 0u32 {
        let (version_inner0, version_error) = inside(item)
        if version_error != ok { ret (zero, version_error) }
        var version_inner = version_inner0
        let (version_value, value_error) = expect(&version_inner, 2u32, false)
        if value_error != ok { ret (zero, value_error) }
        if version_value.content.len != 1usize { ret (zero, InvalidCertificate) }
        version = i64(version_value.content[0])
        let (serial, serial_error) = next(&fields)
        if serial_error != ok { ret (zero, serial_error) }
        item = serial
    }
    if item.tag.number != 2u32 { ret (zero, InvalidCertificate) }
    let (inner_algorithm, inner_algorithm_error) = expect(&fields, 16u32, true)
    if inner_algorithm_error != ok { ret (zero, inner_algorithm_error) }
    let (inner_signature_algorithm, inner_signature_error) = signature_algorithm(inner_algorithm)
    if inner_signature_error != ok || inner_signature_algorithm != outer_signature_algorithm || !same_der(inner_algorithm.encoded, outer_algorithm) { ret (zero, InvalidCertificate) }
    let (issuer, issuer_error) = expect(&fields, 16u32, true)
    if issuer_error != ok { ret (zero, issuer_error) }
    let (issuer_text, issuer_render_error) = render_name(a, issuer)
    if issuer_render_error != ok { ret (zero, issuer_render_error) }
    certificate.issuer = issuer_text
    let (validity, validity_error) = expect(&fields, 16u32, true)
    if validity_error != ok { ret (zero, validity_error) }
    let (window0, window_error) = inside(validity)
    if window_error != ok { ret (zero, window_error) }
    var window = window0
    let (before, before_error) = next(&window)
    if before_error != ok { ret (zero, before_error) }
    let (after, after_error) = next(&window)
    if after_error != ok { ret (zero, after_error) }
    let (not_before, not_before_error) = parse_time(before)
    if not_before_error != ok { ret (zero, not_before_error) }
    let (not_after, not_after_error) = parse_time(after)
    if not_after_error != ok { ret (zero, not_after_error) }
    certificate.not_before = not_before
    certificate.not_after = not_after
    let (subject, subject_error) = expect(&fields, 16u32, true)
    if subject_error != ok { ret (zero, subject_error) }
    let (subject_text, subject_render_error) = render_name(a, subject)
    if subject_render_error != ok { ret (zero, subject_render_error) }
    certificate.subject = subject_text
    // subjectPublicKeyInfo: Ed25519 or an uncompressed named P-256 point.
    let (spki, spki_error) = expect(&fields, 16u32, true)
    if spki_error != ok { ret (zero, spki_error) }
    let (spki_inner0, spki_inner_error) = inside(spki)
    if spki_inner_error != ok { ret (zero, spki_inner_error) }
    var spki_inner = spki_inner0
    let (key_algorithm, key_algorithm_error) = expect(&spki_inner, 16u32, true)
    if key_algorithm_error != ok { ret (zero, key_algorithm_error) }
    let (key_algorithm_inner0, key_inner_error) = inside(key_algorithm)
    if key_inner_error != ok { ret (zero, key_inner_error) }
    var key_algorithm_inner = key_algorithm_inner0
    let (key_oid, key_oid_error) = expect(&key_algorithm_inner, 6u32, false)
    if key_oid_error != ok { ret (zero, key_oid_error) }
    let ed25519: [3]u8 = [3]u8{ 43, 101, 112 }
    let ec_public: [7]u8 = [7]u8{ 42, 134, 72, 206, 61, 2, 1 }
    let p256_curve: [8]u8 = [8]u8{ 42, 134, 72, 206, 61, 3, 1, 7 }
    var key_kind = 0u8
    if oid_equal(key_oid.content, ed25519[0..]) {
        let (_, has_parameter, parameter_error) = asn1.reader_next_err(&key_algorithm_inner)
        if parameter_error != ok || has_parameter { ret (zero, InvalidCertificate) }
        key_kind = 1u8
    } else if oid_equal(key_oid.content, ec_public[0..]) {
        let (curve, curve_error) = expect(&key_algorithm_inner, 6u32, false)
        if curve_error != ok { ret (zero, curve_error) }
        let (_, has_parameter, parameter_error) = asn1.reader_next_err(&key_algorithm_inner)
        if parameter_error != ok || has_parameter { ret (zero, InvalidCertificate) }
        if oid_equal(curve.content, p256_curve[0..]) { key_kind = 2u8 }
    }
    let (key_bits, key_bits_error) = expect(&spki_inner, 3u32, false)
    if key_bits_error != ok { ret (zero, key_bits_error) }
    let (_, has_spki_tail, spki_tail_error) = asn1.reader_next_err(&spki_inner)
    if spki_tail_error != ok || has_spki_tail || key_bits.content.len < 2usize || key_bits.content[0] != 0u8 { ret (zero, InvalidCertificate) }
    if key_kind == 1u8 {
        if key_bits.content.len != 33usize { ret (zero, InvalidCertificate) }
        var public: sign.Ed25519PublicKey = zero
        mem.copy[u8](public.bytes[0..], key_bits.content[1usize..])
        certificate.public_key = PublicKey{ Ed25519: public }
    } else if key_kind == 2u8 {
        if key_bits.content.len != 66usize || key_bits.content[1] != 4u8 { ret (zero, InvalidCertificate) }
        var public: sign.P256PublicKey = zero
        mem.copy[u8](public.bytes[0..], key_bits.content[1usize..])
        certificate.public_key = PublicKey{ P256: public }
    } else {
        certificate.public_key = PublicKey{ Unsupported: key_bits.content[1usize..] }
    }
    // Extensions [3] EXPLICIT, v3 only. An unhandled critical extension is kept
    // on the certificate so an unused supplied suffix can parse but no verified
    // chain can pass through it.
    var names: []const str = zero
    while true {
        let (rest, has_rest, rest_error) = asn1.reader_next_err(&fields)
        if rest_error != ok { ret (zero, InvalidCertificate) }
        if !has_rest { break }
        if rest.tag.class == .Context && rest.tag.number == 3u32 && rest.tag.constructed {
            if version != 2i64 { ret (zero, InvalidCertificate) }
            let (wrapper0, wrapper_error) = inside(rest)
            if wrapper_error != ok { ret (zero, wrapper_error) }
            var wrapper = wrapper0
            let (list, list_error) = expect(&wrapper, 16u32, true)
            if list_error != ok { ret (zero, list_error) }
            let (extensions0, extensions_error) = inside(list)
            if extensions_error != ok { ret (zero, extensions_error) }
            var extensions = extensions0
            while true {
                let (extension, has_extension, extension_error) = asn1.reader_next_err(&extensions)
                if extension_error != ok { ret (zero, InvalidCertificate) }
                if !has_extension { break }
                let (parts0, extension_parts_error) = inside(extension)
                if extension_parts_error != ok { ret (zero, extension_parts_error) }
                var parts = parts0
                let (extension_oid, extension_oid_error) = expect(&parts, 6u32, false)
                if extension_oid_error != ok { ret (zero, extension_oid_error) }
                let (first_payload, payload_error) = next(&parts)
                if payload_error != ok { ret (zero, payload_error) }
                var payload = first_payload
                var critical = false
                if payload.tag.class == .Universal && payload.tag.number == 1u32 && !payload.tag.constructed {
                    if payload.content.len != 1usize { ret (zero, InvalidCertificate) }
                    critical = payload.content[0] != 0u8
                    let (after_critical, critical_error) = next(&parts)
                    if critical_error != ok { ret (zero, critical_error) }
                    payload = after_critical
                }
                if payload.tag.class != .Universal || payload.tag.number != 4u32 || payload.tag.constructed { ret (zero, InvalidCertificate) }
                let (_, has_extension_tail, extension_tail_error) = asn1.reader_next_err(&parts)
                if extension_tail_error != ok || has_extension_tail { ret (zero, InvalidCertificate) }
                let san: [3]u8 = [3]u8{ 85, 29, 17 }
                let basic: [3]u8 = [3]u8{ 85, 29, 19 }
                let key_usage: [3]u8 = [3]u8{ 85, 29, 15 }
                let extended_usage: [3]u8 = [3]u8{ 85, 29, 37 }
                var handled = false
                if oid_equal(extension_oid.content, san[0..]) {
                    handled = true
                    let (parsed, san_error) = parse_dns_names(a, payload.content)
                    if san_error != ok { ret (zero, san_error) }
                    names = parsed
                }
                if oid_equal(extension_oid.content, basic[0..]) {
                    handled = true
                    var constraints = asn1.reader(payload.content, DEPTH)
                    let (sequence, sequence_error) = expect(&constraints, 16u32, true)
                    if sequence_error != ok { ret (zero, sequence_error) }
                    let (flags0, flags_error) = inside(sequence)
                    if flags_error != ok { ret (zero, flags_error) }
                    var flags = flags0
                    let (first, has_first, first_error) = asn1.reader_next_err(&flags)
                    if first_error != ok { ret (zero, InvalidCertificate) }
                    var constraint = first
                    var has_constraint = has_first
                    if has_constraint && constraint.tag.class == .Universal && constraint.tag.number == 1u32 && !constraint.tag.constructed {
                        if constraint.content.len != 1usize { ret (zero, InvalidCertificate) }
                        certificate.is_ca = constraint.content[0] != 0u8
                        let (after_ca, has_after_ca, after_ca_error) = asn1.reader_next_err(&flags)
                        if after_ca_error != ok { ret (zero, InvalidCertificate) }
                        constraint = after_ca
                        has_constraint = has_after_ca
                    }
                    if has_constraint {
                        if constraint.tag.class != .Universal || constraint.tag.number != 2u32 || constraint.tag.constructed { ret (zero, InvalidCertificate) }
                        let (distance, distance_error) = asn1.integer_of(constraint)
                        if distance_error != ok || distance < 0i64 || distance > 65535i64 || !certificate.is_ca { ret (zero, InvalidCertificate) }
                        certificate.has_path_len = true
                        certificate.path_len = u16(distance)
                        let (_, has_constraint_tail, constraint_tail_error) = asn1.reader_next_err(&flags)
                        if constraint_tail_error != ok || has_constraint_tail { ret (zero, InvalidCertificate) }
                    }
                }
                if oid_equal(extension_oid.content, key_usage[0..]) {
                    handled = true
                    var encoded_bits = asn1.reader(payload.content, DEPTH)
                    let (bits, bits_error) = expect(&encoded_bits, 3u32, false)
                    if bits_error != ok || bits.content.len == 0usize || bits.content[0] > 7u8 { ret (zero, InvalidCertificate) }
                    let (_, has_bits_tail, bits_tail_error) = asn1.reader_next_err(&encoded_bits)
                    if bits_tail_error != ok || has_bits_tail { ret (zero, InvalidCertificate) }
                    certificate.has_key_usage = true
                    certificate.key_cert_sign = bits.content.len > 1usize && (bits.content[1] & 4u8) != 0u8
                }
                if oid_equal(extension_oid.content, extended_usage[0..]) { handled = true }
                if critical && !handled { certificate.unhandled_critical = true }
            }
        }
    }
    certificate.dns_names = names
    ret (certificate, ok)
}

// The dNSName entries ([2] IMPLICIT IA5String) of a GeneralNames sequence.
fn parse_dns_names(a: *mem.Arena, content: []const u8) -> ([]const str, err) {
    var top = asn1.reader(content, DEPTH)
    let (sequence, sequence_error) = expect(&top, 16u32, true)
    if sequence_error != ok { ret (zero, sequence_error) }
    var count = 0usize
    let (probe0, probe_error) = inside(sequence)
    if probe_error != ok { ret (zero, probe_error) }
    var probe = probe0
    while true {
        let (general, present, general_error) = asn1.reader_next_err(&probe)
        if general_error != ok { ret (zero, InvalidCertificate) }
        if !present { break }
        if general.tag.class == .Context && general.tag.number == 2u32 { count += 1usize }
    }
    let (names, names_error) = mem.alloc[str](a, count)
    if names_error != ok { ret (zero, names_error) }
    let (walk0, walk_error) = inside(sequence)
    if walk_error != ok { ret (zero, walk_error) }
    var walk = walk0
    var index = 0usize
    while index < count {
        let (general, present, general_error) = asn1.reader_next_err(&walk)
        if general_error != ok || !present { ret (zero, InvalidCertificate) }
        if general.tag.class == .Context && general.tag.number == 2u32 {
            names[index] = general.content
            index += 1usize
        }
    }
    ret (names[0..], ok)
}

fn parse_pem(a: *mem.Arena, source: str) -> ([]const Certificate, err) {
    var count = 0usize
    var rest = source
    while true {
        let (block, after, decode_error) = pem.decode(a, rest, 1048576usize)
        if decode_error != ok { break }
        if str.eq(block.label, "CERTIFICATE") { count += 1usize }
        rest = after
    }
    let (certificates, certificates_error) = mem.alloc[Certificate](a, count)
    if certificates_error != ok { ret (zero, certificates_error) }
    rest = source
    var index = 0usize
    while index < count {
        let (block, after, decode_error) = pem.decode(a, rest, 1048576usize)
        if decode_error != ok { ret (zero, InvalidCertificate) }
        rest = after
        if !str.eq(block.label, "CERTIFICATE") { continue }
        let (certificate, parse_error) = parse(a, block.bytes)
        if parse_error != ok { ret (zero, parse_error) }
        certificates[index] = certificate
        index += 1usize
    }
    ret (certificates[0..], ok)
}

fn pool(a: *mem.Arena, certificates: []const Certificate) -> Pool {
    ret Pool { certificates: certificates }
}

fn verify_signature(certificate: Certificate, issuer: Certificate) -> err {
    let (tbs, signature_bytes, algorithm, outer_algorithm, parts_error) = signed_parts(certificate.der)
    if parts_error != ok { ret parts_error }
    if algorithm == .Ed25519 {
        var signature: sign.Ed25519Signature = zero
        mem.copy[u8](signature.bytes[0..], signature_bytes)
        switch issuer.public_key {
        case .Ed25519 as key:
            if sign.ed25519_verify(key, tbs, signature) { ret ok }
        default:
            ret InvalidCertificate
        }
        ret InvalidCertificate
    }
    if algorithm == .EcdsaSha256 {
        switch issuer.public_key {
        case .P256 as key:
            if sign.p256_verify(key, tbs, signature_bytes) { ret ok }
        default:
            ret InvalidCertificate
        }
    }
    ret InvalidCertificate
}

fn same_der(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// A DNS name against a certificate name, case-insensitively, with a leftmost `*`
// label standing for exactly one label.
fn dns_match(pattern: str, name: str) -> bool {
    if pattern.len > 2usize && pattern[0] == 42u8 && pattern[1] == 46u8 {
        let (dot, has_dot) = str.find(name, ".")
        if !has_dot || dot == 0usize { ret false }
        ret str.compare_ascii_fold(pattern[2usize..], name[dot + 1usize..]) == 0
    }
    ret str.compare_ascii_fold(pattern, name) == 0
}

fn usage_oid(usage: KeyUsage) -> [8]u8 {
    var oid: [8]u8 = [8]u8{ 43, 6, 1, 5, 5, 7, 3, 1 }
    if usage == .ClientAuth { oid[7] = 2u8 }
    if usage == .CodeSigning { oid[7] = 3u8 }
    if usage == .EmailProtection { oid[7] = 4u8 }
    ret oid
}

// True when the leaf carries an extendedKeyUsage that excludes `usage`.
fn usage_excluded(certificate: Certificate, usage: KeyUsage) -> bool {
    if usage == .Any { ret false }
    let wanted = usage_oid(usage)
    let (tbs_bytes, signature, algorithm, outer_algorithm, parts_error) = signed_parts(certificate.der)
    if parts_error != ok { ret true }
    var top = asn1.reader(tbs_bytes, DEPTH)
    let (tbs, tbs_error) = expect(&top, 16u32, true)
    if tbs_error != ok { ret true }
    let (fields0, fields_error) = inside(tbs)
    if fields_error != ok { ret true }
    var fields = fields0
    while true {
        let (item, present, item_error) = asn1.reader_next_err(&fields)
        if item_error != ok || !present { ret false }
        if item.tag.class != .Context || item.tag.number != 3u32 { continue }
        let (wrapper0, wrapper_error) = inside(item)
        if wrapper_error != ok { ret true }
        var wrapper = wrapper0
        let (list, list_error) = expect(&wrapper, 16u32, true)
        if list_error != ok { ret true }
        let (extensions0, extensions_error) = inside(list)
        if extensions_error != ok { ret true }
        var extensions = extensions0
        while true {
            let (extension, has_extension, extension_error) = asn1.reader_next_err(&extensions)
            if extension_error != ok { ret true }
            if !has_extension { ret false }
            let (parts0, parts_inner_error) = inside(extension)
            if parts_inner_error != ok { ret true }
            var parts = parts0
            let (oid, oid_error) = expect(&parts, 6u32, false)
            if oid_error != ok { ret true }
            let eku: [3]u8 = [3]u8{ 85, 29, 37 }
            if !oid_equal(oid.content, eku[0..]) { continue }
            let (first_payload, payload_error) = next(&parts)
            if payload_error != ok { ret true }
            var payload = first_payload
            if payload.tag.number == 1u32 {
                let (after_critical, critical_error) = next(&parts)
                if critical_error != ok { ret true }
                payload = after_critical
            }
            var purposes = asn1.reader(payload.content, DEPTH)
            let (sequence, sequence_error) = expect(&purposes, 16u32, true)
            if sequence_error != ok { ret true }
            let (allowed0, allowed_error) = inside(sequence)
            if allowed_error != ok { ret true }
            var allowed = allowed0
            while true {
                let (purpose, has_purpose, purpose_error) = asn1.reader_next_err(&allowed)
                if purpose_error != ok { ret true }
                if !has_purpose { ret true }
                if oid_equal(purpose.content, wanted[0..]) { ret false }
            }
        }
    }
}

fn find_issuer(pool_of: Pool, subject: str) -> (Certificate, bool) {
    var i = 0usize
    while i < pool_of.certificates.len {
        if str.eq(pool_of.certificates[i].subject, subject) { ret (pool_of.certificates[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn in_window(certificate: Certificate, now: time.Instant) -> bool {
    ret now.nanos >= certificate.not_before.nanos && now.nanos <= certificate.not_after.nanos
}

fn verify(a: *mem.Arena, leaf: Certificate, options: VerifyOptions) -> (Chain, err) {
    var limit = usize(options.max_depth)
    if limit == 0usize { limit = 8usize }
    let (links, links_error) = mem.alloc[Certificate](a, limit + 1usize)
    if links_error != ok { ret (zero, links_error) }
    if leaf.unhandled_critical { ret (zero, InvalidCertificate) }
    if !in_window(leaf, options.now) { ret (zero, Expired) }
    if options.dns_name.len > 0usize {
        var matched = false
        var i = 0usize
        while i < leaf.dns_names.len {
            if dns_match(leaf.dns_names[i], options.dns_name) { matched = true }
            i += 1usize
        }
        if !matched { ret (zero, NameMismatch) }
    }
    if usage_excluded(leaf, options.usage) { ret (zero, InvalidUsage) }
    links[0] = leaf
    var count = 1usize
    var current = leaf
    while true {
        // A root by name closes the chain; an intermediate extends it.
        let (root, has_root) = find_issuer(options.roots, current.issuer)
        if has_root {
            if !in_window(root, options.now) { ret (zero, Expired) }
            if verify_signature(current, root) != ok { ret (zero, UnknownAuthority) }
            if !same_der(root.der, current.der) {
                if count > limit { ret (zero, TooDeep) }
                links[count] = root
                count += 1usize
            }
            break
        }
        let (intermediate, has_intermediate) = find_issuer(options.intermediates, current.issuer)
        if !has_intermediate || same_der(intermediate.der, current.der) { ret (zero, UnknownAuthority) }
        if intermediate.unhandled_critical { ret (zero, InvalidCertificate) }
        if !intermediate.is_ca { ret (zero, UnknownAuthority) }
        if intermediate.has_key_usage && !intermediate.key_cert_sign { ret (zero, UnknownAuthority) }
        if intermediate.has_path_len && count - 1usize > usize(intermediate.path_len) { ret (zero, UnknownAuthority) }
        if !in_window(intermediate, options.now) { ret (zero, Expired) }
        if verify_signature(current, intermediate) != ok { ret (zero, UnknownAuthority) }
        if count >= limit { ret (zero, TooDeep) }
        links[count] = intermediate
        count += 1usize
        current = intermediate
    }
    ret (Chain { certificates: links[..count] }, ok)
}


// --- Certificate Transparency (#1431), RFC 6962 sections 3.2 and 3.3: a
// v1 SignedCertificateTimestamp is `version(1) log_id(32) timestamp(8)
// extensions(2 + n) hash(1) signature_algorithm(1) signature(2 + n)`; the
// log signs `version(1) signature_type(1 = certificate_timestamp)
// timestamp(8) entry_type(2) entry extensions(2 + n)`, where an `x509_entry`
// (0) is the certificate DER under a 3-byte length and a `precert_entry` (1)
// is the issuer key hash (32) then the TBS under a 3-byte length. Only the
// signature over one entry is checked here; the log's Merkle inclusion
// proofs are `e.crypto.merkle`'s.

type Sct = struct { version: u8, log_id: [32]u8, timestamp: u64, extensions: []const u8, hash_algorithm: u8, signature_algorithm: u8, signature: []const u8 }
error InvalidSct
error BadSctSignature

fn be16(bytes: []const u8, at: usize) -> usize { ret (usize(bytes[at]) << 8u32) | usize(bytes[at + 1usize]) }

// Parse the binary SCT (the content of one `SerializedSCT` in a list).
fn ct_parse(bytes: []const u8) -> (Sct, err) {
    if bytes.len < 47usize || bytes[0usize] != 0u8 { ret (zero, InvalidSct) }
    var s: Sct = zero
    s.version = 0u8
    mem.copy[u8](s.log_id[0..], bytes[1usize..33usize])
    var at = 33usize
    var timestamp = 0u64
    var i = 0usize
    while i < 8usize {
        timestamp = (timestamp << 8u32) | u64(bytes[at + i])
        i += 1usize
    }
    s.timestamp = timestamp
    at += 8usize
    let extension_len = be16(bytes, at)
    at += 2usize
    if at + extension_len + 4usize > bytes.len { ret (zero, InvalidSct) }
    s.extensions = bytes[at..at + extension_len]
    at += extension_len
    s.hash_algorithm = bytes[at]
    s.signature_algorithm = bytes[at + 1usize]
    let signature_len = be16(bytes, at + 2usize)
    at += 4usize
    if at + signature_len != bytes.len { ret (zero, InvalidSct) }
    s.signature = bytes[at..]
    ret (s, ok)
}

// The bytes the log signed, into `dst`: `entry` is the certificate DER for
// an X.509 entry, or the TBS certificate when `issuer_key_hash` (32 bytes)
// is given for a precert entry. Answers the length used.
fn ct_signed_data(s: *const Sct, entry: []const u8, issuer_key_hash: []const u8, dst: []u8) -> (usize, err) {
    let precert = issuer_key_hash.len == 32usize
    if !precert && issuer_key_hash.len != 0usize { ret (0usize, InvalidSct) }
    if entry.len > 16777215usize { ret (0usize, InvalidSct) }
    var need = 12usize + 3usize + entry.len + 2usize + s.extensions.len
    if precert { need += 32usize }
    if dst.len < need { ret (0usize, InvalidSct) }
    dst[0usize] = s.version
    dst[1usize] = 0u8
    var i = 0usize
    while i < 8usize {
        dst[2usize + i] = u8((s.timestamp >> u32(56usize - 8usize * i)) & 255u64)
        i += 1usize
    }
    dst[10usize] = 0u8
    dst[11usize] = 0u8
    var at = 12usize
    if precert {
        dst[11usize] = 1u8
        mem.copy[u8](dst[at..at + 32usize], issuer_key_hash)
        at += 32usize
    }
    dst[at] = u8((entry.len >> 16u32) & 255usize)
    dst[at + 1usize] = u8((entry.len >> 8u32) & 255usize)
    dst[at + 2usize] = u8(entry.len & 255usize)
    at += 3usize
    mem.copy[u8](dst[at..at + entry.len], entry)
    at += entry.len
    dst[at] = u8((s.extensions.len >> 8u32) & 255usize)
    dst[at + 1usize] = u8(s.extensions.len & 255usize)
    at += 2usize
    mem.copy[u8](dst[at..at + s.extensions.len], s.extensions)
    at += s.extensions.len
    ret (at, ok)
}

// Verify a serialised SCT for `entry` against the log's key: ECDSA P-256
// with SHA-256 (hash 4, signature 3) or Ed25519 (signature 7). `scratch`
// holds the signed data (`entry.len + 49` bytes, 32 more for a precert).
// Answers the parsed SCT; a mismatch is `BadSctSignature`.
fn ct_verify(sct: []const u8, log_key: PublicKey, entry: []const u8, issuer_key_hash: []const u8, scratch: []u8) -> (Sct, err) {
    let (s, parse_error) = ct_parse(sct)
    if parse_error != ok { ret (zero, parse_error) }
    let (signed_len, data_error) = ct_signed_data(&s, entry, issuer_key_hash, scratch)
    if data_error != ok { ret (zero, data_error) }
    let signed = scratch[..signed_len]
    switch log_key {
    case .P256 as key:
        if s.signature_algorithm != 3u8 || s.hash_algorithm != 4u8 { ret (s, InvalidSct) }
        if sign.p256_verify(key, signed, s.signature) { ret (s, ok) }
    case .Ed25519 as key:
        if s.signature_algorithm != 7u8 || s.signature.len != 64usize { ret (s, InvalidSct) }
        var signature: sign.Ed25519Signature = zero
        mem.copy[u8](signature.bytes[0..], s.signature)
        if sign.ed25519_verify(key, signed, signature) { ret (s, ok) }
    default:
        ret (s, InvalidSct)
    }
    ret (s, BadSctSignature)
}
