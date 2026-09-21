// `e.algo.stat.test` against SciPy on two samples of ten: the one- and
// two-sample t-tests, Welch, Mann-Whitney and Wilcoxon (asymptotic with
// continuity correction), a chi-squared goodness of fit, Fisher's exact test,
// the two-sample Kolmogorov-Smirnov test, one-way ANOVA and Kruskal-Wallis
// over three groups, a permutation test that agrees with the t-test's
// verdict, and the Bonferroni and Benjamini-Hochberg corrections. Each check
// exits with its own code.

use e.algo.rand
use e.algo.stat.test
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [10]f64 = zero
    x[0usize] = 5.1f64
    x[1usize] = 4.9f64
    x[2usize] = 6.2f64
    x[3usize] = 5.8f64
    x[4usize] = 6.0f64
    x[5usize] = 5.5f64
    x[6usize] = 4.7f64
    x[7usize] = 5.3f64
    x[8usize] = 6.1f64
    x[9usize] = 5.6f64
    var y: [10]f64 = zero
    y[0usize] = 6.0f64
    y[1usize] = 6.4f64
    y[2usize] = 5.9f64
    y[3usize] = 7.1f64
    y[4usize] = 6.8f64
    y[5usize] = 6.3f64
    y[6usize] = 5.7f64
    y[7usize] = 6.6f64
    y[8usize] = 7.0f64
    y[9usize] = 6.2f64
    var scratch: [64]f64 = zero
    var order: [32]usize = zero
    let eps = 0.0000001f64

    // 1: t-tests.
    let (t1, t1_error) = test.t_test(x[..], 5.0f64)
    if t1_error != ok || !near(t1.statistic, 3.1869936011372073f64, eps) || !near(t1.p_value, 0.011059836858321407f64, eps) { os.exit(1i32) }
    let (t2, t2_error) = test.t_test_two(x[..], y[..])
    if t2_error != ok || !near(t2.statistic, 0.0f64 - 3.981760050884627f64, eps) || !near(t2.p_value, 0.0008746515578548229f64, eps) { os.exit(1i32) }
    let (w, w_error) = test.welch(x[..], y[..])
    if w_error != ok || !near(w.statistic, 0.0f64 - 3.981760050884627f64, eps) || !near(w.p_value, 0.0008867331325759855f64, eps) { os.exit(1i32) }
    var flat: [3]f64 = zero
    flat[0usize] = 2.0f64
    flat[1usize] = 2.0f64
    flat[2usize] = 2.0f64
    let (_, flat_error) = test.t_test(flat[..], 1.0f64)
    if flat_error != test.Invalid { os.exit(1i32) }
    let (_, short_error) = test.t_test(x[..1usize], 1.0f64)
    if short_error != test.Invalid { os.exit(1i32) }

    // 2: rank tests.
    let (mw, mw_error) = test.mann_whitney(x[..], y[..], scratch[..], order[..])
    if mw_error != ok || mw.statistic != 10.0f64 || !near(mw.p_value, 0.0028065622375925453f64, eps) { os.exit(2i32) }
    let (wil, wil_error) = test.wilcoxon(x[..], y[..], scratch[..], order[..])
    if wil_error != ok || wil.statistic != 1.0f64 || !near(wil.p_value, 0.007922775920579304f64, eps) { os.exit(2i32) }
    let (same, same_error) = test.wilcoxon(x[..], x[..], scratch[..], order[..])
    if same_error != ok || same.p_value != 1.0f64 { os.exit(2i32) }
    let (_, mw_room) = test.mann_whitney(x[..], y[..], scratch[..30usize], order[..])
    if mw_room != test.TooSmall { os.exit(2i32) }
    // Ranks with ties average: 3, 1, 3, 3, 5 rank as 3, 1, 3, 3, 5 and the tie term is 3^3 - 3.
    var tied: [5]f64 = zero
    tied[0usize] = 3.0f64
    tied[1usize] = 1.0f64
    tied[2usize] = 3.0f64
    tied[3usize] = 3.0f64
    tied[4usize] = 5.0f64
    let (ties, rank_error) = test.ranks(tied[..], scratch[..], order[..])
    if rank_error != ok || ties != 24.0f64 || scratch[0usize] != 3.0f64 || scratch[1usize] != 1.0f64 || scratch[4usize] != 5.0f64 { os.exit(2i32) }

    // 3: chi-squared and Fisher.
    var observed: [3]f64 = zero
    observed[0usize] = 30.0f64
    observed[1usize] = 20.0f64
    observed[2usize] = 50.0f64
    var expected: [3]f64 = zero
    expected[0usize] = 33.3333333f64
    expected[1usize] = 33.3333333f64
    expected[2usize] = 33.3333334f64
    let (chi, chi_error) = test.chi_squared(observed[..], expected[..])
    if chi_error != ok || !near(chi.statistic, 13.999999889f64, 0.000001f64) || !near(chi.p_value, 0.0009118820161639679f64, eps) { os.exit(3i32) }
    expected[1usize] = 0.0f64
    let (_, chi_invalid) = test.chi_squared(observed[..], expected[..])
    if chi_invalid != test.Invalid { os.exit(3i32) }
    let fisher = test.fisher_exact(8u64, 2u64, 1u64, 5u64)
    if fisher.statistic != 20.0f64 || !near(fisher.p_value, 0.034965034965034975f64, eps) { os.exit(3i32) }
    let balanced = test.fisher_exact(5u64, 5u64, 5u64, 5u64)
    if balanced.statistic != 1.0f64 || !near(balanced.p_value, 1.0f64, eps) { os.exit(3i32) }

    // 4: Kolmogorov-Smirnov (sorts its inputs), ANOVA and Kruskal-Wallis.
    var xs: [10]f64 = zero
    var ys: [10]f64 = zero
    mem.copy[f64](xs[..], x[..])
    mem.copy[f64](ys[..], y[..])
    let (ks, ks_error) = test.kolmogorov_smirnov(xs[..], ys[..])
    // D = 0.6 as SciPy; the p-value is the Numerical Recipes asymptotic form with its
    // small-sample correction (0.0310), a shade above SciPy's exact 0.0301.
    if ks_error != ok || !near(ks.statistic, 0.6f64, eps) || !near(ks.p_value, 0.031046781145641363f64, 0.000001f64) { os.exit(4i32) }
    var groups: [25]f64 = zero
    mem.copy[f64](groups[..10usize], x[..])
    mem.copy[f64](groups[10usize..20usize], y[..])
    groups[20usize] = 5.5f64
    groups[21usize] = 5.9f64
    groups[22usize] = 6.1f64
    groups[23usize] = 5.2f64
    groups[24usize] = 5.8f64
    var sizes: [3]usize = zero
    sizes[0usize] = 10usize
    sizes[1usize] = 10usize
    sizes[2usize] = 5usize
    let (f, f_error) = test.anova(groups[..], sizes[..])
    if f_error != ok || !near(f.statistic, 9.306862745098046f64, eps) || !near(f.p_value, 0.0011782796286390516f64, eps) { os.exit(4i32) }
    let (kw, kw_error) = test.kruskal_wallis(groups[..], sizes[..], scratch[..], order[..])
    if kw_error != ok || !near(kw.statistic, 11.047956823438723f64, eps) || !near(kw.p_value, 0.003989942689492f64, eps) { os.exit(4i32) }
    let (_, anova_room) = test.anova(groups[..20usize], sizes[..])
    if anova_room != test.TooSmall { os.exit(4i32) }

    // 5: the permutation test agrees with the t-test's verdict.
    var r = rand.pcg64(7u64, 11u64)
    let (perm, perm_error) = test.permutation(&r, x[..], y[..], 4000u32, scratch[..])
    if perm_error != ok || !near(perm.statistic, 0.0f64 - 0.88f64, 0.000000001f64) || perm.p_value > 0.01f64 { os.exit(5i32) }
    let (perm_same, perm_same_error) = test.permutation(&r, x[..], x[..], 500u32, scratch[..])
    if perm_same_error != ok || perm_same.p_value < 0.9f64 { os.exit(5i32) }

    // 6: multiple-comparison corrections.
    var p: [5]f64 = zero
    p[0usize] = 0.01f64
    p[1usize] = 0.04f64
    p[2usize] = 0.03f64
    p[3usize] = 0.2f64
    p[4usize] = 0.5f64
    if test.benjamini_hochberg(p[..], order[..]) != ok { os.exit(6i32) }
    if !near(p[0usize], 0.05f64, eps) || !near(p[1usize], 0.06666666666666667f64, eps) || !near(p[2usize], 0.06666666666666667f64, eps) || !near(p[3usize], 0.25f64, eps) || !near(p[4usize], 0.5f64, eps) { os.exit(6i32) }
    p[0usize] = 0.01f64
    p[1usize] = 0.04f64
    p[2usize] = 0.03f64
    p[3usize] = 0.2f64
    p[4usize] = 0.5f64
    test.bonferroni(p[..])
    if !near(p[0usize], 0.05f64, eps) || !near(p[1usize], 0.2f64, eps) || !near(p[2usize], 0.15f64, eps) || p[3usize] != 1.0f64 || p[4usize] != 1.0f64 { os.exit(6i32) }
    if test.benjamini_hochberg(p[..], order[..3usize]) != test.TooSmall { os.exit(6i32) }

    try io.print("algo stat test ok\n")
    ret ok
}
