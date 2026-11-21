# ordinal::clmm with one random intercept, Laplace (nAGQ = 1) and adaptive Gauss-Hermite quadrature (nAGQ = 5, 10).
#   args (n, p, K, ng, link 0 logit 1 probit 2 cloglog 3 loglog, nAGQ, y[n] 0-based, group[n] 0-based, x[n*p] row-major, extra)
#   "mfix": extra = R's fitted (theta, beta, sd); the port evaluates its marginal log-likelihood there and must equal logLik(f). The port repeats R's own inner Newton for the modes
#     (NRalgv3: gradTol 1e-4 from u = 0) and R's Laplace or adaptive-quadrature formula, so the value agrees to 1e-9, loose inner mode and all.
#   "mfit": the port fits the model the way clmm does (clm start, nlminb without a gradient on log tau) and answers one summary of the fit:
#     extra = what: 0 logLik, 1 sum(theta * position), 2 sum(beta * position), 3 sd, 4 sum(ranef * position), 5 sum(condVar * position).
#     nlminb stops at its own rel.tol 1e-10 on the objective after a finite-difference path, so parameters are checked at 5e-5 relative (observed worst 2e-5), the log-likelihood at 1e-9; ranef (the modes, which stop at the inner gradTol 1e-4 and carry the sd error) at 1e-3 (observed worst 3e-4).
#   ordinal's C code evaluates clmm link "cloglog" as F = exp(-exp(-z)) (the port's link 3) and "loglog" as F = 1 - exp(-exp(z)) (the port's link 2); the fixture swaps them.
suppressMessages(library(ordinal))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
links <- c("logit", "probit", "cloglog", "loglog")
set.seed(20262701)
for (rep in 1:24) {
  ng <- sample(12:25, 1); m <- sample(8:14, 1); n <- ng * m; p <- sample(1:2, 1); K <- sample(3:4, 1); lk <- (rep - 1) %% 4
  agq <- c(1, 5, 10)[(rep - 1) %/% 4 %% 3 + 1]
  g <- rep(0:(ng - 1), each = m); x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  sdv <- runif(1, 0.6, 1.4); re <- rnorm(ng) * sdv
  eta <- as.vector(x %*% b) + re[g + 1]
  u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else if (lk == 2) log(-log(runif(n))) else -log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE); d$g <- factor(g, levels = 0:(ng - 1))
  f <- tryCatch(suppressWarnings(clmm(as.formula(paste("y ~", paste0("v", seq_len(p), collapse = "+"), "+ (1|g)")), data = d, link = links[lk + 1], nAGQ = agq)), error = function(e) NULL)
  if (is.null(f) || !is.finite(logLik(f))) next
  a <- c(n, p, K, ng, lk, agq, y, g, as.vector(t(x)))
  ll <- as.numeric(logLik(f))
  th <- f$alpha; be <- f$beta; sdv <- sqrt(as.numeric(VarCorr(f)$g))
  add("mfix", c(a, th, be, sdv), ll, rel = 1e-9)
  add("mfit", c(a, 0), ll, rel = 1e-9)
  add("mfit", c(a, 1), sum(th * seq_along(th)), rel = 5e-5)
  add("mfit", c(a, 2), sum(be * seq_along(be)), rel = 5e-5)
  add("mfit", c(a, 3), sdv, rel = 5e-5)
  re <- as.vector(ranef(f)$g[, 1]); cv <- as.vector(condVar(f)$g[, 1])
  add("mfit", c(a, 4), sum(re * seq_along(re)), rel = 1e-3, abs = 1e-6)
  if (p == 2) {
    f0 <- tryCatch(suppressWarnings(clmm(y ~ v1 + (1|g), data = d, link = links[lk + 1], nAGQ = agq)), error = function(e) NULL)
    if (!is.null(f0) && is.finite(logLik(f0))) {
      an <- suppressWarnings(ordinal:::anova.clm(f0, f))  # what anova.clmm calls
      add("man", c(a, 0), an$LR.stat[2], rel = 1e-6); add("man", c(a, 1), an[["Pr(>Chisq)"]][2], rel = 1e-6)
    }
  }
  add("mfit", c(a, 5), sum(cv * seq_along(cv)), rel = 5e-5)
}
emit("ordinal3", "ordinal", list(cases))
