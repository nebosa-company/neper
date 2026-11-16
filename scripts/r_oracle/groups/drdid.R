# drdid: reg_did_panel's ATT and standard error.
#   args: (part 0 ATT or 1 se, n, p, y1 - y0 (n), D (n), covariates row-major n by p...)
suppressMessages(library(DRDID))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-11)
set.seed(20262007)
for (rep in 1:25) {
  n <- sample(80:300, 1); p <- sample(1:3, 1)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1)); D <- rbinom(n, 1, plogis(0.3 * X[, p]))
  y0 <- round(rnorm(n, X %*% rep(1, p)), 4); y1 <- round(y0 + 0.5 + 0.3 * X[, p] + 0.8 * D + rnorm(n, 0, 0.5), 4)
  r <- reg_did_panel(y1, y0, D, X)
  dy <- y1 - y0
  add("reg", c(0, n, p, dy, D, as.vector(t(X))), r$ATT); add("reg", c(1, n, p, dy, D, as.vector(t(X))), r$se)
}
emit("drdid", "DRDID", list(cases))
