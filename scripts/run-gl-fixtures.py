"""Run the gpu_* link fixtures that launch on Vulkan devices on e.gpu's .Gl backend instead (T047, D5906).

Each fixture's source is rewritten into build/gl-fixtures/<target>/<name>/src/main.e: `.Vulkan` becomes `.Gl`, the program
imports x.khronos.compute and calls its `install()` (`install_es()` with --es) first thing in `main`. It is built with
`--gpu glsl` by build/windows/neper-try.exe and run: directly for `windows`, through `wsl.exe` for `linux`. The fixtures
check themselves against the CPU backend, so the exit code is the verdict; the last output line is reported beside it.

    python scripts/run-gl-fixtures.py windows
    python scripts/run-gl-fixtures.py linux [--es] [NAME...]
    python scripts/run-gl-fixtures.py windows --ui [--es]

With --ui (T046, D5907) it runs the ui_* fixtures that open host windows instead, each window presenting through GL:
the program calls x.khronos.present's `install()` (`install_es()`) first, and no backend is rewritten.

Fixtures that already open .Gl devices themselves (gpu_gl*, and those importing x.khronos.compute) are left to the suites.
"""
import os
import re
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = os.path.join(REPO, 'tests', 'selfhost', 'fixtures', 'link')
COMPILER = os.environ.get('NEPER_COMPILER') or os.path.join(REPO, 'build', 'windows', 'neper-try.exe')
# The flags the suites build a fixture with.
FLAGS = {'gpu_fault_unchecked': ['--unchecked']}
MAIN = re.compile(r'^fn main\(a: \*mem\.Arena, args: \[\]str\) -> err \{$', re.M)


def rewrite(source, es, ui):
    if not MAIN.search(source):
        return None
    module = 'present' if ui else 'compute'
    if not ui:
        source = source.replace('.Vulkan', '.Gl')
    install = 'install_es' if es else 'install'
    source = MAIN.sub(lambda m: m.group(0) + '\n    ' + module + '.' + install + '()', source, count=1)
    # At the end, so every kernel keeps the line its fault records name.
    return source + '\nuse x.khronos.' + module + '\n'


def wsl_path(path):
    drive, rest = os.path.splitdrive(path)
    return '/mnt/' + drive[0].lower() + rest.replace('\\', '/')


def main(argv):
    target = argv[1]
    es = '--es' in argv
    ui = '--ui' in argv
    names = [n for n in argv[2:] if n not in ('--es', '--ui')]
    if not names and ui:
        names = sorted(n for n in os.listdir(LINK) if n.startswith('ui_')
                       and os.path.isfile(os.path.join(LINK, n, 'src', 'main.e'))
                       and re.search(r'app\.init\[|window\.open\(', open(os.path.join(LINK, n, 'src', 'main.e'), encoding='utf-8').read()))
    if not names:
        names = sorted(n for n in os.listdir(LINK) if n.startswith('gpu_') and not n.startswith('gpu_gl')
                       and os.path.isfile(os.path.join(LINK, n, 'src', 'main.e'))
                       and '.Vulkan' in open(os.path.join(LINK, n, 'src', 'main.e'), encoding='utf-8').read()
                       and 'x.khronos.compute' not in open(os.path.join(LINK, n, 'src', 'main.e'), encoding='utf-8').read())
    out = os.path.join(REPO, 'build', 'gl-fixtures', target + ('-es' if es else '') + ('-ui' if ui else ''))
    failed = 0
    for name in names:
        source = rewrite(open(os.path.join(LINK, name, 'src', 'main.e'), encoding='utf-8').read(), es, ui)
        if source is None:
            print('%-40s skipped: no main(a, args)' % name)
            continue
        root = os.path.join(out, name)
        shutil.rmtree(root, ignore_errors=True)
        shutil.copytree(os.path.join(LINK, name, 'src'), os.path.join(root, 'src'))
        open(os.path.join(root, 'src', 'main.e'), 'w', encoding='utf-8', newline='\n').write(source)
        program = os.path.join(root, name + ('.exe' if target == 'windows' else ''))
        built = subprocess.run([COMPILER, 'emit-executable', os.path.join(root, 'src', 'main.e'), REPO, 'x64', target,
                                program, '--gpu', 'glsl'] + FLAGS.get(name, []), capture_output=True, text=True)
        if 'executable written' not in built.stdout:
            print('%-40s did not build: %s' % (name, (built.stdout + built.stderr).strip().splitlines()[-1:]))
            failed += 1
            continue
        if target == 'windows':
            ran = subprocess.run([program], capture_output=True, text=True, cwd=REPO, timeout=600)
        else:
            ran = subprocess.run(['wsl.exe', '-e', 'sh', '-c', 'cd %s && timeout 300 %s' % (wsl_path(REPO), wsl_path(program))],
                                 capture_output=True, text=True, timeout=600)
        tail = (ran.stdout + ran.stderr).strip().splitlines()
        print('%-40s exit %d  %s' % (name, ran.returncode, tail[-1] if tail else ''))
        if ran.returncode != 0:
            failed += 1
    print('%d of %d failed' % (failed, len(names)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
