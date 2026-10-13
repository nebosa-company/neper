"""Generate the x_cloud_awssig fixture: x.cloud.awssig (AWS Signature Version 4) against botocore's own signers.

Random requests -- methods, hosts with and without ports and userinfo, paths with dot segments, empty segments and
characters that quote, queries in the URL and as `params`, headers in mixed case with padded and multi-space values, a
`Date` or `X-Amz-Date` header already there, a session token, a body or none, http and https, payload signing on and off,
S3 and the other services -- are signed by `botocore.auth.SigV4Auth` / `S3SigV4Auth` on a fixed clock with fixed
credentials. The canonical request, the string to sign, the signature and the headers the request ends with are what the
fixture compares.

    python scripts/awssig_vectors.py
"""
import datetime
import json
import os
import random
import sys

import botocore.auth as bauth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, 'scripts', 'awssig_fixture_template.e')
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'x_cloud_awssig', 'src', 'main.e')
rng = random.Random(0x51643)
pick = rng.choice

ACCESS = ['AKIDEXAMPLE', 'AKIAIOSFODNN7EXAMPLE', 'ASIA0123456789ABCDEF']
SECRET = ['wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY', 'secret', 'k' * 70]
REGIONS = ['us-east-1', 'eu-west-1', 'ap-southeast-2', 'us-gov-west-1', 'cn-north-1']
SERVICES = ['s3', 'iam', 'ec2', 'lightsail', 'sts', 'execute-api', 'ssm', 'service']
HOSTS = ['example.amazonaws.com', 'iam.amazonaws.com', 'EC2.US-EAST-1.AMAZONAWS.COM', 'bucket.s3.amazonaws.com', 'localhost',
         'host.example:8443', 'host.example:443', 'host.example:80', 'user:pw@host.example', '[::1]', '[2001:db8::1]:9000', '127.0.0.1:8080']
PATHS = ['/', '', '/a', '/a/b/c', '/a/./b', '/a/../b', '/../a', '/a//b', '//a', '/a/b/', '/a b', '/a%20b', '/a+b', '/%2F', '/~tilde', '/ünï', '/a/b%2Fc',
         '/foo/bar/..', '/./', '/a/b/../../c', '/photos/photo1.jpg', '/!$&\'()*+,;=:@', '/%7Euser', '/a%', '/a;b=c']
QUERIES = ['', 'Action=ListUsers&Version=2010-05-08', 'b=2&a=1', 'a=1&a=0&a=2', 'k', 'k=', '=v', 'a=b=c', 'x=%20y&x=+z', 'z=1&Z=2&a=3',
           'prefix=photos%2F&max-keys=50', 'uploads', 'a=1&&b=2', 'q=ü']
PARAMS = [[['Action', 'ListUsers'], ['Version', '2010-05-08']], [['b', '2'], ['a', '1']], [['k', 'a b'], ['k', 'a']], [['p', 'ü/~-_.!*'], ['empty', '']],
          [['a b', 'c d']], [['key', 'val+ue'], ['key', 'val%ue']]]
HEADER_NAMES = ['Content-Type', 'content-length', 'X-Amz-Target', 'x-amz-meta-Foo', 'Accept', 'Host', 'USER-AGENT', 'Connection', 'Expect', 'TE', 'Trailer',
                'Transfer-Encoding', 'Upgrade', 'Keep-Alive', 'Proxy-Authorization', 'X-Amzn-Trace-Id', 'Range', 'Content-MD5', 'X-Amz-Content-SHA256',
                'Authorization', 'X-Amz-Security-Token', 'Cache-Control', 'X-Custom']
HEADER_VALUES = ['application/json', 'text/plain; charset=utf-8', '  padded  ', 'a    b   c', '\ttab\tseparated\t', '', 'x', 'x,y', 'Ünï', 'a b',
                 'AmazonEC2.RunInstances', 'bytes=0-9', '8443', 'EXAMPLE.com:8080', 'value with   many    spaces', 'v']
BODIES = [None, '', 'Action=DescribeInstances&Version=2016-11-15', '{"a":1}', 'ü' * 5, 'x' * 5000, '\n', 'a=b']


def clock(ts):
    return lambda: ts


