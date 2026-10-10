# -*- coding: utf-8 -*-
"""Vectors for `e.fmt.elf` and `e.fmt.pe` (L052).

An independent writer lays out ELF32/64 (both byte orders) and PE32/PE32+ images with `struct`; a separate reader here walks
them in the order the fixture does and gives the expected dump. Cuts and header damage give the error cases. Writes
tests/selfhost/fixtures/link/fmt_exe. Usage: python scripts/exe_vectors.py
"""
import json
import os
import random
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x52e1)


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


def rbytes(n):
    return bytes(rng.randrange(256) for _ in range(n))


class Err(Exception):
    pass


def ident(n):
    return ''.join(pick('abcdefghijklmnopqrstuvwxyz_0123456789') for _ in range(n))


# ---------------------------------------------------------------- ELF writer
def build_elf(cls, little):
    e = '<' if little else '>'
    wide = cls == 2
    word = (lambda v: v) if wide else (lambda v: v & 0xFFFFFFFF)
    big = lambda: rng.randrange(1 << 64) if wide else rng.randrange(1 << 32)
    nseg = rng.randrange(0, 6)
    # sections: null, .text, .data, .dynsym, .dynstr, .dynamic, .symtab, .strtab, .shstrtab
    dynstr = b'\0' + b'\0'.join(ident(rng.randrange(1, 10)).encode() for _ in range(rng.randrange(1, 6))) + b'\0'
    strtab = b'\0' + b'\0'.join(ident(rng.randrange(1, 12)).encode() for _ in range(rng.randrange(1, 8))) + b'\0'
    names = ['', '.text', '.data', '.dynsym', '.dynstr', '.dynamic', '.symtab', '.strtab', '.shstrtab']
    shstr = b'\0'
    name_off = [0]
    for nm in names[1:]:
        name_off.append(len(shstr))
        shstr += nm.encode() + b'\0'

    def sym(table_len):
        no = rng.randrange(0, table_len)
        info = rng.randrange(256)
        other = rng.randrange(4)
        shndx = rng.randrange(0, 9)
        value = big()
        size = rng.randrange(0, 1 << 16)
        if wide:
            return struct.pack(e + 'IBBHQQ', no, info, other, shndx, value, size)
        return struct.pack(e + 'IIIBBH', no, value, size, info, other, shndx)

    def symtab(count, table_len):
        return b''.join(sym(table_len) for _ in range(count))

    def dyn(tag):
        if wide:
            return struct.pack(e + 'QQ', tag, big())
        return struct.pack(e + 'II', tag, rng.randrange(1 << 32))

    blobs = {
        1: rbytes(rng.randrange(8, 64)),
        2: rbytes(rng.randrange(0, 32)),
        3: symtab(rng.randrange(1, 6), len(dynstr)),
        4: dynstr,
        5: b''.join(dyn(rng.choice([1, 2, 3, 4, 5, 6, 7, 12, 13, 0x6ffffffb])) for _ in range(rng.randrange(1, 6))) + dyn(0),
        6: symtab(rng.randrange(1, 8), len(strtab)),
        7: strtab,
        8: shstr,
    }
    kinds = {1: 1, 2: 1, 3: 11, 4: 3, 5: 6, 6: 2, 7: 3, 8: 3}
    links = {3: 4, 5: 4, 6: 7}
    ehsize = 64 if wide else 52
    phentsize = 56 if wide else 32
    shentsize = 64 if wide else 40
    pos = ehsize + nseg * phentsize
    offsets = {}
    body = b''
    for i in range(1, 9):
        pad = (-pos) % 8
        body += b'\0' * pad
        pos += pad
        offsets[i] = pos
        body += blobs[i]
        pos += len(blobs[i])
    pad = (-pos) % 8
    body += b'\0' * pad
    pos += pad
    shoff = pos
    shnum = 9
    shdrs = b'\0' * shentsize
    entsizes = {3: 24 if wide else 16, 6: 24 if wide else 16, 5: 16 if wide else 8}
    for i in range(1, 9):
        flags = rng.randrange(0, 8)
        addr = word(rng.randrange(1 << 40))
        es = entsizes.get(i, 0)
        if wide:
            shdrs += struct.pack(e + 'IIQQQQIIQQ', name_off[i], kinds[i], flags, addr, offsets[i], len(blobs[i]), links.get(i, 0), rng.randrange(0, 4), 8, es)
        else:
            shdrs += struct.pack(e + 'IIIIIIIIII', name_off[i], kinds[i], flags, addr, offsets[i], len(blobs[i]), links.get(i, 0), rng.randrange(0, 4), 8, es)
    phdrs = b''
    for _ in range(nseg):
        kind = rng.choice([1, 2, 3, 4, 6, 7, 0x6474e550, 0x6474e551])
        flags = rng.randrange(0, 8)
        off, va, pa, fs, ms, al = (word(big()) for _ in range(6))
        if wide:
            phdrs += struct.pack(e + 'IIQQQQQQ', kind, flags, off, va, pa, fs, ms, al)
        else:
            phdrs += struct.pack(e + 'IIIIIIII', kind, off, va, pa, fs, ms, flags, al)
    osabi = rng.choice([0, 3, 9])
    abi = rng.randrange(0, 3)
    head = bytes([0x7f, 0x45, 0x4c, 0x46, cls, 1 if little else 2, 1, osabi, abi]) + b'\0' * 7
    kind = rng.choice([1, 2, 3, 4])
    machine = rng.choice([3, 8, 40, 62, 183, 243])
    eflags = rng.randrange(0, 1 << 16)
    entry = word(big())
    if wide:
        head += struct.pack(e + 'HHIQQQIHHHHHH', kind, machine, 1, entry, ehsize if nseg == 0 else ehsize, shoff, eflags, ehsize, phentsize, nseg, shentsize, shnum, 8)
        # phoff is at 32: patch (struct above put phoff = ehsize)
    else:
        head += struct.pack(e + 'HHIIIIIHHHHHH', kind, machine, 1, entry, ehsize, shoff, eflags, ehsize, phentsize, nseg, shentsize, shnum, 8)
    return head + phdrs + body + shdrs


