"""Independent oracle for e.cli.config (L123): layered resolution by `collections.ChainMap`,
INI by `configparser`, JSON by `json`, with the flattening, environment-name and typing
rules written out from the module's documented contract.

A scenario is defaults, a file (INI or JSON text), an environment (`APP_`-prefixed
`NAME=value`) and flags. The environment layer is built from keys already known after
the defaults and the file, exactly as the module does. Each scenario lists, for every key
that any layer or the environment could name and for two absent keys, the effective value,
the winning layer and the typed reads.

Lines: `S~format~file_hex~defaults~env~flags` (`k=v;k=v`), then `Q~key~value~layer~i~f~b`
where absent is `-`, i/f/b are `ok:value` or `bad`.
"""
import configparser
import io
import json
import random
import re
import sys
from collections import ChainMap

POOL = ['server.host', 'server.port', 'log.level', 'log.json', 'db.pool.size', 'db.pool.max',
        'feature.beta', 'ratio', 'name']
VALUES = ['8080', '0', '-3', '2.5', '0.125', 'true', 'FALSE', 'yes', 'Off', '1', 'hello', 'debug', 'x1']
BOOLS = {'true': True, 'yes': True, 'on': True, '1': True, 'false': False, 'no': False, 'off': False, '0': False}
PREFIX = 'APP_'


def env_name(key):
    return PREFIX + key.upper().replace('.', '_').replace('-', '_')


def flatten(prefix, node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            flatten(prefix + '.' + k if prefix else k, v, out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            flatten('%s.%d' % (prefix, i) if prefix else str(i), v, out)
    elif node is None:
        pass
    elif isinstance(node, bool):
        out[prefix] = 'true' if node else 'false'
    else:
        out[prefix] = json.dumps(node) if not isinstance(node, str) else node


def make_json(file_flat, rng):
    tree = {}
    for key, value in file_flat.items():
        parts = key.split('.')
        node = tree
        for p in parts[:-1]:
            node = node.setdefault(p, {})
        if re.fullmatch(r'-?[0-9]+', value) and rng.random() < 0.7:
            node[parts[-1]] = int(value)
        elif re.fullmatch(r'-?[0-9]+\.[0-9]+', value) and rng.random() < 0.7:
            node[parts[-1]] = float(value)
        elif value in ('true', 'false') and rng.random() < 0.7:
            node[parts[-1]] = value == 'true'
        else:
            node[parts[-1]] = value
    if rng.random() < 0.5:
        tree['extras'] = ['a', 1, True, None, {'k': 'v'}]
    return json.dumps(tree, indent=rng.choice([None, 2]))


def make_ini(file_flat, rng):
    sections = {}
    for key, value in file_flat.items():
        section, _, rest = key.partition('.')
        sections.setdefault(section, {})[rest] = value
    out = []
    for section, items in sections.items():
        out.append('[%s]' % section)
        for k, v in items.items():
            out.append('%s = %s' % (k, v) if rng.random() < 0.5 else '%s=%s' % (k, v))
        out.append('')
    return '\n'.join(out) + ('' if rng.random() < 0.5 else '\n')


def parse_file(fmt, text):
    flat = {}
    if fmt == 'json':
        flatten('', json.loads(text), flat)
    else:
        cp = configparser.ConfigParser(interpolation=None, default_section='__none__')
        cp.optionxform = str
        cp.read_string(text)
        for section in cp.sections():
            for k, v in cp[section].items():
                flat[section + '.' + k] = v
    return flat


def typed(value):
    i = 'bad'
    if re.fullmatch(r'-?[0-9]+', value) and -(1 << 63) <= int(value) < (1 << 63):
        i = 'ok:%d' % int(value)
    f = 'bad'
    if re.fullmatch(r'-?[0-9]+(\.[0-9]+)?', value):
        f = 'ok:%.6f' % float(value)
    b = 'bad'
    if value.lower() in BOOLS:
        b = 'ok:%s' % ('true' if BOOLS[value.lower()] else 'false')
    return i, f, b


def scenarios():
    rng = random.Random(123)
    out = []
    for n in range(40):
        fmt = 'json' if n % 2 == 0 else 'ini'
        keys = POOL if fmt == 'json' else [k for k in POOL if '.' in k]
        defaults = {k: rng.choice(VALUES) for k in rng.sample(keys, rng.randint(1, 6))}
        file_flat_src = {k: rng.choice(VALUES) for k in rng.sample(keys, rng.randint(0, 5))}
        text = make_json(file_flat_src, rng) if fmt == 'json' else make_ini(file_flat_src, rng)
        file_flat = parse_file(fmt, text)
        known = set(defaults) | set(file_flat)
        env_candidates = sorted(known) + ['unknown.key']
        env = {}
        for k in rng.sample(env_candidates, rng.randint(0, min(4, len(env_candidates)))):
            env[env_name(k)] = rng.choice(VALUES)
        env_layer = {k: env[env_name(k)] for k in known if env_name(k) in env}
        flags = {k: rng.choice(VALUES) for k in rng.sample(POOL + ['extra.flag'], rng.randint(0, 3))}
        chain = ChainMap(flags, env_layer, file_flat, defaults)
        layers = [('l', flags), ('e', env_layer), ('f', file_flat), ('d', defaults)]
        names = sorted(set(chain) | {'absent.one', 'server.nope'} | set(k for k in POOL if rng.random() < 0.3))
        queries = []
        for key in names:
            if key in chain:
                layer = next(letter for letter, d in layers if key in d)
                v = chain[key]
                i, f, b = typed(v)
                queries.append('Q~%s~%s~%s~%s~%s~%s' % (key, v, layer, i, f, b))
            else:
                queries.append('Q~%s~-~-~-~-~-' % key)
        pack = lambda d: ';'.join('%s=%s' % (k, v) for k, v in d.items())
        header = 'S~%s~%s~%s~%s~%s' % (fmt, text.encode().hex(), pack(defaults), pack(env), pack(flags))
        out.append((header, queries))
    return out


if __name__ == '__main__':
    sc = scenarios()
    if '--emit' in sys.argv:
        for header, queries in sc:
            print(header)
            for q in queries:
                print(q)
    else:
        print('config_vectors: %d scenarios, %d queries' % (len(sc), sum(len(q) for _, q in sc)))
