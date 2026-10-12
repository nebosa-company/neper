"""Generate tests/selfhost/fixtures/link/path_tilde/src/main.e (L135, D2801).

Reference: `posixpath.expanduser` driven by $HOME for `~` and `~/...` (the user-table form is
checked against a small Python model, since `pwd` does not exist on the generating host),
a Python model of collapse, and a Python parse of the same passwd text.
"""
import os
import posixpath
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(137)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'path_tilde' / 'src' / 'main.e'
USERS = {'ann': '/home/ann', 'bob': '/srv/bob/', 'root': '/'}
PASSWD = ('root:x:0:0:root:/root:/bin/bash\ndaemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\n'
          'ann:x:1000:1000:Ann,,,:/home/ann:/bin/zsh\n:x:2:2::/nowhere:/bin/false\nbroken\nbob:x:1001:1001::/srv/bob:/bin/sh\n')


def hx(s):
    return s.encode('utf-8').hex() or '-'


def model_expand(home, path):
    if not path.startswith('~'):
        return path
    i = 1
    while i < len(path) and path[i] != '/':
        i += 1
    name = path[1:i]
    if name:
        if name not in USERS:
            return path
        base = USERS[name]
    else:
        base = home
    return (base.rstrip('/') + path[i:]) or '/'


lines = []
homes = ['/root', '/home/ann', '/home/ann/', '/', '', '//', '/a b']
paths = ['~', '~/', '~/x', '~/x/y', '~//x', 'x', '/a/~', '', '~ann', '~ann/', '~ann/docs', '~bob', '~bob/f', '~root', '~root/x',
         '~nobody', '~nobody/x', '~/~', 'a~', '~x y', '~/a b']
for h in homes:
    for p in paths:
        if not p.startswith('~') or p == '~' or p.startswith('~/') or p.startswith('~//'):
            os.environ['HOME'] = h
            ref = posixpath.expanduser(p)
            if h == '' and p.startswith('~'):
                ref = model_expand(h, p)  # posixpath falls back to the user db when HOME is empty
            assert ref == model_expand(h, p) or h == '', (h, p, ref, model_expand(h, p))
        lines.append('X %s %s => %s' % (hx(h), hx(p), hx(model_expand(h, p))))
for h in ('/home/ann', '/home/ann/', '/', ''):
    for p in ('/home/ann', '/home/ann/', '/home/ann/src', '/home/annex', '/home', '/x', '', '/home/ann//y'):
        t = h.rstrip('/')
        if t and (p == t or p.startswith(t) and p[len(t)] in '/\\'):
            r = '~' + p[len(t):]
        else:
            r = p
        lines.append('C %s %s => %s' % (hx(h), hx(p), hx(r)))


def passwd_home(name):
    for line in PASSWD.split('\n'):
        f = line.split(':')
        if len(f) >= 6 and f[0] == name and name:
            return f[5]
    return None


for name in ('root', 'ann', 'bob', 'daemon', 'nobody', '', 'broken', 'an', 'anna'):
    r = passwd_home(name)
    lines.append('P %s => %s' % (hx(name), hx(r) if r is not None else 'E'))

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

fn passwd_text() -> str {
    ret "''' + fc.neper_str(PASSWD) + '''"
}

fn check_line(line: str) -> u8 {
    var home_buf: [64]u8 = zero
    var path_buf: [64]u8 = zero
    var want_buf: [128]u8 = zero
    var out: [128]u8 = zero
    var users: [3]tilde.UserHome = zero
    users[0usize].name = "ann"
    users[0usize].home = "/home/ann"
    users[1usize].name = "bob"
    users[1usize].home = "/srv/bob/"
    users[2usize].name = "root"
    users[2usize].home = "/"
    let (kind, p0) = tok(line, 0usize)
    if kind[0usize] == 80u8 {
        let (name_hex, p1) = tok(line, p0)
        let (arrow, p2) = tok(line, p1)
        let (want_hex, p3) = tok(line, p2)
        let nn = unhex(name_hex, home_buf[0usize..64usize])
        let (got, found) = tilde.passwd_home(passwd_text(), home_buf[0usize..nn])
        if want_hex[0usize] == 69u8 {
            if found { ret 1u8 }
            ret 0u8
        }
        if !found { ret 2u8 }
        let wn = unhex(want_hex, want_buf[0usize..128usize])
        if !text_is(got, want_buf[0usize..wn]) { ret 3u8 }
        ret 0u8
    }
    let (home_hex, p1) = tok(line, p0)
    let (path_hex, p2) = tok(line, p1)
    let (arrow, p3) = tok(line, p2)
    let (want_hex, p4) = tok(line, p3)
    let hn = unhex(home_hex, home_buf[0usize..64usize])
    let pn = unhex(path_hex, path_buf[0usize..64usize])
    let wn = unhex(want_hex, want_buf[0usize..128usize])
    if kind[0usize] == 88u8 {
        let (got, got_error) = tilde.expand(path_buf[0usize..pn], home_buf[0usize..hn], users[0usize..3usize], out[0usize..128usize])
        if got_error != ok { ret 11u8 }
        if !text_is(got, want_buf[0usize..wn]) { ret 12u8 }
        ret 0u8
    }
    let (got, got_error) = tilde.collapse(path_buf[0usize..pn], home_buf[0usize..hn], out[0usize..128usize])
    if got_error != ok { ret 21u8 }
    if !text_is(got, want_buf[0usize..wn]) { ret 22u8 }
    ret 0u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    var tiny: [3]u8 = zero
    var none: [0]tilde.UserHome = zero
    let (_, small) = tilde.expand("~/abc", "/home", none[0usize..0usize], tiny[0usize..3usize])
    if small != tilde.TooSmall { os.exit(101i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("path tilde ok")
    ret ok
}
'''

src = ('// e.path.tilde against posixpath.expanduser (HOME), a Python model for the user table and collapse,\n'
       '// and a Python parse of the same passwd text (D2801). Generated by scripts/gen_tilde_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.path.tilde\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
