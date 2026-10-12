// PKCS #12 (RFC 7292) personal-information exchange files: read the keys and certificates out
// of a `.p12`/`.pfx` and write one holding a private key and its certificate chain.
//
// Profile. This is the modern profile OpenSSL 3 and `cryptography` write by default: bag
// contents protected with PBES2 (PBKDF2 with HMAC-SHA-256 or HMAC-SHA-512, AES-128/192/256
// in CBC mode) and an HMAC-SHA-256 or HMAC-SHA-512 integrity MAC keyed by the RFC 7292
// appendix B key derivation over the BMPString form of the password. Legacy stores
// (PBE-SHA1-3DES, PBE-SHA1-RC2-40, SHA-1 MACs, which pre-3.0 OpenSSL and old Java wrote) are
// `Unsupported`: the cipher or MAC is named in that error rather than guessed. The PBES2
// password is the UTF-8 text, the MAC password is UTF-16BE with a terminating NUL unit, as
// OpenSSL does.
//
// Reading verifies the MAC when the file has one (`BadPassword` when it fails, which is also
// what a wrong password looks like), then collects the key bags (PKCS #8 plaintext,
// decrypted when shrouded) and certificate bags, with each bag's friendly name (UTF-8) and
// local key id. Writing takes the salts and IVs from the caller (use `e.crypto.random`) so
// the output is a pure function of its inputs.

use e.mem
use e.crypto.cipher as cipher
use e.crypto.hash as hash
use e.crypto.kdf as kdf
use e.crypto.mac as mac
use e.fmt.asn1 as asn1

type KeyBag = struct { friendly_name: str, local_key_id: []const u8, pkcs8: []const u8 }
type CertBag = struct { friendly_name: str, local_key_id: []const u8, der: []const u8 }
type Store = struct { keys: []KeyBag, certs: []CertBag, had_mac: bool }
type Params = struct { key_salt: [16]u8, key_iv: [16]u8, cert_salt: [16]u8, cert_iv: [16]u8, mac_salt: [16]u8, iterations: u32 }
error Invalid
error BadPassword
error Unsupported
error TooSmall

const DEPTH: u16 = 16u16

// ---- OIDs (content bytes) ----

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// 1.2.840.113549.1.12.10.1.N
fn oid_bag(n: u8) -> [11]u8 { ret [11]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 12u8, 10u8, 1u8, n } }
// 1.2.840.113549.1.7.N
fn oid_pkcs7(n: u8) -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 7u8, n } }
// 1.2.840.113549.1.9.N
fn oid_attr(n: u8) -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 9u8, n } }
// 1.2.840.113549.1.5.N
fn oid_pbe(n: u8) -> [9]u8 { ret [9]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 5u8, n } }
// 1.2.840.113549.2.N (HMAC prf)
fn oid_prf(n: u8) -> [8]u8 { ret [8]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 2u8, n } }
// 2.16.840.1.101.3.4.1.N (AES-CBC)
fn oid_aes(n: u8) -> [9]u8 { ret [9]u8{ 96u8, 134u8, 72u8, 1u8, 101u8, 3u8, 4u8, 1u8, n } }
// 2.16.840.1.101.3.4.2.N (SHA-2)
fn oid_sha(n: u8) -> [9]u8 { ret [9]u8{ 96u8, 134u8, 72u8, 1u8, 101u8, 3u8, 4u8, 2u8, n } }
fn oid_x509_cert() -> [10]u8 { ret [10]u8{ 42u8, 134u8, 72u8, 134u8, 247u8, 13u8, 1u8, 9u8, 22u8, 1u8 } }

// ---- reading helpers ----

fn next(r: *asn1.Reader) -> (asn1.Value, err) {
    let (v, present, e) = asn1.reader_next_err(r)
    if e != ok || !present { ret (zero, Invalid) }
    ret (v, ok)
}

fn children(v: asn1.Value) -> (asn1.Reader, err) {
    let (r, e) = asn1.children(v, DEPTH)
    if e != ok { ret (zero, Invalid) }
    ret (r, ok)
}

fn seq_of(r: *asn1.Reader) -> (asn1.Reader, err) {
    let (v, e) = next(r)
    if e != ok { ret (zero, e) }
    if v.tag.class != .Universal || v.tag.number != 16u32 { ret (zero, Invalid) }
    let (kids, kids_error) = children(v)
    ret (kids, kids_error)
}

fn int_of(v: asn1.Value) -> (u32, err) {
    if v.tag.number != 2u32 || v.content.len == 0usize || v.content.len > 4usize { ret (0u32, Invalid) }
    var n = 0u32
    var i = 0usize
    while i < v.content.len {
        n = n * 256u32 + u32(v.content[i])
        i += 1usize
    }
    ret (n, ok)
}

