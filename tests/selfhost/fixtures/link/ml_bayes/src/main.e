// `e.ml.bayes` on three blobs and on word counts: the Gaussian fit matches
// scikit-learn means, variances and priors and predicts the blobs (and the
// centre by the widest class), the multinomial fit matches its smoothed log
// probabilities and priors and predicts four documents, and the argument
// checks answer. Each check exits with its own code.

use e.io
use e.mem
use e.ml.bayes
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [48]f64 = zero
    var base: [16]f64 = zero
    base[2usize] = 1.0f64
    base[5usize] = 1.0f64
    base[6usize] = 1.0f64
    base[7usize] = 1.0f64
    base[8usize] = 0.5f64
    base[9usize] = 0.5f64
    base[10usize] = 0.2f64
    base[11usize] = 0.8f64
    base[12usize] = 0.8f64
    base[13usize] = 0.2f64
    base[14usize] = 0.5f64
    base[15usize] = 0.1f64
    var i = 0usize
    while i < 8usize {
        x[2usize * i] = base[2usize * i]
        x[2usize * i + 1usize] = base[2usize * i + 1usize]
        x[16usize + 2usize * i] = base[2usize * i] + 10.0f64
        x[16usize + 2usize * i + 1usize] = base[2usize * i + 1usize]
        x[32usize + 2usize * i] = base[2usize * i]
        x[32usize + 2usize * i + 1usize] = base[2usize * i + 1usize] + 10.0f64
        i += 1usize
    }
    var labels: [24]usize = zero
    i = 0usize
    while i < 24usize {
        labels[i] = i / 8usize
        i += 1usize
    }

    var means: [6]f64 = zero
    var variances: [6]f64 = zero
    var priors: [3]f64 = zero
    var counts: [3]usize = zero

    // 1: the Gaussian form.
    if bayes.gaussian_fit(x[..], labels[..], 24usize, 2usize, 3usize, means[..], variances[..], priors[..], counts[..]) != ok { os.exit(1i32) }
    if !near(means[0usize], 0.5f64, 0.0000001f64) || !near(means[1usize], 0.45f64, 0.0000001f64) || !near(variances[0usize], 0.1475f64, 0.0000001f64) || !near(variances[1usize], 0.165f64, 0.0000001f64) { os.exit(1i32) }
    if !near(priors[2usize], 1.0f64 / 3.0f64, 0.0000001f64) || !near(means[5usize], 10.45f64, 0.0000001f64) { os.exit(1i32) }
    var query: [2]f64 = zero
    query[0usize] = 0.4f64
    query[1usize] = 0.4f64
    if bayes.gaussian_predict(query[..], 2usize, 3usize, means[..], variances[..], priors[..]) != 0usize { os.exit(1i32) }
    query[0usize] = 9.0f64
    query[1usize] = 1.0f64
    if bayes.gaussian_predict(query[..], 2usize, 3usize, means[..], variances[..], priors[..]) != 1usize { os.exit(1i32) }
    query[0usize] = 3.0f64
    query[1usize] = 7.0f64
    if bayes.gaussian_predict(query[..], 2usize, 3usize, means[..], variances[..], priors[..]) != 2usize { os.exit(1i32) }
    query[0usize] = 5.0f64
    query[1usize] = 5.0f64
    if bayes.gaussian_predict(query[..], 2usize, 3usize, means[..], variances[..], priors[..]) != 0usize { os.exit(1i32) }
    let posterior = bayes.gaussian_log_posterior(query[..], 2usize, 0usize, means[..], variances[..], priors[..]) - bayes.gaussian_log_posterior(query[..], 2usize, 2usize, means[..], variances[..], priors[..])
    if !near(posterior, 27.2727273f64, 0.000001f64) { os.exit(1i32) }
    labels[0usize] = 5usize
    if bayes.gaussian_fit(x[..], labels[..], 24usize, 2usize, 3usize, means[..], variances[..], priors[..], counts[..]) != bayes.Invalid { os.exit(1i32) }
    labels[0usize] = 0usize
    if bayes.gaussian_fit(x[..], labels[..], 24usize, 2usize, 3usize, means[..], variances[..], priors[..], counts[..2usize]) != bayes.TooSmall { os.exit(1i32) }

    // 2: the multinomial form over word counts.
    var docs: [15]f64 = zero
    docs[0usize] = 3.0f64
    docs[2usize] = 1.0f64
    docs[3usize] = 2.0f64
    docs[4usize] = 1.0f64
    docs[7usize] = 3.0f64
    docs[8usize] = 1.0f64
    docs[9usize] = 1.0f64
    docs[10usize] = 2.0f64
    docs[11usize] = 2.0f64
    docs[14usize] = 4.0f64
    var kinds: [5]usize = zero
    kinds[2usize] = 1usize
    kinds[3usize] = 1usize
    kinds[4usize] = 1usize
    var log_probability: [6]f64 = zero
    var log_prior: [2]f64 = zero
    if bayes.multinomial_fit(docs[..], kinds[..], 5usize, 3usize, 2usize, 1.0f64, log_probability[..], log_prior[..], counts[..]) != ok { os.exit(2i32) }
    if !near(log_probability[0usize], 0.0f64 - 0.51082562f64, 0.0000001f64) || !near(log_probability[1usize], 0.0f64 - 1.60943791f64, 0.0000001f64) || !near(log_probability[3usize], 0.0f64 - 2.07944154f64, 0.0000001f64) || !near(log_probability[5usize], 0.0f64 - 0.69314718f64, 0.0000001f64) { os.exit(2i32) }
    if !near(log_prior[0usize], 0.0f64 - 0.91629073f64, 0.0000001f64) || !near(log_prior[1usize], 0.0f64 - 0.51082562f64, 0.0000001f64) { os.exit(2i32) }
    var doc: [3]f64 = zero
    doc[0usize] = 2.0f64
    if bayes.multinomial_predict(doc[..], 3usize, 2usize, log_probability[..], log_prior[..]) != 0usize { os.exit(2i32) }
    doc[0usize] = 0.0f64
    doc[1usize] = 2.0f64
    if bayes.multinomial_predict(doc[..], 3usize, 2usize, log_probability[..], log_prior[..]) != 1usize { os.exit(2i32) }
    doc[0usize] = 1.0f64
    doc[1usize] = 1.0f64
    doc[2usize] = 1.0f64
    if bayes.multinomial_predict(doc[..], 3usize, 2usize, log_probability[..], log_prior[..]) != 1usize { os.exit(2i32) }
    doc[0usize] = 0.0f64
    doc[1usize] = 0.0f64
    if bayes.multinomial_predict(doc[..], 3usize, 2usize, log_probability[..], log_prior[..]) != 1usize { os.exit(2i32) }
    if bayes.multinomial_fit(docs[..], kinds[..], 5usize, 3usize, 2usize, 0.0f64 - 1.0f64, log_probability[..], log_prior[..], counts[..]) != bayes.Invalid { os.exit(2i32) }

    try io.print("ml bayes ok\n")
    ret ok
}
