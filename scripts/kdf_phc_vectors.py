"""Generate tests/selfhost/fixtures/link/crypto_kdf_phc/src/main.e (L117, D2520).

The oracle is argon2-cffi (the reference C library) for Argon2d, Argon2i and Argon2id
at versions 0x10 and 0x13 with their PHC strings, the bcrypt package for `$2a$`, `$2b$`
and `$2y$` strings, and hashlib.scrypt for scrypt with PHC strings assembled here with
the `base64` module.  Install them with
`python -m pip install --target DIR argon2-cffi bcrypt` and run with PYLIBS=DIR.
"""
import base64
import hashlib
import os
import random
import sys
from pathlib import Path

sys.path.insert(0, os.environ.get('PYLIBS', ''))
import argon2  # noqa: E402
import argon2.low_level as low  # noqa: E402
import bcrypt  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests/selfhost/fixtures/link/crypto_kdf_phc/src/main.e'
rng = random.Random(2520)


def esc(data):
    if isinstance(data, str):
        data = data.encode('latin-1')
    out = []
    for b in data:
        if 48 <= b <= 57 or 65 <= b <= 90 or 97 <= b <= 122 or b in b'$,=+/-_.':
            out.append(chr(b))
        else:
            out.append('\\x%02x' % b)
    return '"' + ''.join(out) + '"'


def b64(data):
    return base64.b64encode(data).decode().rstrip('=')


lines = []
code = [20]


def check(expr):
    lines.append('    if !(%s) { os.exit(%di32) }' % (expr, code[0]))
    code[0] += 1
    if code[0] > 250:
        raise SystemExit('too many checks')


def rand_bytes(n):
    return bytes(rng.randrange(256) for _ in range(n))


KINDS = {'d': (low.Type.D, 'D'), 'i': (low.Type.I, 'I'), 'id': (low.Type.ID, 'Id')}

# --- Argon2 PHC strings: every kind, both versions, lanes, tag lengths.
argon_cases = []
for kind in ('d', 'i', 'id'):
    for version in (19, 16):
        for (t, m, p, taglen) in ((1, 8, 1, 16), (2, 16, 2, 32), (3, 32, 4, 24), (1, 64, 1, 64), (2, 40, 3, 4), (4, 24, 1, 33)):
            argon_cases.append((kind, version, t, m, p, taglen))
for (kind, version, t, m, p, taglen) in argon_cases:
    pw = bytes(rng.choice(b'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP0123456789 !#') for _ in range(rng.randrange(0, 24)))
    salt = rand_bytes(rng.choice((8, 16, 20)))
    enc = low.hash_secret(pw, salt, t, m, p, taglen, KINDS[kind][0], version).decode()
    assert low.verify_secret(enc.encode(), pw, KINDS[kind][0])
    check('argon_ok(%s, %s, memory)' % (esc(pw), esc(enc)))
    wrong = pw + b'x'
    check('argon_false(%s, %s, memory)' % (esc(wrong), esc(enc)))
    if version == 19:
        check('argon_roundtrip(.%s, %s, %s, %du32, %du32, %du32, %dusize, %s, memory)' % (
            KINDS[kind][1], esc(pw), esc(salt), t, m, p, taglen, esc(enc)))

# --- RFC 9106 section 5 inputs (secret and associated data) at 0x13.
RFC_TAGS = {
    'D': '512b391b6f1162975371d30919734294f868e3be3984f3c1a13a4db9fabe4acb',
    'I': 'c814d9d1dc7f37aa13f0d77f2494bda1c8de6b016dd388d29952a4c4672b6ce8',
    'Id': '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
}
for name, tag in RFC_TAGS.items():
    check('rfc_ok(.%s, %s, memory)' % (name, esc(bytes.fromhex(tag))))