// UTF-16BE (BMPString) to UTF-8.
fn bmp_to_utf8(a: *mem.Arena, bmp: []const u8) -> (str, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, bmp.len * 2usize + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    var n = 0usize
    var i = 0usize
    while i + 1usize < bmp.len {
        var cp = u32(bmp[i]) * 256u32 + u32(bmp[i + 1usize])
        i += 2usize
        if cp >= 55296u32 && cp < 56320u32 && i + 1usize < bmp.len {
            let low = u32(bmp[i]) * 256u32 + u32(bmp[i + 1usize])
            if low >= 56320u32 && low < 57344u32 {
                cp = 65536u32 + ((cp - 55296u32) << 10u32) + (low - 56320u32)
                i += 2usize
            }
        }
        if cp < 128u32 {
            buf[n] = u8(cp)
            n += 1usize
        } else if cp < 2048u32 {
            buf[n] = u8(192u32 + (cp >> 6u32))
            buf[n + 1usize] = u8(128u32 + (cp & 63u32))
            n += 2usize
        } else if cp < 65536u32 {
            buf[n] = u8(224u32 + (cp >> 12u32))
            buf[n + 1usize] = u8(128u32 + ((cp >> 6u32) & 63u32))
            buf[n + 2usize] = u8(128u32 + (cp & 63u32))
            n += 3usize
        } else {
            buf[n] = u8(240u32 + (cp >> 18u32))
            buf[n + 1usize] = u8(128u32 + ((cp >> 12u32) & 63u32))
            buf[n + 2usize] = u8(128u32 + ((cp >> 6u32) & 63u32))
            buf[n + 3usize] = u8(128u32 + (cp & 63u32))
            n += 4usize
        }
    }
    ret (buf[0usize..n], ok)
}

// The PKCS #12 password form: UTF-16BE of the UTF-8 text plus one NUL unit.
fn bmp_password(a: *mem.Arena, password: str) -> ([]u8, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, password.len * 4usize + 2usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var n = 0usize
    var i = 0usize
    while i < password.len {
        let c = u32(password[i])
        var cp = c
        var width = 1usize
        if c >= 240u32 {
            if i + 3usize >= password.len { ret (zero, Invalid) }
            cp = ((c & 7u32) << 18u32) | ((u32(password[i + 1usize]) & 63u32) << 12u32) | ((u32(password[i + 2usize]) & 63u32) << 6u32) | (u32(password[i + 3usize]) & 63u32)
            width = 4usize
        } else if c >= 224u32 {
            if i + 2usize >= password.len { ret (zero, Invalid) }
            cp = ((c & 15u32) << 12u32) | ((u32(password[i + 1usize]) & 63u32) << 6u32) | (u32(password[i + 2usize]) & 63u32)
            width = 3usize
        } else if c >= 192u32 {
            if i + 1usize >= password.len { ret (zero, Invalid) }
            cp = ((c & 31u32) << 6u32) | (u32(password[i + 1usize]) & 63u32)
            width = 2usize
        }
        if cp >= 65536u32 {
            let v = cp - 65536u32
            let high = 55296u32 + (v >> 10u32)
            let low = 56320u32 + (v & 1023u32)
            buf[n] = u8(high >> 8u32)
            buf[n + 1usize] = u8(high & 255u32)
            buf[n + 2usize] = u8(low >> 8u32)
            buf[n + 3usize] = u8(low & 255u32)
            n += 4usize
        } else {
            buf[n] = u8(cp >> 8u32)
            buf[n + 1usize] = u8(cp & 255u32)
            n += 2usize
        }
        i += width
    }
    buf[n] = 0u8
    buf[n + 1usize] = 0u8
    ret (buf[0usize..n + 2usize], ok)
}

fn digest_of(bits: u16, data: []const u8, out: []u8) {
    if bits == 256u16 {
        let d = hash.sha256(data)
        mem.copy[u8](out[0usize..32usize], d[0usize..32usize])
    } else {
        let d = hash.sha512(data)
        mem.copy[u8](out[0usize..64usize], d[0usize..64usize])
    }
}

// RFC 7292 appendix B.2 over SHA-256 (`bits` 256, v = 64, u = 32) or SHA-512 (v = 128, u = 64).
fn pkcs12_kdf(a: *mem.Arena, bits: u16, id: u8, password_bmp: []const u8, salt: []const u8, iterations: u32, out: []u8) -> err {
    var v = 64usize
    var u = 32usize
    if bits == 512u16 {
        v = 128usize
        u = 64usize
    }
    let mark = mem.mark(a)
    let s_len = (salt.len + v - 1usize) / v * v
    let p_len = (password_bmp.len + v - 1usize) / v * v
    let i_len = s_len + p_len
    let (buf, alloc_error) = mem.alloc[u8](a, v + i_len + v + u)
    if alloc_error != ok { ret alloc_error }
    var k = 0usize
    while k < v {
        buf[k] = id
        k += 1usize
    }
    k = 0usize
    while k < s_len {
        buf[v + k] = salt[k % salt.len]
        k += 1usize
    }
    k = 0usize
    while k < p_len {
        buf[v + s_len + k] = password_bmp[k % password_bmp.len]
        k += 1usize
    }
    var digest: [64]u8 = zero
    var block: [128]u8 = zero
    var produced = 0usize
    while produced < out.len {
        // A = H^iterations(D || I)
        digest_of(bits, buf[0usize..v + i_len], digest[0usize..u])
        var round = 1u32
        while round < iterations {
            var again: [64]u8 = zero
            mem.copy[u8](again[0usize..u], digest[0usize..u])
            digest_of(bits, again[0usize..u], digest[0usize..u])
            round += 1u32
        }
        var take = out.len - produced
        if take > u { take = u }
        mem.copy[u8](out[produced..produced + take], digest[0usize..take])
        produced += take
        if produced >= out.len { break }
        // B = A repeated to v bytes; each v-byte block of I is increased by B + 1
        k = 0usize
        while k < v {
            block[k] = digest[k % u]
            k += 1usize
        }
        var at = 0usize
        while at < i_len {
            var carry = 1u32
            var j = v
            while j > 0usize {
                j -= 1usize
                let sum = u32(buf[v + at + j]) + u32(block[j]) + carry
                buf[v + at + j] = u8(sum & 255u32)
                carry = sum >> 8u32
            }
            at += v
        }
    }
    mem.reset(a, mark)
    ret ok
}

