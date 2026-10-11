"""Vectors for tests/selfhost/fixtures/link/algo_tidy (L064).

Oracle: pandas (merge, melt, groupby shift/diff/rank/cumsum/cummax/ffill/bfill,
dropna, fillna) for the data verbs, and a direct Python implementation of
dplyr's tidy-select ordering rules for select/relocate (no R on this host).
Frames travel as `name,name;cell,cell;...` with `~` blank, `#<number>` and
`'<text>`. Run from the repo root.
"""
import sys
from itertools import product
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from fixture_vectors import emit

rng = np.random.default_rng(64)
lines = []
NA = None


def cell(v):
    if v is None or (isinstance(v, float) and v != v):
        return "~"
    if isinstance(v, str):
        assert not any(c in v for c in ",;|~#'\n"), v
        return "'" + v
    return "#" + repr(float(v))


def enc(cols, rows):
    return ";".join([",".join(cols)] + [",".join(cell(v) for v in row) for row in rows])


def enc_df(df):
    return enc(list(df.columns), [[None if pd.isna(v) else v for v in r] for r in df.itertuples(index=False)])


def frame(n, specs, blank=0.15):
    """specs: list of (name, kind) with kind num|int|text|key."""
    cols, rows = [], []
    for name, kind in specs:
        cols.append(name)
    for i in range(n):
        row = []
        for name, kind in specs:
            if rng.random() < blank and kind != "key":
                row.append(None)
            elif kind == "num":
                row.append(round(float(rng.normal(10, 5)), 3))
            elif kind == "int":
                row.append(float(rng.integers(0, 6)))
            elif kind == "key":
                row.append(float(rng.integers(1, 5)))
            else:
                row.append(str(rng.choice(["ant", "bee", "cat", "dog", "eel"])))
        rows.append(row)
    return cols, rows


def kind_of(rows, j):
    for r in rows:
        v = r[j]
        if v is not None and not (isinstance(v, float) and v != v):
            return "text" if isinstance(v, str) else "number"
    return "none"


# ---- select / relocate / rename ----------------------------------------------------------------------------------
def resolve(cols, rows, sels):
    names = list(cols)
    chosen = list(names) if sels and sels[0][3] else []
    for kind, a, b, neg in sels:
        if kind == 1:
            i, j = names.index(a), names.index(b)
            lo, hi = min(i, j), max(i, j)
            hit = names[lo:hi + 1]
        elif kind == 0:
            assert a in names
            hit = [a]
        elif kind == 2:
            hit = [n for n in names if n.startswith(a)]
        elif kind == 3:
            hit = [n for n in names if n.endswith(a)]
        elif kind == 4:
            hit = [n for n in names if a in n]
        elif kind == 5:
            hit = list(names)
        else:
            hit = [n for n in names if kind_of(rows, names.index(n)) == a]
        for n in hit:
            if neg:
                if n in chosen:
                    chosen.remove(n)
            elif n not in chosen:
                chosen.append(n)
    return chosen


def sel_text(sels):
    return " ".join(f"{k}:{a}:{b}:{int(neg)}" for k, a, b, neg in sels)


