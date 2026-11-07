"""Insert generated fence lines at the end of a module's ```neper block in docs/module-apis.md.

Usage: insert_fence_lines.py MODULE FENCE_LINES.txt

The checker compares fences by (kind, name) and exact text, not by order, so
appending before the closing fence is enough. Lines already present verbatim
are skipped, which makes a re-run safe.
"""
import sys

module, lines_path = sys.argv[1], sys.argv[2]
new_lines = [line.rstrip('\n') for line in open(lines_path, encoding='utf-8') if line.strip()]

path = 'docs/module-apis.md'
text = open(path, encoding='utf-8').read()
lines = text.splitlines()

header = '### `%s`' % module
try:
    start = lines.index(header)
except ValueError:
    sys.exit('module heading not found: ' + header)

open_at = start
while open_at < len(lines) and lines[open_at].strip() != '```neper':
    open_at += 1
close_at = open_at + 1
while close_at < len(lines) and lines[close_at].strip() != '```':
    close_at += 1

body = set(lines[open_at + 1:close_at])
added = [line for line in new_lines if line not in body]
lines[close_at:close_at] = added
open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
print('added %d line(s) to %s' % (len(added), module))
