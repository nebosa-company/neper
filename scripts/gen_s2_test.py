#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_s2/src/main.e (L135): e.fmt.s2 against klauspost/compress/s2.

Needs Go and network access for the module (once): the vectors come from scripts/s2_vectors.go (the Go encoder's
Encode, EncodeBetter and EncodeBest blocks and its framed writer) and are decoded by the Neper decoder; the sizes
pinned for the Neper encoder were each decoded by Go's s2.Decode and s2.NewReader when they were recorded.

    python scripts/gen_s2_test.py
"""
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "selfhost" / "fixtures" / "link" / "fmt_s2" / "src" / "main.e"


def vectors():
    with tempfile.TemporaryDirectory() as t:
        shutil.copy(ROOT / "scripts" / "s2_vectors.go", Path(t) / "main.go")
        r = None
        for cmd in (["go", "mod", "init", "vec"], ["go", "get", "github.com/klauspost/compress/s2"], ["go", "run", "."]):
            r = subprocess.run(cmd, cwd=t, capture_output=True, text=True)
            if r.returncode != 0:
                raise SystemExit(r.stderr)
        return json.loads(r.stdout)


def arr(name, hexstr):
    data = bytes.fromhex(hexstr)
    return "    let %s: [%d]u8 = [%d]u8{ %s }\n" % (name, len(data), len(data), ", ".join(str(b) for b in data))


HEAD = '''// `e.fmt.s2` against klauspost/compress/s2 (scripts/gen_s2_test.py, scripts/s2_vectors.go): blocks from its Encode,
// EncodeBetter and EncodeBest (literals, 1- and 2-byte-offset copies, repeats with several length codes, runs) and its
// framed writer decode to the generated inputs; the Neper encoder round-trips them and its sizes are pinned (each
// output was decoded by Go's s2.Decode and s2.NewReader when pinned); and the refusals. Every check has its own exit
// code.
use e.fmt.s2 as s2
use e.mem
use e.os

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn lcg(state: u64) -> u64 { ret state *% 6364136223846793005u64 +% 1442695040888963407u64 }

// Runs, copies of earlier bytes and random bytes from an LCG (scripts/s2_vectors.go mirrors it).
fn fill(out: []u8, seed: u64) {
    var state = seed
    var n = 0usize
    while n < out.len {
        state = lcg(state)
        let r = state >> 33u32
        let mode = r % 3u64
        if mode == 0u64 {
            let b = u8((r >> 8u32) & 255u64)
            var k = 8usize + usize((r >> 16u32) % 40u64)
            while k > 0usize && n < out.len {
                out[n] = b
                n += 1usize
                k -= 1usize
            }
        } else if mode == 1u64 && n >= 64usize {
            let off = 1usize + usize((r >> 8u32) % 60u64)
            var k = 4usize + usize((r >> 16u32) % 30u64)
            while k > 0usize && n < out.len {
                out[n] = out[n - off]
                n += 1usize
                k -= 1usize
            }
        } else {
            var k = 1usize + usize((r >> 16u32) % 12u64)
            while k > 0usize {
                state = lcg(state)
                if n < out.len {
                    out[n] = u8((state >> 33u32) & 255u64)
                    n += 1usize
                }
                k -= 1usize
            }
        }
    }
}

// The inputs: 0 the 3072-byte LCG buffer, 1 "abcdefgh" x 1000, 2 forty LCG bytes, zeros and the forty again 70,040
// bytes on (80 bytes past 70,000), 3 a x 5000, 4 a x 70000, 5 a x 300, 6 empty, 7 a x 5, 8 the LCG buffer and fifty
// more LCG bytes.
fn make(which: usize, out: []u8) -> usize {
    var i = 0usize
    if which == 0usize {
        fill(out[..3072usize], 12345u64)
        ret 3072usize
    }
    if which == 1usize {
        while i < 8000usize {
            out[i] = u8(97usize + i % 8usize)
            i += 1usize
        }
        ret 8000usize
    }
    if which == 2usize {
        while i < 70080usize {
            out[i] = 0u8
            i += 1usize
        }
        var head: [40]u8 = zero
        fill(head[..], 99u64)
        i = 0usize
        while i < 40usize {
            out[i] = head[i]
            out[70040usize + i] = head[i]
            i += 1usize
        }
        ret 70080usize
    }
    if which == 3usize || which == 4usize || which == 5usize || which == 7usize {
        var count = 5000usize
        if which == 4usize { count = 70000usize }
        if which == 5usize { count = 300usize }
        if which == 7usize { count = 5usize }
        while i < count {
            out[i] = 97u8
            i += 1usize
        }
        ret count
    }
    if which == 8usize {
        fill(out[..3072usize], 12345u64)
        fill(out[3072usize..3122usize], 7u64)
        ret 3122usize
    }
    ret 0usize
}

fn decodes_to(block: []const u8, which: usize) -> bool {
    var want: [75000]u8 = zero
    let count = make(which, want[..])
    var got: [75000]u8 = zero
    let (m, e) = s2.decode(block, got[..])
    ret e == ok && m == count && same(got[..m], want[..count])
}

fn stream_decodes_to(stream: []const u8, which: usize) -> bool {
    var want: [75000]u8 = zero
    let count = make(which, want[..])
    var got: [75000]u8 = zero
    let (m, e) = s2.decode_framed(stream, got[..])
    ret e == ok && m == count && same(got[..m], want[..count])
}

// Encodes input `which`; the block must decode back and have `size` bytes, the framed stream `framed`.
fn roundtrips(which: usize, size: usize, framed: usize) -> bool {
    var want: [75000]u8 = zero
    let count = make(which, want[..])
    var table: [16384]u16 = zero
    var enc: [90000]u8 = zero
    let (m, e) = s2.encode(want[..count], enc[..], table[..])
    if e != ok || m != size { ret false }
    var got: [75000]u8 = zero
    let (k, de) = s2.decode(enc[..m], got[..])
    if de != ok || k != count || !same(got[..k], want[..count]) { ret false }
    var fr: [90000]u8 = zero
    let (fm, fe) = s2.encode_framed(want[..count], fr[..], table[..])
    if fe != ok || fm != framed { ret false }
    let (fk, fde) = s2.decode_framed(fr[..fm], got[..])
    ret fde == ok && fk == count && same(got[..fk], want[..count])
}

fn length_of(block: []const u8) -> usize {
    let (count, e) = s2.decoded_length(block)
    if e != ok { ret 0usize }
    ret count
}

fn decode_error(block: []const u8, cap: usize) -> err {
    var sink: [128]u8 = zero
    let (m, e) = s2.decode(block, sink[..cap])
    ret e
}

fn framed_error(stream: []const u8) -> err {
    var sink: [4096]u8 = zero
    let (m, e) = s2.decode_framed(stream, sink[..])
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
'''

CASES = [("enc_a", 0), ("better_a", 0), ("best_a", 0), ("better_abc", 1), ("best_abc", 1), ("enc_far", 2), ("best_far", 2),
         ("best_a5000", 3), ("best_a70000", 4), ("better_a300", 5), ("enc_empty", 6)]
# input, the Neper block's size, the Neper framed stream's size
PINS = [(0, 864, 882), (1, 18, 36), (2, 52, 80), (3, 11, 29), (4, 21, 49), (5, 10, 28), (6, 1, 10), (7, 7, 23)]


def main():
    v = vectors()
    out = [HEAD]
    n = 0

    def check(cond):
        nonlocal n
        n += 1
        out.append("    if %s { os.exit(%di32) }\n" % (cond, n))

    for name, which in CASES:
        out.append(arr(name, v[name]))
        check("!decodes_to(%s[..], %dusize)" % (name, which))
    out.append(arr("stream_a", v["stream_a"]))
    check("!stream_decodes_to(stream_a[..], 8usize)")
    out.append(arr("stream_snappy", v["stream_snappy"]))
    check("!stream_decodes_to(stream_snappy[..], 0usize)")
    check("length_of(enc_a[..]) != 3072usize")
    for which, size, framed in PINS:
        check("!roundtrips(%dusize, %dusize, %dusize)" % (which, size, framed))
    # refusals: a repeat before any copy set an offset, an offset before the start, output past the preamble, a short
    # destination, a flipped CRC, a stream without its identifier, a reserved chunk
    out.append("    let repeat_first: [3]u8 = [3]u8{ 8, 1, 0 }\n")
    check("decode_error(repeat_first[..], 64usize) != s2.Invalid")
    out.append("    let far_copy: [4]u8 = [4]u8{ 4, 0, 97, 1 }\n")
    check("decode_error(far_copy[..], 64usize) != s2.Invalid")
    out.append("    let short_out: [3]u8 = [3]u8{ 40, 0, 97 }\n")
    check("decode_error(short_out[..], 64usize) != s2.Invalid")
    check("decode_error(enc_a[..], 100usize) != s2.TooSmall")
    out.append("    var flipped = stream_a\n    flipped[14] = flipped[14] ^ 255u8\n")
    check("framed_error(flipped[..]) != s2.Checksum")
    out.append("    let headless: [8]u8 = [8]u8{ 1, 4, 0, 0, 0, 0, 0, 0 }\n")
    check("framed_error(headless[..]) != s2.Invalid")
    out.append("    let reserved: [14]u8 = [14]u8{ 255, 6, 0, 0, 83, 50, 115, 84, 119, 79, 2, 0, 0, 0 }\n")
    check("framed_error(reserved[..]) != s2.Invalid")
    out.append("    ret ok\n}\n")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote %d checks" % n)


main()
