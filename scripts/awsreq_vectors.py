"""Generate the x_cloud_awsreq fixture: x.cloud.awsreq against botocore's request serializers.

For each chosen operation of the query (IAM, STS, SNS, RDS, CloudFormation), ec2 and json (Lightsail) protocols, parameter
sets are drawn from the operation's input shape in the service model that ships with botocore, and serialized by
botocore's own serializer. The fixture builds the same request from the shape closure and the parameters.

    python scripts/awsreq_vectors.py
"""
import json
import os
import random
import urllib.parse

import botocore.session
from botocore.serialize import create_serializer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, 'scripts', 'awsreq_fixture_template.e')
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'x_cloud_awsreq', 'src', 'main.e')
rng = random.Random(0xA5E)
session = botocore.session.get_session()

OPS = {
    'iam': ['CreateRole', 'PutRolePolicy', 'TagRole', 'AttachRolePolicy', 'CreateInstanceProfile', 'GetRole', 'DeleteRole', 'UntagRole',
            'CreateUser', 'UpdateAssumeRolePolicy', 'ListRoleTags', 'CreatePolicy', 'SimulatePrincipalPolicy'],
    'sts': ['AssumeRole', 'GetSessionToken', 'AssumeRoleWithSAML'],
    'sns': ['CreateTopic', 'SetTopicAttributes', 'Publish', 'Subscribe', 'TagResource', 'PublishBatch'],
    'rds': ['CreateDBInstance', 'ModifyDBInstance', 'DescribeDBInstances', 'AddTagsToResource', 'CreateDBSubnetGroup'],
    'cloudformation': ['CreateStack', 'UpdateStack', 'DescribeStacks', 'DeleteStack'],
    'ec2': ['RunInstances', 'DescribeInstances', 'TerminateInstances', 'CreateTags', 'DescribeSecurityGroups',
            'AuthorizeSecurityGroupIngress', 'CreateSecurityGroup', 'DescribeVolumes', 'ModifyInstanceAttribute', 'CreateVolume'],
    'lightsail': ['CreateInstances', 'GetInstances', 'CreateDomain', 'TagResource', 'DeleteInstance', 'GetInstance', 'CreateDisk',
                  'AttachDisk', 'PutInstancePublicPorts', 'CreateDatabase'],
}
WORDS = ['alpha', 'beta', 'Gamma Delta', 'a&b=c', 'x/y+z', 'café', '日本語', 'with space', 'q?r#s', '100%', '~tilde_', 'emoji \U0001f600',
         'line\nbreak', 'tab\there', 'quote"s', 'back\\slash', '', 'arn:aws:iam::123456789012:role/Role', 'i-0abcdef1234567890', '{"Version":"2012-10-17"}']


def closure(shapes, root):
    seen = {}
    todo = [root]
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen[n] = shapes[n]
        d = shapes[n]
        for k in ('member', 'key', 'value'):
            if k in d:
                todo.append(d[k]['shape'])
        for m in d.get('members', {}).values():
            todo.append(m['shape'])
    return seen


def usable(shapes, name, depth=0):
    """Whether a value can be drawn for the shape (no float, double or document inside, bounded depth)."""
    d = shapes[name]
    t = d['type']
    if t in ('float', 'double') or d.get('document'):
        return False
    if t == 'structure':
        if depth > 4:
            return False
        return True
    if t == 'list':
        return depth <= 4 and usable(shapes, d['member']['shape'], depth + 1)
    if t == 'map':
        return depth <= 4 and usable(shapes, d['value']['shape'], depth + 1)
    return True


