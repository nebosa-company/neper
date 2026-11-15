# lbeta, d and p of the beta distribution, d and p of the binomial. args: (family, kind, x, p1, p2, lower, log)
#   family 0 beta(a, b), kind 0 d 1 p; 1 binom(n, p); 2 lbeta(p1, p2) (x ignored)
cases <- list()
# densities go through exp of a sum of large terms, so they agree to about 1e-11; a log value near 0 only to an absolute 1e-15
add <- function(args, want) cases[[length(cases) + 1]] <<- case("nmath_beta", args, want, rel = if (args[2] == 0) 1e-11 else 1e-13, abs = if (args[7] == 1) 1e-15 else 1e-300)
shapes <- c(0.001, 0.05, 0.3, 0.9, 1, 1.5, 2, 3.7, 8, 15, 40, 100, 400, 1e4, 1e6)
xs <- c(0, 1e-300, 1e-12, 1e-5, 0.01, 0.1, 0.29, 0.3, 0.5, 0.7, 0.9, 0.999, 1 - 1e-9, 1)
for (a in shapes) for (b in c(0.01, 0.5, 1, 2.5, 9, 30, 120, 1e3, 1e5)) {
  add(c(2, 0, 0, a, b, 1, 0), lbeta(a, b))
  for (x in xs) for (lg in c(FALSE, TRUE)) {
    add(c(0, 0, x, a, b, 1, lg), suppressWarnings(dbeta(x, a, b, log = lg)))
    for (lt in c(TRUE, FALSE)) add(c(0, 1, x, a, b, lt, lg), suppressWarnings(pbeta(x, a, b, lower.tail = lt, log.p = lg)))
  }
}
for (n in c(0, 1, 2, 5, 10, 30, 100, 1000, 1e5)) for (p in c(0, 1e-8, 0.01, 0.3, 0.5, 0.77, 0.999, 1)) {
  for (x in unique(c(-1, 0, 1, 2, 3, floor(n * p), floor(n / 2), n - 1, n, n + 1, 2.5))) for (lg in c(FALSE, TRUE)) {
    add(c(1, 0, x, n, p, 1, lg), suppressWarnings(dbinom(x, n, p, log = lg)))
    for (lt in c(TRUE, FALSE)) add(c(1, 1, x, n, p, lt, lg), suppressWarnings(pbinom(x, n, p, lower.tail = lt, log.p = lg)))
  }
}
# t (family 3) and F (family 4): args (family, kind, x, df1, df2, lower, log)
for (df in c(0.1, 0.5, 1, 2, 3, 7.5, 30, 100, 1e4, 1e8, Inf)) for (x in c(-1e200, -1e10, -50, -5, -2, -0.5, -1e-5, 0, 1e-5, 0.3, 1, 2.5, 8, 40, 1e3, 1e10, 1e200, Inf)) for (lg in c(FALSE, TRUE)) {
  add(c(3, 0, x, df, 0, 1, lg), suppressWarnings(dt(x, df, log = lg)))
  for (lt in c(TRUE, FALSE)) add(c(3, 1, x, df, 0, lt, lg), suppressWarnings(pt(x, df, lower.tail = lt, log.p = lg)))
}
for (d1 in c(0.5, 1, 2, 3, 10, 100, 1e4, 1e8, Inf)) for (d2 in c(0.5, 1, 2, 5, 40, 300, 1e5, 1e9, Inf)) for (x in c(0, 1e-5, 0.1, 0.5, 1, 1.7, 5, 30, 400, 1e6, Inf)) for (lg in c(FALSE, TRUE)) {
  add(c(4, 0, x, d1, d2, 1, lg), suppressWarnings(df(x, d1, d2, log = lg)))
  for (lt in c(TRUE, FALSE)) add(c(4, 1, x, d1, d2, lt, lg), suppressWarnings(pf(x, d1, d2, lower.tail = lt, log.p = lg)))
}
# geometric (5), negative binomial by prob (6) and by mu (7); quantiles of binomial (8) and t (9); kind 2 is q
ps <- c(0, 1e-300, 1e-10, 0.001, 0.05, 0.3, 0.5, 0.8, 0.99, 1 - 1e-9, 1)
lps <- c(-Inf, -1000, -100, -20, -3, -0.7, -0.1, -1e-6, 0)
qkind <- function(lt, lg) if (lg) lps else ps
for (pr in c(0.001, 0.05, 0.3, 0.5, 0.9, 1)) {
  for (x in c(-1, 0, 1, 2, 5, 20, 100, 1e4, 1e8, Inf, 2.5)) for (lg in c(FALSE, TRUE)) {
    add(c(5, 0, x, pr, 0, 1, lg), suppressWarnings(dgeom(x, pr, log = lg)))
    for (lt in c(TRUE, FALSE)) add(c(5, 1, x, pr, 0, lt, lg), suppressWarnings(pgeom(x, pr, lower.tail = lt, log.p = lg)))
  }
  for (lt in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) for (p in qkind(lt, lg)) add(c(5, 2, p, pr, 0, lt, lg), suppressWarnings(qgeom(p, pr, lower.tail = lt, log.p = lg)))
}
for (size in c(0, 0.01, 0.5, 1, 3.3, 20, 500, 1e6)) {
  for (pr in c(0.001, 0.1, 0.5, 0.9, 1)) {
    for (x in c(-1, 0, 1, 2, 7, 30, 200, 3000, 1e5, Inf, 1.5)) for (lg in c(FALSE, TRUE)) {
      add(c(6, 0, x, size, pr, 1, lg), suppressWarnings(dnbinom(x, size, prob = pr, log = lg)))
      for (lt in c(TRUE, FALSE)) add(c(6, 1, x, size, pr, lt, lg), suppressWarnings(pnbinom(x, size, prob = pr, lower.tail = lt, log.p = lg)))
    }
    for (lt in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) for (p in qkind(lt, lg)) add(c(6, 2, p, size, pr, lt, lg), suppressWarnings(qnbinom(p, size, prob = pr, lower.tail = lt, log.p = lg)))
  }
  for (mu in c(0, 0.3, 4, 100, 1e4)) for (x in c(-1, 0, 1, 2, 7, 30, 200, 3000, 1e5, Inf, 1.5)) for (lg in c(FALSE, TRUE)) {
    add(c(7, 0, x, size, mu, 1, lg), suppressWarnings(dnbinom(x, size, mu = mu, log = lg)))
    for (lt in c(TRUE, FALSE)) add(c(7, 1, x, size, mu, lt, lg), suppressWarnings(pnbinom(x, size, mu = mu, lower.tail = lt, log.p = lg)))
  }
}
for (n in c(0, 1, 5, 30, 100, 1000, 1e5, 1e7)) for (pr in c(0, 0.001, 0.2, 0.5, 0.73, 1)) for (lt in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) for (p in qkind(lt, lg))
  add(c(8, 2, p, n, pr, lt, lg), suppressWarnings(qbinom(p, n, pr, lower.tail = lt, log.p = lg)))
for (df in c(0.05, 0.5, 0.99, 1, 1.0000000000001, 1.5, 2, 2.05, 3, 7.5, 30, 1000, 1e10, Inf)) for (lt in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) for (p in qkind(lt, lg))
  add(c(9, 2, p, df, 0, lt, lg), suppressWarnings(qt(p, df, lower.tail = lt, log.p = lg)))
emit("nmath_beta", character(), list(cases))
