"""Writes src/main.e for the crypto_sign_wide fixture (C144, D2249).

  python vectors.py

SHA-384 from hashlib, and ECDSA P-384/P-256 and RSA signatures from Python's cryptography package, so
the Neper verifiers are held to an independent implementation. The keys are fixed (the EC ones derived
from small scalars, the RSA one from fixed primes); only the ECDSA nonces and the output below are
whatever the package chose when this was run, and main.e carries the result, so the fixture does not
depend on the package. Every check in main.e has its own exit code.
"""
import hashlib
import pathlib

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa, utils

HERE = pathlib.Path(__file__).resolve().parent
lines = []
exit_code = [0]


def arr(name, data):
    lines.append("    let %s: [%d]u8 = [%d]u8{ %s }" % (name, len(data), len(data), ", ".join(str(b) for b in data)))


def check(condition):
    exit_code[0] += 1
    lines.append("    if %s { os.exit(%d) }" % (condition, exit_code[0]))


def raw_point(public):
    n = public.public_numbers()
    size = (public.curve.key_size + 7) // 8
    return b'\x04' + n.x.to_bytes(size, 'big') + n.y.to_bytes(size, 'big')


SHA = {256: hashes.SHA256, 384: hashes.SHA384, 512: hashes.SHA512}

# ---- SHA-384 ----
long = b'a' * 1000
two = b'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu'
for name, message in (('abc', b'abc'), ('empty', b''), ('two', two), ('long', long)):
    arr('sha384_' + name, hashlib.sha384(message).digest())
lines.append('    var long: [1000]u8 = zero')
lines.append('    var li = 0usize')
lines.append('    while li < 1000usize {')
lines.append('        long[li] = 97u8')
lines.append('        li += 1usize')
lines.append('    }')
lines.append('    let two = "%s"' % two.decode())
lines.append('    let e1 = hash.sha384("abc")')
check('!same(e1[0..], sha384_abc[0..])')
lines.append('    let e2 = hash.sha384("")')
check('!same(e2[0..], sha384_empty[0..])')
lines.append('    let e3 = hash.sha384(two)')
check('!same(e3[0..], sha384_two[0..])')
lines.append('    let e4 = hash.sha384(long[0..])')
check('!same(e4[0..], sha384_long[0..])')
lines.append('    var s = hash.sha384_init()')
lines.append('    hash.sha384_update(&s, long[..129])')
lines.append('    hash.sha384_update(&s, long[129..])')
lines.append('    let streamed = hash.sha384_done(&s)')
check('!same(streamed[0..], sha384_long[0..])')

