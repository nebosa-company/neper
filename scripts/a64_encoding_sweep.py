#!/usr/bin/env python3
"""The aarch64 encoder's sweep (D2123): a grid of every form `src/emit_a64.e` encodes, over
registers, immediates, widths, conditions and vector arrangements, as assembly text in the exact order
`emit_a64.sweep` encodes it. GNU as (binutils, -march=armv8.2-a) assembles the text and the
words fold into one FNV-1a hash, which the self-test compares with its own.

    python scripts/a64_encoding_sweep.py            (prints the count and the hash)
    python scripts/a64_encoding_sweep.py --listing   (also writes build/a64/sweep.s)

Runs the assembler in WSL. The grid is the contract: change it here and in `sweep` together.
"""
import os, struct, subprocess, sys

R = [0, 1, 2, 7, 8, 15, 16, 17, 18, 19, 28, 29, 30]
R4 = [0, 9, 17, 30]
V = [0, 1, 7, 16, 17, 31]
CONDITIONS = ['eq', 'ne', 'hs', 'lo', 'mi', 'pl', 'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt', 'le']
THREE = ['add', 'adds', 'sub', 'subs', 'and', 'orr', 'eor', 'mul', 'smulh', 'umulh', 'sdiv', 'udiv', 'lsl', 'lsr', 'asr']


def x(r, sp=False):
    if r == 31:
        return 'sp' if sp else 'xzr'
    return 'x%d' % r


def w(r):
    return 'wzr' if r == 31 else 'w%d' % r


