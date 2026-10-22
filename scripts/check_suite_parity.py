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
}

failures = []

bash = shutil.which("bash")
if bash:
    check = subprocess.run([bash, "-n", str(selfhost / "run.sh")], capture_output=True, text=True)
    if check.returncode != 0:
        failures.append("run.sh does not parse: " + check.stderr.strip().splitlines()[0])
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

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("suite parity ok")
