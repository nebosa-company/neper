"""Join multi-line `type X = struct/union/enum {` declarations into one line (the fence
tooling reads one line per declaration). usage: python join_structs.py <file>..."""
import re, sys
for p in sys.argv[1:]:
    s = open(p, encoding='utf-8').read()
    out = []
    lines = s.split('\n')
    i = 0
    changed = 0
    while i < len(lines):
        ln = lines[i]
        if re.match(r'^type \w+(\[[^\]]*\])? = (struct|union( enum[^{]*)?|enum[^{]*) \{\s*$', ln):
            fields = []
            j = i + 1
            while j < len(lines) and lines[j].strip() != '}':
                f = lines[j].strip().rstrip(',')
                f = re.sub(r'\s*//.*$', '', f).rstrip(',')
                if f:
                    fields.append(f)
                j += 1
            out.append(ln.rstrip() + ' ' + ', '.join(fields) + ' }')
            i = j + 1
            changed += 1
        else:
            out.append(ln)
            i += 1
    if changed:
        open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
    print(p, changed)
