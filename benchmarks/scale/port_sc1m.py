"""Port a benchmarks/scale/generate.py program to single-file flattened
equivalents for dart/go/rust/zig/js/ts/python.

  python benchmarks/scale/port_sc1m.py --src sc1m/src --out sc1m/ports [--seed-note]

Semantics: i64, all values non-negative, final mask & 1073741823 (2^30-1).
JS/TS use % 1073741824 instead of the bitmask (identical for non-negative
values < 2^53; a native & would truncate 36-bit intermediates to 32 bits).
Python gets a raised recursion limit (call chains can approach 1000 deep;
generate.py itself needs sys.setrecursionlimit(20000) for its oracle).
Zig prints through std.debug.print (stderr); capture merged streams.
"""
import argparse
import pathlib
import re

FN = re.compile(r"^fn job(\d+)\(n: i64\) -> i64 \{$")
REC = re.compile(r"^    var r = Rec \{ a: n, b: (\d+)i64 \}$")
WHILE = re.compile(r"^    while i < (\d+)i64 \{$")
IF = re.compile(r"^        if \(acc \+ i\) % (\d+)i64 == 0i64 \{ acc = acc \+ r\.a \} else \{ acc = acc \+ r\.b \}$")
RETCALL = re.compile(r"^    ret \(acc \+ (m\d+)\.job(\d+)\(n % 1000i64\)\) & 1073741823i64$")
RETACC = re.compile(r"^    ret acc & 1073741823i64$")
MAIN = re.compile(r"^    sum = \(sum \* 31i64 \+ (m\d+)\.job0\((\d+)i64\)\) & 1073741823i64$")


def parse(src):
    mods = []  # [(name, [(k, m2, m3, m1, callee|None)])]
    for path in sorted(p for p in src.glob("m*.e") if p.stem != "main"):
        name = path.stem
        fns = []
        cur = None
        for line in path.read_text(encoding="utf-8").splitlines():
            m = FN.match(line)
            if m:
                cur = {"k": m.group(1)}
                continue
            m = REC.match(line)
            if m and cur is not None:
                cur["m2"] = m.group(1)
                continue
            m = WHILE.match(line)
            if m and cur is not None:
                cur["m3"] = m.group(1)
                continue
            m = IF.match(line)
            if m and cur is not None:
                cur["m1"] = m.group(1)
                continue
            m = RETCALL.match(line)
            if m and cur is not None:
                cur["callee"] = (m.group(1), m.group(2))
                fns.append(cur)
                cur = None
                continue
            if RETACC.match(line) and cur is not None:
                cur["callee"] = None
                fns.append(cur)
                cur = None
                continue
        assert cur is None, (name, cur)
        mods.append((name, [(f["k"], f["m2"], f["m3"], f["m1"], f["callee"])
                           for f in fns]))
    main_calls = []
    for line in (src / "main.e").read_text(encoding="utf-8").splitlines():
        m = MAIN.match(line)
        if m:
            main_calls.append((m.group(1), m.group(2)))
    return mods, main_calls


def emit(path, mods, main_calls, head, fn, main_head, main_call, main_tail,
         cmt="//"):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        w = f.write
        for line in head:
            w(line + "\n")
        for name, fns in mods:
            w(f"{cmt} Module {name}: {len(fns)} functions.\n")
            for (k, m2, m3, m1, callee) in fns:
                for line in fn(name, k, m2, m3, m1, callee):
                    w(line + "\n")
            w("\n")
        for line in main_head:
            w(line + "\n")
        for (mod, arg) in main_calls:
            w(main_call(mod, arg) + "\n")
        for line in main_tail:
            w(line + "\n")
    with open(path, encoding="utf-8") as f:
        print(path.name, "lines:", sum(1 for _ in f), flush=True)


