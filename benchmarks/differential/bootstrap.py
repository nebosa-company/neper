"""The C bootstrap as an oracle for the self-hosted codegen (D456, H10).

    python benchmarks/differential/bootstrap.py COMPILER BOOTSTRAP ROOT ARCH OS OUTDIR FIXTURE...

Each fixture -- a `tests/neper0` program the bootstrap accepts -- is built twice,
by the bootstrap (`BOOTSTRAP build FILE --output IMAGE`) and by the self-hosted
compiler (`COMPILER emit-executable FILE ROOT ARCH OS IMAGE`), both images are run
with no arguments, and the exit codes and stdout must agree. The two back ends
share no code: the bootstrap is C, the compiler is neper. A fixture the bootstrap
refuses to build is reported and skipped, never counted; exit 1 on the first pair
that disagrees.
"""
import os, subprocess, sys

compiler, bootstrap, root, arch, host_os, outdir = sys.argv[1:7]
fixtures = sys.argv[7:]
os.makedirs(outdir, exist_ok=True)
exe = '.exe' if host_os == 'windows' else ''


def run(argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True)


def executable(path):
    if host_os != 'windows':
        os.chmod(path, 0o755)


agreed, skipped = 0, []
for fixture in fixtures:
    name = os.path.splitext(os.path.basename(fixture))[0]
    by_bootstrap = os.path.join(outdir, name + '-bootstrap' + exe)
    by_self = os.path.join(outdir, name + '-self' + exe)
    built = run([bootstrap, 'build', fixture, '--output', by_bootstrap])
    if built.returncode != 0:
        skipped.append(name)
        continue
    built_self = run([compiler, 'emit-executable', fixture, root, arch, host_os, by_self])
    if built_self.returncode != 0:
        sys.exit('bootstrap-oracle: the self-hosted compiler refused %s that the bootstrap built: %s' % (name, built_self.stderr.decode('utf-8', 'replace')))
    executable(by_bootstrap)
    executable(by_self)
    ran_a, ran_b = run([by_bootstrap], cwd=outdir), run([by_self], cwd=outdir)
    if (ran_a.returncode, ran_a.stdout) != (ran_b.returncode, ran_b.stdout):
        sys.exit('bootstrap-oracle: %s disagrees: bootstrap exit %d %r, self exit %d %r' % (name, ran_a.returncode, ran_a.stdout[:200], ran_b.returncode, ran_b.stdout[:200]))
    agreed += 1
print('bootstrap-oracle: %d programs agree with the bootstrap%s' % (agreed, ('; skipped (the bootstrap refuses them): ' + ', '.join(skipped)) if skipped else ''))
