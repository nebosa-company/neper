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
emit("nmath_beta", character(), list(cases))
