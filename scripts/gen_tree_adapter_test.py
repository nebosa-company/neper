"""Reference model for tests/selfhost/fixtures/link/ui_tree_adapter (L067, D2881).

An independent model of the adapter's documented behaviour (module header of
lib/e/ui/tree_adapter.e): path identity (folded or not), natural sibling order with
folders first (digit runs by magnitude, shorter zero padding first, ASCII case folded,
code point tie-break), placeholder rows for loading and failed folders, key assignment
(prev keys by path or by rename, then FNV-1a 64 of the folded identity probed upward in
identity-path order), selection settling and the scroll anchor. It writes the scenarios'
entry tables and expected renderings between BEGIN SCENARIOS and END SCENARIOS of the
fixture's main.e.

    python scripts/gen_tree_adapter_test.py
"""
import functools
import pathlib

MAIN = pathlib.Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/ui_tree_adapter/src/main.e"
M64 = (1 << 64) - 1


def fnv(data):
    h = 14695981039346656037
    for b in data:
        h = ((h ^ b) * 1099511628211) & M64
    return h


def weak(data):
    return len(data)


def fold(s, sensitive):
    return s if sensitive else "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)


def natural(a, b, case_sensitive=False):
    """-1/0/1: digit runs by magnitude, then by run length; folded; code point tie."""
    i = j = 0
    while i < len(a) and j < len(b):
        if a[i].isdigit() and b[j].isdigit() and a[i] in "0123456789" and b[j] in "0123456789":
            si, sj = i, j
            while i < len(a) and a[i] in "0123456789":
                i += 1
            while j < len(b) and b[j] in "0123456789":
                j += 1
            ra, rb = a[si:i].lstrip("0"), b[sj:j].lstrip("0")
            if len(ra) != len(rb):
                return -1 if len(ra) < len(rb) else 1
            if ra != rb:
                return -1 if ra < rb else 1
            if i - si != j - sj:
                return -1 if (i - si) < (j - sj) else 1
            continue
        ca, cb = a[i], b[j]
        if not case_sensitive:
            ca, cb = fold(ca, False), fold(cb, False)
        if ca != cb:
            return -1 if ord(ca) < ord(cb) else 1
        i += 1
        j += 1
    if i < len(a):
        return 1
    if j < len(b):
        return -1
    if a != b:
        return -1 if a < b else 1
    return 0


