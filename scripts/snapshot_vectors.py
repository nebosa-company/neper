"""Independent oracle for e.test.snapshot (L128), built on pytest-snapshot.

Each case is a stored snapshot file (as a user or pytest-snapshot would leave it, no
header) and a candidate text. pytest-snapshot's own `assert_match` is run over every
case; its verdict and the module's rule must agree, except where the only difference is
trailing whitespace at the end of the whole text or CR bytes, which the module ignores
on purpose (insta's rule; pytest-snapshot compares newline-normalised text exactly) and
the case is marked `t`. `--emit` prints `name~stored_hex~candidate_hex~verdict` with the
verdict `m` (match) or `d` (differ) under the module's rule, plus the line
`@update~name~hex` for what `pytest --snapshot-update` writes for a candidate.

Usage: python scripts/snapshot_vectors.py [--emit]
pytest and pytest-snapshot must be importable (python -m pip install --target DIR
pytest pytest-snapshot; PYTHONPATH=DIR).
"""
import contextlib
import io
import json
import os
import random
import shutil
import sys
import tempfile
import textwrap


def my_rule(stored, candidate):
    """The module's documented comparison: CR dropped, trailing whitespace of the whole text ignored."""
    return stored.replace('\r', '').rstrip() == candidate.replace('\r', '').rstrip()


def words(rng, n):
    return ' '.join(rng.choice(['alpha', 'beta', 'gamma', 'delta', 'x=1', 'y=22', '{a: 1}', '[1, 2]', 'tab\there'])
                    for _ in range(n))


def make_text(rng):
    return '\n'.join(words(rng, rng.randint(0, 5)) for _ in range(rng.randint(1, 6)))


def make_cases():
    rng = random.Random(128)
    cases = []
    for i in range(60):
        base = make_text(rng)
        kind = i % 10
        stored, candidate, trailing = base, base, False
        if kind == 1:
            candidate = base + '\n'
            trailing = True
        elif kind == 2:
            stored = base + '\n\n'
            trailing = True
        elif kind == 3:
            stored = base.replace('\n', '\r\n')
            trailing = True
        elif kind == 4:
            candidate = base + ' '
            trailing = True
        elif kind == 5:
            j = rng.randrange(len(base) + 1)
            candidate = base[:j] + 'Q' + base[j:]
        elif kind == 6:
            candidate = base + '\nextra line'
        elif kind == 7:
            candidate = base.split('\n', 1)[-1] if '\n' in base else base + 'z'
        elif kind == 8:
            candidate = ' ' + base
        cases.append({'stored': stored, 'candidate': candidate, 'trailing': trailing})
    return cases


TEST_MODULE = '''
import json, os
import pytest
CASES = json.load(open(os.environ["SNAP_CASES"], encoding="utf-8"))
DIR = os.environ["SNAP_DIR"]

@pytest.mark.parametrize("i", range(len(CASES)))
def test_case(i, snapshot):
    snapshot.snapshot_dir = DIR
    snapshot.assert_match(CASES[i]["candidate"], "c%d.snap" % i)
'''


class Collector:
    def __init__(self):
        self.verdicts = {}

    def pytest_runtest_logreport(self, report):
        if report.when == 'call':
            self.verdicts[report.nodeid] = report.passed


COUNTER = [0]


def run(cases, update):
    import pytest
    COUNTER[0] += 1
    module = 'test_snap_%d' % COUNTER[0]
    work = tempfile.mkdtemp(prefix='snapvec')
    try:
        snapdir = os.path.join(work, 'snaps')
        os.makedirs(snapdir)
        casefile = os.path.join(work, 'cases.json')
        with open(casefile, 'w', encoding='utf-8') as f:
            json.dump(cases, f)
        with open(os.path.join(work, module + '.py'), 'w', encoding='utf-8') as f:
            f.write(TEST_MODULE)
        if not update:
            for i, c in enumerate(cases):
                with open(os.path.join(snapdir, 'c%d.snap' % i), 'wb') as f:
                    f.write(c['stored'].encode('utf-8'))
        os.environ['SNAP_CASES'] = casefile
        os.environ['SNAP_DIR'] = snapdir
        collector = Collector()
        os.chdir(work)
        args = ['-q', '-p', 'no:cacheprovider', '--rootdir', work, module + '.py']
        if update:
            args.append('--snapshot-update')
        with contextlib.redirect_stdout(io.StringIO()):
            pytest.main(args, plugins=[collector])
        verdicts = [collector.verdicts[module + '.py::test_case[%d]' % i] for i in range(len(cases))]
        written = []
        if update:
            for i in range(len(cases)):
                with open(os.path.join(snapdir, 'c%d.snap' % i), 'rb') as f:
                    written.append(f.read())
        return verdicts, written
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    cases = make_cases()
    verdicts, _ = run(cases, False)
    _, written = run(cases, True)
    out = []
    for i, (c, passed) in enumerate(zip(cases, verdicts)):
        mine = my_rule(c['stored'], c['candidate'])
        if not c['trailing']:
            assert mine == passed, (i, c, mine, passed)
        out.append('c%d~%s~%s~%s' % (i, c['stored'].encode().hex(), c['candidate'].encode().hex(), 'm' if mine else 'd'))
    for i, data in enumerate(written):
        out.append('@update~c%d~%s' % (i, data.hex()))
    return out


if __name__ == '__main__':
    lines = main()
    if '--emit' in sys.argv:
        print('\n'.join(lines))
    else:
        total = sum(1 for l in lines if not l.startswith('@'))
        agree = sum(1 for l in lines if l.endswith('~m'))
        print('snapshot_vectors: %d cases (%d match under the module rule); pytest-snapshot agrees outside trailing-whitespace cases' % (total, agree))