base_cols = ["id", "x_one", "x_two", "y_one", "name", "z", "flag_a", "flag_b"]
for trial in range(6):
    rows = []
    for i in range(7):
        rows.append([float(i), round(float(rng.normal()), 3), None if rng.random() < 0.2 else round(float(rng.normal()), 3),
                     float(rng.integers(0, 9)), str(rng.choice(["ant", "bee", "cat"])), round(float(rng.normal()), 3),
                     str(rng.choice(["p", "q"])), None if rng.random() < 0.3 else str(rng.choice(["p", "q"]))])
    cases = [
        [(0, "z", "", False), (0, "id", "", False)],
        [(1, "x_one", "y_one", False)],
        [(2, "x_", "", False), (0, "name", "", False)],
        [(3, "_one", "", False)],
        [(4, "flag", "", False), (5, "", "", False)],
        [(5, "", "", False), (2, "x_", "", True)],
        [(6, "number", "", False)],
        [(6, "text", "", False), (0, "name", "", True)],
        [(2, "x_", "", True)],
        [(1, "y_one", "x_two", False), (0, "z", "", True)],
    ]
    sels = cases[trial % len(cases)] if trial < 5 else cases[5 + (trial % 5)]
    chosen = resolve(base_cols, rows, sels)
    proj = [[r[base_cols.index(c)] for c in chosen] for r in rows]
    lines.append(f"sel|{sel_text(sels)}|{enc(base_cols, rows)}|{enc(chosen, proj)}")
    # relocate: front, before, after.
    for before, after in (("", ""), ("name", ""), ("", "x_two")):
        moved = chosen
        rest = [c for c in base_cols if c not in moved]
        if not before and not after:
            order = moved + rest
        elif before:
            if before in moved:
                continue
            k = rest.index(before)
            order = rest[:k] + moved + rest[k:]
        else:
            if after in moved:
                continue
            k = rest.index(after)
            order = rest[:k + 1] + moved + rest[k + 1:]
        out = [[r[base_cols.index(c)] for c in order] for r in rows]
        lines.append(f"rel|{sel_text(sels)}|{before}|{after}|{enc(base_cols, rows)}|{enc(order, out)}")

for _ in range(2):
    rows = [[float(i), round(float(rng.normal()), 3), str(rng.choice(["a", "b"]))] for i in range(5)]
    cols = ["k", "v", "g"]
    new = ["key", "value"]
    out_cols = ["key", "value", "g"]
    lines.append(f"ren|k>key v>value|{enc(cols, rows)}|{enc(out_cols, rows)}")

# mutate: new = src * mult + add (blank when src is blank), replacing or appending.
for dest, src in (("w", "v"), ("v", "v"), ("t", "u")):
    cols = ["id", "v", "u"]
    rows = [[float(i), None if rng.random() < 0.3 else round(float(rng.normal()), 3), round(float(rng.normal()), 3)] for i in range(6)]
    mult, add = 2.5, -1.0
    out_cols = list(cols) if dest in cols else cols + [dest]
    out = []
    for r in rows:
        v = r[cols.index(src)]
        new = None if v is None else v * mult + add
        o = list(r)
        if dest in cols:
            o[cols.index(dest)] = new
        else:
            o.append(new)
        out.append(o)
    lines.append(f"mut|{dest} {src} {mult!r} {add!r}|{enc(cols, rows)}|{enc(out_cols, out)}")

