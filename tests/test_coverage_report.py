import os, subprocess, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORT = os.path.join(ROOT, 'scripts', 'coverage_report.py')

# file id (2) and function id (2) name different things; line 12 of src/b.e is only a call cost
CALLGRIND = """fl=(1) ./src/a.e
fn=(1) a.f
10 5
11 3
fl=(2) ./src/b.e
fn=(2) b.g
12 0
cfn=(1)
calls=1 0
12 99
13 4
"""

LINES = """CU: src/a.e:
src/a.e   10   0x400000   x
src/a.e   11   0x400010   x
src/a.e   12   0x400020   x
src/b.e   12   0x400030   x
src/b.e   13   0x400040   x
src/runtime_x.e   1   0x400050   x
"""


def report(exempt=None, *extra):
    with tempfile.TemporaryDirectory() as d:
        os.mkdir(os.path.join(d, 'runs'))
        ex = os.path.join(d, 'ex.tsv')
        for path, text in ((os.path.join(d, 'runs', 'r.out'), CALLGRIND),
                           (os.path.join(d, 'lines.txt'), LINES),
                           (ex, exempt or 'file\tline\treason\n')):
            with open(path, 'w') as f:
                f.write(text)
        return subprocess.run([sys.executable, '-I', REPORT, '--runs', os.path.join(d, 'runs'),
                               '--lines', os.path.join(d, 'lines.txt'), '--exempt', ex, *extra],
                              capture_output=True, text=True)


class CoverageReport(unittest.TestCase):
    def test_files_and_functions_have_separate_id_spaces(self):
        out = report().stdout
        self.assertIn('2/     3', out.split('src/a.e')[0].splitlines()[-1])
        self.assertIn('TOTAL 3/5 60.0%', out)

    def test_call_cost_lines_are_not_hits_and_runtime_is_excluded(self):
        self.assertEqual(report(None, '--uncovered', 'src/b.e').stdout.strip(), '12')

    def test_exempt_lines_leave_both_sides(self):
        out = report('src/a.e\t12\tunreachable\nsrc/b.e\t12\tcall only\n').stdout
        self.assertIn('TOTAL 3/3 100.0%  runs=1 exempt=2', out)

    def test_floor_fails_below_and_passes_at(self):
        self.assertNotEqual(report(None, '--floor', '61').returncode, 0)
        self.assertEqual(report(None, '--floor', '60').returncode, 0)

    def test_exempt_without_reason_is_refused(self):
        self.assertNotEqual(report('src/a.e\t12\t\n').returncode, 0)


if __name__ == '__main__':
    unittest.main()