// PBES2-decrypts `data` under the AlgorithmIdentifier parameters `params` (the SEQUENCE after the
// PBES2 OID) with the UTF-8 `password`. The plaintext is returned from a fresh arena copy.
fn pbes2_decrypt(a: *mem.Arena, params: asn1.Value, data: []const u8, password: str) -> ([]u8, err) {
    let (kids, kids_error) = children(params)
    if kids_error != ok { ret (zero, kids_error) }
    var r = kids
    let (kdf_alg, kdf_error) = seq_of(&r)
    if kdf_error != ok { ret (zero, kdf_error) }
    var kr = kdf_alg
    let (kdf_oid, kdf_oid_error) = next(&kr)
    if kdf_oid_error != ok { ret (zero, kdf_oid_error) }
    let pbkdf2 = oid_pbe(12u8)
    if !same(kdf_oid.content, pbkdf2[0usize..9usize]) { ret (zero, Unsupported) }
    let (kdf_params, kp_error) = seq_of(&kr)
    if kp_error != ok { ret (zero, kp_error) }
    var pr = kdf_params
    let (salt, salt_error) = next(&pr)
    if salt_error != ok || salt.tag.number != 4u32 { ret (zero, Invalid) }
    let (iter_value, iter_error) = next(&pr)
    if iter_error != ok { ret (zero, iter_error) }
    let (iterations, iterations_error) = int_of(iter_value)
    if iterations_error != ok || iterations == 0u32 { ret (zero, Invalid) }
    var prf_bits = 160u16
    var key_len = 0usize
    while true {
        let (item, present, item_error) = asn1.reader_next_err(&pr)
        if item_error != ok { ret (zero, Invalid) }
        if !present { break }
        if item.tag.number == 2u32 {
            let (kl, kl_error) = int_of(item)
            if kl_error != ok { ret (zero, kl_error) }
            key_len = usize(kl)
        } else if item.tag.number == 16u32 {
            let (prf_kids, prf_kids_error) = children(item)
            if prf_kids_error != ok { ret (zero, prf_kids_error) }
            var pk = prf_kids
            let (prf_oid, prf_oid_error) = next(&pk)
            if prf_oid_error != ok { ret (zero, prf_oid_error) }
            let h256 = oid_prf(9u8)
            let h512 = oid_prf(11u8)
            if same(prf_oid.content, h256[0usize..8usize]) {
                prf_bits = 256u16
            } else if same(prf_oid.content, h512[0usize..8usize]) {
                prf_bits = 512u16
            } else {
                ret (zero, Unsupported)
            }
        }
    }
    if prf_bits == 160u16 { ret (zero, Unsupported) }
    let (scheme, scheme_error) = seq_of(&r)
    if scheme_error != ok { ret (zero, scheme_error) }
    var sr = scheme
    let (scheme_oid, scheme_oid_error) = next(&sr)
    if scheme_oid_error != ok { ret (zero, scheme_oid_error) }
    var aes_bytes = 0usize
    let a128 = oid_aes(2u8)
    let a192 = oid_aes(22u8)
    let a256 = oid_aes(42u8)
    if same(scheme_oid.content, a128[0usize..9usize]) { aes_bytes = 16usize }
    if same(scheme_oid.content, a192[0usize..9usize]) { aes_bytes = 24usize }
    if same(scheme_oid.content, a256[0usize..9usize]) { aes_bytes = 32usize }
    if aes_bytes == 0usize { ret (zero, Unsupported) }
    if key_len != 0usize && key_len != aes_bytes { ret (zero, Invalid) }
    let (iv, iv_error) = next(&sr)
    if iv_error != ok || iv.content.len != 16usize { ret (zero, Invalid) }
    var key_material: [32]u8 = zero
    var which = kdf.Hash.Sha256
    if prf_bits == 512u16 { which = .Sha512 }
    let kdf_result = kdf.pbkdf2(which, password, salt.content, iterations, key_material[0usize..aes_bytes])
    if kdf_result != ok { ret (zero, Invalid) }
    let (aes, aes_error) = cipher.aes_key(key_material[0usize..aes_bytes])
    if aes_error != ok { ret (zero, Invalid) }
    if data.len == 0usize || data.len % 16usize != 0usize { ret (zero, Invalid) }
    let (plain, alloc_error) = mem.alloc[u8](a, data.len)
    if alloc_error != ok { ret (zero, alloc_error) }
    mem.copy[u8](plain, data)
    var iv_bytes: [16]u8 = zero
    mem.copy[u8](iv_bytes[0usize..16usize], iv.content)
    if cipher.cbc_decrypt(&aes, iv_bytes, plain) != ok { ret (zero, Invalid) }
    let (n, unpad_error) = cipher.unpad_pkcs7(plain)
    if unpad_error != ok { ret (zero, BadPassword) }
    ret (plain[0usize..n], ok)
}

type Collector = struct { keys: []KeyBag, certs: []CertBag, key_count: usize, cert_count: usize }