# ---- joins ------------------------------------------------------------------------------------------------------
KIND = {"inner": 0, "left": 1, "right": 2, "full": 3, "semi": 4, "anti": 5}
for trial in range(8):
    nl, nr = int(rng.integers(4, 9)), int(rng.integers(3, 8))
    lc, lr = frame(nl, [("k", "key"), ("a", "num"), ("n", "text")], 0.1)
    rc, rr = frame(nr, [("k", "key"), ("b", "num"), ("n", "text")], 0.1)
    if trial == 3:
        lr[0][0] = None
        rr[0][0] = None
    if trial == 6:
        # two key columns
        lc, lr = frame(nl, [("k", "key"), ("j", "int"), ("a", "num")], 0.0)
        rc, rr = frame(nr, [("k", "key"), ("j", "int"), ("b", "num")], 0.0)
        by_l, by_r = ["k", "j"], ["k", "j"]
    elif trial == 7:
        lc, lr = frame(nl, [("id", "key"), ("a", "num")], 0.1)
        rc, rr = frame(nr, [("code", "key"), ("b", "num"), ("a", "num")], 0.1)
        by_l, by_r = ["id"], ["code"]
    else:
        by_l, by_r = ["k"], ["k"]
    ldf = pd.DataFrame(lr, columns=lc)
    rdf = pd.DataFrame(rr, columns=rc)
    for kind in ("inner", "left", "right", "full"):
        # pandas groups an inner join's rows by key; dplyr keeps the left row order, which is the
        # left join restricted to the matched rows.
        how = {"inner": "left", "full": "outer"}.get(kind, kind)
        if by_l == by_r:
            m = ldf.merge(rdf, how=how, on=by_l, suffixes=(".x", ".y"), indicator=True)
        else:
            m = ldf.merge(rdf, how=how, left_on=by_l, right_on=by_r, suffixes=(".x", ".y"), indicator=True)
        if kind == "inner":
            m = m[m["_merge"] == "both"]
        m = m.drop(columns=["_merge"])
        if by_l != by_r:
            for l, r_ in zip(by_l, by_r):
                m[l] = m[l].where(m[l].notna(), m[r_])
                m = m.drop(columns=[r_])
        out_cols = list(m.columns)
        orows = [[None if pd.isna(v) else v for v in r] for r in m.itertuples(index=False)]
        ordered = 0 if kind == "full" else 1
        lines.append(f"join|{KIND[kind]} {','.join(by_l)} {','.join(by_r)} {ordered}|{enc(lc, lr)}|{enc(rc, rr)}|{enc(out_cols, orows)}")
    # semi / anti: left rows whose key is (not) among the right keys, na matching na.
    def keyof(row, cols, by):
        return tuple((None if (row[cols.index(c)] is None) else row[cols.index(c)]) for c in by)
    rkeys = {keyof(r, rc, by_r) for r in rr}
    for kind in ("semi", "anti"):
        keep = [r for r in lr if (keyof(r, lc, by_l) in rkeys) == (kind == "semi")]
        lines.append(f"join|{KIND[kind]} {','.join(by_l)} {','.join(by_r)} 1|{enc(lc, lr)}|{enc(rc, rr)}|{enc(lc, keep)}")

# ---- pivots -----------------------------------------------------------------------------------------------------
for trial in range(4):
    ids = ["s1", "s2", "s3", "s4"][: 3 + trial % 2]
    metrics = ["h", "w", "a", "b"][: 2 + trial % 3]
    rows = []
    for s in ids:
        for m in metrics:
            if rng.random() < 0.8:
                rows.append([s, float(rng.integers(0, 3)), m, round(float(rng.normal(5, 2)), 3)])
    rng.shuffle(rows)
    cols = ["subject", "visit", "metric", "value"]
    # Make (subject, visit, metric) unique: visit is a function of subject here.
    rows = [[r[0], float(ids.index(r[0])), r[2], r[3]] for r in rows]
    df = pd.DataFrame(rows, columns=cols)
    id_order = list(dict.fromkeys(df.apply(lambda r: (r["subject"], r["visit"]), axis=1)))
    names = list(dict.fromkeys(df["metric"]))
    table = {(r["subject"], r["visit"], r["metric"]): r["value"] for _, r in df.iterrows()}
    out = [[s, v] + [table.get((s, v, n)) for n in names] for s, v in id_order]
    chk = df.pivot_table(index=["subject", "visit"], columns="metric", values="value", aggfunc="first")
    for s, v in id_order:
        for n in names:
            exp = table.get((s, v, n))
            got = chk.loc[(s, v), n] if n in chk.columns else None
            assert (exp is None and pd.isna(got)) or abs(exp - got) < 1e-12
    lines.append(f"wide|subject,visit metric value|{enc(cols, rows)}|{enc(['subject', 'visit'] + names, out)}")
    lines.append(f"wide|~ metric value|{enc(cols, rows)}|{enc(['subject', 'visit'] + names, out)}")

