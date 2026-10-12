"""Generate tests/selfhost/fixtures/link/log_rotate/src/main.e (L152, D2802).

Reference: Python's `logging.handlers.RotatingFileHandler` (the policy `e.log.rotate`
adopts): the same messages are logged through the real handler into a temp directory and
the resulting file set (base, base.1, ...) is embedded. Windows text mode turns `\\n`
into `\\r\\n`, which is undone when the files are read back. Configs with `keep == 0` are
not generated (Python never rotates then; `e.log.rotate` truncates, an extension).
"""
import logging
import logging.handlers
import os
import random
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(153)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'log_rotate' / 'src' / 'main.e'


class Handler(logging.handlers.RotatingFileHandler):
    """The stock handler with newline translation off, so `tell()` counts the bytes on disk
    on Windows exactly as it does on Linux."""

    def _open(self):
        return open(self.baseFilename, self.mode, encoding=self.encoding, errors=self.errors, newline='\n')


def run_python(max_bytes, keep, messages):
    d = tempfile.mkdtemp()
    path = os.path.join(d, 'x.log')
    h = Handler(path, maxBytes=max_bytes, backupCount=keep, encoding='latin-1')
    h.setFormatter(logging.Formatter('%(message)s'))
    lg = logging.Logger('t')
    lg.addHandler(h)
    for m in messages:
        lg.warning(m)
    h.close()
    files = []
    for suffix in [''] + ['.%d' % i for i in range(1, keep + 1)]:
        p = path + suffix
        if os.path.exists(p):
            data = open(p, 'rb').read().replace(b'\r\n', b'\n')
            files.append(data)
        else:
            files.append(None)
    return files


def word():
    return ''.join(random.choice('abcdefghij XYZ0123') for _ in range(random.randint(1, 40))).replace('  ', ' ')


lines = []
configs = [(50, 3), (100, 2), (30, 5), (64, 1), (200, 4), (45, 3), (17, 2)]
for max_bytes, keep in configs:
    for _ in range(3):
        n = random.randint(5, 60)
        # a record of max_bytes or more would roll an empty file in Python; keep records shorter
        msgs = [word()[:max_bytes - 2] or 'x' for _ in range(n)]
        files = run_python(max_bytes, keep, msgs)
        lines.append('R %d %d %d %s => %s' % (max_bytes, keep, n, ' '.join(m.encode().hex() for m in msgs),
                                              ' '.join((f.hex() or '-') if f is not None else 'X' for f in files)))

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

fn name_of(a: *mem.Arena, index: u32) -> str {
    if index == 0u32 { ret "np-rotate.log" }
    let (n, n_error) = rotate.backup_name(a, "np-rotate.log", index)
    if n_error != ok { ret "" }
    ret n
}

fn clear(a: *mem.Arena) {
    var i = 0u32
    while i <= 8u32 {
        let removed = os.remove_file(a, name_of(a, i))
        i += 1u32
    }
}

fn slurp(a: *mem.Arena, path: str, dst: []u8) -> (usize, bool) {
    var flags: os.OpenFlags = zero
    flags.read = true
    let (f, open_error) = os.open(a, path, flags)
    if open_error != ok { ret (0usize, false) }
    var n = 0usize
    while n < dst.len {
        let (got, read_error) = os.read(f, dst[n..dst.len])
        if read_error != ok { break }
        if got == 0usize { break }
        n += got
    }
    let closed = os.close(f)
    ret (n, true)
}

fn check_line(a: *mem.Arena, line: str) -> u8 {
    var msg: [64]u8 = zero
    var want: [4096]u8 = zero
    var got: [4096]u8 = zero
    let mark = mem.mark(a)
    clear(a)
    let (kind, p0) = tok(line, 0usize)
    let (max_text, p1) = tok(line, p0)
    let (keep_text, p2) = tok(line, p1)
    let (count_text, p3) = tok(line, p2)
    let count = usize(dec(count_text))
    let keep = u32(dec(keep_text))
    let (r, open_error) = rotate.open(a, "np-rotate.log", u64(dec(max_text)), keep)
    if open_error != ok { ret 1u8 }
    var rot = r
    var p = p3
    var k = 0usize
    while k < count {
        let (word_hex, next) = tok(line, p)
        p = next
        let n = unhex(word_hex, msg[0usize..63usize])
        msg[n] = 10u8
        if rotate.write(&rot, msg[0usize..n + 1usize]) != ok { ret 2u8 }
        k += 1usize
    }
    let closed = rotate.close(&rot)
    let (arrow, p4) = tok(line, p)
    var q = p4
    var index = 0u32
    while index <= keep {
        let (file_hex, next) = tok(line, q)
        q = next
        let (n, found) = slurp(a, name_of(a, index), got[0usize..4096usize])
        if file_hex[0usize] == 88u8 {
            if found { ret 3u8 }
        } else {
            if !found { ret 4u8 }
            let wn = unhex(file_hex, want[0usize..4096usize])
            if wn != n { ret 5u8 }
            var j = 0usize
            while j < n {
                if got[j] != want[j] { ret 6u8 }
                j += 1usize
            }
        }
        index += 1u32
    }
    clear(a)
    mem.reset(a, mark)
    ret 0u8
}

fn run_text(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let code = check_line(a, text[start..i])
            if code != 0u8 {
                let shown = io.print(text[start..start + 40usize])
                ret code
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

'''

calls = '\n'.join('    let r_%s = run_text(a, %s())\n    if r_%s != 0u8 { os.exit(i32(r_%s)) }' % (n, n, n, n) for n in names)

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    clear(a)
    // A record at or past the limit still lands whole, in a freshly rotated file; keep == 0 truncates.
    let (r, open_error) = rotate.open(a, "np-rotate.log", 10u64, 2u32)
    if open_error != ok { os.exit(101i32) }
    var rot = r
    if rotate.write(&rot, "aaaa\\n") != ok { os.exit(102i32) }
    if rotate.write(&rot, "this record is longer than ten bytes\\n") != ok { os.exit(103i32) }
    let closed = rotate.close(&rot)
    var buf: [128]u8 = zero
    let (n0, f0) = slurp(a, "np-rotate.log", buf[0usize..128usize])
    if !f0 || n0 != 37usize { os.exit(104i32) }
    let (n1, f1) = slurp(a, "np-rotate.log.1", buf[0usize..128usize])
    if !f1 || n1 != 5usize { os.exit(105i32) }
    if rotate.write(&rot, "x") != rotate.Closed { os.exit(106i32) }
    clear(a)
    let (z, z_error) = rotate.open(a, "np-rotate.log", 8u64, 0u32)
    if z_error != ok { os.exit(107i32) }
    var zr = z
    if rotate.write(&zr, "abcd\\n") != ok || rotate.write(&zr, "efgh\\n") != ok { os.exit(108i32) }
    let zc = rotate.close(&zr)
    let (n2, f2) = slurp(a, "np-rotate.log", buf[0usize..128usize])
    if !f2 || n2 != 5usize { os.exit(109i32) }
    let (n3, f3) = slurp(a, "np-rotate.log.1", buf[0usize..128usize])
    if f3 { os.exit(110i32) }
    clear(a)
''' + calls + '''
    try io.print("log rotate ok")
    ret ok
}
'''

src = ('// e.log.rotate against Python\'s RotatingFileHandler: the same messages through the real handler, the\n'
       '// resulting base, base.1 .. base.N files embedded and compared byte for byte (D2802). X marks an\n'
       '// absent file. Generated by scripts/gen_rotate_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.log.rotate\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
