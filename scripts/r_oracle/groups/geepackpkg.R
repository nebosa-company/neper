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
# geeglm_glm "geg" (what 0 beta 1 vbeta 2 phi 3 alpha, index, family 0 gaussian 1 binomial 2 poisson, corstr 0 indep 1 exch 2 ar1, k, m, p, y, X row-major)
set.seed(20262099)
for (rep in 1:24) {
  fam <- (rep - 1) %% 3; cs <- ((rep - 1) %/% 3) %% 3
  k <- sample(25:50, 1); m <- sample(3:5, 1); p <- 2; id <- rep(1:k, each = m)
  x1 <- round(rnorm(k * m), 3); X <- cbind(1, x1); re <- rep(rnorm(k, 0, 0.5), each = m); eta <- 0.3 + 0.4 * x1 + re
  y <- switch(fam + 1, round(eta + rnorm(k * m), 4), rbinom(k * m, 1, plogis(eta)), rpois(k * m, exp(eta * 0.6)))
  d <- data.frame(y = y, id = id, x1 = x1)
  g <- tryCatch(geeglm(y ~ x1, id = id, data = d, family = list(gaussian, binomial, poisson)[[fam + 1]], corstr = c("independence", "exchangeable", "ar1")[cs + 1]), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(g)) next
  a <- c(fam, cs, k, m, p, y, as.vector(t(X))); rl <- 1e-4
  for (j in 1:p) cases[[length(cases) + 1]] <- case("geg", c(0, j - 1, a), unname(coef(g))[j], rel = rl, abs = 2e-5)
  for (u in 1:p) for (v in 1:p) cases[[length(cases) + 1]] <- case("geg", c(1, (u - 1) * p + v - 1, a), g$geese$vbeta[u, v], rel = 1e-3, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("geg", c(2, 0, a), g$geese$gamma[[1]], rel = 1e-3, abs = 1e-6)
  if (cs > 0) cases[[length(cases) + 1]] <- case("geg", c(3, 0, a), g$geese$alpha[[1]], rel = 1e-3, abs = 3e-5)
}
emit("geepackpkg", "geepack", list(cases))
