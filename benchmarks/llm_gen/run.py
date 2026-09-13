# -*- coding: utf-8 -*-
"""Generation-cost smoke benchmark: Neper vs Rust on the same small tasks.

For every task in tasks/<name>/ it measures, per language:
  tokens      -- source tokens (tiktoken cl100k_base; a cross-language proxy, not Claude's tokenizer)
  compile_ms  -- median wall time to build an executable (both languages in debug mode)
  compile_ok  -- the build succeeded
  run_ms      -- median wall time to run it
  correct     -- stdout matched expected.txt
  size        -- executable bytes

This is a SMOKE run with reference (hand-written, first-try) solutions. It measures source
density and toolchain cost, not a live model's few-shot/repair loop -- that is the M2.5 / H12
evaluation in docs/post-m2-llm-hardening.md. Run from the repository root:

    python benchmarks/llm_gen/run.py [--trials 3] [--neper build/windows/neper-try.exe]
"""
import argparse, json, os, pathlib, statistics, subprocess, sys, time

REPO = pathlib.Path(__file__).resolve().parents[2]
TASKS = pathlib.Path(__file__).resolve().parent / 'tasks'


def timed(cmd, cwd=None):
    t0 = time.perf_counter()
    p = subprocess.run(cmd, cwd=cwd, capture_output=True)
    return (time.perf_counter() - t0) * 1000.0, p


def median_of(fn, trials):
    times, last = [], None
    for _ in range(trials):
        ms, last = fn()
        times.append(ms)
    return statistics.median(times), last


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--trials', type=int, default=3)
    ap.add_argument('--neper', default=str(REPO / 'build' / 'windows' / 'neper-try.exe'))
    ap.add_argument('--out', default=str(REPO / 'build' / 'gen'))
    args = ap.parse_args()
    import tiktoken
    enc = tiktoken.get_encoding('cl100k_base')
    out = pathlib.Path(args.out); out.mkdir(parents=True, exist_ok=True)
    exe = '.exe' if os.name == 'nt' else ''
    rows = []
    for task in sorted(p for p in TASKS.iterdir() if p.is_dir()):
        expected = (task / 'expected.txt').read_bytes().replace(b'\r\n', b'\n')
        for lang, src, build in (
            ('neper', task / 'neper.e', lambda s, o: [args.neper, 'emit-executable', str(s), str(REPO), 'x64', 'windows' if os.name == 'nt' else 'linux', str(o)]),
            ('rust', task / 'rust.rs', lambda s, o: ['rustc', str(s), '-o', str(o)]),
        ):
            binary = out / f'{task.name}-{lang}{exe}'
            tokens = len(enc.encode(src.read_text(encoding='utf-8')))
            compile_ms, cp = median_of(lambda: timed(build(src, binary)), args.trials)
            compile_ok = cp.returncode == 0 and binary.exists()
            run_ms, correct, size = None, False, 0
            if compile_ok:
                size = binary.stat().st_size
                run_ms, rp = median_of(lambda: timed([str(binary)]), args.trials)
                correct = rp.returncode == 0 and rp.stdout.replace(b'\r\n', b'\n') == expected
            rows.append(dict(task=task.name, lang=lang, tokens=tokens, compile_ms=round(compile_ms, 1),
                             compile_ok=compile_ok, run_ms=None if run_ms is None else round(run_ms, 1),
                             correct=correct, size=size))
    (out / 'llm_gen.json').write_text(json.dumps(rows, indent=1), encoding='utf-8')
    print('| task | lang | tokens | compile ms | ok | run ms | correct | size B |')
    print('|---|---|---:|---:|:-:|---:|:-:|---:|')
    for r in rows:
        print(f"| {r['task']} | {r['lang']} | {r['tokens']} | {r['compile_ms']} | {'y' if r['compile_ok'] else 'N'} | {r['run_ms']} | {'y' if r['correct'] else 'N'} | {r['size']} |")
    print()
    for lang in ('neper', 'rust'):
        rs = [r for r in rows if r['lang'] == lang]
        ok = [r for r in rs if r['correct']]
        print(f"{lang}: tokens={sum(r['tokens'] for r in rs)}  correct={len(ok)}/{len(rs)}  "
              f"median compile={statistics.median(r['compile_ms'] for r in rs):.1f}ms  "
              f"median run={statistics.median(r['run_ms'] for r in ok):.1f}ms  "
              f"median size={statistics.median(r['size'] for r in ok):.0f}B")
    return 0 if all(r['correct'] for r in rows) else 1


if __name__ == '__main__':
    sys.exit(main())
