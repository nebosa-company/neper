"""Reverse a conflict-free set of functions and their resolved calls (D562, H10).

    python benchmarks/metamorphic/reorder_parameters.py COMPILER ROOT SRC_DIR OUT_DIR [OS]

This deliberately reuses the compiler's structured signature plan and plan applier:
each accepted plan changes one declaration and all resolved calls transactionally.
Functions with fixed signatures (exports, foreign functions, protocol choices or
function values) are left alone by the index filter or the planner's refusal.
"""
import bisect, json, os, shutil, subprocess, sys

compiler, root, src_dir, out_dir = map(os.path.abspath, sys.argv[1:5])
host_os = sys.argv[5] if len(sys.argv) > 5 else 'windows'
if os.path.exists(out_dir):
    shutil.rmtree(out_dir)
shutil.copytree(src_dir, out_dir)

functions = {}
for dirpath, dirs, files in os.walk(out_dir):
    dirs.sort()
    for name in sorted(files):
        parts = name.split('.')
        if not name.endswith('.e') or (len(parts) == 3 and parts[1] not in (host_os, 'x64')):
            continue
        path = os.path.join(dirpath, name)
        indexed = subprocess.run(
            [compiler, 'index-file', path, root, 'x64', host_os, '--json'],
            capture_output=True, text=True)
        if indexed.returncode:
            sys.exit('reorder_parameters: index failed for %s: %s' % (path, indexed.stderr[:300]))
        records = [json.loads(line) for line in indexed.stdout.splitlines()]
        for record in records:
            if record.get('record') == 'symbol' and record.get('kind') == 'fn' and not set(record.get('attributes', ())) & {'export', 'import'}:
                functions[record['qualified_name']] = 0
        for record in records:
            if record.get('record') == 'symbol' and record.get('kind') == 'parameter':
                owner = record['qualified_name'].rsplit('.', 1)[0]
                if owner in functions:
                    functions[owner] += 1

operand = os.path.join(out_dir, 'main.e')
project_root = os.path.dirname(out_dir)
batch_path = os.path.join(project_root, '.reorder-parameters-batch.txt')
plan_path = os.path.join(project_root, '.reorder-parameters-plan.jsonl')
requests = [(subject, ','.join(map(str, reversed(range(count)))))
            for subject, count in sorted(functions.items()) if 2 <= count <= 16]
open(batch_path, 'w', encoding='utf-8', newline='\n').write(
    ''.join('signature %s %s\n' % request for request in requests))
planned = subprocess.run(
    [compiler, 'query-batch', operand, root, 'x64', host_os, '--json',
     '--batch', batch_path], capture_output=True, text=True)
if planned.returncode not in (0, 2):
    sys.exit('reorder_parameters: batch failed: %s' % planned.stderr[:300])

streams = []
for line in planned.stdout.splitlines():
    record = json.loads(line)
    if record.get('record') == 'header':
        streams.append([])
    streams[-1].append(record)
if len(streams) != len(requests):
    sys.exit('reorder_parameters: batch returned %d streams for %d requests' %
             (len(streams), len(requests)))

preconditions = {}
edits = []
occupied = {}
changed = refused = conflicts = 0
for stream in streams:
    result = stream[-1]
    if not result.get('ok'):
        refused += 1
        continue
    stream_edits = [record for record in stream if record.get('record') == 'edit']
    spans = []
    conflict = False
    for record in stream_edits:
        span = record['span']
        source = span['source']
        key = (source['root'], source['path'])
        intervals = occupied.setdefault(key, [])
        start, end = span['byte_start'], span['byte_end']
        at = bisect.bisect_left(intervals, (start, end))
        if ((at and intervals[at - 1][1] > start) or
                (at < len(intervals) and intervals[at][0] < end)):
            conflict = True
            break
        spans.append((key, start, end))
    if conflict:
        conflicts += 1
        continue
    changed += 1
    for key, start, end in spans:
        bisect.insort(occupied[key], (start, end))
    for record in stream:
        if record.get('record') == 'precondition':
            key = (record['source']['root'], record['source']['path'])
            if key in preconditions and preconditions[key] != record:
                sys.exit('reorder_parameters: inconsistent precondition for %s' % (key,))
            preconditions[key] = record
    edits.extend(stream_edits)

combined = [
    {'schema': 'neper-stream', 'version': 1, 'record': 'header',
     'command': 'plan-change-signature', 'tool_version': '0.1.0',
     'language_version': '0.1', 'grammar_revision': 3},
    *preconditions.values(), *edits,
    {'record': 'postcondition', 'check': 'the transformed compiler builds and reproduces the stable stage'},
    {'record': 'result', 'ok': True, 'exit_code': 0,
     'data': {'edits': len(edits), 'files': len(preconditions), 'complete': True}},
]
with open(plan_path, 'w', encoding='utf-8', newline='\n') as plan_file:
    for record in combined:
        plan_file.write(json.dumps(record, separators=(',', ':')) + '\n')
applied = subprocess.run(
    [compiler, 'apply-plan', plan_path, '--root', out_dir], capture_output=True)
if applied.returncode:
    sys.exit('reorder_parameters: apply failed: %s' % (applied.stderr or applied.stdout)[:300])
os.remove(batch_path)
os.remove(plan_path)
print('parameters reordered', changed, 'refused', refused,
      'conflicts', conflicts, 'edits', len(edits))
