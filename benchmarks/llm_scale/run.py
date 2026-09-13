"""Emit one program in five languages, then measure tokens, correctness, compile, run and size.

  python run.py [--groups N] [--trials K] [--langs a,b]
"""
import argparse, json, os, pathlib, shutil, statistics, subprocess, sys, time
import tiktoken, spec
import emit_neper, emit_rust, emit_go, emit_js, emit_ts

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
GEN = HERE / "gen"
ENC = tiktoken.get_encoding("cl100k_base")
GOEXE = r"D:\toolchains\go\bin\go.exe"
NEPER = REPO / "build" / "windows" / "neper-try.exe"

EMITTERS = {m.NAME: m for m in (emit_neper, emit_rust, emit_go, emit_js, emit_ts)}


def sh(cmd, cwd=None, timeout=1800):
    # node/tsc/rustc arrive as .cmd or .exe shims; resolve so CreateProcess finds them.
    exe = shutil.which(cmd[0])
    if exe is None:
        raise FileNotFoundError(f"not on PATH: {cmd[0]}")
    cmd = [exe] + list(cmd[1:])
    t = time.perf_counter()
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return time.perf_counter() - t, p


def steps(name, src, out):
    """(compile_cmd | None, run_cmd, artifact_for_size)"""
    if name == "neper":
        return [str(NEPER), "emit-executable", str(src), str(REPO), "x64", "windows", str(out)], [str(out)], out
    if name == "rust":
        return ["rustc", "-C", "debuginfo=0", str(src), "-o", str(out)], [str(out)], out
    if name == "go":
        return [GOEXE, "build", "-o", str(out), src.name], [str(out)], out
    if name == "javascript":
        return None, ["node", str(src)], src
    if name == "typescript":
        js = out.with_suffix(".js")
        return ["tsc", str(src), "--outDir", str(out.parent), "--target", "es2020"], ["node", str(js)], js
    raise KeyError(name)


def measure(name, groups, trials, expect):
    mod = EMITTERS[name]
    GEN.mkdir(exist_ok=True)
    src = GEN / f"{name}.{mod.EXT}"
    out = GEN / f"{name}.exe"
    source = mod.emit(groups)
    src.write_text(source, encoding="utf-8", newline="\n")

    row = {"lang": name, "lines": source.count("\n"), "bytes": len(source.encode()),
           "tokens": len(ENC.encode(source))}

    compile_cmd, run_cmd, artifact = steps(name, src, out)
    cwd = str(GEN) if name == "go" else None
    if name == "go":  # a single-file build needs a module
        (GEN / "go.mod").write_text("module bench\n\ngo 1.27\n", encoding="utf-8", newline="\n")

    ct = []
    if compile_cmd:
        for _ in range(trials):
            for stale in (out, out.with_suffix(".js")):
                stale.unlink(missing_ok=True)
            d, p = sh(compile_cmd, cwd=cwd)
            if p.returncode != 0:
                row["error"] = (p.stderr or p.stdout).strip().splitlines()[:2]
                row["correct"] = False
                return row
            ct.append(d)
        row["compile_ms"] = round(statistics.median(ct) * 1000, 1)
    else:
        row["compile_ms"] = None

    rt, got = [], None
    for _ in range(trials):
        d, p = sh(run_cmd, cwd=cwd)
        if p.returncode != 0:
            row["error"] = (p.stderr or p.stdout).strip().splitlines()[:2]
            row["correct"] = False
            return row
        rt.append(d)
        got = p.stdout.strip()
    row["run_ms"] = round(statistics.median(rt) * 1000, 1)
    row["output"] = got
    row["correct"] = got == str(expect)
    row["artifact_bytes"] = artifact.stat().st_size if artifact.exists() else None
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--groups", type=int, default=spec.GROUPS)
    ap.add_argument("--trials", type=int, default=3)
    ap.add_argument("--langs", default=",".join(EMITTERS))
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    expect = spec.expected(a.groups)
    print(f"groups={a.groups} leaves={a.groups*spec.LEAF_PER_GROUP} expected={expect} trials={a.trials}\n")
    rows = []
    for name in a.langs.split(","):
        r = measure(name.strip(), a.groups, a.trials, expect)
        rows.append(r)
        ok = "OK " if r.get("correct") else "ERR"
        c = f'{r["compile_ms"]:>9.1f}' if r.get("compile_ms") is not None else "      n/a"
        rr = f'{r["run_ms"]:>8.1f}' if r.get("run_ms") is not None else "     n/a"
        sz = f'{r["artifact_bytes"]:>10,}' if r.get("artifact_bytes") else "         -"
        print(f'{ok} {r["lang"]:<11} lines={r["lines"]:>7,} tokens={r["tokens"]:>9,} '
              f'compile={c}ms run={rr}ms size={sz}')
        if r.get("error"):
            print(f'      -> {r["error"]}')
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(rows, indent=1), encoding="utf-8")
    return rows


if __name__ == "__main__":
    main()
