# Reference vectors: AES-GCM via a from-scratch implementation checked against the
# NIST GCM spec test case 3/4 values, and ChaCha20-Poly1305 from RFC 8439 2.8.2.
import struct

def arr(name, h):
    return "    let %s: [%d]u8 = [%d]u8{ %s }" % (name, len(h), len(h), ", ".join(str(b) for b in h))

# --- AES (pure Python) ---
sbox = [
 0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
 0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
 0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
 0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
 0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
 0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
 0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
 0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16]

def xt(x):
    x <<= 1
    return (x ^ 0x1b) & 0xff if x & 0x100 else x

def expand(key):
    n = len(key) // 4
    w = [list(key[4*i:4*i+4]) for i in range(n)]
    rcon = 1
    total = 4 * (n + 7)
    for i in range(n, total):
        t = w[i-1][:]
        if i % n == 0:
            t = [sbox[t[1]] ^ rcon, sbox[t[2]], sbox[t[3]], sbox[t[0]]]
            rcon = xt(rcon)
        elif n > 6 and i % n == 4:
            t = [sbox[b] for b in t]
        w.append([w[i-n][j] ^ t[j] for j in range(4)])
    return w, n + 6

def encrypt(key, block):
    w, rounds = expand(key)
    s = list(block)
    def ark(r):
        for c in range(4):
            for j in range(4):
                s[c*4+j] ^= w[r*4+c][j]
    ark(0)
    for r in range(1, rounds + 1):
        s[:] = [sbox[b] for b in s]
        sh = [0]*16
        for c in range(4):
            for row in range(4):
                sh[c*4+row] = s[((c+row) % 4)*4+row]
        if r != rounds:
            for c in range(4):
                a0,a1,a2,a3 = sh[c*4:c*4+4]
                s[c*4] = xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3
                s[c*4+1] = a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3
                s[c*4+2] = a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3
                s[c*4+3] = xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3)
        else:
            s[:] = sh
        ark(r)
    return bytes(s)

# FIPS-197 check: AES-128 key 000102..0f, plaintext 00112233..ff -> 69c4e0d86a7b0430d8cdb78070b4c55a
assert encrypt(bytes(range(16)), bytes(range(0, 256, 17))).hex() == '69c4e0d86a7b0430d8cdb78070b4c55a'

def gf_mul(x, y):
    R = 0xe1 << 120
    z = 0; v = y
    for i in range(128):
        if (x >> (127 - i)) & 1:
            z ^= v
        carry = v & 1
        v >>= 1
        if carry:
            v ^= R
    return z

def ghash(h, data):
    y = 0
    for i in range(0, len(data), 16):
        block = data[i:i+16].ljust(16, b'\0')
        y = gf_mul(y ^ int.from_bytes(block, 'big'), h)
    return y

def gcm_seal(key, nonce, aad, plain):
    h = int.from_bytes(encrypt(key, bytes(16)), 'big')
    out = bytearray()
    counter = 2
    for i in range(0, len(plain), 16):
        ks = encrypt(key, nonce + counter.to_bytes(4, 'big'))
        chunk = plain[i:i+16]
        out += bytes(a ^ b for a, b in zip(chunk, ks))
        counter += 1
    lengths = (len(aad) * 8).to_bytes(8, 'big') + (len(out) * 8).to_bytes(8, 'big')
    y = ghash(h, aad.ljust((len(aad) + 15) // 16 * 16, b'\0') + bytes(out).ljust((len(out) + 15) // 16 * 16, b'\0') + lengths)
    j0 = encrypt(key, nonce + (1).to_bytes(4, 'big'))
    tag = (y ^ int.from_bytes(j0, 'big')).to_bytes(16, 'big')
    return bytes(out) + tag

# NIST GCM spec test case 4 (AES-128, 60-byte plaintext, 20-byte AAD)
k4 = bytes.fromhex('feffe9928665731c6d6a8f9467308308')
p4 = bytes.fromhex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39')
aad4 = bytes.fromhex('feedfacedeadbeeffeedfacedeadbeefabaddad2')
iv4 = bytes.fromhex('cafebabefacedbaddecaf888')
sealed4 = gcm_seal(k4, iv4, aad4, p4)
assert sealed4.hex() == '42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091' + '5bc94fbc3221a5db94fae95ae7121a47'
# test case 16 (AES-256)
k16 = bytes.fromhex('feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308')
sealed16 = gcm_seal(k16, iv4, aad4, p4)
assert sealed16.hex() == '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662' + '76fc6ece0f4e1768cddf8853bb2d551b'

out = [arr("gcm_key128", k4), arr("gcm_plain", p4), arr("gcm_aad", aad4), arr("gcm_nonce", iv4), arr("gcm_sealed128", sealed4), arr("gcm_key256", k16), arr("gcm_sealed256", sealed16)]

# RFC 8439 2.8.2
key = bytes.fromhex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f')
nonce = bytes.fromhex('070000004041424344454647')
aad = bytes.fromhex('50515253c0c1c2c3c4c5c6c7')
plain = b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
sealed = bytes.fromhex('d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116' + '1ae10b594f09e26a7e902ecbd0600691')
out += [arr("cp_key", key), arr("cp_nonce", nonce), arr("cp_aad", aad), arr("cp_plain", plain), arr("cp_sealed", sealed)]
print("\n".join(out))