// One SafeBag's attributes: friendlyName and localKeyId.
fn read_attributes(a: *mem.Arena, set: asn1.Value) -> (str, []const u8, err) {
    var name: str = ""
    var key_id: []const u8 = zero
    let (kids, kids_error) = children(set)
    if kids_error != ok { ret ("", zero, kids_error) }
    var r = kids
    while true {
        let (attr, present, attr_error) = asn1.reader_next_err(&r)
        if attr_error != ok { ret ("", zero, Invalid) }
        if !present { break }
        let (parts, parts_error) = children(attr)
        if parts_error != ok { ret ("", zero, parts_error) }
        var pr = parts
        let (oid, oid_error) = next(&pr)
        if oid_error != ok { ret ("", zero, oid_error) }
        let (values, values_error) = next(&pr)
        if values_error != ok { ret ("", zero, values_error) }
        let (vk, vk_error) = children(values)
        if vk_error != ok { ret ("", zero, vk_error) }
        var vr = vk
        let (first, first_error) = next(&vr)
        if first_error != ok { ret ("", zero, first_error) }
        let friendly = oid_attr(20u8)
        let local = oid_attr(21u8)
        if same(oid.content, friendly[0usize..9usize]) {
            let (text, text_error) = bmp_to_utf8(a, first.content)
            if text_error != ok { ret ("", zero, text_error) }
            name = text
        } else if same(oid.content, local[0usize..9usize]) {
            key_id = first.content
        }
    }
    ret (name, key_id, ok)
}

fn read_safe_contents(a: *mem.Arena, contents: []const u8, password: str, c: *Collector) -> err {
    var top = asn1.reader(contents, DEPTH)
    let (bags, bags_error) = seq_of(&top)
    if bags_error != ok { ret bags_error }
    var br = bags
    while true {
        let (bag, present, bag_error) = asn1.reader_next_err(&br)
        if bag_error != ok { ret Invalid }
        if !present { break }
        let (parts, parts_error) = children(bag)
        if parts_error != ok { ret parts_error }
        var pr = parts
        let (bag_id, id_error) = next(&pr)
        if id_error != ok { ret id_error }
        let (wrapper, wrapper_error) = next(&pr)
        if wrapper_error != ok { ret wrapper_error }
        var name: str = ""
        var key_id: []const u8 = zero
        let (attrs, has_attrs, attrs_error) = asn1.reader_next_err(&pr)
        if attrs_error != ok { ret Invalid }
        if has_attrs {
            let (n, k, attr_error) = read_attributes(a, attrs)
            if attr_error != ok { ret attr_error }
            name = n
            key_id = k
        }
        let (inner_kids, inner_error) = children(wrapper)
        if inner_error != ok { ret inner_error }
        var ir = inner_kids
        let (value, value_error) = next(&ir)
        if value_error != ok { ret value_error }
        let key_bag = oid_bag(1u8)
        let shrouded = oid_bag(2u8)
        let cert_bag = oid_bag(3u8)
        if same(bag_id.content, key_bag[0usize..11usize]) {
            c.keys[c.key_count] = KeyBag { friendly_name: name, local_key_id: key_id, pkcs8: value.encoded }
            c.key_count += 1usize
        } else if same(bag_id.content, shrouded[0usize..11usize]) {
            // EncryptedPrivateKeyInfo { AlgorithmIdentifier, OCTET STRING }
            let (enc_kids, enc_error) = children(value)
            if enc_error != ok { ret enc_error }
            var er = enc_kids
            let (alg, alg_error) = seq_of(&er)
            if alg_error != ok { ret alg_error }
            var ar = alg
            let (alg_oid, alg_oid_error) = next(&ar)
            if alg_oid_error != ok { ret alg_oid_error }
            let pbes2 = oid_pbe(13u8)
            if !same(alg_oid.content, pbes2[0usize..9usize]) { ret Unsupported }
            let (params, params_error) = next(&ar)
            if params_error != ok { ret params_error }
            let (blob, blob_error) = next(&er)
            if blob_error != ok || blob.tag.number != 4u32 { ret Invalid }
            let (plain, plain_error) = pbes2_decrypt(a, params, blob.content, password)
            if plain_error != ok { ret plain_error }
            c.keys[c.key_count] = KeyBag { friendly_name: name, local_key_id: key_id, pkcs8: plain }
            c.key_count += 1usize
        } else if same(bag_id.content, cert_bag[0usize..11usize]) {
            // CertBag { OID, [0] EXPLICIT OCTET STRING }
            let (cb_kids, cb_error) = children(value)
            if cb_error != ok { ret cb_error }
            var cr = cb_kids
            let (cert_type, cert_type_error) = next(&cr)
            if cert_type_error != ok { ret cert_type_error }
            let x509 = oid_x509_cert()
            if same(cert_type.content, x509[0usize..10usize]) {
                let (cw, cw_error) = next(&cr)
                if cw_error != ok { ret cw_error }
                let (cw_kids, cw_kids_error) = children(cw)
                if cw_kids_error != ok { ret cw_kids_error }
                var cwr = cw_kids
                let (der, der_error) = next(&cwr)
                if der_error != ok || der.tag.number != 4u32 { ret Invalid }
                c.certs[c.cert_count] = CertBag { friendly_name: name, local_key_id: key_id, der: der.content }
                c.cert_count += 1usize
            }
        }
    }
    ret ok
}

