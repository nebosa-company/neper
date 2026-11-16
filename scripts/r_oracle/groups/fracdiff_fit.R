# fracdiff(x, nar, nma): the Haslett-Raftery fit with default start values.
#   args: (n, p, q, M, x[n], what) what 0 d, 1 log.likelihood, 2 fnormMin, 3 sigma, 4..3+p ar, then ma, then h, covariance.dpq (column-major), hessian.dpq, stderror.dpq
suppressMessages(library(fracdiff))
cases <- list()
add <- function(args, want, rel = 1e-6, abs = 1e-8) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("fracdiff_fit", args, want, rel = rel, abs = abs)
# the d row of the Hessian is a second difference over a step of about 1e-8 (|loglik| + 1), so its roundoff is amplified to about 1e-4: those are compared to 3e-2 (the whole covariance is contaminated by them)
set.seed(20261122)
for (rep in 1:24) {
  n <- sample(c(60, 100, 150, 250), 1)
  p <- sample(0:2, 1); q <- sample(0:1, 1)
  x <- if (rep %% 3 == 0) fracdiff.sim(n, ar = if (p) 0.3 else NULL, ma = if (q) -0.4 else NULL, d = 0.3)$series else as.numeric(arima.sim(list(ar = 0.5), n))
  x <- round(x, 5)
  M <- sample(c(100, 30), 1)
  r <- tryCatch(suppressWarnings(fracdiff(x, nar = p, nma = q, M = M)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, p, q, M, x)
  add(c(a, 0), r$d); add(c(a, 1), r$log.likelihood); add(c(a, 2), r$fnormMin); add(c(a, 3), r$sigma)
  for (j in seq_len(p)) add(c(a, 3 + j), r$ar[j])
  for (j in seq_len(q)) add(c(a, 3 + p + j), r$ma[j])
  b <- 4 + p + q; k1 <- p + q + 1
  add(c(a, b), r$h, 1e-9, 1e-12)
  # for a pure AR or a pure MA fit fdhess.c reads g from workspace the optimiser left uninitialised, so R's own covariance is not reproducible there
  if (((p > 0) == (q > 0) || p + q == 0) && !is.null(r$stderror.dpq) && all(r$stderror.dpq > 1e-6) && all(r$msg == "ok")) {
    cv <- as.vector(r$covariance.dpq); hs <- r$hessian.dpq
    for (j in seq_along(cv)) add(c(a, b + j), cv[j], 3e-2, 1e-5)
    # hessian.dpq: R fills its lower triangle in the wrong order, so only the upper triangle is compared
    for (j in seq_along(hs)) if (row(hs)[j] <= col(hs)[j]) add(c(a, b + k1 * k1 + j), hs[j], 3e-2, 1e-5)
    if (!is.null(r$stderror.dpq)) for (j in seq_len(k1)) add(c(a, b + 2 * k1 * k1 + j), r$stderror.dpq[j], 3e-2, 1e-5)
  }
}
emit("fracdiff_fit", "fracdiff", list(cases))
