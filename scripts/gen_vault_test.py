"""Write neperos/src/vault_test.e (D2252, C116): vault.e against independent implementations.

  python scripts/gen_vault_test.py

PBKDF2-HMAC-SHA-256 from hashlib and AES-256-GCM from Python's cryptography package, with a fixed key,
nonce and plaintext, so the program can require byte-for-byte equal records (and open the package's), and
refuse a wrong key, a flipped byte and a record under another name. Every check has its own exit code. The
program is host-independent (it only computes) and runs natively on every host, and on NeperOS.
"""
import hashlib
import pathlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]


def arr(name, data):
    lines.append("    let %s: [%d]u8 = [%d]u8{ %s }" % (name, len(data), len(data), ", ".join(str(b) for b in data)))


def check(condition):
    code[0] += 1
    lines.append("    if %s { os.exit(%d) }" % (condition, code[0]))


password = b'correct horse'
salt = bytes(range(16))
iterations = 1000
key = hashlib.pbkdf2_hmac('sha256', password, salt, iterations, 32)
nonce = bytes(range(100, 112))
plain = b'\x01\x0aNeper Bank\x0asam.rivera\x15correct-horse-battery'
record = b'\x01' + nonce + AESGCM(key).encrypt(nonce, plain, b'l3')
arr('salt', salt)
arr('want_key', key)
arr('nonce', nonce)
arr('plain', plain)
arr('want_record', record)
lines.append('    let password = "%s"' % password.decode())
lines.append('    let (key, derive_error) = vault.derive(password, salt[0..], %du32)' % iterations)
check('derive_error != ok || !same(key[0..], want_key[0..])')
lines.append('    var sealed: [128]u8 = zero')
lines.append('    let (sealed_len, seal_error) = vault.seal(key, nonce[0..], "l3", plain[0..], sealed[0..])')
check('seal_error != ok || !same(sealed[..sealed_len], want_record[0..])')
lines.append('    var opened: [128]u8 = zero')
lines.append('    let (opened_len, open_error) = vault.open(key, "l3", want_record[0..], opened[0..])')
check('open_error != ok || !same(opened[..opened_len], plain[0..])')
lines.append('    let (_n1, _e1) = vault.open(key, "l4", want_record[0..], opened[0..])')
check('_e1 != vault.WrongPassword')
lines.append('    var other_key = key')
lines.append('    other_key[0] = other_key[0] ^ 1u8')
lines.append('    let (_n2, _e2) = vault.open(other_key, "l3", want_record[0..], opened[0..])')
check('_e2 != vault.WrongPassword')
lines.append('    var damaged: [128]u8 = zero')
lines.append('    var di = 0usize')
lines.append('    while di < want_record.len {')
lines.append('        damaged[di] = want_record[di]')
lines.append('        di += 1usize')
lines.append('    }')
lines.append('    damaged[20] = damaged[20] ^ 1u8')
lines.append('    let (_n3, _e3) = vault.open(key, "l3", damaged[..want_record.len], opened[0..])')
check('_e3 != vault.WrongPassword')
lines.append('    let (_n4, _e4) = vault.open(key, "l3", want_record[..10], opened[0..])')
check('_e4 != vault.Damaged')
# The meta file, made and unlocked here, opened by a wrong password.
lines.append('    var meta: [80]u8 = zero')
lines.append('    let (meta_len, meta_error) = vault.meta_make(key, salt[0..], %du32, nonce[0..], meta[0..])' % iterations)
check('meta_error != ok || meta_len != 64usize || vault.meta_iterations(meta[..meta_len]) != %du32' % iterations)
lines.append('    let (unlocked, unlock_error) = vault.meta_unlock(meta[..meta_len], password)')
check('unlock_error != ok || !same(unlocked[0..], want_key[0..])')
lines.append('    let (_n5, _e5) = vault.meta_unlock(meta[..meta_len], "correct horsf")')
check('_e5 != vault.WrongPassword')
lines.append('    let (_n6, _e6) = vault.meta_unlock(meta[..20], password)')
check('_e6 != vault.Damaged')

body = '\n'.join(lines)
source = '''// The Secure vault's cryptography (vault.e, D2252) against hashlib and Python's cryptography package
// (scripts/gen_vault_test.py writes this file): the key from a password, records byte-for-byte equal to
// AES-256-GCM's, the meta file made and unlocked, and the refusals -- a wrong key, a flipped byte, another
// record name, a short record, a wrong password. Every check has its own exit code.
use e.os
use e.mem
use vault

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
%s
    os.exit(0)
    ret ok
}
''' % body
(root / 'neperos' / 'src' / 'vault_test.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote neperos/src/vault_test.e with', code[0], 'checks')
