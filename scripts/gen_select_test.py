"""Vectors for tests/selfhost/fixtures/link/ml_select (L063: k-fold, pipeline, search).

Oracle: scikit-learn KFold, StratifiedKFold, SimpleImputer / StandardScaler /
MinMaxScaler pipelines and GridSearchCV(Pipeline([StandardScaler, Ridge]),
scoring neg_mean_squared_error). Run from the repo root.
"""
import sys
import warnings
from pathlib import Path

import numpy as np
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold, StratifiedKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import MinMaxScaler, StandardScaler

sys.path.insert(0, str(Path(__file__).parent))
from fixture_vectors import emit

warnings.filterwarnings("ignore")
rng = np.random.default_rng(631)
lines = []


def num(v):
    return "nan" if v != v else repr(float(v))


def flat(a):
    return " ".join(num(v) for v in np.asarray(a, float).flatten())


# KFold.
for n, k in [(10, 3), (11, 5), (17, 4), (20, 5), (7, 7)]:
    fold = np.zeros(n, int)
    for f, (_, test) in enumerate(KFold(k).split(np.zeros(n))):
        fold[test] = f
    lines.append(f"kf|{n} {k}||{flat(fold)}")

# StratifiedKFold.
for n, classes, k, weights in [(30, 3, 3, [0.5, 0.3, 0.2]), (41, 2, 5, [0.7, 0.3]), (53, 4, 4, [0.4, 0.3, 0.2, 0.1]),
                               (25, 3, 5, [0.34, 0.33, 0.33])]:
    labels = rng.choice(classes, n, p=weights)
    for c in range(classes):
        if (labels == c).sum() < k:
            labels[np.where(labels != c)[0][: k]] = c
    fold = np.zeros(n, int)
    for f, (_, test) in enumerate(StratifiedKFold(k).split(np.zeros(n), labels)):
        fold[test] = f
    lines.append(f"skf|{n} {classes} {k}|{flat(labels)}|{flat(fold)}")

# Pipelines: step codes IMPUTE_MEAN 0, MEDIAN 1, CONSTANT 2:c, STANDARDIZE 3, MIN_MAX 4.
def build(spec):
    steps = []
    for tok in spec.split():
        code, _, const = tok.partition(":")
        code = int(code)
        if code == 0:
            steps.append(SimpleImputer(strategy="mean"))
        elif code == 1:
            steps.append(SimpleImputer(strategy="median"))
        elif code == 2:
            steps.append(SimpleImputer(strategy="constant", fill_value=float(const)))
        elif code == 3:
            steps.append(StandardScaler())
        else:
            steps.append(MinMaxScaler())
    return Pipeline([(f"s{i}", s) for i, s in enumerate(steps)])


for n, d, spec in [(40, 3, "0 3"), (35, 4, "1 4"), (30, 2, "2:-1.5 3"), (28, 3, "3"), (33, 4, "4"), (45, 3, "1 3 4")]:
    x = rng.normal(5, 3, (n, d))
    x[:, 0] = np.round(x[:, 0])
    if d > 2:
        x[:, 2] = 7.0                       # a constant column
    mask = rng.random((n, d)) < 0.12
    if "3" in spec.split() and "0" not in spec.split() and "1" not in spec.split() and "2" not in spec:
        mask[:] = False
    x = np.where(mask, np.nan, x)
    perm = rng.permutation(n)
    train, test = perm[: int(n * 0.7)], perm[int(n * 0.7):]
    pipe = build(spec).fit(x[train])
    out = pipe.transform(x[test])
    lines.append(f"pipe|{n} {d}|{spec}|{flat(x)}|{flat(train)}|{flat(test)}|{flat(out)}")

# Grid search of Ridge over a standardized pipeline, with KFold.
for n, d, k, alphas in [(40, 3, 4, [0.01, 0.1, 1.0, 10.0, 100.0]), (60, 5, 5, [0.5, 5.0, 50.0]), (33, 2, 3, [1e-3, 1.0])]:
    x = rng.normal(0, 1, (n, d)) * rng.uniform(0.5, 4, d)
    y = x @ rng.normal(0, 1, d) + 2.0 + rng.normal(0, 1.0, n)
    pipe = Pipeline([("scale", StandardScaler()), ("ridge", Ridge(alpha=1.0))])
    gs = GridSearchCV(pipe, {"ridge__alpha": alphas}, cv=KFold(k), scoring="neg_mean_squared_error").fit(x, y)
    lines.append(f"grid|{n} {d} {k}|{flat(x)}|{flat(y)}|{flat(alphas)}|{flat(gs.cv_results_['mean_test_score'])}|{gs.best_index_}")

