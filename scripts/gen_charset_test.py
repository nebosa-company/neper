"""Regenerates the byte-frequency tables inside lib/e/text/encoding.e and the vectors of
tests/selfhost/fixtures/link/text_charset/src/main.e (L110).

The model is trained from scripts/charset_corpus.py. The fixture replays the held-out
test sentences, encoded in every charset that serves their language, through
`detect_legacy` and checks (charset id, confidence) against the Python port of the same
algorithm below. Accuracy against the ground-truth charset (an answer counts when it
decodes the bytes to the same text) and against chardet / charset-normalizer, when
importable, is printed so the decision row can quote it.

    PYTHONPATH=<dir with chardet,charset_normalizer> python scripts/gen_charset_test.py
"""
import math, os, re, sys, unicodedata
sys.path.insert(0, os.path.dirname(__file__))
from charset_corpus import TRAIN, TEST, CHARSETS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENC = os.path.join(ROOT, "lib", "e", "text", "encoding.e")
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "text_charset", "src", "main.e")


def fix_ro(s):
    return s.replace("ș", "ş").replace("ț", "ţ").replace("Ș", "Ş").replace("Ț", "Ţ")


def encode(codec, s):
    return fix_ro(s).encode(codec)


def build_tables():
    tables = []
    for codec, label, langs in CHARSETS:
        counts = [0] * 128
        joined = lone = 0
        for lg in langs:
            data = encode(codec, TRAIN[lg])
            for i, b in enumerate(data):
                if b >= 128:
                    counts[b - 128] += 1
                    if i > 0 and data[i - 1] >= 128:
                        joined += 1
                    else:
                        lone += 1
        # class-based smoothing: an unseen letter of this charset is far likelier than an unseen symbol
        pseudo = []
        for k in range(128):
            ch = bytes([128 + k]).decode(codec, errors="replace")
            cat = unicodedata.category(ch)
            pseudo.append(0.6 if cat == "Ll" else 0.25 if cat in ("Lu", "Lo") else 0.01 if ch != "�" else 0.002)
        total = sum(counts) + sum(pseudo)
        row = [min(63, round(-2 * math.log2((counts[k] + pseudo[k]) / total))) for k in range(128)]
        pj = (joined + 1) / (joined + lone + 2)
        row.append(min(63, round(-2 * math.log2(pj))))
        row.append(min(63, round(-2 * math.log2(1 - pj))))
        tables.append(row)
    return tables


