# MASS polr (every method) with its glm.fit start and the optim BFGS fit, Hessian included.
# Tolerance 1e-6: polr runs BFGS to reltol 1.5e-8 over pnorm/plogis/log, and the one-ulp differences measured in mass_probe.R move the stopping iteration (gamma and Weibull in fitdistr match at 1e-8 because their path is not sensitive); measured group maximum is about 1e-7
#   "polr" (n, pc, levels, method 0 logistic 1 probit 2 loglog 3 cloglog 4 cauchit, has.w, has.off, use.start, mode, y[n] 1-based, X[n pc] col-major, w[n] (if has.w), off[n] (if has.off), start[pc + levels - 1] (if use.start))
#   mode 0 weighted coefficients, 1 weighted zeta, 2 deviance, 3 weighted fitted probabilities (row-major n by levels), 4 weighted Hessian (column-major), 5 weighted lp
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, abs = 1e-9) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262408)
mn <- c("logistic", "probit", "loglog", "cloglog", "cauchit")
for (rep in 1:40) {
  n <- sample(c(60, 90, 120), 1); pc <- sample(1:3, 1); lv <- sample(3:5, 1); method <- rep %% 5
  X <- matrix(rnorm(n * pc), n, pc); b <- rnorm(pc, 0, 0.8)
  has.w <- as.numeric(rep %% 3 == 1); has.off <- as.numeric(rep %% 4 == 2); use.start <- as.numeric(rep %% 7 == 0)
  w <- round(runif(n, 0.5, 2), 3); off <- round(rnorm(n, 0, 0.3), 3)
  lat <- as.vector(X %*% b) + (if (has.off == 1) off else 0) + rlogis(n)
  y <- cut(lat, c(-Inf, quantile(lat, (1:(lv - 1)) / lv), Inf), labels = FALSE)
  d <- data.frame(y = factor(y, levels = 1:lv, ordered = TRUE), X); colnames(d)[-1] <- paste0("X", 1:pc)
  fo <- as.formula(paste("y ~", paste(colnames(d)[-1], collapse = " + "), if (has.off == 1) "+ offset(off)"))
  args <- list(fo, data = d, method = mn[method + 1], Hess = TRUE)
  if (has.w == 1) args$weights <- w
  st <- NULL
  if (use.start == 1) { st <- c(round(b, 2), seq(-1, 1, length.out = lv - 1)); args$start <- st }
  f <- tryCatch(suppressWarnings(do.call(polr, args)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, pc, lv, method, has.w, has.off, use.start); tail <- c(y, as.vector(X), if (has.w == 1) w, if (has.off == 1) off, if (use.start == 1) st)
  v <- c(wsum(f$coefficients), wsum(f$zeta), f$deviance, wsum(as.vector(t(f$fitted.values))), wsum(as.vector(f$Hessian)), wsum(f$lp))
  for (m in 0:5) add("polr", c(a, m, tail), v[m + 1], rel = 1e-6)  # BFGS stops at reltol 1.5e-8; last-bit differences of pnorm / plogis move the stop by about 1e-7 relative
}
emit("mass_polr", "MASS", list(cases))