def gen(i):
    method = pick(['GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'get', 'Post'])
    scheme = pick(['https', 'https', 'https', 'http', 'HTTPS'])
    host = pick(HOSTS)
    path = pick(PATHS)
    use_params = rng.random() < 0.35
    query = '' if use_params else pick(QUERIES)
    url = f'{scheme}://{host}{path}' + (f'?{query}' if query else '')
    headers = {}
    used = set()
    for _ in range(rng.randint(0, 6)):
        n = pick(HEADER_NAMES)
        if n.lower() in used:
            continue
        used.add(n.lower())
        headers[n] = pick(HEADER_VALUES)
    if rng.random() < 0.12:
        headers['Date'] = 'Mon, 01 Jan 2001 00:00:00 GMT'
    if rng.random() < 0.12:
        headers['X-Amz-Date'] = '19990101T000000Z'
    s3 = rng.random() < 0.3
    service = 's3' if s3 else pick(SERVICES)
    ts = datetime.datetime(rng.choice([2015, 2024, 2038]), rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59))
    return {
        'method': method, 'url': url, 'headers': [[k, v] for k, v in headers.items()],
        'params': [list(p) for p in pick(PARAMS)] if use_params else None,
        'body': pick(BODIES) or '', 'region': pick(REGIONS), 'service': service, 'access_key': pick(ACCESS), 'secret_key': pick(SECRET),
        'token': pick(['', '', 'FQoGZXIvYXdzEJr', 'tok/en+=']), 'timestamp': ts.strftime('%Y%m%dT%H%M%SZ'), 's3': s3,
        'payload_signing': rng.random() < 0.6, 'streaming_input': rng.random() < 0.25,
    }, ts


def expected(req, ts):
    creds = Credentials(req['access_key'], req['secret_key'], req['token'] or None)
    cls = bauth.S3SigV4Auth if req['s3'] else bauth.SigV4Auth
    auth = cls(creds, req['service'], req['region'])
    r = AWSRequest(method=req['method'], url=req['url'], headers=dict((k, v) for k, v in req['headers']),
                   data=req['body'] if req['body'] else None, params=[tuple(p) for p in req['params']] if req['params'] else None)
    r.context['payload_signing_enabled'] = req['payload_signing']
    if req['streaming_input']:
        r.context['has_streaming_input'] = True
    r.context['timestamp'] = ts.strftime('%Y%m%dT%H%M%SZ')
    auth._modify_request_before_signing(r)
    cr = auth.canonical_request(r)
    sts = auth.string_to_sign(r, cr)
    sig = auth.signature(sts, r)
    auth._inject_signature_to_request(r, sig)
    return {'canonical_request': cr, 'string_to_sign': sts, 'signature': sig, 'authorization': r.headers['Authorization'],
            'headers': [[k, v] for k, v in r.headers.items()]}


def main():
    cases = []
    skipped = 0
    guard = 0
    while len(cases) < 1500 and guard < 20000:
        guard += 1
        req, ts = gen(guard)
        try:
            e = expected(req, ts)
        except Exception:
            skipped += 1
            continue
        cases.append({'req': req, 'e': e})
    texts = [json.dumps(c, sort_keys=True, separators=(',', ':'), ensure_ascii=True) for c in cases]
    bs = chr(92)
    chunks = []
    for i in range(0, len(texts), 10):
        chunks.append('"' + (bs + 'n').join(t.replace(bs, bs + bs).replace('"', bs + '"') for t in texts[i:i + 10]) + bs + 'n"')
    funcs = '\n'.join(f'fn vectors_{i}() -> str {{\n    ret {c}\n}}\n' for i, c in enumerate(chunks))
    calls = ''.join(f'    if run_chunk(a, vectors_{i}()) != 0u8 {{ os.exit({i + 1}i32) }}\n' for i in range(len(chunks)))
    t = open(TEMPLATE, encoding='utf8').read()
    out = t.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    with open(FIXTURE, 'w', encoding='utf8', newline='\n') as f:
        f.write(out)
    print(f'{len(cases)} requests ({skipped} botocore refused) in {len(chunks)} chunks -> x_cloud_awssig')


main()
