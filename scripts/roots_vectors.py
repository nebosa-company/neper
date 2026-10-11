"""Generate L109's data: the bundled Mozilla root set and the trust-root fixture.

Oracle: the `cryptography` library (OpenSSL) builds a test PKI (P-256, RSA-2048 and Ed25519 roots, an intermediate,
leaves, junk blocks) and judges certifi's bundle (unique count, SHA-256 of the concatenated DER, how many roots verify
their own signature). Needs `certifi` and `cryptography` on PYTHONPATH (`pip install --target DIR certifi cryptography`).

    python scripts/roots_vectors.py            # writes lib/e/net/tls/mozilla.e and the net_tls_roots fixture

The Mozilla set is data: regenerate it from a newer certifi to refresh it.
"""
import datetime
import hashlib
import os
import sys

import certifi
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, padding, rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)


def lit(text):
    out = text.replace(BS, BS + BS).replace('"', BS + '"').replace('\n', BS + 'n').replace('\r', BS + 'r')
    return '"' + out + '"'


def pem(cert):
    return cert.public_bytes(serialization.Encoding.PEM).decode('ascii')


NB = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
NA = datetime.datetime(2046, 1, 1, tzinfo=datetime.timezone.utc)


def name(cn):
    return x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, 'Neper Tests'), x509.NameAttribute(NameOID.COMMON_NAME, cn)])


def make(subject_cn, key, issuer_cn, issuer_key, ca, sans=None, algorithm=None, path_len=None):
    builder = (x509.CertificateBuilder().subject_name(name(subject_cn)).issuer_name(name(issuer_cn))
               .public_key(key.public_key()).serial_number(x509.random_serial_number())
               .not_valid_before(NB).not_valid_after(NA))
    if ca:
        builder = builder.add_extension(x509.BasicConstraints(ca=True, path_length=path_len), critical=True)
        builder = builder.add_extension(x509.KeyUsage(True, False, False, False, False, True, True, False, False), critical=True)
    else:
        builder = builder.add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        builder = builder.add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
    if sans:
        builder = builder.add_extension(x509.SubjectAlternativeName([x509.DNSName(s) for s in sans]), critical=False)
    return builder.sign(issuer_key, algorithm)


def build_pki():
    p256 = lambda: ec.generate_private_key(ec.SECP256R1())
    r1k, i1k, l1k = p256(), p256(), p256()
    r2k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    l2k = p256()
    r3k, l3k = ed25519.Ed25519PrivateKey.generate(), ed25519.Ed25519PrivateKey.generate()
    r1 = make('Neper Test Root P256', r1k, 'Neper Test Root P256', r1k, True, algorithm=hashes.SHA256())
    i1 = make('Neper Test Intermediate', i1k, 'Neper Test Root P256', r1k, True, algorithm=hashes.SHA256(), path_len=0)
    l1 = make('leaf1.example.test', l1k, 'Neper Test Intermediate', i1k, False, ['leaf1.example.test', '*.wild.example.test'], hashes.SHA256())
    r2 = make('Neper Test Root RSA', r2k, 'Neper Test Root RSA', r2k, True, algorithm=hashes.SHA256())
    l2 = make('leaf2.example.test', l2k, 'Neper Test Root RSA', r2k, False, ['leaf2.example.test'], hashes.SHA256())
    r3 = make('Neper Test Root Ed25519', r3k, 'Neper Test Root Ed25519', r3k, True, algorithm=None)
    l3 = make('leaf3.example.test', l3k, 'Neper Test Root Ed25519', r3k, False, ['leaf3.example.test'], None)
    return dict(r1=r1, i1=i1, l1=l1, r2=r2, l2=l2, r3=r3, l3=l3)


def certifi_certs():
    text = open(certifi.where(), encoding='ascii').read()
    blocks, cur = [], None
    for line in text.splitlines():
        if line.startswith('-----BEGIN CERTIFICATE'):
            cur = [line]
        elif cur is not None:
            cur.append(line)
            if line.startswith('-----END CERTIFICATE'):
                blocks.append('\n'.join(cur) + '\n')
                cur = None
    certs = []
    seen = set()
    for b in blocks:
        c = x509.load_pem_x509_certificate(b.encode('ascii'))
        der = c.public_bytes(serialization.Encoding.DER)
        if der in seen:
            continue
        seen.add(der)
        certs.append((b, c, der))
    return text, blocks, certs


def self_signed_supported(c):
    """The count Neper's verify_signature can be expected to accept: a self-signed root whose key and hash it implements."""
    if c.subject != c.issuer:
        return False
    key = c.public_key()
    algo = c.signature_hash_algorithm
    if isinstance(key, ed25519.Ed25519PublicKey):
        return c.signature_algorithm_oid.dotted_string == '1.3.101.112' and verifies(c)
    if algo is None or algo.name not in ('sha256', 'sha384', 'sha512'):
        return False
    if isinstance(key, rsa.RSAPublicKey):
        # PKCS#1 v1.5 only (RSA-PSS is a different OID).
        return c.signature_algorithm_oid._name.endswith('Encryption') and verifies(c)
    if isinstance(key, ec.EllipticCurvePublicKey):
        return key.curve.name in ('secp256r1', 'secp384r1') and verifies(c)
    return False


