# timereg prop.excess (proportional excess hazard model): cumulative baseline and excess functions with robust variances, beta and its robust variance, dU/dbeta, and the
# resampled sup, Hall-Wellner and Cramer-von Mises tests with the sup and Hall-Wellner 95% quantiles. beta starts at coxph's fit, as prop.excess does.
#   fn "s00".."s09": weighted sum (position, row-major) of cum, var.cum, gamma, var.gamma, pval, score, pval.HW, pval.CM, quant95, quant95HW
#   args: (n, p, q, antsim, seed, tol, alpha, time[n], status[n], X[n*p], Z[n*q], excess[n], beta0[q])
suppressMessages({library(timereg); library(survival)})
cases <- list()
flat <- function(m) as.vector(t(as.matrix(m)))
set.seed(20271201)
done <- 0
for (rep in 1:40) {
  if (done >= 12) break
  n <- sample(45:75, 1); p <- sample(1:2, 1); q <- sample(1:2, 1)
  zz <- matrix(rnorm(n * q), n); x1 <- rnorm(n); ex <- runif(n, 0.5, 1.5)
  rate <- 0.3 + ex * exp(0.5 * zz[, 1]); tt <- rexp(n, rate) + runif(n) * 1e-4; cc <- runif(n, 0, 3)
  y <- pmin(tt, cc) + seq_len(n) * 1e-9; ev <- as.numeric(tt <= cc)
  d <- data.frame(y, ev, x1); for (k in seq_len(q)) d[[paste0("z", k)]] <- zz[, k]
  nsim <- sample(c(50, 100), 1); sd <- sample(1:100000, 1)
  xt <- if (p == 1) "" else "x1 + "
  fm <- as.formula(paste("Surv(y, ev) ~", xt, paste0("cox(z", seq_len(q), ")", collapse = " + ")))
  b0 <- as.numeric(coxph(Surv(y, ev) ~ zz, d)$coef)
  set.seed(sd)
  f <- tryCatch(suppressWarnings(prop.excess(fm, d, excess = ex, n.sim = nsim)), error = function(e) NULL)
  set.seed(20271201 + rep)
  if (is.null(f) || any(is.na(f$gamma)) || any(!is.finite(f$cum)) || any(!is.finite(f$var.cum)) || any(is.na(f$pval)) || any(is.na(f$pval.HW))) next
  X <- cbind(1, x1)[, seq_len(p), drop = FALSE]
  a <- c(n, p, q, nsim, sd, 1e-4, 1, y, ev, as.vector(t(X)), as.vector(t(zz)), ex, b0)
  sl <- list(f$cum, f$var.cum, f$gamma, f$var.gamma, f$pval, f$score, f$pval.HW, f$pval.CM, f$quant95, f$quant95HW)
  for (j in 0:9) {
    v <- flat(sl[[j + 1]])
    cases[[length(cases) + 1]] <- case(sprintf("s%02d", j), a, sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12)
  }
  done <- done + 1
}
emit("timereg_propexcess", "timereg", list(cases))
