# The gamma function and its logarithm, and d and p of gamma, chi-squared and Poisson with lower.tail and log.p.
#   args: (family, kind 0 d 1 p, x, p1, p2, lower, log)  family 0 gamma(shape, scale) 1 chisq(df) 2 pois(lambda) 3 gamma() 4 lgamma()
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("nmath", args, want, rel = 1e-13, abs = 1e-300)
xs <- c(-Inf, -30.5, -10.5, -3.2, -2.5, -1.5, -0.5, -1e-8, 1e-300, 1e-100, 1e-20, 1e-8, 0.001, 0.1, 0.5, 0.9, 1, 1.5, 2, 3, 4.5, 5, 7.5, 10, 12.3, 20, 30, 50, 80, 100, 150, 170, 171.5, 200, 500, 1e3, 1e4, 1e5, 1e7, 1e17, 1e20, Inf)
for (x in c(xs, 0, -1, -2, 15, 23.5, 27, 40.5)) {
  add(c(3, 0, x, 0, 0, 1, 0), suppressWarnings(gamma(x)))
  add(c(4, 0, x, 0, 0, 1, 0), suppressWarnings(lgamma(x)))
}
shapes <- c(0.001, 0.05, 0.3, 0.9, 1, 1.5, 2.5, 5, 10, 50, 100, 1000, 1e4, 1e6)
pts <- c(0, 1e-10, 1e-3, 0.1, 0.5, 0.9, 1, 1.2, 2, 3, 5, 8, 10, 20, 40, 80, 100, 500, 1100, 1e4, 1e6, 1e7, Inf)
for (a in shapes) for (s in c(1, 2.5)) for (x in pts) {
  for (lg in c(FALSE, TRUE)) {
    add(c(0, 0, x, a, s, 1, lg), suppressWarnings(dgamma(x, a, scale = s, log = lg)))
    for (lt in c(TRUE, FALSE)) add(c(0, 1, x, a, s, lt, lg), suppressWarnings(pgamma(x, a, scale = s, lower.tail = lt, log.p = lg)))
  }
}
for (df in c(0.5, 1, 2, 3, 7, 30, 100, 1000)) for (x in pts) for (lg in c(FALSE, TRUE)) {
  add(c(1, 0, x, df, 0, 1, lg), suppressWarnings(dchisq(x, df, log = lg)))
  for (lt in c(TRUE, FALSE)) add(c(1, 1, x, df, 0, lt, lg), suppressWarnings(pchisq(x, df, lower.tail = lt, log.p = lg)))
}
for (lam in c(0, 0.01, 0.5, 1, 3.3, 10, 25, 100, 1000, 1e5)) for (x in c(-1, 0, 1, 2, 3, 5, 8, 10, 12, 20, 30, 50, 100, 150, 400, 1000, 1100, 1e5, 1e5 + 700, Inf, 2.5)) for (lg in c(FALSE, TRUE)) {
  add(c(2, 0, x, lam, 0, 1, lg), suppressWarnings(dpois(x, lam, log = lg)))
  for (lt in c(TRUE, FALSE)) add(c(2, 1, x, lam, 0, lt, lg), suppressWarnings(ppois(x, lam, lower.tail = lt, log.p = lg)))
}
emit("nmath", character(), list(cases))
