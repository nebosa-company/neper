"""Shared emitter for the L056-L064 library fixtures.

A generator builds a list of vector lines ``op|field|field|...`` (numbers
space-separated inside a field, written with ``repr`` so the fixture's
`str.parse_f64` reads back the exact double) and hands them to ``emit`` with the
Neper source of its ``check`` function. The emitted ``main.e`` chunks the lines
into ``vectors_N`` functions (one string literal each), splits them into
fields and exits with the failing chunk number plus a printed line.
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

COMMON = r'''
fn near(x: f64, want: f64, eps: f64) -> bool {
    if x != x || want != want { ret x != x && want != want }
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    var scale = want
    if scale < 0.0f64 { scale = 0.0f64 - scale }
    if scale < 1.0f64 { scale = 1.0f64 }
    ret d <= eps * scale
}

// Parses a field of space-separated numbers into `out` and answers how many.
fn nums(field: str, out: []f64) -> usize {
    var count = 0usize
    let (it0, e0) = str.split(str.trim(field), " ")
    if e0 != ok { ret 0usize }
    var it = it0
    while true {
        let (piece, more) = str.split_next(&it)
        if !more { break }
        if piece.len == 0usize { continue }
        let (v, pe) = str.parse_f64(piece)
        if pe != ok { os.exit(97i32) }
        if count < out.len {
            out[count] = v
            count += 1usize
        }
    }
    ret count
}

fn load(field: str, out: []f64) {
    let loaded = nums(field, out)
}

fn run_chunk(block: str) -> u32 {
    let (lines0, le) = str.split(block, "\n")
    if le != ok { ret 99u32 }
    var lines = lines0
    var failed = 0u32
    while true {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        if line.len == 0usize { continue }
        let (parts0, pe) = str.split(line, "|")
        if pe != ok { ret 98u32 }
        var parts = parts0
        var fields: [8]str = zero
        var nf = 0usize
        while nf < 8usize {
            let (piece, got) = str.split_next(&parts)
            if !got { break }
            fields[nf] = piece
            nf += 1usize
        }
        if !check(fields[..], nf) {
            let shown = io.print(line)
            let nl = io.print("\n")
            failed += 1u32
        }
    }
    ret failed
}
'''


def emit(fixture, header, uses, harness, lines, ok_text, per_chunk=40, arena=False):
    """Write tests/selfhost/fixtures/link/<fixture>/src/main.e."""
    only = os.environ.get("FIXTURE_ONLY")
    if only:
        lines = [l for l in lines if l.split("|")[0] in set(only.split(","))]
    out = [header.rstrip() + "\n"]
    uses = sorted(set(uses) | {"use e.io", "use e.mem", "use e.os", "use e.str"})
    out += [u + "\n" for u in uses]
    common = COMMON
    if arena:
        common = common.replace('fn run_chunk(block: str) -> u32 {', 'fn run_chunk(a: *mem.Arena, block: str) -> u32 {')
        common = common.replace('if !check(fields[..], nf) {',
                                'let mark = mem.mark(a)\n        let passed = check(a, fields[..], nf)\n        mem.reset(a, mark)\n        if !passed {')
    out.append(common)
    out.append(harness)
    chunks = [lines[i:i + per_chunk] for i in range(0, len(lines), per_chunk)]
    for n, chunk in enumerate(chunks):
        body = "\\n".join(l.replace("\\", "\\\\").replace('"', '\\"') for l in chunk)
        out.append(f'\nfn vectors_{n}() -> str {{\n    ret "{body}"\n}}\n')
    main = ["\nfn main(a: *mem.Arena, args: []str) -> err {\n"]
    main.append("    var failed = 0u32\n")
    for n in range(len(chunks)):
        main.append(f"    failed += run_chunk({'a, ' if arena else ''}vectors_{n}())\n")
    main.append("    if failed != 0u32 { os.exit(1i32) }\n")
    main.append(f'    try io.print("{ok_text}")\n    ret ok\n}}\n')
    out.append("".join(main))
    dest = ROOT / "tests" / "selfhost" / "fixtures" / "link" / fixture / "src" / "main.e"
    if os.environ.get("FIXTURE_OUT"):
        dest = Path(os.environ["FIXTURE_OUT"])
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("".join(out), encoding="utf-8", newline="\n")
    print(f"{dest} ({len(lines)} vectors in {len(chunks)} chunks)")


def fmt(values):
    """Space-separated reprs; a list/array of floats."""
    return " ".join(repr(float(v)) for v in values)
