"""Refresh a runner's literal pin of a module's declaration list from the module's source.

usage: python pin_surface.py <root> <lib path> <sh variable> <ps variable>
  e.g. python pin_surface.py . lib/e/data/heap.e expected_heap_surface expectedHeapSurface
The suites pin a few modules' `type|fn|error|const|var` names literally in
tests/selfhost/run.sh and run.ps1; extending such a module must move the pin too.
"""
import re, sys
from pathlib import Path

root, lib, sh_var, ps_var = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
names = [m.group(2) for m in re.finditer(r'^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*)',
                                         (root / lib).read_text(encoding='utf-8'), re.M)]
sh = root / 'tests/selfhost/run.sh'
s = open(sh, encoding='utf-8', newline='').read()
old = re.search(sh_var + r"='[^']*'", s).group(0)
s = s.replace(old, sh_var + "='" + '\n'.join(names) + "'")
open(sh, 'w', encoding='utf-8', newline='').write(s)
ps = root / 'tests/selfhost/run.ps1'
s = open(ps, encoding='utf-8', newline='').read()
old = re.search(r"\$" + ps_var + r" = @\([^)]*\)", s).group(0)
s = s.replace(old, "$" + ps_var + " = @(" + ', '.join("'%s'" % n for n in names) + ")")
open(ps, 'w', encoding='utf-8', newline='').write(s)
print(lib, len(names), 'names pinned')
