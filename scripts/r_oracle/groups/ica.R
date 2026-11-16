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
emit("ica", "ica", list(cases))