MASK = "1073741823"
MASKP1 = "1073741824"  # 2^30, for JS/TS % instead of &


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True,
                    help="generate.py output dir holding src/*.e")
    ap.add_argument("--out", required=True, help="ports directory to write")
    args = ap.parse_args()
    src = pathlib.Path(args.src)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    mods, main_calls = parse(src)
    total_fns = sum(len(f) for _, f in mods)
    print(f"parsed: {len(mods)} modules, {total_fns} functions, "
          f"{len(main_calls)} main calls", flush=True)

    emit(out / "sc1m.dart", mods, main_calls,
         ["// sc1m port: flattened Neper scale benchmark.",
          "class Rec { int a; int b; Rec(this.a, this.b); }", ""],
         lambda name, k, m2, m3, m1, callee: (
            [f"int {name}_job{k}(int n) {{", f"  var r = Rec(n, {m2});",
             "  var acc = 0;", "  var i = 0;", f"  while (i < {m3}) {{",
             f"    if ((acc + i) % {m1} == 0) {{ acc = acc + r.a; }} else {{ acc = acc + r.b; }}",
             "    i = i + 1;", "  }",
             (f"  return (acc + {callee[0]}_job{callee[1]}(n % 1000)) & {MASK};"
              if callee else f"  return acc & {MASK};"), "}", ""]),
         ["void main() {", "  var sum = 0;"],
         lambda mod, arg: f"  sum = (sum * 31 + {mod}_job0({arg})) & {MASK};",
         ["  print(sum);", "}"])

    emit(out / "sc1m.go", mods, main_calls,
         ["// sc1m port: flattened Neper scale benchmark.",
          "package main", "", 'import "fmt"', "",
          "type Rec struct { a, b int64 }", ""],
         lambda name, k, m2, m3, m1, callee: (
            [f"func {name}_job{k}(n int64) int64 {{", f"  r := Rec{{n, {m2}}}",
             "  var acc int64 = 0", "  var i int64 = 0", f"  for i < {m3} {{",
             f"    if (acc+i)%{m1} == 0 {{ acc = acc + r.a }} else {{ acc = acc + r.b }}",
             "    i = i + 1", "  }",
             (f"  return (acc + {callee[0]}_job{callee[1]}(n % 1000)) & {MASK}"
              if callee else f"  return acc & {MASK}"), "}", ""]),
         ["func main() {", "  var sum int64 = 0"],
         lambda mod, arg: f"  sum = (sum*31 + {mod}_job0({arg})) & {MASK}",
         ["  fmt.Println(sum)", "}"])

    emit(out / "sc1m.rs", mods, main_calls,
         ["// sc1m port: flattened Neper scale benchmark.",
          "struct Rec { a: i64, b: i64 }", ""],
         lambda name, k, m2, m3, m1, callee: (
            [f"fn {name}_job{k}(n: i64) -> i64 {{",
             f"  let r = Rec {{ a: n, b: {m2} }};",
             "  let mut acc: i64 = 0;", "  let mut i: i64 = 0;",
             f"  while i < {m3} {{",
             f"    if (acc + i) % {m1} == 0 {{ acc = acc + r.a; }} else {{ acc = acc + r.b; }}",
             "    i = i + 1;", "  }",
             (f"  (acc + {callee[0]}_job{callee[1]}(n % 1000)) & {MASK}"
              if callee else f"  acc & {MASK}"), "}", ""]),
         ["fn main() {", "  let mut sum: i64 = 0;"],
         lambda mod, arg: f"  sum = (sum * 31 + {mod}_job0({arg})) & {MASK};",
         ['  println!("{}", sum);', "}"])

    emit(out / "sc1m.zig", mods, main_calls,
         ["// sc1m port: flattened Neper scale benchmark.",
          "// NOTE: debug.print writes stderr; capture merged streams.",
          'const std = @import("std");', "",
          "const Rec = struct { a: i64, b: i64 };", ""],
         lambda name, k, m2, m3, m1, callee: (
            [f"fn {name}_job{k}(n: i64) i64 {{",
             f"  var r = Rec{{ .a = n, .b = {m2} }};",
             "  var acc: i64 = 0;", "  var i: i64 = 0;",
             f"  while (i < {m3}) {{",
             f"    if (@rem(acc + i, {m1}) == 0) {{ acc = acc + r.a; }} else {{ acc = acc + r.b; }}",
             "    i = i + 1;", "  }",
             (f"  return (acc + {callee[0]}_job{callee[1]}(@rem(n, 1000))) & {MASK};"
              if callee else f"  return acc & {MASK};"), "}", ""]),
         ["pub fn main() void {", "  var sum: i64 = 0;"],
         lambda mod, arg: f"  sum = (sum * 31 + {mod}_job0({arg})) & {MASK};",
         ['  std.debug.print("{d}\\n", .{sum});', "}"])

    emit(out / "sc1m.js", mods, main_calls,
         ["// sc1m port: flattened Neper scale benchmark.",
          "// NOTE: % 2^30 instead of & mask (identical for non-negative < 2^53).", ""],
         lambda name, k, m2, m3, m1, callee: (
            [f"function {name}_job{k}(n) {{",
             f"  let a = n, b = {m2};",
             "  let acc = 0;", "  let i = 0;", f"  while (i < {m3}) {{",
             f"    if ((acc + i) % {m1} === 0) {{ acc = acc + a; }} else {{ acc = acc + b; }}",
             "    i = i + 1;", "  }",
             (f"  return (acc + {callee[0]}_job{callee[1]}(n % 1000)) % {MASKP1};"
              if callee else f"  return acc % {MASKP1};"), "}", ""]),
         ["let sum = 0;"],
         lambda mod, arg: f"sum = (sum * 31 + {mod}_job0({arg})) % {MASKP1};",
         ["console.log(sum);"])

    emit(out / "sc1m.ts", mods, main_calls,
         ["// sc1m port: flattened Neper scale benchmark.",
          "// NOTE: % 2^30 instead of & mask (identical for non-negative < 2^53).", ""],
         lambda name, k, m2, m3, m1, callee: (
            [f"function {name}_job{k}(n: number): number {{",
             f"  let a: number = n, b: number = {m2};",
             "  let acc: number = 0;", "  let i: number = 0;",
             f"  while (i < {m3}) {{",
             f"    if ((acc + i) % {m1} === 0) {{ acc = acc + a; }} else {{ acc = acc + b; }}",
             "    i = i + 1;", "  }",
             (f"  return (acc + {callee[0]}_job{callee[1]}(n % 1000)) % {MASKP1};"
              if callee else f"  return acc % {MASKP1};"), "}", ""]),
         ["let sum: number = 0;"],
         lambda mod, arg: f"sum = (sum * 31 + {mod}_job0({arg})) % {MASKP1};",
         ["console.log(sum);"])

    emit(out / "sc1m.py", mods, main_calls,
         ["# sc1m port: flattened Neper scale benchmark.",
          "import sys", "sys.setrecursionlimit(100000)  # call chains run deep", ""],
         lambda name, k, m2, m3, m1, callee: (
            [f"def {name}_job{k}(n: int) -> int:",
             f"    a = n; b = {m2}",
             "    acc = 0", "    i = 0", f"    while i < {m3}:",
             f"        if (acc + i) % {m1} == 0: acc = acc + a",
             "        else: acc = acc + b",
             "        i = i + 1",
             (f"    return (acc + {callee[0]}_job{callee[1]}(n % 1000)) & {MASK}"
              if callee else f"    return acc & {MASK}"), ""]),
         ["gsum = 0"],
         lambda mod, arg: f"gsum = (gsum * 31 + {mod}_job0({arg})) & {MASK}",
         ["print(gsum)"], cmt="#")
    print("ports written", flush=True)


if __name__ == "__main__":
    main()