for trial in range(4):
    cols = ["id", "grp", "q1", "q2", "q3"]
    rows = [[float(i), str(rng.choice(["m", "f"])), *[None if rng.random() < 0.25 else round(float(rng.normal()), 3) for _ in range(3)]]
            for i in range(4 + trial)]
    df = pd.DataFrame(rows, columns=cols)
    for drop in (0, 1):
        sels = [(2, "q", "", False)] if trial % 2 == 0 else [(1, "q1", "q3", False)]
        m = df.melt(id_vars=["id", "grp"], value_vars=["q1", "q2", "q3"], var_name="item", value_name="score", ignore_index=False)
        m = m.sort_index(kind="stable")
        if drop:
            m = m[m["score"].notna()]
        out = [[None if pd.isna(v) else v for v in r] for r in m.itertuples(index=False)]
        lines.append(f"long|{sel_text(sels)} item score {drop}|{enc(cols, rows)}|{enc(['id', 'grp', 'item', 'score'], out)}")

# ---- window functions ------------------------------------------------------------------------------------------
WIN = {"row_number": 0, "rank": 1, "dense_rank": 2, "lag": 3, "lead": 4, "cumsum": 5, "cummean": 6, "cummax": 7,
       "cummin": 8, "rollsum": 9, "rollmean": 10, "diff": 11}
for trial in range(6):
    n = 14
    cols = ["g", "t", "x"]
    rows = [[str(rng.choice(["a", "b", "c"])), float(rng.permutation(100)[0]) if False else float(i * 3 + rng.integers(0, 3)),
             None if rng.random() < 0.15 else float(rng.integers(0, 6))] for i in range(n)]
    rng.shuffle(rows)
    # unique t per group keeps the order total (ties would need the stable row order, tested separately).
    for fname in WIN:
        for desc in (0, 1):
            if desc and fname in ("lag", "lead", "diff", "rollsum", "rollmean") and trial % 2:
                continue
            size = 2 if fname in ("lag", "lead", "rollsum", "rollmean") else 0
            df = pd.DataFrame(rows, columns=cols)
            df["_row"] = range(n)
            ordered = df.sort_values(["g", "t"], ascending=[True, not desc], kind="stable")
            res = pd.Series(np.nan, index=df.index, dtype=float)
            for g, grp in ordered.groupby("g", sort=False):
                x = grp["x"]
                if fname == "row_number":
                    out = pd.Series(np.arange(1, len(grp) + 1), index=grp.index, dtype=float)
                elif fname in ("rank", "dense_rank"):
                    out = df.loc[grp.index, "x"].rank(method="min" if fname == "rank" else "dense", ascending=not desc)
                elif fname == "lag":
                    out = x.shift(size)
                elif fname == "lead":
                    out = x.shift(-size)
                elif fname == "diff":
                    out = x.diff()
                elif fname == "cumsum":
                    out = x.cumsum()
                elif fname == "cummax":
                    out = x.cummax()
                elif fname == "cummin":
                    out = x.cummin()
                elif fname == "cummean":
                    out = x.cumsum() / x.notna().cumsum()
                    out[x.isna()] = np.nan
                elif fname == "rollsum":
                    out = x.rolling(size, min_periods=size).sum()
                else:
                    out = x.rolling(size, min_periods=size).mean()
                res.loc[out.index] = out
            if fname in ("rank", "dense_rank"):
                # Rank partitions by group but the order key does not matter: group over the original frame.
                res = pd.Series(np.nan, index=df.index, dtype=float)
                for g, grp in df.groupby("g", sort=False):
                    res.loc[grp.index] = grp["x"].rank(method="min" if fname == "rank" else "dense", ascending=not desc)
            outrows = [r + [None if pd.isna(res.iloc[i]) else float(res.iloc[i])] for i, r in enumerate(rows)]
            lines.append(f"win|{WIN[fname]} x out g t {desc} {size}|{enc(cols, rows)}|{enc(cols + ['out'], outrows)}")
    if trial >= 2:
        break

