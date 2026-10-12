"""Generate the x_elastic_rest fixture: vectors from elasticsearch-py (the Elastic project's Python client).

Oracle: `elasticsearch._sync.client.utils._quote` / `_quote_query` for URL parts and query strings, and
`elasticsearch.helpers.actions.expand_action` with elastic-transport's `NdjsonSerializer` for the `_bulk` request
lines. Response parsing has no library function worth calling (the client returns the decoded JSON as is), so the
responses are generated from a model in the documented shapes and the expected text is rendered from that model.

    PYTHONPATH=DIR python scripts/elastic_vectors.py
"""
import json
import os
import random
import struct
import sys

from elastic_transport import JsonSerializer, NdjsonSerializer
from elasticsearch._sync.client.utils import _quote, _quote_query
from elasticsearch.helpers.actions import expand_action

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x454C4153)
lines = []
JS, ND = JsonSerializer(), NdjsonSerializer()


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


def add(*f):
    lines.append('\t'.join(str(x) for x in f))


VALUES = ['', 'abc', 'a b', 'a/b', 'a,b', 'a*b', 'café', 'snow☃', 'emoji\U0001F600', '100%', 'x=y&z', 'q?x#y', '~tilde_', 'dot.dash-',
          'pl+us', '"quoted"', "it's", 'back\\slash', 'a:b@c', '[1]{2}', 'new\nline']
for v in VALUES:
    add('Q', hx(v), hx(_quote(v)))

for _ in range(15):
    segs = [rng.choice(['idx', 'my-index', '_doc', '_search', '_bulk', '', 'a/b', 'café', 'id 1', '*', 'a,b']) for _ in range(rng.randrange(0, 5))]
    expected = '/' + '/'.join(_quote(s) for s in segs if s) if any(segs) else '/'
    add('P', ','.join(hx(s) if s else '-' for s in segs) or '-', hx(expected))

for _ in range(15):
    params = [(rng.choice(['refresh', 'routing', 'size', 'q', 'filter_path', 'timeout']), rng.choice(VALUES + ['true', '10', 'a,b'])) for _ in range(rng.randrange(0, 4))]
    names = {}
    for k, v in params:
        names[k] = v
    params = list(names.items())
    add('Z', ','.join(hx(k) + ':' + hx(v) for k, v in params) or '-', hx(_quote_query(dict(params))))

# ---- bulk lines
KEYS = [('_id', 'id', 'str'), ('_index', 'index', 'str'), ('_if_seq_no', 'if_seq_no', 'int'), ('_if_primary_term', 'if_primary_term', 'int'),
        ('_retry_on_conflict', 'retry_on_conflict', 'int'), ('_routing', 'routing', 'str'), ('_version', 'version', 'int'),
        ('_version_type', 'version_type', 'str'), ('pipeline', 'pipeline', 'str')]
for _ in range(60):
    op = rng.choice(['index', 'create', 'update', 'delete', 'index'])
    action = {'_op_type': op}
    meta = []
    for lib_key, _, kind in KEYS:
        if rng.random() < 0.35:
            v = rng.choice(['doc-%d' % rng.randrange(100), 'café', 'a "b"', 'x\ty']) if kind == 'str' else rng.randrange(0, 5000)
            action[lib_key] = v
            meta.append((kind, v))
        else:
            meta.append((kind, None))
    source = {'field': rng.choice(['v', 'hé', 'line\nbreak']), 'n': rng.randrange(100), 'nested': {'a': [1, 2, None]}}
    action['_source'] = source
    head, body = expand_action(action)
    items = [head] + ([body] if body is not None else [])
    wire = ND.dumps(items)
    head_line = wire.split(b'\n', 1)[0]
    src_text = JS.dumps(body).decode('utf-8') if body is not None else ''
    spec = ','.join('-' if v is None else (hx(v) if k == 'str' else str(v)) for k, v in meta)
    add('B', op, spec, hx(src_text), hx(wire))
assert True

# ---- bulk responses
def item(op):
    d = {'_index': rng.choice(['idx', 'logs-2026', 'café']), '_id': str(rng.randrange(1000)), 'status': 0}
    if rng.random() < 0.7:
        d.update({'_version': rng.randrange(1, 9), 'result': rng.choice(['created', 'updated', 'deleted', 'not_found', 'noop']),
                  '_shards': {'total': 2, 'successful': 1, 'failed': 0}, '_seq_no': rng.randrange(100), '_primary_term': 1})
        d['status'] = rng.choice([200, 201, 404])
    else:
        d['status'] = rng.choice([400, 409, 429, 500])
        d['error'] = {'type': rng.choice(['version_conflict_engine_exception', 'mapper_parsing_exception', 'es_rejected_execution_exception']),
                      'reason': rng.choice(['[1]: version conflict', 'failed to parse field [x] of type [date]', 'rejected "execution"']),
                      'index': d['_index'], 'shard': '0'}
        if rng.random() < 0.2:
            d['error'] = 'legacy string error'
    return {op: d}