def verifies(c):
    try:
        c.verify_directly_issued_by(c)
        return True
    except Exception:
        return False


def main():
    text, blocks, certs = certifi_certs()
    version = 'certifi ' + getattr(certifi, '__version__', '?')
    try:
        import importlib.metadata as md
        version = 'certifi ' + md.version('certifi')
    except Exception:
        pass
    concat = b''.join(der for _, _, der in certs)
    digest = hashlib.sha256(concat).hexdigest()
    supported = sum(1 for _, c, _ in certs if self_signed_supported(c))
    print(version, len(blocks), 'blocks', len(certs), 'unique', digest, supported, 'self-verifying supported')

    # --- lib/e/net/tls/mozilla.e
    per = 8
    parts = [''.join(b for b, _, _ in certs[i:i + per]) for i in range(0, len(certs), per)]
    src = []
    src.append('// The Mozilla root program\'s CA set, bundled (L109): %s, %d unique certificates, SHA-256 of their DER back to back\n' % (version, len(certs)))
    src.append('// %s. Generated by scripts/roots_vectors.py from certifi\'s cacert.pem; regenerate to refresh, never edit.\n' % digest)
    src.append('// `bundle` answers the set as a `roots.Bundle` ready for `tls.ClientConfig.trust_roots`; use `roots.merge` to\n')
    src.append('// add the host store or a caller\'s own roots. A bundled set ages: a caller that needs revocation must refresh.\n')
    src.append('use e.mem\nuse e.net.tls.roots as roots\n\n')
    src.append('fn source() -> str { ret %s }\n\n' % lit(version))
    src.append('fn certificate_count() -> usize { ret %dusize }\n\n' % len(certs))
    src.append('fn sha256_hex() -> str { ret %s }\n\n' % lit(digest))
    src.append('fn part_count() -> usize { ret %dusize }\n\n' % len(parts))
    for i, p in enumerate(parts):
        src.append('fn part_%d() -> str { ret %s }\n\n' % (i, lit(p)))
    src.append('fn part(i: usize) -> str {\n')
    for i in range(len(parts)):
        src.append('    if i == %dusize { ret part_%d() }\n' % (i, i))
    src.append('    ret ""\n}\n\n')
    src.append('''// The whole set as PEM text in `a`.
fn pem(a: *mem.Arena) -> (str, err) {
    var total = 0usize
    var i = 0usize
    while i < part_count() {
        total += part(i).len
        i += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, total)
    if buffer_error != ok { ret ("", buffer_error) }
    var at = 0usize
    i = 0usize
    while i < part_count() {
        let chunk = part(i)
        mem.copy[u8](buffer[at..at + chunk.len], chunk)
        at += chunk.len
        i += 1usize
    }
    ret (buffer[0usize..total], ok)
}

fn bundle(a: *mem.Arena) -> (roots.Bundle, err) {
    var none: roots.Bundle = zero
    let (text, text_error) = pem(a)
    if text_error != ok { ret (none, text_error) }
    let (set, set_error) = roots.from_pem(a, text, text.len + 1usize)
    ret (set, set_error)
}
''')
    with open(os.path.join(ROOT, 'lib', 'e', 'net', 'tls', 'mozilla.e'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(src))

    # --- fixture
    pki = build_pki()
    junk_cert = '-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n'
    key_block = '-----BEGIN PRIVATE KEY-----\n' + 'QUFBQUFBQUFBQUFBQUFBQQ==\n' + '-----END PRIVATE KEY-----\n'
    crlf = pem(pki['r1']).replace('\n', '\r\n')
    bundle_text = ('# Test bundle: comments and Issuer lines between blocks are skipped\n# Issuer: CN=Neper Test Root P256\n'
                   + crlf + '\nSubject: Neper Test Root RSA\n' + pem(pki['r2']) + key_block + junk_cert
                   + pem(pki['r3']) + '# a duplicate of the first root, LF endings\n' + pem(pki['r1']))
    out = {
        'BUNDLE': lit(bundle_text),
        'R1': lit(pem(pki['r1'])), 'R2': lit(pem(pki['r2'])), 'R3': lit(pem(pki['r3'])),
        'I1': lit(pem(pki['i1'])), 'L1': lit(pem(pki['l1'])), 'L2': lit(pem(pki['l2'])), 'L3': lit(pem(pki['l3'])),
        'JUNK': lit(junk_cert + key_block),
        'MOZ_COUNT': str(len(certs)), 'MOZ_BLOCKS': str(len(blocks)), 'MOZ_SHA': lit(digest), 'MOZ_SELF': str(supported),
    }
    with open(os.path.join(ROOT, 'scripts', 'roots_fixture_template.e'), encoding='utf-8') as f:
        template = f.read()
    for k, v in out.items():
        template = template.replace('@@%s@@' % k, v)
    target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_tls_roots', 'src', 'main.e')
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, 'w', encoding='utf-8', newline='\n') as f:
        f.write(template)
    print('wrote mozilla.e (%d parts) and the net_tls_roots fixture' % len(parts))


if __name__ == '__main__':
    sys.exit(main())