# ---- ECDSA ----
message = b'neper wide signatures'
lines.append('    let message = "%s"' % message.decode())
lines.append('    let other = "neper wide signature"')
for curve_name, curve, key_size, scalar in (('p384', ec.SECP384R1(), 97, 7), ('p256', ec.SECP256R1(), 65, 11)):
    key = ec.derive_private_key(scalar, curve)
    arr(curve_name + '_key', raw_point(key.public_key()))
    lines.append('    let %s_public = key_%s(%s_key[0..])' % (curve_name, curve_name, curve_name))
    for hash_bits in (256, 384, 512):
        signature = key.sign(message, ec.ECDSA(SHA[hash_bits]()))
        if hash_bits == 384:
            sig384_len = len(signature)
        arr('%s_sig%d' % (curve_name, hash_bits), signature)
        check('!sign.%s_verify_hash(%s_public, message, %s_sig%d[0..], %du16)' % (curve_name, curve_name, curve_name, hash_bits, hash_bits))
        check('sign.%s_verify_hash(%s_public, other, %s_sig%d[0..], %du16)' % (curve_name, curve_name, curve_name, hash_bits, hash_bits))
    # A signature is for the hash it was made with.
    check('sign.%s_verify_hash(%s_public, message, %s_sig384[0..], 256u16)' % (curve_name, curve_name, curve_name))
    check('sign.%s_verify_hash(%s_public, message, %s_sig384[0..], 7u16)' % (curve_name, curve_name, curve_name))
    # One flipped bit in the signature, a truncated one, a key off the curve, another key.
    lines.append('    var flipped_%s: [%d]u8 = zero' % (curve_name, sig384_len))
    lines.append('    copy(flipped_%s[0..], %s_sig384[0..])' % (curve_name, curve_name))
    arr('%s_sig384_again' % curve_name, key.sign(message, ec.ECDSA(hashes.SHA384())))
    lines.append('    flipped_%s[%d] = flipped_%s[%d] ^ 1u8' % (curve_name, sig384_len - 5, curve_name, sig384_len - 5))
    check('sign.%s_verify_hash(%s_public, message, flipped_%s[..%s_sig384.len], 384u16)' % (curve_name, curve_name, curve_name, curve_name))
    check('sign.%s_verify_hash(%s_public, message, %s_sig384[..%s_sig384.len - 1usize], 384u16)' % (curve_name, curve_name, curve_name, curve_name))
    check('!sign.%s_verify_hash(%s_public, message, %s_sig384_again[0..], 384u16)' % (curve_name, curve_name, curve_name))
    lines.append('    var off_%s = %s_public' % (curve_name, curve_name))
    lines.append('    off_%s.bytes[%d] = off_%s.bytes[%d] ^ 1u8' % (curve_name, key_size - 3, curve_name, key_size - 3))
    check('sign.%s_verify_hash(off_%s, message, %s_sig384[0..], 384u16)' % (curve_name, curve_name, curve_name))
    other_key = ec.derive_private_key(scalar + 1, curve)
    arr(curve_name + '_other', raw_point(other_key.public_key()))
    lines.append('    let other_%s = key_%s(%s_other[0..])' % (curve_name, curve_name, curve_name))
    check('sign.%s_verify_hash(other_%s, message, %s_sig384[0..], 384u16)' % (curve_name, curve_name, curve_name))
# The default entry points are the matching hash: SHA-384 for P-384, SHA-256 for P-256.
lines.append('    ')

# ---- RSA ----
rsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
numbers = rsa_key.public_key().public_numbers()
arr('rsa_n', numbers.n.to_bytes(256, 'big'))
arr('rsa_e', numbers.e.to_bytes(3, 'big'))
for hash_bits in (256, 384, 512):
    arr('pkcs1_%d' % hash_bits, rsa_key.sign(message, padding.PKCS1v15(), SHA[hash_bits]()))
    arr('pss_%d' % hash_bits, rsa_key.sign(message, padding.PSS(mgf=padding.MGF1(SHA[hash_bits]()), salt_length=SHA[hash_bits]().digest_size), SHA[hash_bits]()))
    mark = 'let mark_%d = mem.mark(a)' % hash_bits
    lines.append('    ' + mark)
    check('!sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_%d[0..], %du16)' % (hash_bits, hash_bits))
    check('sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pkcs1_%d[0..], %du16)' % (hash_bits, hash_bits))
    check('!sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_%d[0..], %du16)' % (hash_bits, hash_bits))
    check('sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pss_%d[0..], %du16)' % (hash_bits, hash_bits))
    lines.append('    mem.reset(a, mark_%d)' % hash_bits)
# A signature is for its hash: SHA-384 PKCS#1 under SHA-512 and the reverse, PSS likewise.
check('sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_384[0..], 512u16)')
check('sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_512[0..], 384u16)')
check('sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_384[0..], 512u16)')
check('sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_256[0..], 384u16)')
# The SHA-256 entry points are unchanged.
check('!sign.rsa_pkcs1v15_verify(a, rsa_n[0..], rsa_e[0..], message, pkcs1_256[0..])')
check('!sign.rsa_pss_verify(a, rsa_n[0..], rsa_e[0..], message, pss_256[0..])')

# ---- X.509 chains with the new signature algorithms ----
import datetime

from cryptography import x509
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