fn parse(a: *mem.Arena, der: []const u8, password: str) -> (Store, err) {
    var store: Store = zero
    var top = asn1.reader(der, DEPTH)
    let (pfx, pfx_error) = seq_of(&top)
    if pfx_error != ok { ret (store, pfx_error) }
    var r = pfx
    let (version, version_error) = next(&r)
    if version_error != ok { ret (store, version_error) }
    let (version_number, version_number_error) = int_of(version)
    if version_number_error != ok || version_number != 3u32 { ret (store, Unsupported) }
    let (auth_safe, auth_error) = seq_of(&r)
    if auth_error != ok { ret (store, auth_error) }
    var ar = auth_safe
    let (content_type, ct_error) = next(&ar)
    if ct_error != ok { ret (store, ct_error) }
    let data_oid = oid_pkcs7(1u8)
    if !same(content_type.content, data_oid[0usize..9usize]) { ret (store, Unsupported) }
    let (wrap, wrap_error) = next(&ar)
    if wrap_error != ok { ret (store, wrap_error) }
    let (wrap_kids, wrap_kids_error) = children(wrap)
    if wrap_kids_error != ok { ret (store, wrap_kids_error) }
    var wr = wrap_kids
    let (octets, octets_error) = next(&wr)
    if octets_error != ok || octets.tag.number != 4u32 { ret (store, Invalid) }
    let safe = octets.content
    // MacData (optional)
    let (mac_data, has_mac, mac_error) = asn1.reader_next_err(&r)
    if mac_error != ok { ret (store, Invalid) }
    if has_mac {
        store.had_mac = true
        let (mk, mk_error) = children(mac_data)
        if mk_error != ok { ret (store, mk_error) }
        var mr = mk
        let (digest_info, di_error) = seq_of(&mr)
        if di_error != ok { ret (store, di_error) }
        var dr = digest_info
        let (alg, alg_error) = seq_of(&dr)
        if alg_error != ok { ret (store, alg_error) }
        var alr = alg
        let (alg_oid, alg_oid_error) = next(&alr)
        if alg_oid_error != ok { ret (store, alg_oid_error) }
        let (digest, digest_error) = next(&dr)
        if digest_error != ok { ret (store, digest_error) }
        let (mac_salt, ms_error) = next(&mr)
        if ms_error != ok { ret (store, ms_error) }
        var iterations = 1u32
        let (iter_value, has_iter, iter_error) = asn1.reader_next_err(&mr)
        if iter_error != ok { ret (store, Invalid) }
        if has_iter {
            let (n, n_error) = int_of(iter_value)
            if n_error != ok { ret (store, n_error) }
            iterations = n
        }
        let s256 = oid_sha(1u8)
        let s512 = oid_sha(3u8)
        var bits = 0u16
        if same(alg_oid.content, s256[0usize..9usize]) { bits = 256u16 }
        if same(alg_oid.content, s512[0usize..9usize]) { bits = 512u16 }
        if bits == 0u16 { ret (store, Unsupported) }
        let mark = mem.mark(a)
        let (bmp, bmp_error) = bmp_password(a, password)
        if bmp_error != ok { ret (store, bmp_error) }
        var key: [64]u8 = zero
        var out_len = 32usize
        if bits == 512u16 { out_len = 64usize }
        let kdf_error = pkcs12_kdf(a, bits, 3u8, bmp, mac_salt.content, iterations, key[0usize..out_len])
        if kdf_error != ok { ret (store, kdf_error) }
        var computed: [64]u8 = zero
        if bits == 256u16 {
            let m = mac.hmac_sha256(key[0usize..32usize], safe)
            mem.copy[u8](computed[0usize..32usize], m[0usize..32usize])
        } else {
            let m = mac.hmac_sha512(key[0usize..64usize], safe)
            mem.copy[u8](computed[0usize..64usize], m[0usize..64usize])
        }
        mem.reset(a, mark)
        if !same(computed[0usize..out_len], digest.content) { ret (store, BadPassword) }
    }
    // AuthenticatedSafe
    var safe_top = asn1.reader(safe, DEPTH)
    let (infos, infos_error) = seq_of(&safe_top)
    if infos_error != ok { ret (store, infos_error) }
    // size the collectors by a generous bound: every bag is at least a few bytes
    let bound = safe.len / 8usize + 4usize
    let (keys, keys_error) = mem.alloc[KeyBag](a, bound)
    if keys_error != ok { ret (store, keys_error) }
    let (certs, certs_error) = mem.alloc[CertBag](a, bound)
    if certs_error != ok { ret (store, certs_error) }
    var c: Collector = zero
    c.keys = keys
    c.certs = certs
    var ir = infos
    while true {
        let (info, present, info_error) = asn1.reader_next_err(&ir)
        if info_error != ok { ret (store, Invalid) }
        if !present { break }
        let (parts, parts_error) = children(info)
        if parts_error != ok { ret (store, parts_error) }
        var pr = parts
        let (type_oid, type_error) = next(&pr)
        if type_error != ok { ret (store, type_error) }
        let (explicit, explicit_error) = next(&pr)
        if explicit_error != ok { ret (store, explicit_error) }
        let (inner, inner_error) = children(explicit)
        if inner_error != ok { ret (store, inner_error) }
        var inr = inner
        let plain_type = oid_pkcs7(1u8)
        let encrypted_type = oid_pkcs7(6u8)
        if same(type_oid.content, plain_type[0usize..9usize]) {
            let (octet, octet_error) = next(&inr)
            if octet_error != ok || octet.tag.number != 4u32 { ret (store, Invalid) }
            let e = read_safe_contents(a, octet.content, password, &c)
            if e != ok { ret (store, e) }
        } else if same(type_oid.content, encrypted_type[0usize..9usize]) {
            // EncryptedData { version, EncryptedContentInfo { OID, AlgorithmIdentifier, [0] encrypted } }
            let (ed, ed_error) = next(&inr)
            if ed_error != ok { ret (store, ed_error) }
            let (ed_kids, ed_kids_error) = children(ed)
            if ed_kids_error != ok { ret (store, ed_kids_error) }
            var edr = ed_kids
            let (ev, ev_error) = next(&edr)
            if ev_error != ok { ret (store, ev_error) }
            let (eci, eci_error) = seq_of(&edr)
            if eci_error != ok { ret (store, eci_error) }
            var ecr = eci
            let (content_oid, content_oid_error) = next(&ecr)
            if content_oid_error != ok { ret (store, content_oid_error) }
            let (alg, alg_error) = seq_of(&ecr)
            if alg_error != ok { ret (store, alg_error) }
            var algr = alg
            let (alg_oid, alg_oid_error) = next(&algr)
            if alg_oid_error != ok { ret (store, alg_oid_error) }
            let pbes2 = oid_pbe(13u8)
            if !same(alg_oid.content, pbes2[0usize..9usize]) { ret (store, Unsupported) }
            let (params, params_error) = next(&algr)
            if params_error != ok { ret (store, params_error) }
            let (blob, blob_error) = next(&ecr)
            if blob_error != ok { ret (store, blob_error) }
            // [0] IMPLICIT OCTET STRING: primitive content is the ciphertext
            let (plain, plain_error) = pbes2_decrypt(a, params, blob.content, password)
            if plain_error != ok { ret (store, plain_error) }
            let e = read_safe_contents(a, plain, password, &c)
            if e != ok { ret (store, e) }
        } else {
            ret (store, Unsupported)
        }
    }
    store.keys = c.keys[0usize..c.key_count]
    store.certs = c.certs[0usize..c.cert_count]
    ret (store, ok)
}

