# Hmisc: binconf (three methods), wtd.mean, wtd.var, somers2.
#   binconf: (x, n, alpha, method 0 exact 1 wilson 2 asymptotic)  fn "bc_lo" "bc_hi"
#   wtd: (n, x..., w...)  fn "wmean" "wvar"        somers2: (n, x..., y...)  fn "c" "dxy"
suppressMessages(library(Hmisc))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
mth <- c("exact", "wilson", "asymptotic")
for (n in c(5, 20, 100, 1000)) for (x in unique(c(0, 1, 2, n %/% 3, n %/% 2, n - 2, n - 1, n))) for (al in c(0.05, 0.01, 0.2)) for (m in 0:2) {
  b <- binconf(x, n, alpha = al, method = mth[m + 1])
  add("bc_lo", c(x, n, al, m), b[2]); add("bc_hi", c(x, n, al, m), b[3])
}
set.seed(20261115)
for (rep in 1:10) {
  n <- sample(8:40, 1); x <- round(rnorm(n), 3); w <- round(runif(n, 0.5, 3), 2)
  add("wmean", c(n, x, w), wtd.mean(x, w)); add("wvar", c(n, x, w), wtd.var(x, w))
  y <- rbinom(n, 1, 0.5); xs <- round(x + y * 0.8, 1)
  if (length(unique(y)) == 2) { s <- somers2(xs, y); add("c", c(n, xs, y), s[["C"]]); add("dxy", c(n, xs, y), s[["Dxy"]]) }
}
# wtd.quantile "wq" (n, k, index, x[n], w[n], probs[k]); wtd.rank "wrk" (n, index, x, w); rcspline.eval "rcs" (n, nk, norm, column-major index, x[n], knots[nk])
for (rep in 1:30) {
  n <- sample(6:40, 1); x <- if (rep %% 2 == 0) round(rnorm(n), 1) else rnorm(n); w <- round(runif(n, 0.5, 3), 2); pr <- sort(runif(sample(2:5, 1)))
  q <- wtd.quantile(x, w, probs = pr); for (j in seq_along(pr)) add("wq", c(n, length(pr), j - 1, x, w, pr), q[[j]])
  r <- wtd.rank(x, w); for (i in seq_len(n)) add("wrk", c(n, i - 1, x, w), r[i])
  nk <- sample(3:6, 1); kn <- sort(sample(x, nk)); if (length(unique(kn)) < nk) next; nm <- sample(0:2, 1)
  B <- rcspline.eval(x, knots = kn, norm = nm); for (j in seq_along(as.vector(B))) add("rcs", c(n, nk, nm, j - 1, x, kn), as.vector(B)[j])
}
# hdquantile "hdq" (n, p, x[n]); rcorr "rc" (n, spearman, index 0 r 1 P, x[n], y[n])
for (rep in 1:40) {
  n <- sample(5:40, 1); x <- rnorm(n); y <- 0.4 * x + rnorm(n); if (rep %% 2 == 0) { x <- round(x, 1); y <- round(y, 1) }
  for (p in c(0.1, 0.5, 0.87)) add("hdq", c(n, p, x), hdquantile(x, p)[[1]])
  for (sp in 0:1) { r <- rcorr(x, y, type = c("pearson", "spearman")[sp + 1]); add("rc", c(n, sp, 0, x, y), r$r[1, 2]); add("rc", c(n, sp, 1, x, y), r$P[1, 2]) }
}
emit("hmisc", "Hmisc", list(cases))
