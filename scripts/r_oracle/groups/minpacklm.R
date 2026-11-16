# minpack.lm::nls.lm (numerical Jacobian "lm", analytic Jacobian "lmder", default control): par, deviance, info, niter.
#   "lmsum" is summary(nlsLM(...)): q 0 sigma, 1.. the coefficient standard errors (rel 1e-4: nls differentiates numerically).
#   "lmhess" is the hessian entry (row * np + col) in the q slot.
#   "lmopt" has factor and diag[np] (nls.lm.control(factor, diag)) between upper and q
#   args: (id, n, np, t[n], y[n], p0[np], lower[np], upper[np], q)  q 0..np-1 par, np deviance, np+1 info, np+2 niter
#   ids: 0 p1 exp(-p2 t) + p3   1 p1 t / (p2 + t)   2 p1 / (1 + exp(-(t - p2) / p3))
suppressMessages(library(minpack.lm))
cases <- list()
set.seed(20261116)
mods <- list(function(p, t) p[1] * exp(-p[2] * t) + p[3], function(p, t) p[1] * t / (p[2] + t), function(p, t) p[1] / (1 + exp(-(t - p[2]) / p[3])))
truth <- list(c(5, 0.8, 1), c(10, 2), c(8, 4, 1.5)); start <- list(c(3, 0.3, 0), c(6, 5), c(6, 3, 1))
for (rep in 1:30) {
  id <- (rep - 1) %% 3; n <- sample(12:40, 1); tt <- sort(round(runif(n, 0.1, 10), 3))
  y <- round(mods[[id + 1]](truth[[id + 1]], tt) + rnorm(n, 0, 0.15), 4); p0 <- start[[id + 1]] * runif(length(start[[id + 1]]), 0.7, 1.4)
  np <- length(p0); bounded <- rep %% 4 == 0
  lo <- rep(-1e300, np); hi <- rep(1e300, np); if (bounded) { lo[1] <- 0; hi[1] <- truth[[id + 1]][1] * 0.9 }
  f <- function(p) y - mods[[id + 1]](p, tt)
  r <- suppressWarnings(nls.lm(p0, lower = lo, upper = hi, fn = f))
  out <- c(r$par, r$deviance, r$info, r$niter)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("lm", c(id, n, np, tt, y, p0, lo, hi, q - 1), out[q], rel = 1e-6, abs = 1e-9)
}
jacs <- list(function(p, t) -cbind(exp(-p[2] * t), -p[1] * t * exp(-p[2] * t), 1),
             function(p, t) -cbind(t / (p[2] + t), -p[1] * t / (p[2] + t)^2),
             function(p, t) { u <- exp(-(t - p[2]) / p[3]); den <- 1 + u; s <- (t - p[2]) / p[3]; -cbind(1 / den, -p[1] * u / (p[3] * den^2), -p[1] * u * s / (p[3] * den^2)) })
for (rep in 1:30) {
  id <- (rep - 1) %% 3; n <- sample(12:40, 1); tt <- sort(round(runif(n, 0.1, 10), 3))
  y <- round(mods[[id + 1]](truth[[id + 1]], tt) + rnorm(n, 0, 0.15), 4); p0 <- start[[id + 1]] * runif(length(start[[id + 1]]), 0.7, 1.4)
  np <- length(p0); bounded <- rep %% 4 == 0
  lo <- rep(-1e300, np); hi <- rep(1e300, np); if (bounded) { lo[1] <- 0; hi[1] <- truth[[id + 1]][1] * 0.9 }
  f <- function(p) y - mods[[id + 1]](p, tt); jf <- function(p) jacs[[id + 1]](p, tt)
  r <- tryCatch(suppressWarnings(nls.lm(p0, lower = lo, upper = hi, fn = f, jac = jf)), error = function(e) NULL); if (is.null(r)) next
  out <- c(r$par, r$deviance, r$info, r$niter)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("lmder", c(id, n, np, tt, y, p0, lo, hi, q - 1), out[q], rel = 1e-6, abs = 1e-9)
}
for (rep in 1:30) {
  id <- (rep - 1) %% 3; n <- sample(12:40, 1); tt <- sort(round(runif(n, 0.1, 10), 3))
  y <- round(mods[[id + 1]](truth[[id + 1]], tt) + rnorm(n, 0, 0.15), 4); p0 <- start[[id + 1]] * runif(length(start[[id + 1]]), 0.7, 1.4)
  np <- length(p0); lo <- rep(-1e300, np); hi <- rep(1e300, np); fc <- sample(c(1, 10, 100, 1000), 1); dg <- round(runif(np, 0.5, 5), 2)
  f <- function(p) y - mods[[id + 1]](p, tt)
  r <- suppressWarnings(nls.lm(p0, lower = lo, upper = hi, fn = f, control = nls.lm.control(factor = fc, diag = as.list(dg))))
  out <- c(r$par, r$deviance, r$info, r$niter)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("lmopt", c(id, n, np, tt, y, p0, lo, hi, fc, dg, q - 1), out[q], rel = 1e-6, abs = 1e-9)
}
for (rep in 1:30) {
  id <- (rep - 1) %% 3; n <- sample(12:40, 1); tt <- sort(round(runif(n, 0.1, 10), 3))
  y <- round(mods[[id + 1]](truth[[id + 1]], tt) + rnorm(n, 0, 0.15), 4); p0 <- start[[id + 1]] * runif(length(start[[id + 1]]), 0.7, 1.4)
  np <- length(p0); lo <- rep(-1e300, np); hi <- rep(1e300, np)
  f <- function(p) y - mods[[id + 1]](p, tt)
  r <- suppressWarnings(nls.lm(p0, lower = lo, upper = hi, fn = f))
  for (i in 1:np) for (j in 1:np) cases[[length(cases) + 1]] <- case("lmhess", c(id, n, np, tt, y, p0, lo, hi, (i - 1) * np + j - 1), r$hessian[i, j], rel = 1e-5, abs = 1e-8)
}
fm <- list(y ~ p1 * exp(-p2 * t) + p3, y ~ p1 * t / (p2 + t), y ~ p1 / (1 + exp(-(t - p2) / p3)))
pn <- list(c("p1", "p2", "p3"), c("p1", "p2"), c("p1", "p2", "p3"))
for (rep in 1:30) {
  id <- (rep - 1) %% 3; n <- sample(15:40, 1); tt <- sort(round(runif(n, 0.1, 10), 3))
  y <- round(mods[[id + 1]](truth[[id + 1]], tt) + rnorm(n, 0, 0.15), 4); p0 <- start[[id + 1]] * runif(length(start[[id + 1]]), 0.7, 1.4)
  np <- length(p0); names(p0) <- pn[[id + 1]]
  fit <- tryCatch(suppressWarnings(nlsLM(fm[[id + 1]], data = list(t = tt, y = y), start = as.list(p0))), error = function(e) NULL); if (is.null(fit)) next
  sm <- summary(fit); lo <- rep(-1e300, np); hi <- rep(1e300, np)
  out <- c(sm$sigma, sm$coefficients[, 2])
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("lmsum", c(id, n, np, tt, y, p0, lo, hi, q - 1), out[q], rel = 1e-4, abs = 1e-8)
}
emit("minpacklm", "minpack.lm", list(cases))