def lines():
    out = []
    for form in THREE:
        for d in R:
            for n in R:
                for m in R:
                    out.append('%s %s, %s, %s' % (form, x(d), x(n), x(m)))
    for name in ('madd', 'msub'):
        for d in R4:
            for n in R4:
                for m in R4:
                    for a in R4:
                        out.append('%s %s, %s, %s, %s' % (name, x(d), x(n), x(m), x(a)))
    for d in R:
        for m in R:
            out.append('neg %s, %s' % (x(d), x(m)))
            out.append('mvn %s, %s' % (x(d), x(m)))
            out.append('cmp %s, %s' % (x(d), x(m)))
            out.append('cmp %s, %s, asr #63' % (x(d), x(m)))
            out.append('mov %s, %s' % (x(d), x(m)))
    for d in R:
        for c in CONDITIONS:
            out.append('cset %s, %s' % (x(d), c))
    for d in R4:
        for n in R4:
            for m in R4:
                for c in CONDITIONS:
                    out.append('csel %s, %s, %s, %s' % (x(d), x(n), x(m), c))
    for d in R:
        for n in R:
            for width in (8, 16, 32):
                out.append('sbfm %s, %s, #0, #%d' % (x(d), x(n), width - 1))
                out.append('ubfm %s, %s, #0, #%d' % (x(d), x(n), width - 1))
            for count in (1, 7, 31, 32, 63):
                out.append('lsl %s, %s, #%d' % (x(d), x(n), count))
                out.append('lsr %s, %s, #%d' % (x(d), x(n), count))
                out.append('asr %s, %s, #%d' % (x(d), x(n), count))
    for d in R + [31]:
        for n in R + [31]:
            for imm in (0, 1, 2048, 4095, 4096, 0x5000, 0x123456, 0xfff000):
                for name in ('add', 'sub'):
                    high, low = imm >> 12, imm & 0xfff
                    if high:
                        out.append('%s %s, %s, #%d, lsl #12' % (name, x(d, True), x(n, True), high))
                        if low:
                            out.append('%s %s, %s, #%d' % (name, x(d, True), x(d, True), low))
                    else:
                        out.append('%s %s, %s, #%d' % (name, x(d, True), x(n, True), low))
    for n in R + [31]:
        for imm in (0, 1, 4095):
            out.append('cmp %s, #%d' % (x(n, True), imm))
    for d in R:
        for imm in (0, 1, 0xffff, 0x1234):
            for hw in range(4):
                for name in ('movz', 'movk', 'movn'):
                    out.append('%s %s, #%d, lsl #%d' % (name, x(d), imm, hw * 16))
    for width in (1, 2, 4, 8):
        for signed in (False, True):
            if width == 8 and signed:
                continue
            for t in R4:
                for n in R4 + [31]:
                    for offset in (0, width, 8 * width, 4095 * width, 3, 255):
                        out.append(load_text(t, n, offset, width, signed))
    for width in (1, 2, 4, 8):
        for t in R4:
            for n in R4 + [31]:
                for offset in (0, width, 8 * width, 4095 * width, 3, 255):
                    out.append(store_text(t, n, offset, width))
    for t in R4:
        for n in R4 + [29, 31]:
            for offset in (8, 16, 256):
                out.append('ldur %s, [%s, #-%d]' % (x(t), x(n, True), offset))
                out.append('stur %s, [%s, #-%d]' % (x(t), x(n, True), offset))
    for width in (1, 2, 4, 8):
        for signed in (False, True):
            if width == 8 and signed:
                continue
            for t in R4:
                for n in R4:
                    for m in R4:
                        out.append(indexed_text('ldr', t, n, m, width, signed))
        for t in R4:
            for n in R4:
                for m in R4:
                    out.append(indexed_text('str', t, n, m, width, False))
    for t in R4:
        for t2 in R4:
            for n in (0, 9, 31):
                for offset in (16, 32, 496):
                    out.append('stp %s, %s, [%s, #-%d]!' % (x(t), x(t2), x(n, True), offset))
                    out.append('ldp %s, %s, [%s], #%d' % (x(t), x(t2), x(n, True), offset))
    suffix = {1: 'b', 2: 'h', 4: '', 8: ''}
    for width in (1, 2, 4, 8):
        reg = x if width == 8 else w
        for t in R4:
            for n in R4:
                out.append('ldar%s %s, [%s]' % (suffix[width], reg(t), x(n, True)))
                out.append('stlr%s %s, [%s]' % (suffix[width], reg(t), x(n, True)))
    atomic = {0: 'swpal', 1: 'ldaddal', 3: 'ldclral', 4: 'ldsetal', 5: 'ldeoral', 6: 'ldsminal', 7: 'ldsmaxal', 8: 'lduminal', 9: 'ldumaxal'}
    for kind in (0, 1, 3, 4, 5, 6, 7, 8, 9):
        for width in (1, 2, 4, 8):
            reg = x if width == 8 else w
            for s in R4:
                for t in R4:
                    for n in R4:
                        out.append('%s%s %s, %s, [%s]' % (atomic[kind], suffix[width], reg(s), reg(t), x(n, True)))
    for width in (1, 2, 4, 8):
        reg = x if width == 8 else w
        for s in R4:
            for t in R4:
                for n in R4:
                    out.append('casal%s %s, %s, [%s]' % (suffix[width], reg(s), reg(t), x(n, True)))
    out.append('dmb ish')
    out.append('svc #0')
    for imm in (0, 1, 0xffff):
        out.append('brk #%d' % imm)
    out.append('nop')
    for r in R:
        out.append('br %s' % x(r))
        out.append('blr %s' % x(r))
    out.append('ret')
    for v in V:
        for r in R:
            out.append('fmov d%d, %s' % (v, x(r)))
            out.append('fmov s%d, %s' % (v, w(r)))
            out.append('fmov %s, d%d' % (x(r), v))
            out.append('fmov %s, s%d' % (w(r), v))
    for operation in ('fadd', 'fsub', 'fmul', 'fdiv'):
        for p in ('d', 's'):
            for d in V:
                for n in V:
                    for m in V:
                        out.append('%s %s%d, %s%d, %s%d' % (operation, p, d, p, n, p, m))
    for p in ('d', 's'):
        for d in V:
            for n in V:
                out.append('fsqrt %s%d, %s%d' % (p, d, p, n))
                out.append('fneg %s%d, %s%d' % (p, d, p, n))
                out.append('fcmp %s%d, %s%d' % (p, d, p, n))
    for p in ('d', 's'):
        for d in V:
            for n in V:
                for m in V:
                    for a in V:
                        out.append('fmadd %s%d, %s%d, %s%d, %s%d' % (p, d, p, n, p, m, p, a))
    for d in V:
        for n in V:
            out.append('fcvt d%d, s%d' % (d, n))
            out.append('fcvt s%d, d%d' % (d, n))
    for p in ('d', 's'):
        for v in V:
            for r in R:
                out.append('scvtf %s%d, %s' % (p, v, x(r)))
                out.append('ucvtf %s%d, %s' % (p, v, x(r)))
                out.append('fcvtzs %s, %s%d' % (x(r), p, v))
                out.append('fcvtzu %s, %s%d' % (x(r), p, v))
    for d in R4:
        for n in R4:
            for m in R4:
                for shift in (0, 1, 3, 4, 63):
                    out.append('add %s, %s, %s, lsl #%d' % (x(d), x(n), x(m), shift))
    out.extend(vector_lines())
    return out


ARRANGEMENT = ['16b', '8h', '4s', '2d']


