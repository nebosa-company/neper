// R klaR: NaiveBayes with Gaussian class-conditional densities (usekernel = FALSE) and its predict: priors are the class frequencies, each
// variable has a per-class mean and (n - 1) standard deviation, a density of exactly 0 is replaced by threshold, and the posterior is the
// normalised exp of log prior plus the summed log densities.
//
// Not here: kernel densities, factor and logical predictors, the Laplace smoothing fL, rda, woe, stepclass, greedy.wilks and the plots.

use e.math
use e.math.dist as dist
use e.mem

// x is n by p row-major, labels 1..k; mean and sd are k by p, prior k
fn nb_fit(x: []const f64, n: usize, p: usize, labels: []const usize, k: usize, prior: []f64, mean: []f64, sd: []f64) {
    var cnt: [16]f64 = zero
    var j = 0usize
    while j < k {
        cnt[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < k * p {
        mean[j] = 0.0f64
        sd[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[labels[i] - 1usize] += 1.0f64
        var c = 0usize
        while c < p {
            mean[(labels[i] - 1usize) * p + c] += x[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < k {
        prior[j] = cnt[j] / f64(n)
        var c = 0usize
        while c < p {
            mean[j * p + c] = mean[j * p + c] / cnt[j]
            c += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            let d = x[i * p + c] - mean[(labels[i] - 1usize) * p + c]
            sd[(labels[i] - 1usize) * p + c] += d * d
            c += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < k {
        var c = 0usize
        while c < p {
            sd[j * p + c] = math.sqrt[f64](sd[j * p + c] / (cnt[j] - 1.0f64))
            c += 1usize
        }
        j += 1usize
    }
}

// the posterior of one observation (p values) over the k classes into post, and the predicted class (1-based)
fn nb_predict(row: []const f64, p: usize, k: usize, prior: []const f64, mean: []const f64, sd: []const f64, threshold: f64, post: []f64) -> usize {
    var best = 0usize
    var j = 0usize
    while j < k {
        var l = math.log[f64](prior[j])
        var c = 0usize
        while c < p {
            var d = dist.dnorm(row[c], mean[j * p + c], sd[j * p + c], false)
            if d == 0.0f64 { d = threshold }
            l += math.log[f64](d)
            c += 1usize
        }
        post[j] = l
        if j == 0usize || l > post[best] { best = j }
        j += 1usize
    }
    var tot = 0.0f64
    j = 0usize
    while j < k {
        post[j] = math.exp[f64](post[j])
        tot += post[j]
        j += 1usize
    }
    j = 0usize
    while j < k {
        post[j] = post[j] / tot
        j += 1usize
    }
    ret best + 1usize
}
