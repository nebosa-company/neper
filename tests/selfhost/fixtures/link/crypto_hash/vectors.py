# Regenerates the digest arrays in src/main.e from Python's hashlib.
import hashlib
def arr(name, h): return "    let %s: [%d]u8 = [%d]u8{ %s }" % (name, len(h), len(h), ", ".join(str(b) for b in h))
for name, data in [("abc", b"abc"), ("empty", b""), ("long", b"a" * 1000), ("two", b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")]:
    for algo in ["sha256", "sha512", "sha3_256", "sha3_512", "sha1", "md5"]:
        print(arr(algo + "_" + name, getattr(hashlib, algo)(data).digest()))
