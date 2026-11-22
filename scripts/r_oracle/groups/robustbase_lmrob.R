# robustbase lmrob (method "MM" with bisquare, and "SMDM" with lqq; default control), seeded: the S step's subsampling draws are in R's order.
#   "lmrob" args (seed, n, pp, intercept, nResample, smdm, x[n*pp] row-major, y[n], which): element `which` of
#   c(S coefficients, S scale, final coefficients, final scale, last M iterations, S converged, last M converged, final residuals[n], final weights[n],
#     and for smdm: kappa, D scale, D converged, first M coefficients); the coefficients have the intercept first
suppressMessages(library(robustbase))
cases <- list()
set.seed(20261501)
for (rep in 1:26) {
  smdm <- rep %% 2 == 0
  pp <- sample(1:3, 1); n <- sample(25:90, 1); icpt <- rep %% 5 != 0
  x <- matrix(round(rnorm(n * pp, 1, 2), 3), n, pp)
  beta <- round(rnorm(pp + 1, 0, 1.5), 2)
  y <- round(drop(x %*% beta[-1]) + (if (icpt) beta[1] else 0) + rnorm(n, 0, 0.4), 4)
  k <- max(2, n %/% 6); o <- sample(n, k); y[o] <- y[o] + sample(c(-1, 1), k, TRUE) * runif(k, 5, 15)
  if (rep %% 4 == 0) { o2 <- sample(n, 2); x[o2, 1] <- x[o2, 1] + 12 }  # a few leverage points
  ns <- c(500, 200, 300)[1 + rep %% 3]
  sd0 <- sample(1:100000, 1)
  X <- if (icpt) cbind(1, x) else x
  p <- ncol(X)
  set.seed(sd0)
  r <- tryCatch(suppressWarnings(lmrob.fit(X, y, control = lmrob.control(nResample = ns, method = if (smdm) "SMDM" else "MM"), bare.only = TRUE)), error = function(e) NULL)
  if (is.null(r) || !isTRUE(r$converged)) next
  if (smdm) {
    d <- r$init; s <- d$init$init.S
    if (is.null(s) || !isTRUE(d$converged)) next
  } else s <- r$init.S
  if (is.null(s)) next
  v <- c(s$coefficients, s$scale, r$coefficients, r$scale, r$iter, as.numeric(isTRUE(s$converged)), as.numeric(isTRUE(r$converged)), r$residuals, r$rweights)
  if (smdm) v <- c(v, d$kappa, d$scale, as.numeric(isTRUE(d$converged)), d$coefficients)
  a0 <- c(sd0, n, pp, as.integer(icpt), ns, as.integer(smdm), as.vector(t(x)), y)
  pick <- c(seq_len(2 * p + 5), 2 * p + 5 + sample(n, 3), 2 * p + 5 + n + sample(n, 3))
  if (smdm) pick <- c(pick, 2 * p + 5 + 2 * n + seq_len(3 + p))
  for (w in pick) cases[[length(cases) + 1]] <- case("lmrob", c(a0, w - 1), unname(v[w]), rel = 1e-9, abs = 1e-11)
}
emit("robustbase_lmrob", "robustbase", list(cases))
