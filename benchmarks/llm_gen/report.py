# -*- coding: utf-8 -*-
"""Generated-code report (T023, tooling.md section 9): first-pass rates against the thresholds.

For each task in tasks/<name>/ the candidate `<name>/neper.e` -- by default the committed reference
solution, or a model's output laid out the same way under --candidates DIR -- is put through the
real toolchain and scored on the four thresholds of the roadmap's cross-milestone verification:

  parse first pass      parse-file accepts it                                     >= 95%
  type-check first pass check-file accepts it                                     >= 90%
  zero unrelated diff   `fmt FILE --check` finds it already canonical, so a
                        model's formatting never adds a diff beside its change    100%
  one-turn repair       of the candidates that failed parse or check, the share
                        whose --repairs DIR/<name>/neper.e passes check             >= 95%

and, beyond the thresholds, whether the built program prints expected.txt (`correct`).

What this does NOT do: ask a model for the candidates. That needs a provider and a budget; the
harness for it is benchmarks/llm_edit (agent command) and the H12 evaluation. Run on the
reference solutions it is a regression gate on the corpus and the toolchain, and the report says
so ("source": "reference"); it must not be quoted as a model's pass rate.

    python benchmarks/llm_gen/report.py --compiler build/windows/neper-self.exe [--candidates DIR]
        [--repairs DIR] [--json] [--strict]
"""
import argparse, json, os, pathlib, subprocess, sys, tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
TASKS = pathlib.Path(__file__).resolve().parent / 'tasks'

THRESHOLDS = {'parse': 0.95, 'check': 0.90, 'format': 1.00, 'repair': 0.95}


def run(cmd, cwd=None, timeout=300):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).decode('utf-8', 'replace')


def score_candidate(compiler, source, host, expected, workdir):
    """parse, check, format and run results for one source file."""
    code, out = run([compiler, 'parse-file', str(source)])
    parse = code == 0 and 'parse file ok' in out
    code, out = run([compiler, 'check-file', str(source), str(REPO), 'x64', host])
    check = code == 0 and 'module check ok' in out
    code, _ = run([compiler, 'fmt', str(source), '--check'])
    fmt = code == 0
    correct = False
    if check and expected is not None:
        exe = pathlib.Path(workdir) / (source.parent.name + ('.exe' if host == 'windows' else ''))
        code, out = run([compiler, 'emit-executable', str(source), str(REPO), 'x64', host, str(exe)])
        if code == 0 and 'executable written' in out and exe.exists():
            code, got = run([str(exe)], timeout=30)
            correct = code == 0 and got.replace('\r\n', '\n') == expected
    return {'parse': parse, 'check': check, 'format': fmt, 'correct': correct}


def summarize(rows, repaired, source):
    """Rates and verdicts from per-task rows; `repaired` maps a failed task to its repair's check."""
    n = len(rows)
    rate = lambda key: (sum(1 for r in rows if r[key]) / n) if n else 0.0
    failed = [r['task'] for r in rows if not (r['parse'] and r['check'])]
    fixed = [t for t in failed if repaired.get(t)]
    repair_rate = (len(fixed) / len(failed)) if failed else None
    report = {
        'source': source, 'tasks': n,
        'rates': {'parse': rate('parse'), 'check': rate('check'), 'format': rate('format'),
                  'correct': rate('correct'), 'repair': repair_rate},
        'failed_first_pass': failed, 'repaired_in_one_turn': fixed,
        'thresholds': THRESHOLDS,
    }
    verdict = {
        'parse': report['rates']['parse'] >= THRESHOLDS['parse'],
        'check': report['rates']['check'] >= THRESHOLDS['check'],
        'format': report['rates']['format'] >= THRESHOLDS['format'],
        # Nothing failed: nothing to repair, and the threshold is met vacuously.
        'repair': True if repair_rate is None else repair_rate >= THRESHOLDS['repair'],
    }
    report['verdict'] = verdict
    report['pass'] = all(verdict.values()) and n > 0
    return report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', default=str(REPO / 'build' / 'windows' / 'tests' / 'selfhost' / 'neper-self.exe'))
    ap.add_argument('--candidates', help='DIR/<task>/neper.e; default is the committed reference solutions')
    ap.add_argument('--repairs', help='DIR/<task>/neper.e: the one repair turn for a first pass that failed')
    ap.add_argument('--host', default='windows' if os.name == 'nt' else 'linux')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--strict', action='store_true', help='exit 1 unless every threshold is met')
    args = ap.parse_args()
    candidates = pathlib.Path(args.candidates) if args.candidates else None
    source = 'candidates' if candidates else 'reference'
    rows, repaired = [], {}
    with tempfile.TemporaryDirectory() as work:
        for task in sorted(p for p in TASKS.iterdir() if p.is_dir()):
            expected_path = task / 'expected.txt'
            expected = expected_path.read_bytes().decode('utf-8').replace('\r\n', '\n') if expected_path.exists() else None
            src = (candidates / task.name / 'neper.e') if candidates else task / 'neper.e'
            if not src.exists():
                rows.append({'task': task.name, 'parse': False, 'check': False, 'format': False, 'correct': False})
                continue
            row = score_candidate(args.compiler, src, args.host, expected, work)
            row['task'] = task.name
            rows.append(row)
            if not (row['parse'] and row['check']) and args.repairs:
                fix = pathlib.Path(args.repairs) / task.name / 'neper.e'
                if fix.exists():
                    r = score_candidate(args.compiler, fix, args.host, None, work)
                    repaired[task.name] = r['parse'] and r['check']
    report = summarize(rows, repaired, source)
    report['rows'] = rows
    if args.json:
        print(json.dumps(report, indent=1, sort_keys=True))
    else:
        rates = report['rates']
        print(f"generated-code report ({source}, {report['tasks']} tasks)")
        for key in ('parse', 'check', 'format', 'repair'):
            value = rates[key]
            shown = 'n/a (nothing failed)' if value is None else f'{value * 100:.0f}%'
            print(f"  {key:7s} {shown:22s} threshold {THRESHOLDS[key] * 100:.0f}%  {'ok' if report['verdict'][key] else 'BELOW'}")
        print(f"  correct {rates['correct'] * 100:.0f}% (the built program prints expected.txt)")
    if args.strict and not report['pass']:
        sys.exit(1)


if __name__ == '__main__':
    main()