class Model:
    def __init__(self, entries, renames=(), prev=None, case_sensitive=True, hasher=fnv, folders_first=True):
        self.cs = case_sensitive
        self.hasher = hasher
        self.nodes = []  # dicts
        paths = [e[0] for e in entries]
        ident = lambda p: fold(p, case_sensitive)
        by_id = {}
        for (p, is_dir, state) in entries:
            if ident(p) in by_id:
                raise ValueError("Duplicate")
            by_id[ident(p)] = (p, is_dir, state)
        order = sorted(by_id.keys(), key=lambda s: s.encode("latin-1", "backslashreplace") if False else [ord(c) for c in s])
        info = {}
        for k in order:
            p, is_dir, state = by_id[k]
            info[k] = {"path": p, "kind": "D" if is_dir else "F", "state": state, "parent": None}
        for k in order:
            p = info[k]["path"]
            if "/" in p:
                par = ident(p.rsplit("/", 1)[0])
                if par not in info:
                    raise ValueError("MissingParent")
                if info[par]["kind"] != "D":
                    raise ValueError("NotDirectory")
                info[k]["parent"] = par
        # placeholders in identity order of their folders
        allnodes = dict(info)
        for k in order:
            n = info[k]
            if n["kind"] == "D" and n["state"] != 0:
                pp = n["path"] + "/\x00" + chr(1 if n["state"] == 1 else 2)
                allnodes[ident(pp)] = {"path": pp, "kind": "L" if n["state"] == 1 else "X", "state": 0, "parent": k}
        self.info = allnodes
        ids = sorted(allnodes.keys(), key=lambda s: [ord(c) for c in s])
        # keys: pass one from prev, pass two by hash in identity order
        keys, used = {}, set()
        for k in ids:
            if prev is None:
                break
            p = allnodes[k]["path"]
            old = None
            for (frm, to) in renames:
                if ident(p) == ident(to) or ident(p).startswith(ident(to) + "/"):
                    old = ident(frm + p[len(to):])
                    break
            if old is None:
                old = k
            if old in prev.keys_by_id and prev.keys_by_id[old] not in used:
                keys[k] = prev.keys_by_id[old]
                used.add(keys[k])
        for k in ids:
            if k in keys:
                continue
            key = hasher(fold(allnodes[k]["path"], case_sensitive).encode("latin-1"))
            if key == 0:
                key = 1
            while key in used:
                key = (key + 1) & M64
                if key == 0:
                    key = 1
            keys[k] = key
            used.add(key)
        self.keys_by_id = keys
        self.keys = keys
        # siblings
        def name_of(n):
            return n["path"].rsplit("/", 1)[-1] if n["kind"] in "DF" else ""

        def rank(n):
            if n["kind"] in "LX":
                return 2
            return 0 if (n["kind"] == "D" and folders_first) else 1

        def cmp(x, y):
            a, b = allnodes[x], allnodes[y]
            ra, rb = rank(a), rank(b)
            if ra != rb:
                return -1 if ra < rb else 1
            if ra < 2:
                c = natural(name_of(a), name_of(b), False)
                if c:
                    return c
            ix, iy = [ord(c) for c in fold(a["path"], case_sensitive)], [ord(c) for c in fold(b["path"], case_sensitive)]
            return -1 if ix < iy else (1 if ix > iy else 0)

        self.children = {}
        for k in ids:
            self.children.setdefault(allnodes[k]["parent"], []).append(k)
        for par in self.children:
            self.children[par].sort(key=functools.cmp_to_key(cmp))
        self.ident = ident

    def key_of(self, path):
        return self.keys[self.ident(path)]

    def has(self, path):
        return self.ident(path) in self.keys

    def rows(self, expanded_ids=None):
        """Depth-first visible rows with every folder expanded (or the given ids)."""
        out = []

        def walk(par, depth):
            for k in self.children.get(par, []):
                n = self.info[k]
                out.append((self.keys[k], depth, n["kind"], n["path"].replace("\x00", "<0>").replace("\x01", "L").replace("\x02", "X")))
                if n["kind"] == "D" and (expanded_ids is None or k in expanded_ids):
                    walk(k, depth + 1)

        walk(None, 0)
        return out

    def render(self):
        return "".join(f"{k} {d} {kind} {p}\n" for (k, d, kind, p) in self.rows())

    def settle(self, prev, key):
        """Where `key` of prev goes in self (the module header's rule)."""
        inv = {v: k for k, v in self.keys.items()}
        if key in inv:
            return key
        pinv = {v: k for k, v in prev.keys.items()}
        old = pinv[key]
        cur = old
        while True:
            par = prev.info[cur]["parent"]
            if par is None:
                roots = self.children.get(None, [])
                if not roots:
                    return 0
                pos = prev.children[None].index(cur)
                return self.keys[roots[min(pos, len(roots) - 1)]]
            pk = prev.keys[par]
            if pk in inv:
                alive = inv[pk]
                kids = self.children.get(alive, [])
                if cur != old or not kids:
                    return pk
                pos = prev.children[par].index(old)
                return self.keys[kids[min(pos, len(kids) - 1)]]
            cur = par


def anchor(before_rows, after_rows, offset, row_h, viewport):
    if not before_rows or not after_rows:
        return 0.0
    index = min(int(offset / row_h), len(before_rows) - 1)
    within = offset - index * row_h
    after_idx = {k: i for i, (k, *_r) in enumerate(after_rows)}
    target, carry = None, 0.0
    for d in range(index, len(before_rows)):
        if before_rows[d][0] in after_idx:
            target = after_idx[before_rows[d][0]]
            carry = within if d == index else 0.0
            break
    if target is None:
        for d in range(index - 1, -1, -1):
            if before_rows[d][0] in after_idx:
                target = after_idx[before_rows[d][0]]
                carry = 0.0
                break
    if target is None:
        target = 0
    out = target * row_h + carry
    most = max(len(after_rows) * row_h - viewport, 0.0)
    return min(max(out, 0.0), most)


def nlit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def entries_fn(name, entries):
    s = f"fn {name}(out: []tree.Entry) -> usize {{\n"
    for i, (p, d, st) in enumerate(entries):
        state = {0: ".Ready", 1: ".Loading", 2: ".Failed"}[st]
        s += f"    out[{i}usize] = tree.Entry {{ path: {nlit(p)}, dir: {'true' if d else 'false'}, state: {state} }}\n"
    s += f"    ret {len(entries)}usize\n}}\n"
    return s


