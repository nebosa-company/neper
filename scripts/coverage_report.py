#!/usr/bin/env python3
"""Compiler line coverage: callgrind runs merged against the compiler's DWARF line table.

  coverage_report.py --runs DIR --lines FILE [--exempt docs/coverage-exempt.tsv]
                     [--floor PCT] [--json OUT] [--uncovered src/check.e] [--include-runtime]

--lines is `objdump --dwarf=decodedline COMPILER`. --runs holds callgrind outputs made with
--dump-line=yes. A line counts when the line table has it and some run executed it; lines
named in the exempt list are removed from both sides. Exit 1 when --floor is not met.
"""
import argparse, collections, glob, json, os, re, sys


def parse_callgrind(path):
    # callgrind numbers files (fl/fi/fe/cfi/cfl) and functions (fn/cfn) separately
    files, fns = {}, {}
    cur, line, skip = None, 0, False
    hit = collections.defaultdict(set)

    def res(tok, table):
        m = re.match(r'\((\d+)\)(?: (.*))?$', tok)
        if not m:
            return tok
        if m.group(2) is not None:
            table[m.group(1)] = m.group(2)
        return table.get(m.group(1), '?')

    with open(path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            s = raw.rstrip('\n')
            if not s:
                continue
            if s[:3] in ('fl=', 'fi=', 'fe='):
                cur = res(s[3:], files)
            elif s.startswith('fn='):
                res(s[3:], fns)
            elif s.startswith(('cfi=', 'cfl=')):
                res(s[4:], files)
            elif s.startswith('cfn='):
                res(s[4:], fns)
            elif s.startswith('calls='):
                skip = True
            elif s[0].isdigit() or s[0] in '+-*':
                parts = s.split()
                p = parts[0]
                if p[0] == '+':
                    line += int(p[1:])
                elif p[0] == '-':
                    line -= int(p[1:])
                elif p != '*':
                    line = int(p)
                if skip:
                    skip = False
                elif cur and len(parts) > 1 and int(parts[1]) > 0:
                    hit[cur[2:] if cur.startswith('./') else cur].add(line)
    return hit


def parse_line_table(path):
    out = collections.defaultdict(set)
    for raw in open(path, encoding='utf-8', errors='replace'):
        m = re.match(r'^(\S.*?\.e)\s+(\d+)\s+0x[0-9a-f]+', raw)
        if m:
            out[m.group(1)].add(int(m.group(2)))
    return out


def parse_exempt(path):
    ex = collections.defaultdict(set)
    if not path or not os.path.exists(path):
        return ex
    for n, raw in enumerate(open(path, encoding='utf-8'), 1):
        if not raw.strip() or raw.startswith('#') or raw.startswith('file\t'):
            continue
        cols = raw.rstrip('\n').split('\t')
        if len(cols) < 3 or not cols[2].strip():
            sys.exit(f'{path}:{n}: want file<TAB>line or lo-hi<TAB>reason')
        lo, _, hi = cols[1].partition('-')
        ex[cols[0]].update(range(int(lo), int(hi or lo) + 1))
    return ex


def ranges(lines):
    lines = sorted(lines)
    out, i = [], 0
    while i < len(lines):
        j = i
        while j + 1 < len(lines) and lines[j + 1] - lines[j] <= 1:
            j += 1
        out.append(f'{lines[i]}' if i == j else f'{lines[i]}-{lines[j]}')
        i = j + 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--runs', required=True)
    ap.add_argument('--lines', required=True)
    ap.add_argument('--exempt', default='docs/coverage-exempt.tsv')
    ap.add_argument('--floor', type=float)
    ap.add_argument('--json')
    ap.add_argument('--uncovered')
    ap.add_argument('--include-runtime', action='store_true')
    a = ap.parse_args()

    valid = {f: ls for f, ls in parse_line_table(a.lines).items()
             if f.startswith('src/') and (a.include_runtime or not f.startswith('src/runtime_'))}
    exempt = parse_exempt(a.exempt)
    runs = sorted(glob.glob(os.path.join(a.runs, '*.out')))
    if not runs:
        sys.exit(f'no callgrind outputs in {a.runs}')
    union = collections.defaultdict(set)
    for r in runs:
        for f, ls in parse_callgrind(r).items():
            if f in valid:
                union[f] |= ls & valid[f]

    rows, hit_all, tot_all = [], 0, 0
    for f in sorted(valid):
        lines = valid[f] - exempt[f]
        hit = union[f] & lines
        rows.append({'file': f, 'hit': len(hit), 'lines': len(lines),
                     'exempt': len(valid[f] & exempt[f]),
                     'uncovered': ranges(lines - hit)})
        hit_all += len(hit)
        tot_all += len(lines)
    pct = 100.0 * hit_all / max(tot_all, 1)

    if a.uncovered:
        row = next((r for r in rows if r['file'] == a.uncovered), None)
        print(' '.join(row['uncovered']) if row else f'{a.uncovered}: not in the line table')
        return
    for r in sorted(rows, key=lambda r: r['hit'] / max(r['lines'], 1)):
        print(f"{r['hit']:6d}/{r['lines']:6d} {100.0 * r['hit'] / max(r['lines'], 1):5.1f}%  {r['file']}")
    print(f'TOTAL {hit_all}/{tot_all} {pct:.1f}%  runs={len(runs)} exempt={sum(r["exempt"] for r in rows)}')
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            json.dump({'hit': hit_all, 'lines': tot_all, 'percent': round(pct, 2),
                       'runs': len(runs), 'files': rows}, f, indent=1)
    if a.floor is not None and pct < a.floor:
        sys.exit(f'coverage {pct:.2f}% is below the floor {a.floor}%')


if __name__ == '__main__':
    main()
