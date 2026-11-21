# ordinal::profile and confint (profile likelihood) for clm.
#   args (n, p, K, link 0 logit 1 probit 2 cloglog 3 loglog 4 cauchit, which 0-based, level, y[n] 0-based, x[n*p] row-major)
#   "plo", "phi": confint(f, level) lower and upper limit of coefficient which (profile.clm at alpha = (1 - level) / 4, spline, approx)
#   "pn": number of profile points of profile(f, which.beta = which) at the default alpha 0.001; "psum": sum of lroot * (1-based position)
#   The port repeats R's grid (beta_hat +- step * delta * se, R's own Newton path at gradTol 1e-6 with the coefficient held fixed), so values agree to 1e-9.
suppressMessages(library(ordinal))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
links <- c("logit", "probit", "cloglog", "loglog", "cauchit")
set.seed(20262801)
for (rep in 1:25) {
  n <- sample(120:260, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 5
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.8; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b)
  u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else if (lk == 2) log(-log(runif(n))) else if (lk == 3) -log(-log(runif(n))) else if (rep %% 2 == 0) rcauchy(n) else rnorm(n)
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(suppressWarnings(clm(y ~ ., data = d, link = links[lk + 1])), error = function(e) NULL)
  if (is.null(f) || !is.finite(logLik(f))) next
  level <- c(0.95, 0.9, 0.99)[rep %% 3 + 1]
  w <- sample(seq_len(p), 1)
  ci <- tryCatch(suppressWarnings(confint(f, level = level)), error = function(e) NULL)
  pr <- tryCatch(suppressWarnings(profile(f, which.beta = w)), error = function(e) NULL)
  if (is.null(ci) || is.null(pr)) next
  a <- c(n, p, K, lk, w - 1, level, y, as.vector(t(x)))
  pp <- pr[[1]]
  add("plo", a, unname(ci[w, 1])); add("phi", a, unname(ci[w, 2]))
  add("pn", a, nrow(pp)); add("psum", a, sum(pp$lroot * seq_len(nrow(pp))))
}
emit("ordinal4", "ordinal", list(cases))
