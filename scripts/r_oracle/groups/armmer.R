# armmer: arm for an lme4 linear mixed model with one random intercept: sim, se.fixef, se.ranef and extractDIC.
#   "simmer" (seed, nsims, n, p, ng, reml, which, from, len, X[n p] column-major, group codes 0-based[n], y[n]): after set.seed(seed), sim(lmer fit, nsims) with which 0 the sigma draws,
#       1 the fixef draw `from`, 2 the ranef draw `from`; the weighted sum 1 * v[1] + 2 * v[2] + ... of `len` values
#   "semer" (n, p, ng, reml, which, X, g, y) with which 0 se.fixef, 1 se.ranef (the weighted sum); "dicmer" (n, p, ng, reml, X, g, y) extractDIC
# lmer's own optimiser (bobyqa) stops at theta within about 1e-4 of the optimum, which Neper's Brent search (1e-10) does not copy, so the tolerance is lmer's oracle's, 2e-3.
suppressMessages(library(arm)); suppressMessages(library(lme4))
cases <- list()
wsum <- function(v) sum(seq_along(v) * v)
set.seed(20262500)
for (rep in 1:18) {
  ng <- sample(6:12, 1); per <- sample(4:9, ng, TRUE); n <- sum(per); g <- rep(seq_len(ng) - 1, per); p <- sample(1:3, 1)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1)); sb <- runif(1, 0.5, 2); b <- rnorm(ng, 0, sb); y <- round(as.vector(X %*% rnorm(p)) + b[g + 1] + rnorm(n), 4)
  reml <- rep %% 3 != 0; d <- data.frame(y = y, g = factor(g)); for (j in seq_len(p - 1)) d[[paste0("x", j)]] <- X[, j + 1]
  f <- if (p == 1) y ~ 1 + (1 | g) else as.formula(paste("y ~", paste0("x", seq_len(p - 1), collapse = " + "), "+ (1 | g)"))
  m <- suppressWarnings(suppressMessages(lmer(f, d, REML = reml)))
  if (getME(m, "theta")[[1]] < 0.2) next
  body <- c(as.vector(X), g, y)
  se <- c(wsum(se.fixef(m)), wsum(as.vector(se.ranef(m)$g)))
  for (w in 0:1) cases[[length(cases) + 1]] <- case("semer", c(n, p, ng, reml, w, body), se[w + 1], rel = 2e-3, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("dicmer", c(n, p, ng, reml, body), extractDIC(m), rel = 1e-5, abs = 1e-5)
  if (reml) {
    ns <- 4; sd0 <- sample(1:100000, 1); set.seed(sd0); sm <- sim(m, ns)
    pre <- c(sd0, ns, n, p, ng, 1)
    cases[[length(cases) + 1]] <- case("simmer", c(pre, 0, 0, ns, body), wsum(sm@sigma), rel = 2e-3, abs = 1e-6)
    for (i in 1:ns) {
      cases[[length(cases) + 1]] <- case("simmer", c(pre, 1, i - 1, p, body), wsum(sm@fixef[i, ]), rel = 2e-3, abs = 1e-4)
      cases[[length(cases) + 1]] <- case("simmer", c(pre, 2, i - 1, ng, body), wsum(sm@ranef$g[i, , 1]), rel = 2e-3, abs = 1e-4)
    }
  }
}
emit("armmer", "arm", list(cases))
