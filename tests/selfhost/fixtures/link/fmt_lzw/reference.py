# An independent GIF-style LZW encoder, to compare bytes with lib/e/fmt/lzw.e.
def encode(data, width, lsb):
    clear = 1 << width
    end = clear + 1
    out = bytearray()
    bits = 0
    nbits = 0
    code_width = width + 1
    table = {}
    nxt = end + 1
    def emit(code):
        nonlocal bits, nbits, out
        if lsb:
            bits |= code << nbits
        else:
            bits = (bits << code_width) | code
        nbits += code_width
        while nbits >= 8:
            if lsb:
                out.append(bits & 255)
                bits >>= 8
            else:
                out.append((bits >> (nbits - 8)) & 255)
                bits &= (1 << (nbits - 8)) - 1
            nbits -= 8
    emit(clear)
    current = None
    for b in data:
        if current is None:
            current = b
            continue
        key = (current, b)
        if key in table:
            current = table[key]
        else:
            emit(current)
            if nxt < 4096:
                table[key] = nxt
                nxt += 1
                if nxt > (1 << code_width) and code_width < 12:
                    code_width += 1
            else:
                emit(clear)
                table = {}
                nxt = end + 1
                code_width = width + 1
            current = b
    if current is not None:
        emit(current)
    emit(end)
    if nbits > 0:
        if lsb:
            out.append(bits & 255)
        else:
            out.append((bits << (8 - nbits)) & 255)
    return bytes(out)

text = b"TOBEORNOTTOBEORTOBEORNOT#TOBEORNOTTOBEORTOBEORNOT"
pixels = bytes((i * 7 + i // 13) % 4 for i in range(400))
state = 12345
long = bytearray()
for i in range(20000):
    state = (state * 1103515245 + 12345) & 0xFFFFFFFF
    long.append((state >> 16) & 255)
import hashlib
for name, data, width, lsb in [("text_lsb", text, 8, True), ("text_msb", text, 8, False), ("pixels", pixels, 2, True), ("long_lsb", bytes(long), 8, True), ("long_msb", bytes(long), 8, False)]:
    enc = encode(data, width, lsb)
    print(name, len(enc), hashlib.sha256(enc).hexdigest()[:16])
