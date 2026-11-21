"""Writes the SAS7BDAT variants that no ReadStat writer produces, from the files scripts/make_haven_sas2.c writes:
RDC (SASYZCR2) row compression and big-endian byte order, 32 and 64 bit. Every file is checked by haven afterwards
(scripts/r_oracle/groups/haven_sas.R reads each one and the oracle compares the numbers).

  python scripts/make_haven_sas3.py tests/data/haven

reads rle32, rle64 and raw64 .sas7bdat and writes rdc32, rdc64, rle32be, rdc64be, raw64be. A file is re-laid page by
page: the subheader pointers, the subheaders (rows when compressed) and, for uncompressed files, the raw rows."""
import struct
import sys

SIG = {0xF7F7F7F7: 'rowsize', 0xF6F6F6F6: 'colsize', 0xFFFFFC00: 'counts', 0xFFFFFFFD: 'text',
       0xFFFFFFFF: 'names', 0xFFFFFFFC: 'attrs', 0xFFFFFBFE: 'format', 0xFFFFFFFE: 'list'}


def rle_unpack(src):
    out = bytearray()
    p = 0
    while p < len(src):
        c = src[p]; p += 1
        cmd, ln = c >> 4, c & 15
        if cmd == 0: n = src[p] + 64 + ln * 256; p += 1; out += src[p:p + n]; p += n
        elif cmd == 1: n = src[p] + 64 + ln * 256 + 4096; p += 1; out += src[p:p + n]; p += n
        elif cmd == 2: n = ln + 96; out += src[p:p + n]; p += n
        elif cmd == 4: n = src[p] + 18 + ln * 256; out += bytes([src[p + 1]]) * n; p += 2
        elif cmd == 5: n = src[p] + 17 + ln * 256; p += 1; out += b'@' * n
        elif cmd == 6: n = src[p] + 17 + ln * 256; p += 1; out += b' ' * n
        elif cmd == 7: n = src[p] + 17 + ln * 256; p += 1; out += b'\0' * n
        elif cmd == 8: n = ln + 1; out += src[p:p + n]; p += n
        elif cmd == 9: n = ln + 17; out += src[p:p + n]; p += n
        elif cmd == 10: n = ln + 33; out += src[p:p + n]; p += n
        elif cmd == 11: n = ln + 49; out += src[p:p + n]; p += n
        elif cmd == 12: n = ln + 3; out += bytes([src[p]]) * n; p += 1
        elif cmd == 13: out += b'@' * (ln + 2)
        elif cmd == 14: out += b' ' * (ln + 2)
        elif cmd == 15: out += b'\0' * (ln + 2)
        else: raise ValueError('rle command %d' % cmd)
    return bytes(out)


def rle_pack(row):
    out = bytearray()
    lit = bytearray()

    def flush():
        i = 0
        while i < len(lit):
            n = len(lit) - i
            if n >= 64:
                n = min(n, 64 + 255 + 256 * 15)
                v = n - 64
                out.append(((v >> 8) & 15)); out.append(v & 255)
            elif n >= 49: n = 49 + min(n - 49, 15); out.append(0xB0 | (n - 49)); n = n
            elif n >= 33: n = 33 + min(n - 33, 15); out.append(0xA0 | (n - 33))
            elif n >= 17: n = 17 + min(n - 17, 15); out.append(0x90 | (n - 17))
            else: out.append(0x80 | (n - 1))
            out.extend(lit[i:i + n])
            i += n
        lit.clear()

    i = 0
    while i < len(row):
        j = i
        while j < len(row) and row[j] == row[i]: j += 1
        r = j - i
        if r >= 3:
            flush()
            b = row[i]
            while r >= 3:
                if r <= 17 and b in (0, 32, 64) and r >= 2:
                    n = r; out.append({0: 0xF0, 32: 0xE0, 64: 0xD0}[b] | (n - 2))
                elif r >= 17 and b in (0, 32, 64):
                    n = min(r, 17 + 255 + 256 * 15); v = n - 17
                    out.append({0: 0x70, 32: 0x60, 64: 0x50}[b] | (v >> 8)); out.append(v & 255)
                elif r <= 18:
                    n = r; out.append(0xC0 | (n - 3)); out.append(b)
                else:
                    n = min(r, 18 + 255 + 256 * 15); v = n - 18
                    out.append(0x40 | (v >> 8)); out.append(v & 255); out.append(b)
                r -= n
            i = j - r
            if r: lit += row[i:j]; i = j
        else:
            lit += row[i:j]; i = j
    flush()
    return bytes(out)


