"""Every module of a source tree with its declarations in reverse order (D531, H10).

    python benchmarks/metamorphic/reorder_declarations.py SRC_DIR OUT_DIR

The metamorphic harness's `reorder` transformation (D438) over a whole tree: in each
`.e` file the `use` lines and what precedes them stay, and the rest is split at every
line that starts a declaration -- column one, not a comment, a brace or a blank --
and reversed, an attribute line staying with the declaration under it. Spec section
14 makes module scope order-independent, so a compiler built from the result lays
its functions out in another order and is another image -- but it must build the
original sources to the stable stage byte for byte.
"""
import os, shutil, sys

src_dir, out_dir = sys.argv[1:3]
if os.path.exists(out_dir):
    shutil.rmtree(out_dir)
os.makedirs(out_dir)


def reordered(path):
    lines = open(path, 'rb').read().split(b'\n')
    head = 0
    while head < len(lines) and (lines[head].startswith(b'use ') or lines[head].startswith(b'//') or lines[head].strip() == b''):
        head += 1
    blocks, current = [], []
    pending_attribute = False
    for line in lines[head:]:
        starts = line[:1] not in (b'', b' ', b'\t', b'}', b'/') and not line.startswith(b'//')
        if starts and current and not pending_attribute:
            blocks.append(current)
            current = []
        current.append(line)
        pending_attribute = starts and line.startswith(b'@')
    if current:
        blocks.append(current)
    blocks.reverse()
    return b'\n'.join(lines[:head] + [l for b in blocks for l in b]), len(blocks)


total = 0
for name in sorted(os.listdir(src_dir)):
    source = os.path.join(src_dir, name)
    if not os.path.isfile(source):
        continue
    if name.endswith('.e'):
        text, count = reordered(source)
        open(os.path.join(out_dir, name), 'wb').write(text)
        total += count
    else:
        shutil.copy(source, os.path.join(out_dir, name))
print('blocks', total)