def be_walk_elf(data):
    """Reader written separately from the module; mirrors the fixture's walk and error classes."""
    def need(cond, kind='truncated'):
        if not cond:
            raise Err(kind)
    need(len(data) >= 16)
    if data[:4] != b'\x7fELF':
        raise Err('invalid')
    cls = data[4]
    if cls not in (1, 2):
        raise Err('invalid')
    if data[5] not in (1, 2):
        raise Err('invalid')
    little = data[5] == 1
    e = '<' if little else '>'
    wide = cls == 2
    need(len(data) >= (64 if wide else 52))
    if wide:
        kind, machine, _ver, entry, phoff, shoff, flags, ehsize, phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from(e + 'HHIQQQIHHHHHH', data, 16)
    else:
        kind, machine, _ver, entry, phoff, shoff, flags, ehsize, phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from(e + 'HHIIIIIHHHHHH', data, 16)
    hdr = {'class': cls, 'little': little, 'version': data[6], 'osabi': data[7], 'abi': data[8], 'kind': kind, 'machine': machine,
           'entry': '%x' % entry, 'phoff': '%x' % phoff, 'shoff': '%x' % shoff, 'flags': flags, 'ehsize': ehsize, 'phentsize': phentsize,
           'phnum': phnum, 'shentsize': shentsize, 'shnum': shnum, 'shstrndx': shstrndx}
    segs = []
    for i in range(phnum):
        if phentsize != (56 if wide else 32):
            raise Err('invalid')
        at = phoff + i * phentsize
        need(at + phentsize <= len(data))
        if wide:
            k, fl, off, va, pa, fs, ms, al = struct.unpack_from(e + 'IIQQQQQQ', data, at)
        else:
            k, off, va, pa, fs, ms, fl, al = struct.unpack_from(e + 'IIIIIIII', data, at)
        segs.append({'kind': k, 'flags': fl, 'off': '%x' % off, 'vaddr': '%x' % va, 'paddr': '%x' % pa, 'filesz': '%x' % fs, 'memsz': '%x' % ms, 'align': '%x' % al})

    def section(i):
        if shentsize != (64 if wide else 40):
            raise Err('invalid')
        if i >= shnum:
            raise Err('invalid')
        at = shoff + i * shentsize
        need(at + shentsize <= len(data))
        if wide:
            return struct.unpack_from(e + 'IIQQQQIIQQ', data, at)
        return struct.unpack_from(e + 'IIIIIIIIII', data, at)

    def cstring(sec, offset):
        if sec[1] != 3:
            raise Err('invalid')
        if offset >= sec[5]:
            raise Err('invalid')
        need(sec[4] + sec[5] <= len(data))
        start = sec[4] + offset
        end = sec[4] + sec[5]
        z = data.find(b'\0', start, end)
        need(z >= 0)
        return data[start:z].decode('latin-1')

    secs, syms, dyns = [], [], []
    for i in range(shnum):
        s = section(i)
        table = section(shstrndx)
        name = cstring(table, s[0])
        name_off, k, fl, addr, off, size, link, info, align, entsize = s
        secs.append({'name': name, 'nameoff': name_off, 'kind': k, 'flags': '%x' % fl, 'addr': '%x' % addr, 'off': '%x' % off,
                     'size': '%x' % size, 'link': link, 'info': info, 'align': '%x' % align, 'entsize': '%x' % entsize})
        if k in (2, 11):
            strtab = section(link)
            want = 24 if wide else 16
            for j in range(size // want):
                if entsize != want:
                    raise Err('invalid')
                at = off + j * want
                need(at + want <= len(data))
                if wide:
                    no, info_b, other, shndx, value, ssize = struct.unpack_from(e + 'IBBHQQ', data, at)
                else:
                    no, value, ssize, info_b, other, shndx = struct.unpack_from(e + 'IIIBBH', data, at)
                syms.append({'sec': i, 'i': j, 'name': cstring(strtab, no), 'info': info_b, 'other': other, 'shndx': shndx,
                             'value': '%x' % value, 'size': '%x' % ssize})
        elif k == 6:
            want = 16 if wide else 8
            for j in range(size // want):
                at = off + j * want
                need(at + want <= len(data))
                tag, value = struct.unpack_from(e + ('QQ' if wide else 'II'), data, at)
                dyns.append({'sec': i, 'i': j, 'tag': '%x' % tag, 'value': '%x' % value})
    return {'hdr': hdr, 'segs': segs, 'secs': secs, 'syms': syms, 'dyn': dyns}


# ---------------------------------------------------------------- PE writer
def build_pe(plus, with_imports=True, with_exports=True, ndirs=16):
    falign, salign = 0x200, 0x1000
    sections = []
    text = rbytes(rng.randrange(16, 0x180))
    rdata_rva = 0x2000
    # .rdata contents
    dlls = []
    if with_imports:
        for _ in range(rng.randrange(1, 4)):
            funcs = []
            for _ in range(rng.randrange(1, 6)):
                if chance(0.25):
                    funcs.append(('ord', rng.randrange(1, 4000)))
                else:
                    funcs.append(('name', ident(rng.randrange(3, 14)), rng.randrange(0, 600)))
            dlls.append((ident(rng.randrange(3, 9)) + '.dll', funcs))
    thunk = 8 if plus else 4
    flag = (1 << 63) if plus else (1 << 31)
    buf = bytearray()
    # import descriptors first
    imp_off = 0
    imp_size = 20 * (len(dlls) + 1)
    pos = imp_size
    placements = []
    for dll, funcs in dlls:
        ilt = pos
        pos += thunk * (len(funcs) + 1)
        iat = pos
        pos += thunk * (len(funcs) + 1)
        placements.append((ilt, iat))
    hn_pos = {}
    for di, (dll, funcs) in enumerate(dlls):
        for fi, fn in enumerate(funcs):
            if fn[0] == 'name':
                if pos % 2:
                    pos += 1
                hn_pos[(di, fi)] = pos
                pos += 2 + len(fn[1]) + 1
    dll_name_pos = []
    for dll, funcs in dlls:
        dll_name_pos.append(pos)
        pos += len(dll) + 1
    exp_off = None
    exp_size = 0
    exp = None
    if with_exports:
        if pos % 4:
            pos += 4 - pos % 4
        nfuncs = rng.randrange(1, 7)
        nnames = rng.randrange(1, nfuncs + 1)
        enames = sorted(set(ident(rng.randrange(3, 12)) for _ in range(nnames)))
        nnames = len(enames)
        base = rng.choice([1, 1, 1, 5, 100])
        modname = ident(rng.randrange(3, 8)) + '.dll'
        exp_off = pos
        pos += 40
        eat = pos
        pos += 4 * nfuncs
        npt = pos
        pos += 4 * nnames
        ot = pos
        pos += 2 * nnames
        mod_pos = pos
        pos += len(modname) + 1
        name_pos = []
        for nm in enames:
            name_pos.append(pos)
            pos += len(nm) + 1
        exp_size = pos - exp_off
        ords = rng.sample(range(nfuncs), nnames) if nnames <= nfuncs else list(range(nnames))
        exp = (nfuncs, base, modname, enames, ords)
    total = pos
    raw_size = (total + falign - 1) // falign * falign
    buf = bytearray(raw_size)
    R = rdata_rva
    # descriptors
    for di, (dll, funcs) in enumerate(dlls):
        ilt, iat = placements[di]
        struct.pack_into('<IIIII', buf, di * 20, R + ilt, rng.randrange(0, 5), 0, R + dll_name_pos[di], R + iat)
        for fi, fn in enumerate(funcs):
            if fn[0] == 'ord':
                v = flag | fn[1]
            else:
                v = R + hn_pos[(di, fi)]
            for t in (ilt, iat):
                if plus:
                    struct.pack_into('<Q', buf, t + fi * 8, v)
                else:
                    struct.pack_into('<I', buf, t + fi * 4, v)
            if fn[0] == 'name':
                p = hn_pos[(di, fi)]
                struct.pack_into('<H', buf, p, fn[2])
                buf[p + 2:p + 2 + len(fn[1])] = fn[1].encode()
        buf[dll_name_pos[di]:dll_name_pos[di] + len(dll)] = dll.encode()
    if exp is not None:
        nfuncs, base, modname, enames, ords = exp
        struct.pack_into('<IIHHIIIIIII', buf, exp_off, 0, rng.randrange(1 << 32), 0, 0, R + mod_pos, base, nfuncs, len(enames), R + eat, R + npt, R + ot)
        for k in range(nfuncs):
            struct.pack_into('<I', buf, eat + 4 * k, 0x1000 + rng.randrange(0, 0x100))
        for k, nm in enumerate(enames):
            struct.pack_into('<I', buf, npt + 4 * k, R + name_pos[k])
            struct.pack_into('<H', buf, ot + 2 * k, ords[k])
            buf[name_pos[k]:name_pos[k] + len(nm)] = nm.encode()
        buf[mod_pos:mod_pos + len(modname)] = modname.encode()
    data_blob = rbytes(rng.randrange(0, 0x100))
    # sections (name, rva, vsize, raw bytes)
    vs_rdata = total if chance(0.7) else total + rng.randrange(1, 0x400)
    secs = [
        ('.text', 0x1000, len(text), text + b'\0' * ((-len(text)) % falign)),
        ('.rdata', R, vs_rdata, bytes(buf)),
        ('.data', 0x3000, len(data_blob) + rng.randrange(0, 0x100), data_blob + b'\0' * ((-len(data_blob)) % falign)),
    ]
    opt_size = (112 if plus else 96) + ndirs * 8
    lfanew = 0x40 + 8 * rng.randrange(0, 8)
    hdr_end = lfanew + 4 + 20 + opt_size + 40 * len(secs)
    size_of_headers = max(0x200, (hdr_end + falign - 1) // falign * falign)
    raw_ptr = size_of_headers
    sec_headers = b''
    body = b''
    for name, rva, vsize, raw in secs:
        sec_headers += struct.pack('<8sIIIIIIHHI', name.encode().ljust(8, b'\0'), vsize, rva, len(raw), raw_ptr if raw else 0, 0, 0, 0, 0, rng.randrange(1 << 32))
        body += raw
        raw_ptr += len(raw)
    dirs = [(0, 0)] * 16
    if exp is not None:
        dirs[0] = (R + exp_off, exp_size)
    if dlls:
        dirs[1] = (R, imp_size)
    dirbytes = b''.join(struct.pack('<II', r, s) for r, s in dirs[:ndirs])
    entry = 0x1000 + rng.randrange(0, 0x100)
    image_base = rng.choice([0x400000, 0x10000000, 0x140000000, 0x180000000]) if plus else rng.choice([0x400000, 0x10000000])
    subsystem = rng.choice([2, 3, 9])
    dllchars = rng.randrange(0, 1 << 16)
    size_of_image = 0x4000
    if plus:
        opt = struct.pack('<HBBIIIIIQIIHHHHHHIIIIHHQQQQII', 0x20b, 14, 0, len(text), 0, 0, entry, 0x1000, image_base, salign, falign,
                          6, 0, 0, 0, 6, 0, 0, size_of_image, size_of_headers, 0, subsystem, dllchars, 0x100000, 0x1000, 0x100000, 0x1000, 0, ndirs)
    else:
        opt = struct.pack('<HBBIIIIIIIIIHHHHHHIIIIHHIIIIII', 0x10b, 14, 0, len(text), 0, 0, entry, 0x1000, 0x2000, image_base, salign, falign,
                          6, 0, 0, 0, 6, 0, 0, size_of_image, size_of_headers, 0, subsystem, dllchars, 0x100000, 0x1000, 0x100000, 0x1000, 0, ndirs)
    opt += dirbytes
    assert len(opt) == opt_size, (len(opt), opt_size)
    machine = 0x8664 if plus else 0x14c
    chars = rng.choice([0x22, 0x2022, 0x102, 0x2102])
    timestamp = rng.randrange(1 << 32)
    coff = struct.pack('<HHIIIHH', machine, len(secs), timestamp, 0, 0, opt_size, chars)
    mz = b'MZ' + b'\0' * 58 + struct.pack('<I', lfanew)
    stub = b'\0' * (lfanew - 64)
    head = mz + stub + b'PE\0\0' + coff + opt + sec_headers
    head += b'\0' * (size_of_headers - len(head))
    return head + body, {'rdata_rva': R, 'sections': secs}


def walk_pe(data, probes):
    def need(cond, kind='truncated'):
        if not cond:
            raise Err(kind)
    need(len(data) >= 64)
    if data[:2] != b'MZ':
        raise Err('invalid')
    lfanew = struct.unpack_from('<I', data, 60)[0]
    need(lfanew <= len(data) and 24 <= len(data) - lfanew)
    if data[lfanew:lfanew + 4] != b'PE\0\0':
        raise Err('invalid')
    coff = lfanew + 4
    machine, nsec, ts, _p, _n, optsize, chars = struct.unpack_from('<HHIIIHH', data, coff)
    opt = coff + 20
    need(optsize >= 2 and opt <= len(data) and optsize <= len(data) - opt)
    magic = struct.unpack_from('<H', data, opt)[0]
    if magic == 0x10b:
        plus = False
        if optsize < 96:
            raise Err('invalid')
        entry = struct.unpack_from('<I', data, opt + 16)[0]
        base = struct.unpack_from('<I', data, opt + 28)[0]
        nd = struct.unpack_from('<I', data, opt + 92)[0]
        dirs_at = opt + 96
    elif magic == 0x20b:
        plus = True
        if optsize < 112:
            raise Err('invalid')
        entry = struct.unpack_from('<I', data, opt + 16)[0]
        base = struct.unpack_from('<Q', data, opt + 24)[0]
        nd = struct.unpack_from('<I', data, opt + 108)[0]
        dirs_at = opt + 112
    else:
        raise Err('invalid')
    salign, falign = struct.unpack_from('<II', data, opt + 32)
    size_of_image, size_of_headers = struct.unpack_from('<II', data, opt + 56)
    subsystem, dllchars = struct.unpack_from('<HH', data, opt + 68)
    dirs = [[0, 0] for _ in range(16)]
    i = 0
    while i < 16 and i < nd:
        p = dirs_at + i * 8
        if p + 8 > opt + optsize:
            break
        dirs[i] = list(struct.unpack_from('<II', data, p))
        i += 1
    sec_table = opt + optsize
    need(sec_table <= len(data) and nsec * 40 <= len(data) - sec_table)
    img = {'machine': machine, 'nsec': nsec, 'ts': ts, 'chars': chars, 'magic': magic, 'plus': plus, 'entry': entry, 'base': '%x' % base,
           'salign': salign, 'falign': falign, 'subsys': subsystem, 'dllchars': dllchars, 'imgsize': size_of_image,
           'hdrsize': size_of_headers, 'ndirs': nd, 'dirs': dirs}
    secs = []
    raw = []
    for i in range(nsec):
        p = sec_table + i * 40
        nm, vsize, va, rsize, rptr, _r, _l, _nr, _nl, ch = struct.unpack_from('<8sIIIIIIHHI', data, p)
        n = nm.find(b'\0')
        n = 8 if n < 0 else n
        secs.append({'name': nm[:n].decode('latin-1'), 'vsize': vsize, 'va': va, 'rsize': rsize, 'rptr': rptr, 'chars': ch})
        raw.append((va, vsize, rsize, rptr))

    def off(rva):
        if rva < size_of_headers:
            return rva
        for va, vsize, rsize, rptr in raw:
            span = max(vsize, rsize)
            if va <= rva and rva - va < span:
                if rva - va >= rsize:
                    raise Err('invalid')
                return rptr + (rva - va)
        raise Err('invalid')

    def cstr(rva):
        start = off(rva)
        z = data.find(b'\0', start) if start <= len(data) else -1
        need(z >= 0)
        return data[start:z].decode('latin-1')

    pr = []
    for r in probes:
        try:
            pr.append(off(r))
        except Err:
            pr.append(-1)
    imports = []
    if nd >= 2 and dirs[1][0] != 0:
        base_off = off(dirs[1][0])
        index = 0
        while index < 32:
            p = base_off + index * 20
            need(p <= len(data) and 20 <= len(data) - p)
            oft, _ts, _fw, nrva, ft = struct.unpack_from('<IIIII', data, p)
            if nrva == 0 and ft == 0 and oft == 0:
                break
            dll = cstr(nrva)
            table = oft if oft != 0 else ft
            tb = off(table)
            width = 8 if plus else 4
            funcs = []
            k = 0
            while k < 96:
                q = tb + k * width
                need(q <= len(data) and width <= len(data) - q)
                v = struct.unpack_from('<Q' if plus else '<I', data, q)[0]
                if v == 0:
                    break
                if v & ((1 << 63) if plus else (1 << 31)):
                    funcs.append({'ord': v & 0xFFFF})
                else:
                    rv = v & 0xFFFFFFFF
                    h = off(rv)
                    need(h <= len(data) and 2 <= len(data) - h)
                    funcs.append({'name': cstr(rv + 2), 'hint': struct.unpack_from('<H', data, h)[0]})
                k += 1
            imports.append({'dll': dll, 'funcs': funcs})
            index += 1
    exports = {'has': False}
    if nd >= 1 and dirs[0][0] != 0:
        p = off(dirs[0][0])
        need(p <= len(data) and 40 <= len(data) - p)
        _c, _t, _mj, _mn, nrva, obase, naddr, nnames, at, nt, ot = struct.unpack_from('<IIHHIIIIIII', data, p)
        exports = {'has': True, 'name': cstr(nrva), 'base': obase, 'naddr': naddr, 'nnames': nnames, 'names': []}
        k = 0
        while k < nnames and k < 96:
            names = off(nt)
            need(names + k * 4 <= len(data) and 4 <= len(data) - (names + k * 4))
            name_rva = struct.unpack_from('<I', data, names + k * 4)[0]
            ords = off(ot)
            need(ords + k * 2 <= len(data) and 2 <= len(data) - (ords + k * 2))
            ordinal = struct.unpack_from('<H', data, ords + k * 2)[0] + obase
            exports['names'].append({'name': cstr(name_rva), 'ord': ordinal})
            k += 1
    return {'img': img, 'secs': secs, 'probes': pr, 'imports': imports, 'exports': exports}


cases = []


def add(c):
    cases.append(c)


def elf_case(data):
    try:
        v = be_walk_elf(data)
        e = {'ok': True, 'v': v}
    except Err as x:
        e = {'ok': False, 'error': str(x)}
    add({'op': 'elf', 'h': data.hex(), 'e': e})


def pe_case(data, probes):
    try:
        v = walk_pe(data, probes)
        e = {'ok': True, 'v': v}
    except Err as x:
        e = {'ok': False, 'error': str(x)}
    add({'op': 'pe', 'h': data.hex(), 'probes': probes, 'e': e})


for cls in (1, 2):
    for little in (True, False):
        for _ in range(8):
            d = build_elf(cls, little)
            elf_case(d)
            if chance(0.5):
                elf_case(d[:rng.randrange(0, len(d))])
elf_case(b'')
elf_case(b'\x7fELF')
elf_case(b'MZ' + b'\0' * 70)
for pos, val in ((4, 0), (4, 3), (5, 0), (5, 3), (0, 0x7e)):
    d = bytearray(build_elf(2, True))
    d[pos] = val
    elf_case(bytes(d))
for _ in range(40):
    d = build_elf(pick((1, 2)), chance(0.5))
    elf_case(d[:rng.randrange(0, len(d))])

for plus in (False, True):
    for _ in range(14):
        d, info = build_pe(plus, with_imports=chance(0.85), with_exports=chance(0.5), ndirs=pick([16, 16, 16, 10, 2]))
        probes = [rng.randrange(0, 0x4000) for _ in range(10)] + [0, 0x1000, 0x1fff, 0x2000, 0x2100, 0x3000]
        pe_case(d, probes)
        if chance(0.4):
            pe_case(d[:rng.randrange(0, len(d))], probes[:6])
    for _ in range(12):
        d, info = build_pe(plus)
        pe_case(d[:rng.randrange(0, len(d))], [0x2000, 0x2200])
pe_case(b'', [])
pe_case(b'MZ' + b'\0' * 70, [])
d, _ = build_pe(False)
bad = bytearray(d)
bad[0] = 0
pe_case(bytes(bad), [])
bad = bytearray(d)
lf = struct.unpack_from('<I', bad, 60)[0]
bad[lf] = 0x51
pe_case(bytes(bad), [])
bad = bytearray(d)
struct.pack_into('<H', bad, lf + 24, 0x107)
pe_case(bytes(bad), [])
bad = bytearray(d)
struct.pack_into('<H', bad, lf + 6, 200)
pe_case(bytes(bad), [])

for c in cases:
    if c['op'] == 'elf' and c['e']['ok']:
        v = c['e']['v']
        assert len(v['segs']) < 96 and len(v['secs']) < 96 and len(v['syms']) < 96 and len(v['dyn']) < 96

BS = chr(92)
lines = [json.dumps(c, sort_keys=True) for c in cases]
chunks = []
for i in range(0, len(lines), 10):
    body = '\\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"') for l in lines[i:i + 10]) + '\\n'
    chunks.append('"' + body + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'exe_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'fmt_exe', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d cases in %d chunks -> fmt_exe' % (len(cases), len(chunks)))