// ---- writing ----

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
    mem.copy[u8](dst[at..at + bytes.len], bytes)
    ret at + bytes.len
}

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

fn tlv4(dst: []u8, at: usize, tag: u8, p0: []const u8, p1: []const u8, p2: []const u8, p3: []const u8) -> (usize, err) {
    let (o, e) = begin(dst, at, tag, p0.len + p1.len + p2.len + p3.len)
    if e != ok { ret (at, e) }
    ret (append(dst, append(dst, append(dst, append(dst, o, p0), p1), p2), p3), ok)
}

// Little builder: a bump area `buf` with `at`, each piece appended and returned as a slice.
type Build = struct { buf: []u8, at: usize, failed: bool }

fn piece1(b: *Build, tag: u8, p0: []const u8) -> []const u8 {
    let start = b.at
    let (n, e) = tlv1(b.buf, b.at, tag, p0)
    if e != ok {
        b.failed = true
        ret b.buf[0usize..0usize]
    }
    b.at = n
    ret b.buf[start..n]
}

fn piece2(b: *Build, tag: u8, p0: []const u8, p1: []const u8) -> []const u8 {
    let start = b.at
    let (n, e) = tlv2(b.buf, b.at, tag, p0, p1)
    if e != ok {
        b.failed = true
        ret b.buf[0usize..0usize]
    }
    b.at = n
    ret b.buf[start..n]
}

fn piece3(b: *Build, tag: u8, p0: []const u8, p1: []const u8, p2: []const u8) -> []const u8 {
    let start = b.at
    let (n, e) = tlv3(b.buf, b.at, tag, p0, p1, p2)
    if e != ok {
        b.failed = true
        ret b.buf[0usize..0usize]
    }
    b.at = n
    ret b.buf[start..n]
}

fn piece4(b: *Build, tag: u8, p0: []const u8, p1: []const u8, p2: []const u8, p3: []const u8) -> []const u8 {
    let start = b.at
    let (n, e) = tlv4(b.buf, b.at, tag, p0, p1, p2, p3)
    if e != ok {
        b.failed = true
        ret b.buf[0usize..0usize]
    }
    b.at = n
    ret b.buf[start..n]
}

fn integer_piece(b: *Build, value: u32) -> []const u8 {
    var bytes: [5]u8 = zero
    var n = 0usize
    if value == 0u32 {
        bytes[0usize] = 0u8
        n = 1usize
    } else {
        var tmp: [4]u8 = zero
        var count = 0usize
        var v = value
        while v > 0u32 {
            tmp[count] = u8(v & 255u32)
            v = v >> 8u32
            count += 1usize
        }
        if tmp[count - 1usize] >= 128u8 {
            bytes[0usize] = 0u8
            n = 1usize
        }
        while count > 0usize {
            count -= 1usize
            bytes[n] = tmp[count]
            n += 1usize
        }
    }
    ret piece1(b, 2u8, bytes[0usize..n])
}

// AlgorithmIdentifier-like SEQUENCE { OID, params } where params is a ready piece.
fn oid_piece(b: *Build, oid: []const u8) -> []const u8 { ret piece1(b, 6u8, oid) }

fn utf16_bmp(a: *mem.Arena, s: str) -> ([]u8, err) {
    // ASCII and BMP only, as friendly names are in practice
    let (buf, alloc_error) = mem.alloc[u8](a, s.len * 2usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = u32(s[i])
        var cp = c
        var width = 1usize
        if c >= 224u32 && i + 2usize < s.len {
            cp = ((c & 15u32) << 12u32) | ((u32(s[i + 1usize]) & 63u32) << 6u32) | (u32(s[i + 2usize]) & 63u32)
            width = 3usize
        } else if c >= 192u32 && i + 1usize < s.len {
            cp = ((c & 31u32) << 6u32) | (u32(s[i + 1usize]) & 63u32)
            width = 2usize
        }
        buf[n] = u8(cp >> 8u32)
        buf[n + 1usize] = u8(cp & 255u32)
        n += 2usize
        i += width
    }
    ret (buf[0usize..n], ok)
}

