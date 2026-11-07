"""Static checks that keep tests/selfhost/run.sh and run.ps1 the same suite on two shells.

  1. run.sh parses (`bash -n`): bash reads a script as it runs, so a syntax error 9000 lines in would otherwise
     show up 45 minutes into a run.
  2. Every variable run.sh reads (ALL_CAPS ones are the environment) is assigned somewhere in it; `set -u` makes the first read of one that is
     not fatal, late in the run.
  3. The fixtures the two scripts name are the same, except those that exist on one host only.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
selfhost = root / "tests" / "selfhost"
sh_text = (selfhost / "run.sh").read_text(encoding="utf-8")
ps_text = (selfhost / "run.ps1").read_text(encoding="utf-8")

# A fixture one script runs and the other cannot: Windows UI Automation and SSPI against X11 and AT-SPI.
ONE_HOST = {
    "os_uia": "ps1",
    "x_tds_integrated": "ps1",
    "os_atspi": "sh",
    "os_window_buttons": "sh",
    "os_window_resize": "ps1",
    "import_touch": "ps1",
    "mem_commit_refused": "ps1",
    # X11 loader behaviour and a Linux-only syscall surface.
    "x_khronos_xlib_loader_race": "sh",
    "proc_sys_x86_linux": "sh",
    # Windows window layout, and the Khronos context teardown only Windows reaches.
    "proc_sys_windows_layout": "ps1",
    "x_khronos_context_cleanup": "ps1",
    # Formatting fixtures the Linux runner names and the Windows one does not yet.
    "fmt_css_selector_validation": "sh",
    "fmt_mermaid": "sh",
    "fmt_woff2_bounds": "sh",
}

failures = []

bash = shutil.which("bash")
if bash:
    # By stdin: on Windows `bash` can be WSL's, which does not read a Windows path.
    check = subprocess.run([bash, "-n"], input=sh_text.encode("utf-8"), capture_output=True)
    if check.returncode != 0:
        failures.append("run.sh does not parse: " + check.stderr.decode("utf-8", "replace").strip().splitlines()[0])
else:
    print("skipped: bash is not on PATH, run.sh was not parsed")

NAME = r"[A-Za-z_][A-Za-z0-9_]*"
# Set by a ports file the suite sources after it starts a database server.
SOURCED = {"pg_port", "mysql_port", "tds_port", "tds_root", "tds_user", "tds_password"}
assigned = set(re.findall(rf"(?<![\w$])({NAME})\+?=", sh_text)) | SOURCED
assigned |= set(re.findall(rf"\bfor\s+({NAME})\s+in\b", sh_text))
assigned |= set(re.findall(rf"\b(?:mapfile|readarray)\s+(?:-\w+\s+)*({NAME})", sh_text))
for names in re.findall(rf"\bread\s+(?:-\w+\s+)*((?:{NAME}\s*)+)", sh_text):
    assigned |= set(names.split())
read = {}
for number, line in enumerate(sh_text.split("\n"), 1):
    if line.lstrip().startswith("#"):
        continue
    for name in re.findall(rf"\$\{{?({NAME})", line):
        if name != name.upper():
            read.setdefault(name, number)
for name, number in sorted(read.items(), key=lambda item: item[1]):
    if name not in assigned:
        failures.append(f"run.sh line {number} reads ${name}, which is never assigned")

def fixtures(text):
    return set(re.findall(r"fixtures[/\\]+link[/\\]+([a-z0-9_]+)", text))

in_sh, in_ps = fixtures(sh_text), fixtures(ps_text)
for name in sorted(in_sh - in_ps):
    if ONE_HOST.get(name) != "sh":
        failures.append(f"fixture {name} is in run.sh and not run.ps1")
for name in sorted(in_ps - in_sh):
    if ONE_HOST.get(name) != "ps1":
        failures.append(f"fixture {name} is in run.ps1 and not run.sh")
for name in ONE_HOST:
    if name not in (in_sh if ONE_HOST[name] == "sh" else in_ps):
        failures.append(f"ONE_HOST lists {name}, which {ONE_HOST[name]} no longer names")

# A fixture directory no suite runs is a test that has stopped testing. extra-fixtures.txt holds the ones neither
# script names; `differential` belongs to scripts/a64-differential.
extra = {line.strip() for line in (selfhost / "extra-fixtures.txt").read_text(encoding="utf-8").split("\n") if line.strip()}
NOT_SUITE = {"differential"}
named = in_sh | in_ps | extra | NOT_SUITE
for main in sorted((selfhost / "fixtures" / "link").glob("*/src/main.e")):
    name = main.parent.parent.name
    # `macos_*` fixtures are the Mac corpus's (tests/macos): they need AppKit, so neither suite names them.
    if name.startswith("macos_"): continue
    if name not in named:
        failures.append(f"fixture {name} is run by no suite: add it to tests/selfhost/extra-fixtures.txt")
for name in sorted(extra):
    if not (selfhost / "fixtures" / "link" / name / "src" / "main.e").exists():
        failures.append(f"extra-fixtures.txt names {name}, which has no src/main.e")
    if name in in_sh or name in in_ps:
        failures.append(f"extra-fixtures.txt names {name}, which a suite script already runs")

# The compiler the suite runs must be a release build. A debug build fills every allocation
# with 0xCD (D306, section 11), and an arena pool charges what it touches, so every pool the
# loader sizes from the program is committed whether it holds anything or not: 6.6-8.9 GB
# against 365 MB on Windows and 371 MB on Linux, for byte-identical output. The suite spends
# hours in that compiler, so losing the flag is not a slowdown, it is what makes the suite
# exhaust a machine shared with anything else. Checked here because both runners build that
# stage and nothing else would notice a runner that stopped asking for it.
COMPILER_BUILD = re.compile(r"emit-executable[^\n]*src[\\/]main\.e")
for label, text, target in (("run.sh", sh_text, '"$test_build/neper-self"'), ("run.ps1", ps_text, "$compiler")):
    number, line = None, None
    for at, candidate in enumerate(text.split("\n"), 1):
        # The first emit-executable of src/main.e is the stage this suite runs everything
        # with; later ones build comparison compilers, which are their own business.
        if COMPILER_BUILD.search(candidate) and target in candidate:
            number, line = at, candidate
            break
    if number is None:
        failures.append(f"{label} does not build the self-hosted compiler from src/main.e")
    elif "--release" not in line:
        failures.append(
            f"{label} line {number} builds the self-hosted compiler without --release: a debug "
            "build commits every pool it sizes (D306), 6.6-8.9 GB against 365 MB"
        )

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print(f"suite parity ok: run.sh names {len(in_sh | extra)} fixtures, run.ps1 names {len(in_ps | extra)}, both build the compiler with --release")