def rdc_pack(row):
    """SASYZCR2: 16-bit control words (bit 15 first), 1 = command; runs, long runs, short and long copies, literals."""
    items = []  # (is_command, bytes)
    i = 0
    n = len(row)
    while i < n:
        j = i
        while j < n and row[j] == row[i]: j += 1
        run = j - i
        if run >= 3:
            run = min(run, 19 + 15 + 255 * 16)
            if run <= 18:
                items.append((1, bytes([run - 3, row[i]])))
            else:
                v = run - 19
                items.append((1, bytes([0x10 | (v & 15), v >> 4, row[i]])))
            i += run
            continue
        best = (0, 0)
        for back in range(3, min(i, 3 + 15 + 255 * 16) + 1):
            m = 0
            while i + m < n and m < back and m < 271 and row[i + m] == row[i - back + m]: m += 1
            if m >= 3 and m > best[0]: best = (m, back)
        m, back = best
        if m >= 3:
            v = back - 3
            if m <= 15:
                items.append((1, bytes([(m << 4) | (v & 15), v >> 4])))
            else:
                items.append((1, bytes([0x20 | (v & 15), v >> 4, m - 16])))
            i += m
        else:
            items.append((0, bytes([row[i]])))
            i += 1
    out = bytearray()
    for k in range(0, len(items), 16):
        grp = items[k:k + 16]
        w = 0
        for t, (c, _) in enumerate(grp):
            if c: w |= 1 << (15 - t)
        out += struct.pack('>H', w)
        for _, b in grp: out += b
    return bytes(out)


class File:
    def __init__(self, data):
        self.wide = data[32] == 0x33
        self.pad = 4 if data[35] == 0x33 else 0
        self.h = 164 + self.pad + 32
        self.hs, self.ps = struct.unpack_from('<II', data, self.h)
        self.pc = struct.unpack_from('<Q' if self.wide else '<I', data, self.h + 8)[0]
        self.phs = 40 if self.wide else 24
        self.lshp = 24 if self.wide else 12
        self.sigl = 8 if self.wide else 4
        self.head = bytearray(data[:self.hs])
        self.pages = []
        for i in range(self.pc):
            pg = data[self.hs + i * self.ps: self.hs + (i + 1) * self.ps]
            pt, nrows, cnt = struct.unpack_from('<HHH', pg, self.phs - 8)
            subs = []
            for j in range(cnt):
                at = self.phs + j * self.lshp
                if self.wide:
                    off, ln = struct.unpack_from('<QQ', pg, at); comp, pk = pg[at + 16], pg[at + 17]
                else:
                    off, ln = struct.unpack_from('<II', pg, at); comp, pk = pg[at + 8], pg[at + 9]
                subs.append([bytes(pg[off:off + ln]), comp, pk, pg[at + 10:at + self.lshp]])
            self.pages.append({'type': pt, 'rows': nrows, 'subs': subs, 'raw': bytes(pg), 'hdr': bytes(pg[:self.phs - 8])})
        # column layout from the attribute subheaders
        self.cols = []
        self.row_len = 0
        self.total = 0
        for pg in self.pages:
            for s in pg['subs']:
                kind = SIG.get(self.sig(s[0]))
                if kind == 'attrs' and s[1] == 0:
                    n = (len(s[0]) - (28 if self.wide else 20)) // (16 if self.wide else 12)
                    p = self.sigl + 8
                    for _ in range(n):
                        if self.wide:
                            off = struct.unpack_from('<Q', s[0], p)[0]; w = struct.unpack_from('<I', s[0], p + 8)[0]; ty = s[0][p + 14]; p += 16
                        else:
                            off = struct.unpack_from('<I', s[0], p)[0]; w = struct.unpack_from('<I', s[0], p + 4)[0]; ty = s[0][p + 10]; p += 12
                        self.cols.append((off, w, ty))
                if kind == 'rowsize' and s[1] == 0:
                    self.row_len, self.total = struct.unpack_from('<QQ', s[0], 40) if self.wide else struct.unpack_from('<II', s[0], 20)

    def sig(self, b):
        v = struct.unpack_from('<I', b, 0)[0]
        return v

    kind = 'rle'