// PBES2 parameters piece and the AES-256-CBC / PBKDF2-HMAC-SHA256 encryption of `plain`.
fn pbes2_encrypt(a: *mem.Arena, b: *Build, plain: []const u8, password: str, salt: []const u8, iv: []const u8, iterations: u32) -> ([]const u8, []const u8, err) {
    var key_material: [32]u8 = zero
    if kdf.pbkdf2(.Sha256, password, salt, iterations, key_material[0usize..32usize]) != ok { ret (zero, zero, Invalid) }
    let (aes, aes_error) = cipher.aes_key(key_material[0usize..32usize])
    if aes_error != ok { ret (zero, zero, Invalid) }
    let (padded, alloc_error) = mem.alloc[u8](a, plain.len + 16usize)
    if alloc_error != ok { ret (zero, zero, alloc_error) }
    let (n, pad_error) = cipher.pad_pkcs7(padded, plain)
    if pad_error != ok { ret (zero, zero, pad_error) }
    var iv_bytes: [16]u8 = zero
    mem.copy[u8](iv_bytes[0usize..16usize], iv)
    if cipher.cbc_encrypt(&aes, iv_bytes, padded[0usize..n]) != ok { ret (zero, zero, Invalid) }
    // AlgorithmIdentifier { pbes2, { { pbkdf2, { salt, iterations, keyLength 32, prf sha256 } }, { aes256, iv } } }
    let pbkdf2 = oid_pbe(12u8)
    let pbes2 = oid_pbe(13u8)
    let aes256 = oid_aes(42u8)
    let prf = oid_prf(9u8)
    let salt_octets = piece1(b, 4u8, salt)
    let iter_int = integer_piece(b, iterations)
    let key_len = integer_piece(b, 32u32)
    let prf_oid = oid_piece(b, prf[0usize..8usize])
    let null_piece = piece1(b, 5u8, b.buf[0usize..0usize])
    let prf_alg = piece2(b, 48u8, prf_oid, null_piece)
    let kdf_params = piece4(b, 48u8, salt_octets, iter_int, key_len, prf_alg)
    let pbkdf2_oid = oid_piece(b, pbkdf2[0usize..9usize])
    let kdf_alg = piece2(b, 48u8, pbkdf2_oid, kdf_params)
    let aes_oid = oid_piece(b, aes256[0usize..9usize])
    let iv_octets = piece1(b, 4u8, iv)
    let scheme = piece2(b, 48u8, aes_oid, iv_octets)
    let params = piece2(b, 48u8, kdf_alg, scheme)
    let pbes2_oid = oid_piece(b, pbes2[0usize..9usize])
    let alg = piece2(b, 48u8, pbes2_oid, params)
    ret (alg, padded[0usize..n], ok)
}

fn attributes_piece(b: *Build, a: *mem.Arena, friendly: str, key_id: []const u8) -> ([]const u8, err) {
    let friendly_oid = oid_attr(20u8)
    let local_oid = oid_attr(21u8)
    let (bmp, bmp_error) = utf16_bmp(a, friendly)
    if bmp_error != ok { ret (zero, bmp_error) }
    let name_value = piece1(b, 30u8, bmp)
    let name_set = piece1(b, 49u8, name_value)
    let name_oid = oid_piece(b, friendly_oid[0usize..9usize])
    let name_attr = piece2(b, 48u8, name_oid, name_set)
    let id_value = piece1(b, 4u8, key_id)
    let id_set = piece1(b, 49u8, id_value)
    let id_oid = oid_piece(b, local_oid[0usize..9usize])
    let id_attr = piece2(b, 48u8, id_oid, id_set)
    // DER SET OF: sorted by encoding; friendlyName (…14) sorts before localKeyId (…15)
    ret (piece2(b, 49u8, name_attr, id_attr), ok)
}

