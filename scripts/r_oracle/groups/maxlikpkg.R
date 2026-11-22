# maxlikpkg: maxLik::maxLik with method NR, BHHH, BFGS and NM on five log-likelihoods with analytic per-observation gradients and Hessians, and stdEr().
#   args: (model, method, what, index, n, start (p), x (n), y (n)); model 0 normal (mu, s), 1 poisson regression, 2 logistic regression, 3 Weibull (shape, scale), 4 linear regression (b0, b1, s);
#   method 0 NR, 1 BHHH, 2 BFGS, 3 NM; what 0 maximum, 1 estimate[index], 2 stdEr[index], 3 code, 4 iterations (NR and BHHH) or optim's function count (BFGS, NM), 5 gradient[index]
#   tolerances: maximum, estimate and stdEr 1e-9 relative (the paths are the same sequence of operations; only libm's last digit differs); gradient 1e-6 relative with 1e-6 absolute (it is noise near zero); code and iterations exact
suppressMessages(library(maxLik))
cases <- list()
add <- function(args, want, rel, abs) cases[[length(cases) + 1]] <<- case("maxlik", args, want, rel = rel, abs = abs)
npar <- c(2, 2, 2, 2, 3)
mkf <- function(m, x, y) {
  n <- length(x)
  if (m == 0) list(
    ll = function(th) -0.5 * log(2 * pi) - log(th[2]) - (x - th[1]) * (x - th[1]) / (2 * th[2] * th[2]),
    gr = function(th) cbind((x - th[1]) / (th[2] * th[2]), -1 / th[2] + (x - th[1]) * (x - th[1]) / (th[2] * th[2] * th[2])),
    he = function(th) { s <- th[2]; d <- x - th[1]; h12 <- sum(-2 * d / (s * s * s)); matrix(c(sum(rep(-1 / (s * s), n)), h12, h12, sum(1 / (s * s) - 3 * d * d / (s * s * s * s))), 2) })
  else if (m == 1) list(
    ll = function(th) { eta <- th[1] + th[2] * x; y * eta - exp(eta) },
    gr = function(th) { mu <- exp(th[1] + th[2] * x); cbind(y - mu, (y - mu) * x) },
    he = function(th) { mu <- exp(th[1] + th[2] * x); h12 <- sum(-mu * x); matrix(c(sum(-mu), h12, h12, sum(-mu * x * x)), 2) })
  else if (m == 2) list(
    ll = function(th) { eta <- th[1] + th[2] * x; y * eta - log(1 + exp(eta)) },
    gr = function(th) { p <- 1 / (1 + exp(0 - (th[1] + th[2] * x))); cbind(y - p, (y - p) * x) },
    he = function(th) { p <- 1 / (1 + exp(0 - (th[1] + th[2] * x))); w <- p * (1 - p); h12 <- sum(-w * x); matrix(c(sum(-w), h12, h12, sum(-w * x * x)), 2) })
  else if (m == 3) list(
    ll = function(th) log(th[1]) - th[1] * log(th[2]) + (th[1] - 1) * log(x) - (x / th[2])^th[1],
    gr = function(th) { z <- x / th[2]; u <- z^th[1]; cbind(1 / th[1] + log(x) - log(th[2]) - u * log(z), th[1] / th[2] * (u - 1)) },
    he = function(th) { k <- th[1]; l <- th[2]; z <- x / l; u <- z^k; lz <- log(z)
      h12 <- sum((u - 1 + k * u * lz) / l); matrix(c(sum(-1 / (k * k) - u * lz * lz), h12, h12, sum(k / (l * l) * (1 - u - k * u))), 2) })
  else list(
    ll = function(th) { r <- y - th[1] - th[2] * x; -0.5 * log(2 * pi) - log(th[3]) - r * r / (2 * th[3] * th[3]) },
    gr = function(th) { r <- y - th[1] - th[2] * x; s2 <- th[3] * th[3]; cbind(r / s2, r * x / s2, -1 / th[3] + r * r / (s2 * th[3])) },
    he = function(th) { s <- th[3]; r <- y - th[1] - th[2] * x
      h <- matrix(0, 3, 3); h[1, 1] <- sum(rep(-1 / (s * s), n)); h[1, 2] <- sum(-x / (s * s)); h[1, 3] <- sum(-2 * r / (s * s * s))
      h[2, 2] <- sum(-x * x / (s * s)); h[2, 3] <- sum(-2 * r * x / (s * s * s)); h[3, 3] <- sum(1 / (s * s) - 3 * r * r / (s * s * s * s))
      h[2, 1] <- h[1, 2]; h[3, 1] <- h[1, 3]; h[3, 2] <- h[2, 3]; h })
}
set.seed(20262718)
meth <- c("NR", "BHHH", "BFGS", "NM")
for (rep in 1:200) {
  m <- (rep - 1) %% 5; mt <- ((rep - 1) %/% 5) %% 4; n <- sample(25:70, 1)
  if (m == 0) { tr <- c(runif(1, -2, 2), runif(1, 0.5, 3)); x <- round(rnorm(n, tr[1], tr[2]), 3); y <- rep(0, n); st <- tr * runif(2, 0.4, 1.8) + c(0.5, 0) }
  if (m == 1) { tr <- c(runif(1, -0.5, 1), runif(1, -1, 1)); x <- round(runif(n, -1, 1), 3); y <- rpois(n, exp(tr[1] + tr[2] * x)); st <- tr + runif(2, -1, 1) }
  if (m == 2) { tr <- c(runif(1, -1, 1), runif(1, -2, 2)); x <- round(rnorm(n), 3); y <- rbinom(n, 1, 1 / (1 + exp(-(tr[1] + tr[2] * x)))); st <- tr + runif(2, -1.5, 1.5) }
  if (m == 3) { tr <- c(runif(1, 0.8, 3), runif(1, 0.5, 3)); x <- pmax(round(rweibull(n, tr[1], tr[2]), 3), 0.001); y <- rep(0, n); st <- tr * runif(2, 0.6, 1.5) }
  if (m == 4) { tr <- c(runif(1, -1, 1), runif(1, -2, 2), runif(1, 0.3, 2)); x <- round(runif(n, -1, 2), 3); y <- round(tr[1] + tr[2] * x + rnorm(n, 0, tr[3]), 3); st <- tr * runif(3, 0.5, 1.6) }
  st <- round(st, 3); f <- mkf(m, x, y)
  r <- tryCatch(suppressWarnings(maxLik(f$ll, f$gr, f$he, start = st, method = meth[mt + 1])), error = function(e) NULL)
  if (is.null(r)) next
  se <- tryCatch(suppressWarnings(stdEr(r)), error = function(e) NULL)
  if (is.null(se) || any(!is.finite(se)) || any(!is.finite(r$estimate)) || !is.finite(r$maximum)) next
  p <- npar[m + 1]; a <- function(what, idx) c(m, mt, what, idx, n, st, x, y)
  # BFGS: R's own function count moves with the summation precision (long double against double sums changes it by up to 10 evaluations in 40 seeds, and the estimate by 1e-8),
  # so the count and the noise-sized final gradient are not compared and the estimate and stdEr carry 1e-6
  loose <- mt == 2; er <- if (loose) 1e-6 else 1e-9
  add(a(0, 0), r$maximum, 1e-9, 0)
  for (j in seq_len(p)) { add(a(1, j - 1), r$estimate[j], er, 0); add(a(2, j - 1), se[j], er, 0); if (!loose) add(a(5, j - 1), r$gradient[j], 1e-6, 1e-6) }
  add(a(3, 0), r$code, 0, 0); if (!loose) add(a(4, 0), r$iterations, 0, 0)
}
emit("maxlikpkg", "maxLik", list(cases))
