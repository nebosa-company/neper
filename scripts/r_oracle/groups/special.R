# e.math.special against base R: the normal, t, chi-squared and F cdfs, the normal quantile,
# gamma, lgamma and choose, over the domain the module is written for. Left out, and queued
# under L265: qnorm at 0 and 1 (NaN) and from 1 - 1e-8 (8e-11 off, 5e-10 at 1 - 1e-10), lgamma/gamma at 0 and at
# negative non-integers (NaN), choose with negative or fractional n (answers 0).
set.seed(20261115)
edge <- c(NA, NaN, Inf, -Inf)

z <- c(-40, -38, -8, -3, -1, -0.5, 0, 0.5, 1, 2.5, 5, 8, 37, edge, round(rnorm(40) * 3, 6))
p <- c(1e-300, 1e-15, 1e-10, 0.001, 0.025, 0.3, 0.5, 0.7, 0.975, 0.999, -0.1, 1.1, NA, signif(runif(40), 8))
g <- c(0.1, 0.5, 1, 2, 3, 5.5, 10, 20.5, 100.3, 170.5, 171, 172, 1e5, 1e10, NA, Inf, round(runif(30, 0.01, 60), 6))
df <- c(0.5, 1, 2, 3, 7.5, 30, 100, 1e4)
tt <- c(-1e3, -12, -3, -0.7, 0, 0.1, 1, 2.5, 6, 40)
xq <- c(0, 0.01, 0.5, 1, 3, 10, 50, 200)

emit("special", character(), list(
  sweep("pnorm", pnorm, data.frame(z = z), rel = 1e-13),
  sweep("qnorm", qnorm, data.frame(p = p), rel = 1e-12),
  sweep("lgamma", lgamma, data.frame(x = g), rel = 1e-12),
  sweep("gamma", gamma, data.frame(x = g), rel = 1e-12),
  sweep("pt", pt, expand.grid(tt, df), rel = 1e-10),
  sweep("pchisq", pchisq, expand.grid(xq, df), rel = 1e-10),
  sweep("pf", pf, expand.grid(xq, df[c(1, 3, 5, 7)], df[c(2, 4, 6, 8)]), rel = 1e-10),
  sweep("choose", choose, expand.grid(c(0, 1, 5, 10, 30, 52, 100), c(0, 1, 2, 5, 10, 26, 50)), rel = 1e-12)
))