// A `.p12` with one private key (`pkcs8`) and a certificate chain (leaf first), both under
// PBES2 AES-256-CBC / PBKDF2-HMAC-SHA256, an HMAC-SHA-256 MAC, `iterations` rounds. The
// local key id is the SHA-1 of the leaf certificate, as OpenSSL does. Returns the length.
fn encode(a: *mem.Arena, pkcs8: []const u8, chain: []const []const u8, friendly: str, password: str, p: Params, out: []u8) -> (usize, err) {
    if chain.len == 0usize { ret (0usize, Invalid) }
    let mark = mem.mark(a)
    // every wrapping layer copies what it wraps: key about 8 layers, a certificate about 12
    var total = 16384usize + pkcs8.len * 32usize
    var i = 0usize
    while i < chain.len {
        total += chain[i].len * 48usize + 1024usize
        i += 1usize
    }
    let (area, area_error) = mem.alloc[u8](a, total)
    if area_error != ok { ret (0usize, area_error) }
    var b: Build = zero
    b.buf = area
    let key_id = hash.legacy_sha1(chain[0usize])
    let (attrs, attrs_error) = attributes_piece(&b, a, friendly, key_id[0usize..20usize])
    if attrs_error != ok { ret (0usize, attrs_error) }
    // --- the shrouded key bag inside plain SafeContents
    let (key_alg, encrypted_key, key_error) = pbes2_encrypt(a, &b, pkcs8, password, p.key_salt[0usize..16usize], p.key_iv[0usize..16usize], p.iterations)
    if key_error != ok { ret (0usize, key_error) }
    let enc_octets = piece1(&b, 4u8, encrypted_key)
    let epki = piece2(&b, 48u8, key_alg, enc_octets)
    let shrouded = oid_bag(2u8)
    let shrouded_oid = oid_piece(&b, shrouded[0usize..11usize])
    let key_wrap = piece1(&b, 160u8, epki)
    let key_bag = piece3(&b, 48u8, shrouded_oid, key_wrap, attrs)
    let key_safe = piece1(&b, 48u8, key_bag)
    let key_octets = piece1(&b, 4u8, key_safe)
    let key_explicit = piece1(&b, 160u8, key_octets)
    let data_type = oid_pkcs7(1u8)
    let data_oid = oid_piece(&b, data_type[0usize..9usize])
    let key_info = piece2(&b, 48u8, data_oid, key_explicit)
    // --- the certificate bags inside encrypted SafeContents
    let cert_type = oid_bag(3u8)
    let x509 = oid_x509_cert()
    var bag_pieces: [8][]const u8 = zero
    var count = chain.len
    if count > 8usize { count = 8usize }
    var c = 0usize
    while c < count {
        let der_octets = piece1(&b, 4u8, chain[c])
        let der_wrap = piece1(&b, 160u8, der_octets)
        let x509_oid = oid_piece(&b, x509[0usize..10usize])
        let cert_value = piece2(&b, 48u8, x509_oid, der_wrap)
        let cert_wrap = piece1(&b, 160u8, cert_value)
        let cert_oid = oid_piece(&b, cert_type[0usize..11usize])
        if c == 0usize {
            bag_pieces[c] = piece3(&b, 48u8, cert_oid, cert_wrap, attrs)
        } else {
            bag_pieces[c] = piece2(&b, 48u8, cert_oid, cert_wrap)
        }
        c += 1usize
    }
    // SafeContents is a SEQUENCE of the bags: concatenate them into one piece
    var bags_len = 0usize
    c = 0usize
    while c < count {
        bags_len += bag_pieces[c].len
        c += 1usize
    }
    let bags_start = b.at
    let (bags_header_end, bags_error) = begin(b.buf, b.at, 48u8, bags_len)
    if bags_error != ok { ret (0usize, bags_error) }
    var cursor = bags_header_end
    c = 0usize
    while c < count {
        cursor = append(b.buf, cursor, bag_pieces[c])
        c += 1usize
    }
    b.at = cursor
    let cert_safe = b.buf[bags_start..cursor]
    let (cert_alg, encrypted_certs, cert_error) = pbes2_encrypt(a, &b, cert_safe, password, p.cert_salt[0usize..16usize], p.cert_iv[0usize..16usize], p.iterations)
    if cert_error != ok { ret (0usize, cert_error) }
    let encrypted_type = oid_pkcs7(6u8)
    let encrypted_oid = oid_piece(&b, encrypted_type[0usize..9usize])
    let content_oid = oid_piece(&b, data_type[0usize..9usize])
    let implicit_content = piece1(&b, 128u8, encrypted_certs)
    let eci = piece3(&b, 48u8, content_oid, cert_alg, implicit_content)
    let zero_version = integer_piece(&b, 0u32)
    let encrypted_data = piece2(&b, 48u8, zero_version, eci)
    let encrypted_explicit = piece1(&b, 160u8, encrypted_data)
    let cert_info = piece2(&b, 48u8, encrypted_oid, encrypted_explicit)
    // --- AuthenticatedSafe, the MAC and the PFX
    let safe_seq = piece2(&b, 48u8, key_info, cert_info)
    let safe_octets = piece1(&b, 4u8, safe_seq)
    let safe_explicit = piece1(&b, 160u8, safe_octets)
    let auth_safe = piece2(&b, 48u8, data_oid, safe_explicit)
    let (bmp, bmp_error) = bmp_password(a, password)
    if bmp_error != ok { ret (0usize, bmp_error) }
    var mac_key: [32]u8 = zero
    let kdf_error = pkcs12_kdf(a, 256u16, 3u8, bmp, p.mac_salt[0usize..16usize], p.iterations, mac_key[0usize..32usize])
    if kdf_error != ok { ret (0usize, kdf_error) }
    let digest = mac.hmac_sha256(mac_key[0usize..32usize], safe_seq)
    let sha256 = oid_sha(1u8)
    let sha_oid = oid_piece(&b, sha256[0usize..9usize])
    let null_piece = piece1(&b, 5u8, b.buf[0usize..0usize])
    let digest_alg = piece2(&b, 48u8, sha_oid, null_piece)
    let digest_octets = piece1(&b, 4u8, digest[0usize..32usize])
    let digest_info = piece2(&b, 48u8, digest_alg, digest_octets)
    let salt_octets = piece1(&b, 4u8, p.mac_salt[0usize..16usize])
    let iterations_int = integer_piece(&b, p.iterations)
    let mac_data = piece3(&b, 48u8, digest_info, salt_octets, iterations_int)
    let version_int = integer_piece(&b, 3u32)
    let (n, final_error) = tlv3(out, 0usize, 48u8, version_int, auth_safe, mac_data)
    mem.reset(a, mark)
    if b.failed { ret (0usize, TooSmall) }
    if final_error != ok { ret (0usize, final_error) }
    ret (n, ok)
}