def swap_row(f, row):
    r = bytearray(row)
    for off, w, ty in f.cols:
        if ty == 1: r[off:off + w] = bytes(reversed(r[off:off + w]))
    return bytes(r)


def swap16(b, at, n=1):
    for k in range(n): b[at + 2 * k:at + 2 * k + 2] = b[at + 2 * k:at + 2 * k + 2][::-1]


def swap32(b, at, n=1):
    for k in range(n): b[at + 4 * k:at + 4 * k + 4] = b[at + 4 * k:at + 4 * k + 4][::-1]


def swap64(b, at, n=1):
    for k in range(n): b[at + 8 * k:at + 8 * k + 8] = b[at + 8 * k:at + 8 * k + 8][::-1]


def swap_sub(f, data):
    """a metadata subheader read big-endian: signature, counts and text references swapped"""
    b = bytearray(data)
    kind = SIG.get(struct.unpack_from('<I', b, 0)[0])
    sg = f.sigl
    sig = struct.unpack_from('<I', b, 0)[0]
    if f.wide:
        # a big-endian 64-bit signature is the pattern itself (rows, column sizes) or all ones then the pattern
        if sig not in (0xF7F7F7F7, 0xF6F6F6F6):
            b[0:4] = b'\xff\xff\xff\xff'; b[4:8] = struct.pack('>I', sig)
        else:
            b[4:8] = b'\0\0\0\0'
    else:
        b[0:4] = struct.pack('>I', sig)
    w = f.wide
    wi = swap64 if w else swap32
    if kind == 'rowsize':
        wi(b, 40 if w else 20); wi(b, 48 if w else 24); wi(b, 120 if w else 60)
        swap16(b, len(b) - 130, 3); swap16(b, len(b) - 118, 3)
    elif kind == 'colsize':
        wi(b, 8 if w else 4)
    elif kind in ('text', 'names', 'attrs'):
        swap16(b, sg)
        if kind == 'names':
            p = sg + 8
            for _ in range((len(b) - (28 if w else 20)) // 8): swap16(b, p, 3); p += 8
        if kind == 'attrs':
            step = 16 if w else 12
            p = sg + 8
            n = (len(b) - (28 if w else 20)) // step
            for _ in range(n):
                wi(b, p); swap32(b, p + (8 if w else 4)); swap16(b, p + (12 if w else 8)); p += step
    elif kind == 'format':
        swap16(b, 24, 2)
        base = 46 if w else 34
        swap16(b, base, 3); swap16(b, base + 6, 3)
    return bytes(b)


def write(src, dst, big, comp):
    data = open(src, 'rb').read()
    f = File(data)
    f.kind = 'rle' if any(s[1] == 4 for pg in f.pages for s in pg['subs']) else 'raw'
    rows = []
    for pg in f.pages:
        if f.kind == 'rle':
            for s in pg['subs']:
                if s[1] == 4: rows.append(rle_unpack(s[0]))
        elif pg['type'] & 0xF00 == 0x100:
            for i in range(pg['rows']):
                rows.append(pg['raw'][f.phs + i * f.row_len:f.phs + (i + 1) * f.row_len])
    assert len(rows) == f.total, (len(rows), f.total)
    if big: rows = [swap_row(f, r) for r in rows]
    pages = []
    # the first page: the metadata subheaders (byte order swapped when big-endian), then as many rows as fit; later pages hold rows
    cap = f.ps - f.phs
    meta = []
    for pg in f.pages:
        for s in pg['subs']:
            if s[1] != 0: continue
            d = s[0]
            if big and struct.unpack_from('<I', d, 0)[0] >= 0xF6F6F6F6: d = swap_sub(f, d)
            if comp == 'rdc': d = d.replace(b'SASYZCRL', b'SASYZCR2')
            meta.append([d, s[1], s[2], b''])
    if f.kind == 'rle':
        packed = [rdc_pack(r) if comp == 'rdc' else rle_pack(r) for r in rows]
        cur = list(meta)
        used = sum(len(x[0]) + f.lshp for x in cur)
        for c in packed:
            if used + len(c) + f.lshp > cap:
                pages.append((0, 0, cur, [])); cur = []; used = 0
            cur.append([c, 4, 1, b'']); used += len(c) + f.lshp
        pages.append((0, 0, cur, []))
    else:
        pages.append((0, 0, meta, []))
        per = cap // f.row_len
        for k in range(0, len(rows), per):
            chunk = rows[k:k + per]
            pages.append((0x100, len(chunk), [], chunk))
    # emit
    head = bytearray(f.head)
    if big:
        head[37] = 0
        swap32(head, f.h, 2)
        if f.wide: swap64(head, f.h + 8)
        else: swap32(head, f.h + 8)
    if f.wide: head[f.h + 8:f.h + 16] = struct.pack('>Q' if big else '<Q', len(pages))
    else: head[f.h + 8:f.h + 12] = struct.pack('>I' if big else '<I', len(pages))
    if f.kind == 'rle':
        head = bytearray(head)
    blob = bytearray(head)
    e = '>' if big else '<'
    for ptype, nrows, subs, raw in pages:
        pgb = bytearray(f.ps)
        # the page header: sequence and similar fields are not read, only the type, row count and subheader count
        struct.pack_into(e + 'HHH', pgb, f.phs - 8, ptype, nrows if ptype & 0xF00 == 0x100 else len(subs), len(subs))
        struct.pack_into(e + 'H', pgb, f.phs - 2, 0)
        pos = f.ps
        for j, (d, comp_, pk, _) in enumerate(subs):
            pos -= len(d)
            assert pos >= f.phs + (len(subs)) * f.lshp, 'page overflow'
            pgb[pos:pos + len(d)] = d
            at = f.phs + j * f.lshp
            if f.wide:
                struct.pack_into(e + 'QQ', pgb, at, pos, len(d)); pgb[at + 16] = comp_; pgb[at + 17] = pk
            else:
                struct.pack_into(e + 'II', pgb, at, pos, len(d)); pgb[at + 8] = comp_; pgb[at + 9] = pk
        if ptype & 0xF00 == 0x100:
            for i, r in enumerate(raw): pgb[f.phs + i * f.row_len:f.phs + (i + 1) * f.row_len] = r
        blob += pgb
    open(dst, 'wb').write(bytes(blob))


if __name__ == '__main__':
    d = sys.argv[1]
    write(d + '/rle32.sas7bdat', d + '/rdc32.sas7bdat', False, 'rdc')
    write(d + '/rle64.sas7bdat', d + '/rdc64.sas7bdat', False, 'rdc')
    write(d + '/rle32.sas7bdat', d + '/rle32be.sas7bdat', True, 'rle')
    write(d + '/rle64.sas7bdat', d + '/rdc64be.sas7bdat', True, 'rdc')
    write(d + '/raw64.sas7bdat', d + '/raw64be.sas7bdat', True, 'raw')
