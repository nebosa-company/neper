# ordinal::clm with the flexible links (Aranda-Ordaz, log-gamma), and ordinal::clmm with a random intercept.
#   flexible links: args (n, p, K, link 5 Aranda-Ordaz 6 log-gamma, y[n] 0-based, x[n*p] row-major);
#     "fll" (log-likelihood), "fth" (thresholds weighted by position), "fbeta" (coefficients weighted by position), "flam" (lambda)
#     R estimates lambda with nlminb (no gradient) from a loose probit start; nlminb stops at rel.tol 1e-10 on the objective, so parameters are checked at 1e-5 (the log-likelihood at 1e-9).
suppressMessages(library(ordinal))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
lnk <- c("Aranda-Ordaz", "log-gamma")
set.seed(20262601)
for (rep in 1:24) {
  n <- sample(150:300, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- 5 + (rep - 1) %% 2
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (rep %% 3 == 0) rnorm(n) else if (rep %% 3 == 1) rlogis(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(suppressWarnings(clm(y ~ ., data = d, link = lnk[lk - 4])), error = function(e) NULL)
  if (is.null(f) || !is.finite(logLik(f)) || f$maxGradient > 1e-3 || f$cond.H > 1e4) next  # ill-conditioned or loosely converged: nlminb stops where its path ends, not at the optimum
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("fll", a, as.numeric(logLik(f))); add("fth", a, sum(f$alpha * seq_along(f$alpha)), rel = 1e-5); add("fbeta", a, sum(f$beta * seq_along(f$beta)), rel = 1e-5); add("flam", a, unname(f$lambda), rel = 1e-5)
}
emit("ordinal2", "ordinal", list(cases))
