# robustbase ltsReg (alpha < 1, adjust = FALSE, mcd = FALSE), seeded.
#   "lts" args (seed, n, pp, intercept, alpha, nsamp, x[n*pp] row-major, y[n], which): element `which` of
#   c(raw.coefficients, coefficients, raw.scale, scale, crit, rsquared, quan, raw.weights[n], lts.wt[n], residuals[n], best[quan]) with the intercept first in the coefficients
suppressMessages(library(robustbase))
cases <- list()
set.seed(20261401)
for (rep in 1:22) {
  pp <- sample(1:3, 1); n <- sample(25:80, 1); icpt <- rep %% 3 != 0
  if (rep %% 4 == 1) n <- sample(25:48, 1)      # exhaustive starts when p = 2
  if (rep %% 9 == 2) { pp <- 1; icpt <- FALSE }  # p = 1: every observation is a start
  exact <- rep %% 7 == 3
  if (exact) { pp <- sample(1:2, 1); n <- sample(20:30, 1) }  # nsamp = "exact": every elemental subset
  x <- matrix(round(rnorm(n * pp, 1, 2), 3), n, pp)
  beta <- round(rnorm(pp + 1, 0, 1.5), 2)
  y <- round(drop(x %*% beta[-1]) + (if (icpt) beta[1] else 0) + rnorm(n, 0, 0.4), 4)
  k <- max(2, n %/% 6); o <- sample(n, k); y[o] <- y[o] + sample(c(-1, 1), k, TRUE) * runif(k, 5, 15)
  alpha <- c(0.5, 0.6, 0.75, 0.9)[1 + rep %% 4]
  ns <- if (exact) 0 else c(500, 200, 1000)[1 + rep %% 3]
  sd0 <- sample(1:100000, 1); set.seed(sd0)
  r <- tryCatch(suppressWarnings(ltsReg(x, y, intercept = icpt, alpha = alpha, nsamp = if (ns == 0) "exact" else ns, mcd = FALSE)), error = function(e) NULL)
  if (is.null(r) || r$scale == 0) next
  p <- pp + icpt
  v <- c(r$raw.coefficients, r$coefficients, r$raw.scale, r$scale, r$crit, r$rsquared, r$quan, r$raw.weights, r$lts.wt, r$residuals, r$best)
  a0 <- c(sd0, n, pp, as.integer(icpt), alpha, ns, as.vector(t(x)), y)
  head <- seq_len(2 * p + 5)
  pick <- c(head, 2 * p + 5 + sample(n, 3), 2 * p + 5 + n + sample(n, 3), 2 * p + 5 + 2 * n + sample(n, 3), 2 * p + 5 + 3 * n + sample(r$quan, 3))
  for (w in pick) cases[[length(cases) + 1]] <- case("lts", c(a0, w - 1), unname(v[w]), rel = 1e-9, abs = 1e-11)
}
emit("robustbase_lts", "robustbase", list(cases))