HARNESS = r'''
type Task = struct { x: []const f64, y: []const f64, n: usize, d: usize, alphas: []const f64, steps: []const select.Step, params: []f64, work: []f64, train_x: []f64, test_x: []f64, train_y: []f64, coef: []f64, ridge_scratch: []f64 }

fn score_ridge(t: *Task, alpha: f64, train: []const usize, test: []const usize) -> f64 {
    let d = t.d
    if select.pipeline_fit(t.steps, t.x, t.n, d, train, t.params, t.work) != ok { ret 0.0f64 - 1.0e300f64 }
    if select.pipeline_transform(t.steps, t.params, t.x, d, train, t.train_x) != ok { ret 0.0f64 - 1.0e300f64 }
    if select.pipeline_transform(t.steps, t.params, t.x, d, test, t.test_x) != ok { ret 0.0f64 - 1.0e300f64 }
    var i = 0usize
    while i < train.len {
        t.train_y[i] = t.y[train[i]]
        i += 1usize
    }
    if linear.ridge(t.train_x[..train.len * d], t.train_y[..train.len], train.len, d, alpha, t.coef, t.ridge_scratch) != ok { ret 0.0f64 - 1.0e300f64 }
    var sse = 0.0f64
    i = 0usize
    while i < test.len {
        let r = t.y[test[i]] - linear.predict(t.test_x, d, i, t.coef)
        sse += r * r
        i += 1usize
    }
    ret 0.0f64 - sse / f64(test.len)
}

fn eval_point(t: *Task, point: usize, train: []const usize, test: []const usize) -> f64 {
    ret score_ridge(t, t.alphas[point], train, test)
}

fn eval_params(t: *Task, candidate: []const f64, train: []const usize, test: []const usize) -> f64 {
    ret score_ridge(t, candidate[0usize], train, test)
}

fn labels_of(text: str, out: []usize) -> usize {
    var tmp: [128]f64 = zero
    let n = nums(text, tmp[..])
    var i = 0usize
    while i < n {
        out[i] = usize(tmp[i])
        i += 1usize
    }
    ret n
}

fn parse_steps(text: str, out: []select.Step) -> usize {
    var count = 0usize
    let (it0, e) = str.split(text, " ")
    if e != ok { ret 0usize }
    var it = it0
    while true {
        let (tok, more) = str.split_next(&it)
        if !more { break }
        if tok.len == 0usize { continue }
        let (code, rest, got) = str.split_once(tok, ":")
        let (c, pe) = str.parse_f64(code)
        var constant = 0.0f64
        if got {
            let (cv, ce) = str.parse_f64(rest)
            constant = cv
        }
        out[count] = select.Step{ kind: u8(c), constant: constant }
        count += 1usize
    }
    ret count
}

fn check(a: *mem.Arena, f: []str, nf: usize) -> bool {
    var head: [8]f64 = zero
    load(f[1usize], head[..])
    let op = f[0usize]
    if str.eq(op, "kf") {
        let n = usize(head[0usize])
        let k = usize(head[1usize])
        var fold: [64]usize = zero
        var want: [64]usize = zero
        if select.kfold_assign(n, k, fold[..]) != ok { ret false }
        let nw = labels_of(f[3usize], want[..])
        var i = 0usize
        while i < n {
            if fold[i] != want[i] { ret false }
            i += 1usize
        }
        // The shuffled variant keeps the sizes and covers every row once.
        var r = rand.pcg64(77u64, 3u64)
        var order: [64]usize = zero
        var shuffled: [64]usize = zero
        if select.kfold_shuffled(&r, n, k, shuffled[..], order[..]) != ok { ret false }
        var counts: [16]usize = zero
        var want_counts: [16]usize = zero
        i = 0usize
        while i < n {
            counts[shuffled[i]] += 1usize
            want_counts[want[i]] += 1usize
            i += 1usize
        }
        i = 0usize
        while i < k {
            if counts[i] != want_counts[i] { ret false }
            i += 1usize
        }
        ret nw == n
    }
    if str.eq(op, "skf") {
        let n = usize(head[0usize])
        let classes = usize(head[1usize])
        let k = usize(head[2usize])
        var labels: [128]usize = zero
        var want: [128]usize = zero
        var fold: [128]usize = zero
        var scratch: [64]usize = zero
        let nl = labels_of(f[2usize], labels[..])
        let nw = labels_of(f[3usize], want[..])
        if select.stratified_assign(labels[..nl], n, classes, k, fold[..], scratch[..]) != ok { ret false }
        var i = 0usize
        while i < n {
            if fold[i] != want[i] { ret false }
            i += 1usize
        }
        ret nl == n && nw == n
    }
    if str.eq(op, "pipe") {
        let n = usize(head[0usize])
        let d = usize(head[1usize])
        var steps: [8]select.Step = zero
        let ns = parse_steps(f[2usize], steps[..])
        var x: [400]f64 = zero
        var train_f: [64]f64 = zero
        var test_f: [64]f64 = zero
        var want: [400]f64 = zero
        let nx = nums(f[3usize], x[..])
        let ntr = nums(f[4usize], train_f[..])
        let nte = nums(f[5usize], test_f[..])
        let nw = nums(f[6usize], want[..])
        var train: [64]usize = zero
        var test: [64]usize = zero
        var i = 0usize
        while i < ntr {
            train[i] = usize(train_f[i])
            i += 1usize
        }
        i = 0usize
        while i < nte {
            test[i] = usize(test_f[i])
            i += 1usize
        }
        var params: [64]f64 = zero
        var work: [500]f64 = zero
        var out: [400]f64 = zero
        if select.pipeline_fit(steps[..ns], x[..nx], n, d, train[..ntr], params[..], work[..]) != ok { ret false }
        if select.pipeline_transform(steps[..ns], params[..], x[..nx], d, test[..nte], out[..]) != ok { ret false }
        if nw != nte * d { ret false }
        i = 0usize
        while i < nw {
            if !near(out[i], want[i], 0.000000001f64) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(op, "grid") {
        let n = usize(head[0usize])
        let d = usize(head[1usize])
        let k = usize(head[2usize])
        let (x, xe) = mem.alloc[f64](a, n * d)
        let (y, ye) = mem.alloc[f64](a, n)
        let (alphas, ae) = mem.alloc[f64](a, 8usize)
        let (want, we) = mem.alloc[f64](a, 8usize)
        let (best_text, be) = mem.alloc[f64](a, 2usize)
        if xe != ok || ye != ok || ae != ok || we != ok || be != ok { ret false }
        let nx = nums(f[2usize], x)
        let ny = nums(f[3usize], y)
        let na = nums(f[4usize], alphas)
        let nw = nums(f[5usize], want)
        let nb = nums(f[6usize], best_text)
        if nx != n * d || ny != n || na != nw || nb != 1usize { ret false }
        let (params, pe) = mem.alloc[f64](a, 2usize * d)
        let (work, wke) = mem.alloc[f64](a, n * d + n)
        let (train_x, txe) = mem.alloc[f64](a, n * d)
        let (test_x, tse) = mem.alloc[f64](a, n * d)
        let (train_y, tye) = mem.alloc[f64](a, n)
        let (coef, ce) = mem.alloc[f64](a, d + 1usize)
        let (rs, rse) = mem.alloc[f64](a, (d + 1usize) * (d + 1usize))
        let (fold_of, fe) = mem.alloc[usize](a, n)
        let (train_rows, tre) = mem.alloc[usize](a, n)
        let (test_rows, tee) = mem.alloc[usize](a, n)
        let (means, me) = mem.alloc[f64](a, 8usize)
        if pe != ok || wke != ok || txe != ok || tse != ok || tye != ok || ce != ok || rse != ok || fe != ok || tre != ok || tee != ok || me != ok { ret false }
        var steps: [1]select.Step = zero
        steps[0usize] = select.Step{ kind: select.STANDARDIZE, constant: 0.0f64 }
        var task = Task{ x: x, y: y, n: n, d: d, alphas: alphas[..na], steps: steps[..], params: params, work: work, train_x: train_x, test_x: test_x, train_y: train_y, coef: coef, ridge_scratch: rs }
        if select.kfold_assign(n, k, fold_of) != ok { ret false }
        let (best, e) = select.grid_search[Task](&task, na, n, k, fold_of, train_rows, test_rows, eval_point, means)
        if e != ok || best != usize(best_text[0usize]) { ret false }
        var i = 0usize
        while i < na {
            if !near(means[i], want[i], 0.000000001f64) { ret false }
            i += 1usize
        }
        // Random search over a log-scaled alpha: the best draw reproduces its own score.
        var ranges: [1]select.ParamRange = zero
        ranges[0usize] = select.ParamRange{ low: 0.001f64, high: 100.0f64, log_scale: true, integer: false }
        var r = rand.pcg64(9u64, 1u64)
        var candidate: [1]f64 = zero
        var chosen: [1]f64 = zero
        let (best_score, se) = select.random_search[Task](&task, &r, ranges[..], 6usize, n, k, fold_of, train_rows, test_rows, eval_params, candidate[..], chosen[..], means)
        if se != ok || chosen[0usize] < 0.001f64 || chosen[0usize] > 100.0f64 { ret false }
        var again = 0.0f64
        var fold = 0usize
        let (nr0, nt0) = select.split_fold(fold_of, n, 0usize, train_rows, test_rows)
        while fold < k {
            let (nr, nt) = select.split_fold(fold_of, n, fold, train_rows, test_rows)
            again += eval_params(&task, chosen[..], train_rows[..nr], test_rows[..nt])
            fold += 1usize
        }
        ret near(again / f64(k), best_score, 0.000000001f64)
    }
    ret false
}
'''

emit("ml_select",
     "// `e.ml.select` against scikit-learn (scripts/gen_select_test.py): KFold and StratifiedKFold assignment, imputer / scaler\n"
     "// pipelines fitted on a training fold, and a grid search of Ridge over a standardized pipeline with the same mean CV scores as\n"
     "// GridSearchCV; random search is checked for range and self-consistency.",
     ["use e.algo.rand as rand", "use e.ml.linear as linear", "use e.ml.select as select"], HARNESS, lines, "ml select ok",
     per_chunk=6, arena=True)
