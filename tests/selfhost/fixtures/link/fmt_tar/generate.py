# Regenerates the two archives in src/main.e: python generate.py, paste the two lines.
import io, tarfile

def strip(raw):
    blocks = [raw[i:i + 512] for i in range(0, len(raw), 512)]
    while len(blocks) > 2 and blocks[-1] == bytes(512) and blocks[-2] == bytes(512) and blocks[-3] == bytes(512):
        blocks.pop()
    return b''.join(blocks)

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w', format=tarfile.USTAR_FORMAT) as t:
    def add(name, data, mtime=1700000000, mode=0o644, kind=tarfile.REGTYPE, link=''):
        ti = tarfile.TarInfo(name)
        ti.size = len(data)
        ti.mtime = mtime
        ti.mode = mode
        ti.type = kind
        ti.linkname = link
        t.addfile(ti, io.BytesIO(data) if data else None)
    add('hello.txt', b'hello, tar\n')
    add('dir/', b'', mode=0o755, kind=tarfile.DIRTYPE)
    add('dir/big.bin', bytes(range(256)) * 3)
    add('link', b'', kind=tarfile.SYMTYPE, link='hello.txt')
raw = strip(buf.getvalue())

buf2 = io.BytesIO()
with tarfile.open(fileobj=buf2, mode='w', format=tarfile.PAX_FORMAT) as t:
    ti = tarfile.TarInfo('a/' * 60 + 'deep.txt')
    data = b'deep'
    ti.size = len(data)
    ti.mtime = 1700000000
    t.addfile(ti, io.BytesIO(data))
raw2 = strip(buf2.getvalue())

BS = chr(92)
def lit(name, b):
    return "    let %s = \"%s\"" % (name, "".join(BS + "x%02x" % x for x in b))

print(lit("archive", raw))
print(lit("pax_archive", raw2))
