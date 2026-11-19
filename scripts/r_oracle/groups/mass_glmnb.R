# MASS glm.nb (and theta.ml / theta.mm inside it).
# Tolerance 1e-5 for modes 1 and 2 (theta and its SE): theta.ml iterates on digamma/trigamma sums where lgamma differs by an ulp in 70% of points (mass_probe.R), and near-Poisson samples amplify it
#   "nb" (n, p, link 0 log 1 sqrt, has.w, has.off, init.theta (0 none), maxit, epsilon, mode, y[n], X[n p] col-major (intercept first), w[n] (if has.w), off[n] (if has.off))
#   mode 0 weighted coefficients, 1 theta, 2 SE.theta, 3 twologlik, 4 aic, 5 deviance, 6 null.deviance, 7 glm.fit iterations, 8 rank, 9 weighted fitted values
#   "thmm" (n, dfr, limit, y[n], mu[n], w[n]): theta.mm
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, abs = 1e-9) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262407)
for (rep in 1:30) {
  n <- sample(c(25, 35, 45), 1); p <- sample(2:3, 1)
  X <- cbind(1, matrix(rnorm(n * (p - 1), 0, 0.7), n, p - 1)); b <- c(1.2, rnorm(p - 1, 0, 0.5)); th <- runif(1, 1, 6)
  link <- as.numeric(rep %% 5 == 0); has.w <- as.numeric(rep %% 3 == 1); has.off <- as.numeric(rep %% 4 == 2); init <- if (rep %% 6 == 0) round(runif(1, 1, 3), 2) else 0
  off <- round(rnorm(n, 0, 0.3), 3); w <- round(runif(n, 0.5, 2), 3)
  eta <- as.vector(X %*% b) + if (has.off == 1) off else 0
  mu <- if (link == 0) exp(eta) else (abs(eta) + 0.5)^2
  y <- rnbinom(n, size = th, mu = mu)
  d <- data.frame(y = y, X[, -1, drop = FALSE]); fo <- as.formula(paste("y ~", paste(colnames(d)[-1], collapse = " + "), if (has.off == 1) "+ offset(off)"))
  args <- list(fo, data = d, link = if (link == 0) quote(log) else quote(sqrt), control = glm.control(maxit = 25, epsilon = 1e-8))
  if (has.w == 1) args$weights <- w
  if (init > 0) args$init.theta <- init
  f <- tryCatch(suppressWarnings(do.call(glm.nb, args)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, link, has.w, has.off, init, 25, 1e-8); tail <- c(y, as.vector(X), if (has.w == 1) w, if (has.off == 1) off)
  v <- c(wsum(f$coefficients), f$theta, f$SE.theta, f$twologlik, f$aic, f$deviance, f$null.deviance, f$iter, f$rank, wsum(f$fitted.values))
  for (m in 0:9) add("nb", c(a, m, tail), v[m + 1], if (m %in% c(7, 8)) 0 else if (m %in% c(1, 2)) 1e-5 else 1e-8, if (m %in% c(7, 8)) 0 else 1e-9)  # theta and its SE: a near-Poisson sample has theta ~ 3e4, where digamma differences of a few ulp move theta.ml at 1e-6
}
for (rep in 1:15) {
  n <- sample(10:40, 1); mu <- runif(n, 1, 8); y <- rnbinom(n, mu = mu, size = 3); w <- round(runif(n, 0.5, 2), 3); dfr <- n - 2
  add("thmm", c(n, dfr, 10, y, mu, w), as.vector(theta.mm(y, mu, dfr, w, limit = 10)), 1e-9)
}
emit("mass_glmnb", "MASS", list(cases))
