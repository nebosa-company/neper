"""Generate tests/selfhost/fixtures/link/crypto_jks/src/main.e (L160, D2803).

Reference: `pyjks` (a pure-Python JKS reader/writer): keystores of private-key entries
(RSA-1024, P-256 and Ed25519 PKCS#8 keys with certificate chains) and trusted-certificate
entries, written by pyjks under several store passwords (ASCII, non-BMP, empty). The fixture
parses each, checks aliases, kinds, timestamps, chains and the decrypted PKCS#8, and
refuses a wrong password and a flipped byte; then it re-protects each key with the salt
found in the original and re-encodes the store, which must equal pyjks' bytes exactly.
"""
import datetime
import sys
from pathlib import Path

import jks
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, rsa
from cryptography.x509.oid import NameOID

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'crypto_jks' / 'src' / 'main.e'


def make(kind, cn):
    if kind == 'rsa':
        key = rsa.generate_private_key(public_exponent=65537, key_size=1024)
        algo = hashes.SHA256()
    elif kind == 'ec':
        key = ec.generate_private_key(ec.SECP256R1())
        algo = hashes.SHA256()
    else:
        key = ed25519.Ed25519PrivateKey.generate()
        algo = None
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
    now = datetime.datetime(2026, 1, 1)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now).not_valid_after(now + datetime.timedelta(days=3650))
            .sign(key, algo))
    pkcs8 = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    return pkcs8, cert.public_bytes(serialization.Encoding.DER)


def hx(b):
    return b.hex() or '-'


stores = []
passwords = ['password', 'pässwörd€', 'x\U0001F600y', '']
for n, password in enumerate(passwords):
    entries = []
    for kind in ('rsa', 'ec', 'ed')[:1 + n % 3]:
        pkcs8, cert = make(kind, '%s-%d' % (kind, n))
        _, ca = make('ec', 'ca-%d' % n)
        entries.append(jks.PrivateKeyEntry.new('key-%s-%d' % (kind, n), [cert, ca], pkcs8, 'pkcs8'))
    for t in range(1 + n % 2):
        _, cert = make('rsa', 'trusted-%d-%d' % (n, t))
        entries.append(jks.TrustedCertEntry.new('trusted-%d-%d' % (n, t), cert))
    ks = jks.KeyStore.new('jks', entries)
    blob = ks.saves(password)
    # read back with pyjks to record what the fixture must see
    back = jks.KeyStore.loads(blob, password)
    rows = []
    for alias, e in back.entries.items():
        if isinstance(e, jks.PrivateKeyEntry):
            rows.append(('k', alias, e.timestamp, [c[1] for c in e.cert_chain], e.pkey_pkcs8))
        else:
            rows.append(('c', alias, e.timestamp, [e.cert], b''))
    stores.append((password, blob, rows))

lines = []
for password, blob, rows in stores:
    lines.append('K %s %s %d %s' % (hx(password.encode('utf-8')), hx(blob), len(rows), 'x'))
    for kind, alias, ts, certs, pkcs8 in rows:
        lines.append('E %s %s %d %d %s %s' % (kind, hx(alias.encode()), ts, len(certs), hx(pkcs8), ' '.join(hx(c) for c in certs)))

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

