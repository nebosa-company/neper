# quantreg inference and the other fitters; args (n, p, tau, mode, seed, R, y..., X...) with X the n x (p-1) covariates (the intercept is added)
#   mode 0..p-1 coefficient j; 100+j iid se; 200+j boot se (xy pairs, set.seed(seed), R replications); 300+k*p+j: coefficient j of the k-th tau in the grid
suppressMessages(library(quantreg))
cases <- list()
set.seed(20261120)
taus <- c(0.1, 0.3, 0.5, 0.7, 0.9)
for (rep in 1:12) {
  n <- sample(20:60, 1); p <- sample(2:4, 1)
  X <- matrix(round(rnorm(n * (p - 1)), 3), n, p - 1)
  y <- round(1 + X %*% seq_len(p - 1) + rt(n, 3), 3)
  seed <- sample(1000:9999, 1)
  for (tau in c(0.25, 0.5, 0.75)) {
    se <- suppressWarnings(summary(rq(y ~ X, tau = tau, method = "br"), se = "iid")$coefficients[, 2])
    for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("rq", c(n, p, tau, 100 + j - 1, 0, 0, y, X), se[j], rel = 1e-9, abs = 1e-12)
  }
  fit <- coef(rq(y ~ X, tau = taus, method = "br"))
  for (k in seq_along(taus)) for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("rq", c(n, p, taus[k], 300 + (k - 1) * p + j - 1, 0, 0, y, X), fit[j, k], rel = 1e-9, abs = 1e-12)
  if (rep <= 5) for (tau in c(0.25, 0.5)) {
    set.seed(seed)
    se <- suppressWarnings(summary(rq(y ~ X, tau = tau, method = "br"), se = "boot", R = 30)$coefficients[, 2])
    for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("rq", c(n, p, tau, 200 + j - 1, seed, 30, y, X), se[j], rel = 1e-9, abs = 1e-12)
  }
}
emit("quantreg_inf", "quantreg", list(cases))
