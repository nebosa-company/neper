// CMS / PKCS #7 SignedData (RFC 5652) for S/MIME: read and verify what OpenSSL, Outlook and
// `cryptography` produce, and write an Ed25519 signature (RFC 8419) a standard verifier accepts.
//
// Reading. `parse` takes a DER ContentInfo holding SignedData, with the content attached or
// detached, the embedded certificates and the SignerInfos. `verify_signer` checks one signer
// end to end: the content digest against the signed `messageDigest` attribute (SHA-256/384/512),
// the `contentType` attribute against the encapsulated type, then the signature over the DER
// of the signed attributes (tag rewritten from `[0]` to SET, per RFC 5652 5.4) or over the
// content directly when there are none. Supported signatures, by the signer's embedded
// certificate key: ECDSA P-256/P-384, RSA PKCS#1 v1.5, Ed25519. The signer is found by
// IssuerAndSerialNumber (the SubjectKeyIdentifier form is `Unsupported`). Trust is the caller's:
// `signer_certificate` hands back the certificate for `e.crypto.x509.verify` against roots.
//
// Writing. `sign_ed25519` produces a SignedData with signed attributes (content type, signing
// time, message digest), SHA-512 and the signer's certificate embedded, detached for an S/MIME
// `multipart/signed` body or attached. RSA and ECDSA signing are not here: `e.crypto.sign` has
// no PKCS#1 v1.5 signer and its P-256 signer is `Unsupported`.
//
// Only definite-length DER is read (what `openssl cms -outform DER` and S/MIME produce without
// `-stream`); BER indefinite lengths are `Invalid`. CRLs, attribute certificates, countersignatures,
// unsigned attributes and EnvelopedData are not interpreted.

use e.mem
use e.crypto.hash as hash
use e.crypto.sign as sign
use e.crypto.x509 as x509
use e.fmt.asn1 as asn1

type Signer = struct { version: u8, issuer: []const u8, serial: []const u8, digest_oid: []const u8, has_attributes: bool, attributes: []const u8, signature_oid: []const u8, signature: []const u8 }
type SignedData = struct { content_type: []const u8, has_content: bool, content: []const u8, certificates: []const x509.Certificate, signers: []const Signer }
error Invalid
error Unsupported
error BadDigest
error BadSignature
error NoCertificate
error TooSmall

const DEPTH: u16 = 16u16

// ---- OIDs, as their content bytes ----

fn oid_signed_data() -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 7u8, 2u8 } }
fn oid_data() -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 7u8, 1u8 } }
fn oid_content_type() -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 9u8, 3u8 } }
fn oid_message_digest() -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 9u8, 4u8 } }
fn oid_signing_time() -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 9u8, 5u8 } }
fn oid_sha256() -> [9]u8 { ret [9]u8{ 96u8, 134u8, 72u8, 1u8, 101u8, 3u8, 4u8, 2u8, 1u8 } }
fn oid_sha384() -> [9]u8 { ret [9]u8{ 96u8, 134u8, 72u8, 1u8, 101u8, 3u8, 4u8, 2u8, 2u8 } }
fn oid_sha512() -> [9]u8 { ret [9]u8{ 96u8, 134u8, 72u8, 1u8, 101u8, 3u8, 4u8, 2u8, 3u8 } }
fn oid_ed25519() -> [3]u8 { ret [3]u8{ 43u8, 101u8, 112u8 } }
fn oid_rsa_encryption() -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 1u8, 1u8 } }
fn oid_ecdsa_sha256() -> [8]u8 { ret [8]u8{ 42u8, 134u8, 72u8, 206u8, 61u8, 4u8, 3u8, 2u8 } }
fn oid_ecdsa_sha384() -> [8]u8 { ret [8]u8{ 42u8, 134u8, 72u8, 206u8, 61u8, 4u8, 3u8, 3u8 } }
fn oid_ecdsa_sha512() -> [8]u8 { ret [8]u8{ 42u8, 134u8, 72u8, 206u8, 61u8, 4u8, 3u8, 4u8 } }

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// sha256WithRSAEncryption .. sha512WithRSAEncryption: 1.2.840.113549.1.1.11 .. 13.
fn rsa_with_hash(oid: []const u8) -> u16 {
    if oid.len != 9usize { ret 0u16 }
    let base = oid_rsa_encryption()
    var i = 0usize
    while i < 8usize {
        if oid[i] != base[i] { ret 0u16 }
        i += 1usize
    }
    if oid[8] == 11u8 { ret 256u16 }
    if oid[8] == 12u8 { ret 384u16 }
    if oid[8] == 13u8 { ret 512u16 }
    ret 0u16
}

