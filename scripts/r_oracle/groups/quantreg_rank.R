# quantreg summary.rq(se = "rank") and the coefficient table; args (n, p, tau, mode, y..., X...) with X the n x (p-1) covariates (the intercept is added)
#   mode = 10 kind + j: kind 0 coefficient, 1 / 2 lower / upper rank bound (alpha 0.1, iid), 3 / 4 the same with iid = FALSE,
#   5 / 6 alpha 0.05 with tcrit = FALSE, 7 / 8 t value and p value of se = "iid"
suppressMessages(library(quantreg))
cases <- list()
set.seed(20261121)
for (rep in 1:8) {
  n <- sample(20:50, 1); p <- sample(2:4, 1)
  X <- matrix(round(rnorm(n * (p - 1)), 3), n, p - 1)
  y <- round(1 + X %*% seq_len(p - 1) + rt(n, 3), 3)
  for (tau in c(0.25, 0.5, 0.75)) {
    f <- rq(y ~ X, tau = tau, method = "br")
    s1 <- suppressWarnings(summary(f, se = "rank"))$coefficients
    s3 <- suppressWarnings(summary(f, se = "rank", iid = FALSE))$coefficients
    s5 <- suppressWarnings(summary(f, se = "rank", alpha = 0.05, tcrit = FALSE))$coefficients
    si <- suppressWarnings(summary(f, se = "iid"))$coefficients
    add <- function(kind, v) for (j in seq_len(p)) cases[[length(cases) + 1]] <<- case("rq", c(n, p, tau, 10 * kind + j - 1, y, X), v[j], rel = 1e-9, abs = 1e-9)
    add(0, s1[, 1]); add(1, s1[, 2]); add(2, s1[, 3])
    add(3, s3[, 2]); add(4, s3[, 3])
    add(5, s5[, 2]); add(6, s5[, 3])
    add(7, si[, 3]); add(8, si[, 4])
  }
}
emit("quantreg_rank", "quantreg", list(cases))