def detect(tables, data):
    counts = [0] * 128
    high = joined = 0
    for i, b in enumerate(data):
        if b >= 128:
            counts[b - 128] += 1
            high += 1
            if i > 0 and data[i - 1] >= 128:
                joined += 1
    lone = high - joined
    n = len(tables)
    if high == 0:
        return n, 60
    cost = [sum(counts[i] * t[i] for i in range(128)) + joined * t[128] + lone * t[129] for t in tables]
    best = 0
    for c in range(1, n):
        if cost[c] < cost[best]:
            best = c
    rest = 0
    for c in range(n):
        if c != best:
            gap = min(cost[c] - cost[best], 400)
            w = 100000
            for _ in range(gap):
                w = w * 917 // 1000
            rest += w
    conf = min(99, 10000000 // (100000 + rest))
    return best, conf


def table_source(tables):
    out = ["const LEGACY_COUNT: usize = %dusize" % len(tables), ""]
    out.append("fn legacy_name(id: usize) -> str {")
    for i, (_, label, _) in enumerate(CHARSETS):
        out.append('    if id == %dusize { ret "%s" }' % (i, label))
    out.append('    ret "us-ascii"')
    out.append("}")
    out.append("")
    out.append("// Per-byte cost of 0x80..0xFF under each model: the character is '0' plus the cost.")
    out.append("fn legacy_table(id: usize) -> str {")
    for i, row in enumerate(tables):
        lit = "".join(("\\\\" if chr(48 + v) == "\\" else chr(48 + v)) for v in row)
        out.append('    if id == %dusize { ret "%s" }' % (i, lit))
    out.append('    ret "%s"' % ("0" * 130))
    out.append("}")
    return "\n".join(out) + "\n"


def patch_module(src):
    s = open(ENC, encoding="utf-8").read()
    a = s.index("// BEGIN generated tables")
    b = s.index("// END generated tables")
    head = s[:a] + "// BEGIN generated tables (scripts/gen_charset_test.py)\n"
    s = head + src + s[b:]
    open(ENC, "w", encoding="utf-8", newline="\n").write(s)


def vectors(tables):
    rows = []
    for ci, (codec, label, langs) in enumerate(CHARSETS):
        for lg in langs:
            sents = TEST.get(lg, [])
            for s in sents + [" ".join(sents)]:
                try:
                    data = encode(codec, s)
                except UnicodeEncodeError as e:
                    print("skip", label, lg, e)
                    continue
                rows.append((ci, lg, data))
                if len(data) > 40:
                    rows.append((ci, lg, data[:23]))
    # ascii, a lone high byte and the empty run
    rows.append((-1, "ascii", b"plain ascii only"))
    rows.append((0, "one", encode("cp1252", "café")))
    return rows


def decodes_same(truth_codec, guess_codec, data):
    try:
        return data.decode(truth_codec) == data.decode(guess_codec)
    except Exception:
        return False


def accuracy(tables, rows):
    codecs = [c[0] for c in CHARSETS]
    right = tot = 0
    bad = []
    for ci, lg, data in rows:
        if ci < 0 or not any(b >= 128 for b in data):
            continue
        g, conf = detect(tables, data)
        tot += 1
        if decodes_same(codecs[ci], codecs[g], data):
            right += 1
        else:
            bad.append((CHARSETS[ci][1], CHARSETS[g][1], lg, len(data), conf))
    return right, tot, bad


def oracle(rows):
    try:
        import chardet
        import charset_normalizer
    except ImportError:
        return
    codecs = [c[0] for c in CHARSETS]
    r1 = r2 = tot = 0
    for ci, lg, data in rows:
        if ci < 0 or not any(b >= 128 for b in data):
            continue
        tot += 1
        n = chardet.detect(data)["encoding"]
        if n and decodes_same(codecs[ci], n, data):
            r1 += 1
        m = charset_normalizer.from_bytes(data).best()
        if m and decodes_same(codecs[ci], m.encoding, data):
            r2 += 1
    print("oracle accuracy on the same %d vectors: chardet %d, charset-normalizer %d" % (tot, r1, r2))


FIXTURE = """// `e.text.encoding.detect_legacy` against its independent Python port (scripts/gen_charset_test.py): the held-out
// test sentences of 10+ languages, encoded in every legacy charset that serves them, in full and truncated. Each
// vector is `hex charset-id confidence;`. Every check has its own exit code.
use e.io
use e.mem
use e.os
use e.str
use e.text.encoding as enc

fn nib(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn run_chunk(a: *mem.Arena, v: str) -> u32 {
    var i = 0usize
    var seen = 0u32
    while i < v.len {
        let start = i
        while v[i] != 32u8 { i += 1usize }
        let count = (i - start) / 2usize
        let (buf, e) = mem.alloc[u8](a, count + 1usize)
        if e != ok { ret 1000u32 }
        var k = 0usize
        while k < count {
            buf[k] = (nib(v[start + 2usize * k]) << 4u8) | nib(v[start + 2usize * k + 1usize])
            k += 1usize
        }
        i += 1usize
        var id = 0u32
        while v[i] != 32u8 {
            id = id * 10u32 + u32(v[i] - 48u8)
            i += 1usize
        }
        i += 1usize
        var conf = 0u32
        while v[i] != 59u8 {
            conf = conf * 10u32 + u32(v[i] - 48u8)
            i += 1usize
        }
        i += 1usize
        let g = enc.detect_legacy(buf[0usize..count])
        if u32(g.charset) != id || u32(g.confidence) != conf { ret seen + 1u32 }
        seen += 1u32
    }
    ret 0u32
}

%(chunks)s
fn main(a: *mem.Arena, args: []str) -> err {
%(calls)s
    // names and the one-call answer
    if !str.eq(enc.legacy_name(0usize), "windows-1252") || !str.eq(enc.legacy_name(%(ascii)dusize), "us-ascii") { os.exit(90i32) }
    let koi: [6]u8 = [6]u8{ 208, 210, 201, 215, 197, 212 }
    let (n1, c1) = enc.detect_name(koi[0..])
    if !str.eq(n1, "koi8-r") || c1 == 0u8 { os.exit(91i32) }
    let wide: [4]u8 = [4]u8{ 97, 0, 98, 0 }
    let (n2, c2) = enc.detect_name(wide[0..])
    if !str.eq(n2, "utf-16le") || c2 != 70u8 { os.exit(92i32) }
    let plain: [3]u8 = [3]u8{ 97, 98, 99 }
    let g3 = enc.detect_legacy(plain[0..])
    if usize(g3.charset) != %(ascii)dusize || g3.confidence != 60u8 { os.exit(93i32) }
    try io.print("text charset ok")
    ret ok
}
"""


def write_fixture(tables, rows):
    entries = []
    for ci, lg, data in rows:
        g, conf = detect(tables, data)
        entries.append("%s %d %d;" % (data.hex(), g, conf))
    per = 40
    chunks, calls = [], []
    for k in range(0, len(entries), per):
        n = k // per
        body = "".join(entries[k:k + per])
        chunks.append('fn vectors_%d() -> str {\n    ret "%s"\n}\n' % (n, body))
        calls.append("    if run_chunk(a, vectors_%d()) != 0u32 { os.exit(%di32) }" % (n, n + 1))
    src = FIXTURE % {"chunks": "\n".join(chunks), "calls": "\n".join(calls), "ascii": len(tables)}
    os.makedirs(os.path.dirname(FIX), exist_ok=True)
    open(FIX, "w", encoding="utf-8", newline="\n").write(src)
    return len(entries)


def main():
    tables = build_tables()
    patch_module(table_source(tables))
    rows = vectors(tables)
    right, tot, bad = accuracy(tables, rows)
    print("detect_legacy accuracy: %d/%d" % (right, tot))
    for b in bad:
        print("  miss", b)
    oracle(rows)
    n = write_fixture(tables, rows)
    print("vectors:", n)


main()
