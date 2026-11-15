# qgamma, qchisq and qpois with lower.tail and log.p (same args layout as nmath.R, kind 2).
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("nmath", args, want, rel = 1e-13, abs = 1e-300)
ps <- c(0, 1e-300, 1e-100, 1e-20, 1e-10, 1e-5, 0.001, 0.05, 0.25, 0.5, 0.75, 0.95, 0.999, 1 - 1e-8, 1)
lps <- c(-Inf, -1000, -100, -30, -10, -2, -0.7, -0.1, -1e-5, -1e-20, 0)
for (lt in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) for (p in if (lg) lps else ps) {
  for (a in c(1e-12, 0.001, 0.05, 0.3, 0.9, 1, 1.5, 2.5, 5, 10, 50, 100, 1000, 1e5)) for (sc in c(1, 2.5))
    add(c(0, 2, p, a, sc, lt, lg), suppressWarnings(qgamma(p, a, scale = sc, lower.tail = lt, log.p = lg)))
  for (df in c(0.1, 0.5, 1, 2, 3, 7, 30, 100, 1000)) add(c(1, 2, p, df, 0, lt, lg), suppressWarnings(qchisq(p, df, lower.tail = lt, log.p = lg)))
  for (lam in c(0, 0.01, 0.5, 1, 3.3, 10, 25, 100, 1000, 1e5, 1e7)) add(c(2, 2, p, lam, 0, lt, lg), suppressWarnings(qpois(p, lam, lower.tail = lt, log.p = lg)))
}
emit("nmath_q", character(), list(cases))