# ---------------------------------------------------------------------------------- data
S1 = [  # a case-sensitive host; input order is deliberately not sorted
    ("src/lib/y10.e", False, 0), ("README.md", False, 0), ("readme.md", False, 0), ("docs", True, 0),
    ("src", True, 0), ("src/lib", True, 0), ("src/main.e", False, 0), ("src/lib/x.e", False, 0),
    ("docs/a10.txt", False, 0), ("docs/a2.txt", False, 0), ("docs/A1.txt", False, 0), ("docs/B.txt", False, 0),
    ("Zeta", True, 0), ("alpha", True, 0), ("alpha/one", False, 0), ("10.txt", False, 0), ("9.txt", False, 0),
    ("09.txt", False, 0), ("net", True, 1), ("bad", True, 2), ("src/lib/y2.e", False, 0), ("Zeta/z", False, 0),
]
S2 = [  # after: src renamed core, docs/B.txt removed, docs/new.txt added, net loaded, bad ready
    ("core", True, 0), ("core/main.e", False, 0), ("core/lib", True, 0), ("core/lib/x.e", False, 0),
    ("core/lib/y2.e", False, 0), ("core/lib/y10.e", False, 0), ("core/added.e", False, 0),
    ("README.md", False, 0), ("readme.md", False, 0), ("docs", True, 0), ("docs/a10.txt", False, 0),
    ("docs/a2.txt", False, 0), ("docs/A1.txt", False, 0), ("docs/new.txt", False, 0),
    ("Zeta", True, 0), ("alpha", True, 0), ("alpha/one", False, 0), ("10.txt", False, 0), ("9.txt", False, 0),
    ("09.txt", False, 0), ("net", True, 0), ("net/a.c", False, 0), ("bad", True, 0),
]
S2_RENAMES = [("src", "core")]
# the same names as S1 with only the case differing between two of them
S5_CI = [("docs", True, 0), ("Docs/x", False, 0)]  # parent found by folding
S5_DUP = [("A.txt", False, 0), ("a.txt", False, 0)]
S5_MISSING = [("a/b", False, 0)]
S5_FILE_PARENT = [("a", False, 0), ("a/b", False, 0)]
S5_SLASH = [("a/", True, 0)]
# collisions: a hash that is the identity's length, so every same-length path collides
S4_A = [("aaa", False, 0), ("bbb", False, 0), ("ccc", False, 0), ("dd", True, 0), ("dd/ee", False, 0), ("ff", True, 0)]
S4_B = [("ccc", False, 0), ("0zz", False, 0), ("bbb", False, 0), ("ff", True, 0), ("dd/ee", False, 0), ("dd", True, 0), ("aaa", False, 0), ("zzz", False, 0)]


def large(deleted=(), added=(), renamed=None):
    """30 packages of 100 numbered files plus top-level files; listed in reverse order."""
    out = []
    for d in range(30):
        base = f"pkg{d}"
        if renamed and d == renamed[0]:
            base = renamed[1]
        out.append((base, True, 0))
        for k in range(100):
            if (d, k) in deleted:
                continue
            out.append((f"{base}/f{k}.c" if k % 7 else f"{base}/F{k}.h", False, 0))
        for (dd, kk) in added:
            if dd == d:
                out.append((f"{base}/new{kk}.c", False, 0))
    for t in range(40):
        out.append((f"top{t}.txt", False, 0))
    out.reverse()
    return out