fn hash_bits(oid: []const u8) -> u16 {
    let s256 = oid_sha256()
    let s384 = oid_sha384()
    let s512 = oid_sha512()
    if same(oid, s256[0usize..9usize]) { ret 256u16 }
    if same(oid, s384[0usize..9usize]) { ret 384u16 }
    if same(oid, s512[0usize..9usize]) { ret 512u16 }
    ret 0u16
}

// ---- reading ----

fn next(r: *asn1.Reader) -> (asn1.Value, err) {
    let (value, present, next_error) = asn1.reader_next_err(r)
    if next_error != ok || !present { ret (zero, Invalid) }
    ret (value, ok)
}

fn universal(r: *asn1.Reader, number: u32, constructed: bool) -> (asn1.Value, err) {
    let (value, e) = next(r)
    if e != ok { ret (zero, e) }
    if value.tag.class != .Universal || value.tag.number != number || value.tag.constructed != constructed { ret (zero, Invalid) }
    ret (value, ok)
}

fn children(v: asn1.Value) -> (asn1.Reader, err) {
    let (r, e) = asn1.children(v, DEPTH)
    if e != ok { ret (zero, Invalid) }
    ret (r, ok)
}

// An OID value's content bytes.
fn oid_of(r: *asn1.Reader) -> ([]const u8, err) {
    let (v, e) = universal(r, 6u32, false)
    if e != ok { ret (zero, e) }
    ret (v.content, ok)
}

// An AlgorithmIdentifier's OID content (parameters, if any, are skipped).
fn algorithm_oid(r: *asn1.Reader) -> ([]const u8, err) {
    let (seq, e) = universal(r, 16u32, true)
    if e != ok { ret (zero, e) }
    let (kids, kids_error) = children(seq)
    if kids_error != ok { ret (zero, kids_error) }
    var k = kids
    let (oid, oid_error) = oid_of(&k)
    ret (oid, oid_error)
}

// (issuer Name encoding, serial INTEGER content) of a certificate's TBS.
fn issuer_and_serial(der: []const u8) -> ([]const u8, []const u8, err) {
    var top = asn1.reader(der, DEPTH)
    let (cert, cert_error) = universal(&top, 16u32, true)
    if cert_error != ok { ret (zero, zero, cert_error) }
    let (parts, parts_error) = children(cert)
    if parts_error != ok { ret (zero, zero, parts_error) }
    var p = parts
    let (tbs, tbs_error) = universal(&p, 16u32, true)
    if tbs_error != ok { ret (zero, zero, tbs_error) }
    let (fields, fields_error) = children(tbs)
    if fields_error != ok { ret (zero, zero, fields_error) }
    var f = fields
    let (first_item, item_error) = next(&f)
    if item_error != ok { ret (zero, zero, item_error) }
    var item = first_item
    if item.tag.class == .Context && item.tag.number == 0u32 {
        let (serial0, serial0_error) = next(&f)
        if serial0_error != ok { ret (zero, zero, serial0_error) }
        item = serial0
    }
    if item.tag.number != 2u32 { ret (zero, zero, Invalid) }
    let serial = item.content
    let (alg, alg_error) = universal(&f, 16u32, true)
    if alg_error != ok { ret (zero, zero, alg_error) }
    let (issuer, issuer_error) = universal(&f, 16u32, true)
    if issuer_error != ok { ret (zero, zero, issuer_error) }
    ret (issuer.encoded, serial, ok)
}

fn parse_signer(v: asn1.Value) -> (Signer, err) {
    var s: Signer = zero
    let (kids, kids_error) = children(v)
    if kids_error != ok { ret (s, kids_error) }
    var r = kids
    let (version, version_error) = universal(&r, 2u32, false)
    if version_error != ok || version.content.len != 1usize { ret (s, Invalid) }
    s.version = version.content[0usize]
    let (sid, sid_error) = next(&r)
    if sid_error != ok { ret (s, sid_error) }
    if sid.tag.class != .Universal || sid.tag.number != 16u32 { ret (s, Unsupported) }
    let (sid_kids, sid_kids_error) = children(sid)
    if sid_kids_error != ok { ret (s, sid_kids_error) }
    var sr = sid_kids
    let (issuer, issuer_error) = universal(&sr, 16u32, true)
    if issuer_error != ok { ret (s, issuer_error) }
    let (serial, serial_error) = universal(&sr, 2u32, false)
    if serial_error != ok { ret (s, serial_error) }
    s.issuer = issuer.encoded
    s.serial = serial.content
    let (digest_oid, digest_error) = algorithm_oid(&r)
    if digest_error != ok { ret (s, digest_error) }
    s.digest_oid = digest_oid
    let (after_digest, after_error) = next(&r)
    if after_error != ok { ret (s, after_error) }
    var item = after_digest
    if item.tag.class == .Context && item.tag.number == 0u32 {
        s.has_attributes = true
        s.attributes = item.encoded
        let (n2, n2_error) = next(&r)
        if n2_error != ok { ret (s, n2_error) }
        item = n2
    }
    // item is the signatureAlgorithm SEQUENCE
    if item.tag.class != .Universal || item.tag.number != 16u32 { ret (s, Invalid) }
    let (alg_kids, alg_kids_error) = children(item)
    if alg_kids_error != ok { ret (s, alg_kids_error) }
    var ar = alg_kids
    let (sig_oid, sig_oid_error) = oid_of(&ar)
    if sig_oid_error != ok { ret (s, sig_oid_error) }
    s.signature_oid = sig_oid
    let (sig, sig_error) = universal(&r, 4u32, false)
    if sig_error != ok { ret (s, sig_error) }
    s.signature = sig.content
    ret (s, ok)
}

