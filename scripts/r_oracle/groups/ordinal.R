# ordinal::clm, cumulative link models without constant column, at a tight convergence tolerance.
#   args: (n, p, K, link 0 logit 1 probit 2 cloglog, y[n] 0-based, x[n*p] row-major)
#   fn "ll" (log-likelihood), "theta" (thresholds weighted by position), "beta" (coefficients weighted by position)
suppressMessages(library(ordinal))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-7)
set.seed(20261209)
links <- c("logit", "probit", "cloglog")
for (rep in 1:24) {
  n <- sample(100:250, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3
  x <- matrix(rnorm(n * p), n); b <- rnorm(p); th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(y ~ ., data = d, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("ll", a, as.numeric(logLik(f))); add("theta", a, sum(f$alpha * seq_along(f$alpha))); add("beta", a, sum(f$beta * seq_along(f$beta)))
}
emit("ordinal", "ordinal", list(cases))