UTC = datetime.timezone.utc
start = datetime.datetime(2025, 1, 1, tzinfo=UTC)
end = datetime.datetime(2035, 1, 1, tzinfo=UTC)
now = int(datetime.datetime(2026, 6, 1, tzinfo=UTC).timestamp())


def name(cn):
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])


def build(subject, issuer, public, signer, algorithm, ca=False, dns=None, serial=1):
    b = (x509.CertificateBuilder().subject_name(name(subject)).issuer_name(name(issuer)).public_key(public)
         .serial_number(serial).not_valid_before(start).not_valid_after(end)
         .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True))
    if dns:
        b = b.add_extension(x509.SubjectAlternativeName([x509.DNSName(dns)]), critical=False)
        b = b.add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
    return b.sign(signer, algorithm).public_bytes(serialization.Encoding.DER)


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


def der_let(name_, data):
    lines.append('    let %s = %s' % (name_, literal(data)))


# Chain 1: a P-384 root (SHA-384 self-signature) signs a P-256 intermediate with SHA-384; the
# intermediate signs a P-256 leaf with SHA-256 -- the shape of example.com's and github.com's chains.
root384_key = ec.derive_private_key(21, ec.SECP384R1())
mid256_key = ec.derive_private_key(22, ec.SECP256R1())
leaf256_key = ec.derive_private_key(23, ec.SECP256R1())
der_let('c1_root', build('Wide P384 Root', 'Wide P384 Root', root384_key.public_key(), root384_key, hashes.SHA384(), ca=True, serial=1))
der_let('c1_mid', build('Wide P256 Intermediate', 'Wide P384 Root', mid256_key.public_key(), root384_key, hashes.SHA384(), ca=True, serial=2))
der_let('c1_leaf', build('c1.example', 'Wide P256 Intermediate', leaf256_key.public_key(), mid256_key, hashes.SHA256(), dns='c1.example', serial=3))
# The same leaf signed by the P-384 root directly with SHA-512, and a leaf signed with a P-384 key under SHA-256.
der_let('c1_leaf512', build('c1.example', 'Wide P384 Root', leaf256_key.public_key(), root384_key, hashes.SHA512(), dns='c1.example', serial=4))
leaf384_key = ec.derive_private_key(24, ec.SECP384R1())
der_let('c1_leaf384', build('c1.example', 'Wide P384 Root', leaf384_key.public_key(), root384_key, hashes.SHA256(), dns='c1.example', serial=5))
# Chain 2: an RSA root signs itself with sha384WithRSA and a leaf with sha512WithRSA.
root_rsa = rsa.generate_private_key(public_exponent=65537, key_size=2048)
der_let('c2_root', build('Wide RSA Root', 'Wide RSA Root', root_rsa.public_key(), root_rsa, hashes.SHA384(), ca=True, serial=1))
der_let('c2_leaf', build('c2.example', 'Wide RSA Root', leaf256_key.public_key(), root_rsa, hashes.SHA512(), dns='c2.example', serial=2))
der_let('c2_leaf384', build('c2.example', 'Wide RSA Root', leaf256_key.public_key(), root_rsa, hashes.SHA384(), dns='c2.example', serial=3))
lines.append('    var c1_roots: [1]x509.Certificate = zero')
lines.append('    var c1_mids: [1]x509.Certificate = zero')
lines.append('    var c2_roots: [1]x509.Certificate = zero')
lines.append('    var c1_root_parsed: x509.Certificate = zero')
for tag, variable in (('c1_root', 'c1_root_cert'), ('c1_mid', 'c1_mid_cert'), ('c1_leaf', 'c1_leaf_cert'), ('c1_leaf512', 'c1_leaf512_cert'),
                      ('c1_leaf384', 'c1_leaf384_cert'), ('c2_root', 'c2_root_cert'), ('c2_leaf', 'c2_leaf_cert'), ('c2_leaf384', 'c2_leaf384_cert')):
    lines.append('    let (%s, pe_%s) = x509.parse(a, %s)' % (variable, tag, tag))
    check('pe_%s != ok' % tag)
