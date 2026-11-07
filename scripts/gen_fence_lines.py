"""Print `docs/module-apis.md` fence lines for named symbols, from source and the compiler index.

Usage: gen_fence_lines.py INDEX.json NAMES.txt SOURCE.e

Functions come from the index `signature`. Types and consts need their whole
declaration (the catalogue fences a struct's body too), which the index only
gives as a line span, so those are cut from the source text.
"""
import json
import sys

index_path, names_path, source_path = sys.argv[1], sys.argv[2], sys.argv[3]
wanted = {line.strip() for line in open(names_path, encoding='utf-8') if line.strip()}
source_lines = open(source_path, encoding='utf-8').read().splitlines()

records = {}
for line in open(index_path, encoding='utf-8'):
    line = line.strip()
    if not line:
        continue
    record = json.loads(line)
    if record.get('record') == 'symbol' and record.get('name') in wanted:
        records[record['name']] = record

missing = sorted(wanted - set(records))
if missing:
    print('# no index record for: ' + ', '.join(missing), file=sys.stderr)

out = []
for name in sorted(records):
    record = records[name]
    signature = (record.get('signature') or name).strip()
    span = record.get('span')
    if record['kind'] in ('type', 'const') and span is not None:
        first = span['line'] - 1
        last = span['end_line'] - 1
        if first == last:
            text = source_lines[first][span['column'] - 1:].strip()
        else:
            parts = [source_lines[first][span['column'] - 1:]]
            parts.extend(source_lines[first + 1:last])
            parts.append(source_lines[last][:span['end_column'] - 1])
            text = ' '.join(part.strip() for part in parts)
        out.append(text)
    else:
        out.append(signature)

for line in out:
    print(line)