for _ in range(25):
    items = [item(rng.choice(['index', 'create', 'update', 'delete'])) for _ in range(rng.randrange(0, 6))]
    errors = any('error' in list(i.values())[0] for i in items)
    body = {'took': rng.randrange(0, 5000), 'errors': errors, 'items': items}
    rendered = []
    for i in items:
        op, d = next(iter(i.items()))
        err = d.get('error')
        etype = err['type'] if isinstance(err, dict) else ''
        ereason = err['reason'] if isinstance(err, dict) else (err or '')
        rendered.append('%s:%s:%s:%d:%s:%s:%s:%d' % (hx(op), hx(d['_index']), hx(d['_id']), d['status'], hx(d.get('result', '')), hx(etype), hx(ereason), d.get('_version', -1)))
    add('R', hx(json.dumps(body, ensure_ascii=rng.random() < 0.5)), '%d|%d|%s' % (body['took'], int(errors), ';'.join(rendered)))
add('R', hx('{"took":1,"errors":false}'), 'Invalid')
add('R', hx('not json'), 'Invalid')
add('R', hx('{"took":1,"errors":false,"items":[{"index":{},"extra":1}]}'), 'Invalid')

# ---- search responses
for _ in range(25):
    hits = []
    for i in range(rng.randrange(0, 5)):
        h = {'_index': 'idx', '_id': str(i), '_score': rng.choice([None, 1.0, 0.5, 12.25, 3]), '_source': rng.choice([{'a': 1}, {'a': 1, 'b': {'c': 2}}, {}, {'k': [1, 2, 3], 'z': 'café'}])}
        if rng.random() < 0.2:
            del h['_source']
        hits.append(h)
    total = rng.choice([{'value': len(hits), 'relation': 'eq'}, {'value': 10000, 'relation': 'gte'}, len(hits)])
    body = {'took': rng.randrange(0, 300), 'timed_out': rng.random() < 0.1, '_shards': {'total': 3, 'successful': 3, 'skipped': 0, 'failed': rng.choice([0, 0, 1])},
            'hits': {'total': total, 'max_score': 1.0, 'hits': hits}}
    if rng.random() < 0.3:
        body['_scroll_id'] = 'DXF1ZXJ5QW5kRmV0Y2gB' + str(rng.randrange(100))
    rendered = []
    for h in hits:
        score = h['_score']
        sb = '-' if score is None else hx(struct.pack('>d', float(score)))
        src = h.get('_source')
        rendered.append('%s:%s:%s:%s' % (hx(h['_index']), hx(h['_id']), sb, ('m%d' % len(src)) if src is not None else 'x'))
    tv, rel = (total['value'], total['relation']) if isinstance(total, dict) else (total, 'eq')
    add('S', hx(json.dumps(body)), '%d|%d|%d|%s|%s|%d|%s' % (body['took'], int(body['timed_out']), tv, hx(rel), hx(body.get('_scroll_id', '')), body['_shards']['failed'], ';'.join(rendered)))
add('S', hx('{"took":1}'), 'Invalid')

# ---- errors
for body in [{'error': {'root_cause': [{'type': 'index_not_found_exception', 'reason': 'no such index [x]', 'index': 'x'}], 'type': 'index_not_found_exception', 'reason': 'no such index [x]', 'index': 'x'}, 'status': 404},
             {'error': {'root_cause': [], 'type': 'search_phase_execution_exception', 'reason': 'all shards failed'}, 'status': 503},
             {'error': 'IndexMissingException[[x] missing]', 'status': 404},
             {'error': {'type': 'security_exception', 'reason': 'missing authentication credentials'}, 'status': 401},
             {'error': {'root_cause': [{'type': 'parsing_exception', 'reason': 'unknown query [foo]'}], 'type': 'x_content_parse_exception', 'reason': '[1:2] bad'}, 'status': 400}]:
    err = body['error']
    if isinstance(err, str):
        kind, reason, rk, rr = '', err, '', ''
    else:
        kind, reason = err['type'], err['reason']
        rc = err.get('root_cause') or []
        rk, rr = (rc[0]['type'], rc[0]['reason']) if rc else ('', '')
    add('E', hx(json.dumps(body)), '%d|%s|%s|%s|%s' % (body['status'], hx(kind), hx(reason), hx(rk), hx(rr)))
add('E', hx('{"status":500}'), 'Invalid')

# ---- write
chunks, step = [], 30
for i in range(0, len(lines), step):
    body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in lines[i:i + step]) + '\n'
    chunks.append('"' + body.replace('\n', BS + 'n') + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'elastic_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'x_elastic_rest', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d vectors in %d chunks -> x_elastic_rest' % (len(lines), len(chunks)))