fn parse(a: *mem.Arena, der: []const u8) -> (SignedData, err) {
    var sd: SignedData = zero
    var top = asn1.reader(der, DEPTH)
    let (info, info_error) = universal(&top, 16u32, true)
    if info_error != ok { ret (sd, info_error) }
    let (info_kids, info_kids_error) = children(info)
    if info_kids_error != ok { ret (sd, info_kids_error) }
    var ir = info_kids
    let (type_oid, type_error) = oid_of(&ir)
    if type_error != ok { ret (sd, type_error) }
    let signed = oid_signed_data()
    if !same(type_oid, signed[0usize..9usize]) { ret (sd, Unsupported) }
    let (wrapper, wrapper_error) = next(&ir)
    if wrapper_error != ok { ret (sd, wrapper_error) }
    if wrapper.tag.class != .Context || wrapper.tag.number != 0u32 { ret (sd, Invalid) }
    let (wrap_kids, wrap_kids_error) = children(wrapper)
    if wrap_kids_error != ok { ret (sd, wrap_kids_error) }
    var wr = wrap_kids
    let (data, data_error) = universal(&wr, 16u32, true)
    if data_error != ok { ret (sd, data_error) }
    let (data_kids, data_kids_error) = children(data)
    if data_kids_error != ok { ret (sd, data_kids_error) }
    var dr = data_kids
    let (version, version_error) = universal(&dr, 2u32, false)
    if version_error != ok { ret (sd, version_error) }
    let (digests, digests_error) = universal(&dr, 17u32, true)
    if digests_error != ok { ret (sd, digests_error) }
    // EncapsulatedContentInfo
    let (encap, encap_error) = universal(&dr, 16u32, true)
    if encap_error != ok { ret (sd, encap_error) }
    let (encap_kids, encap_kids_error) = children(encap)
    if encap_kids_error != ok { ret (sd, encap_kids_error) }
    var er = encap_kids
    let (content_type, content_type_error) = oid_of(&er)
    if content_type_error != ok { ret (sd, content_type_error) }
    sd.content_type = content_type
    let (explicit_content, has_explicit, explicit_error) = asn1.reader_next_err(&er)
    if explicit_error != ok { ret (sd, Invalid) }
    if has_explicit {
        if explicit_content.tag.class != .Context || explicit_content.tag.number != 0u32 { ret (sd, Invalid) }
        let (octets_kids, octets_kids_error) = children(explicit_content)
        if octets_kids_error != ok { ret (sd, octets_kids_error) }
        var cr = octets_kids
        let (octets, octets_error) = universal(&cr, 4u32, false)
        if octets_error != ok { ret (sd, octets_error) }
        sd.has_content = true
        sd.content = octets.content
    }
    // certificates [0] IMPLICIT, crls [1] IMPLICIT, then signerInfos SET
    var signer_set: asn1.Value = zero
    var found_set = false
    var certs_value: asn1.Value = zero
    var has_certs = false
    while !found_set {
        let (v, v_error) = next(&dr)
        if v_error != ok { ret (sd, Invalid) }
        if v.tag.class == .Context && v.tag.number == 0u32 {
            certs_value = v
            has_certs = true
        } else if v.tag.class == .Context && v.tag.number == 1u32 {
            // revocation lists are not interpreted
        } else if v.tag.class == .Universal && v.tag.number == 17u32 {
            signer_set = v
            found_set = true
        } else {
            ret (sd, Invalid)
        }
    }
    var cert_count = 0usize
    if has_certs {
        let (cert_kids, cert_kids_error) = children(certs_value)
        if cert_kids_error != ok { ret (sd, cert_kids_error) }
        var scan = cert_kids
        while true {
            let (c, present, c_error) = asn1.reader_next_err(&scan)
            if c_error != ok { ret (sd, Invalid) }
            if !present { break }
            cert_count += 1usize
        }
        let (certs, certs_error) = mem.alloc[x509.Certificate](a, cert_count + 1usize)
        if certs_error != ok { ret (sd, certs_error) }
        let (cert_kids2, cert_kids2_error) = children(certs_value)
        if cert_kids2_error != ok { ret (sd, cert_kids2_error) }
        var again = cert_kids2
        var index = 0usize
        while index < cert_count {
            let (c, c_error) = next(&again)
            if c_error != ok { ret (sd, c_error) }
            let (parsed, parse_error) = x509.parse(a, c.encoded)
            if parse_error != ok { ret (sd, Invalid) }
            certs[index] = parsed
            index += 1usize
        }
        sd.certificates = certs[0usize..cert_count]
    }
    // signers
    let (signer_kids, signer_kids_error) = children(signer_set)
    if signer_kids_error != ok { ret (sd, signer_kids_error) }
    var count_reader = signer_kids
    var signer_count = 0usize
    while true {
        let (s, present, s_error) = asn1.reader_next_err(&count_reader)
        if s_error != ok { ret (sd, Invalid) }
        if !present { break }
        signer_count += 1usize
    }
    if signer_count == 0usize { ret (sd, Invalid) }
    let (signers, signers_error) = mem.alloc[Signer](a, signer_count)
    if signers_error != ok { ret (sd, signers_error) }
    let (signer_kids2, signer_kids2_error) = children(signer_set)
    if signer_kids2_error != ok { ret (sd, signer_kids2_error) }
    var sr = signer_kids2
    var si = 0usize
    while si < signer_count {
        let (sv, sv_error) = universal(&sr, 16u32, true)
        if sv_error != ok { ret (sd, sv_error) }
        let (s, s_error) = parse_signer(sv)
        if s_error != ok { ret (sd, s_error) }
        signers[si] = s
        si += 1usize
    }
    sd.signers = signers[0usize..signer_count]
    ret (sd, ok)
}

