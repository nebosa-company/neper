// R tm and tidytext on a document-term count matrix (docs by terms, row-major): weightTfIdf, weightBin, weightSMART (all three letters, with the package's own quirks), removeSparseTerms and tidytext's bind_tf_idf, plus the cosine similarity of documents.
//
// Not here: tokenisation, stemming, stop words, corpora and the term-association functions.

use e.math
use e.mem

fn doc_freq(m: []const f64, nd: usize, nt: usize, df: []f64) {
    var j = 0usize
    while j < nt {
        var c = 0.0f64
        var i = 0usize
        while i < nd {
            if m[i * nt + j] > 0.0f64 { c += 1.0f64 }
            i += 1usize
        }
        df[j] = c
        j += 1usize
    }
}

// weightTfIdf(normalize): term share of the document times log2(D / df)
fn tfidf(a: *mem.Arena, m: []const f64, nd: usize, nt: usize, normalize: bool, out: []f64) -> err {
    let (df, e1) = mem.alloc[f64](a, nt)
    if e1 != ok { ret e1 }
    doc_freq(m, nd, nt, df)
    var i = 0usize
    while i < nd {
        var tot = 1.0f64
        if normalize {
            tot = 0.0f64
            var j = 0usize
            while j < nt {
                tot += m[i * nt + j]
                j += 1usize
            }
        }
        var j = 0usize
        while j < nt {
            var idf = math.log2[f64](f64(nd) / df[j])
            if idf - idf != 0.0f64 { idf = 0.0f64 }
            out[i * nt + j] = m[i * nt + j] / tot * idf
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// tidytext::bind_tf_idf: n / total of the document times the natural log of D / df, zero where the count is zero
fn bind_tf_idf(a: *mem.Arena, m: []const f64, nd: usize, nt: usize, out: []f64) -> err {
    let (df, e1) = mem.alloc[f64](a, nt)
    if e1 != ok { ret e1 }
    doc_freq(m, nd, nt, df)
    var i = 0usize
    while i < nd {
        var tot = 0.0f64
        var j = 0usize
        while j < nt {
            tot += m[i * nt + j]
            j += 1usize
        }
        j = 0usize
        while j < nt {
            out[i * nt + j] = 0.0f64
            if m[i * nt + j] > 0.0f64 { out[i * nt + j] = m[i * nt + j] / tot * math.log[f64](f64(nd) / df[j]) }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// weightSMART: tf 0 n, 1 l, 2 a, 3 b, 4 L; idf 0 n, 1 t, 2 p; norm 0 n, 1 c. The norm is taken from the tf weights before the idf is applied, and idf p is one scalar for all terms (max(0, log2((D - df) / df)) over every term), as in tm.
fn smart(a: *mem.Arena, m: []const f64, nd: usize, nt: usize, tfk: usize, idfk: usize, normk: usize, out: []f64) -> err {
    let (df, e1) = mem.alloc[f64](a, nt)
    let (w, e2) = mem.alloc[f64](a, nd * nt)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    doc_freq(m, nd, nt, df)
    var i = 0usize
    while i < nd {
        var mx = 0.0f64
        var sm = 0.0f64
        var cnt = 0.0f64
        var j = 0usize
        while j < nt {
            let v = m[i * nt + j]
            if v > mx { mx = v }
            if v > 0.0f64 {
                sm += v
                cnt += 1.0f64
            }
            j += 1usize
        }
        j = 0usize
        while j < nt {
            let v = m[i * nt + j]
            var r = 0.0f64
            if v > 0.0f64 {
                if tfk == 0usize { r = v }
                if tfk == 1usize { r = 1.0f64 + math.log2[f64](v) }
                if tfk == 2usize { r = 0.5f64 + 0.5f64 * v / mx }
                if tfk == 3usize { r = 1.0f64 }
                if tfk == 4usize { r = (1.0f64 + math.log2[f64](v)) / (1.0f64 + math.log2[f64](sm / cnt)) }
            }
            w[i * nt + j] = r
            j += 1usize
        }
        i += 1usize
    }
    var pmax = 0.0f64
    var j = 0usize
    while j < nt {
        let l = math.log2[f64]((f64(nd) - df[j]) / df[j])
        if l > pmax { pmax = l }
        j += 1usize
    }
    i = 0usize
    while i < nd {
        var nrm = 1.0f64
        if normk == 1usize {
            var s = 0.0f64
            j = 0usize
            while j < nt {
                s += w[i * nt + j] * w[i * nt + j]
                j += 1usize
            }
            nrm = math.sqrt[f64](s)
        }
        j = 0usize
        while j < nt {
            var idf = 1.0f64
            if idfk == 1usize {
                idf = math.log2[f64](f64(nd) / df[j])
                if idf - idf != 0.0f64 { idf = 0.0f64 }
            }
            if idfk == 2usize { idf = pmax }
            out[i * nt + j] = w[i * nt + j] * idf / nrm
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// removeSparseTerms(sparse): the number of terms kept, those with df > D (1 - sparse); keep receives 1 for kept terms
fn sparse_terms(a: *mem.Arena, m: []const f64, nd: usize, nt: usize, sparse: f64, keep: []f64) -> usize {
    let (df, e1) = mem.alloc[f64](a, nt)
    if e1 != ok { ret 0usize }
    doc_freq(m, nd, nt, df)
    var kept = 0usize
    var j = 0usize
    while j < nt {
        keep[j] = 0.0f64
        if df[j] > f64(nd) * (1.0f64 - sparse) {
            keep[j] = 1.0f64
            kept += 1usize
        }
        j += 1usize
    }
    ret kept
}

// cosine similarity of every pair of documents into out (nd by nd)
fn cosine(m: []const f64, nd: usize, nt: usize, out: []f64) {
    var i = 0usize
    while i < nd {
        var k = 0usize
        while k < nd {
            var dot = 0.0f64
            var ni = 0.0f64
            var nk = 0.0f64
            var j = 0usize
            while j < nt {
                dot += m[i * nt + j] * m[k * nt + j]
                ni += m[i * nt + j] * m[i * nt + j]
                nk += m[k * nt + j] * m[k * nt + j]
                j += 1usize
            }
            out[i * nd + k] = dot / math.sqrt[f64](ni * nk)
            k += 1usize
        }
        i += 1usize
    }
}

// findFreqTerms(dtm, lower, upper): the 0-based indices of the terms whose total count lies in [lower, upper]; returns the count
fn find_freq_terms(m: []const f64, nd: usize, nt: usize, lower: f64, upper: f64, out: []usize) -> usize {
    var cnt = 0usize
    var j = 0usize
    while j < nt {
        var s = 0.0f64
        var i = 0usize
        while i < nd {
            s += m[i * nt + j]
            i += 1usize
        }
        if s >= lower && s <= upper {
            out[cnt] = j
            cnt += 1usize
        }
        j += 1usize
    }
    ret cnt
}

// findAssocs(dtm, term, corlimit): the other terms whose correlation with the term is at least corlimit, correlations rounded to two digits, in decreasing order (equal values in term order);
// idx and val receive the 0-based term indices and the rounded correlations; returns the count
fn find_assocs(a: *mem.Arena, m: []const f64, nd: usize, nt: usize, term: usize, corlimit: f64, idx: []usize, val: []f64) -> usize {
    let (cs, e) = mem.alloc[f64](a, nt)
    if e != ok { ret 0usize }
    let nn = f64(nd)
    var mt = 0.0f64
    var i = 0usize
    while i < nd {
        mt += m[i * nt + term]
        i += 1usize
    }
    mt = mt / nn
    var st = 0.0f64
    i = 0usize
    while i < nd {
        st += (m[i * nt + term] - mt) * (m[i * nt + term] - mt)
        i += 1usize
    }
    var cnt = 0usize
    var j = 0usize
    while j < nt {
        if j != term {
            var mj = 0.0f64
            i = 0usize
            while i < nd {
                mj += m[i * nt + j]
                i += 1usize
            }
            mj = mj / nn
            var sj = 0.0f64
            var sxy = 0.0f64
            i = 0usize
            while i < nd {
                sj += (m[i * nt + j] - mj) * (m[i * nt + j] - mj)
                sxy += (m[i * nt + term] - mt) * (m[i * nt + j] - mj)
                i += 1usize
            }
            var r = sxy / math.sqrt[f64](st * sj)
            if r != r { r = 0.0f64 }
            cs[j] = math.floor[f64](r * 100.0f64 + 0.5f64) / 100.0f64
            if r >= corlimit {
                idx[cnt] = j
                val[cnt] = cs[j]
                cnt += 1usize
            }
        }
        j += 1usize
    }
    // insertion sort, decreasing, stable
    i = 1usize
    while i < cnt {
        let kv = val[i]
        let ki = idx[i]
        var q = i
        while q > 0usize && val[q - 1usize] < kv {
            val[q] = val[q - 1usize]
            idx[q] = idx[q - 1usize]
            q -= 1usize
        }
        val[q] = kv
        idx[q] = ki
        i += 1usize
    }
    ret cnt
}
