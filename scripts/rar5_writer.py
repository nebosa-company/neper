"""A small RAR5 writer for the test oracle: store and the LZ + Huffman method (no filters).

RAR is a proprietary format with no free compressor, so the archives the Neper reader is
tested on are built here from the published format description and then checked by a
second implementation: libarchive's reader (the `tar` that ships with Windows 10 and later,
bsdtar) must extract exactly the bytes that went in, or the archive is not used.
"""
import struct
import zlib

NC, DC, LDC, RC, BC = 306, 64, 16, 44, 20


def vint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            break
    return bytes(out)


def block(htype, flags, body, extra=b'', data_size=None):
    h = vint(htype) + vint(flags | (1 if extra else 0) | (2 if data_size is not None else 0))
    if extra:
        h += vint(len(extra))
    if data_size is not None:
        h += vint(data_size)
    h += body + extra
    h = vint(len(h)) + h
    return struct.pack('<I', zlib.crc32(h)) + h


class Bits:
    def __init__(self):
        self.acc = 0
        self.n = 0

    def put(self, value, count):
        if count:
            self.acc = (self.acc << count) | (value & ((1 << count) - 1))
            self.n += count

    def bytes(self):
        pad = (-self.n) % 8
        value = self.acc << pad
        return value.to_bytes((self.n + pad) // 8, 'big')


def huffman_lengths(freqs, limit=15):
    """Code lengths by the usual two-smallest merge, flattened until they fit `limit`."""
    import heapq
    freqs = list(freqs)
    while True:
        used = [(f, i) for i, f in enumerate(freqs) if f > 0]
        lengths = [0] * len(freqs)
        if len(used) == 0:
            return lengths
        if len(used) == 1:
            lengths[used[0][1]] = 1
            return lengths
        heap = [(f, i, None, None) for f, i in used]
        heapq.heapify(heap)
        counter = len(freqs)
        nodes = {}
        while len(heap) > 1:
            f1, i1, _, _ = heapq.heappop(heap)
            f2, i2, _, _ = heapq.heappop(heap)
            nodes[counter] = (i1, i2)
            heapq.heappush(heap, (f1 + f2, counter, None, None))
            counter += 1
        stack = [(heap[0][1], 0)]
        while stack:
            node, depth = stack.pop()
            if node in nodes:
                stack.append((nodes[node][0], depth + 1))
                stack.append((nodes[node][1], depth + 1))
            else:
                lengths[node] = max(depth, 1)
        if max(lengths) <= limit:
            return lengths
        freqs = [(f + 1) // 2 if f else 0 for f in freqs]


def canonical(lengths):
    """Code value per symbol, shorter codes first and equal lengths in symbol order."""
    codes = [0] * len(lengths)
    code = 0
    for length in range(1, 16):
        for sym, l in enumerate(lengths):
            if l == length:
                codes[sym] = code
                code += 1
        code <<= 1
    return codes


def ensure_two(lengths):
    used = [i for i, l in enumerate(lengths) if l]
    if len(used) < 2:
        for i in range(len(lengths)):
            if i not in used:
                lengths[i] = 1
                used.append(i)
                break
        lengths[used[0]] = 1
    return lengths


def length_slot(code):
    if code < 8:
        return code, 0, 0
    b = code.bit_length()
    lbits = b - 3
    top = (code >> lbits) & 3
    return 4 * (lbits + 1) + top, lbits, code - ((4 | top) << lbits)


def dist_slot(dist):
    d = dist - 1
    if d < 4:
        return d, 0, 0
    b = d.bit_length()
    dbits = b - 2
    top = (d >> dbits) & 1
    return 2 * (dbits + 1) + top, dbits, d - ((2 | top) << dbits)


def adjust(dist):
    return (1 if dist > 0x100 else 0) + (1 if dist > 0x2000 else 0) + (1 if dist > 0x40000 else 0)


def tokenize(history, data, window, reps=True):
    """Greedy LZ over `history + data` returning tokens for `data` only.  A token is
    ('lit', byte) or ('match', length, distance)."""
    full = history + data
    start = len(history)
    table = {}
    for i in range(max(0, start - window), start):
        table.setdefault(full[i:i + 3], []).append(i)
    tokens = []
    i = start
    cache = [0, 0, 0, 0]
    while i < len(full):
        best_len = 0
        best_dist = 0
        key = full[i:i + 3]
        if len(key) == 3:
            for j in reversed(table.get(key, [])[-48:]):
                dist = i - j
                if dist > window:
                    break
                n = 0
                while i + n < len(full) and full[j + n] == full[i + n] and n < 4000:
                    n += 1
                if n - adjust(dist) >= 2 and n > best_len:
                    best_len, best_dist = n, dist
        # prefer a repeated distance when it is as good
        if reps:
            for d in cache:
                if d and d <= i:
                    n = 0
                    while i + n < len(full) and full[i - d + n] == full[i + n] and n < 4000:
                        n += 1
                    if n - adjust(d) >= 2 and n >= best_len:
                        best_len, best_dist = n, d
                        break
        if best_len >= 3 or (best_len >= 2 and best_dist in cache):
            tokens.append(('match', best_len, best_dist))
            if best_dist in cache:
                cache.remove(best_dist)
            cache = [best_dist] + cache[:3]
            for k in range(best_len):
                if len(full[i + k:i + k + 3]) == 3:
                    table.setdefault(full[i + k:i + k + 3], []).append(i + k)
            i += best_len
        else:
            tokens.append(('lit', full[i]))
            if len(key) == 3:
                table.setdefault(key, []).append(i)
            i += 1
    return tokens


def symbols(tokens, cache0=None, last_len0=0):
    """The Huffman symbols of the tokens: (kind, value, extra bits...) records, updating the
    distance cache exactly as a decoder will."""
    cache = list(cache0 or [0, 0, 0, 0])
    last_len = last_len0
    out = []
    for token in tokens:
        if token[0] == 'lit':
            out.append(('main', token[1]))
            continue
        _, length, dist = token
        if dist in cache and cache.index(dist) == 0 and length == last_len:
            out.append(('main', 257))
            continue
        code = length - adjust(dist) - 2
        slot, lbits, lextra = length_slot(code)
        if dist in cache:
            index = cache.index(dist)
            out.append(('main', 258 + index))
            out.append(('len', slot))
            out.append(('bits', lextra, lbits))
            cache.pop(index)
            cache.insert(0, dist)
        else:
            out.append(('main', 262 + slot))
            out.append(('bits', lextra, lbits))
            dslot, dbits, dextra = dist_slot(dist)
            out.append(('dist', dslot))
            if dbits >= 4:
                out.append(('bits', dextra >> 4, dbits - 4))
                out.append(('low', dextra & 15))
            else:
                out.append(('bits', dextra, dbits))
            cache = [dist] + cache[:3]
        last_len = length
    return out, cache, last_len


def table_bits(w, lengths):
    """Writes the 430 code lengths: the 20 bit-length lengths, then the run-length coded body."""
    # run-length code the body with symbols 0-15 (length), 16/17 repeat previous, 18/19 zeros
    body = []
    i = 0
    n = len(lengths)
    while i < n:
        v = lengths[i]
        run = 1
        while i + run < n and lengths[i + run] == v:
            run += 1
        if v == 0 and run >= 3:
            take = min(run, 138)
            if take >= 11:
                body.append((19, take - 11, 7))
            else:
                body.append((18, take - 3, 3))
            i += take
        elif v != 0 and run >= 4:
            body.append(('lit', v))
            take = min(run - 1, 138)
            if take >= 11:
                body.append((17, take - 11, 7))
            else:
                body.append((16, take - 3, 3))
            i += 1 + take
        else:
            body.append(('lit', v))
            i += 1
    freqs = [0] * BC
    for item in body:
        sym = item[1] if item[0] == 'lit' else item[0]
        freqs[sym] += 1
    bl = ensure_two(huffman_lengths(freqs))
    # the 20 four-bit values with the 15 escape for runs of zeros
    i = 0
    while i < BC:
        if bl[i] == 0:
            run = 1
            while i + run < BC and bl[i + run] == 0 and run < 17:
                run += 1
            if run >= 3:
                w.put(15, 4)
                w.put(run - 2, 4)
                i += run
                continue
        if bl[i] == 15:
            w.put(15, 4)
            w.put(0, 4)
        else:
            w.put(bl[i], 4)
        i += 1
    codes = canonical(bl)
    for item in body:
        if item[0] == 'lit':
            w.put(codes[item[1]], bl[item[1]])
        else:
            sym, extra, nbits = item
            w.put(codes[sym], bl[sym])
            w.put(extra, nbits)


class Tables:
    def __init__(self, syms):
        fm = [0] * NC
        fd = [0] * DC
        fl = [0] * LDC
        fr = [0] * RC
        for s in syms:
            if s[0] == 'main':
                fm[s[1]] += 1
            elif s[0] == 'dist':
                fd[s[1]] += 1
            elif s[0] == 'low':
                fl[s[1]] += 1
            elif s[0] == 'len':
                fr[s[1]] += 1
        self.main = ensure_two(huffman_lengths(fm))
        self.dist = ensure_two(huffman_lengths(fd))
        self.low = ensure_two(huffman_lengths(fl))
        self.len = ensure_two(huffman_lengths(fr))
        self.cm = canonical(self.main)
        self.cd = canonical(self.dist)
        self.cl = canonical(self.low)
        self.cr = canonical(self.len)

    def all_lengths(self):
        return self.main + self.dist + self.low + self.len


def encode_blocks(syms, tables, blocks=1, table_in_every_block=True):
    """The compressed bit stream: `blocks` blocks, the first carrying the tables."""
    per = max(1, (len(syms) + blocks - 1) // blocks)
    # split on symbol-group boundaries: a 'main' symbol starts a group
    groups = []
    for s in syms:
        if s[0] == 'main' or not groups:
            groups.append([s])
        else:
            groups[-1].append(s)
    out = bytearray()
    chunks = [groups[i:i + per] for i in range(0, len(groups), per)] or [[]]
    for index, chunk in enumerate(chunks):
        w = Bits()
        present = index == 0 or table_in_every_block
        if present:
            table_bits(w, tables.all_lengths())
        for group in chunk:
            for s in group:
                kind = s[0]
                if kind == 'main':
                    w.put(tables.cm[s[1]], tables.main[s[1]])
                elif kind == 'dist':
                    w.put(tables.cd[s[1]], tables.dist[s[1]])
                elif kind == 'low':
                    w.put(tables.cl[s[1]], tables.low[s[1]])
                elif kind == 'len':
                    w.put(tables.cr[s[1]], tables.len[s[1]])
                else:
                    w.put(s[1], s[2])
        nbits = w.n
        data = w.bytes()
        if not data:
            data = b'\x00'
            nbits = 1
        bit_size = (nbits - 1) % 8
        last = index == len(chunks) - 1
        size = len(data)
        size_bytes = size.to_bytes(3, 'little')[:1 if size < 256 else (2 if size < 65536 else 3)]
        flags = bit_size | ((len(size_bytes) - 1) << 3) | (0x40 if last else 0) | (0x80 if present else 0)
        cksum = 0x5A ^ flags
        for b in size_bytes:
            cksum ^= b
        out += bytes([flags, cksum]) + size_bytes + data
    return bytes(out)


def file_header(name, data, packed, method, unpacked, solid=False, directory=False, dict_code=3):
    comp = 0 | ((1 if solid else 0) << 6) | (method << 7) | (dict_code << 10)
    flags = 0x4 | (1 if directory else 0)
    body = vint(flags) + vint(unpacked) + vint(0x20) + struct.pack('<I', zlib.crc32(data)) + vint(comp) + vint(1) + vint(len(name)) + name
    return block(2, 0, body, data_size=len(packed)) + packed


def build_rar5(files, solid=False, blocks=1, table_every_block=True, reps=True):
    """files: [(name, data or None for a directory)].  Compressed unless `store`-named."""
    out = b'Rar!\x1a\x07\x01\x00' + block(1, 0, vint(0))
    history = b''
    cache = [0, 0, 0, 0]
    last_len = 0
    first = True
    for name, data in files:
        raw = name.encode('utf-8')
        if data is None:
            out += file_header(raw, b'', b'', 0, 0, directory=True)
            continue
        if name.startswith('store/') or len(data) == 0:
            out += file_header(raw, data, data, 0, len(data))   # a stored file never enters the window
            continue
        use_solid = solid and not first
        tokens = tokenize(history if use_solid else b'', data, 1 << 20, reps=reps)
        syms, new_cache, new_last = symbols(tokens, None, 0)
        tables = Tables(syms)
        packed = encode_blocks(syms, tables, blocks=blocks, table_in_every_block=table_every_block)
        out += file_header(raw, data, packed, 3, len(data), solid=use_solid)
        history = (history + data) if solid else b''
        if solid:
            cache, last_len = new_cache, new_last
        first = False
    out += block(5, 0, vint(0))
    return out