# ---- missing values --------------------------------------------------------------------------------------------
for trial in range(4):
    cols = ["g", "a", "b", "c"]
    rows = [[str(rng.choice(["u", "v"])), *[None if rng.random() < 0.35 else round(float(rng.normal()), 3) for _ in range(3)]]
            for _ in range(9)]
    df = pd.DataFrame(rows, columns=cols)
    subset = [["a"], ["a", "b"], [], ["c"]][trial]
    keep = df.dropna(subset=subset if subset else None)
    lines.append(f"dropna|{','.join(subset) or '~'}|{enc(cols, rows)}|{enc(cols, [[None if pd.isna(v) else v for v in r] for r in keep.itertuples(index=False)])}")
    rep = df.copy()
    rep["a"] = rep["a"].fillna(-1.5)
    lines.append(f"repna|a -1.5|{enc(cols, rows)}|{enc(cols, [[None if pd.isna(v) else v for v in r] for r in rep.itertuples(index=False)])}")
    for direction, fn in ((0, "ffill"), (1, "bfill")):
        for part in ([], ["g"]):
            work = df.copy()
            targets = ["a", "b"]
            if part:
                for c in targets:
                    work[c] = getattr(work.groupby("g")[c], fn)()
            else:
                for c in targets:
                    work[c] = getattr(work[c], fn)()
            lines.append(f"fill|a,b {','.join(part) or '~'} {direction}|{enc(cols, rows)}|"
                         f"{enc(cols, [[None if pd.isna(v) else v for v in r] for r in work.itertuples(index=False)])}")

