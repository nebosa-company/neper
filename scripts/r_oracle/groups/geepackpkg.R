# geepackpkg: geeglm gaussian with independence or exchangeable working correlation, equal clusters. geepack stops its iteration at tol 1e-5, so the exchangeable cases are compared at rel 1e-4 and the independence cases (one step) at 1e-8.
#   args: (what 0 beta 1 vbeta 2 phi 3 alpha, index (beta, or row * p + col), exch 0/1, k, m, p, y (k m), x row-major (k m) by p with the intercept column)
suppressMessages(library(geepack))
cases <- list()
add <- function(fn, args, want, rel = 1e-8) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-9)
set.seed(20262014)
for (rep in 1:20) {
  k <- sample(15:40, 1); m <- sample(3:6, 1); p <- sample(2:3, 1); id <- rep(1:k, each = m)
  X <- cbind(1, matrix(round(rnorm(k * m * (p - 1)), 4), k * m, p - 1)); y <- round(as.vector(X %*% runif(p, -1, 1)) + rep(rnorm(k, 0, 0.8), each = m) + rnorm(k * m), 4)
  d <- data.frame(y = y, id = id); for (j in 2:p) d[[paste0("x", j)]] <- X[, j]
  f <- as.formula(paste("y ~", paste(paste0("x", 2:p), collapse = " + ")))
  for (ex in 0:1) {
    g <- geeglm(f, id = id, data = d, family = gaussian, corstr = if (ex == 1) "exchangeable" else "independence")
    a <- c(k, m, p, y, as.vector(t(X)))
    rl <- if (ex == 1) 1e-4 else 1e-8
    for (j in 1:p) add("gee", c(0, j - 1, ex, a), unname(coef(g))[j], rl)
    for (u in 1:p) for (v in 1:p) add("gee", c(1, (u - 1) * p + v - 1, ex, a), g$geese$vbeta[u, v], rl)
    add("gee", c(2, 0, ex, a), g$geese$gamma[[1]], rl); if (ex == 1) add("gee", c(3, 0, ex, a), g$geese$alpha[[1]], rl)
  }
}
emit("geepackpkg", "geepack", list(cases))
