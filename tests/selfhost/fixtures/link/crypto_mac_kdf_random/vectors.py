# Regenerates the vector arrays in src/main.e; paste its output over them.
import hmac, hashlib, struct

def arr(name, h):
    return "    let %s: [%d]u8 = [%d]u8{ %s }" % (name, len(h), len(h), ", ".join(str(b) for b in h))

out = []
# RFC 4231 test case 2 (key "Jefe", data "what do ya want for nothing?") and case 6 (131-byte key)
key2 = b"Jefe"; data2 = b"what do ya want for nothing?"
out.append(arr("hmac256_jefe", hmac.new(key2, data2, hashlib.sha256).digest()))
out.append(arr("hmac512_jefe", hmac.new(key2, data2, hashlib.sha512).digest()))
key6 = bytes([0xaa]) * 131; data6 = b"Test Using Larger Than Block-Size Key - Hash Key First"
out.append(arr("hmac256_long", hmac.new(key6, data6, hashlib.sha256).digest()))
out.append(arr("hmac512_long", hmac.new(key6, data6, hashlib.sha512).digest()))

def hkdf_extract(salt, ikm, algo):
    if not salt:
        salt = bytes(algo().digest_size)
    return hmac.new(salt, ikm, algo).digest()

def hkdf_expand(prk, info, length, algo):
    t = b""; okm = b""; i = 1
    while len(okm) < length:
        t = hmac.new(prk, t + info + bytes([i]), algo).digest()
        okm += t; i += 1
    return okm[:length]

# RFC 5869 test case 1
ikm = bytes([0x0b]) * 22; salt = bytes(range(0x00, 0x0d)); info = bytes(range(0xf0, 0xfa))
prk = hkdf_extract(salt, ikm, hashlib.sha256)
out.append(arr("hkdf_prk", prk))
out.append(arr("hkdf_okm", hkdf_expand(prk, info, 42, hashlib.sha256)))
# test case 3: empty salt and info
prk3 = hkdf_extract(b"", ikm, hashlib.sha256)
out.append(arr("hkdf_prk3", prk3))
out.append(arr("hkdf_okm3", hkdf_expand(prk3, b"", 42, hashlib.sha256)))
prk512 = hkdf_extract(salt, ikm, hashlib.sha512)
out.append(arr("hkdf512_okm", hkdf_expand(prk512, info, 82, hashlib.sha512)))

# ChaCha20 RFC 8439 2.4.2: key 00..1f, nonce 00 00 00 00 00 00 00 4a 00 00 00 00, counter 1, 114-byte plaintext
def rotl(x, n): return ((x << n) | (x >> (32 - n))) & 0xffffffff
def qr(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & 0xffffffff; s[d] = rotl(s[d] ^ s[a], 16)
    s[c] = (s[c] + s[d]) & 0xffffffff; s[b] = rotl(s[b] ^ s[c], 12)
    s[a] = (s[a] + s[b]) & 0xffffffff; s[d] = rotl(s[d] ^ s[a], 8)
    s[c] = (s[c] + s[d]) & 0xffffffff; s[b] = rotl(s[b] ^ s[c], 7)
def block(key, nonce, counter):
    st = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574] + list(struct.unpack('<8I', key)) + [counter] + list(struct.unpack('<3I', nonce))
    w = st[:]
    for _ in range(10):
        qr(w, 0, 4, 8, 12); qr(w, 1, 5, 9, 13); qr(w, 2, 6, 10, 14); qr(w, 3, 7, 11, 15)
        qr(w, 0, 5, 10, 15); qr(w, 1, 6, 11, 12); qr(w, 2, 7, 8, 13); qr(w, 3, 4, 9, 14)
    return struct.pack('<16I', *[(w[i] + st[i]) & 0xffffffff for i in range(16)])
key = bytes(range(32)); nonce = bytes([0, 0, 0, 0, 0, 0, 0, 0x4a, 0, 0, 0, 0])
stream = block(key, nonce, 1) + block(key, nonce, 2)
out.append(arr("chacha_stream", stream[:100]))
# RFC 8439 2.3.2 single block: nonce 00 00 00 09 00 00 00 4a 00 00 00 00, counter 1
nonce2 = bytes([0, 0, 0, 9, 0, 0, 0, 0x4a, 0, 0, 0, 0])
out.append(arr("chacha_block", block(key, nonce2, 1)))
print(chr(10).join(out))
