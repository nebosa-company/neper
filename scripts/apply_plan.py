"""Apply a `plan-rename-file --json` plan (D376, H29) to the files it names.

    python scripts/apply_plan.py PLAN.jsonl --root DIR [--project-src DIR]

Every `precondition` record's file must hash as recorded, or nothing is written;
the `edit` records are applied per file from the highest byte offset down, so
earlier spans stay valid; each file is written whole through a temporary and a
replace. The `postcondition` record is printed for the caller to check (re-run
`check-file` and `uses-file`). Sources are resolved by root: `operand` under
--root, `project-src` under --project-src (default --root).
"""
import argparse, hashlib, json, os, sys

parser = argparse.ArgumentParser()
parser.add_argument('plan')
parser.add_argument('--root', required=True)
parser.add_argument('--project-src', default=None)
args = parser.parse_args()
roots = {'operand': args.root, 'project-src': args.project_src or args.root}

records = [json.loads(l) for l in open(args.plan, encoding='utf-8') if l.strip()]
result = [r for r in records if r['record'] == 'result']
if not result or not result[0]['ok']:
    sys.exit('apply_plan: the plan did not succeed')

def resolve(source):
    if source['root'] not in roots:
        sys.exit('apply_plan: no directory for source root %s' % source['root'])
    return os.path.join(roots[source['root']], source['path'])

files = {}
for r in records:
    if r['record'] == 'precondition':
        path = resolve(r['source'])
        data = open(path, 'rb').read()
        if hashlib.sha256(data).hexdigest() != r['sha256']:
            sys.exit('apply_plan: %s changed since the plan was made; nothing applied' % path)
        files[path] = bytearray(data)
edits = {}
for r in records:
    if r['record'] == 'edit':
        path = resolve(r['span']['source'])
        if path not in files:
            sys.exit('apply_plan: an edit names %s, which has no precondition; nothing applied' % path)
        edits.setdefault(path, []).append((r['span']['byte_start'], r['span']['byte_end'], r['replacement'].encode('utf-8')))
for path, spans in edits.items():
    data = files[path]
    for start, end, replacement in sorted(spans, reverse=True):
        data[start:end] = replacement
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(bytes(data))
    os.replace(tmp, path)
    print('applied %d edits to %s' % (len(spans), path))
for r in records:
    if r['record'] == 'postcondition':
        print('postcondition: %s' % r['check'])
