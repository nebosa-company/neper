# ica: icafast with the symmetric update. Compared up to the sign and order of the components:
# vafs (sorted), the iteration count, convergence and the reconstruction S %*% t(M).
#   args: (n, p, nc, fun 0 logcosh 1 kur 2 exp, alpha, maxit, tol, X row-wise...)
#   fn "vafs" (position last), "iter", "conv", "recon" (stat last: 0 sum 1 position-weighted sum 2 sum of squares)
library(ica)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261115)
funs <- c("logcosh", "kur", "exp")
for (rep in 1:4) {
  n <- c(100, 120, 90, 110)[rep]; p <- c(3, 4, 5)[(rep - 1) %% 3 + 1]
  S <- cbind(runif(n, -1, 1), rexp(n) - 1, rt(n, 5), sign(rnorm(n)) * runif(n, 0.5, 1), rnorm(n) * runif(n))[, 1:p]
  A <- matrix(round(runif(p * p, -1, 1), 2), p, p) + diag(p)
  X <- round(S %*% A, 4)
  for (nc in unique(c(2, p))) for (fn in 0:2) for (alpha in 1) {
    r <- tryCatch(suppressWarnings(icafast(X, nc, fun = funs[fn + 1], alpha = alpha, maxit = 200, tol = 1e-8)), error = function(e) NULL)
    if (is.null(r) || length(r$vafs) != nc) next
    a <- c(n, p, nc, fn, alpha, 200, 1e-8, as.vector(t(X)))
    for (i in seq_len(nc)) add("vafs", c(a, i - 1), r$vafs[i])
    add("iter", a, r$iter); add("conv", a, as.numeric(r$converged))
    rec <- as.vector(t(r$S %*% t(r$M))); w <- seq_along(rec)
    add("recon", c(a, 0), sum(rec)); add("recon", c(a, 1), sum(w * rec)); add("recon", c(a, 2), sum(rec^2))
  }
}
#   icajade and icaimax: the same names with a prefix, j icajade, n icaimax newton, g icaimax gradient (rate = alpha), a gradient with rateanneal c(20, 0.8); fun 0 tanh 1 log 2 ext
imfun <- c("tanh", "log", "ext")
for (rep in 1:4) {
  n <- c(100, 120, 90, 110)[rep]; p <- c(3, 4, 5)[(rep - 1) %% 3 + 1]
  S <- cbind(runif(n, -1, 1), rexp(n) - 1, rt(n, 5), sign(rnorm(n)) * runif(n, 0.5, 1), rnorm(n) * runif(n))[, 1:p]
  A <- matrix(round(runif(p * p, -1, 1), 2), p, p) + diag(p)
  X <- round(S %*% A, 4)
  for (nc in unique(c(2, p))) {
    emit_case <- function(pre, r, a) {
      if (is.null(r) || length(r$vafs) != nc) return()
      for (i in seq_len(nc)) add(paste0(pre, "vafs"), c(a, i - 1), r$vafs[i])
      add(paste0(pre, "iter"), a, r$iter); add(paste0(pre, "conv"), a, as.numeric(r$converged))
      rec <- as.vector(t(r$S %*% t(r$M))); w <- seq_along(rec)
      add(paste0(pre, "recon"), c(a, 0), sum(rec)); add(paste0(pre, "recon"), c(a, 1), sum(w * rec)); add(paste0(pre, "recon"), c(a, 2), sum(rec^2))
    }
    a <- c(n, p, nc, 0, 1, 100, 1e-8, as.vector(t(X)))
    emit_case("j", tryCatch(suppressWarnings(icajade(X, nc, maxit = 100, tol = 1e-8)), error = function(e) NULL), a)
    for (fn in 0:2) {
      a <- c(n, p, nc, fn, 1, 200, 1e-8, as.vector(t(X)))
      emit_case("n", tryCatch(suppressWarnings(icaimax(X, nc, fun = imfun[fn + 1], alg = "newton", maxit = 200, tol = 1e-8)), error = function(e) NULL), a)
      emit_case("g", tryCatch(suppressWarnings(icaimax(X, nc, fun = imfun[fn + 1], alg = "gradient", rate = 0.5, maxit = 200, tol = 1e-8)), error = function(e) NULL), c(n, p, nc, fn, 0.5, 200, 1e-8, as.vector(t(X))))
      emit_case("a", tryCatch(suppressWarnings(icaimax(X, nc, fun = imfun[fn + 1], alg = "gradient", rate = 0.5, rateanneal = c(20, 0.8), maxit = 200, tol = 1e-8)), error = function(e) NULL), c(n, p, nc, fn, 0.5, 200, 1e-8, as.vector(t(X))))
    }
  }
}
#   icafast with alg "def" (prefix d, tall data), alg "par" on wide data n < p (prefix w) and "def" on wide data (prefix x); "diter" is the sum over components, "diterj"
#   (position last) the count of component j
funs2 <- c("logcosh", "kur", "exp")
for (rep in 1:6) {
  wide <- rep > 3
  n <- c(100, 120, 90, 20, 24, 18)[rep]; p <- c(3, 4, 5, 30, 26, 28)[rep]
  S <- cbind(runif(n, -1, 1), rexp(n) - 1, rt(n, 5), sign(rnorm(n)) * runif(n, 0.5, 1), rnorm(n) * runif(n), rnorm(n))
  nsrc <- ncol(S); A <- matrix(round(runif(nsrc * p, -1, 1), 2), nsrc, p)
  X <- round(S[, seq_len(min(nsrc, 6))] %*% A[seq_len(min(nsrc, 6)), ] + (if (wide) matrix(rnorm(n * p, 0, 0.05), n, p) else 0), 4)
  if (!wide) X <- round(S[, 1:p] %*% (matrix(round(runif(p * p, -1, 1), 2), p, p) + diag(p)), 4)
  for (nc in unique(c(2, min(p, if (wide) 4 else p)))) for (fn in 0:2) {
    a <- c(n, p, nc, fn, 1, 200, 1e-8, as.vector(t(X)))
    for (alg in (if (wide) c("par", "def") else "def")) {
      r <- tryCatch(suppressWarnings(icafast(X, nc, fun = funs2[fn + 1], alg = alg, maxit = 200, tol = 1e-8)), error = function(e) NULL)
      if (is.null(r) || length(r$vafs) != nc) next
      pre <- if (!wide) "d" else if (alg == "par") "w" else "x"
      if (r$converged && all(r$iter < 200)) for (i in seq_len(nc)) add(paste0(pre, "vafs"), c(a, i - 1), r$vafs[i])
      add(paste0(pre, "iter"), a, sum(r$iter)); add(paste0(pre, "conv"), a, as.numeric(r$converged))
      if (alg == "def") for (i in seq_len(nc)) add(paste0(pre, "iterj"), c(a, i - 1), r$iter[i])
      rec <- as.vector(t(r$S %*% t(r$M))); w <- seq_along(rec)
      add(paste0(pre, "recon"), c(a, 0), sum(rec)); add(paste0(pre, "recon"), c(a, 1), sum(w * rec)); add(paste0(pre, "recon"), c(a, 2), sum(rec^2))
    }
  }
}
emit("ica", "ica", list(cases))