def vector_lines():
    out = []
    letter = {16: 'q', 8: 'd', 4: 's', 2: 'h'}
    for size in (16, 8, 4, 2):
        for t in V:
            for n in R4 + [31]:
                out.append('ldr %s%d, [%s]' % (letter[size], t, x(n, True)))
                out.append('str %s%d, [%s]' % (letter[size], t, x(n, True)))
    names = ['add', 'sub', 'mul', 'ushl', 'sshl', 'and', 'orr', 'eor', 'bif', 'fadd', 'fsub', 'fmul', 'fdiv', 'fcmeq']
    for operation, name in enumerate(names):
        if operation <= 4:
            sizes = [0, 1, 2] if operation == 2 else [0, 1, 2, 3]
        elif operation <= 8:
            sizes = [0]
        else:
            sizes = [2, 3]
        for size in sizes:
            arrangement = '16b' if 5 <= operation <= 8 else ARRANGEMENT[size]
            for d in V:
                for n in V:
                    for m in V:
                        out.append('%s v%d.%s, v%d.%s, v%d.%s' % (name, d, arrangement, n, arrangement, m, arrangement))
    for d in V:
        for n in V:
            out.append('not v%d.16b, v%d.16b' % (d, n))
            for size in range(4):
                out.append('neg v%d.%s, v%d.%s' % (d, ARRANGEMENT[size], n, ARRANGEMENT[size]))
    for size in range(4):
        for d in V:
            for r in R:
                out.append('dup v%d.%s, %s' % (d, ARRANGEMENT[size], x(r) if size == 3 else w(r)))
    for d in V:
        for imm in (0, 1, 0xff, 0x5a):
            out.append('movi v%d.16b, #%d' % (d, imm))
    for size in range(4):
        width = 8 << size
        for d in V:
            for n in V:
                for count in (0, 1, width - 1):
                    out.append('shl v%d.%s, v%d.%s, #%d' % (d, ARRANGEMENT[size], n, ARRANGEMENT[size], count))
                for count in (1, width // 2, width):
                    out.append('ushr v%d.%s, v%d.%s, #%d' % (d, ARRANGEMENT[size], n, ARRANGEMENT[size], count))
                    out.append('sshr v%d.%s, v%d.%s, #%d' % (d, ARRANGEMENT[size], n, ARRANGEMENT[size], count))
    return out


def load_text(t, n, offset, width, signed):
    base = x(n, True)
    scaled = offset % width == 0 and offset // width < 4096
    if signed:
        name = {1: 'ldrsb', 2: 'ldrsh', 4: 'ldrsw'}[width]
        if not scaled:
            name = name.replace('ldr', 'ldur')
        return '%s %s, [%s, #%d]' % (name, x(t), base, offset)
    name = {1: 'ldrb', 2: 'ldrh', 4: 'ldr', 8: 'ldr'}[width]
    if not scaled:
        name = name.replace('ldr', 'ldur')
    reg = x(t) if width == 8 else w(t)
    return '%s %s, [%s, #%d]' % (name, reg, base, offset)


def store_text(t, n, offset, width):
    scaled = offset % width == 0 and offset // width < 4096
    name = {1: 'strb', 2: 'strh', 4: 'str', 8: 'str'}[width]
    if not scaled:
        name = name.replace('str', 'stur')
    reg = x(t) if width == 8 else w(t)
    return '%s %s, [%s, #%d]' % (name, reg, x(n, True), offset)


def indexed_text(op, t, n, m, width, signed):
    if signed:
        name = {1: 'ldrsb', 2: 'ldrsh', 4: 'ldrsw'}[width]
        return '%s %s, [%s, %s]' % (name, x(t), x(n, True), x(m))
    name = op + {1: 'b', 2: 'h', 4: '', 8: ''}[width]
    reg = x(t) if width == 8 else w(t)
    return '%s %s, [%s, %s]' % (name, reg, x(n, True), x(m))


def main():
    text = lines()
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build = os.path.join(repo, 'build', 'a64')
    os.makedirs(build, exist_ok=True)
    source = os.path.join(build, 'sweep.s')
    with open(source, 'w', newline='\n') as f:
        f.write('.text\n' + '\n'.join(text) + '\n')
    def wsl(path):
        full = os.path.abspath(path)
        return '/mnt/' + full[0].lower() + full[2:].replace('\\', '/')
    obj, binary = os.path.join(build, 'sweep.o'), os.path.join(build, 'sweep.bin')
    for command in (['aarch64-linux-gnu-as', '-march=armv8.2-a', wsl(source), '-o', wsl(obj)],
                    ['aarch64-linux-gnu-objcopy', '-O', 'binary', '--only-section=.text', wsl(obj), wsl(binary)]):
        subprocess.run(['wsl', '-d', 'Ubuntu-24.04', '--'] + command, check=True)
    data = open(binary, 'rb').read()
    words = struct.unpack('<%dI' % (len(data) // 4), data)
    value = 14695981039346656037
    for word in words:
        value = ((value ^ word) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    print('instructions %d words %d hash %d' % (len(text), len(words), value))


if __name__ == '__main__':
    main()