def draw(shapes, name, depth=0):
    d = shapes[name]
    t = d['type']
    if t == 'structure':
        members = d.get('members', {})
        names = [k for k, m in members.items() if usable(shapes, m['shape'], depth + 1)]
        required = set(d.get('required', []))
        picked = [k for k in names if k in required or rng.random() < (0.55 if depth < 3 else 0.25)]
        if rng.random() < 0.3:
            rng.shuffle(picked)
        out = {}
        for k in picked:
            if depth >= 5 and k not in required:
                continue
            out[k] = draw(shapes, members[k]['shape'], depth + 1)
        return out
    if t == 'list':
        n = rng.choice([0, 1, 1, 2, 3])
        if depth >= 4:
            n = min(n, 1)
        return [draw(shapes, d['member']['shape'], depth + 1) for _ in range(n)]
    if t == 'map':
        n = rng.choice([0, 1, 2, 3])
        keys = ['k' + str(i) for i in range(n)] + []
        if n and rng.random() < 0.3:
            keys[0] = rng.choice(WORDS[:12]) or 'key'
        seen = {}
        for k in keys:
            seen[k] = draw(shapes, d['value']['shape'], depth + 1)
        return seen
    if t == 'string':
        return rng.choice(WORDS)
    if t in ('integer', 'long'):
        return rng.choice([0, 1, 7, 42, 65535, 2147483647, 9999999999])
    if t == 'boolean':
        return rng.random() < 0.5
    if t == 'timestamp':
        return rng.choice([0, 86400, 1700000000, 1234567890, 2000000000, 951782400])
    if t == 'blob':
        return rng.choice(['bytes', 'a', 'ab', 'abc', 'binary \x01\x02', 'hello world'])
    return rng.choice(WORDS)


def main():
    chunks = []
    total = 0
    cases = 0
    for svc, ops in OPS.items():
        model = session.get_service_model(svc)
        shapes = model._service_description['shapes']
        protocol = model.metadata['protocol']
        serializer = create_serializer(protocol, include_validation=False)
        for op in ops:
            try:
                om = model.operation_model(op)
            except Exception:
                continue
            if om.input_shape is None:
                continue
            input_name = om.input_shape.name
            sub = closure(shapes, input_name)
            call = {'protocol': 'ec2' if protocol == 'ec2' else ('json' if protocol == 'json' else 'query'), 'name': om.name,
                    'method': om.http.get('method', 'POST'), 'apiVersion': model.metadata.get('apiVersion', ''),
                    'targetPrefix': model.metadata.get('targetPrefix', ''), 'jsonVersion': model.metadata.get('jsonVersion', ''),
                    'input': input_name, 'shapes': sub}
            lines = [json.dumps(call, sort_keys=True, separators=(',', ':'))]
            for _ in range(6):
                params = draw(shapes, input_name)
                req = serializer.serialize_to_request(params, om)
                body = req['body']
                if isinstance(body, dict):
                    body = urllib.parse.urlencode(body, doseq=True)
                else:
                    body = body.decode('utf-8')
                e = {'method': req['method'], 'path': req['url_path'], 'headers': [[k, v] for k, v in req['headers'].items()], 'body': body}
                lines.append(json.dumps({'params': params, 'e': e}, sort_keys=False, separators=(',', ':'), ensure_ascii=True))
                cases += 1
            chunks.append(lines)
            total += sum(len(l) for l in lines)
    bs = chr(92)

    def lit(lines):
        return '"' + (bs + 'n').join(l.replace(bs, bs + bs).replace('"', bs + '"') for l in lines) + bs + 'n"'
    funcs = '\n'.join(f'fn vectors_{i}() -> str {{\n    ret {lit(c)}\n}}\n' for i, c in enumerate(chunks))
    calls = ''.join(f'    if run_chunk(a, vectors_{i}()) != 0u8 {{ os.exit({i + 1}i32) }}\n' for i in range(len(chunks)))
    t = open(TEMPLATE, encoding='utf8').read()
    out = t.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    with open(FIXTURE, 'w', encoding='utf8', newline='\n') as f:
        f.write(out)
    print(f'{cases} requests over {len(chunks)} operations, {total} bytes of vectors -> x_cloud_awsreq')


main()
