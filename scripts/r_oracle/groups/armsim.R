# arm: binned.resids and sim(lm) cases, split from arm.R to keep each oracle file small. Layouts are in arm.R.
suppressMessages(library(arm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262001)
for (rep in 1:7) {
  n <- sample(30:120, 1); nclass <- sample(c(0, 3, 4, 6, 10), 1); if (nclass == 0) nclass <- floor(sqrt(n))
  x <- if (rep %% 2 == 0) round(rnorm(n), 1) else round(rnorm(n), 5); y <- round(rnorm(n), 4)
  bn <- binned.resids(x, y, nclass)$binned
  for (b in seq_len(nrow(bn))) for (cc in 1:6) add("binned", c(nclass, n, x, y, cc - 1, b - 1), bn[b, cc])
  add("binned_rows", c(nclass, n, x, y, 0, 0), nrow(bn))
}
# sim(lm): "simlm" args (seed, nsims, n, k, y[n], x[n*k] row-major, which, s) with which 0 sigma[s], 1 sum((beta[s, ] - beta.hat)^2): a sum of squares does not depend on the sign or the basis of the
# eigenvectors mvrnorm uses (a LAPACK build may flip one), so it checks the draws without fixing the signs
for (rep in 1:18) {
  n <- sample(15:50, 1); k <- sample(2:4, 1); X <- matrix(round(rnorm(n * k), 4), n, k); X[, 1] <- 1; if (rep > 12) X[, k] <- round(X[, k] * 10^sample(c(-2, 2, 3), 1), 6); y <- round(rnorm(n, X %*% rnorm(k)), 4)
  fit <- lm(y ~ X - 1); sd0 <- sample(1:100000, 1); ns <- 6
  set.seed(sd0); s <- sim(fit, ns)
  for (i in 1:ns) {
    cases[[length(cases) + 1]] <- case("simlm", c(sd0, ns, n, k, y, as.vector(t(X)), 0, i - 1), s@sigma[i], rel = 1e-12, abs = 1e-14)
    for (j in 1:k) cases[[length(cases) + 1]] <- case("simlmc", c(sd0, ns, n, k, y, as.vector(t(X)), 2, i - 1, j - 1), s@coef[i, j], rel = 1e-11, abs = 1e-13)
    if (rep <= 12) cases[[length(cases) + 1]] <- case("simlm", c(sd0, ns, n, k, y, as.vector(t(X)), 1, i - 1), sum((s@coef[i, ] - coef(fit))^2), rel = 1e-11, abs = 1e-13)
  }
}
emit("armsim", "arm", list(cases))
