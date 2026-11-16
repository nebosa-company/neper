# drdid: reg_did_panel's ATT and standard error.
#   args: (part 0 ATT or 1 se, n, p, y1 - y0 (n), D (n), covariates row-major n by p...); "reg" is reg_did_panel, "dr" is drdid_panel (propensity by glm, so rel 1e-6)
suppressMessages(library(DRDID))
cases <- list()
add <- function(fn, args, want, rel = 1e-8) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-9)
set.seed(20262007)
for (rep in 1:25) {
  n <- sample(80:300, 1); p <- sample(1:3, 1)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1)); D <- rbinom(n, 1, plogis(0.3 * X[, p]))
  y0 <- round(rnorm(n, X %*% rep(1, p)), 4); y1 <- round(y0 + 0.5 + 0.3 * X[, p] + 0.8 * D + rnorm(n, 0, 0.5), 4)
  r <- reg_did_panel(y1, y0, D, X)
  dy <- y1 - y0
  add("reg", c(0, n, p, dy, D, as.vector(t(X))), r$ATT); add("reg", c(1, n, p, dy, D, as.vector(t(X))), r$se)
}
for (rep in 1:25) {
  n <- sample(150:400, 1); p <- sample(1:3, 1)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1)); D <- rbinom(n, 1, plogis(0.3 * X[, p] - 0.2)); if (p == 1) D <- rbinom(n, 1, 0.4)
  y0 <- round(rnorm(n, X %*% rep(1, p)), 4); y1 <- round(y0 + 0.5 + 0.3 * X[, p] + 0.8 * D + rnorm(n, 0, 0.5), 4)
  r <- drdid_panel(y1, y0, D, X); dy <- y1 - y0
  add("dr", c(0, n, p, dy, D, as.vector(t(X))), r$ATT, 1e-6); add("dr", c(1, n, p, dy, D, as.vector(t(X))), r$se, 1e-6)
}
emit("drdid", "DRDID", list(cases))
