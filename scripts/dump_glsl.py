"""Write the GLSL a `--gpu glsl` build embeds (D5888): every kernel's text after the ';' of its module string, decoded
from hex, one `//entry:` shader after another in the order they appear.

    python scripts/dump_glsl.py PROGRAM OUT        write the shaders to OUT
    python scripts/dump_glsl.py PROGRAM --check G  exit 1 unless they equal the golden G
"""
import re
import sys


def shaders(path):
    data = open(path, 'rb').read()
    found = []
    for m in re.finditer(rb'[0-9a-f]{16}:[0-9a-f]*;([0-9a-f]+)', data):
        tail = m.group(1).decode()
        found.append(bytes.fromhex(tail[: len(tail) // 2 * 2]).decode('utf-8'))
    return ''.join(found)


def main(argv):
    text = shaders(argv[1])
    if not text:
        print('no GLSL in %s' % argv[1])
        return 1
    if argv[2] == '--check':
        golden = open(argv[3], encoding='utf-8').read()
        if golden != text:
            print('the GLSL of %s is not %s' % (argv[1], argv[3]))
            return 1
        return 0
    open(argv[2], 'w', encoding='utf-8', newline='\n').write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
