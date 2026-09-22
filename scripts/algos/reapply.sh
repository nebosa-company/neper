#!/bin/bash
# Register batches of the algos.md stream in a worktree on top of the current shared
# files, insert the stream's decision rows, validate the fences, stage and render.
# usage: bash scripts/algos/reapply.sh <worktree> <decisions-file> <batches...>
#   e.g. bash scripts/algos/reapply.sh build/wt-algos build/my-decisions.md batch28 batch29
# Each batch is scripts/algos/<batch>.json (see add_batch.py for the shape).
set -e
wt=$1; rows=$2; shift 2
cd "$wt"
S=scripts/algos
for b in "$@"; do python $S/add_batch.py . $S/$b.json; done
python - "$rows" <<'EOF'
import re, sys
p='docs/decisions.md'
s=open(p,encoding='utf-8').read()
mine=open(sys.argv[1],encoding='utf-8').read()
# Insert each of the stream's rows before the first row with a higher number.
rows=re.split(r'(?m)^(?=## D\d+ )', mine)
for row in rows:
    m=re.match(r'## D(\d+) ', row)
    if not m: continue
    num=int(m.group(1))
    if f'## D{num} ' in s: continue
    later=[(int(x.group(1)), x.start()) for x in re.finditer(r'(?m)^## D(\d+) ', s) if int(x.group(1))>num and x.start()>s.index('## D800 ')]
    at=min(later, key=lambda t:t[1])[1] if later else len(s)
    s=s[:at]+row.rstrip('\n')+'\n\n'+s[at:]
open(p,'w',encoding='utf-8',newline='\n').write(s)
EOF
python scripts/check_module_surfaces.py | tail -1
git add docs/decisions.md docs/module-apis.md docs/modules.json tests/selfhost/run.ps1 tests/selfhost/run.sh
git add $(git status --short | grep '^??' | grep -E 'lib/e/|fixtures/link/' | cut -c4-)
git add -u lib/e tests/selfhost/fixtures/link
python scripts/render_progress.py | tail -1
python scripts/render_tasks.py | tail -1
git add docs/progress.html docs/tasks
git status --short | grep -v '^[AM] ' || true