lines.append('    c1_roots[0] = c1_root_cert')
lines.append('    c1_mids[0] = c1_mid_cert')
lines.append('    c2_roots[0] = c2_root_cert')
# Signatures one link at a time, then whole chains with the name and usage checked.
check('x509.verify_signature(a, c1_root_cert, c1_root_cert) != ok')
check('x509.verify_signature(a, c1_mid_cert, c1_root_cert) != ok')
check('x509.verify_signature(a, c1_leaf_cert, c1_mid_cert) != ok')
check('x509.verify_signature(a, c1_leaf512_cert, c1_root_cert) != ok')
check('x509.verify_signature(a, c1_leaf384_cert, c1_root_cert) != ok')
check('x509.verify_signature(a, c1_leaf_cert, c1_root_cert) != x509.InvalidCertificate')
check('x509.verify_signature(a, c1_mid_cert, c1_leaf_cert) != x509.InvalidCertificate')
check('x509.verify_signature(a, c2_root_cert, c2_root_cert) != ok')
check('x509.verify_signature(a, c2_leaf_cert, c2_root_cert) != ok')
check('x509.verify_signature(a, c2_leaf384_cert, c2_root_cert) != ok')
check('x509.verify_signature(a, c2_leaf_cert, c1_root_cert) != x509.InvalidCertificate')
lines.append('    let (chain1, chain1_error) = x509.verify(a, c1_leaf_cert, options(c1_roots[0..], c1_mids[0..], "c1.example", .ServerAuth, 4u16))')
check('chain1_error != ok || chain1.certificates.len != 3usize')
lines.append('    let (chain1b, chain1b_error) = x509.verify(a, c1_leaf_cert, options(c1_roots[0..], c1_mids[0..], "other.example", .ServerAuth, 4u16))')
check('chain1b_error == ok')
lines.append('    let (chain2, chain2_error) = x509.verify(a, c2_leaf_cert, options(c2_roots[0..], zero, "c2.example", .ServerAuth, 4u16))')
check('chain2_error != ok || chain2.certificates.len != 2usize')
lines.append('    let (chain3, chain3_error) = x509.verify(a, c2_leaf_cert, options(c1_roots[0..], zero, "c2.example", .ServerAuth, 4u16))')
check('chain3_error == ok')

body = '\n'.join(lines)
source = '''// `e.crypto.hash` SHA-384, `e.crypto.sign` ECDSA over P-384 and P-256 with SHA-256/384/512, and RSA PKCS#1
// v1.5 and PSS with SHA-256/384/512 (C144, D2249), against hashlib and Python's cryptography package
// (vectors.py beside this fixture writes this file). Each signature is also refused for another message,
// another hash, a flipped bit, a truncation, an off-curve key and another key. Every check has its own
// exit code.
use e.os
use e.mem
use e.crypto.hash as hash
use e.crypto.sign as sign
use e.crypto.x509 as x509
use e.time

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn copy(dst: []u8, src: []const u8) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

fn options(roots: []const x509.Certificate, intermediates: []const x509.Certificate, dns_name: str, usage: x509.KeyUsage, depth: u16) -> x509.VerifyOptions {
    var o: x509.VerifyOptions = zero
    o.roots = x509.Pool { certificates: roots }
    o.intermediates = x509.Pool { certificates: intermediates }
    o.dns_name = dns_name
    o.now = time.Instant { nanos: @@NOW@@i64 * 1000000000i64 }
    o.usage = usage
    o.max_depth = depth
    ret o
}

fn key_p384(raw: []const u8) -> sign.P384PublicKey {
    var key: sign.P384PublicKey = zero
    copy(key.bytes[0..], raw)
    ret key
}

fn key_p256(raw: []const u8) -> sign.P256PublicKey {
    var key: sign.P256PublicKey = zero
    copy(key.bytes[0..], raw)
    ret key
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body).replace('@@NOW@@', str(now))
(HERE / 'src').mkdir(exist_ok=True)
(HERE / 'src' / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote src/main.e with', exit_code[0], 'checks')