HARNESS = r'''
fn parse_frame(a: *mem.Arena, text: str) -> []view.Row {
    var rows: []view.Row = zero
    let (lines0, le) = str.split(text, ";")
    if le != ok { ret rows }
    var lines = lines0
    var names: []str = zero
    var width = 0usize
    var count = 0usize
    let (all, ae) = mem.alloc[view.Row](a, text.len + 1usize)
    if ae != ok { ret rows }
    var first = true
    while true {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        let (cells0, ce) = str.split(line, ",")
        if ce != ok { ret rows }
        var cells = cells0
        if first {
            let (h, he) = mem.alloc[str](a, line.len + 1usize)
            if he != ok { ret rows }
            width = 0usize
            while true {
                let (name, got) = str.split_next(&cells)
                if !got { break }
                h[width] = name
                width += 1usize
            }
            names = h[..width]
            first = false
        } else {
            let (values, ve) = mem.alloc[f.Value](a, width + 1usize)
            if ve != ok { ret rows }
            var i = 0usize
            while i < width {
                let (cell_text, got) = str.split_next(&cells)
                if !got { break }
                var v = f.blank()
                if cell_text.len > 0usize && cell_text[0usize] == 35u8 {
                    let (num, pe) = str.parse_f64(cell_text[1usize..])
                    if pe != ok { os.exit(96i32) }
                    v = f.number(num)
                } else if cell_text.len > 0usize && cell_text[0usize] == 39u8 {
                    v = f.text(cell_text[1usize..])
                }
                values[i] = v
                i += 1usize
            }
            let (fields, fe) = mem.alloc[f.Field](a, width + 1usize)
            if fe != ok { ret rows }
            i = 0usize
            while i < width {
                fields[i] = f.Field { name: names[i], value: values[i] }
                i += 1usize
            }
            all[count] = view.Row{ fields: fields[..width] }
            count += 1usize
        }
    }
    ret all[..count]
}

fn same_value(x: f.Value, y: f.Value) -> bool {
    if x.kind != y.kind { ret false }
    if x.kind == .Number || x.kind == .Date { ret near(x.n, y.n, 0.000000001f64) }
    if x.kind == .Text { ret str.eq(x.s, y.s) }
    ret true
}

fn same_row(x: view.Row, y: view.Row) -> bool {
    if x.fields.len != y.fields.len { ret false }
    var i = 0usize
    while i < x.fields.len {
        if !str.eq(x.fields[i].name, y.fields[i].name) || !same_value(x.fields[i].value, y.fields[i].value) { ret false }
        i += 1usize
    }
    ret true
}

fn same_frame(x: []const view.Row, y: []const view.Row) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if !same_row(x[i], y[i]) { ret false }
        i += 1usize
    }
    ret true
}

// The same rows in any order: every row of x pairs with a distinct equal row of y.
fn same_rows_any_order(a: *mem.Arena, x: []const view.Row, y: []const view.Row) -> bool {
    if x.len != y.len { ret false }
    let (used, e) = mem.alloc[bool](a, y.len + 1usize)
    if e != ok { ret false }
    var j = 0usize
    while j < y.len {
        used[j] = false
        j += 1usize
    }
    var i = 0usize
    while i < x.len {
        var found = false
        j = 0usize
        while j < y.len && !found {
            if !used[j] && same_row(x[i], y[j]) {
                used[j] = true
                found = true
            }
            j += 1usize
        }
        if !found { ret false }
        i += 1usize
    }
    ret true
}

fn words(a: *mem.Arena, text: str, out: []str) -> usize {
    var count = 0usize
    if text.len == 0usize { ret 0usize }
    let (it0, e) = str.split(text, " ")
    if e != ok { ret 0usize }
    var it = it0
    while true {
        let (piece, more) = str.split_next(&it)
        if !more { break }
        if piece.len > 0usize && count < out.len {
            out[count] = piece
            count += 1usize
        }
    }
    ret count
}

fn csv_list(text: str, out: []str) -> usize {
    var count = 0usize
    if text.len == 0usize || str.eq(text, "~") { ret 0usize }
    let (it0, e) = str.split(text, ",")
    if e != ok { ret 0usize }
    var it = it0
    while true {
        let (piece, more) = str.split_next(&it)
        if !more { break }
        if count < out.len {
            out[count] = piece
            count += 1usize
        }
    }
    ret count
}

fn number_of(text: str) -> f64 {
    let (v, e) = str.parse_f64(text)
    if e != ok { os.exit(95i32) }
    ret v
}

fn selectors_of(text: str, out: []tidy.Selector) -> usize {
    var count = 0usize
    let (it0, e) = str.split(text, " ")
    if e != ok { ret 0usize }
    var it = it0
    while true {
        let (term, more) = str.split_next(&it)
        if !more { break }
        if term.len == 0usize || !str.contains(term, ":") { continue }
        let (kind_text, rest, g1) = str.split_once(term, ":")
        let (first, rest2, g2) = str.split_once(rest, ":")
        let (second, neg, g3) = str.split_once(rest2, ":")
        var sel = tidy.Selector{ kind: u8(number_of(kind_text)), first: first, second: second, negate: false }
        if str.eq(neg, "1") { sel.negate = true }
        out[count] = sel
        count += 1usize
    }
    ret count
}

struct_ctx_placeholder
'''.replace("struct_ctx_placeholder", r'''
type Scale = struct { source: str, mult: f64, add: f64 }

fn scale_value(ctx: *Scale, row: view.Row, index: usize) -> f.Value {
    let v = view.value_at(row, ctx.source)
    if v.kind != .Number { ret f.blank() }
    ret f.number(v.n * ctx.mult + ctx.add)
}

fn check(a: *mem.Arena, f_: []str, nf: usize) -> bool {
    let op = f_[0usize]
    var names: [16]str = zero
    var sels: [16]tidy.Selector = zero
    var other: [16]str = zero
    var other2: [16]str = zero
    if str.eq(op, "sel") {
        let n = selectors_of(f_[1usize], sels[..])
        let (got, e) = tidy.select(a, parse_frame(a, f_[2usize]), sels[..n])
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "rel") {
        let n = selectors_of(f_[1usize], sels[..])
        let (got, e) = tidy.relocate(a, parse_frame(a, f_[4usize]), sels[..n], f_[2usize], f_[3usize])
        ret e == ok && same_frame(got, parse_frame(a, f_[5usize]))
    }
    if str.eq(op, "ren") {
        var from: [8]str = zero
        var to: [8]str = zero
        var pairs: [8]str = zero
        let n = words(a, f_[1usize], pairs[..])
        var i = 0usize
        while i < n {
            let (l, r, g) = str.split_once(pairs[i], ">")
            from[i] = l
            to[i] = r
            i += 1usize
        }
        let (got, e) = tidy.rename(a, parse_frame(a, f_[2usize]), from[..n], to[..n])
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "mut") {
        let n = words(a, f_[1usize], other[..])
        var ctx = Scale{ source: other[1usize], mult: number_of(other[2usize]), add: number_of(other[3usize]) }
        let (got, e) = tidy.mutate[Scale](a, parse_frame(a, f_[2usize]), other[0usize], &ctx, scale_value)
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "join") {
        let n = words(a, f_[1usize], other[..])
        let kind = u8(number_of(other[0usize]))
        let nl = csv_list(other[1usize], names[..])
        let nr = csv_list(other[2usize], other2[..])
        let ordered = number_of(other[3usize]) != 0.0f64
        let (got, e) = tidy.join(a, parse_frame(a, f_[2usize]), parse_frame(a, f_[3usize]), names[..nl], other2[..nr], kind, ".x", ".y")
        if e != ok { ret false }
        let want = parse_frame(a, f_[4usize])
        if ordered { ret same_frame(got, want) }
        ret same_rows_any_order(a, got, want)
    }
    if str.eq(op, "wide") {
        let n = words(a, f_[1usize], other[..])
        let nid = csv_list(other[0usize], names[..])
        let (got, e) = tidy.pivot_wider(a, parse_frame(a, f_[2usize]), names[..nid], other[1usize], other[2usize], f.blank())
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "long") {
        let ns = selectors_of(f_[1usize], sels[..])
        let n = words(a, f_[1usize], other[..])
        // The last three words are names_to values_to drop; the selectors are the others.
        let (got, e) = tidy.pivot_longer(a, parse_frame(a, f_[2usize]), sels[..ns], other[n - 3usize], other[n - 2usize], other[n - 1usize][0usize] == 49u8)
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "win") {
        let n = words(a, f_[1usize], other[..])
        var parts: [4]str = zero
        let np = csv_list(other[3usize], parts[..])
        let spec = tidy.Window{ function: u8(number_of(other[0usize])), input: other[1usize], output: other[2usize], partition: parts[..np], order_by: other[4usize], descending: number_of(other[5usize]) != 0.0f64, size: usize(number_of(other[6usize])) }
        let (got, e) = tidy.window(a, parse_frame(a, f_[2usize]), spec)
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "dropna") {
        let nc = csv_list(f_[1usize], names[..])
        let (got, e) = tidy.drop_na(a, parse_frame(a, f_[2usize]), names[..nc])
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "repna") {
        let n = words(a, f_[1usize], other[..])
        let (got, e) = tidy.replace_na(a, parse_frame(a, f_[2usize]), other[0usize], f.number(number_of(other[1usize])))
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    if str.eq(op, "fill") {
        let n = words(a, f_[1usize], other[..])
        let nc = csv_list(other[0usize], names[..])
        let np = csv_list(other[1usize], other2[..])
        let (got, e) = tidy.fill(a, parse_frame(a, f_[2usize]), names[..nc], other2[..np], u8(number_of(other[2usize])))
        ret e == ok && same_frame(got, parse_frame(a, f_[3usize]))
    }
    ret false
}
''')

emit("algo_tidy",
     "// `e.algo.tidy` against pandas (scripts/gen_tidy_test.py): tidy-select select/relocate/rename and mutate, the six joins over\n"
     "// `e.db.query`, pivot_wider and pivot_longer, window functions per partition, and the missing-value verbs.",
     ["use e.algo.formula as f", "use e.algo.tidy as tidy", "use e.algo.view as view"], HARNESS, lines, "algo tidy ok",
     per_chunk=12, arena=True)
