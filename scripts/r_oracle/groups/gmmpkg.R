# gmmpkg: gmm's linear two-step estimator with vcov = "iid" or "MDS".
#   args: (what 0 coefficient 1 covariance entry 2 J test, index, mds 0/1, n, p, q, y (n), x row-major n by p, z row-major n by q)
suppressMessages(library(gmm))
cases <- list()
add <- function(fn, args, want, rel = 1e-6) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-9)
set.seed(20262017)
for (rep in 1:20) {
  n <- sample(100:400, 1); q <- sample(3:5, 1); Z <- cbind(1, matrix(round(rnorm(n * (q - 1)), 4), n, q - 1)); u <- rnorm(n)
  x1 <- round(as.vector(Z[, 2:3] %*% c(1, 0.5)) + 0.5 * u + rnorm(n), 4); y <- round(1 + 2 * x1 + u * (1 + 0.5 * abs(Z[, 2])), 4)
  X <- cbind(1, x1); d <- data.frame(y = y, x = x1); for (j in 2:q) d[[paste0("z", j)]] <- Z[, j]
  zf <- as.formula(paste("~", paste(paste0("z", 2:q), collapse = " + ")))
  for (md in 0:1) {
    g <- gmm(y ~ x, zf, data = d, vcov = if (md == 1) "MDS" else "iid", type = "twoStep")
    a <- c(md, n, 2, q, y, as.vector(t(X)), as.vector(t(Z)))
    for (j in 1:2) add("gmm", c(0, j - 1, a), unname(coef(g))[j])
    for (u2 in 1:2) for (v in 1:2) add("gmm", c(1, (u2 - 1) * 2 + v - 1, a), vcov(g)[u2, v])
    add("gmm", c(2, 0, a), unname(specTest(g)$test[1, 1]))
  }
}
emit("gmmpkg", "gmm", list(cases))
