import cramjam, xxhash, sys

M = (1 << 64) - 1
def lcg(state):
    state = (state * 6364136223846793005 + 1442695040888963407) & M
    return state, state >> 33

# 1: repetitive 300-byte text.
text = (b"the quick brown fox jumps over the lazy dog; " * 7)[:300]
assert len(text) == 300
block = bytes(cramjam.lz4.compress_block(text, store_size=False))
frame = bytes(cramjam.lz4.compress(text))

# 2: 2 KB LCG buffer with runs and repeats (mirrored in the fixture).
def gen(n):
    out = bytearray()
    state = 42
    while len(out) < n:
        state, r = lcg(state)
        kind = r % 4
        if kind == 0:
            state, v = lcg(state)
            out += bytes([v & 255]) * (5 + r % 20)
        elif kind == 1 and len(out) > 16:
            start = (r >> 8) % (len(out) - 8)
            out += out[start:start + 8 + (r >> 4) % 24]
        else:
            k = 0
            while k < 1 + r % 8:
                state, v = lcg(state)
                out.append(v & 255)
                k += 1
    return bytes(out[:n])

buf = gen(2048)
# 3: 64 incompressible bytes.
def rnd(n, seed):
    out = bytearray(); state = seed
    for _ in range(n):
        state, v = lcg(state)
        out.append(v & 255)
    return bytes(out)
inc = rnd(64, 7)
assert len(bytes(cramjam.lz4.compress_block(inc, store_size=False))) == 66, len(bytes(cramjam.lz4.compress_block(inc, store_size=False)))
assert bytes(cramjam.lz4.compress_block(b"", store_size=False)) == b"\x00"

def esc(b):
    return "".join("\\x%02x" % c for c in b)

print("buf fnv1a64 =", hex(__import__('functools').reduce(lambda h, c: ((h ^ c) * 1099511628211) & M, buf, 0xcbf29ce484222325)))
print("cramjam block len", len(block), "frame len", len(frame))
print("xxh32 empty", hex(xxhash.xxh32(b"", 0).intdigest()), "a", hex(xxhash.xxh32(b"a", 0).intdigest()), "text", xxhash.xxh32(text, 0).intdigest(), "buf", xxhash.xxh32(buf, 0).intdigest())
print("frame flags", frame[4:6].hex())
with open(sys.argv[1] if len(sys.argv) > 1 else "vectors.txt", "w") as f:
    f.write("TEXT " + text.decode() + "\n")
    f.write("BLOCK " + esc(block) + "\n")
    f.write("FRAME " + esc(frame) + "\n")
    f.write("BUF_FNV %d\n" % __import__('functools').reduce(lambda h, c: ((h ^ c) * 1099511628211) & M, buf, 0xcbf29ce484222325))
    f.write("BUF_XXH %d\n" % xxhash.xxh32(buf, 0).intdigest())
    f.write("TEXT_XXH %d\n" % xxhash.xxh32(text, 0).intdigest())
    f.write("INC_XXH %d\n" % xxhash.xxh32(inc, 0).intdigest())
