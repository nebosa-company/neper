"""Write golden-refreshing variants of the suite runners next to them: run-refresh.ps1 and
run-refresh.sh, in which every `<actual> differs from the conformance corpus` check copies
the actual output over the golden (printing `REFRESHED <golden>`) instead of failing, and
the static gate re-pins its baseline. Use them ONLY to collect a batch of moved goldens
(a library module every program links, such as e.mem, moves every snapshot golden), then
AUDIT each refreshed file's diff -- only snapshot hashes, module digests, explain-inline
rows or a moved span may differ -- and run the real runner clean before committing. The
generated files are not committed. usage: python make_refresh_runners.py <repo root>
"""
import re, sys
from pathlib import Path

root = Path(sys.argv[1])

ps = open(root / 'tests/selfhost/run.ps1', encoding='utf-8', newline='').read()
ps_pat = re.compile(r"if \(\(Get-FileHash -Algorithm SHA256 -LiteralPath (.+?)\)\.Hash -ne "
                    r"\(Get-FileHash -Algorithm SHA256 -LiteralPath (.+?)\)\.Hash\) \{ throw "
                    r"(['\"])[^'\"]*differs? from the conformance corpus[^'\"]*\3 \}")
ps_out, n_ps = ps_pat.subn(lambda m: "if ((Get-FileHash -Algorithm SHA256 -LiteralPath %s).Hash -ne "
                                     "(Get-FileHash -Algorithm SHA256 -LiteralPath %s).Hash) "
                                     "{ Copy-Item -LiteralPath %s -Destination %s -Force; Write-Output \"REFRESHED %s\" }"
                                     % (m.group(1), m.group(2), m.group(1), m.group(2), m.group(2)), ps)
gate_ps = "if ($LASTEXITCODE -ne 0) { throw 'the static performance gate breached"
if gate_ps in ps_out:
    ps_out = ps_out.replace(gate_ps, "if ($LASTEXITCODE -ne 0) { Copy-Item -LiteralPath $staticMeasured -Destination "
                                     "(Join-Path $repo 'benchmarks/baseline/results/static-windows.json') -Force; "
                                     "Write-Output 'REFRESHED static-windows.json' } if ($false) { throw 'the static performance gate breached", 1)
open(root / 'tests/selfhost/run-refresh.ps1', 'w', encoding='utf-8', newline='').write(ps_out)

sh = open(root / 'tests/selfhost/run.sh', encoding='utf-8', newline='').read()
sh_pat = re.compile(r'cmp -s ("[^"]+") ("[^"]+") \|\| \{ (?:echo|printf \'%s(?:\n|\\n)\') '
                    r'"([^"]*differs? from the conformance corpus[^"]*)"(?: >&2)?; exit 1; \}')
sh_out, n_sh = sh_pat.subn(lambda m: 'cmp -s %s %s || { cp %s %s; echo "REFRESHED %s"; }'
                           % (m.group(1), m.group(2), m.group(1), m.group(2), m.group(2)), sh)
gate_sh = ('python3 "$repo/benchmarks/baseline/gate.py" "$test_build/static-linux.json" '
           '--baseline "$repo/benchmarks/baseline/results/static-linux.json"')
if gate_sh in sh_out:
    sh_out = sh_out.replace(gate_sh, gate_sh + ' || { cp "$test_build/static-linux.json" '
                            '"$repo/benchmarks/baseline/results/static-linux.json"; echo "REFRESHED static-linux.json"; }', 1)
open(root / 'tests/selfhost/run-refresh.sh', 'w', encoding='utf-8', newline='').write(sh_out)
print('run-refresh.ps1:', n_ps, 'checks;', 'run-refresh.sh:', n_sh, 'checks; static gates re-pin on breach')
print('after a refreshed run: normalise the baseline paths (worktree -> repo) and set revision, audit every diff, then run the real runner')
