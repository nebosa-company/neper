// R QCA minimize(): the models of a crisp truth table as canonical text, to be compared with R's solutions exactly. A model is a set of prime implicants, a prime is one
// character per condition (1 present, 0 negated, - minimized), the primes of a model are sorted bytewise and joined by "+", the models sorted and joined by ";".
// The complex solution takes the outcome-1 configurations alone, the parsimonious one the unobserved configurations as don't cares, and the intermediate solution
// adds only the easy counterfactuals of the directional expectations (the unobserved configurations a parsimonious model covers that a complex term, within its
// parsimonious superset and less the literals the expectations contradict, matches).
//
// Not here: multi-value conditions, the contradictory "C" and the "0" inclusions, conjunctural expectations, pi.cons and sol.cons, all.sol and row dominance.

use e.algo.logic as lg
use e.mem

// a text under construction in a fixed buffer; bytes past the end are dropped
type Text = struct { b: []u8, len: usize }

fn put(t: *Text, c: u8) {
    if t.len < t.b.len {
        t.b[t.len] = c
        t.len += 1usize
    }
}

fn cmp_bytes(x: []const u8, y: []const u8) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        if x[at] != y[at] {
            if x[at] < y[at] { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

// one prime as n characters, the first condition first: 1 present, 0 negated, - minimized
fn prime_row(p: lg.Implicant, n: usize, row: []u8) {
    var j = 0usize
    while j < n {
        let bit = 1u32 << u32(n - 1usize - j)
        if (p.care & bit) == 0u32 {
            row[j] = 45u8
        } else if (p.value & bit) != 0u32 {
            row[j] = 49u8
        } else {
            row[j] = 48u8
        }
        j += 1usize
    }
}

// the terms of one model, sorted bytewise and joined by "+" (at most 64 terms, n <= 16)
fn model_text(t: *Text, terms: []const lg.Implicant, n: usize) {
    var rows: [1024]u8 = zero
    var idx: [64]usize = zero
    var i = 0usize
    while i < terms.len {
        prime_row(terms[i], n, rows[i * n..i * n + n])
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < terms.len {
        var j = i
        while j > 0usize && cmp_bytes(rows[idx[j] * n..idx[j] * n + n], rows[idx[j - 1usize] * n..idx[j - 1usize] * n + n]) < 0i32 {
            let s = idx[j]
            idx[j] = idx[j - 1usize]
            idx[j - 1usize] = s
            j -= 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < terms.len {
        if i > 0usize { put(t, 43u8) }
        var k = 0usize
        while k < n {
            put(t, rows[idx[i] * n + k])
            k += 1usize
        }
        i += 1usize
    }
}

// the prime implicants of the minterms (with the don't cares), those covering a minterm (kept), and every minimum-size cover of the minterms by the kept ones (masks over them)
type Mset = struct { primes: []lg.Implicant, kept: []usize, nk: usize, models: []u64, nm: usize }

fn build_mset(a: *mem.Arena, n: usize, on: []const u32, dc: []const u32) -> (Mset, err) {
    var m: Mset = zero
    let cap = 3usize * (1usize << n) + 64usize
    let (primes, e1) = mem.alloc[lg.Implicant](a, cap)
    if e1 != ok { ret (m, e1) }
    let (work, e2) = mem.alloc[lg.Implicant](a, cap)
    if e2 != ok { ret (m, e2) }
    let (merged, e3) = mem.alloc[u8](a, cap)
    if e3 != ok { ret (m, e3) }
    let (np, e4) = lg.prime_implicants(n, on, dc, primes, work, merged)
    if e4 != ok { ret (m, e4) }
    let (kept, e5) = mem.alloc[usize](a, np + 1usize)
    if e5 != ok { ret (m, e5) }
    var nk = 0usize
    var i = 0usize
    while i < np {
        var any = false
        var q = 0usize
        while q < on.len {
            if lg.covers(primes[i], on[q]) { any = true }
            q += 1usize
        }
        if any {
            kept[nk] = i
            nk += 1usize
        }
        i += 1usize
    }
    if nk > 64usize || on.len > 64usize { ret (m, lg.TooSmall) }
    let (cov, e6) = mem.alloc[u64](a, nk + 1usize)
    if e6 != ok { ret (m, e6) }
    let (models, e7) = mem.alloc[u64](a, 4096usize)
    if e7 != ok { ret (m, e7) }
    i = 0usize
    while i < nk {
        var bits = 0u64
        var q = 0usize
        while q < on.len {
            if lg.covers(primes[kept[i]], on[q]) { bits = bits | (1u64 << u64(q)) }
            q += 1usize
        }
        cov[i] = bits
        i += 1usize
    }
    var full = 0u64
    i = 0usize
    while i < on.len {
        full = full | (1u64 << u64(i))
        i += 1usize
    }
    var nm = 0usize
    var k = 1usize
    while k <= nk && nm == 0usize {
        var covat: [66]u64 = zero
        var maskat: [66]u64 = zero
        var cand: [66]usize = zero
        var d = 0usize
        var live = true
        while live {
            var back = false
            if covat[d] == full {
                if d == k {
                    var seen = false
                    var s = 0usize
                    while s < nm {
                        if models[s] == maskat[d] { seen = true }
                        s += 1usize
                    }
                    if !seen {
                        if nm >= models.len { ret (m, lg.TooSmall) }
                        models[nm] = maskat[d]
                        nm += 1usize
                    }
                }
                back = true
            } else if d >= k {
                back = true
            } else {
                var b = 0u64
                while ((full - (covat[d] & full)) >> b) & 1u64 == 0u64 { b += 1u64 }
                var j = cand[d]
                var found = false
                while j < nk && !found {
                    if (cov[j] >> b) & 1u64 == 1u64 {
                        found = true
                    } else {
                        j += 1usize
                    }
                }
                if found {
                    cand[d] = j + 1usize
                    covat[d + 1usize] = covat[d] | cov[j]
                    maskat[d + 1usize] = maskat[d] | (1u64 << u64(j))
                    cand[d + 1usize] = 0usize
                    d += 1usize
                } else {
                    back = true
                }
            }
            if back {
                if d == 0usize {
                    live = false
                } else {
                    d -= 1usize
                }
            }
        }
        k += 1usize
    }
    m.primes = primes
    m.kept = kept
    m.nk = nk
    m.models = models
    m.nm = nm
    ret (m, ok)
}

// the terms of model `mask` of the set
fn mset_terms(m: *const Mset, mask: u64, out: []lg.Implicant) -> usize {
    var c = 0usize
    var i = 0usize
    while i < m.nk {
        if ((mask >> u64(i)) & 1u64) == 1u64 {
            out[c] = m.primes[m.kept[i]]
            c += 1usize
        }
        i += 1usize
    }
    ret c
}

// texts[0 .. cnt) of the buffer at starts/lens, sorted bytewise and joined by sep into out
fn join_sorted(buf: []const u8, starts: []usize, lens: []usize, cnt: usize, out: *Text, sep: u8) {
    var i = 1usize
    while i < cnt {
        var j = i
        while j > 0usize && cmp_bytes(buf[starts[j]..starts[j] + lens[j]], buf[starts[j - 1usize]..starts[j - 1usize] + lens[j - 1usize]]) < 0i32 {
            let s = starts[j]
            starts[j] = starts[j - 1usize]
            starts[j - 1usize] = s
            let l = lens[j]
            lens[j] = lens[j - 1usize]
            lens[j - 1usize] = l
            j -= 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < cnt {
        if i > 0usize { put(out, sep) }
        var k = 0usize
        while k < lens[i] {
            put(out, buf[starts[i] + k])
            k += 1usize
        }
        i += 1usize
    }
}

// every model of the set, sorted and joined by ";"
fn models_joined(a: *mem.Arena, m: *const Mset, n: usize, out: *Text) -> err {
    let (eb, e1) = mem.alloc[u8](a, 65536usize)
    if e1 != ok { ret e1 }
    let (st, e2) = mem.alloc[usize](a, m.nm + 1usize)
    if e2 != ok { ret e2 }
    let (ln, e3) = mem.alloc[usize](a, m.nm + 1usize)
    if e3 != ok { ret e3 }
    var t: Text = zero
    t.b = eb
    var terms: [64]lg.Implicant = zero
    var i = 0usize
    while i < m.nm {
        st[i] = t.len
        let c = mset_terms(m, m.models[i], terms[0usize..64usize])
        model_text(&t, terms[0usize..c], n)
        ln[i] = t.len - st[i]
        i += 1usize
    }
    join_sorted(eb, st, ln, m.nm, out, 59u8)
    ret ok
}

// the unobserved configurations a parsimonious model covers that the expectations let a complex term reach: the term must lie inside a term of the model, and
// loses the literals the expectations contradict (de per condition 0 none, 1 absent, 2 present); a remainder it still matches is an easy counterfactual
fn easy_counterfactuals(n: usize, cterms: []const lg.Implicant, pterms: []const lg.Implicant, is_on: []const u8, de: []const u8, ec: []u32) -> usize {
    let rows = usize(1u64 << u64(n))
    var nec = 0usize
    var m = 0usize
    while m < rows {
        var sa = false
        var q = 0usize
        while q < pterms.len {
            if lg.covers(pterms[q], u32(m)) { sa = true }
            q += 1usize
        }
        var hit = false
        if sa && is_on[m] == 0u8 {
            var x = 0usize
            while x < cterms.len && !hit {
                var y = 0usize
                while y < pterms.len && !hit {
                    let xt = cterms[x]
                    let yt = pterms[y]
                    if (yt.care & xt.care) == yt.care && (xt.value & yt.care) == yt.value {
                        var rc = xt.care
                        var j = 0usize
                        while j < n {
                            let bit = 1u32 << u32(n - 1usize - j)
                            if (xt.care & bit) != 0u32 && (yt.care & bit) == 0u32 && de[j] != 0u8 {
                                var lit = 1u8
                                if (xt.value & bit) == 0u32 { lit = 0u8 }
                                var want = 0u8
                                if de[j] == 2u8 { want = 1u8 }
                                if lit != want { rc = rc - bit }
                            }
                            j += 1usize
                        }
                        if (u32(m) & rc) == (xt.value & rc) { hit = true }
                    }
                    y += 1usize
                }
                x += 1usize
            }
        }
        if hit {
            ec[nec] = u32(m)
            nec += 1usize
        }
        m += 1usize
    }
    ret nec
}

// the intermediate solutions: one "complex|parsimonious|models" entry per pair of a complex and a parsimonious model, the entries sorted and joined by "#"
fn intermediate_text(a: *mem.Arena, n: usize, on: []const u32, dc: []const u32, de: []const u8, out: *Text) -> err {
    var empty: [1]u32 = zero
    let (cs, e1) = build_mset(a, n, on, empty[0usize..0usize])
    if e1 != ok { ret e1 }
    let (ps, e2) = build_mset(a, n, on, dc)
    if e2 != ok { ret e2 }
    let rows = usize(1u64 << u64(n))
    let (is_on, e3) = mem.alloc[u8](a, rows)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < rows {
        is_on[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < on.len {
        is_on[usize(on[i])] = 1u8
        i += 1usize
    }
    let (ebuf, e4) = mem.alloc[u8](a, 262144usize)
    if e4 != ok { ret e4 }
    let (st, e5) = mem.alloc[usize](a, cs.nm * ps.nm + 1usize)
    if e5 != ok { ret e5 }
    let (ln, e6) = mem.alloc[usize](a, cs.nm * ps.nm + 1usize)
    if e6 != ok { ret e6 }
    var et: Text = zero
    et.b = ebuf
    var entries = 0usize
    var ci = 0usize
    while ci < cs.nm {
        var cterms: [64]lg.Implicant = zero
        let nc = mset_terms(&cs, cs.models[ci], cterms[0usize..64usize])
        var pi = 0usize
        while pi < ps.nm {
            let mark = mem.mark(a)
            var pterms: [64]lg.Implicant = zero
            let np = mset_terms(&ps, ps.models[pi], pterms[0usize..64usize])
            let (ec, e7) = mem.alloc[u32](a, rows + 1usize)
            if e7 != ok { ret e7 }
            let nec = easy_counterfactuals(n, cterms[0usize..nc], pterms[0usize..np], is_on, de, ec)
            let (is, e8) = build_mset(a, n, on, ec[0usize..nec])
            if e8 != ok { ret e8 }
            let (mb, e9) = mem.alloc[u8](a, 65536usize)
            if e9 != ok { ret e9 }
            var mt: Text = zero
            mt.b = mb
            let e10 = models_joined(a, &is, n, &mt)
            if e10 != ok { ret e10 }
            st[entries] = et.len
            model_text(&et, cterms[0usize..nc], n)
            put(&et, 124u8)
            model_text(&et, pterms[0usize..np], n)
            put(&et, 124u8)
            var q = 0usize
            while q < mt.len {
                put(&et, mb[q])
                q += 1usize
            }
            ln[entries] = et.len - st[entries]
            entries += 1usize
            mem.reset(a, mark)
            pi += 1usize
        }
        ci += 1usize
    }
    join_sorted(ebuf, st, ln, entries, out, 35u8)
    ret ok
}

// minimize() of a truth table whose outcome-1 configurations are `on` and whose included remainders are `dc`, as text: kind 0 the complex models (dc ignored), 1 the
// parsimonious models, 2 the intermediate solutions for the expectations `de`, 3 and 4 the rows of the prime implicant chart of the complex and the parsimonious call
fn minimize_text(a: *mem.Arena, kind: usize, n: usize, on: []const u32, dc: []const u32, de: []const u8) -> (str, err) {
    var empty: [1]u32 = zero
    let (obuf, e0) = mem.alloc[u8](a, 262144usize)
    if e0 != ok { ret ("", e0) }
    var out: Text = zero
    out.b = obuf
    if kind == 2usize {
        let e1 = intermediate_text(a, n, on, dc, de, &out)
        if e1 != ok { ret ("", e1) }
        ret (obuf[0usize..out.len], ok)
    }
    var d = dc
    if kind == 0usize || kind == 3usize { d = empty[0usize..0usize] }
    let (ms, e2) = build_mset(a, n, on, d)
    if e2 != ok { ret ("", e2) }
    if kind >= 3usize {
        var terms: [64]lg.Implicant = zero
        var all = 0u64
        var i = 0usize
        while i < ms.nk {
            all = all | (1u64 << u64(i))
            i += 1usize
        }
        let c = mset_terms(&ms, all, terms[0usize..64usize])
        model_text(&out, terms[0usize..c], n)
        ret (obuf[0usize..out.len], ok)
    }
    let e3 = models_joined(a, &ms, n, &out)
    if e3 != ok { ret ("", e3) }
    ret (obuf[0usize..out.len], ok)
}