# --- Hostile and malformed Argon2 strings.
good = low.hash_secret(b'password', b'saltsalt', 1, 8, 1, 16, low.Type.ID, 19).decode()
assert good.startswith('$argon2id$v=19$m=8,t=1,p=1$')
head = '$argon2id$v=19$m=8,t=1,p=1$'
salt22 = good.split('$')[4]
tag22 = good.split('$')[5]
bad = [
    ('$argon3id$v=19$m=8,t=1,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2x$v=19$m=8,t=1,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=18$m=8,t=1,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=08,t=1,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=0,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=0$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=7,t=1,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=2$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$' + tag22 + '$extra', 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$' + tag22 + '=', 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$' + tag22[:-1] + '!', 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$' + tag22[:-1] + 'B', 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + b64(b'short') + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$' + b64(b'abc'), 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$', 'Invalid'),
    ('$argon2id$v=19$m=8,t=1,p=1$$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=4294967296,p=1$' + salt22 + '$' + tag22, 'Invalid'),
    ('$argon2id$v=19$m=8,t=1000001,p=1$' + salt22 + '$' + tag22, 'TooLarge'),
    ('$argon2id$v=19$m=999999999,t=1,p=1$' + salt22 + '$' + tag22, 'TooSmall'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + b64(b'0' * 65) + '$' + tag22, 'TooLarge'),
    ('$argon2id$v=19$m=8,t=1,p=1$' + salt22 + '$' + b64(b'0' * 65), 'TooLarge'),
    ('$argon2id$v=19$m=8,t=1,p=16777216$' + salt22 + '$' + tag22, 'Invalid'),
    ('', 'Invalid'),
    ('$', 'Invalid'),
]
for text, error in bad:
    check('argon_err(%s, %s, memory, kdf.%s)' % (esc('password'), esc(text), error))
# every prefix and every single-byte change of a good string is refused
check('argon_mutations(%s, memory)' % esc(good))

# --- scrypt PHC strings against hashlib.scrypt.
scrypt_good = None
for (ln, r, p, taglen) in ((1, 1, 1, 16), (4, 8, 1, 32), (6, 2, 3, 20), (10, 8, 1, 64), (3, 4, 2, 5)):
    pw = bytes(rng.choice(b'abcdefghijklmnopqrstuvwxyz0123456789') for _ in range(rng.randrange(0, 16)))
    salt = rand_bytes(rng.choice((4, 16, 32)))
    tag = hashlib.scrypt(pw, salt=salt, n=1 << ln, r=r, p=p, dklen=taglen, maxmem=1 << 28)
    enc = '$scrypt$ln=%d,r=%d,p=%d$%s$%s' % (ln, r, p, b64(salt), b64(tag))
    if scrypt_good is None:
        scrypt_good = enc
    check('scrypt_ok(%s, %s, scratch)' % (esc(pw), esc(enc)))
    check('scrypt_false(%s, %s, scratch)' % (esc(pw + b'!'), esc(enc)))
    check('scrypt_roundtrip(%dusize, %dusize, %dusize, %s, %s, %dusize, %s, scratch)' % (1 << ln, r, p, esc(pw), esc(salt), taglen, esc(enc)))
salt = b'NaCl'
enc = '$scrypt$ln=10,r=8,p=16$%s$%s' % (b64(salt), b64(hashlib.scrypt(b'password', salt=salt, n=1024, r=8, p=16, dklen=64, maxmem=1 << 28)))
check('scrypt_ok(%s, %s, scratch)' % (esc('password'), esc(enc)))
ghead = '$scrypt$ln=4,r=8,p=1$'
gparts = scrypt_good.split('$')
sbad = [
    ('$scrypt$ln=0,r=8,p=1$' + gparts[3] + '$' + gparts[4], 'Invalid'),
    ('$scrypt$ln=4,r=0,p=1$' + gparts[3] + '$' + gparts[4], 'Invalid'),
    ('$scrypt$ln=4,r=8,p=0$' + gparts[3] + '$' + gparts[4], 'Invalid'),
    ('$scrypt$ln=33,r=8,p=1$' + gparts[3] + '$' + gparts[4], 'TooLarge'),
    ('$scrypt$ln=4,r=1025,p=1$' + gparts[3] + '$' + gparts[4], 'TooLarge'),
    ('$scrypt$ln=4,r=8,p=1025$' + gparts[3] + '$' + gparts[4], 'TooLarge'),
    ('$scrypt$ln=30,r=8,p=1$' + gparts[3] + '$' + gparts[4], 'TooSmall'),
    ('$scrypt$ln=4,r=8,p=1$' + gparts[3], 'Invalid'),
    ('$scrypt$ln=4,r=8,p=1$' + gparts[3] + '$', 'Invalid'),
    ('$scrypt$n=4,r=8,p=1$' + gparts[3] + '$' + gparts[4], 'Invalid'),
    ('$scrypt$ln=4,r=8,p=1$' + gparts[3] + '$' + gparts[4] + '$x', 'Invalid'),
    ('$scrypt$ln=4,r=8,p=1$' + gparts[3] + '=$' + gparts[4], 'Invalid'),
    ('', 'Invalid'),
]
for text, error in sbad:
    check('scrypt_err(%s, %s, scratch, kdf.%s)' % (esc('password'), esc(text), error))
check('scrypt_mutations(%s, scratch)' % esc(scrypt_good_text := scrypt_good))

# --- bcrypt against the bcrypt package: costs, prefixes, high bytes, mutations.
for i, cost in enumerate((4, 5, 6, 4, 7)):
    pw = bytes(rng.choice(b'abcdefghijklmnopqrstuvwxyzABC0123456789!@#') for _ in range(rng.randrange(1, 40)))
    if i == 3:
        pw = bytes([0xc3, 0xa9, 0xe2, 0x82, 0xac, 0xff, 0x01])
    enc = bcrypt.hashpw(pw, bcrypt.gensalt(cost)).decode()
    assert bcrypt.checkpw(pw, enc.encode())
    for prefix in ('2b', '2a', '2y'):
        variant = '$' + prefix + enc[3:]
        check('bcrypt_ok(%s, %s)' % (esc(pw), esc(variant)))
    check('bcrypt_false(%s, %s)' % (esc(pw + b'x'), esc(enc)))
    check('bcrypt_roundtrip(%s, %s, %du32)' % (esc(pw), esc(enc), cost))
bc = bcrypt.hashpw(b'hunter2', bcrypt.gensalt(4)).decode()
check('bcrypt_mutations(%s)' % esc(bc))
for text in ('$2x$04$' + bc[7:], '$2b$03$' + bc[7:], '$2b$32$' + bc[7:], '$2b$4$' + bc[7:],
             bc[:-1], bc + 'a', '$2b$04$' + bc[7:29] + '!' + bc[30:], '', '$2b$04$'):
    check('!kdf.bcrypt_verify(%s, %s)' % (esc('hunter2'), esc(text)))
check('kdf.bcrypt_verify(%s, %s)' % (esc('hunter2'), esc(bc)))

body = '\n'.join(lines)
TEMPLATE = (ROOT / 'scripts' / 'kdf_phc_fixture_head.e').read_text(encoding='utf-8')
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(TEMPLATE.replace('@@CHECKS@@', body), encoding='utf-8', newline='\n')
print('wrote', OUT, 'checks', code[0] - 20)