// The embedded certificate that issued-and-serial matches signer `index`.
fn find_certificate(sd: *const SignedData, index: usize) -> (x509.Certificate, bool) {
    if index >= sd.signers.len { ret (zero, false) }
    var i = 0usize
    while i < sd.certificates.len {
        let (issuer, serial, e) = issuer_and_serial(sd.certificates[i].der)
        if e == ok && same(issuer, sd.signers[index].issuer) && same(serial, sd.signers[index].serial) { ret (sd.certificates[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn signer_certificate(sd: *const SignedData, index: usize) -> (x509.Certificate, bool) {
    let (c, found) = find_certificate(sd, index)
    ret (c, found)
}

// Digest of `content` under `bits`; returns it in `out` (at least 64 bytes) and its length.
fn digest(bits: u16, content: []const u8, out: []u8) -> usize {
    if bits == 256u16 {
        let d = hash.sha256(content)
        mem.copy[u8](out, d[0usize..32usize])
        ret 32usize
    }
    if bits == 384u16 {
        let d = hash.sha384(content)
        mem.copy[u8](out, d[0usize..48usize])
        ret 48usize
    }
    let d = hash.sha512(content)
    mem.copy[u8](out, d[0usize..64usize])
    ret 64usize
}

// Walks the signed attributes (the encoded `[0]`) for `want`; returns its single value's bytes.
fn attribute_value(encoded: []const u8, want: []const u8) -> ([]const u8, bool) {
    var top = asn1.reader(encoded, DEPTH)
    let (outer, outer_error) = next(&top)
    if outer_error != ok { ret (zero, false) }
    let (kids, kids_error) = children(outer)
    if kids_error != ok { ret (zero, false) }
    var r = kids
    while true {
        let (attr, present, attr_error) = asn1.reader_next_err(&r)
        if attr_error != ok || !present { break }
        let (parts, parts_error) = children(attr)
        if parts_error != ok { ret (zero, false) }
        var pr = parts
        let (oid, oid_error) = oid_of(&pr)
        if oid_error != ok { ret (zero, false) }
        if same(oid, want) {
            let (values, values_error) = universal(&pr, 17u32, true)
            if values_error != ok { ret (zero, false) }
            let (vk, vk_error) = children(values)
            if vk_error != ok { ret (zero, false) }
            var vr = vk
            let (first, first_error) = next(&vr)
            if first_error != ok { ret (zero, false) }
            ret (first.content, true)
        }
    }
    ret (zero, false)
}

// Verifies signer `index` against `content` (the attached content when `detached` is empty
// and the SignedData has one). `a` is scratch for the RSA arithmetic.
fn verify_signer(a: *mem.Arena, sd: *const SignedData, index: usize, detached: []const u8) -> err {
    if index >= sd.signers.len { ret Invalid }
    let signer = sd.signers[index]
    var content = detached
    if detached.len == 0usize && sd.has_content { content = sd.content }
    if detached.len == 0usize && !sd.has_content { ret Invalid }
    let (cert, found) = find_certificate(sd, index)
    if !found { ret NoCertificate }
    let bits = hash_bits(signer.digest_oid)
    if bits == 0u16 { ret Unsupported }
    var message = content
    if signer.has_attributes {
        var computed: [64]u8 = zero
        let n = digest(bits, content, computed[0usize..64usize])
        let md_oid = oid_message_digest()
        let ct_oid = oid_content_type()
        let (md, has_md) = attribute_value(signer.attributes, md_oid[0usize..9usize])
        if !has_md || !same(md, computed[0usize..n]) { ret BadDigest }
        let (ct, has_ct) = attribute_value(signer.attributes, ct_oid[0usize..9usize])
        if has_ct && !same(ct, sd.content_type) { ret BadDigest }
        // RFC 5652 5.4: the signature covers the DER of the attributes with the SET OF tag
        let (copy, copy_error) = mem.alloc[u8](a, signer.attributes.len)
        if copy_error != ok { ret copy_error }
        mem.copy[u8](copy, signer.attributes)
        copy[0usize] = 49u8
        message = copy
    }
    let ed = oid_ed25519()
    let e256 = oid_ecdsa_sha256()
    let e384 = oid_ecdsa_sha384()
    let e512 = oid_ecdsa_sha512()
    let rsa = oid_rsa_encryption()
    if same(signer.signature_oid, ed[0usize..3usize]) {
        if signer.signature.len != 64usize { ret BadSignature }
        var sig: sign.Ed25519Signature = zero
        mem.copy[u8](sig.bytes[0usize..], signer.signature)
        switch cert.public_key {
        case .Ed25519 as key:
            if sign.ed25519_verify(key, message, sig) { ret ok }
        default:
            ret BadSignature
        }
        ret BadSignature
    }
    var rsa_bits = rsa_with_hash(signer.signature_oid)
    if same(signer.signature_oid, rsa[0usize..9usize]) { rsa_bits = bits }
    if rsa_bits != 0u16 {
        switch cert.public_key {
        case .Rsa as key:
            let mark = mem.mark(a)
            let valid = sign.rsa_pkcs1v15_verify_hash(a, key.modulus, key.exponent, message, signer.signature, rsa_bits)
            mem.reset(a, mark)
            if valid { ret ok }
        default:
            ret BadSignature
        }
        ret BadSignature
    }
    var ec_bits = 0u16
    if same(signer.signature_oid, e256[0usize..8usize]) { ec_bits = 256u16 }
    if same(signer.signature_oid, e384[0usize..8usize]) { ec_bits = 384u16 }
    if same(signer.signature_oid, e512[0usize..8usize]) { ec_bits = 512u16 }
    if ec_bits != 0u16 {
        switch cert.public_key {
        case .P256 as key:
            if sign.p256_verify_hash(key, message, signer.signature, ec_bits) { ret ok }
        case .P384 as key:
            if sign.p384_verify_hash(key, message, signer.signature, ec_bits) { ret ok }
        default:
            ret BadSignature
        }
        ret BadSignature
    }
    ret Unsupported
}

// Every signer must verify; at least one is required.
fn verify(a: *mem.Arena, sd: *const SignedData, detached: []const u8) -> err {
    if sd.signers.len == 0usize { ret Invalid }
    var i = 0usize
    while i < sd.signers.len {
        try verify_signer(a, sd, i, detached)
        i += 1usize
    }
    ret ok
}

// ---- writing ----

// A DER header for `total` content bytes at `at`; `TooSmall` when header and content do not fit.
fn begin(dst: []u8, at: usize, tag: u8, total: usize) -> (usize, err) {
    var header = 2usize
    if total >= 128usize {
        header = 3usize
        if total >= 256usize { header = 4usize }
        if total >= 65536usize { header = 5usize }
    }
    if at + header + total > dst.len { ret (at, TooSmall) }
    ret (asn1.put_header(dst, at, tag, total), ok)
}

fn append(dst: []u8, at: usize, bytes: []const u8) -> usize {
    var k = 0usize
    while k < bytes.len {
        dst[at + k] = bytes[k]
        k += 1usize
    }
    ret at + bytes.len
}

// TLV assembly: the tag, the DER length, then the parts back to back, into `dst` at `at`.
fn tlv1(dst: []u8, at: usize, tag: u8, p0: []const u8) -> (usize, err) {
    let (o, e) = begin(dst, at, tag, p0.len)
    if e != ok { ret (at, e) }
    ret (append(dst, o, p0), ok)
}

fn tlv2(dst: []u8, at: usize, tag: u8, p0: []const u8, p1: []const u8) -> (usize, err) {
    let (o, e) = begin(dst, at, tag, p0.len + p1.len)
    if e != ok { ret (at, e) }
    ret (append(dst, append(dst, o, p0), p1), ok)
}

fn tlv3(dst: []u8, at: usize, tag: u8, p0: []const u8, p1: []const u8, p2: []const u8) -> (usize, err) {
    let (o, e) = begin(dst, at, tag, p0.len + p1.len + p2.len)
    if e != ok { ret (at, e) }
    ret (append(dst, append(dst, append(dst, o, p0), p1), p2), ok)
}

fn tlv5(dst: []u8, at: usize, tag: u8, p0: []const u8, p1: []const u8, p2: []const u8, p3: []const u8, p4: []const u8) -> (usize, err) {
    let (o, e) = begin(dst, at, tag, p0.len + p1.len + p2.len + p3.len + p4.len)
    if e != ok { ret (at, e) }
    var n = append(dst, o, p0)
    n = append(dst, n, p1)
    n = append(dst, n, p2)
    n = append(dst, n, p3)
    n = append(dst, n, p4)
    ret (n, ok)
}

fn tlv6(dst: []u8, at: usize, tag: u8, p0: []const u8, p1: []const u8, p2: []const u8, p3: []const u8, p4: []const u8, p5: []const u8) -> (usize, err) {
    let (o, e) = begin(dst, at, tag, p0.len + p1.len + p2.len + p3.len + p4.len + p5.len)
    if e != ok { ret (at, e) }
    var n = append(dst, o, p0)
    n = append(dst, n, p1)
    n = append(dst, n, p2)
    n = append(dst, n, p3)
    n = append(dst, n, p4)
    n = append(dst, n, p5)
    ret (n, ok)
}

fn utc_time(seconds: i64, dst: []u8) -> str {
    // days from civil, inverse: Howard Hinnant's algorithm in plain i64
    var days = seconds / 86400i64
    var rem = seconds % 86400i64
    if rem < 0i64 {
        rem += 86400i64
        days -= 1i64
    }
    let z = days + 719468i64
    var era = z / 146097i64
    if z < 0i64 { era = (z - 146096i64) / 146097i64 }
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    let day = doy - (153i64 * mp + 2i64) / 5i64 + 1i64
    var month = mp + 3i64
    if mp >= 10i64 { month = mp - 9i64 }
    var year = yoe + era * 400i64
    if month <= 2i64 { year += 1i64 }
    let hour = rem / 3600i64
    let minute = (rem % 3600i64) / 60i64
    let second = rem % 60i64
    let y2 = year % 100i64
    dst[0usize] = u8(48i64 + y2 / 10i64)
    dst[1usize] = u8(48i64 + y2 % 10i64)
    dst[2usize] = u8(48i64 + month / 10i64)
    dst[3usize] = u8(48i64 + month % 10i64)
    dst[4usize] = u8(48i64 + day / 10i64)
    dst[5usize] = u8(48i64 + day % 10i64)
    dst[6usize] = u8(48i64 + hour / 10i64)
    dst[7usize] = u8(48i64 + hour % 10i64)
    dst[8usize] = u8(48i64 + minute / 10i64)
    dst[9usize] = u8(48i64 + minute % 10i64)
    dst[10usize] = u8(48i64 + second / 10i64)
    dst[11usize] = u8(48i64 + second % 10i64)
    dst[12usize] = 90u8
    ret dst[0usize..13usize]
}

// An Ed25519 SignedData over `content` by `secret`, whose certificate is `cert_der` (embedded);
// signed attributes with `signing_time` (Unix seconds, years 1950..2049). Detached unless
// `attached`. The DER is written into `out`; its length is returned.
fn sign_ed25519(a: *mem.Arena, content: []const u8, cert_der: []const u8, secret: sign.Ed25519SecretKey, attached: bool, signing_time: i64, out: []u8) -> (usize, err) {
    let mark = mem.mark(a)
    let (issuer, serial, cert_error) = issuer_and_serial(cert_der)
    if cert_error != ok { ret (0usize, cert_error) }
    let d = hash.sha512(content)
    let oid_sha = oid_sha512()
    let oid_dt = oid_data()
    let oid_ct = oid_content_type()
    let oid_md = oid_message_digest()
    let oid_st = oid_signing_time()
    let oid_ed = oid_ed25519()
    let oid_sd = oid_signed_data()
    let (scratch, scratch_error) = mem.alloc[u8](a, 4096usize + cert_der.len * 2usize + content.len * 2usize)
    if scratch_error != ok { ret (0usize, scratch_error) }
    var at = 0usize
    // pieces, each built then referred to by a slice
    // attribute: contentType
    let ct_oid_start = at
    let (t1, e1) = tlv1(scratch, at, 6u8, oid_ct[0usize..9usize])
    if e1 != ok { ret (0usize, e1) }
    let ct_oid = scratch[ct_oid_start..t1]
    at = t1
    let ct_val_start = at
    let (t2, e2) = tlv1(scratch, at, 6u8, oid_dt[0usize..9usize])
    if e2 != ok { ret (0usize, e2) }
    let ct_val_oid = scratch[ct_val_start..t2]
    at = t2
    let ct_set_start = at
    let (t3, e3) = tlv1(scratch, at, 49u8, ct_val_oid)
    if e3 != ok { ret (0usize, e3) }
    let ct_set = scratch[ct_set_start..t3]
    at = t3
    let ct_attr_start = at
    let (t4, e4) = tlv2(scratch, at, 48u8, ct_oid, ct_set)
    if e4 != ok { ret (0usize, e4) }
    let ct_attr = scratch[ct_attr_start..t4]
    at = t4
    // attribute: signingTime
    let st_oid_start = at
    let (t5, e5) = tlv1(scratch, at, 6u8, oid_st[0usize..9usize])
    if e5 != ok { ret (0usize, e5) }
    let st_oid = scratch[st_oid_start..t5]
    at = t5
    var time_text: [13]u8 = zero
    let time_bytes = utc_time(signing_time, time_text[0usize..13usize])
    let st_time_start = at
    let (t6, e6) = tlv1(scratch, at, 23u8, time_bytes)
    if e6 != ok { ret (0usize, e6) }
    let st_time = scratch[st_time_start..t6]
    at = t6
    let st_set_start = at
    let (t7, e7) = tlv1(scratch, at, 49u8, st_time)
    if e7 != ok { ret (0usize, e7) }
    let st_set = scratch[st_set_start..t7]
    at = t7
    let st_attr_start = at
    let (t8, e8) = tlv2(scratch, at, 48u8, st_oid, st_set)
    if e8 != ok { ret (0usize, e8) }
    let st_attr = scratch[st_attr_start..t8]
    at = t8
    // attribute: messageDigest
    let md_oid_start = at
    let (t9, e9) = tlv1(scratch, at, 6u8, oid_md[0usize..9usize])
    if e9 != ok { ret (0usize, e9) }
    let md_oid = scratch[md_oid_start..t9]
    at = t9
    let md_octets_start = at
    let (t10, e10) = tlv1(scratch, at, 4u8, d[0usize..64usize])
    if e10 != ok { ret (0usize, e10) }
    let md_octets = scratch[md_octets_start..t10]
    at = t10
    let md_set_start = at
    let (t11, e11) = tlv1(scratch, at, 49u8, md_octets)
    if e11 != ok { ret (0usize, e11) }
    let md_set = scratch[md_set_start..t11]
    at = t11
    let md_attr_start = at
    let (t12, e12) = tlv2(scratch, at, 48u8, md_oid, md_set)
    if e12 != ok { ret (0usize, e12) }
    let md_attr = scratch[md_attr_start..t12]
    at = t12
    // signed attributes as a DER SET OF: sorted by encoding (the lengths already differ in
    // contentType < signingTime < messageDigest order)
    let attrs_set_start = at
    let (t13, e13) = tlv3(scratch, at, 49u8, ct_attr, st_attr, md_attr)
    if e13 != ok { ret (0usize, e13) }
    let attrs_set = scratch[attrs_set_start..t13]
    at = t13
    // the signature is over the SET encoding
    let (sig_value, sig_error) = sign.ed25519_sign(secret, attrs_set)
    if sig_error != ok { ret (0usize, sig_error) }
    // [0] IMPLICIT form of the same attributes
    let attrs_implicit_start = at
    let (t14, e14) = tlv3(scratch, at, 160u8, ct_attr, st_attr, md_attr)
    if e14 != ok { ret (0usize, e14) }
    let attrs_implicit = scratch[attrs_implicit_start..t14]
    at = t14
    // version 1
    var one: [1]u8 = zero
    one[0usize] = 1u8
    let version_start = at
    let (t15, e15) = tlv1(scratch, at, 2u8, one[0usize..1usize])
    if e15 != ok { ret (0usize, e15) }
    let version = scratch[version_start..t15]
    at = t15
    // issuerAndSerialNumber
    let serial_start = at
    let (t16, e16) = tlv1(scratch, at, 2u8, serial)
    if e16 != ok { ret (0usize, e16) }
    let serial_tlv = scratch[serial_start..t16]
    at = t16
    let ias_start = at
    let (t17, e17) = tlv2(scratch, at, 48u8, issuer, serial_tlv)
    if e17 != ok { ret (0usize, e17) }
    let ias = scratch[ias_start..t17]
    at = t17
    // digestAlgorithm sha512 (no parameters), signatureAlgorithm id-Ed25519
    let oid_sha_start = at
    let (t18, e18) = tlv1(scratch, at, 6u8, oid_sha[0usize..9usize])
    if e18 != ok { ret (0usize, e18) }
    let oid_sha_tlv = scratch[oid_sha_start..t18]
    at = t18
    let digest_alg_start = at
    let (t19, e19) = tlv1(scratch, at, 48u8, oid_sha_tlv)
    if e19 != ok { ret (0usize, e19) }
    let digest_alg = scratch[digest_alg_start..t19]
    at = t19
    let oid_ed_start = at
    let (t20, e20) = tlv1(scratch, at, 6u8, oid_ed[0usize..3usize])
    if e20 != ok { ret (0usize, e20) }
    let oid_ed_tlv = scratch[oid_ed_start..t20]
    at = t20
    let sig_alg_start = at
    let (t21, e21) = tlv1(scratch, at, 48u8, oid_ed_tlv)
    if e21 != ok { ret (0usize, e21) }
    let sig_alg = scratch[sig_alg_start..t21]
    at = t21
    let sig_octets_start = at
    let (t22, e22) = tlv1(scratch, at, 4u8, sig_value.bytes[0usize..64usize])
    if e22 != ok { ret (0usize, e22) }
    let sig_octets = scratch[sig_octets_start..t22]
    at = t22
    let signer_start = at
    let (t23, e23) = tlv6(scratch, at, 48u8, version, ias, digest_alg, attrs_implicit, sig_alg, sig_octets)
    if e23 != ok { ret (0usize, e23) }
    let signer_info = scratch[signer_start..t23]
    at = t23
    let signers_start = at
    let (t24, e24) = tlv1(scratch, at, 49u8, signer_info)
    if e24 != ok { ret (0usize, e24) }
    let signers_set = scratch[signers_start..t24]
    at = t24
    // digestAlgorithms SET
    let digests_start = at
    let (t25, e25) = tlv1(scratch, at, 49u8, digest_alg)
    if e25 != ok { ret (0usize, e25) }
    let digests_set = scratch[digests_start..t25]
    at = t25
    // encapContentInfo
    let oid_data_start = at
    let (t26, e26) = tlv1(scratch, at, 6u8, oid_dt[0usize..9usize])
    if e26 != ok { ret (0usize, e26) }
    let oid_data_tlv = scratch[oid_data_start..t26]
    at = t26
    var encap: []const u8 = oid_data_tlv
    var encap_tlv: []const u8 = zero
    if attached {
        let octets_start = at
        let (t27, e27) = tlv1(scratch, at, 4u8, content)
        if e27 != ok { ret (0usize, e27) }
        let octets = scratch[octets_start..t27]
        at = t27
        let explicit_start = at
        let (t28, e28) = tlv1(scratch, at, 160u8, octets)
        if e28 != ok { ret (0usize, e28) }
        let explicit_tlv = scratch[explicit_start..t28]
        at = t28
        let encap_start = at
        let (t29, e29) = tlv2(scratch, at, 48u8, oid_data_tlv, explicit_tlv)
        if e29 != ok { ret (0usize, e29) }
        encap_tlv = scratch[encap_start..t29]
        at = t29
    } else {
        let encap_start = at
        let (t29, e29) = tlv1(scratch, at, 48u8, oid_data_tlv)
        if e29 != ok { ret (0usize, e29) }
        encap_tlv = scratch[encap_start..t29]
        at = t29
    }
    // certificates [0] IMPLICIT
    let certs_start = at
    let (t30, e30) = tlv1(scratch, at, 160u8, cert_der)
    if e30 != ok { ret (0usize, e30) }
    let certs = scratch[certs_start..t30]
    at = t30
    let sd_start = at
    let (t31, e31) = tlv5(scratch, at, 48u8, version, digests_set, encap_tlv, certs, signers_set)
    if e31 != ok { ret (0usize, e31) }
    let sd_body = scratch[sd_start..t31]
    at = t31
    let sd_wrap_start = at
    let (t32, e32) = tlv1(scratch, at, 160u8, sd_body)
    if e32 != ok { ret (0usize, e32) }
    let sd_wrap = scratch[sd_wrap_start..t32]
    at = t32
    let type_start = at
    let (t33, e33) = tlv1(scratch, at, 6u8, oid_sd[0usize..9usize])
    if e33 != ok { ret (0usize, e33) }
    let type_tlv = scratch[type_start..t33]
    at = t33
    let (n, e_final) = tlv2(out, 0usize, 48u8, type_tlv, sd_wrap)
    mem.reset(a, mark)
    if e_final != ok { ret (0usize, e_final) }
    ret (n, ok)
}