def main():
    parts = []
    parts.append(entries_fn("s1_entries", S1))
    parts.append(entries_fn("s2_entries", S2))
    parts.append(entries_fn("s4_a", S4_A))
    parts.append(entries_fn("s4_b", S4_B))
    parts.append(entries_fn("s5_ci", S5_CI))
    parts.append(entries_fn("s5_dup", S5_DUP))
    parts.append(entries_fn("s5_missing", S5_MISSING))
    parts.append(entries_fn("s5_file_parent", S5_FILE_PARENT))
    parts.append(entries_fn("s5_slash", S5_SLASH))

    m1 = Model(S1, case_sensitive=True)
    m2 = Model(S2, S2_RENAMES, m1, case_sensitive=True)
    expect = {}
    expect["s1"] = m1.render()
    expect["s2"] = m2.render()
    # selection and expansion
    sel_old = "docs/B.txt"
    settled = m2.settle(m1, m1.key_of(sel_old))
    expect["settle_docs"] = [p for (k, d, kind, p) in m2.rows() if k == settled][0]
    # a selected node under a folder that vanished: src/lib/x.e with src->core renamed keeps its key,
    # so the second probe removes alpha/one (its folder survives) and the third a whole folder
    m3_entries = [e for e in S2 if not e[0].startswith("docs")]
    m3 = Model(m3_entries, (), m2, case_sensitive=True)
    settled2 = m3.settle(m2, m2.key_of("docs/a2.txt"))
    expect["settle_gone"] = [p for (k, d, kind, p) in m3.rows() if k == settled2][0]
    # scroll anchor over S1 -> S2, everything expanded, 20 high rows, 100 viewport
    rows1, rows2 = m1.rows(), m2.rows()
    expect["anchor"] = [anchor(rows1, rows2, off, 20.0, 100.0) for off in (0.0, 107.0, 20.0 * 12 + 3.0, 20.0 * 30)]
    expect["anchor_rows"] = (len(rows1), len(rows2))
    # collisions
    c1 = Model(S4_A, case_sensitive=True, hasher=weak)
    c2 = Model(S4_B, (), c1, case_sensitive=True, hasher=weak)
    expect["s4a"] = c1.render()
    expect["s4b"] = c2.render()
    ci = Model(S5_CI, case_sensitive=False)
    expect["s5ci"] = ci.render()
    # large
    L1 = Model(large(), case_sensitive=True)
    dele = {(2, k) for k in range(0, 100, 3)} | {(11, 5)}
    adds = [(7, 1), (7, 2), (19, 0)]
    L2 = Model(large(deleted=dele, added=adds, renamed=(3, "mod3")), [("pkg3", "mod3")], L1, case_sensitive=True)
    expect["l1_digest"] = fnv(L1.render().encode("latin-1", "replace"))
    expect["l2_digest"] = fnv(L2.render().encode("latin-1", "replace"))
    expect["l1_rows"] = len(L1.rows())
    expect["l2_rows"] = len(L2.rows())
    expect["l_stable"] = sum(1 for k, v in L1.keys.items() if k in L2.keys and L2.keys[k] == v)
    expect["l_mod3"] = L2.key_of("mod3/f5.c") == L1.key_of("pkg3/f5.c")
    expect["l_new"] = L2.key_of("pkg7/new1.c")

    def fn_str(name, value):
        return f"fn {name}() -> str {{ ret {nlit(value)} }}\n"

    def fn_u64(name, value):
        return f"fn {name}() -> u64 {{ ret {value}u64 }}\n"

    parts.append(fn_str("want_s1", expect["s1"]))
    parts.append(fn_str("want_s2", expect["s2"]))
    parts.append(fn_str("want_s4a", expect["s4a"]))
    parts.append(fn_str("want_s4b", expect["s4b"]))
    parts.append(fn_str("want_s5ci", expect["s5ci"]))
    parts.append(fn_str("want_settle_docs", expect["settle_docs"]))
    parts.append(fn_str("want_settle_gone", expect["settle_gone"]))
    parts.append(fn_u64("want_l1_digest", expect["l1_digest"]))
    parts.append(fn_u64("want_l2_digest", expect["l2_digest"]))
    parts.append(fn_u64("want_l_new", expect["l_new"]))
    parts.append("fn want_l1_rows() -> usize { ret %dusize }\n" % expect["l1_rows"])
    parts.append("fn want_l2_rows() -> usize { ret %dusize }\n" % expect["l2_rows"])
    parts.append("fn want_l_stable() -> usize { ret %dusize }\n" % expect["l_stable"])
    parts.append("fn want_rows1() -> usize { ret %dusize }\n" % expect["anchor_rows"][0])
    parts.append("fn want_rows2() -> usize { ret %dusize }\n" % expect["anchor_rows"][1])
    a = expect["anchor"]
    parts.append("fn want_anchor(i: usize) -> f32 {\n" + "".join(f"    if i == {i}usize {{ ret {v!r} }}\n" for i, v in enumerate(a)) + "    ret -1.0\n}\n")
    assert expect["l_mod3"]
    text = MAIN.read_text(encoding="utf-8")
    lo = text.index("// BEGIN SCENARIOS\n") + len("// BEGIN SCENARIOS\n")
    hi = text.index("// END SCENARIOS")
    MAIN.write_text(text[:lo] + "\n".join(parts) + text[hi:], encoding="utf-8")
    print("rows", len(rows1), len(rows2), expect["l1_rows"], expect["l2_rows"], "stable", expect["l_stable"], "anchors", a)
    print(expect["settle_docs"], "|", expect["settle_gone"])


if __name__ == "__main__":
    main()
