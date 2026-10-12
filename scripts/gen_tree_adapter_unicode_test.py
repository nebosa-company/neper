"""Reference data for tests/selfhost/fixtures/link/ui_tree_adapter_unicode (L067, D3305).

Part one is an independent model of the name order of lib/e/ui/tree_adapter.e under
`policy_unicode` (Python's unicodedata NFD, `lower`, its own natural comparison; folders
first, then the base letters, then the full NFD letters, then the identity bytes) and under
the ASCII `policy` (natural order with ASCII folding, then code points, then bytes). Part
two writes the small lazy-loading listings. The scenarios go between BEGIN SCENARIOS and
END SCENARIOS of the fixture's main.e.

    python scripts/gen_tree_adapter_unicode_test.py
"""
import functools
import pathlib
import unicodedata

MAIN = pathlib.Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/ui_tree_adapter_unicode/src/main.e"

ENTRIES = [  # (name, is_dir); one folder's worth, deliberately unsorted
    ("apple", 0), ("Äpfel", 0), ("zebra", 0), ("Zoë", 0), ("éclair", 0), ("Eclair", 0), ("eclair2", 0),
    ("Ecole", 0), ("école", 0), ("école", 0), ("ñandu", 0), ("nugget", 0), ("Nz", 0), ("Ωmega", 0),
    ("alpha", 0), ("Αλφα", 0), ("Ярлык", 0), ("ярлык", 0),
    ("файл10", 0), ("файл2", 0), ("Файл1", 0),
    ("10 résumé.txt", 0), ("9 resume.txt", 0), ("résumé", 0), ("resume", 0), ("Resume", 0), ("résume", 0),
    ("Öl", 1), ("ol", 1), ("Zürich", 1), ("zebra-dir", 1), ("Éire", 1), ("eire", 1), ("File007", 0), ("file7", 0), ("file12", 0),
]


def natural(x, y, numeric=True):
    """-1/0/1 over two lists of code points: ASCII digit runs by magnitude, then by length."""
    i = j = 0
    dig = lambda c: 48 <= c <= 57
    while i < len(x) and j < len(y):
        if numeric and dig(x[i]) and dig(y[j]):
            si, sj = i, j
            while i < len(x) and dig(x[i]):
                i += 1
            while j < len(y) and dig(y[j]):
                j += 1
            a = list(x[si:i])
            b = list(y[sj:j])
            while a and a[0] == 48:
                a = a[1:]
            while b and b[0] == 48:
                b = b[1:]
            if len(a) != len(b):
                return -1 if len(a) < len(b) else 1
            if a != b:
                return -1 if a < b else 1
            if i - si != j - sj:
                return -1 if i - si < j - sj else 1
            continue
        if x[i] != y[j]:
            return -1 if x[i] < y[j] else 1
        i += 1
        j += 1
    if i < len(x):
        return 1
    if j < len(y):
        return -1
    return 0


def lower1(ch):
    r = ch.lower()
    assert len(r) == 1, ch
    return ord(r)


def unicode_keys(name):
    nfd = unicodedata.normalize("NFD", name)
    allk = [lower1(c) for c in nfd]
    base = [lower1(c) for c in nfd if unicodedata.combining(c) == 0]
    return base, allk


def ascii_fold(cp):
    return cp + 32 if 65 <= cp <= 90 else cp


def order(entries, unicode_mode):
    def cmp(x, y):
        (nx, dx), (ny, dy) = x, y
        if dx != dy:
            return -1 if dx else 1  # folders first
        if unicode_mode:
            bx, ax = unicode_keys(nx)
            by, ay = unicode_keys(ny)
            c = natural(bx, by)
            if c:
                return c
            c = natural(ax, ay, numeric=False)
            if c:
                return c
        else:
            c = natural([ascii_fold(ord(ch)) for ch in nx], [ascii_fold(ord(ch)) for ch in ny])
            if c:
                return c
            cx, cy = [ord(ch) for ch in nx], [ord(ch) for ch in ny]
            if cx != cy:
                return -1 if cx < cy else 1
        bx, by = nx.encode("utf-8"), ny.encode("utf-8")
        return -1 if bx < by else (1 if bx > by else 0)

    return sorted(entries, key=functools.cmp_to_key(cmp))


def listing(entries, unicode_mode):
    return "".join("0 %s %s\n" % ("D" if d else "F", n) for (n, d) in order(entries, unicode_mode))


def nlit(s):
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ord(ch) < 128:
            out.append(ch)
        else:
            out.append("".join("\\x%02x" % b for b in ch.encode("utf-8")))
    out.append('"')
    return "".join(out)


def entries_fn(name, entries):
    s = "fn %s(out: []tree.Entry) -> usize {\n" % name
    for i, (p, d, st) in enumerate(entries):
        state = [".Ready", ".Loading", ".Failed", ".Unloaded"][st]
        s += "    out[%dusize] = tree.Entry { path: %s, dir: %s, state: %s }\n" % (i, nlit(p), "true" if d else "false", state)
    s += "    ret %dusize\n}\n" % len(entries)
    return s


def main():
    parts = [entries_fn("names", [(n, bool(d), 0) for (n, d) in ENTRIES])]
    parts.append("fn want_unicode() -> str { ret %s }\n" % nlit(listing(ENTRIES, True)))
    parts.append("fn want_ascii() -> str { ret %s }\n" % nlit(listing(ENTRIES, False)))
    lazy1 = [("src", True, 3), ("README.md", False, 0), ("docs", True, 0), ("docs/a.txt", False, 0)]
    lazy2 = [("src", True, 1), ("README.md", False, 0), ("docs", True, 0), ("docs/a.txt", False, 0)]
    lazy3 = [("src", True, 0), ("src/main.e", False, 0), ("src/lib", True, 3), ("README.md", False, 0), ("docs", True, 0), ("docs/a.txt", False, 0)]
    parts += [entries_fn("lazy_1", lazy1), entries_fn("lazy_2", lazy2), entries_fn("lazy_3", lazy3)]
    parts.append("fn want_lazy_1() -> str { ret %s }\n" % nlit("0 D docs\n1 F a.txt\n0 D? src\n0 F README.md\n"))
    parts.append("fn want_lazy_2() -> str { ret %s }\n" % nlit("0 D docs\n1 F a.txt\n0 D src\n1 L \n0 F README.md\n"))
    parts.append("fn want_lazy_3() -> str { ret %s }\n" % nlit("0 D docs\n1 F a.txt\n0 D src\n1 D? lib\n1 F main.e\n0 F README.md\n"))
    text = MAIN.read_text(encoding="utf-8")
    lo = text.index("// BEGIN SCENARIOS\n") + len("// BEGIN SCENARIOS\n")
    hi = text.index("// END SCENARIOS")
    MAIN.write_text(text[:lo] + "\n".join(parts) + text[hi:], encoding="utf-8", newline="\n")
    print(listing(ENTRIES, True).encode("utf-8"))
    print(listing(ENTRIES, False).encode("utf-8"))


if __name__ == "__main__":
    main()
