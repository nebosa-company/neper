# arm: logit, invlogit, se.coef of a linear model, binned.resids.
#   args: "logit"/"invlogit" (v); "se" (n, p, x row-major n by p, y) with the coefficient index last; "binned" (nclass, n, x, y, column, bin) weighted by position over the table
suppressMessages(library(arm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262000)
for (v in c(0.01, 0.2, 0.5, 0.77, 0.999)) add("logit", c(v), logit(v))
for (v in c(-12, -3, -0.4, 0, 1.3, 8, 30)) add("invlogit", c(v), invlogit(v))
for (rep in 1:15) {
  n <- sample(20:60, 1); p <- sample(2:4, 1); x <- matrix(round(rnorm(n * p), 4), n, p); x[, 1] <- 1; y <- round(rnorm(n, x %*% rnorm(p)), 4)
  fit <- lm(y ~ x - 1); se <- se.coef(fit)
  for (j in 1:p) add("se", c(n, p, as.vector(t(x)), y, j - 1), se[j])
}
for (rep in 1:25) {
  n <- sample(30:120, 1); nclass <- sample(c(0, 3, 4, 6, 10), 1); if (nclass == 0) nclass <- floor(sqrt(n))
  x <- if (rep %% 2 == 0) round(rnorm(n), 1) else round(rnorm(n), 5); y <- round(rnorm(n), 4)
  bn <- binned.resids(x, y, nclass)$binned
  for (b in seq_len(nrow(bn))) for (cc in 1:6) add("binned", c(nclass, n, x, y, cc - 1, b - 1), bn[b, cc])
  add("binned_rows", c(nclass, n, x, y, 0, 0), nrow(bn))
}
emit("arm", "arm", list(cases))