fn same_bytes(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

type Ctx = struct { loaded: bool, ks: jks.Keystore, password_len: usize, index: usize, store_len: usize }

fn u64dec(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

// Per run state lives in module-level buffers because lines of one store are checked together.
var password_store: [128]u8 = zero
var blob_store: [16384]u8 = zero
var scratch_store: [4096]u8 = zero

fn check_line(a: *mem.Arena, c: *Ctx, line: str) -> u8 {
    let (kind, p0) = tok(line, 0usize)
    let k = kind[0usize]
    if k == 75u8 {
        let (pw_hex, p1) = tok(line, p0)
        let (blob_hex, p2) = tok(line, p1)
        let (count_text, p3) = tok(line, p2)
        let pn = unhex(pw_hex, password_store[0usize..128usize])
        let bn = unhex(blob_hex, blob_store[0usize..16384usize])
        c.password_len = pn
        c.store_len = bn
        let password: str = password_store[0usize..pn]
        let (ks, e) = jks.parse(a, blob_store[0usize..bn], password)
        if e != ok { ret 1u8 }
        if ks.entries.len != usize(dec(count_text)) { ret 2u8 }
        c.ks = ks
        c.loaded = true
        c.index = 0usize
        // a wrong password and a flipped byte are refused
        let (_, wrong_error) = jks.parse(a, blob_store[0usize..bn], "not the password")
        if wrong_error != jks.BadPassword { ret 3u8 }
        var flipped: [16384]u8 = zero
        mem.copy[u8](flipped[0usize..bn], blob_store[0usize..bn])
        flipped[bn / 2usize] = flipped[bn / 2usize] ^ 1u8
        let (_, flip_error) = jks.parse(a, flipped[0usize..bn], password)
        if flip_error == ok { ret 4u8 }
        // re-encode: protect each key again with its original salt, then the whole store
        var rebuilt: [32]jks.Entry = zero
        var protected_bytes: [8192]u8 = zero
        var used = 0usize
        var key_buf: [2048]u8 = zero
        var i = 0usize
        while i < ks.entries.len {
            var entry = ks.entries[i]
            if entry.is_key {
                let (kn, ke) = jks.decrypt_key(a, entry.protected, password, key_buf[0usize..2048usize])
                if ke != ok { ret 5u8 }
                // the salt is the first 20 bytes of the payload, which ends the DER
                let blob = entry.protected
                var salt_at = 0usize
                // payload = last (20 + kn + 20) bytes of the DER
                salt_at = blob.len - (40usize + kn)
                let (pn2, pe) = jks.protect_key(key_buf[0usize..kn], password, blob[salt_at..salt_at + 20usize], protected_bytes[used..8192usize])
                if pe != ok { ret 6u8 }
                if !same_bytes(protected_bytes[used..used + pn2], entry.protected) { ret 7u8 }
                entry.protected = protected_bytes[used..used + pn2]
                used += pn2
            }
            rebuilt[i] = entry
            i += 1usize
        }
        var out: [16384]u8 = zero
        let (wn, we) = jks.encode(a, rebuilt[0usize..ks.entries.len], password, out[0usize..16384usize])
        if we != ok { ret 8u8 }
        if !same_bytes(out[0usize..wn], blob_store[0usize..bn]) { ret 9u8 }
        ret 0u8
    }
    if !c.loaded { ret 20u8 }
    // E kind alias ts n pkcs8 certs...
    let (ek, q1) = tok(line, p0)
    let (alias_hex, q2) = tok(line, q1)
    let (ts_text, q3) = tok(line, q2)
    let (n_text, q4) = tok(line, q3)
    let (pkcs8_hex, q5) = tok(line, q4)
    if c.index >= c.ks.entries.len { ret 21u8 }
    let entry = c.ks.entries[c.index]
    c.index += 1usize
    var buf: [2048]u8 = zero
    let an = unhex(alias_hex, buf[0usize..256usize])
    if !same_bytes(entry.alias, buf[0usize..an]) { ret 22u8 }
    if entry.timestamp_ms != u64dec(ts_text) { ret 23u8 }
    if entry.is_key != (kind[0usize] == 69u8 && ek[0usize] == 107u8) { ret 24u8 }
    let count = usize(dec(n_text))
    if entry.chain.len != count { ret 25u8 }
    var q = q5
    var j = 0usize
    while j < count {
        let (cert_hex, next) = tok(line, q)
        q = next
        let cn = unhex(cert_hex, scratch_store[0usize..4096usize])
        if !same_bytes(entry.chain[j], scratch_store[0usize..cn]) { ret 26u8 }
        j += 1usize
    }
    if entry.is_key {
        let password: str = password_store[0usize..c.password_len]
        var key_out: [2048]u8 = zero
        let (kn, ke) = jks.decrypt_key(a, entry.protected, password, key_out[0usize..2048usize])
        if ke != ok { ret 27u8 }
        let wn = unhex(pkcs8_hex, buf[0usize..2048usize])
        if !same_bytes(key_out[0usize..kn], buf[0usize..wn]) { ret 28u8 }
        // a wrong password fails the key check
        let (_, bad) = jks.decrypt_key(a, entry.protected, "wrong", key_out[0usize..2048usize])
        if bad != jks.BadPassword { ret 29u8 }
    }
    ret 0u8
}

fn run_chunk(a: *mem.Arena, c: *Ctx, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let code = check_line(a, c, text[start..i])
            if code != 0u8 {
                let shown = io.print(text[start..start + 30usize])
                ret code
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

'''

calls = '\n'.join('    let r_%s = run_chunk(a, &ctx, %s())\n    if r_%s != 0u8 { os.exit(i32(r_%s)) }' % (n, n, n, n) for n in names)

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    var ctx: Ctx = zero
''' + calls + '''
    try io.print("crypto jks ok")
    ret ok
}
'''

src = ('// e.crypto.jks against pyjks: keystores it writes (key entries with chains, trusted certificates, ASCII,\n'
       '// non-BMP and empty passwords) are parsed and decrypted; a wrong password and a flipped byte are refused;\n'
       '// re-protecting each key with its original salt and re-encoding reproduces pyjks\' bytes exactly (D2803).\n'
       '// K store, E entry. Generated by scripts/gen_jks_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.crypto.jks\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
